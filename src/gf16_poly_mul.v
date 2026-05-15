`default_nettype none
// gf16_poly_mul.v — GF(2^4) polynomial multiplier, irreducible poly x^4+x+1 (0x13)
// Anchor: phi^2+phi^-2=3  DOI 10.5281/zenodo.19227877
// R-SI-1: zero $mul cells. Pure XOR/AND only.
// Apache-2.0
//
// Ports: 4-bit a, b, y — native GF(2^4) lane.
// Wave-16a PATH-3 (SHADOW): new src for experimental GF(2^4) mesh tile.
//
// Multiplication table correctness: exhaustively verified (256/256) in
// sim/tb_gf16_poly_mul.v using the same polynomial.
//
// Author: Vasilev Dmitrii <admin@t27.ai>  ORCID 0009-0008-4294-6159

module gf16_poly_mul (
    input  wire [3:0] a,
    input  wire [3:0] b,
    output wire [3:0] y
);
    // Carryless multiplication mod x^4+x+1 over GF(2).
    // Reduction rules: x^4 = x+1, x^5 = x^2+x, x^6 = x^3+x^2.
    //
    // y[bit] = XOR of a[i]&b[j] terms where power_map(i+j) includes bit:
    //   power 0..3: direct map to y[0..3]
    //   power 4 (i+j=4): contributes to y[0] and y[1]
    //   power 5 (i+j=5): contributes to y[1] and y[2]
    //   power 6 (i+j=6): contributes to y[2] and y[3]
    assign y[0] = (a[0]&b[0])     // power 0
                ^ (a[1]&b[3])     // power 4
                ^ (a[2]&b[2])     // power 4
                ^ (a[3]&b[1]);    // power 4

    assign y[1] = (a[0]&b[1])     // power 1
                ^ (a[1]&b[0])     // power 1
                ^ (a[1]&b[3])     // power 4
                ^ (a[2]&b[2])     // power 4
                ^ (a[2]&b[3])     // power 5
                ^ (a[3]&b[1])     // power 4
                ^ (a[3]&b[2]);    // power 5

    assign y[2] = (a[0]&b[2])     // power 2
                ^ (a[1]&b[1])     // power 2
                ^ (a[2]&b[0])     // power 2
                ^ (a[2]&b[3])     // power 5
                ^ (a[3]&b[2])     // power 5
                ^ (a[3]&b[3]);    // power 6

    assign y[3] = (a[0]&b[3])     // power 3
                ^ (a[1]&b[2])     // power 3
                ^ (a[2]&b[1])     // power 3
                ^ (a[3]&b[0])     // power 3
                ^ (a[3]&b[3]);    // power 6

endmodule
