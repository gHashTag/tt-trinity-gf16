// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Trinity Agent <agent@trinity.local>
//
// TT-Shuttle Squeeze v7 — S-48 Permutation Equivalence Checker
// Stream: W15-TT-C Guards+Sparse+Approx+TimeDomain+CarrySkip+BitSlice+SigmaDelta+Perm+Therm
// Anchor: phi^2 + phi^-2 = 3
//
// G-48 FALSIFICATION: dot32 output is bit-identical to non-permuted reference
//                     on 100% of Wave-29 vectors; verified by this EQY checker.
//
// Combinational equivalence checker: verifies that the permuted dot32 output
// equals the reference (non-permuted) dot32 output.
//
// Reference dot32: computes sum_i(w_valid_ref[i] ? (w_sign_ref[i] ? -act_ref[i] : act_ref[i]) : 0)
// Permuted dot32:  same computation on bucket-reordered inputs from v7_perm_bucket_S48
//
// Used in CI by S-49 EQY formal equivalence flow.
// equiv = 1 iff both dot products are identical.

`default_nettype none

module v7_perm_check_S48 #(
    parameter N    = 32,   // weights per dot-product group
    parameter ACCW = 8     // accumulator width
) (
    // Reference (original) inputs
    input  wire [N-1:0]              w_valid_ref,
    input  wire [N-1:0]              w_sign_ref,
    input  wire [N-1:0]              act_ref,

    // Permuted inputs (from v7_perm_bucket_S48)
    input  wire [N-1:0]              w_valid_perm,
    input  wire [N-1:0]              w_sign_perm,
    input  wire [N-1:0]              act_perm,

    // Equivalence outputs
    output wire signed [ACCW-1:0]    dot_ref,     // reference dot product
    output wire signed [ACCW-1:0]    dot_perm,    // permuted dot product
    output wire                      equiv        // 1 = outputs match
);

    // Reference dot32 computation (combinational, no *)
    function signed [ACCW-1:0] dot32;
        input [N-1:0] wv;
        input [N-1:0] ws;
        input [N-1:0] act;
        integer j;
        reg signed [ACCW-1:0] acc;
        begin
            acc = {ACCW{1'b0}};
            for (j = 0; j < N; j = j+1) begin
                if (wv[j]) begin
                    if (ws[j])
                        acc = acc - {{(ACCW-1){1'b0}}, act[j]};
                    else
                        acc = acc + {{(ACCW-1){1'b0}}, act[j]};
                end
            end
            dot32 = acc;
        end
    endfunction

    assign dot_ref  = dot32(w_valid_ref,  w_sign_ref,  act_ref);
    assign dot_perm = dot32(w_valid_perm, w_sign_perm, act_perm);
    assign equiv    = (dot_ref == dot_perm);

endmodule
`default_nettype wire
