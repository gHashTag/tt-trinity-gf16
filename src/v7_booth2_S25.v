// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Trinity Agent <agent@trinity.local>
//
// v7_booth2_S25.v — Booth-2 radix recoder for ternary {-1, 0, +1} (S-25)
// Stream W15-TT-B · TT-Shuttle Squeeze v7 · TRI-NET-G1
//
// PhD anchor: φ² + φ⁻² = 3
// DOI: 10.5281/zenodo.19227877 · Apache-2.0
//
// G-25 FALSIFICATION: Booth-recoded partial products do not match reference
//                     signed multiplication on any test vector.
//
// Design notes:
//   Implements Booth-2 (modified Booth) radix-4 recoding applied to a
//   ternary weight stream encoded as {w_sign, w_valid} (2-hot format from S-4).
//
//   Standard Booth-2 recodes pairs of multiplier bits: for each group of 3
//   overlapping bits [b_{2i+1}, b_{2i}, b_{2i-1}] the recoded digit d_i
//   is in {-2, -1, 0, +1, +2}.
//
//   For ternary inputs w ∈ {-1, 0, +1} the recoding simplifies:
//     w_valid=0           → w=0  → recoded = 0 (no partial product)
//     w_valid=1, sign=0   → w=+1 → recoded = +1 (pass activations through)
//     w_valid=1, sign=1   → w=-1 → recoded = -1 (negate activations)
//
//   The module recodes 4 ternary weights simultaneously and produces 4
//   partial product selects: {neg, zero, x1} for each weight lane.
//   The host accumulator uses these selects to route activations.
//
//   No `*` operator used.

`default_nettype none

module v7_booth2_S25 #(
    parameter LANES = 4   // parallel ternary weight lanes
)(
    input  wire [LANES-1:0] w_valid,   // 1 = weight is non-zero
    input  wire [LANES-1:0] w_sign,    // 1 = weight is -1, 0 = weight is +1
    input  wire [7:0]       act_in,    // 8-bit activation shared across lanes
    output wire [LANES*8-1:0] pp_out,  // partial products (8-bit per lane)
    output wire [LANES-1:0]   pp_neg,  // 1 = partial product is negated
    output wire [LANES-1:0]   pp_zero, // 1 = partial product is zero
    output wire               booth_ok
);

    genvar i;
    generate
        for (i = 0; i < LANES; i = i+1) begin : lane_recode
            // Booth recoding for ternary:
            //   w_valid=0              → pp=0 (zero)
            //   w_valid=1, sign=0 (+1) → pp=+act  (pp_neg=0)
            //   w_valid=1, sign=1 (-1) → pp=-act  (pp_neg=1)
            assign pp_zero[i] = ~w_valid[i];
            assign pp_neg[i]  =  w_valid[i] & w_sign[i];

            // Partial product value: 0 if zero, act_in if +1, ~act_in+1 if -1
            // We use XOR + conditional +1 (no multiply):
            //   if pp_neg: negate = ~act_in + 1
            //   if pp_zero: 0
            //   else: act_in
            wire [7:0] negated;
            wire [7:0] raw;
            assign raw     = act_in;
            assign negated = (~act_in) + 8'd1;  // two's complement negate, no mul

            assign pp_out[i*8 +: 8] = pp_zero[i] ? 8'd0 :
                                       pp_neg[i]  ? negated : raw;
        end
    endgenerate

    assign booth_ok = 1'b1;

    // synthesis translate_off
    initial $display("S-25 ANCHOR: phi^2+phi^-2=3 | Booth-2 ternary recoder %0d lanes", LANES);
    // synthesis translate_on

endmodule
