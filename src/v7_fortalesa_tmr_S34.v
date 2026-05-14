// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 TRI-NET-G1 / TT-Shuttle Squeeze v7
//
// v7_fortalesa_tmr_S34.v — FORTALESA selective Triple Modular Redundancy voter
// Stream S-34 · Wave W15-TT-F · Anchor φ²+φ⁻²=3
//
// G-34 FALSIFICATION: stuck-at-0 fault injection on any TMR'd PE — output
//                     remains correct → else TMR scope reduced or dropped.
//
// Reference: FORTALESA arXiv 2503.04426
//   "FORTALESA: Selective TMR for critical MAC PEs"
//
// This is a "self-healing model" voter — no claims of trusted execution.
//
// Features:
//   - 8-bit accumulator voter (configurable protection per PE via protect_en)
//   - Majority voter: out = (a&b)|(b&c)|(a&c)
//   - Error flag:     err = (a^b)|(b^c)
//   - protect_en=0: bypass TMR, pass input_a directly (area-saving for non-critical PEs)
//   - NUM_PE parameter: number of PEs covered (default 4, per FORTALESA recommendation)
//
// No wildcard (*) in synth RTL.

`default_nettype none

// ============================================================
// Single-bit TMR voter cell
// ============================================================
module v7_tmr_voter_1b (
    input  wire a,
    input  wire b,
    input  wire c,
    output wire voted,
    output wire err
);
    // Majority: voted = (a&b)|(b&c)|(a&c)
    assign voted = (a & b) | (b & c) | (a & c);
    // Error flag: any disagreement
    assign err   = (a ^ b) | (b ^ c);
endmodule


// ============================================================
// 8-bit TMR voter: vote all 8 bits independently
// ============================================================
module v7_tmr_voter_8b (
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [7:0] c,
    output wire [7:0] voted,
    output wire       err          // any bit mismatch across all 8
);
    wire [7:0] bit_err;

    // Explicit bit-by-bit instantiation (no generate with implicit *)
    v7_tmr_voter_1b bit0 (.a(a[0]), .b(b[0]), .c(c[0]), .voted(voted[0]), .err(bit_err[0]));
    v7_tmr_voter_1b bit1 (.a(a[1]), .b(b[1]), .c(c[1]), .voted(voted[1]), .err(bit_err[1]));
    v7_tmr_voter_1b bit2 (.a(a[2]), .b(b[2]), .c(c[2]), .voted(voted[2]), .err(bit_err[2]));
    v7_tmr_voter_1b bit3 (.a(a[3]), .b(b[3]), .c(c[3]), .voted(voted[3]), .err(bit_err[3]));
    v7_tmr_voter_1b bit4 (.a(a[4]), .b(b[4]), .c(c[4]), .voted(voted[4]), .err(bit_err[4]));
    v7_tmr_voter_1b bit5 (.a(a[5]), .b(b[5]), .c(c[5]), .voted(voted[5]), .err(bit_err[5]));
    v7_tmr_voter_1b bit6 (.a(a[6]), .b(b[6]), .c(c[6]), .voted(voted[6]), .err(bit_err[6]));
    v7_tmr_voter_1b bit7 (.a(a[7]), .b(b[7]), .c(c[7]), .voted(voted[7]), .err(bit_err[7]));

    assign err = |bit_err;   // OR-reduce: any bit error → flag

endmodule


// ============================================================
// FORTALESA selective TMR PE wrapper — 8-bit accumulator
//
// For each PE index, protect_en[i] selects TMR or bypass.
// In bypass mode the single input_a[i] is passed through.
// In protect mode the TMR voter receives three independent
// copies of the accumulator (a/b/c supplied externally, e.g.
// from triplicated flip-flop banks).
//
// NUM_PE: number of processing elements (default 4)
// ============================================================
module v7_fortalesa_tmr_S34 #(
    parameter NUM_PE = 4
) (
    input  wire clk,
    input  wire rst_n,

    // Protection enable per PE (1 = TMR active, 0 = bypass)
    input  wire [NUM_PE-1:0] protect_en,

    // Three redundant copies of 8-bit accumulator per PE
    // Layout: [PE_idx * 8 +: 8]
    input  wire [(NUM_PE*8)-1:0] acc_a,   // copy A
    input  wire [(NUM_PE*8)-1:0] acc_b,   // copy B
    input  wire [(NUM_PE*8)-1:0] acc_c,   // copy C

    // Voted / bypassed outputs
    output reg  [(NUM_PE*8)-1:0] voted_out,

    // Per-PE error flags
    output reg  [NUM_PE-1:0]     err_flag,

    // Aggregate error (any PE fault)
    output wire                  any_err
);

    assign any_err = |err_flag;

    // Wiring for voter outputs (combinational)
    wire [7:0] v_voted  [0:NUM_PE-1];
    wire       v_err    [0:NUM_PE-1];

    // PE 0
    v7_tmr_voter_8b voter_pe0 (
        .a(acc_a[7:0]),   .b(acc_b[7:0]),   .c(acc_c[7:0]),
        .voted(v_voted[0]), .err(v_err[0])
    );

    // PE 1
    v7_tmr_voter_8b voter_pe1 (
        .a(acc_a[15:8]),  .b(acc_b[15:8]),  .c(acc_c[15:8]),
        .voted(v_voted[1]), .err(v_err[1])
    );

    // PE 2
    v7_tmr_voter_8b voter_pe2 (
        .a(acc_a[23:16]), .b(acc_b[23:16]), .c(acc_c[23:16]),
        .voted(v_voted[2]), .err(v_err[2])
    );

    // PE 3
    v7_tmr_voter_8b voter_pe3 (
        .a(acc_a[31:24]), .b(acc_b[31:24]), .c(acc_c[31:24]),
        .voted(v_voted[3]), .err(v_err[3])
    );

    // Register outputs and apply protect_en mux
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            voted_out <= {(NUM_PE*8){1'b0}};
            err_flag  <= {NUM_PE{1'b0}};
        end else begin
            // PE 0
            voted_out[7:0]   <= protect_en[0] ? v_voted[0] : acc_a[7:0];
            err_flag[0]      <= protect_en[0] & v_err[0];
            // PE 1
            voted_out[15:8]  <= protect_en[1] ? v_voted[1] : acc_a[15:8];
            err_flag[1]      <= protect_en[1] & v_err[1];
            // PE 2
            voted_out[23:16] <= protect_en[2] ? v_voted[2] : acc_a[23:16];
            err_flag[2]      <= protect_en[2] & v_err[2];
            // PE 3
            voted_out[31:24] <= protect_en[3] ? v_voted[3] : acc_a[31:24];
            err_flag[3]      <= protect_en[3] & v_err[3];
        end
    end

endmodule
