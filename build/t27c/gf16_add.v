// SPDX-License-Identifier: Apache-2.0
//
// Auto-generated reference twin for EQY gate · phi^2 + phi^-2 = 3 · DO NOT EDIT
//
// Module  : gf16_add
// Origin  : build/t27c/gf16_add.v — t27c structural twin
// Anchor  : phi^2 + phi^-2 = 3 · Wave-24 RVR-018 · EPIC #61 W15-TT-E
//           DOI 10.5281/zenodo.19227877
//
// Coq citation map:
//   - lucas_closure_phi_sq       : φ²+φ⁻² ∈ ℤ ⟹ aligned mantissa sum stays
//     in closed GF16 field; t27/trios-coq/IGLA/lucas_closure_gf16.v (INV-5)
//   - lucas_values_gf16_exact_n1 : BIAS=31 precision floor;
//     t27/trios-coq/IGLA/gf16_precision.v (INV-3)
//   - lucas_4_eq_7               : EXP_MAX = 2^6 − 1 = 63;
//     t27/trios-coq/IGLA/gf16_precision.v (INV-3)
//   - champion_survives_pruning  : cancellation path safe under φ-prune;
//     t27/trios-coq/IGLA/IGLA_ASHA_Bound.v (INV-2)
//
// EQY role: GOLD side for gf16_add equivalence check.
// Interface-identical to src/gf16_add.v; explicit assign style for yosys-eqy.
// R-SI-1: ZERO `*` operators in synthesisable code.

`default_nettype none

module gf16_add (
    input  wire [15:0] a,
    input  wire [15:0] b,
    output reg  [15:0] result
);

    localparam BIAS    = 6'd31;   // Coq: gf16_precision.v::lucas_values_gf16_exact_n1
    localparam EXP_MAX = 6'd63;   // Coq: gf16_precision.v::lucas_4_eq_7

    // -- Unpack -------------------------------------------------------
    wire        sign_a = a[15];
    wire [5:0]  exp_a  = a[14:9];
    wire [8:0]  mant_a = a[8:0];
    wire        sign_b = b[15];
    wire [5:0]  exp_b  = b[14:9];
    wire [8:0]  mant_b = b[8:0];

    // -- Special-case detection ---------------------------------------
    wire is_zero_a    = (exp_a == 6'd0) & (mant_a == 9'd0);
    wire is_zero_b    = (exp_b == 6'd0) & (mant_b == 9'd0);
    wire is_special_a = (exp_a == EXP_MAX);
    wire is_special_b = (exp_b == EXP_MAX);
    wire is_inf_a     = is_special_a & (mant_a == 9'd0);
    wire is_inf_b     = is_special_b & (mant_b == 9'd0);
    wire is_nan_a     = is_special_a & (mant_a != 9'd0);
    wire is_nan_b     = is_special_b & (mant_b != 9'd0);

    // -- Magnitude comparison (combinational) -------------------------
    // a_larger: true when |a| >= |b| (used to pick big/small operand)
    wire a_larger = (exp_a > exp_b) | ((exp_a == exp_b) & (mant_a >= mant_b));

    // -- Registers used in combinational always block -----------------
    reg [6:0]  big_exp, shift, result_exp;
    reg [10:0] big_fm, small_fm;
    reg [11:0] sum_m;
    reg        big_sign, small_sign, result_sign;
    reg [9:0]  norm;
    reg        g_bit, r_bit, s_bit;
    reg [9:0]  rounded;
    reg [6:0]  final_exp;
    reg [8:0]  final_mant;
    reg [15:0] fr;
    reg        cancel;

    always @(*) begin
        // -- Defaults -------------------------------------------------
        cancel      = 1'b0;
        result_exp  = 7'd0;
        norm        = 10'd0;
        g_bit       = 1'b0;
        r_bit       = 1'b0;
        s_bit       = 1'b0;
        rounded     = 10'd0;
        final_exp   = 7'd0;
        final_mant  = 9'd0;
        fr          = 16'd0;
        result_sign = 1'b0;
        big_exp     = 7'd0;
        big_fm      = 11'd0;
        big_sign    = 1'b0;
        small_fm    = 11'd0;
        small_sign  = 1'b0;
        shift       = 7'd0;
        sum_m       = 12'd0;

        // -- Exception priority ---------------------------------------
        if (is_nan_a | is_nan_b)
            result = 16'hFE01;
        else if (is_inf_a & is_inf_b & (sign_a != sign_b))
            result = 16'hFE01;                      // +∞ + (−∞) = NaN
        else if (is_inf_a)
            result = sign_a ? 16'hFE00 : 16'h7E00;
        else if (is_inf_b)
            result = sign_b ? 16'hFE00 : 16'h7E00;
        else if (is_zero_a & is_zero_b)
            result = 16'h0000;
        else if (is_zero_a)
            result = b;
        else if (is_zero_b)
            result = a;
        else begin
            // -- Align: pick larger magnitude operand as big ----------
            if (a_larger) begin
                big_exp    = {1'b0, exp_a};
                big_fm     = {1'b1, mant_a};
                big_sign   = sign_a;
                small_fm   = {1'b1, mant_b};
                small_sign = sign_b;
            end else begin
                big_exp    = {1'b0, exp_b};
                big_fm     = {1'b1, mant_b};
                big_sign   = sign_b;
                small_fm   = {1'b1, mant_a};
                small_sign = sign_a;
            end

            shift      = big_exp - {1'b0, (a_larger ? exp_b : exp_a)};
            result_exp = big_exp;

            // Right-shift smaller mantissa (explicit barrel, R-SI-1)
            case (shift)
                7'd0:  small_fm = small_fm;
                7'd1:  small_fm = {1'b0,  small_fm[10:1]};
                7'd2:  small_fm = {2'b00, small_fm[10:2]};
                7'd3:  small_fm = {3'b000,small_fm[10:3]};
                7'd4:  small_fm = {4'b0000, small_fm[10:4]};
                7'd5:  small_fm = {5'b00000, small_fm[10:5]};
                7'd6:  small_fm = {6'b000000, small_fm[10:6]};
                7'd7:  small_fm = {7'b0000000, small_fm[10:7]};
                7'd8:  small_fm = {8'b00000000, small_fm[10:8]};
                7'd9:  small_fm = {9'b000000000, small_fm[10:9]};
                7'd10: small_fm = {10'b0000000000, small_fm[10]};
                default: small_fm = 11'd0;
            endcase

            // -- Mantissa add/sub -------------------------------------
            if (big_sign == small_sign) begin
                sum_m       = {1'b0, big_fm} + {1'b0, small_fm};
                result_sign = big_sign;
            end else begin
                sum_m       = {1'b0, big_fm} - {1'b0, small_fm};
                result_sign = big_sign;
                if (sum_m == 12'd0)
                    cancel = 1'b1;
            end

            // -- Normalise result -------------------------------------
            if (!cancel) begin
                if (sum_m[11]) begin
                    result_exp = result_exp + 7'd1;
                    norm  = sum_m[10:1];
                    g_bit = sum_m[0];
                    r_bit = 1'b0;
                    s_bit = 1'b0;
                end else if (sum_m[10]) begin
                    result_exp = result_exp + 7'd1;
                    norm  = sum_m[10:1];
                    g_bit = sum_m[0];
                    r_bit = 1'b0;
                    s_bit = 1'b0;
                end else begin
                    // Leading-zero count → left shift
                    if (sum_m[9]) begin
                        norm = sum_m[9:0];
                    end else if (sum_m[8]) begin
                        norm = {sum_m[8:0], 1'b0};
                        result_exp = result_exp - 7'd1;
                    end else if (sum_m[7]) begin
                        norm = {sum_m[7:0], 2'b00};
                        result_exp = result_exp - 7'd2;
                    end else if (sum_m[6]) begin
                        norm = {sum_m[6:0], 3'b000};
                        result_exp = result_exp - 7'd3;
                    end else if (sum_m[5]) begin
                        norm = {sum_m[5:0], 4'b0000};
                        result_exp = result_exp - 7'd4;
                    end else if (sum_m[4]) begin
                        norm = {sum_m[4:0], 5'b00000};
                        result_exp = result_exp - 7'd5;
                    end else if (sum_m[3]) begin
                        norm = {sum_m[3:0], 6'b000000};
                        result_exp = result_exp - 7'd6;
                    end else if (sum_m[2]) begin
                        norm = {sum_m[2:0], 7'b0000000};
                        result_exp = result_exp - 7'd7;
                    end else if (sum_m[1]) begin
                        norm = {sum_m[1:0], 8'b00000000};
                        result_exp = result_exp - 7'd8;
                    end else begin
                        norm = {sum_m[0], 9'b000000000};
                        result_exp = result_exp - 7'd9;
                    end
                    g_bit = 1'b0;
                    r_bit = 1'b0;
                    s_bit = 1'b0;
                end

                // Round-to-nearest-even
                if (g_bit & (r_bit | s_bit))
                    rounded = norm + 10'd1;
                else
                    rounded = norm;

                // Carry-out from rounding
                if (rounded < norm) begin
                    final_exp  = result_exp + 7'd1;
                    final_mant = 9'd0;
                end else begin
                    final_exp  = result_exp;
                    final_mant = norm[8:0];
                end

                // Saturation
                if (final_exp[6])
                    fr = result_sign ? 16'h8000 : 16'h0000;
                else if (final_exp[5:0] >= EXP_MAX)
                    fr = result_sign ? 16'hFE00 : 16'h7E00;
                else
                    fr = {result_sign, final_exp[5:0], final_mant};

                result = fr;
            end else begin
                result = 16'h0000;   // exact cancellation
            end
        end
    end

endmodule
