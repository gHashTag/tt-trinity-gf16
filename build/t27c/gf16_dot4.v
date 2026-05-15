// SPDX-License-Identifier: Apache-2.0
//
// Auto-generated reference twin for EQY gate · phi^2 + phi^-2 = 3 · DO NOT EDIT
//
// Module  : gf16_dot4
// Origin  : build/t27c/gf16_dot4.v — t27c structural twin
// Anchor  : phi^2 + phi^-2 = 3 · Wave-24 RVR-018 · EPIC #61 W15-TT-E
//           DOI 10.5281/zenodo.19227877
//
// Coq citation map:
//   - lucas_4_eq_7               : 4-element dot-product maps to φ-structured
//     4-bit radix; t27/trios-coq/IGLA/gf16_precision.v (INV-3)
//   - lucas_values_gf16_exact_n1 : precision floor for each GF16 product term;
//     t27/trios-coq/IGLA/gf16_precision.v (INV-3)
//   - lucas_closure_phi_sq       : pairwise adder tree stays within GF16 field;
//     t27/trios-coq/IGLA/lucas_closure_gf16.v (INV-5)
//   - champion_survives_pruning  : dot4 accumulator order is champion-safe;
//     t27/trios-coq/IGLA/IGLA_ASHA_Bound.v (INV-2)
//
// EQY role: GOLD side for gf16_dot4 equivalence check.
// Interface-identical to src/gf16_dot4.v; instantiates gf16_mul / gf16_add
// twins from the same build/t27c/ directory so the full dot4 tree is
// self-contained in the EQY gold elaboration.
// R-SI-1: ZERO `*` operators in this file (multiplications are inside gf16_mul).

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

    // -- Four parallel GF16 multiplications ---------------------------
    // Coq: each product is bounded by lucas_values_gf16_exact_n1 (INV-3)
    wire [15:0] p0, p1, p2, p3;

    gf16_mul m0 (.a(a0), .b(b0), .result(p0));
    gf16_mul m1 (.a(a1), .b(b1), .result(p1));
    gf16_mul m2 (.a(a2), .b(b2), .result(p2));
    gf16_mul m3 (.a(a3), .b(b3), .result(p3));

    // -- Adder tree: (p0+p1) + (p2+p3) --------------------------------
    // Coq: pairwise closure proven in lucas_closure_phi_sq (INV-5)
    wire [15:0] s01, s23;

    gf16_add a01 (.a(p0), .b(p1), .result(s01));
    gf16_add a23 (.a(p2), .b(p3), .result(s23));

    gf16_add a_final (.a(s01), .b(s23), .result(result));

endmodule
