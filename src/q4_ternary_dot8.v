`default_nettype none
// q4_ternary_dot8.v — L-S35 Hybrid Q4 × Ternary 8-wide dot product
// Apache-2.0 · TRI-1 v2 · PhD Ch.attention/Q4-T1.58 anchor
//
// Computes sum_{i=0..7} w[i] * act[i] where:
//   w[i] is signed Q4 in [-8, +7]   (4 bits, 2's-complement)
//   act[i] is ternary in {-1, 0, +1} encoded as 2-bit: 00=0, 01=+1, 10=-1
//
// No `*` multiplier — uses sign-flip + zero-mask + saturating adder tree.
// Yosys ABCs to LUTs without DSP (R-SI-1 compliant).
//
// Bit-exactness: output matches reference C:
//   int8_t y = sat8( sum_{i} (act[i]==+1 ? +w[i] : act[i]==-1 ? -w[i] : 0) )
//
// Latency: 1 clock cycle (register on output, combinational datapath).
// EPIC: gHashTag/trinity-fpga#52
// SPDX-License-Identifier: Apache-2.0

module q4_ternary_dot8 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] w_q4,          // 8 × 4-bit signed  w[i] = w_q4[4*i+3:4*i]
    input  wire [15:0] act_trits,     // 8 × 2-bit ternary act[i] = act_trits[2*i+1:2*i]
    input  wire        valid_in,
    output reg  signed [7:0] dot_out, // 8-bit signed saturated result
    output reg         valid_out,
    output reg         saturated      // 1 if accumulator was clipped
);

    // -------------------------------------------------------------------------
    // Lane sign-flip / zero-mask
    // Each lane produces a 5-bit signed partial:
    //   act==01 (+1) → +w[i]  (sign-extend Q4 to 5 bits)
    //   act==10 (-1) → -w[i]  (negate)
    //   act==00 (0)  → 0
    //   act==11 (reserved) → 0
    // Q4 is 4-bit 2's-complement in [-8,+7]; sign-extend to 5 bits → [-8,+7] still fits,
    // negation of -8 → +8 which requires 5 bits (01000).
    // -------------------------------------------------------------------------

    wire signed [4:0] partial [0:7];

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : lane
            wire [1:0] act = act_trits[2*i+1 : 2*i];
            wire signed [3:0] w  = $signed(w_q4[4*i+3 : 4*i]);
            wire signed [4:0] w5 = {{1{w[3]}}, w};   // sign-extend to 5 bits

            // -w5: negate. For w5 = -8 (5'b11000), -w5 = +8 (5'b01000) — fits 5 bits.
            wire signed [4:0] neg_w5 = -w5;

            assign partial[i] = (act == 2'b01) ? w5 :
                                 (act == 2'b10) ? neg_w5 :
                                                  5'sb0;
        end
    endgenerate

    // -------------------------------------------------------------------------
    // 3-stage adder tree (8 inputs → 4 → 2 → 1)
    // Widths grow to avoid overflow:
    //   Stage 0: 5-bit + 5-bit → 6-bit (max ±8+±8 = ±16, fits 6-bit signed)
    //   Stage 1: 6-bit + 6-bit → 7-bit (max ±32, fits 7-bit signed)
    //   Stage 2: 7-bit + 7-bit → 8-bit (max ±64, fits 8-bit signed)
    // But actual max |sum| = 8×8 = 64, fits in 7-bit signed (range -64..+63)?
    // No: 7-bit signed = [-64, +63]; +64 overflows. So use 8-bit for stage 2 result
    // to hold the full range [-64, +56] before saturation to [-128,+127].
    // -------------------------------------------------------------------------

    // Stage 0: pairs (0,1), (2,3), (4,5), (6,7)
    wire signed [5:0] s0_0 = {partial[0][4], partial[0]} + {partial[1][4], partial[1]};
    wire signed [5:0] s0_1 = {partial[2][4], partial[2]} + {partial[3][4], partial[3]};
    wire signed [5:0] s0_2 = {partial[4][4], partial[4]} + {partial[5][4], partial[5]};
    wire signed [5:0] s0_3 = {partial[6][4], partial[6]} + {partial[7][4], partial[7]};

    // Stage 1: pairs (s0_0,s0_1), (s0_2,s0_3)
    wire signed [6:0] s1_0 = {s0_0[5], s0_0} + {s0_1[5], s0_1};
    wire signed [6:0] s1_1 = {s0_2[5], s0_2} + {s0_3[5], s0_3};

    // Stage 2: final sum — use 8-bit to capture full range
    wire signed [7:0] s2   = {s1_0[6], s1_0} + {s1_1[6], s1_1};

    // -------------------------------------------------------------------------
    // Saturation to 8-bit signed [-128, +127]
    // s2 is already 8-bit signed, so no overflow can occur here.
    // The maximum magnitude is 8 * 8 = 64 which fits in 8-bit signed [-128,+127].
    // However the spec says "saturating" — we keep the sat flag for transparency.
    // -------------------------------------------------------------------------
    wire signed [8:0] sum_wide = {s2[7], s2};  // extend for sat check (unused here)
    wire               sat_pos = 1'b0;  // 64 < 127, no positive saturation possible
    wire               sat_neg = 1'b0;  // -64 > -128, no negative saturation possible

    // -------------------------------------------------------------------------
    // Output register
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dot_out   <= 8'sd0;
            valid_out <= 1'b0;
            saturated <= 1'b0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                dot_out   <= s2;
                saturated <= sat_pos | sat_neg;
            end
        end
    end

endmodule
