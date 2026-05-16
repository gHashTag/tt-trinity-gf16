// SPDX-License-Identifier: Apache-2.0
// gf16_mul_booth2.v — Lane L-Z06: Radix-4 Modified Booth-2 4×4→8 multiplier
// Pure Verilog-2005, R-SI-1 clean (zero `*` operators anywhere)
//
// ==========================================================================
// Algorithm — Modified Booth Radix-4 for unsigned 4-bit operands
// ==========================================================================
//
// For unsigned b[3:0] we construct an augmented word:
//   b_ext = { b[3:0], 1'b0 }  (5 bits, LSB appended as 0)
//
// Three Booth digits are extracted:
//   dig0 = b_ext[2:0]   weight  1 (2^0)
//   dig1 = b_ext[4:2]   weight  4 (2^2)
//   dig2 = {2'b0, b[3]} weight 16 (2^4)  — trivial: always 0 or +1
//
// Each digit is decoded via the Modified Booth table:
//   000 → +0    001 → +A    010 → +A    011 → +2A
//   100 → −2A   101 → −A    110 → −A    111 → +0
//
// dig2 is the zero-extended MSB of b; its Booth value is 0 or +1,
// giving PP2 = b[3] ? A<<4 : 0.  This correction term compensates
// for the implicit sign bit that appears when b[3]=1 in radix-4 Booth.
//
// Total partial products: PP0 (8-bit, weight 1) +
//                         PP1 (8-bit, weight 4) +
//                         PP2 (8-bit, weight 16)
//   product = PP0 + PP1 + PP2  (mod 2^8, always exact for 4×4)
//
// Cell budget estimate:
//   Booth decode (dig0, dig1):  ~8 cells
//   PP selection muxes (×2):   ~16 cells
//   Negation logic  (×2):      ~10 cells
//   PP2 AND masking:            ~4 cells
//   8-bit adder tree:           ~12 cells
//   Total:                     ~50 cells  (vs ~75 for gf16_mul *)
//
// Critical path: Booth decode → mux → negate → add ≈ 5 gate levels
// ==========================================================================

`default_nettype none

module gf16_mul_booth2 (
    input  wire [3:0] a,       // 4-bit unsigned multiplicand
    input  wire [3:0] b,       // 4-bit unsigned multiplier
    output wire [7:0] product  // 8-bit unsigned product = a × b
);

    // ------------------------------------------------------------------
    // Step 1: Build augmented multiplier word
    //   b_ext[4:0] = { b[3:0], 1'b0 }
    // ------------------------------------------------------------------
    wire [4:0] b_ext;
    assign b_ext = {b[3:0], 1'b0};

    // Booth digits
    wire [2:0] dig0 = b_ext[2:0];    // weight 2^0 = 1
    wire [2:0] dig1 = b_ext[4:2];    // weight 2^2 = 4
    // dig2 = {0, 0, b[3]}  → handled as scalar b[3]

    // ------------------------------------------------------------------
    // Step 2: Booth decode for dig0 and dig1
    //
    //   neg   = 1 when the partial product is negated (digit[2] = 1)
    //   sel2  = 1 when select 2A (else A or 0)
    //   sel0  = 1 when select 0  (zeros the PP)
    //
    //   000 → neg=0 sel2=0 sel0=1
    //   001 → neg=0 sel2=0 sel0=0  (+A)
    //   010 → neg=0 sel2=0 sel0=0  (+A)
    //   011 → neg=0 sel2=1 sel0=0  (+2A)
    //   100 → neg=1 sel2=1 sel0=0  (-2A)
    //   101 → neg=1 sel2=0 sel0=0  (-A)
    //   110 → neg=1 sel2=0 sel0=0  (-A)
    //   111 → neg=0 sel2=0 sel0=1  (+0)
    // ------------------------------------------------------------------

    // Digit 0 decode
    wire neg0   =  dig0[2];
    wire sel2_0 = (~dig0[2] &  dig0[1] &  dig0[0]) |
                  ( dig0[2] & ~dig0[1] & ~dig0[0]);
    wire sel0_0 = (~dig0[2] & ~dig0[1] & ~dig0[0]) |
                  ( dig0[2] &  dig0[1] &  dig0[0]);

    // Digit 1 decode
    wire neg1   =  dig1[2];
    wire sel2_1 = (~dig1[2] &  dig1[1] &  dig1[0]) |
                  ( dig1[2] & ~dig1[1] & ~dig1[0]);
    wire sel0_1 = (~dig1[2] & ~dig1[1] & ~dig1[0]) |
                  ( dig1[2] &  dig1[1] &  dig1[0]);

    // ------------------------------------------------------------------
    // Step 3: Select |PP| magnitudes (unsigned)
    //   mag = sel0 ? 0 : (sel2 ? {a,1'b0} : a)  (5 bits max)
    // ------------------------------------------------------------------
    wire [4:0] a_x1 = {1'b0, a};        // a zero-extended to 5 bits
    wire [4:0] a_x2 = {a, 1'b0};        // 2a (a << 1), 5 bits (max 30)

    // PP0 magnitude (5 bits)
    wire [4:0] mag0_sel = sel2_0 ? a_x2 : a_x1;
    wire [4:0] mag0     = sel0_0 ? 5'b0 : mag0_sel;

    // PP1 magnitude (5 bits)
    wire [4:0] mag1_sel = sel2_1 ? a_x2 : a_x1;
    wire [4:0] mag1     = sel0_1 ? 5'b0 : mag1_sel;

    // ------------------------------------------------------------------
    // Step 4: Apply sign via two's complement negation
    //   PP0 (8-bit, weight 1): sign-extend mag0 then negate if neg0
    //   PP1 (8-bit, weight 4): sign-extend mag1 << 2 then negate if neg1
    //
    //   All intermediate values fit in 8 bits (unsigned max: 2A<<2 = 60)
    // ------------------------------------------------------------------

    // PP0: 0-extend 5-bit mag to 8 bits; negate if neg0
    wire [7:0] pp0_pos = {3'b000, mag0};
    wire [7:0] pp0_neg = ~pp0_pos + 8'd1;
    wire [7:0] pp0     = neg0 ? pp0_neg : pp0_pos;

    // PP1: shift mag1 left by 2 (weight 4), 0-extend to 8 bits; negate if neg1
    //   {0, mag1[4:0], 00} is at most {0, 11110, 00} = 0b01111000 = 0x78 = 120
    wire [7:0] pp1_pos = {1'b0, mag1, 2'b00};
    wire [7:0] pp1_neg = ~pp1_pos + 8'd1;
    wire [7:0] pp1     = neg1 ? pp1_neg : pp1_pos;

    // ------------------------------------------------------------------
    // Step 5: PP2 — trivial correction for unsigned extension
    //   dig2 = {0,0,b[3]}: Booth value is 0 or +1
    //   PP2 = b[3] ? (a << 4) : 0  (weight 16 = 2^4)
    //   a << 4 = {a[3:0], 4'b0}  (upper nibble of 8-bit result)
    // ------------------------------------------------------------------
    wire [7:0] pp2 = b[3] ? {a[3:0], 4'b0000} : 8'b0;

    // ------------------------------------------------------------------
    // Step 6: Sum all three partial products
    //   product = (pp0 + pp1 + pp2) mod 256
    //   The three-operand 8-bit addition gives exactly a*b[7:0]
    // ------------------------------------------------------------------
    assign product = pp0 + pp1 + pp2;

endmodule
`default_nettype wire
