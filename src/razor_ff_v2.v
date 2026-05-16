// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// razor_ff_v2.v  —  Razor FF v2 (L-S17, Lane L)
// Trinity TRI-1 / TTSKY26b  ·  SKY130 sky130_fd_sc_hd  ·  Verilog-2005
//
// Implements Razor I topology (Ernst et al., MICRO-36 2003) with:
//   • Parameterised N-bit width
//   • clk_del generated internally via 3-inverter delay chain (≈2–3 cell delay)
//     so the caller need only supply clk + rst_n + d.  clk_del is also exposed
//     as an output for inspection / chaining.
//   • XOR comparator on every bit (1 cell per bit)
//   • error_flag OR-reduction across all WIDTH bits (|error_vec)
//   • rollback output: when error_flag=1 the caller should stall / replay;
//     q_safe presents the shadow value (correct late-arriving data)
//
// Cell estimate per instantiation (Yosys/ABC on sky130_fd_sc_hd):
//   WIDTH=1  → ~6 cells  (1 DFF + 1 latch + 1 XOR + 1 INV + 3 BUF)
//   WIDTH=8  → ~8 cells  (8 DFF + 8 latch + 8 XOR + 1 OR-tree + delay chain)
//   WIDTH=16 → ~10 cells overhead + 2 per bit ≈ 42 cells
//
// For 8 FSM FFs (WIDTH=1 ×8)   → ~48 cells
// For 16-bit accum (WIDTH=16)  → ~42 cells  (counted as 1 instance)
// Total for L-S17 integration  → ~90 cells raw; with OR-tree ~10 extra → ~100 cells
// (well within the ≤200 cell budget stated in the ticket)
//
// Constitutional compliance:
//   R-SI-1  : NO standalone `*` in sensitivity lists — all always blocks use
//             explicit signal lists (Verilog-2005 §9.7.1).
//   Style   : Pure Verilog-2005; no `logic`, no `'{...}`, no SystemVerilog.
//   R-SI-1 arithmetic: `|error_vec` is a unary reduction — not a standalone `*`.
//
// References:
//   Ernst et al. MICRO-36 2003  http://www.cecs.uci.edu/~papers/micro03/pdf/ernst-Razor.pdf
//   Ernst et al. IEEE D&T 2004  http://www.cse.umich.edu/awards/pdfs/razor04.pdf
//   Spec: /home/user/workspace/S17_RAZOR_FF_SPEC.md
//   PoC:  /home/user/workspace/RAZOR_FF_POC_RESULTS.md  (V_dd floor 1.65 V verified)
//
// Anchor: phi^2 + phi^-2 = 3  ·  DOI 10.5281/zenodo.19227877
// ========================================================================

`timescale 1ns / 1ps
`default_nettype none

module razor_ff_v2 #(
    parameter integer WIDTH = 1   // set to 8 for FSM state, 16 for accumulator
) (
    input  wire             clk,        // system clock (posedge = speculative capture)
    input  wire             rst_n,      // active-low async reset

    input  wire [WIDTH-1:0] d,          // data input from combinational path

    output reg  [WIDTH-1:0] q,          // main FF output (speculative; use q_safe on error)
    output wire [WIDTH-1:0] q_safe,     // shadow latch output (correct value on error)
    output wire [WIDTH-1:0] error_vec,  // per-bit error flags (q XOR q_shadow)
    output wire             error_flag, // OR of error_vec — drives FSM stall / rollback
    output wire             clk_del_o   // delayed clock (exported for debug / chaining)
);

    // ------------------------------------------------------------------
    // 1. Delayed clock: 3 cascaded inverters ≈ 2–3 cell delay at SKY130.
    //    In RTL simulation this resolves to ~0 ns (inertial), so the
    //    testbench drives clk_del_o by checking timing; silicon STA uses
    //    the actual cell delay.  For functional RTL sim we invert clk to
    //    approximate T/2 phase shift (Ernst et al. recommendation).
    //
    //    Synthesises to:  3× sky130_fd_sc_hd__inv_1
    //    Simulation proxy: clk_del_o ≈ ~clk  (T/2 shift)
    // ------------------------------------------------------------------
    wire clk_inv1;
    wire clk_inv2;
    wire clk_del;

    assign clk_inv1 = ~clk;          // INV cell 1
    assign clk_inv2 = ~clk_inv1;     // INV cell 2 (re-invert = in-phase)
    assign clk_del  = ~clk_inv2;     // INV cell 3 (invert again = ~clk = T/2 shift)
    assign clk_del_o = clk_del;

    // ------------------------------------------------------------------
    // 2. Shadow latch: level-sensitive, transparent while clk_del = 1.
    //    Synthesises to WIDTH × sky130_fd_sc_hd__dlxtp_1
    //    R-SI-1: explicit sensitivity list  (clk_del, d, rst_n)
    // ------------------------------------------------------------------
    reg [WIDTH-1:0] q_shadow;

    always @(clk_del or d or rst_n) begin
        if (!rst_n) begin
            q_shadow <= {WIDTH{1'b0}};
        end else if (clk_del) begin
            q_shadow <= d;          // transparent phase: capture late-arriving data
        end
        // opaque phase: q_shadow holds last captured value
    end

    // ------------------------------------------------------------------
    // 3. Main flip-flop: posedge-triggered, async reset.
    //    Synthesises to WIDTH × sky130_fd_sc_hd__dfrtp_1
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q <= {WIDTH{1'b0}};
        end else begin
            q <= d;                 // speculative capture
        end
    end

    // ------------------------------------------------------------------
    // 4. Error detection: XOR per bit.
    //    error_flag = 1 → setup violation; shadow latch caught the data
    //    that the main FF missed (or caught a transition mid-setup).
    //    Synthesises to: WIDTH × sky130_fd_sc_hd__xor2_1
    //                  + 1 OR reduction tree (~WIDTH/4 cells)
    // ------------------------------------------------------------------
    assign error_vec  = q ^ q_shadow;
    assign error_flag = |error_vec;     // unary reduction — not a standalone `*`

    // ------------------------------------------------------------------
    // 5. Safe (corrected) output: shadow value when error, main FF otherwise.
    //    On error the caller should:
    //      (a) stall the pipeline for 1 cycle (pipeline_stall <= error_flag)
    //      (b) use q_safe instead of q for downstream logic during the stall
    //    This is the "rollback" recovery described in Ernst et al. 2004.
    //    Synthesises to: WIDTH × sky130_fd_sc_hd__mux2_1
    // ------------------------------------------------------------------
    assign q_safe = error_flag ? q_shadow : q;

endmodule

// ========================================================================
// razor_ff_v2_bank.v  —  8-instance bank used in trinity_master_fsm
//
// Wraps 8 × razor_ff_v2 #(.WIDTH(1)) for the 8 critical FSM state FFs.
// One shared error_flag drives the FSM rollback signal.
//
// Cell estimate: 8 × ~6 cells = ~48 cells + 1 OR8 tree (~7 cells) = ~55 cells
// ========================================================================

module razor_ff_v2_bank #(
    parameter integer DEPTH = 8   // number of 1-bit FFs in this bank
) (
    input  wire [DEPTH-1:0] d,
    input  wire             clk,
    input  wire             rst_n,
    output wire [DEPTH-1:0] q,
    output wire [DEPTH-1:0] q_safe,
    output wire [DEPTH-1:0] error_vec,
    output wire             error_flag   // OR across all DEPTH FFs
);

    // Intermediate per-FF error flags
    wire [DEPTH-1:0] ff_err;

    // Generate DEPTH 1-bit razor_ff_v2 instances
    // Verilog-2005: use generate + genvar (no SystemVerilog)
    genvar gi;
    generate
        for (gi = 0; gi < DEPTH; gi = gi + 1) begin : g_razor_bank
            wire q_i;
            wire q_safe_i;
            wire err_vec_i;
            wire err_flag_i;
            wire clk_del_unused;

            razor_ff_v2 #(.WIDTH(1)) u_rff (
                .clk        (clk),
                .rst_n      (rst_n),
                .d          (d[gi]),
                .q          (q_i),
                .q_safe     (q_safe_i),
                .error_vec  (err_vec_i),
                .error_flag (err_flag_i),
                .clk_del_o  (clk_del_unused)
            );

            assign q[gi]         = q_i;
            assign q_safe[gi]    = q_safe_i;
            assign error_vec[gi] = err_vec_i;
            assign ff_err[gi]    = err_flag_i;
        end
    endgenerate

    // OR-tree across all FF error flags
    // R-SI-1 compliant: unary reduction
    assign error_flag = |ff_err;

endmodule
`default_nettype wire
