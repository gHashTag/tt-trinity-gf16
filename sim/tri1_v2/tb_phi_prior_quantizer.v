// SPDX-License-Identifier: Apache-2.0
// Author: Dmitrii Vasilev <admin@t27.ai>
// Testbench: phi_prior_quantizer
// 10 deterministic boundary vectors + 128 LFSR-random vectors
// Sim token: PHI_PRIOR_QUANT_GREEN (printed on 100% PASS)
//
// Pipeline latency = 1 cycle: apply input on cycle N, read output on cycle N+1.
//
// Boundary test plan (10 vectors, all 8 lanes driven with same value):
//   1. w =      0  (0x0000) → 0    (zero)
//   2. w = +12532  (0x30F4) → 0    (just below threshold)
//   3. w = +12533  (0x30F5) → +1   (at threshold)
//   4. w = +12534  (0x30F6) → +1   (just above threshold)
//   5. w = -12532  (0xCF0C) → 0    (magnitude just below)
//   6. w = -12533  (0xCF0B) → -1   (at neg threshold)
//   7. w = -12534  (0xCF0A) → -1   (magnitude just above)
//   8. w = +32767  (0x7FFF) → +1   (max positive Q1.15)
//   9. w = -32768  (0x8000) → -1   (min negative Q1.15)
//  10. w =     -1  (0xFFFF) → 0    (small negative)

`timescale 1ns/1ps
`default_nettype none

module tb_phi_prior_quantizer;

    parameter integer N_LANES    = 8;
    parameter integer W_BITS     = 16;
    parameter integer PHI_INV_SQ = 12533;

    // Clock & reset
    reg clk;
    reg rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT
    reg  [N_LANES*W_BITS-1:0] fp_in;
    wire [N_LANES*2-1:0]      tern_out;

    phi_prior_quantizer #(
        .N_LANES(N_LANES),
        .W_BITS (W_BITS)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .fp_in   (fp_in),
        .tern_out(tern_out)
    );

    // Global counters
    integer pass_count;
    integer fail_count;
    integer test_num;

    // Random data memories
    reg [15:0] rand_in   [0:127];
    reg [15:0] rand_gold [0:127];

    // Set all 8 lanes to the same 16-bit value
    task set_all_lanes;
        input [15:0] val;
        integer ii;
        begin
            for (ii = 0; ii < N_LANES; ii = ii + 1)
                fp_in[ii*W_BITS +: W_BITS] = val;
        end
    endtask

    // Build expected packed output: all 8 lanes same code
    function [N_LANES*2-1:0] build_exp;
        input [1:0] code;
        integer ii;
        reg [N_LANES*2-1:0] tmp;
        begin
            tmp = {(N_LANES*2){1'b0}};
            for (ii = 0; ii < N_LANES; ii = ii + 1)
                tmp[ii*2 +: 2] = code;
            build_exp = tmp;
        end
    endfunction

    // Drive one deterministic test vector (1-cycle pipeline)
    task det_test;
        input [15:0]       in_val;
        input [1:0]        exp_code;
        reg [N_LANES*2-1:0] exp_pack;
        begin
            set_all_lanes(in_val);
            @(posedge clk); #1;
            exp_pack = build_exp(exp_code);
            if (tern_out === exp_pack) begin
                $display("  PASS[%0d] w=0x%04h exp=2'b%02b lane0_got=2'b%02b",
                    test_num, in_val, exp_code, tern_out[1:0]);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL[%0d] w=0x%04h exp=%016b got=%016b",
                    test_num, in_val, exp_pack, tern_out);
                fail_count = fail_count + 1;
            end
            test_num = test_num + 1;
        end
    endtask

    // Loop variables (must be declared at module scope for Verilog-2001)
    integer ri;

    initial begin : TB_MAIN
        rst_n       = 0;
        fp_in       = {(N_LANES*W_BITS){1'b0}};
        pass_count  = 0;
        fail_count  = 0;
        test_num    = 1;

        $readmemh("rand_in.hex",   rand_in);
        $readmemh("rand_gold.hex", rand_gold);

        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("");
        $display("=== phi_prior_quantizer testbench ===");
        $display("    N_LANES=%0d  W_BITS=%0d  PHI_INV_SQ=%0d",
                 N_LANES, W_BITS, PHI_INV_SQ);
        $display("");
        $display("-- Section 1: Deterministic boundary vectors (10) --");

        // T01: w=0 → 0
        det_test(16'h0000, 2'b01);
        // T02: w=+12532 → 0
        det_test(16'd12532, 2'b01);
        // T03: w=+12533 → +1
        det_test(16'd12533, 2'b00);
        // T04: w=+12534 → +1
        det_test(16'd12534, 2'b00);
        // T05: w=-12532 (0xCF0C) → 0
        det_test(16'hCF0C, 2'b01);
        // T06: w=-12533 (0xCF0B) → -1
        det_test(16'hCF0B, 2'b10);
        // T07: w=-12534 (0xCF0A) → -1
        det_test(16'hCF0A, 2'b10);
        // T08: w=+32767 → +1
        det_test(16'h7FFF, 2'b00);
        // T09: w=-32768 → -1
        det_test(16'h8000, 2'b10);
        // T10: w=-1 (0xFFFF) → 0
        det_test(16'hFFFF, 2'b01);

        $display("");
        $display("-- Section 1 done: %0d pass, %0d fail --",
                 pass_count, fail_count);
        $display("");
        $display("-- Section 2: 128 LFSR-random vectors --");

        for (ri = 0; ri < 128; ri = ri + 1) begin
            set_all_lanes(rand_in[ri]);
            @(posedge clk); #1;
            if (tern_out === rand_gold[ri]) begin
                pass_count = pass_count + 1;
            end else begin
                $display("  RAND FAIL[%0d] in=0x%04h exp=%016b got=%016b",
                    ri, rand_in[ri], rand_gold[ri], tern_out);
                fail_count = fail_count + 1;
            end
            test_num = test_num + 1;
        end

        $display("  Random section: done");
        $display("");
        $display("=== TOTAL: %0d pass, %0d fail (138 tests) ===",
                 pass_count, fail_count);
        $display("");

        if (fail_count == 0) begin
            $display("PHI_PRIOR_QUANT_GREEN");
        end else begin
            $display("PHI_PRIOR_QUANT_FAIL  failures=%0d", fail_count);
        end

        $display("");
        $finish;
    end

    initial begin
        #500000;
        $display("TIMEOUT");
        $finish;
    end

endmodule

`default_nettype wire
