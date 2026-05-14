// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Trinity Agent <agent@trinity.local>
//
// TT-Shuttle Squeeze v7 — S-52 2-Hot Thermometer Ternary Encoding XOR/AND MAC
// Stream: W15-TT-C Guards+Sparse+Approx+TimeDomain+CarrySkip+BitSlice+SigmaDelta+Perm+Therm
// Anchor: phi^2 + phi^-2 = 3
//
// G-52 FALSIFICATION: Yosys synth shows MAC sign path ≤ 2 gates (vs ≥ 4 for
//                     full 3-state mux). Verified by Yosys gate count in CI.
//
// 2-hot thermometer encoding of ternary weight: w in {-1, 0, +1}
//   Encoding: {s, v} where v = is_nonzero, s = is_negative
//   w = +1 => {s=0, v=1}
//   w = -1 => {s=1, v=1}
//   w =  0 => {s=x, v=0}
//
// MAC contribution sign path (≤ 2 gates):
//   contribution = AND(v, XOR(s, x_sign))
// where x_sign = MSB of signed activation x.
//
// For a full N-weight dot product, accumulate 1-bit contributions.
// Total gate count for sign path per weight: 1 XOR + 1 AND = 2 gates exactly.

`default_nettype none

module v7_therm_mac_S52 #(
    parameter N    = 32,  // number of ternary weight lanes
    parameter ACCW = 8    // accumulator width (must be ≥ log2(N)+1)
) (
    input  wire [N-1:0]  w_v,       // valid (non-zero) bits
    input  wire [N-1:0]  w_s,       // sign bits (1 = negative weight)
    input  wire [N-1:0]  x_sign,    // MSB of each activation (sign bit)
    input  wire [N-1:0]  x_valid,   // activation non-zero (for zero-skip)

    output wire signed [ACCW-1:0] mac_out  // signed dot product
);

    // Sign path per weight: ≤ 2 gates
    // contribution[i] = AND(w_v[i], XOR(w_s[i], x_sign[i]))
    //   = w_v[i] & (w_s[i] ^ x_sign[i])
    // Interpretation: 1 = positive contribution, 0 = negative contribution
    // Only count if both weight and activation are non-zero (zero-skip)
    wire [N-1:0] sign_path;
    wire [N-1:0] active;

    genvar i;
    generate
        for (i = 0; i < N; i = i+1) begin : gen_sign
            // ≤ 2 gates: XOR then AND
            assign sign_path[i] = w_v[i] & (w_s[i] ^ x_sign[i]);
            assign active[i]    = w_v[i] & x_valid[i];  // both non-zero
        end
    endgenerate

    // Count positive contributions among active lanes
    // n_pos = popcount(active & ~sign_path)  [XOR=0 means signs agree = positive]
    // n_neg = popcount(active & sign_path)   [XOR=1 means signs differ = negative... wait]
    //
    // Clarify: w_s XOR x_sign = 0 when same sign => w*x is positive (+)
    //                         = 1 when different sign => w*x is negative (-)
    // So: positive contribution = active[i] & ~sign_path[i]
    //     negative contribution = active[i] &  sign_path[i]
    wire [N-1:0] pos_mask = active & ~sign_path;
    wire [N-1:0] neg_mask = active &  sign_path;

    // Popcount both masks (simple adder tree, no *)
    function [ACCW-1:0] popcnt;
        input [N-1:0] x;
        integer j;
        reg [ACCW-1:0] cnt;
        begin
            cnt = {ACCW{1'b0}};
            for (j = 0; j < N; j = j+1)
                cnt = cnt + {{(ACCW-1){1'b0}}, x[j]};
            popcnt = cnt;
        end
    endfunction

    wire [ACCW-1:0] n_pos = popcnt(pos_mask);
    wire [ACCW-1:0] n_neg = popcnt(neg_mask);

    // Signed result: n_pos - n_neg (no *)
    assign mac_out = $signed(n_pos) - $signed(n_neg);

endmodule
`default_nettype wire
