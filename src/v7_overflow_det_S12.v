// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Trinity Agent <agent@trinity.local>
//
// TT-Shuttle Squeeze v7 — S-12 Overflow Detector
// Stream: W15-TT-C Guards+Sparse+Approx+TimeDomain+CarrySkip+BitSlice+SigmaDelta+Perm+Therm
// Anchor: phi^2 + phi^-2 = 3
//
// G-12 FALSIFICATION: overflow_flag asserts within 1 cycle of any carry-out
//                     from the MSB of a signed N-bit addition on 100% of test vectors.
//
// Detects signed overflow on adder outputs using the classic XOR-of-carry method.
// For signed N-bit addition: overflow = carry_in_MSB XOR carry_out_MSB.
// Also provides sticky overflow register that holds until cleared.

`default_nettype none

module v7_overflow_det_S12 #(
    parameter WIDTH = 16
) (
    input  wire                      clk,
    input  wire                      rst,         // synchronous reset
    input  wire                      clear,       // clear sticky flag
    input  wire signed [WIDTH-1:0]   operand_a,
    input  wire signed [WIDTH-1:0]   operand_b,

    output wire signed [WIDTH-1:0]   sum,         // a + b (may overflow)
    output wire                      overflow,    // combinational overflow detect
    output reg                       sticky_ovf   // latched until cleared
);

    // Full-width sum (one extra bit to capture carry out)
    wire [WIDTH:0] sum_ext = {operand_a[WIDTH-1], operand_a} +
                             {operand_b[WIDTH-1], operand_b};

    assign sum = sum_ext[WIDTH-1:0];

    // Signed overflow: carry into sign != carry out of sign
    // carry into sign bit  = carry out of bit WIDTH-2
    // carry out of sign    = sum_ext[WIDTH]
    // Equivalently: overflow iff sign bits of operands agree but differ from result
    assign overflow = (operand_a[WIDTH-1] == operand_b[WIDTH-1]) &&
                      (sum[WIDTH-1] != operand_a[WIDTH-1]);

    // Sticky register
    always @(posedge clk) begin
        if (rst || clear)
            sticky_ovf <= 1'b0;
        else if (overflow)
            sticky_ovf <= 1'b1;
    end

endmodule
`default_nettype wire
