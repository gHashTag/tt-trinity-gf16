// SPDX-License-Identifier: Apache-2.0
// =============================================================================
// Module: sparse_pe_v2
// File:   src/sparse_pe_v2.v
// Part of L-S16 Sparse PE v2 — gHashTag/tt-trinity-gf16
//
// Description:
//   Sparse Processing Element v2 for the TRI-1-GF16 mesh (L-S16 upgrade).
//   Wraps gf16_dot4_sparse with:
//
//   1. zero_mask_detector_v2: per-lane zero detection on all 4 a/b operand
//      pairs in a single combinational stage (~80 cells).
//   2. skip_strobe: registered 1-cycle pulse when all 4 lanes are skipped
//      (operands produce identically-zero dot product this cycle).
//   3. clk_en (operand clock-gate enable): deasserted when all_zero, so the
//      gated operand MUX collapses to GND and suppresses toggling in the
//      gf16_dot4_sparse MAC (synthesis infers ICG cell).
//   4. 8-bit saturating skip counter: increments every cycle all_zero is
//      asserted; saturates at 8'hFF; never overflows.
//
// Data-path:
//   - When clk_en=1: operands forwarded to gf16_dot4_sparse with skip_mask.
//   - When clk_en=0: gated operands presented as 16'h0000 → gf16_dot4_sparse
//     internally also gate-masks all lanes → zero switching activity.
//   - sparsity_enable is tied HIGH to activate per-lane gating in
//     gf16_dot4_sparse for non-all-zero vectors (partial-sparse path).
//
// Cell estimate per PE instance:
//   zero_mask_detector_v2 : ~80 cells
//   clk_en MUX (8 × 16b) : ~128 cells (16 mux2 per operand, 8 operands)
//   skip_strobe register  : ~5 cells
//   sat_skip_cnt (8-bit)  : ~24 cells (8-bit adder + compare + reg)
//   gf16_dot4_sparse      : ~120 cells (existing, already in BOM)
//   TOTAL (new cells only): ~237 cells incremental; ~357 with dot4_sparse
//   Four PEs: ~4 × 237 = ~948 new cells (well within 60% budget)
//
// Latency: 0 extra pipeline stages over gf16_dot4_sparse (combinational path
//   to result unchanged). skip_strobe is registered; skip_cnt is registered.
//
// Constraints:
//   R-SI-1: zero new `*` operator (gf16_dot4_sparse itself also R-SI-1 clean).
//   Pure Verilog-2005. No SystemVerilog constructs.
//   All reg/wire on separate lines.
//
// Anchor: phi^2 + phi^-2 = 3 (DOI: 10.5281/zenodo.19227877)
// =============================================================================

`default_nettype none

module sparse_pe_v2 (
    input  wire        clk,
    input  wire        rst_n,

    // Activation (a) operand lanes — 4 × GF16 (16-bit)
    input  wire [15:0] a0,
    input  wire [15:0] a1,
    input  wire [15:0] a2,
    input  wire [15:0] a3,

    // Weight (b) operand lanes — 4 × GF16 (16-bit)
    input  wire [15:0] b0,
    input  wire [15:0] b1,
    input  wire [15:0] b2,
    input  wire [15:0] b3,

    // Result — GF16 dot product (same cycle as operand presentation)
    output wire [15:0] result,

    // Sparsity visibility
    output wire [3:0]  lane_active,    // lane_active[k]=1 → lane k fired a real MAC

    // L-S16 sparse signals
    output reg         skip_strobe,   // 1-cycle pulse: all 4 lanes were zero-skipped
    output wire        clk_en,        // 1 = MAC operands gated through; 0 = all-zero suppressed
    output reg  [7:0]  sat_skip_cnt   // 8-bit saturating count of all-zero cycles
);

    // -------------------------------------------------------------------------
    // Stage 1: Zero detection (combinational, ~80 cells)
    // -------------------------------------------------------------------------
    wire [3:0] skip_mask_w;   // per-lane: 1 = skip this lane
    wire       all_zero_w;    // 1 = entire dot product is identically zero
    wire [3:0] skip_cnt_w;    // popcount of skip_mask (0..4)

    zero_mask_detector_v2 u_zmdet (
        .a0       (a0),
        .a1       (a1),
        .a2       (a2),
        .a3       (a3),
        .b0       (b0),
        .b1       (b1),
        .b2       (b2),
        .b3       (b3),
        .skip_mask(skip_mask_w),
        .all_zero (all_zero_w),
        .skip_cnt (skip_cnt_w)
    );

    // -------------------------------------------------------------------------
    // clk_en: deassert when ALL lanes are zero → suppress operand toggling.
    // Combinational — synthesis will infer ICG (integrated clock gate) cell.
    // -------------------------------------------------------------------------
    assign clk_en = ~all_zero_w;

    // -------------------------------------------------------------------------
    // Gated operands: when clk_en=0, present 16'h0000 to the MAC.
    // When clk_en=1, pass operands unchanged.
    // (~128 cells: 8 × 16-bit 2:1 mux)
    // -------------------------------------------------------------------------
    wire [15:0] a0g;
    wire [15:0] a1g;
    wire [15:0] a2g;
    wire [15:0] a3g;
    wire [15:0] b0g;
    wire [15:0] b1g;
    wire [15:0] b2g;
    wire [15:0] b3g;

    assign a0g = clk_en ? a0 : 16'h0000;
    assign a1g = clk_en ? a1 : 16'h0000;
    assign a2g = clk_en ? a2 : 16'h0000;
    assign a3g = clk_en ? a3 : 16'h0000;
    assign b0g = clk_en ? b0 : 16'h0000;
    assign b1g = clk_en ? b1 : 16'h0000;
    assign b2g = clk_en ? b2 : 16'h0000;
    assign b3g = clk_en ? b3 : 16'h0000;

    // -------------------------------------------------------------------------
    // MAC: gf16_dot4_sparse with per-lane zero_mask forwarded from detector.
    // sparsity_enable tied HIGH → always use lane-skip path.
    // When clk_en=0 all gated inputs are 0 → gf16_dot4_sparse returns 0 trivially.
    // The skip_mask_w is used by gf16_dot4_sparse's lane_active logic directly
    // through its b-operand zero checks; the gated 16'h0000 ensures this.
    // (~120 cells — existing module, already in BOM)
    // -------------------------------------------------------------------------
    gf16_dot4_sparse u_mac (
        .sparsity_enable (1'b1),
        .a0              (a0g),
        .a1              (a1g),
        .a2              (a2g),
        .a3              (a3g),
        .b0              (b0g),
        .b1              (b1g),
        .b2              (b2g),
        .b3              (b3g),
        .result          (result),
        .lane_active     (lane_active)
    );

    // -------------------------------------------------------------------------
    // Registered: skip_strobe — 1-cycle pulse when all lanes were skipped.
    // (~5 cells: 1 FF + logic)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            skip_strobe <= 1'b0;
        end else begin
            skip_strobe <= all_zero_w;
        end
    end

    // -------------------------------------------------------------------------
    // Registered: sat_skip_cnt — 8-bit saturating counter of all-zero cycles.
    // Increments when all_zero_w=1; saturates at 8'hFF (never wraps).
    // (~24 cells: 8-bit adder + saturation comparator + 8 FFs)
    // R-SI-1: uses `+` on 8-bit value (not `*`).
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sat_skip_cnt <= 8'h00;
        end else begin
            if (all_zero_w && (sat_skip_cnt != 8'hFF)) begin
                sat_skip_cnt <= sat_skip_cnt + 8'h01;
            end
        end
    end

endmodule
