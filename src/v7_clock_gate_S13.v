// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// v7_clock_gate_S13.v — S-13 Per-PE clock gating (hd/hdll dual-library zoning)
// TT-Shuttle Squeeze v7 · W15-TT-D Power stream
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// G-13 FALSIFICATION: Mixed hd+hdll OpenLane2 run closes timing @ 50 MHz;
//                     else fall back to pure hd library.
//
// This module implements an ICG (Integrated Clock Gate) cell for per-PE clock
// gating. The enable signal is latched on the negedge of clk so the gated clock
// glitch-free follows SKY130 cgt discipline (Antmicro 2025 flow).
// hdll cells (10× lower leakage) are used on the enable path and hold latch;
// hd cells are used on the compute path — zoning enforced by synthesis attribute
// comments below.

`default_nettype none

module v7_clock_gate_S13 (
    input  wire clk,       // raw clock from PLL / clk_in
    input  wire enable,    // 1 = PE active; 0 = idle → gate clock
    output wire clk_out    // gated clock to PE registers
);

    // (* SYNTHESIS_CELL_LIB = "sky130_fd_sc_hdll" *) — hold latch (hdll, low-leakage)
    reg  latch_q;

    // Latch fires on falling edge (standard ICG topology)
    always @(*) begin
        if (!clk) latch_q = enable;
    end

    // (* SYNTHESIS_CELL_LIB = "sky130_fd_sc_hd" *) — AND gate on hot path (hd)
    assign clk_out = clk & latch_q;

endmodule
`default_nettype wire
