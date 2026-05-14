// SPDX-License-Identifier: Apache-2.0
// Author: Dmitrii Vasilev <admin@t27.ai>
// L-S37: phi-prior on-chip weight quantizer (FP Q1.15 → ternary)
//
// Quantizer rule (φ-prior):
//   |w| >= φ⁻² (12533 Q1.15 = 0x30F4) → sign(w)  → {+1, -1}
//   |w| <  φ⁻²                         → 0
//
// Ternary encoding: 2-bit per lane
//   2'b00 = +1
//   2'b01 =  0
//   2'b10 = -1
//   2'b11 = reserved (unused)
//
// Architecture: pure combinational comparators + 1-cycle pipeline register
// NO `*` / DSP — only comparators and sign extraction
// Pipeline registers annotated (* keep *)(* no_retiming *)
//
// DOI: 10.5281/zenodo.19227877

`default_nettype none

module phi_prior_quantizer #(
    parameter integer N_LANES = 8,
    parameter integer W_BITS  = 16        // Q1.15 signed width
) (
    input  wire                             clk,
    input  wire                             rst_n,
    // FP input: N_LANES × W_BITS signed Q1.15
    input  wire [N_LANES*W_BITS-1:0]        fp_in,
    // Ternary output: N_LANES × 2 bits (00=+1, 01=0, 10=-1)
    output wire [N_LANES*2-1:0]             tern_out
);

    // φ⁻² in Q1.15: 12533 (0x30F5) ; context anchor: 0x30F4=12532 is one below
    // φ² + φ⁻² = 3 ; 2·φ⁻² = 25066
    // Task spec: threshold = 12533 (decimal) — boundary vectors ±12532, ±12533, ±12534
    localparam signed [W_BITS-1:0] PHI_INV_SQ = 16'sd12533;

    // ------------------------------------------------------------------
    // Per-lane combinational logic: 2 comparators + sign extraction
    // ------------------------------------------------------------------
    wire [1:0] comb_out [0:N_LANES-1];

    genvar i;
    generate
        for (i = 0; i < N_LANES; i = i + 1) begin : GEN_LANE
            // Extract the 16-bit signed word for lane i
            wire signed [W_BITS-1:0] w;
            assign w = $signed(fp_in[i*W_BITS +: W_BITS]);

            // Cast to wider type to silence WIDTHTRUNC on comparisons
            wire signed [W_BITS:0] w_wide;
            assign w_wide = {{1{w[W_BITS-1]}}, w};  // sign-extend by 1 bit

            wire signed [W_BITS:0] thr_wide;
            assign thr_wide = {{1{PHI_INV_SQ[W_BITS-1]}}, PHI_INV_SQ};

            // Comparator 1: w >= +PHI_INV_SQ
            wire cmp_pos;
            assign cmp_pos = (w_wide >= thr_wide);

            // Comparator 2: w <= -PHI_INV_SQ (i.e. w_wide <= -thr_wide)
            wire cmp_neg;
            assign cmp_neg = (w_wide <= -thr_wide);

            // Ternary encoding (combinational)
            //   cmp_pos → 2'b00 (+1)
            //   cmp_neg → 2'b10 (-1)
            //   else    → 2'b01  (0)
            assign comb_out[i] = cmp_pos ? 2'b00 :
                                 cmp_neg ? 2'b10 :
                                           2'b01;
        end
    endgenerate

    // ------------------------------------------------------------------
    // 1-cycle pipeline register  (* keep *)(* no_retiming *)
    // ------------------------------------------------------------------
    (* keep *)(* no_retiming *)
    reg [1:0] pipe_reg [0:N_LANES-1];

    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < N_LANES; j = j + 1)
                pipe_reg[j] <= 2'b01;  // reset to 0
        end else begin
            for (j = 0; j < N_LANES; j = j + 1)
                pipe_reg[j] <= comb_out[j];
        end
    end

    // ------------------------------------------------------------------
    // Output assembly
    // ------------------------------------------------------------------
    genvar k;
    generate
        for (k = 0; k < N_LANES; k = k + 1) begin : GEN_OUT
            assign tern_out[k*2 +: 2] = pipe_reg[k];
        end
    endgenerate

endmodule

`default_nettype wire
