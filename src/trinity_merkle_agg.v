// SPDX-License-Identifier: Apache-2.0
// trinity_merkle_agg.v — L-S45 Trinity Merkle Aggregator (Wave-12b)
//
// 4-leaf → 1-root merkle tree: on-die, no external dependency.
//
//   Stage 0 (combinational):
//     node01 = hash_combine(leaf0, leaf1)
//     node23 = hash_combine(leaf2, leaf3)
//   Stage 1 (pipeline register — 1 cycle latency):
//     root   = hash_combine(node01, node23)
//
// Hash combiner: same lightweight 3-round XOR+rotate as Wave-12a (L-S44).
// Round constants:  R1=5, R2=11, R3=22  (ternary-friendly prime rotations).
//
//   hash_combine(a, b):
//     s0 = a ^ b
//     s1 = {s0[58:0], s0[63:59]} ^ a       // rotl 5  XOR a
//     s2 = {s1[52:0], s1[63:53]} ^ b       // rotl 11 XOR b
//     out= {s2[41:0], s2[63:42]} ^ a ^ b   // rotl 22 XOR a XOR b
//
// Constraints:
//   - No `*` or DSP (R-SI-1)
//   - Pipeline FFs annotated (* keep *)  (* no_retiming *)
//   - Apache-2.0, on-die, pure RTL, Verilog-2001
//
// PhD anchor: φ² + φ⁻² = 3 | DOI: 10.5281/zenodo.19227877
//
`default_nettype none

module trinity_merkle_agg (
    input  wire        clk,
    input  wire        rst_n,
    // 4 tile leaves (one per tile, 64-bit each)
    input  wire [63:0] leaf0,
    input  wire [63:0] leaf1,
    input  wire [63:0] leaf2,
    input  wire [63:0] leaf3,
    input  wire        leaves_valid,
    // Merkle root output (1 cycle after leaves_valid)
    output reg  [63:0] root,
    output reg         root_valid
);

    // ---------------------------------------------------------------
    // Combinational hash_combine function (3-round XOR+rotate)
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
    // Stage 0: combinational — two parallel combine operations
    // ---------------------------------------------------------------
    wire [63:0] node01_comb;
    wire [63:0] node23_comb;

    assign node01_comb = hash_combine(leaf0, leaf1);
    assign node23_comb = hash_combine(leaf2, leaf3);

    // ---------------------------------------------------------------
    // Stage 1: pipeline register + root combine
    // (* keep *) (* no_retiming *) prevent synthesis optimisation
    // ---------------------------------------------------------------
    (* keep *) (* no_retiming *) reg [63:0] node01_r;
    (* keep *) (* no_retiming *) reg [63:0] node23_r;
    (* keep *) (* no_retiming *) reg        valid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            node01_r  <= 64'b0;
            node23_r  <= 64'b0;
            valid_r   <= 1'b0;
        end else begin
            node01_r  <= node01_comb;
            node23_r  <= node23_comb;
            valid_r   <= leaves_valid;
        end
    end

    // ---------------------------------------------------------------
    // Stage 2: root = hash_combine(node01_r, node23_r)  (comb after reg)
    // ---------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            root       <= 64'b0;
            root_valid <= 1'b0;
        end else begin
            root       <= hash_combine(node01_r, node23_r);
            root_valid <= valid_r;
        end
    end

endmodule
`default_nettype wire
