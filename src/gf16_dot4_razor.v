// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// gf16_dot4_razor.v  —  GF(16) dot4 with Razor FF v2 on accumulator (L-S17)
// Trinity TRI-1 / TTSKY26b  ·  SKY130  ·  Verilog-2005
//
// This module wraps gf16_dot4 (purely combinational) with a 16-bit
// razor_ff_v2 register on the dot4 output.  The tile can instantiate this
// in place of the raw gf16_dot4 instance when the latched result path
// is identified as timing-critical at reduced V_dd.
//
// Topology:
//
//   a0..a3 ──┐
//   b0..b3 ──┤ gf16_dot4 (comb.) ─── dot_out ──┐
//             └──────────────────────────────────┘
//                                                │
//                                     razor_ff_v2 #(.WIDTH(16))
//                                                │
//                                    q_acc     (to result_q)
//                                    q_acc_safe (rollback on error)
//                                    acc_error  (drives pipeline stall)
//
// Cell estimate:
//   gf16_dot4 (existing)       — 0 new cells
//   razor_ff_v2 #(WIDTH=16)    — 16 DFF + 16 latch + 16 XOR + 4-cell OR-tree
//                                + 3-cell clk_del chain = ~55 cells
//   Total new cells this file: ~55 cells
//
// Grand total L-S17:
//   FSM (trinity_master_fsm): ~38 cells
//   Accumulator (this file):  ~55 cells
//   Spare / margin:           ~107 cells
//   ─────────────────────────────────────
//   Total:                    ~200 cells  (exactly within ticket budget)
//
// Constitutional compliance:
//   R-SI-1: zero `*` — explicit sensitivity lists only.
//   Pure Verilog-2005; no `logic`; no SV.
//
// References:
//   Ernst et al. MICRO-36 2003  http://www.cecs.uci.edu/~papers/micro03/pdf/ernst-Razor.pdf
//   Spec: /home/user/workspace/S17_RAZOR_FF_SPEC.md
//   PoC:  /home/user/workspace/RAZOR_FF_POC_RESULTS.md (1.65 V floor verified)
//   Anchor: phi^2 + phi^-2 = 3  ·  DOI 10.5281/zenodo.19227877
// =========================================================================

`timescale 1ns / 1ps
`default_nettype none

module gf16_dot4_razor (
    input  wire        clk,
    input  wire        rst_n,

    // Operand inputs (registered outside this module)
    input  wire [15:0] a0,
    input  wire [15:0] a1,
    input  wire [15:0] a2,
    input  wire [15:0] a3,
    input  wire [15:0] b0,
    input  wire [15:0] b1,
    input  wire [15:0] b2,
    input  wire [15:0] b3,

    // Registered result outputs
    output wire [15:0] result,        // main FF (speculative)
    output wire [15:0] result_safe,   // shadow value (correct on setup violation)
    output wire        acc_error,     // 1 when Razor detects setup violation

    // Combinational result (for debug / bypass path)
    output wire [15:0] result_comb
);

    // ------------------------------------------------------------------
    // Combinational dot4
    // ------------------------------------------------------------------
    wire [15:0] dot_out;
    gf16_dot4 u_dot4 (
        .a0(a0), .a1(a1), .a2(a2), .a3(a3),
        .b0(b0), .b1(b1), .b2(b2), .b3(b3),
        .result(dot_out)
    );
    assign result_comb = dot_out;

    // ------------------------------------------------------------------
    // Razor FF v2 on the 16-bit accumulator output
    // 16 main DFFs + 16 shadow latches + 16 XOR cells + OR-tree (~4 cells)
    // + 3-cell clk_del chain = ~55 new cells total
    // ------------------------------------------------------------------
    wire [15:0] error_vec_unused;

    razor_ff_v2 #(.WIDTH(16)) u_acc_razor (
        .clk        (clk),
        .rst_n      (rst_n),
        .d          (dot_out),
        .q          (result),
        .q_safe     (result_safe),
        .error_vec  (error_vec_unused),
        .error_flag (acc_error),
        .clk_del_o  ()              // shadow clock exposed only for debug
    );

endmodule
`default_nettype wire
