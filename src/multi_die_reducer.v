// SPDX-License-Identifier: Apache-2.0
// multi_die_reducer.v — L-S48 Multi-Die Ledger Reducer (Wave-13b)
//
// 8-leaf inter-die merkle tree: 8 die-roots → 1 super-root, 3 stages.
//
//   Stage 0 (combinational):
//     n01 = hash_combine(die0, die1)
//     n23 = hash_combine(die2, die3)
//     n45 = hash_combine(die4, die5)
//     n67 = hash_combine(die6, die7)
//
//   Pipeline register 1 (clk)
//
//   Stage 1 (combinational after reg):
//     m0 = hash_combine(n01_r, n23_r)
//     m1 = hash_combine(n45_r, n67_r)
//
//   Pipeline register 2 (clk)
//
//   Stage 2 (combinational after reg):
//     super_root = hash_combine(m0_r, m1_r)
//
// Hash combiner: 3-round XOR+rotate, R1=5, R2=11, R3=22 — identical to
//   Wave-12a (L-S44) and Wave-12b (L-S45) for cross-module byte-for-byte match.
//
//   hash_combine(a, b):
//     s0  = a ^ b
//     s1  = rotl64(s0, 5)  ^ a
//     s2  = rotl64(s1, 11) ^ b
//     out = rotl64(s2, 22) ^ a ^ b
//
// Pipeline latency: 2 cycles (2 pipeline registers between stages).
// Throughput:       1 super-root per cycle (pipelined).
//
// Constraints:
//   - No `*` or DSP (R-SI-1) — pure XOR/rotate combinational logic
//   - Pipeline FFs annotated (* keep *) (* no_retiming *)
//   - Apache-2.0, pure RTL, Verilog-2001
//   - Author: Dmitrii Vasilev <admin@t27.ai>
//
// PhD anchor: φ² + φ⁻² = 3 | 8-leaf inter-die aggregation
//
`default_nettype none

module multi_die_reducer (
    input  wire        clk,
    input  wire        rst_n,
    // 8 die-root inputs (64-bit each, one per die)
    input  wire [63:0] die0,
    input  wire [63:0] die1,
    input  wire [63:0] die2,
    input  wire [63:0] die3,
    input  wire [63:0] die4,
    input  wire [63:0] die5,
    input  wire [63:0] die6,
    input  wire [63:0] die7,
    input  wire        dies_valid,
    // Super-root output (2 cycles after dies_valid)
    output reg  [63:0] super_root,
    output reg         super_root_valid
);

    // ---------------------------------------------------------------
    // Combinational hash_combine function (3-round XOR+rotate)
    // Identical to Wave-12a/b trinity_merkle_agg.v for cross-module match.
    // rotl(x, n) = {x[63-n:0], x[63:64-n]}
    // ---------------------------------------------------------------
    function [63:0] hash_combine;
        input [63:0] a, b;
        reg [63:0] s0, s1, s2, out;
        begin
            // Round 0: mix
            s0  = a ^ b;
            // Round 1: rotl-5 XOR a
            s1  = {s0[58:0], s0[63:59]} ^ a;
            // Round 2: rotl-11 XOR b
            s2  = {s1[52:0], s1[63:53]} ^ b;
            // Round 3: rotl-22 XOR a XOR b
            out = {s2[41:0], s2[63:42]} ^ a ^ b;
            hash_combine = out;
        end
    endfunction

    // ---------------------------------------------------------------
    // Stage 0: combinational — four parallel combine operations (8→4)
    // ---------------------------------------------------------------
    wire [63:0] n01_comb;
    wire [63:0] n23_comb;
    wire [63:0] n45_comb;
    wire [63:0] n67_comb;

    assign n01_comb = hash_combine(die0, die1);
    assign n23_comb = hash_combine(die2, die3);
    assign n45_comb = hash_combine(die4, die5);
    assign n67_comb = hash_combine(die6, die7);

    // ---------------------------------------------------------------
    // Pipeline register 1: stage 0→1 (8→4 result latched)
    // (* keep *) (* no_retiming *) prevent synthesis optimisation
    // ---------------------------------------------------------------
    (* keep *) (* no_retiming *) reg [63:0] n01_r;
    (* keep *) (* no_retiming *) reg [63:0] n23_r;
    (* keep *) (* no_retiming *) reg [63:0] n45_r;
    (* keep *) (* no_retiming *) reg [63:0] n67_r;
    (* keep *) (* no_retiming *) reg        valid_r1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n01_r   <= 64'b0;
            n23_r   <= 64'b0;
            n45_r   <= 64'b0;
            n67_r   <= 64'b0;
            valid_r1 <= 1'b0;
        end else begin
            n01_r   <= n01_comb;
            n23_r   <= n23_comb;
            n45_r   <= n45_comb;
            n67_r   <= n67_comb;
            valid_r1 <= dies_valid;
        end
    end

    // ---------------------------------------------------------------
    // Stage 1: combinational — two parallel combine operations (4→2)
    // ---------------------------------------------------------------
    wire [63:0] m0_comb;
    wire [63:0] m1_comb;

    assign m0_comb = hash_combine(n01_r, n23_r);
    assign m1_comb = hash_combine(n45_r, n67_r);

    // ---------------------------------------------------------------
    // Pipeline register 2: stage 1→2 (4→2 result latched)
    // ---------------------------------------------------------------
    (* keep *) (* no_retiming *) reg [63:0] m0_r;
    (* keep *) (* no_retiming *) reg [63:0] m1_r;
    (* keep *) (* no_retiming *) reg        valid_r2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m0_r    <= 64'b0;
            m1_r    <= 64'b0;
            valid_r2 <= 1'b0;
        end else begin
            m0_r    <= m0_comb;
            m1_r    <= m1_comb;
            valid_r2 <= valid_r1;
        end
    end

    // ---------------------------------------------------------------
    // Stage 2: super-root = hash_combine(m0_r, m1_r)  (2→1)
    // Registered output for timing closure
    // ---------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            super_root       <= 64'b0;
            super_root_valid <= 1'b0;
        end else begin
            super_root       <= hash_combine(m0_r, m1_r);
            super_root_valid <= valid_r2;
        end
    end

endmodule
`default_nettype wire
