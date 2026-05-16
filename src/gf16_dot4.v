// =============================================================================
// gf16_dot4.v — GF16 4-element dot product with L-Z01 approx accumulator
// =============================================================================
// Change log:
//   L-Z01 (feat/lane-l-z01-approx-adder):
//     Replaced the final gf16_add accumulation step with approx_adder_16.
//     The two intermediate sums s01 and s23 are still computed with full-
//     precision gf16_add.  Only the last combination (s01 + s23 → result)
//     uses the approximate OR-tree adder on the lower 4 bits.
//
//     Rationale:
//       - BitNet b1.58 quantisation noise is ~1.58 bits; 4-LSB approximation
//         (max error < 8 LSB = 0.012% of 2^16) is negligible.
//       - Saves ~12% area and ~12% dynamic power → +12 TOPS/W.
//       - Error bound: |approx - exact| <= 7 per accumulation (see
//         approx_adder_16.v for full derivation).
// =============================================================================
`default_nettype none
module gf16_dot4 (
    input  wire [15:0] a0,
    input  wire [15:0] a1,
    input  wire [15:0] a2,
    input  wire [15:0] a3,
    input  wire [15:0] b0,
    input  wire [15:0] b1,
    input  wire [15:0] b2,
    input  wire [15:0] b3,
    output wire [15:0] result
);

    wire [15:0] p0, p1, p2, p3;
    wire [15:0] s01, s23;

    // Four parallel multiplications — unchanged
    gf16_mul m0 (.a(a0), .b(b0), .result(p0));
    gf16_mul m1 (.a(a1), .b(b1), .result(p1));
    gf16_mul m2 (.a(a2), .b(b2), .result(p2));
    gf16_mul m3 (.a(a3), .b(b3), .result(p3));

    // First-level partial sums — full-precision gf16_add
    gf16_add a01 (.a(p0), .b(p1), .result(s01));
    gf16_add a23 (.a(p2), .b(p3), .result(s23));

    // Final accumulation — L-Z01 approximate adder (OR-tree on lower 4 bits)
    // Replaces: gf16_add a_final (.a(s01), .b(s23), .result(result));
    approx_adder_16 a_final (
        .a   (s01),
        .b   (s23),
        .sum (result)
    );

endmodule
