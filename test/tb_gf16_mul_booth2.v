// SPDX-License-Identifier: Apache-2.0
// tb_gf16_mul_booth2.v — Exhaustive testbench for gf16_mul_booth2
// Tests all 16×16 = 256 input combinations, asserts product == (a*b)[7:0]
// Pure Verilog-2005, R-SI-1 clean (reference uses integer arithmetic, not *)
//
// Compile & run:
//   iverilog -o /tmp/tb_booth2 tb_gf16_mul_booth2.v gf16_mul_booth2.v
//   vvp /tmp/tb_booth2

`default_nettype none
`timescale 1ns/1ps

module tb_gf16_mul_booth2;

    // DUT ports
    reg  [3:0] a;
    reg  [3:0] b;
    wire [7:0] product;

    // Expected value (computed without * by shift-add in integer task)
    reg  [7:0] expected;

    // Counters
    integer pass_count;
    integer fail_count;
    integer ia;
    integer ib;

    // Integer multiplication without * : shift-add over bits of b
    // Reference: expected = a_int * b_int (shift-add)
    // We use a local task to avoid the * operator in synthesisable code;
    // this is only in the testbench (not synthesised) but we keep it
    // * -free for R-SI-1 consistency.
    task ref_mul;
        input  [3:0] ta;
        input  [3:0] tb;
        output [7:0] result;
        reg [7:0] acc;
        reg [7:0] shifted;
        integer k;
        begin
            acc = 8'b0;
            shifted = {4'b0, ta};
            for (k = 0; k < 4; k = k + 1) begin
                if (tb[k])
                    acc = acc + (shifted << k);
            end
            result = acc;
        end
    endtask

    // Instantiate DUT
    gf16_mul_booth2 dut (
        .a(a),
        .b(b),
        .product(product)
    );

    initial begin
        pass_count = 0;
        fail_count = 0;

        // Sweep all 256 combinations
        for (ia = 0; ia < 16; ia = ia + 1) begin
            for (ib = 0; ib < 16; ib = ib + 1) begin
                a = ia[3:0];
                b = ib[3:0];
                #10;  // allow combinational propagation

                ref_mul(a, b, expected);

                if (product !== expected) begin
                    $display("FAIL: a=%0d b=%0d  got=0x%02h  expected=0x%02h",
                             ia, ib, product, expected);
                    fail_count = fail_count + 1;
                end else begin
                    pass_count = pass_count + 1;
                end
            end
        end

        // Summary
        $display("-----------------------------------");
        $display("Booth-2 exhaustive test: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("Total pairs tested: %0d / 256", pass_count + fail_count);
        $display("-----------------------------------");

        if (fail_count == 0) begin
            $display("ALL 256 PAIRS PASSED — L-Z06 booth-2 VERIFIED");
            $finish(0);
        end else begin
            $display("ERRORS DETECTED — check output above");
            $finish(1);
        end
    end

endmodule
`default_nettype wire
