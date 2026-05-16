// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// clk_gate_cell.v — S-14 Clock Gating: Standard ICG cell wrapper
// Trinity TRI-1 · tt-trinity-gf16 · feat/tt-v7-power stream
//
// Constitutional: R-SI-1 (zero standalone * operators) ✓
// Language:       Verilog-2005 — no SystemVerilog constructs ✓
// Anchor:         φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// Description:
//   Implements a glitch-free ICG (Integrated Clock Gate) cell following the
//   sky130_fd_sc_hd__dlclkp_1 topology:
//     - D-latch transparent when CLK=0 (negedge phase), captures GATE input.
//     - Output: GCLK = latch_q & CLK  (AND gate — glitch-free)
//
//   OpenLane/Yosys synthesis intent: the always @(*) latch construct with
//   the level-sensitive enable on !clk maps directly to sky130_fd_sc_hd__dlclkp_1
//   during technology mapping. In production tape-out the latch is inferred
//   as a hard macro; in simulation the behavioural model is used.
//
//   No `*` operator used anywhere. Named-port instantiation style.
//
// Interface:
//   clk       — ungated system clock
//   gate_en   — enable from cg_activity_monitor (1 = allow clock through)
//   clk_gated — glitch-free gated clock output to downstream FFs
//
// Cell count: 1× D-latch + 1× AND2 ≈ 2 cells per instance.
// 4 instances (one per gated block) = ~8 cells.

`timescale 1ns/1ps
`default_nettype none

module clk_gate_cell (
    input  wire clk,        // ungated system clock
    input  wire gate_en,    // ICG enable from cg_activity_monitor
    output wire clk_gated   // glitch-free gated clock
);

    // D-latch: transparent when CLK=0
    // Captures gate_en at the falling edge (negedge) of clk.
    // When CLK goes high, latch holds the captured value — prevents glitch.
    //
    // OpenLane synthesis note: this construct is the canonical latch form
    // that Yosys maps to sky130_fd_sc_hd__dlclkp_1 (GATE=gate_en, CLK=clk,
    // GCLK=clk_gated). The dlclkp_1 cell internally is:
    //   GCLK = GATE_latched & CLK
    // which is exactly what we model here.
    reg latch_q;

    // Level-sensitive latch: transparent when clk=0
    always @(*) begin : icg_latch
        if (!clk)
            latch_q = gate_en;
    end

    // AND gate: gated clock is clean (latch_q stable while CLK=1)
    assign clk_gated = latch_q & clk;

endmodule

`default_nettype wire
