// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// cg_activity_monitor.v — S-14 Clock Gating: Per-block activity monitor
// Trinity TRI-1 · tt-trinity-gf16 · feat/tt-v7-power stream
//
// Constitutional: R-SI-1 (zero standalone * operators) ✓
// Language:       Verilog-2005 — no SystemVerilog constructs ✓
// Anchor:         φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// Description:
//   Monitors register-output activity across N_BLOCKS independent blocks.
//   Each block supplies a 1-bit activity pulse (act[i]).
//   An independent 3-bit saturating idle counter tracks each block.
//
//   Counter rules:
//     - reset to 0 and clk_en[i] stays 1 when act[i]=1 (activity)
//     - increments each cycle act[i]=0, saturates at IDLE_THRESH (=7)
//     - when counter reaches IDLE_THRESH and act[i] still 0 on next cycle:
//       clk_en[i] deasserts → ICG freezes that block's clock
//     - clk_en[i] reasserts immediately on the next clock edge after activity
//
//   ICG wakeup safety: clk_en is a registered output — no combinational
//   glitch path into the ICG latch input.
//
// Interface:
//   clk       — system clock (50 MHz TT target)
//   rst_n     — active-low synchronous reset
//   act       — [N_BLOCKS-1:0] activity pulses: 1 = block had register change
//   clk_en    — [N_BLOCKS-1:0] ICG enables: 1 = clock running, 0 = gated off
//
// Estimated cell count: N_BLOCKS × (3-bit counter ~4 + comparator ~3 + FF ~1) ≈ 8×8 = ~64
// Total with glue: ~72 cells — well within 180-cell budget.

`timescale 1ns/1ps
`default_nettype none

module cg_activity_monitor #(
    parameter integer N_BLOCKS   = 4,    // number of gated blocks
    parameter [2:0]   IDLE_THRESH = 3'd7 // idle for IDLE_THRESH+1 = 8 cycles → gate off
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire [N_BLOCKS-1:0]  act,     // activity pulse per block per cycle
    output reg  [N_BLOCKS-1:0]  clk_en   // ICG gate enables (1 = clock running)
);

    // 3-bit saturating idle counter per block
    reg [2:0] idle_cnt_0;
    reg [2:0] idle_cnt_1;
    reg [2:0] idle_cnt_2;
    reg [2:0] idle_cnt_3;

    // Next-state wires
    reg [2:0] cnt_next_0;
    reg [2:0] cnt_next_1;
    reg [2:0] cnt_next_2;
    reg [2:0] cnt_next_3;

    reg en_next_0;
    reg en_next_1;
    reg en_next_2;
    reg en_next_3;

    // ------------------------------------------------------------------
    // Combinational: compute next counter and next clk_en per block
    // ------------------------------------------------------------------
    always @(*) begin : comb_blk0
        if (act[0]) begin
            cnt_next_0 = 3'd0;
            en_next_0  = 1'b1;
        end else if (idle_cnt_0 < IDLE_THRESH) begin
            cnt_next_0 = idle_cnt_0 + 3'd1;
            en_next_0  = 1'b1;
        end else begin
            cnt_next_0 = IDLE_THRESH;
            en_next_0  = 1'b0;
        end
    end

    always @(*) begin : comb_blk1
        if (act[1]) begin
            cnt_next_1 = 3'd0;
            en_next_1  = 1'b1;
        end else if (idle_cnt_1 < IDLE_THRESH) begin
            cnt_next_1 = idle_cnt_1 + 3'd1;
            en_next_1  = 1'b1;
        end else begin
            cnt_next_1 = IDLE_THRESH;
            en_next_1  = 1'b0;
        end
    end

    always @(*) begin : comb_blk2
        if (act[2]) begin
            cnt_next_2 = 3'd0;
            en_next_2  = 1'b1;
        end else if (idle_cnt_2 < IDLE_THRESH) begin
            cnt_next_2 = idle_cnt_2 + 3'd1;
            en_next_2  = 1'b1;
        end else begin
            cnt_next_2 = IDLE_THRESH;
            en_next_2  = 1'b0;
        end
    end

    always @(*) begin : comb_blk3
        if (act[3]) begin
            cnt_next_3 = 3'd0;
            en_next_3  = 1'b1;
        end else if (idle_cnt_3 < IDLE_THRESH) begin
            cnt_next_3 = idle_cnt_3 + 3'd1;
            en_next_3  = 1'b1;
        end else begin
            cnt_next_3 = IDLE_THRESH;
            en_next_3  = 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // Sequential: register state on rising clock edge
    // ------------------------------------------------------------------
    always @(posedge clk) begin : seq_regs
        if (!rst_n) begin
            // Reset: all clocks running, idle counters cleared
            idle_cnt_0 <= 3'd0;
            idle_cnt_1 <= 3'd0;
            idle_cnt_2 <= 3'd0;
            idle_cnt_3 <= 3'd0;
            clk_en     <= {N_BLOCKS{1'b1}};
        end else begin
            idle_cnt_0 <= cnt_next_0;
            idle_cnt_1 <= cnt_next_1;
            idle_cnt_2 <= cnt_next_2;
            idle_cnt_3 <= cnt_next_3;
            clk_en[0]  <= en_next_0;
            clk_en[1]  <= en_next_1;
            clk_en[2]  <= en_next_2;
            clk_en[3]  <= en_next_3;
        end
    end

endmodule

`default_nettype wire
