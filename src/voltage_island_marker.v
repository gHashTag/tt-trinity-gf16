// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// voltage_island_marker.v — L-S30 Voltage Island Marker
// TT-Shuttle GF16 · Lane L-S30 Voltage Island
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// PURPOSE: Synthesizable marker module that tags low-power island blocks and
// propagates a 3-bit island-membership status vector. No actual VDD switching
// occurs in TT process — this module records the partition for Phase 2 silicon
// synthesis constraints and validates via simulation that the tag bits are
// correctly wired.
//
// CELL BUDGET: ~20 cells (3 AND2 + 3 BUF + island_id latch + health OR3 + misc)
//
// MARKER PROTOCOL:
//   - Each island block drives its rom_ok / ctrl_ok health pin to 1'b1.
//   - island_en[2:0] input: software/compile-time enable per block.
//   - lp_island_status[2:0] output: island_en[i] & block_ok[i]
//   - island_active: OR of all status bits — overall island armed.
//   - island_id[1:0]: static ID = 2'b01 (S30 island).
//
// R-SI-1: No `*`. Pure Verilog-2005. ~20 cells.

`default_nettype none

module voltage_island_marker (
    input  wire        clk,
    input  wire        rst_n,

    // Per-block health inputs (driven by block rom_ok / ctrl_ok pins)
    input  wire        crown47_ok,      // from crown47_rom.rom_ok
    input  wire        restraint_ok,    // from restraint_ctrl.ctrl_ok
    input  wire        k3_alu_ok,       // from alu9_decoder.decoder_ok (k3 path)

    // Island-enable bitmap (set by synthesis or host register)
    // island_en[0] = crown47_rom in island
    // island_en[1] = restraint_ctrl in island
    // island_en[2] = k3_alu path in island
    input  wire [2:0]  island_en,

    // Outputs
    output wire [2:0]  lp_island_status,  // island_en[i] & block_ok[i]
    output wire        island_active,     // OR of lp_island_status
    output wire [1:0]  island_id,         // static S30 island ID = 2'b01
    output wire        marker_ok          // all enabled blocks healthy
);

    // Per-block island status: enabled AND healthy
    // (* LP_ISLAND = "S30_07V" *)
    assign lp_island_status[0] = island_en[0] & crown47_ok;
    assign lp_island_status[1] = island_en[1] & restraint_ok;
    assign lp_island_status[2] = island_en[2] & k3_alu_ok;

    // Island active if any block is in island
    assign island_active = lp_island_status[0]
                         | lp_island_status[1]
                         | lp_island_status[2];

    // Static island identifier for S30
    assign island_id = 2'b01;

    // Health: all enabled blocks must be ok
    // marker_ok = (~island_en[i] | lp_island_status[i]) for all i
    // Equivalently: no enabled block is unhealthy
    wire ok0, ok1, ok2;
    assign ok0 = (~island_en[0]) | lp_island_status[0];
    assign ok1 = (~island_en[1]) | lp_island_status[1];
    assign ok2 = (~island_en[2]) | lp_island_status[2];
    assign marker_ok = ok0 & ok1 & ok2;

    // Suppress unused clk/rst_n warnings in purely combinational module.
    // These are present for future registered variant (Phase 2 power sequencer).
    wire _unused_clk;
    wire _unused_rst_n;
    assign _unused_clk   = clk;
    assign _unused_rst_n = rst_n;

endmodule
`default_nettype wire
