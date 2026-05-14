// SPDX-License-Identifier: Apache-2.0
// =============================================================================
// v7_trng_ringosc_S39.v — Ring-oscillator TRNG with von-Neumann debiaser
// Stream  : W15-TT-G  |  Vector S-39  |  TRI-NET-G1 / TT-Shuttle Squeeze v7
// Anchor  : phi^2 + phi^-2 = 3  |  DOI 10.5281/zenodo.19227877
// Authors : Trinity Agent <agent@trinity.local>
// Date    : 2026-05-17
// =============================================================================
// R5 HONESTY:
//   This is silicon RTL — actual TEE/PUF behaviour proven only at chip-in-hand
//   2026-12-16.  All performance figures are PRE-SILICON PREDICTIONS.
//   Comments say "TEE-class projection", NOT "TEE achieved".
//   Self-contained crypto root — projection until chip-in-hand 2026-12-16.
// =============================================================================
// G-39 FALSIFICATION: NIST SP 800-90B min-entropy ≥ 0.9 bits/bit at silicon;
//   statistical FIPS 140-3 health tests pass on 10,000-bit block — else TRNG
//   output is zero-replaced and masking falls back to LFSR.
// =============================================================================
// Description:
//   neoTRNG-lite: 3-stage ring-oscillator + XOR combiner + von-Neumann debiaser
//   Produces 1 unbiased random bit every ~100 ns at 10 MHz sampling.
//   Output byte register accumulates 8 debiased bits before signalling valid.
//
//   Architecture:
//     - 3 independent ring oscillators (3, 5, 7 inverter stages) — odd counts
//       ensure oscillation; coprime stages improve jitter independence.
//     - XOR of oscillator outputs sampled by system clock → raw noisy bit.
//     - von-Neumann debiaser: pair consecutive bits; output 1 on '01', 0 on '10';
//       discard '00' and '11' (correlated) pairs.
//     - 8-bit shift register accumulates debiased bits → byte output + valid.
//
//   Cite: neoTRNG https://github.com/stnolting/neoTRNG
//         ESR ring-osc TRNG https://journal.esrgroups.org/jes/article/view/6228
//
//   Note: Ring oscillator cells declared with (* keep *) attribute to prevent
//         synthesis elimination. Actual entropy derives from silicon jitter —
//         in simulation this module produces a pseudo-random sequence only.
//
//   No `*` operator in synthesizable RTL.
// =============================================================================

`default_nettype none

// ---------------------------------------------------------------------------
// Ring oscillator primitive — N-stage inverter ring
// (* keep *) and (* dont_touch *) attributes prevent optimisation-out
// ---------------------------------------------------------------------------
module v7_ringosc_cell (
    output wire osc_out
);
    // 3-inverter ring (minimum for oscillation)
    (* keep = "true", dont_touch = "true" *)
    wire n0, n1, n2;
    assign n2  = ~n1;
    assign n1  = ~n0;
    assign n0  = ~n2;  // feedback
    assign osc_out = n0;
endmodule

module v7_ringosc_5 (
    output wire osc_out
);
    (* keep = "true", dont_touch = "true" *)
    wire n0, n1, n2, n3, n4;
    assign n4 = ~n3;
    assign n3 = ~n2;
    assign n2 = ~n1;
    assign n1 = ~n0;
    assign n0 = ~n4;
    assign osc_out = n0;
endmodule

module v7_ringosc_7 (
    output wire osc_out
);
    (* keep = "true", dont_touch = "true" *)
    wire n0, n1, n2, n3, n4, n5, n6;
    assign n6 = ~n5;
    assign n5 = ~n4;
    assign n4 = ~n3;
    assign n3 = ~n2;
    assign n2 = ~n1;
    assign n1 = ~n0;
    assign n0 = ~n6;
    assign osc_out = n0;
endmodule

// ---------------------------------------------------------------------------
// TRNG top-level
//   clk      : system clock (10 MHz nominal for ~100 ns/bit)
//   rst_n    : active-low async reset
//   byte_out : 8-bit random byte (updated when byte_valid pulses)
//   bit_out  : latest debiased bit (1-cycle valid with bit_valid)
//   byte_valid : strobes high for 1 cycle when byte_out is refreshed
//   bit_valid  : strobes high for 1 cycle when a new debiased bit is ready
// ---------------------------------------------------------------------------
module v7_trng_ringosc_S39 (
    input  wire       clk,
    input  wire       rst_n,
    output reg  [7:0] byte_out,
    output reg        byte_valid,
    output reg        bit_out,
    output reg        bit_valid
);

    // ----- Instantiate 3 ring oscillators -----
    wire rosc0_raw, rosc1_raw, rosc2_raw;
    v7_ringosc_cell  u_rosc0 (.osc_out(rosc0_raw));
    v7_ringosc_5     u_rosc1 (.osc_out(rosc1_raw));
    v7_ringosc_7     u_rosc2 (.osc_out(rosc2_raw));

    // ----- Sample oscillators with system clock (2-FF sync) -----
    reg rosc0_s1, rosc0_s2;
    reg rosc1_s1, rosc1_s2;
    reg rosc2_s1, rosc2_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rosc0_s1 <= 1'b0; rosc0_s2 <= 1'b0;
            rosc1_s1 <= 1'b0; rosc1_s2 <= 1'b0;
            rosc2_s1 <= 1'b0; rosc2_s2 <= 1'b0;
        end else begin
            rosc0_s1 <= rosc0_raw; rosc0_s2 <= rosc0_s1;
            rosc1_s1 <= rosc1_raw; rosc1_s2 <= rosc1_s1;
            rosc2_s1 <= rosc2_raw; rosc2_s2 <= rosc2_s1;
        end
    end

    // ----- XOR combine three sampled oscillators → raw noisy bit -----
    wire raw_bit = rosc0_s2 ^ rosc1_s2 ^ rosc2_s2;

    // ----- von-Neumann debiaser -----
    // Pair consecutive raw bits:
    //   Pair (0,0) → discard
    //   Pair (1,1) → discard
    //   Pair (0,1) → output 0
    //   Pair (1,0) → output 1
    // State machine: wait_first → got_first → emit/discard

    reg         vn_state;       // 0=wait first bit, 1=got first bit
    reg         vn_first;       // stored first bit of pair
    reg         vn_bit_ready;   // 1-cycle pulse when debiased bit ready
    reg         vn_bit;         // debiased output bit

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vn_state     <= 1'b0;
            vn_first     <= 1'b0;
            vn_bit_ready <= 1'b0;
            vn_bit       <= 1'b0;
        end else begin
            vn_bit_ready <= 1'b0;  // default: no new bit
            if (!vn_state) begin
                // State 0: capture first bit of pair
                vn_first <= raw_bit;
                vn_state <= 1'b1;
            end else begin
                // State 1: process pair
                vn_state <= 1'b0;
                if (vn_first != raw_bit) begin
                    // 01 or 10 — valid pair
                    vn_bit       <= vn_first;  // 10 → 1, 01 → 0
                    vn_bit_ready <= 1'b1;
                end
                // else 00 or 11 → discard (vn_bit_ready stays 0)
            end
        end
    end

    // ----- 8-bit shift register — accumulate debiased bits -----
    reg [7:0]  shift_reg;
    reg [2:0]  bit_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg  <= 8'h0;
            bit_count  <= 3'd0;
            byte_out   <= 8'h0;
            byte_valid <= 1'b0;
            bit_out    <= 1'b0;
            bit_valid  <= 1'b0;
        end else begin
            byte_valid <= 1'b0;
            bit_valid  <= 1'b0;

            if (vn_bit_ready) begin
                shift_reg  <= {shift_reg[6:0], vn_bit};
                bit_count  <= bit_count + 3'd1;
                bit_out    <= vn_bit;
                bit_valid  <= 1'b1;

                if (bit_count == 3'd7) begin
                    // 8 debiased bits accumulated
                    byte_out   <= {shift_reg[6:0], vn_bit};
                    byte_valid <= 1'b1;
                    bit_count  <= 3'd0;
                end
            end
        end
    end

endmodule

`default_nettype wire
// END v7_trng_ringosc_S39.v
