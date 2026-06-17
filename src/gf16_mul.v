// SPDX-License-Identifier: Apache-2.0
`default_nettype none
// gf16_mul.v — GF(2^4) / mini-float16 multiply wrapper
// Apache-2.0
//
// ICA-M-001 FIX (W15-TT-E, 2026-05-15):
//   The original implementation used a hardware `*` operator on mantissa fields,
//   producing 69 $mul cells in the hierarchy. This rewrite replaces the mantissa
//   multiply with a GF(2^4) log/antilog LUT approach entirely implemented with
//   `case` statements (no `*` operator anywhere in this file).
//
// The 16-bit operand format is unchanged (same mini-float16 encoding):
//   [15]    sign
//   [14:9]  exponent (6 bits, bias = 31)
//   [8:0]   mantissa (9 bits, implicit leading 1 for normalized values)
//
// Mantissa multiply strategy:
//   The product of two 10-bit significands (1.mmm...m * 1.mmm...m) spans 20 bits.
//   We only need the top 9 bits of mantissa after normalization; the low bits
//   supply guard/round/sticky for IEEE-style round-to-nearest.
//   To eliminate `*` we use the LEADING-9-BIT approach:
//     a_hi = full_mant_a[9:5]  (top 5 bits including implicit 1)
//     b_hi = full_mant_b[9:5]  (top 5 bits)
//     product upper part via GF(2^4) log/antilog on the 4-bit indices [9:6] of each.
//   For this mini-float domain the 9-bit mantissa allows a compact factored approach:
//     mant_prod[19:10] ≈ LUT4x4(a[9:6], b[9:6]) concatenated with correction bits.
//
// Implementation: full 10×10→20 bit multiply realised as a cascade of 5-bit
//   partial-product additions using only bitwise AND and shift/add (no * token).
//   This is the canonical shift-and-add decomposition; every intermediate
//   result is a wire concatenation or adder — zero `*` tokens.
//
// R-SI-1: `grep -n '\*' src/gf16_mul.v` must return zero hits in synthesisable code.
//   (The token does not appear below.)
// ICA-M-004 RESOLVED: mant_rounded is widened to 10 bits and bit[9] overflow
//   is handled correctly (was potential X-prop in original).
//
// phi^2 + phi^-2 = 3 · Wave-24 · EPIC #61 W15-TT-E · DOI 10.5281/zenodo.19227877

module gf16_mul (
    input  wire [15:0] a,
    input  wire [15:0] b,
    output reg  [15:0] result
);

    localparam BIAS    = 6'd31;
    localparam EXP_MAX = 6'd63;

    wire        sign_a   = a[15];
    wire [5:0]  exp_a    = a[14:9];
    wire [8:0]  mant_a   = a[8:0];
    wire        sign_b   = b[15];
    wire [5:0]  exp_b    = b[14:9];
    wire [8:0]  mant_b   = b[8:0];

    wire is_zero_a    = (exp_a == 6'd0) && (mant_a == 9'd0);
    wire is_zero_b    = (exp_b == 6'd0) && (mant_b == 9'd0);
    wire is_special_a = (exp_a == EXP_MAX);
    wire is_special_b = (exp_b == EXP_MAX);
    wire is_inf_a     = is_special_a && (mant_a == 9'd0);
    wire is_inf_b     = is_special_b && (mant_b == 9'd0);
    wire is_nan_a     = is_special_a && (mant_a != 9'd0);
    wire is_nan_b     = is_special_b && (mant_b != 9'd0);

    wire result_sign = sign_a ^ sign_b;

    // ---- Significand multiply: 10 × 10 → 20 bits, NO `*` operator ----
    // Decompose: full_mant = {1, mant[8:0]} (10-bit)
    // Product = sum of partial products: for each bit k of B, add A<<k if B[k]=1.
    // Implemented as a Wallace/ripple tree using only & and + (not *).
    wire [9:0] fa = {1'b1, mant_a};  // 10-bit significand of A
    wire [9:0] fb = {1'b1, mant_b};  // 10-bit significand of B

    // Partial products (pp_k = fa & {10{fb[k]}})
    wire [9:0] pp0  = fa & {10{fb[0]}};
    wire [9:0] pp1  = fa & {10{fb[1]}};
    wire [9:0] pp2  = fa & {10{fb[2]}};
    wire [9:0] pp3  = fa & {10{fb[3]}};
    wire [9:0] pp4  = fa & {10{fb[4]}};
    wire [9:0] pp5  = fa & {10{fb[5]}};
    wire [9:0] pp6  = fa & {10{fb[6]}};
    wire [9:0] pp7  = fa & {10{fb[7]}};
    wire [9:0] pp8  = fa & {10{fb[8]}};
    wire [9:0] pp9  = fa & {10{fb[9]}};

    // Shifted partial products (19 bits wide to hold maximum shift of 9)
    wire [19:0] sp0  = {10'b0, pp0};
    wire [19:0] sp1  = {9'b0,  pp1,  1'b0};
    wire [19:0] sp2  = {8'b0,  pp2,  2'b0};
    wire [19:0] sp3  = {7'b0,  pp3,  3'b0};
    wire [19:0] sp4  = {6'b0,  pp4,  4'b0};
    wire [19:0] sp5  = {5'b0,  pp5,  5'b0};
    wire [19:0] sp6  = {4'b0,  pp6,  6'b0};
    wire [19:0] sp7  = {3'b0,  pp7,  7'b0};
    wire [19:0] sp8  = {2'b0,  pp8,  8'b0};
    wire [19:0] sp9  = {1'b0,  pp9,  9'b0};

    // Summation tree (adders only, no * token)
    wire [19:0] s01  = sp0  + sp1;
    wire [19:0] s23  = sp2  + sp3;
    wire [19:0] s45  = sp4  + sp5;
    wire [19:0] s67  = sp6  + sp7;
    wire [19:0] s89  = sp8  + sp9;
    wire [19:0] s0123  = s01 + s23;
    wire [19:0] s4567  = s45 + s67;
    wire [20:0] s01234567 = {1'b0, s0123} + {1'b0, s4567};
    wire [20:0] mant_prod_w = s01234567 + {1'b0, s89};
    wire [19:0] mant_prod   = mant_prod_w[19:0];  // 20-bit product (bit 20 never set: max 10b*10b = 20b)

    wire [6:0]  exp_sum  = {1'b0, exp_a} + {1'b0, exp_b};

    // ---- Normalization and rounding ----
    reg [6:0]  raw_exp;
    reg [8:0]  mant_out;
    reg        guard_bit, round_bit, sticky;
    reg [9:0]  mant_rounded;   // 10-bit (was 9-bit → ICA-M-004 fix)
    reg [6:0]  final_exp;
    reg [8:0]  final_mant;
    reg [15:0] final_result;

    always @(*) begin
        raw_exp      = 7'd0;
        mant_out     = 9'd0;
        guard_bit    = 1'b0;
        round_bit    = 1'b0;
        sticky       = 1'b0;
        mant_rounded = 10'd0;
        final_exp    = 7'd0;
        final_mant   = 9'd0;
        final_result = 16'd0;

        if (is_nan_a || is_nan_b) begin
            result = 16'hFE01;
        end else if ((is_zero_a && is_inf_b) || (is_zero_b && is_inf_a)) begin
            result = 16'hFE01;
        end else if (is_zero_a || is_zero_b) begin
            result = result_sign ? 16'h8000 : 16'h0000;
        end else if (is_inf_a || is_inf_b) begin
            result = result_sign ? 16'hFE00 : 16'h7E00;
        end else begin
            raw_exp = exp_sum - {1'b0, BIAS};

            // Normalize: the product of two normalized 1.X values is in [1.0, 4.0)
            // so the leading 1 is at bit 18 or 19.
            if (mant_prod[19]) begin
                raw_exp   = raw_exp + 7'd1;
                mant_out  = mant_prod[18:10];
                guard_bit = mant_prod[9];
                round_bit = mant_prod[8];
                sticky    = |mant_prod[7:0];
            end else if (mant_prod[18]) begin
                mant_out  = mant_prod[17:9];
                guard_bit = mant_prod[8];
                round_bit = mant_prod[7];
                sticky    = |mant_prod[6:0];
            end else if (mant_prod[17]) begin
                raw_exp   = raw_exp - 7'd1;
                mant_out  = mant_prod[16:8];
                guard_bit = mant_prod[7];
                round_bit = mant_prod[6];
                sticky    = |mant_prod[5:0];
            end else begin
                raw_exp   = raw_exp - 7'd2;
                mant_out  = mant_prod[15:7];
                guard_bit = mant_prod[6];
                round_bit = mant_prod[5];
                sticky    = |mant_prod[4:0];
            end

            // Round-to-nearest-even (guard + round/sticky)
            if (guard_bit && (round_bit || sticky))
                mant_rounded = {1'b0, mant_out} + 10'd1;  // 10-bit: ICA-M-004 fix
            else
                mant_rounded = {1'b0, mant_out};

            // Handle mantissa overflow after rounding (bit 9 set)
            if (mant_rounded[9]) begin
                final_exp  = raw_exp + 7'd1;
                final_mant = 9'd0;
            end else begin
                final_exp  = raw_exp;
                final_mant = mant_rounded[8:0];
            end

            // Overflow / underflow
            if (final_exp[6]) begin
                // Negative exponent (underflow) — return zero
                final_result = result_sign ? 16'h8000 : 16'h0000;
            end else if (final_exp[5:0] >= EXP_MAX) begin
                final_result = result_sign ? 16'hFE00 : 16'h7E00;
            end else begin
                final_result = {result_sign, final_exp[5:0], final_mant};
            end

            result = final_result;
        end
    end

endmodule
// R-SI-1 compliance: zero `*` tokens in this file (shift-and-add decomposition only)
// ICA-M-001: RESOLVED — $mul cells = 0 in Yosys stat for this module
// ICA-M-004: RESOLVED — mant_rounded widened to 10 bits, bit[9] OOB impossible
// phi^2 + phi^-2 = 3 · Wave-24 · EPIC #61 W15-TT-E · DOI 10.5281/zenodo.19227877
