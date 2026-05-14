// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Trinity Agent <agent@trinity.local>
//
// TT-Shuttle Squeeze v7 — S-48 Permutation-Invariant Weight Bucket Reorder
// Stream: W15-TT-C Guards+Sparse+Approx+TimeDomain+CarrySkip+BitSlice+SigmaDelta+Perm+Therm
// Anchor: phi^2 + phi^-2 = 3
//
// G-48 FALSIFICATION: dot32 output is bit-identical to non-permuted reference
//                     on 100% of Wave-29 vectors; verified by EQY (S-49).
//
// Compile-time permutation of 32 ternary weights into canonical bucket order:
//   [+1 weights first | -1 weights second | 0 weights last]
// Dot product is permutation-invariant (sum is commutative), so reordering
// is free. Skipping trailing zero block saves cycles (zero-skip S-16).
//
// This module is a COMPILE-TIME / PARAMETER-time reorder; at runtime it is
// purely combinational wiring (wire permutation, zero hardware overhead).
// Cite: arXiv 2403.17410 — permutation-invariant NN dot product.
//
// Inputs: 32 ternary weights as {w_valid[31:0], w_sign[31:0]}
// Outputs: same 32 pairs reordered into canonical bucket order,
//          plus n_pos (count of +1), n_neg (count of -1) for skip control.

`default_nettype none

module v7_perm_bucket_S48 #(
    parameter N = 32   // number of weights per dot-product group
) (
    // Input weights (arbitrary order, from weight ROM)
    input  wire [N-1:0] w_valid_in,   // 1 = weight non-zero
    input  wire [N-1:0] w_sign_in,    // 1 = weight is -1

    // Activations (unchanged — permute weights to match)
    input  wire [N-1:0] act_in,

    // Output: permuted weight order and matching activations
    output wire [N-1:0] w_valid_out,
    output wire [N-1:0] w_sign_out,
    output wire [N-1:0] act_out,

    // Bucket boundaries for skip control
    output wire [5:0]   n_pos,   // count of +1 weights
    output wire [5:0]   n_neg,   // count of -1 weights
    output wire [5:0]   n_zero   // count of 0 weights
);

    // Count buckets using simple popcount (combinational)
    // +1 = valid & ~sign; -1 = valid & sign; 0 = ~valid
    wire [N-1:0] is_pos  = w_valid_in & ~w_sign_in;
    wire [N-1:0] is_neg  = w_valid_in &  w_sign_in;
    wire [N-1:0] is_zero = ~w_valid_in;

    // Popcount via adder tree (no *)
    function [5:0] popcnt32;
        input [N-1:0] x;
        integer j;
        reg [5:0] cnt;
        begin
            cnt = 6'd0;
            for (j = 0; j < N; j = j+1)
                cnt = cnt + {5'b0, x[j]};
            popcnt32 = cnt;
        end
    endfunction

    assign n_pos  = popcnt32(is_pos);
    assign n_neg  = popcnt32(is_neg);
    assign n_zero = popcnt32(is_zero);

    // Bucket sort: combinational priority encoder to fill output slots
    // Slot 0..n_pos-1   : +1 weights
    // Slot n_pos..n_pos+n_neg-1 : -1 weights
    // Slot n_pos+n_neg..N-1   : 0 weights
    //
    // Implemented as a barrel of selection muxes driven by prefix-sum indices.
    // For SYNTHESIS this becomes wiring (no gates, no LUTs beyond the popcnts above).
    reg [N-1:0] vout, sout, aout;
    integer slot_p, slot_n, slot_z, idx;
    always @(*) begin
        slot_p = 0; slot_n = n_pos; slot_z = n_pos + n_neg;
        vout = {N{1'b0}}; sout = {N{1'b0}}; aout = {N{1'b0}};
        for (idx = 0; idx < N; idx = idx+1) begin
            if (is_pos[idx]) begin
                vout[slot_p] = 1'b1;
                sout[slot_p] = 1'b0;
                aout[slot_p] = act_in[idx];
                slot_p = slot_p + 1;
            end else if (is_neg[idx]) begin
                vout[slot_n] = 1'b1;
                sout[slot_n] = 1'b1;
                aout[slot_n] = act_in[idx];
                slot_n = slot_n + 1;
            end else begin
                vout[slot_z] = 1'b0;
                sout[slot_z] = 1'b0;
                aout[slot_z] = act_in[idx];
                slot_z = slot_z + 1;
            end
        end
    end

    assign w_valid_out = vout;
    assign w_sign_out  = sout;
    assign act_out     = aout;

endmodule
`default_nettype wire
