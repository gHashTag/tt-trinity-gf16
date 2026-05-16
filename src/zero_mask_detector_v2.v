// SPDX-License-Identifier: Apache-2.0
// =============================================================================
// Module: zero_mask_detector_v2
// File:   src/zero_mask_detector_v2.v
// Part of L-S16 Sparse PE v2 — gHashTag/tt-trinity-gf16
//
// Description:
//   Zero-detects 4 GF16 operand pairs (8 × 16-bit words).
//   Each GF16 word is zero when [14:0] == 15'h0 (sign bit irrelevant, matches
//   is_zero_a/is_zero_b convention in gf16_mul.v).
//
//   Per-lane skip_mask[k] = 1 when EITHER a[k] OR b[k] is zero (no MAC needed).
//   all_zero = 1 when ALL 4 lanes would be skipped.
//   skip_cnt[3:0] = popcount of skip_mask (0..4).
//
//   XOR-tree implementation per lane:
//     zero_a[k] = ~|a[k][14:0]  → 1 XOR-reduce of 15 bits ≈ 4 gate levels, ~7 cells
//     zero_b[k] = ~|b[k][14:0]  → same
//     skip[k]   = zero_a[k] | zero_b[k]
//   Total 4 lanes: ~4×(7+7+1) = ~60 cells + popcount tree ~20 cells ≈ 80 cells.
//
// Constraints:
//   R-SI-1: zero new `*` operator.
//   Pure Verilog-2005. No SystemVerilog.
//
// Anchor: phi^2 + phi^-2 = 3 (DOI: 10.5281/zenodo.19227877)
// =============================================================================

`default_nettype none

module zero_mask_detector_v2 (
    // Activation operands (a) and weight operands (b) — 4 lanes of GF16 (16-bit)
    input  wire [15:0] a0,
    input  wire [15:0] a1,
    input  wire [15:0] a2,
    input  wire [15:0] a3,
    input  wire [15:0] b0,
    input  wire [15:0] b1,
    input  wire [15:0] b2,
    input  wire [15:0] b3,

    // Per-lane skip: skip_mask[k]=1 means lane k can be bypassed (one operand is zero)
    output wire [3:0]  skip_mask,

    // Aggregate signals
    output wire        all_zero,    // 1 = all 4 lanes skippable → full MAC skip
    output wire [3:0]  skip_cnt     // popcount of skip_mask (0..4, 3 bits needed but 4 provided)
);

    // -------------------------------------------------------------------------
    // Zero detection per operand: GF16 zero iff [14:0] == 15'h0
    // Using NOR reduction (OR-reduce then invert) — XOR-tree equivalent.
    // Each: ~15-input OR ≈ 4 gate levels, 7 cells (NAND-AOI reduction)
    // -------------------------------------------------------------------------
    wire az0 = (a0[14:0] == 15'h0);
    wire az1 = (a1[14:0] == 15'h0);
    wire az2 = (a2[14:0] == 15'h0);
    wire az3 = (a3[14:0] == 15'h0);

    wire bz0 = (b0[14:0] == 15'h0);
    wire bz1 = (b1[14:0] == 15'h0);
    wire bz2 = (b2[14:0] == 15'h0);
    wire bz3 = (b3[14:0] == 15'h0);

    // -------------------------------------------------------------------------
    // Per-lane skip: skip if EITHER operand is zero
    // (a×0 = 0×b = 0 — no partial product, no carry chain)
    // -------------------------------------------------------------------------
    assign skip_mask[0] = az0 | bz0;
    assign skip_mask[1] = az1 | bz1;
    assign skip_mask[2] = az2 | bz2;
    assign skip_mask[3] = az3 | bz3;

    // -------------------------------------------------------------------------
    // all_zero: all 4 lanes skippable → full zero-skip of the dot product
    // -------------------------------------------------------------------------
    assign all_zero = &skip_mask;

    // -------------------------------------------------------------------------
    // 4-input popcount (skip_cnt): adder tree, pure Verilog-2005
    // Level 0: 2 half-adders → 2 × 2-bit partial sums
    // Level 1: one 2-bit adder → 3-bit (but we output 4 bits for clarity)
    // No `*` — only `+` on 1-bit and 2-bit values.
    // -------------------------------------------------------------------------
    wire [1:0] ha0_s;
    wire [1:0] ha1_s;
    assign ha0_s = {1'b0, skip_mask[0]} + {1'b0, skip_mask[1]};
    assign ha1_s = {1'b0, skip_mask[2]} + {1'b0, skip_mask[3]};

    assign skip_cnt = {1'b0, ha0_s} + {1'b0, ha1_s};

endmodule
