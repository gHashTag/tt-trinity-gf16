`default_nettype none
// gf16_dot4_poly.v — GF(2^4) dot-product of four 4-bit lanes.
// Uses gf16_poly_mul (XOR/AND, R-SI-1 compliant).
// Addition in GF(2^4) is bitwise XOR.
// Anchor: phi^2+phi^-2=3  DOI 10.5281/zenodo.19227877
// Apache-2.0
// Author: Vasilev Dmitrii <admin@t27.ai>  ORCID 0009-0008-4294-6159

module gf16_dot4_poly (
    input  wire [3:0] a0,
    input  wire [3:0] a1,
    input  wire [3:0] a2,
    input  wire [3:0] a3,
    input  wire [3:0] b0,
    input  wire [3:0] b1,
    input  wire [3:0] b2,
    input  wire [3:0] b3,
    output wire [3:0] result
);
    wire [3:0] p0, p1, p2, p3;

    gf16_poly_mul m0 (.a(a0), .b(b0), .y(p0));
    gf16_poly_mul m1 (.a(a1), .b(b1), .y(p1));
    gf16_poly_mul m2 (.a(a2), .b(b2), .y(p2));
    gf16_poly_mul m3 (.a(a3), .b(b3), .y(p3));

    // GF(2^4) add = XOR
    assign result = p0 ^ p1 ^ p2 ^ p3;

endmodule
