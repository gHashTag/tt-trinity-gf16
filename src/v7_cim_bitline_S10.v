// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Trinity Agent <agent@trinity.local>
//
// v7_cim_bitline_S10.v — Compute-in-Memory bitline ternary popcount cell (S-10)
// Stream W15-TT-B · TT-Shuttle Squeeze v7 · TRI-NET-G1
//
// PhD anchor: φ² + φ⁻² = 3
// DOI: 10.5281/zenodo.19227877 · Apache-2.0
//
// G-10 FALSIFICATION: CIM popcount output != reference binary tree popcount
//                     on any test vector from Wave-29 suite.
//
// Design notes:
//   Models a CIM bitline ternary dot-product cell in RTL.
//   Each cell takes 8 pairs of ternary weight bits (w_pos[i], w_neg[i]) and
//   8 activation bits (act[i]), and produces a signed popcount in the range
//   [-8..+8] (5-bit signed result).
//
//   Ternary weight encoding: w_pos=1, w_neg=0 → +1
//                            w_pos=0, w_neg=1 → -1
//                            w_pos=0, w_neg=0 →  0  (masked)
//                            w_pos=1, w_neg=1 →  0  (invalid; treated as 0)
//
//   CIM model: partial sums computed via full-adder tree (Dadda-like).
//   The positive and negative accumulations are computed separately then
//   subtracted via carry-save. No `*` operator used.

`default_nettype none

module v7_cim_bitline_S10 #(
    parameter LANE = 8   // number of input lanes (weights × activations)
)(
    input  wire [LANE-1:0] act,      // 1-bit activations
    input  wire [LANE-1:0] w_pos,    // ternary weight positive bit
    input  wire [LANE-1:0] w_neg,    // ternary weight negative bit
    output wire [4:0]      popcount, // signed popcount [-8..+8] (2's complement 5-bit)
    output wire            ovf,      // overflow flag (should never fire for LANE=8)
    output wire            cim_ok    // health/sanity flag
);

    // -----------------------------------------------------------------------
    // 1. Per-lane contribution bits
    //    pos_bit[i] = act[i] & w_pos[i] & ~w_neg[i]  → +1 contribution
    //    neg_bit[i] = act[i] & w_neg[i] & ~w_pos[i]  → -1 contribution
    // -----------------------------------------------------------------------
    wire [LANE-1:0] pos_bit;
    wire [LANE-1:0] neg_bit;

    genvar i;
    generate
        for (i = 0; i < LANE; i = i+1) begin : lane_bits
            assign pos_bit[i] = act[i] & w_pos[i] & ~w_neg[i];
            assign neg_bit[i] = act[i] & w_neg[i] & ~w_pos[i];
        end
    endgenerate

    // -----------------------------------------------------------------------
    // 2. Popcount trees for pos_bits and neg_bits (4-bit unsigned each, LANE=8)
    //    Built from carry-save adder (CSA) stages — no multiply.
    //
    //    Stage 1: 8 bits → 3× CSA → 2 bits (sum + carry) per group of 3
    //    We use full-adder primitives explicitly.
    // -----------------------------------------------------------------------

    // Full adder macro (inline)
    // sum = a^b^c, carry = (a&b)|(b&c)|(a&c)

    // pos tree (8 → 4-bit count)
    wire ps1, pc1, ps2, pc2, ps3, pc3, ps4, pc4, ps5, pc5, ps6, pc6;
    // Level 1: 3 groups of 3 → 3 FA = 6 half-results, 2 remainder
    assign ps1 = pos_bit[0] ^ pos_bit[1] ^ pos_bit[2];
    assign pc1 = (pos_bit[0]&pos_bit[1])|(pos_bit[1]&pos_bit[2])|(pos_bit[0]&pos_bit[2]);
    assign ps2 = pos_bit[3] ^ pos_bit[4] ^ pos_bit[5];
    assign pc2 = (pos_bit[3]&pos_bit[4])|(pos_bit[4]&pos_bit[5])|(pos_bit[3]&pos_bit[5]);
    // Level 2: ps1,pc1,ps2 → FA
    assign ps3 = ps1 ^ pc1 ^ ps2;
    assign pc3 = (ps1&pc1)|(pc1&ps2)|(ps1&ps2);
    // Level 2: pc2,pos_bit[6],pos_bit[7] → FA
    assign ps4 = pc2 ^ pos_bit[6] ^ pos_bit[7];
    assign pc4 = (pc2&pos_bit[6])|(pos_bit[6]&pos_bit[7])|(pc2&pos_bit[7]);
    // Level 3: ps3,pc3,ps4 → FA
    assign ps5 = ps3 ^ pc3 ^ ps4;
    assign pc5 = (ps3&pc3)|(pc3&ps4)|(ps3&ps4);
    // Level 3: pc4 remainder; form 4-bit count via ripple adder
    wire [3:0] pos_cnt;
    wire c_p1, c_p2, c_p3;
    assign pos_cnt[0] = ps5;
    assign {c_p1, pos_cnt[1]} = {1'b0,pc5} + {1'b0,pc4};
    assign {c_p2, pos_cnt[2]} = c_p1 + 1'b0; // propagate
    assign pos_cnt[3] = c_p2;
    assign c_p3 = 1'b0; // unused; suppress warning

    // neg tree (8 → 4-bit count) — symmetric
    wire ns1, nc1, ns2, nc2, ns3, nc3, ns4, nc4, ns5, nc5;
    assign ns1 = neg_bit[0] ^ neg_bit[1] ^ neg_bit[2];
    assign nc1 = (neg_bit[0]&neg_bit[1])|(neg_bit[1]&neg_bit[2])|(neg_bit[0]&neg_bit[2]);
    assign ns2 = neg_bit[3] ^ neg_bit[4] ^ neg_bit[5];
    assign nc2 = (neg_bit[3]&neg_bit[4])|(neg_bit[4]&neg_bit[5])|(neg_bit[3]&neg_bit[5]);
    assign ns3 = ns1 ^ nc1 ^ ns2;
    assign nc3 = (ns1&nc1)|(nc1&ns2)|(ns1&ns2);
    assign ns4 = nc2 ^ neg_bit[6] ^ neg_bit[7];
    assign nc4 = (nc2&neg_bit[6])|(neg_bit[6]&neg_bit[7])|(nc2&neg_bit[7]);
    assign ns5 = ns3 ^ nc3 ^ ns4;
    assign nc5 = (ns3&nc3)|(nc3&ns4)|(ns3&ns4);
    wire [3:0] neg_cnt;
    wire c_n1, c_n2;
    assign neg_cnt[0] = ns5;
    assign {c_n1, neg_cnt[1]} = {1'b0,nc5} + {1'b0,nc4};
    assign {c_n2, neg_cnt[2]} = c_n1 + 1'b0;
    assign neg_cnt[3] = c_n2;

    // -----------------------------------------------------------------------
    // 3. Signed result = pos_cnt - neg_cnt (5-bit signed)
    //    Range: -8 .. +8 fits in 5-bit 2's complement [-16..+15]
    // -----------------------------------------------------------------------
    wire [4:0] pos_ext = {1'b0, pos_cnt};
    wire [4:0] neg_ext = {1'b0, neg_cnt};
    assign popcount = pos_ext - neg_ext;  // subtract — no multiply

    // overflow: only if pos+neg > 8 (impossible with LANE=8 and correct weights)
    assign ovf  = (pos_cnt > 4'd8) | (neg_cnt > 4'd8);
    assign cim_ok = ~ovf;

    // synthesis translate_off
    initial $display("S-10 ANCHOR: phi^2+phi^-2=3 | CIM bitline 8-lane ternary popcount");
    // synthesis translate_on

endmodule
