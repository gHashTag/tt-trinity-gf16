// SPDX-License-Identifier: Apache-2.0
// tb_tri_zero_skip_gate.v — Unit testbench for tri_zero_skip_gate
// Apache-2.0
//
// Wave-16a · feat/wave-16a-zero-skip-experimental
// Author: Vasilev Dmitrii <admin@t27.ai> ORCID 0009-0008-4294-6159
//
// TEST PLAN
// ---------
// Feed weights 0..15 (4-bit) to tri_zero_skip_gate.
// Expected: pe_clk_en == 0 ONLY when weight == 4'b0000 (i.e., weight == 0).
//           pe_clk_en == 1 for all other values 1..15.
//
// PASS criterion: all 16 cases correct → print "PASS: tb_tri_zero_skip_gate"
// FAIL criterion: any mismatch → print "FAIL: ..." and $finish with non-zero.
//
// ANCHOR: φ²+φ⁻²=3 · DOI 10.5281/zenodo.19227877

`timescale 1ns/1ps
`default_nettype none

module tb_tri_zero_skip_gate;

    // DUT ports
    reg  [3:0] weight;
    reg        clk;
    wire       pe_clk_en;

    // Clock generation (50 MHz — not needed for comb DUT, included for ICG context)
    initial clk = 0;
    always #10 clk = ~clk;  // 50 MHz: 20 ns period

    // DUT instantiation
    tri_zero_skip_gate dut (
        .weight   (weight),
        .clk      (clk),
        .pe_clk_en(pe_clk_en)
    );

    // Test variables
    integer w;
    integer fail_count;
    reg     expected;

    initial begin
        fail_count = 0;
        weight = 4'b0;

        $display("=== tb_tri_zero_skip_gate: Wave-16a zero-skip v2 unit test ===");
        $display("    Testing weights 0..15, expect pe_clk_en=0 only at weight==0");
        $display("");

        // Sweep all 4-bit weight values
        for (w = 0; w < 16; w = w + 1) begin
            weight = w[3:0];
            #5;  // small combinational settle time

            expected = (w != 0) ? 1'b1 : 1'b0;

            if (pe_clk_en !== expected) begin
                $display("FAIL: weight=%0d (%04b) → pe_clk_en=%b, expected=%b",
                         w, w[3:0], pe_clk_en, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("  OK: weight=%2d (%04b) → pe_clk_en=%b (correct)",
                         w, w[3:0], pe_clk_en);
            end
            #5;
        end

        $display("");
        $display("=== Results: %0d/16 correct, %0d failures ===", 16 - fail_count, fail_count);

        if (fail_count == 0) begin
            $display("PASS: tb_tri_zero_skip_gate — all 16 weight values correct");
            $display("  pe_clk_en=0 for weight=0x0 (GF16 zero), pe_clk_en=1 for 0x1..0xF");
            $display("  NorthPole-style zero-skip v2: clock-enable gate verified R-SI-1");
        end else begin
            $display("FAIL: tb_tri_zero_skip_gate — %0d errors detected", fail_count);
            $finish(1);
        end

        $finish;
    end

endmodule
`default_nettype wire
