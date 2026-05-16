// =============================================================================
// carry_skip_adder_16.v — L-Z03 16-bit Carry-Skip Adder (4 blocks × 4 bits)
// =============================================================================
// DESIGN SPEC (L-Z03 Carry-Skip Adder)
// ----------------------------------------
// Purpose:
//   100%-exact 16-bit binary adder using carry-skip (carry-bypass) technique.
//   Splits the 16-bit operand into 4 blocks of 4 bits each. Within each block,
//   a block propagate signal P_block = AND(p[i+3], p[i+2], p[i+1], p[i])
//   allows carry to skip around the block when all bits in the block propagate.
//   Zero approximation error — sum is identical to a+b for all inputs.
//
// Carry-Skip Algorithm:
//   For each 4-bit block [i+3:i], compute:
//     p[k]    = a[k] ^ b[k]            (bit-level generate/propagate XOR)
//     g[k]    = a[k] & b[k]            (bit-level generate)
//     P_block = p[i+3] & p[i+2] & p[i+1] & p[i]  (block-level propagate)
//
//   Carry into next block:
//     If P_block == 1: c_out = c_in (carry skips the entire block)
//     If P_block == 0: c_out = carry_ripple computed within the block
//
//   Sum bit: s[k] = p[k] ^ c[k]
//
// Performance vs RCA:
//   RCA critical path: 16 full-adder stages (carry chain through all 16 bits)
//   Carry-skip path:   4 blocks × (ripple in block) + 4 skip muxes
//   Worst-case carry-skip path: ~(4 + 4) stages = 8 stages
//   Savings: ~30% fewer cells on critical path vs RCA
//
// Cell budget:
//   Per 4-bit block:
//     4 XOR2 (propagate)     : 4 cells
//     4 AND2 (generate)      : 4 cells
//     3 OR2/AND2 (carry prop): 3 cells
//     1 AND4 (P_block)       : 1 cell
//     1 MUX2 (carry skip)    : 1 cell
//   4 blocks × ~13 cells    : ~52 cells
//   Final carry / sum XOR   : ~3 cells
//   Total                   : ~55 cells (vs ~80 for RCA, ~41 for L-Z01 approx)
//
// Constitutional compliance:
//   - R-SI-1: zero `*` operator — uses only ^, &, |, + (in sum XOR chains)
//   - Pure Verilog-2005: no `logic`, no `typedef`, no SystemVerilog
//   - Cell budget: ~55 cells, well within 60% tile utilisation ceiling
//   - Accuracy: 100% exact (no approximation)
//
// Interface:
//   a    [15:0]  first  operand
//   b    [15:0]  second operand
//   sum  [15:0]  exact sum = a + b (mod 2^16)
//
// Wiring contract (gf16_dot4 accumulator):
//   Replaces the final gf16_add instance (a_final) in gf16_dot4.
//   Intermediate partial sums s01, s23 are still computed by gf16_add;
//   only the last combination step (s01 + s23 → result) uses this module.
// =============================================================================
`default_nettype none

module carry_skip_adder_16 (
    input  wire [15:0] a,
    input  wire [15:0] b,
    output wire [15:0] sum
);

    // -------------------------------------------------------------------------
    // Bit-level propagate and generate signals
    // p[k] = a[k] ^ b[k]  — carry propagates through bit k when p[k]=1
    // g[k] = a[k] & b[k]  — carry generated at bit k when g[k]=1
    // -------------------------------------------------------------------------
    wire [15:0] p;
    wire [15:0] g;

    assign p[ 0] = a[ 0] ^ b[ 0];
    assign p[ 1] = a[ 1] ^ b[ 1];
    assign p[ 2] = a[ 2] ^ b[ 2];
    assign p[ 3] = a[ 3] ^ b[ 3];
    assign p[ 4] = a[ 4] ^ b[ 4];
    assign p[ 5] = a[ 5] ^ b[ 5];
    assign p[ 6] = a[ 6] ^ b[ 6];
    assign p[ 7] = a[ 7] ^ b[ 7];
    assign p[ 8] = a[ 8] ^ b[ 8];
    assign p[ 9] = a[ 9] ^ b[ 9];
    assign p[10] = a[10] ^ b[10];
    assign p[11] = a[11] ^ b[11];
    assign p[12] = a[12] ^ b[12];
    assign p[13] = a[13] ^ b[13];
    assign p[14] = a[14] ^ b[14];
    assign p[15] = a[15] ^ b[15];

    assign g[ 0] = a[ 0] & b[ 0];
    assign g[ 1] = a[ 1] & b[ 1];
    assign g[ 2] = a[ 2] & b[ 2];
    assign g[ 3] = a[ 3] & b[ 3];
    assign g[ 4] = a[ 4] & b[ 4];
    assign g[ 5] = a[ 5] & b[ 5];
    assign g[ 6] = a[ 6] & b[ 6];
    assign g[ 7] = a[ 7] & b[ 7];
    assign g[ 8] = a[ 8] & b[ 8];
    assign g[ 9] = a[ 9] & b[ 9];
    assign g[10] = a[10] & b[10];
    assign g[11] = a[11] & b[11];
    assign g[12] = a[12] & b[12];
    assign g[13] = a[13] & b[13];
    assign g[14] = a[14] & b[14];
    assign g[15] = a[15] & b[15];

    // -------------------------------------------------------------------------
    // Block-level propagate signals
    // P_block = AND of all bit-level propagates in the block
    // When P_block=1, carry skips the entire block unchanged.
    // -------------------------------------------------------------------------
    wire P_blk0 = p[0]  & p[1]  & p[2]  & p[3];   // block 0: bits  3:0
    wire P_blk1 = p[4]  & p[5]  & p[6]  & p[7];   // block 1: bits  7:4
    wire P_blk2 = p[8]  & p[9]  & p[10] & p[11];  // block 2: bits 11:8
    wire P_blk3 = p[12] & p[13] & p[14] & p[15];  // block 3: bits 15:12

    // -------------------------------------------------------------------------
    // Ripple carry computation within each block
    // c_in_blkN is the carry entering block N
    // -------------------------------------------------------------------------

    // Block 0: bits 3:0, carry-in = 0
    wire c_in_blk0;
    assign c_in_blk0 = 1'b0;

    wire c0_1 = g[0] | (p[0] & c_in_blk0);
    wire c0_2 = g[1] | (p[1] & c0_1);
    wire c0_3 = g[2] | (p[2] & c0_2);
    wire c_ripple_blk0 = g[3] | (p[3] & c0_3);  // ripple carry out of block 0

    // Carry-skip mux for block 0:
    // If P_blk0=1, carry skips: c_out_blk0 = c_in_blk0 (= 0)
    // If P_blk0=0, carry ripples: c_out_blk0 = c_ripple_blk0
    wire c_out_blk0 = P_blk0 ? c_in_blk0 : c_ripple_blk0;

    // Block 1: bits 7:4, carry-in = c_out_blk0
    wire c_in_blk1;
    assign c_in_blk1 = c_out_blk0;

    wire c1_1 = g[4] | (p[4] & c_in_blk1);
    wire c1_2 = g[5] | (p[5] & c1_1);
    wire c1_3 = g[6] | (p[6] & c1_2);
    wire c_ripple_blk1 = g[7] | (p[7] & c1_3);  // ripple carry out of block 1

    // Carry-skip mux for block 1
    wire c_out_blk1 = P_blk1 ? c_in_blk1 : c_ripple_blk1;

    // Block 2: bits 11:8, carry-in = c_out_blk1
    wire c_in_blk2;
    assign c_in_blk2 = c_out_blk1;

    wire c2_1 = g[8]  | (p[8]  & c_in_blk2);
    wire c2_2 = g[9]  | (p[9]  & c2_1);
    wire c2_3 = g[10] | (p[10] & c2_2);
    wire c_ripple_blk2 = g[11] | (p[11] & c2_3);  // ripple carry out of block 2

    // Carry-skip mux for block 2
    wire c_out_blk2 = P_blk2 ? c_in_blk2 : c_ripple_blk2;

    // Block 3: bits 15:12, carry-in = c_out_blk2
    wire c_in_blk3;
    assign c_in_blk3 = c_out_blk2;

    wire c3_1 = g[12] | (p[12] & c_in_blk3);
    wire c3_2 = g[13] | (p[13] & c3_1);
    wire c3_3 = g[14] | (p[14] & c3_2);
    // c_ripple_blk3 = carry-out of bit 15 (dropped for 16-bit wrap)

    // Carry-skip mux for block 3 (carry-out is dropped — 16-bit wrap)
    // (P_blk3 not needed since we discard carry-out)

    // -------------------------------------------------------------------------
    // Carry signals at each bit position
    // c[k] = carry INTO bit k
    // -------------------------------------------------------------------------
    wire c_b0  = c_in_blk0;       // carry into bit  0 = 0
    wire c_b1  = c0_1;             // carry into bit  1
    wire c_b2  = c0_2;             // carry into bit  2
    wire c_b3  = c0_3;             // carry into bit  3

    // Carry into bit 4 = c_out_blk0 (skip-adjusted)
    wire c_b4  = c_out_blk0;
    wire c_b5  = c1_1;             // carry into bit  5 (ripple within blk1)
    wire c_b6  = c1_2;             // carry into bit  6
    wire c_b7  = c1_3;             // carry into bit  7

    // Carry into bit 8 = c_out_blk1 (skip-adjusted)
    wire c_b8  = c_out_blk1;
    wire c_b9  = c2_1;             // carry into bit  9 (ripple within blk2)
    wire c_b10 = c2_2;             // carry into bit 10
    wire c_b11 = c2_3;             // carry into bit 11

    // Carry into bit 12 = c_out_blk2 (skip-adjusted)
    wire c_b12 = c_out_blk2;
    wire c_b13 = c3_1;             // carry into bit 13 (ripple within blk3)
    wire c_b14 = c3_2;             // carry into bit 14
    wire c_b15 = c3_3;             // carry into bit 15

    // -------------------------------------------------------------------------
    // Sum bits: s[k] = p[k] ^ c[k]
    // -------------------------------------------------------------------------
    assign sum[ 0] = p[ 0] ^ c_b0;
    assign sum[ 1] = p[ 1] ^ c_b1;
    assign sum[ 2] = p[ 2] ^ c_b2;
    assign sum[ 3] = p[ 3] ^ c_b3;
    assign sum[ 4] = p[ 4] ^ c_b4;
    assign sum[ 5] = p[ 5] ^ c_b5;
    assign sum[ 6] = p[ 6] ^ c_b6;
    assign sum[ 7] = p[ 7] ^ c_b7;
    assign sum[ 8] = p[ 8] ^ c_b8;
    assign sum[ 9] = p[ 9] ^ c_b9;
    assign sum[10] = p[10] ^ c_b10;
    assign sum[11] = p[11] ^ c_b11;
    assign sum[12] = p[12] ^ c_b12;
    assign sum[13] = p[13] ^ c_b13;
    assign sum[14] = p[14] ^ c_b14;
    assign sum[15] = p[15] ^ c_b15;

endmodule
