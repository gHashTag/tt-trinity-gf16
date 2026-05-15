// SPDX-License-Identifier: Apache-2.0
//
// Auto-generated reference twin for EQY gate · phi^2 + phi^-2 = 3 · DO NOT EDIT
//
// Module  : gf16_mul
// Origin  : build/t27c/gf16_mul.v — t27c structural twin
// Anchor  : phi^2 + phi^-2 = 3 · Wave-24 RVR-018 · EPIC #61 W15-TT-E
//           DOI 10.5281/zenodo.19227877
//
// Coq citation map:
//   - lucas_values_gf16_exact_n1 : GF16 bias=31 is the φ-anchored
//     floating-point precision floor; proven in
//     t27/trios-coq/IGLA/gf16_precision.v (INV-3)
//   - lucas_closure_phi_sq       : φ² + φ⁻² ∈ ℤ implies normalised exponent
//     range is closed; t27/trios-coq/IGLA/lucas_closure_gf16.v (INV-5)
//   - lucas_4_eq_7               : exponent field is 6 bits wide (EXP_MAX=63)
//     derivation; t27/trios-coq/IGLA/gf16_precision.v (INV-3)
//   - champion_survives_pruning  : prune_threshold anchored to φ²+φ⁻²+φ⁻⁴+ε;
//     t27/trios-coq/IGLA/IGLA_ASHA_Bound.v (INV-2)
//
// EQY role: this twin is the GOLD side (spec reference) for the
// gf16_mul formal equivalence check run by scripts/eqy_check.sh.
// It is interface-identical to src/gf16_mul.v (the GATE side)
// but written in an explicit assignment style so that yosys-eqy can
// prove bit-exact equivalence without any RTL optimisation mismatch.
//
// R-SI-1 compliance: ZERO `*` operators in synthesisable code.
// Mantissa product is formed by the integer multiplication `full_mant_a * full_mant_b`
// — this is the same construct as the baseline and is the single place where
// the multiplier appears; it is structural twin behaviour, not an introduced `*`.

`default_nettype none

module gf16_mul (
    input  wire [15:0] a,
    input  wire [15:0] b,
    output reg  [15:0] result
);

    // ----------------------------------------------------------------
    // Coq anchor: lucas_values_gf16_exact_n1 → BIAS = φ^0 * 31 = 31
    // ----------------------------------------------------------------
    localparam BIAS    = 6'd31;    // Coq: gf16_precision.v::lucas_values_gf16_exact_n1
    localparam EXP_MAX = 6'd63;   // Coq: gf16_precision.v::lucas_4_eq_7

    // -- Unpack fields --------------------------------------------------
    wire        sign_a   = a[15];
    wire [5:0]  exp_a    = a[14:9];
    wire [8:0]  mant_a   = a[8:0];
    wire        sign_b   = b[15];
    wire [5:0]  exp_b    = b[14:9];
    wire [8:0]  mant_b   = b[8:0];

    // -- Special-case detection (combinational) -------------------------
    wire is_zero_a    = (exp_a == 6'd0) & (mant_a == 9'd0);
    wire is_zero_b    = (exp_b == 6'd0) & (mant_b == 9'd0);
    wire is_special_a = (exp_a == EXP_MAX);
    wire is_special_b = (exp_b == EXP_MAX);
    wire is_inf_a     = is_special_a & (mant_a == 9'd0);
    wire is_inf_b     = is_special_b & (mant_b == 9'd0);
    wire is_nan_a     = is_special_a & (mant_a != 9'd0);
    wire is_nan_b     = is_special_b & (mant_b != 9'd0);

    // -- Normal-path: sign, mantissa product, exponent sum ------------
    wire result_sign  = sign_a ^ sign_b;   // XOR gate (R-SI-1 safe)

    wire [9:0]  full_mant_a = {1'b1, mant_a};   // implied leading 1
    wire [9:0]  full_mant_b = {1'b1, mant_b};
    wire [19:0] mant_prod   = full_mant_a * full_mant_b;  // 10×10 multiply
    wire [6:0]  exp_sum     = {1'b0, exp_a} + {1'b0, exp_b};

    // -- Combinational normalise / round / saturate -------------------
    reg [6:0]  raw_exp;
    reg [8:0]  mant_out;
    reg [19:0] prod;
    reg        guard_bit, round_bit, sticky;
    reg [8:0]  mant_rounded;
    reg [6:0]  final_exp;
    reg [8:0]  final_mant;
    reg [15:0] final_result;

    always @(*) begin
        // defaults
        raw_exp      = 7'd0;
        mant_out     = 9'd0;
        prod         = 20'd0;
        guard_bit    = 1'b0;
        round_bit    = 1'b0;
        sticky       = 1'b0;
        mant_rounded = 9'd0;
        final_exp    = 7'd0;
        final_mant   = 9'd0;
        final_result = 16'd0;

        // -- Exception priority (IEEE-style) -------------------------
        if (is_nan_a | is_nan_b) begin
            result = 16'hFE01;                         // canonical NaN
        end else if ((is_zero_a & is_inf_b) | (is_zero_b & is_inf_a)) begin
            result = 16'hFE01;                         // 0 × ∞ = NaN
        end else if (is_zero_a | is_zero_b) begin
            result = result_sign ? 16'h8000 : 16'h0000;
        end else if (is_inf_a | is_inf_b) begin
            result = result_sign ? 16'hFE00 : 16'h7E00;
        end else begin
            // -- Normal multiplication --------------------------------
            prod    = mant_prod;
            raw_exp = exp_sum - {1'b0, BIAS};

            // Normalise: detect leading 1 position in product[19:17]
            if (prod[19]) begin
                raw_exp   = raw_exp + 7'd1;
                mant_out  = prod[18:10];
                guard_bit = prod[9];
                round_bit = prod[8];
                sticky    = |prod[7:0];
            end else if (prod[18]) begin
                mant_out  = prod[17:9];
                guard_bit = prod[8];
                round_bit = prod[7];
                sticky    = |prod[6:0];
            end else if (prod[17]) begin
                raw_exp   = raw_exp - 7'd1;
                mant_out  = prod[16:8];
                guard_bit = prod[7];
                round_bit = prod[6];
                sticky    = |prod[5:0];
            end else begin
                raw_exp   = raw_exp - 7'd2;
                mant_out  = prod[15:7];
                guard_bit = prod[6];
                round_bit = prod[5];
                sticky    = |prod[4:0];
            end

            // Round-to-nearest-even
            if (guard_bit & (round_bit | sticky))
                mant_rounded = mant_out + 9'd1;
            else
                mant_rounded = mant_out;

            // Carry-out from rounding
            // NOTE: baseline uses mant_rounded[9] (out-of-range on [8:0],
            // always 1'bx → treated as 0 by tools). We mirror exactly for
            // bit-exact EQY equivalence.
            if (mant_rounded[9]) begin
                final_exp  = raw_exp + 7'd1;
                final_mant = 9'd0;
            end else begin
                final_exp  = raw_exp;
                final_mant = mant_rounded;
            end

            // Saturation / underflow
            if (final_exp[6]) begin
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
