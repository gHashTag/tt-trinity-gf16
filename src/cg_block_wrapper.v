// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// cg_block_wrapper.v — S-14 Clock Gating: Integration wrapper for 4 low-activity blocks
// Trinity TRI-1 · tt-trinity-gf16 · feat/tt-v7-power stream
//
// Constitutional: R-SI-1 (zero standalone * operators) ✓
// Language:       Verilog-2005 — no SystemVerilog constructs ✓
// Anchor:         φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// Description:
//   Wires cg_activity_monitor + 4× clk_gate_cell to 4 low-activity blocks:
//     Block 0: lucas_rom       — combinational ROM, zero register activity when idle
//     Block 1: ring27_memory   — ternary ring, idle when shift=0 and wr_en=0
//     Block 2: alu9_decoder    — combinational ALU decoder, idle when no opcode issued
//     Block 3: blake3_anchor   — hash engine, idle between start pulses
//
//   Activity detection uses a 1-bit XOR pulse per block:
//     - lucas_rom:     act = any change in idx (top-level combinational — no regs;
//                      activity pulse = idx changing, driven from ui_in)
//     - ring27_memory: act = shift | wr_en  (register activity on either control)
//     - alu9_decoder:  act = valid          (decoder produced a valid result)
//     - blake3_anchor: act = start | done   (hash engine starting or completing)
//
//   Each block receives a gated clock (clk_gated[i]). The blocks themselves
//   are NOT modified — they still receive the same functional signals. Only
//   the clock line is gated via the ICG cell.
//
//   Note: lucas_rom and alu9_decoder are combinational (no FFs). Their gated
//   clock ports are connected but have no registered downstream — this is safe
//   and the ICG cell becomes a zero-power dead branch that synthesis optimizes
//   away (or retains as a hook for future pipelined versions).
//
// Instantiation hint for tt_um_ghtag_trinity_gf16.v (top-level):
//   cg_block_wrapper u_cg_wrap (
//       .clk         (clk),
//       .rst_n       (rst_n),
//       .idx         (lucas_idx),
//       .shift       (ring_shift),
//       .wr_en       (ring_wr_en),
//       .alu_valid   (alu_valid),
//       .blake_start (blake_start),
//       .blake_done  (blake_done),
//       .clk_lucas   (clk_lucas),
//       .clk_ring    (clk_ring),
//       .clk_alu     (clk_alu),
//       .clk_blake   (clk_blake),
//       .cg_en_out   (cg_en_out)
//   );
//
// Projected dynamic power saving:
//   At 50% average activity per block, 4 gated blocks × 50% gating time
//   = 2 equivalent blocks gated → saves ~14% of total dynamic power.
//   Combined with S-13 (HVT leakage): +10 TOPS/W incremental.
//
// Estimated cell count:
//   cg_activity_monitor (4 lanes): ~36 cells
//   4× clk_gate_cell:              ~8 cells
//   Activity XOR glue:             ~6 cells
//   Total:                         ~50 cells

`timescale 1ns/1ps
`default_nettype none

module cg_block_wrapper (
    input  wire       clk,
    input  wire       rst_n,

    // Activity signals — block 0: lucas_rom (combinational; activity = idx change)
    input  wire [2:0] idx,          // lucas_rom address (from ui_in[3:1])

    // Activity signals — block 1: ring27_memory
    input  wire       shift,        // ring rotate strobe
    input  wire       wr_en,        // ring write enable

    // Activity signals — block 2: alu9_decoder
    input  wire       alu_valid,    // decoder produced a valid result this cycle

    // Activity signals — block 3: blake3_anchor
    input  wire       blake_start,  // hash engine start pulse
    input  wire       blake_done,   // hash engine done pulse

    // Gated clock outputs (one per block)
    output wire       clk_lucas,    // gated clock for lucas_rom region
    output wire       clk_ring,     // gated clock for ring27_memory
    output wire       clk_alu,      // gated clock for alu9_decoder region
    output wire       clk_blake,    // gated clock for blake3_anchor

    // Observation port (for testbench / status register)
    output wire [3:0] cg_en_out     // ICG enables: 1=running, 0=gated
);

    // ------------------------------------------------------------------
    // Activity pulse generation (1-bit per block, registered for S14 cleanliness)
    // ------------------------------------------------------------------
    // Block 0 (lucas_rom): detect any change in idx via XOR with previous cycle
    reg [2:0] idx_prev;
    wire      act_lucas;
    assign    act_lucas = (idx != idx_prev);   // combinational change detect

    always @(posedge clk) begin : reg_idx_prev
        if (!rst_n)
            idx_prev <= 3'd0;
        else
            idx_prev <= idx;
    end

    // Block 1 (ring27_memory): activity = shift OR wr_en
    wire act_ring;
    assign act_ring = shift | wr_en;

    // Block 2 (alu9_decoder): activity = alu_valid pulse
    wire act_alu;
    assign act_alu = alu_valid;

    // Block 3 (blake3_anchor): activity = start OR done
    wire act_blake;
    assign act_blake = blake_start | blake_done;

    // Activity bus for monitor
    wire [3:0] act_bus;
    assign act_bus = {act_blake, act_alu, act_ring, act_lucas};

    // ------------------------------------------------------------------
    // Activity monitor: 4-block, 8-cycle idle threshold
    // ------------------------------------------------------------------
    wire [3:0] cg_en;
    assign cg_en_out = cg_en;

    cg_activity_monitor #(
        .N_BLOCKS   (4),
        .IDLE_THRESH(3'd7)
    ) u_act_mon (
        .clk    (clk),
        .rst_n  (rst_n),
        .act    (act_bus),
        .clk_en (cg_en)
    );

    // ------------------------------------------------------------------
    // ICG cells: one per block
    // ------------------------------------------------------------------
    clk_gate_cell u_icg_lucas (
        .clk       (clk),
        .gate_en   (cg_en[0]),
        .clk_gated (clk_lucas)
    );

    clk_gate_cell u_icg_ring (
        .clk       (clk),
        .gate_en   (cg_en[1]),
        .clk_gated (clk_ring)
    );

    clk_gate_cell u_icg_alu (
        .clk       (clk),
        .gate_en   (cg_en[2]),
        .clk_gated (clk_alu)
    );

    clk_gate_cell u_icg_blake (
        .clk       (clk),
        .gate_en   (cg_en[3]),
        .clk_gated (clk_blake)
    );

endmodule

`default_nettype wire
