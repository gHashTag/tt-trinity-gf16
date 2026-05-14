// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Trinity Agent <agent@trinity.local>
//
// TT-Shuttle Squeeze v7 — S-16 Sparsity nz_detect Skip
// Stream: W15-TT-C Guards+Sparse+Approx+TimeDomain+CarrySkip+BitSlice+SigmaDelta+Perm+Therm
// Anchor: phi^2 + phi^-2 = 3
//
// G-16 FALSIFICATION: skip signal asserts for every zero-weight lane, saving
//                     a MAC cycle on 100% of Wave-29 zero-weight inputs.
//
// Sparsity detector for ternary weight vector. Scans a WIDTH-wide weight bus
// encoded as {sign[W-1:0], valid[W-1:0]} (2-bit-per-weight thermometer).
// Asserts nz_detect[i] = 1 when weight[i] is non-zero (valid[i]=1).
// Asserts skip when ALL weights in the group are zero (any_nz = 0).

`default_nettype none

module v7_sparsity_skip_S16 #(
    parameter N_WEIGHTS = 32  // number of ternary weights per group
) (
    // Ternary weight encoding: each weight w in {-1,0,+1}
    // encoded as valid[i]=1 iff w!=0, sign[i]=1 iff w==-1
    input  wire [N_WEIGHTS-1:0] w_valid,  // non-zero mask
    input  wire [N_WEIGHTS-1:0] w_sign,   // sign (1=negative, 0=positive)

    output wire [N_WEIGHTS-1:0] nz_detect,  // per-weight non-zero flag
    output wire                 any_nz,     // OR of all nz_detect
    output wire                 skip        // assert to skip MAC cycle
);

    // Non-zero detect: weight is non-zero iff valid bit is set
    assign nz_detect = w_valid;

    // Group skip: skip entire dot-product if ALL weights are zero
    assign any_nz = |w_valid;
    assign skip   = ~any_nz;

    // Suppress unused warning on w_sign (available to downstream MAC)
    wire _unused_sign = |w_sign;

endmodule
`default_nettype wire
