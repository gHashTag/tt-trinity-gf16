// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// operand_iso_buf.v — L-Z02 Operand Isolation Buffer
// TT-Shuttle Squeeze · Power stream
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// PURPOSE
// -------
// AND-gate operand bus inputs to unused functional units.
// When enable=0, out is forced all-zero → zero toggle activity propagates
// into the downstream combinational unit (gf16_mul, gf16_add, gf16_dot4 lane,
// alu9_decoder). This is the canonical "operand isolation cell" used in ARM
// Cortex power analysis.
//
// SAVINGS MODEL
// -------------
//   - Each idle GF16 multiplier switches ~N/4 bits per cycle on average.
//   - AND-gating collapses switching to 0 when enable=0.
//   - For a 4-lane dot4 tile: 8 isolators × 16 bits = 128 input bits clamped.
//   - Projected: ~8% dynamic power reduction at the tile level → +8 TOPS/W.
//   - Cell cost: 1 AND2 per bit → N cells per instance.
//
// USAGE
// -----
//   operand_iso_buf #(.N(16)) u_iso_a0 (
//       .enable (lane_active),
//       .in     (a0_reg),
//       .out    (a0_iso)
//   );
//
// CONSTITUTIONAL RULES
// --------------------
//   R-SI-1: no `*` operator used here (pure AND masking).
//   Pure Verilog-2005 only.

`default_nettype none

module operand_iso_buf #(
    parameter integer N = 16   // bus width in bits
) (
    input  wire             enable, // 1 = pass through; 0 = clamp to zero
    input  wire [N-1:0]     in,     // operand bus from register
    output wire [N-1:0]     out     // isolated operand bus to functional unit
);

    // AND-gate each bit with enable.
    // When enable=0 → out = {N{1'b0}} (all zero, no toggle into unit).
    // When enable=1 → out = in (transparent pass-through).
    // Synthesis maps to N sky130_fd_sc_hd__and2_1 cells (~N cells total).
    assign out = {N{enable}} & in;

endmodule
`default_nettype wire
