/* Booth radix-4 10×10 unsigned multiplier · Charter Rule 2 compliant · Wave-24 RVR-016 dry-run */
//
// ============================================================================
// MODULE: gf16_mul_booth
// DESCRIPTION: 10×10 unsigned integer multiplier using Booth radix-4 encoding
//              with Carry-Save Adder (CSA) tree accumulation.
//              ZERO arithmetic `*` operators — fully synthesisable shift+add.
//              Charter Rule 2: NO `*` in synthesisable RTL. ✅
//
// Anchor: phi^2 + phi^-2 = 3 · Wave-24 RVR-016 dry-run · DOI 10.5281/zenodo.19227877
// ============================================================================
//
// ============================================================================
// MATH DERIVATION: BOOTH RADIX-4 ENCODING (≥20 lines)
// ============================================================================
//
// 1. CLASSICAL BOOTH RECODING (radix-2)
//    For an N-bit multiplier B, write B = Σ_{i=0}^{N-1} b_i · 2^i
//    Rewrite each bit-pair as a signed digit: d_i = b_{i-1} - 2·b_i + b_{i+1}
//    where b_{-1} = 0 (implicit). Each d_i ∈ {-1, 0, +1}.
//    This halves the number of partial products vs. standard add-and-shift.
//
// 2. RADIX-4 EXTENSION (Modified Booth Encoding, MBE)
//    Group multiplier B into overlapping 3-bit windows:
//      Window k covers bits {b[2k+1], b[2k], b[2k-1]} (b[-1]=0 implicit).
//    Encoding table per window (b2, b1, b0) = sel[2:0]:
//      000 →  0·A    (zero)
//      001 → +1·A
//      010 → +1·A
//      011 → +2·A    (A shifted left 1)
//      100 → -2·A    (two's complement of 2A)
//      101 → -1·A    (two's complement of A)
//      110 → -1·A
//      111 →  0·A    (zero)
//    Result: ceil(N/2) signed partial products each at bit position 2k.
//
// 3. UNSIGNED OPERAND TREATMENT
//    Standard MBE is defined for two's-complement (signed) numbers.
//    For unsigned N-bit operands, extend both A and B with a zero sign bit
//    to make them (N+1)-bit non-negative signed values:
//      A_ext = {1'b0, a}   →  11-bit, value = a  (sign bit = 0)
//      B_ext = {1'b0, b}   →  11-bit, value = b  (sign bit = 0)
//    The 11×11 signed Booth product equals the 10×10 unsigned product
//    in bits [19:0] because both values are non-negative.
//
// 4. WINDOW ASSIGNMENT for 11-bit B_ext (bits [10:0], B_ext[10]=0)
//    We need ceil(11/2) = 6 windows, but windows at k=5 would read
//    B_ext[11] which is undefined; however since B_ext[10]=0 and we
//    use an even number of bits (11 bits → pad to 12 with one more 0):
//      B_pad = {1'b0, B_ext} = {2'b00, b}  (12 bits, bits [11:0])
//    Windows k=0..5:
//      k=0: {B_pad[1], B_pad[0], 1'b0}
//      k=1: {B_pad[3], B_pad[2], B_pad[1]}
//      k=2: {B_pad[5], B_pad[4], B_pad[3]}
//      k=3: {B_pad[7], B_pad[6], B_pad[5]}
//      k=4: {B_pad[9], B_pad[8], B_pad[7]}
//      k=5: {B_pad[11], B_pad[10], B_pad[9]} = {0, 0, b[9]} → sel ∈ {000,001}
//    Window k=5: B_pad[11]=B_pad[10]=0, so sel[2:1]=00 → either 0·A or +1·A.
//    We include this 6th partial product (pp5 = (b[9] ? A_ext : 0) << 10).
//
// 5. PARTIAL PRODUCT GENERATION
//    For each k ∈ {0..5}:
//      raw_k = booth_mux(sel_k, multiples_of_A)  — 22-bit signed value
//      pp_k  = sign_extend(raw_k, 32) << (2k)    — aligned 32-bit value
//    The sign extension propagates the two's-complement partial product
//    correctly into the full-width accumulator.
//
// 6. CSA (CARRY-SAVE ADDER) REDUCTION
//    6 partial products reduced with CSA tree:
//      Level 1: CSA(pp0, pp1, pp2)         → s1, c1
//      Level 2: CSA(pp3, pp4, pp5)         → s2, c2
//      Level 3: CSA(s1,  c1,  s2)          → s3, c3
//      Level 4: CSA(s3,  c3,  c2)          → s4, c4
//    Final:   p_full = s4 + c4  (ripple-carry adder)
//    The CSA tree reduces 6 operands to 2 in 4 levels, then one final add.
//
// 7. RESULT EXTRACTION
//    p[19:0] = p_full[19:0] — lower 20 bits are the exact unsigned product
//    for any a,b ∈ [0, 1023] (max product = 1023² = 1046529 < 2^20).
//
// ============================================================================

`default_nettype none

module gf16_mul_booth (
    input  wire [9:0] a,   // 10-bit unsigned multiplicand
    input  wire [9:0] b,   // 10-bit unsigned multiplier
    output wire [19:0] p   // 20-bit unsigned product
);

    // -----------------------------------------------------------------------
    // Zero-extend A to 11 bits (non-negative signed representation)
    // A_ext[10:0] = {0, a[9:0]}
    // -----------------------------------------------------------------------
    wire [10:0] A_ext = {1'b0, a};

    // -----------------------------------------------------------------------
    // B zero-extended to 12 bits for window extraction:
    //   B_pad[11:0] = {00, b[9:0]}
    // -----------------------------------------------------------------------
    wire [11:0] B_pad = {2'b00, b};

    // -----------------------------------------------------------------------
    // Multiples of A_ext, sign-extended to 22 bits.
    // A_ext[10]=0 so all sign extensions are zero-extensions.
    // m_pos1 = +A   m_pos2 = +2A   m_neg1 = -A   m_neg2 = -2A
    // -----------------------------------------------------------------------
    wire [21:0] m_0    = 22'd0;
    wire [21:0] m_pos1 = {11'd0, a};            // +A  zero-extended
    wire [21:0] m_pos2 = {10'd0, a, 1'b0};      // +2A zero-extended
    wire [21:0] m_neg1 = (~m_pos1) + 22'd1;    // -A  two's complement
    wire [21:0] m_neg2 = (~m_pos2) + 22'd1;    // -2A two's complement

    // -----------------------------------------------------------------------
    // MBE window selectors (3 bits each from B_pad)
    // -----------------------------------------------------------------------
    wire [2:0] sel0 = {B_pad[1],  B_pad[0],  1'b0};
    wire [2:0] sel1 = {B_pad[3],  B_pad[2],  B_pad[1]};
    wire [2:0] sel2 = {B_pad[5],  B_pad[4],  B_pad[3]};
    wire [2:0] sel3 = {B_pad[7],  B_pad[6],  B_pad[5]};
    wire [2:0] sel4 = {B_pad[9],  B_pad[8],  B_pad[7]};
    wire [2:0] sel5 = {B_pad[11], B_pad[10], B_pad[9]};   // = {0,0,b[9]}

    // -----------------------------------------------------------------------
    // Booth MBE multiplexer (combinational function)
    // -----------------------------------------------------------------------
    function [21:0] booth_mux;
        input [2:0]  sel;
        input [21:0] p0, p1, p2, n1, n2;
        case (sel)
            3'b000: booth_mux = p0;
            3'b001: booth_mux = p1;
            3'b010: booth_mux = p1;
            3'b011: booth_mux = p2;
            3'b100: booth_mux = n2;
            3'b101: booth_mux = n1;
            3'b110: booth_mux = n1;
            3'b111: booth_mux = p0;
            default: booth_mux = p0;
        endcase
    endfunction

    wire [21:0] raw0 = booth_mux(sel0, m_0, m_pos1, m_pos2, m_neg1, m_neg2);
    wire [21:0] raw1 = booth_mux(sel1, m_0, m_pos1, m_pos2, m_neg1, m_neg2);
    wire [21:0] raw2 = booth_mux(sel2, m_0, m_pos1, m_pos2, m_neg1, m_neg2);
    wire [21:0] raw3 = booth_mux(sel3, m_0, m_pos1, m_pos2, m_neg1, m_neg2);
    wire [21:0] raw4 = booth_mux(sel4, m_0, m_pos1, m_pos2, m_neg1, m_neg2);
    wire [21:0] raw5 = booth_mux(sel5, m_0, m_pos1, m_pos2, m_neg1, m_neg2);

    // -----------------------------------------------------------------------
    // Sign-extend each raw partial product to 32 bits, then shift by 2k.
    //
    // 32 bits is sufficient:
    //   max raw magnitude = 2*A = 2046  → 12 bits unsigned, 13 bits signed
    //   shifted by 10 (k=5) → 23 bits
    //   sign-extended to 32 → safe for all cases
    // -----------------------------------------------------------------------
    wire [31:0] pp0 = {{10{raw0[21]}}, raw0};                    // << 0
    wire [31:0] pp1 = {{8{raw1[21]}},  raw1, 2'b00};             // << 2
    wire [31:0] pp2 = {{6{raw2[21]}},  raw2, 4'b0000};           // << 4
    wire [31:0] pp3 = {{4{raw3[21]}},  raw3, 6'b000000};         // << 6
    wire [31:0] pp4 = {{2{raw4[21]}},  raw4, 8'b00000000};       // << 8
    wire [31:0] pp5 = {raw5[21],       raw5, 10'b0000000000};    // << 10

    // -----------------------------------------------------------------------
    // CSA reduction tree: 6 → 4 → 2 operands
    //
    // A CSA takes three 32-bit inputs (x,y,z) and produces:
    //   sum   = x ^ y ^ z         (bit-wise XOR)
    //   carry = {(maj(x,y,z)), 0} (majority function, shifted left 1)
    //
    // Level 1a: CSA(pp0, pp1, pp2) → s1, c1
    // Level 1b: CSA(pp3, pp4, pp5) → s2, c2
    // Level 2:  CSA(s1,  c1,  s2)  → s3, c3
    // Level 3:  CSA(s3,  c3,  c2)  → s4, c4
    // -----------------------------------------------------------------------

    // Level 1a
    wire [31:0] s1 = pp0 ^ pp1 ^ pp2;
    wire [31:0] c1 = {((pp0 & pp1) | (pp1 & pp2) | (pp0 & pp2)), 1'b0};

    // Level 1b
    wire [31:0] s2 = pp3 ^ pp4 ^ pp5;
    wire [31:0] c2 = {((pp3 & pp4) | (pp4 & pp5) | (pp3 & pp5)), 1'b0};

    // Level 2
    wire [31:0] s3 = s1 ^ c1 ^ s2;
    wire [31:0] c3 = {((s1 & c1) | (c1 & s2) | (s1 & s2)), 1'b0};

    // Level 3
    wire [31:0] s4 = s3 ^ c3 ^ c2;
    wire [31:0] c4 = {((s3 & c3) | (c3 & c2) | (s3 & c2)), 1'b0};

    // Final addition
    wire [32:0] p_full = {1'b0, s4} + {1'b0, c4};

    // Extract lower 20 bits (exact unsigned product for 10-bit operands)
    assign p = p_full[19:0];

endmodule

`default_nettype wire
// ============================================================================
// END gf16_mul_booth
// phi^2 + phi^-2 = 3 · Wave-24 RVR-016 dry-run · DOI 10.5281/zenodo.19227877
// ============================================================================
