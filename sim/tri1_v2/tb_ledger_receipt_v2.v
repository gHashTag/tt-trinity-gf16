// SPDX-License-Identifier: Apache-2.0
// tb_ledger_receipt_v2.v — Testbench for ledger_receipt_v2
// Apache-2.0
//
// Test plan:
//   8  deterministic compute windows (tests  0- 7)
//  60  LFSR-random result streams with golden hash reference (tests  8-67)
//   4  cross-tile receipts cycling tile_id 0..3 (tests 68-71)
//   Total: 72 tests minimum
//
// Pass criterion: all 72 tests PASS → prints LEDGER_RECEIPT_V2_GREEN
// Author: Dmitrii Vasilev <admin@t27.ai>

`default_nettype none
`timescale 1ns/1ps

module tb_ledger_receipt_v2;

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    reg         clk;
    reg         rst_n;
    reg  [1:0]  tile_id;
    reg         window_valid;
    reg  [31:0] result;
    wire [127:0] receipt;
    wire         receipt_valid;

    // -----------------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------------
    ledger_receipt_v2 dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .tile_id       (tile_id),
        .window_valid  (window_valid),
        .result        (result),
        .receipt       (receipt),
        .receipt_valid (receipt_valid)
    );

    // -----------------------------------------------------------------------
    // Clock generation: 10 ns period
    // -----------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // Test bookkeeping
    // -----------------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    integer test_num;

    // -----------------------------------------------------------------------
    // Golden hash model — must mirror hardware hash3 function exactly
    // 3-round XOR+rotate (ternary-friendly, no SHA)
    // -----------------------------------------------------------------------
    function [31:0] rol32_7;
        input [31:0] x;
        rol32_7 = {x[24:0], x[31:25]};
    endfunction

    function [31:0] rol32_13;
        input [31:0] x;
        rol32_13 = {x[18:0], x[31:19]};
    endfunction

    function [31:0] rol32_17;
        input [31:0] x;
        rol32_17 = {x[14:0], x[31:15]};
    endfunction

    function [31:0] hash3_golden;
        input [31:0] data;
        input [1:0]  tid;
        input [29:0] wctr;
        reg   [31:0] seed_a;
        reg   [31:0] h;
        begin
            seed_a = {tid, wctr};
            h = data ^ seed_a;
            h = rol32_7(h) ^ (seed_a ^ rol32_13(data));
            h = rol32_17(h) ^ ({seed_a[28:0], 3'b000} ^ data);
            hash3_golden = h;
        end
    endfunction

    function [63:0] merkle_leaf_golden;
        input [31:0] rh;
        input [31:0] res;
        input [1:0]  tid;
        input [29:0] wctr;
        reg   [31:0] upper;
        reg   [31:0] lower;
        begin
            upper = hash3_golden(rol32_13(res), tid, wctr);
            lower = rh ^ {wctr, tid};
            merkle_leaf_golden = {upper, lower};
        end
    endfunction

    // -----------------------------------------------------------------------
    // Task: drive one compute window and wait for receipt
    // -----------------------------------------------------------------------
    reg  [127:0] got_receipt;
    reg          got_valid;

    task drive_window;
        input [1:0]  t_id;
        input [31:0] res_in;
        input integer t_num;
        // Expected values computed in task
        reg  [29:0] exp_wctr;
        reg  [31:0] exp_rh;
        reg  [63:0] exp_ml;
        reg  [127:0] exp_receipt;
        integer      wait_cnt;
        begin
            // Capture current counter before driving
            exp_wctr = dut.window_ctr;

            // Assert window_valid for one cycle
            @(negedge clk);
            tile_id      = t_id;
            result       = res_in;
            window_valid = 1'b1;
            @(negedge clk);
            window_valid = 1'b0;

            // Wait for receipt_valid (pipeline = 4 cycles max after posedge)
            got_valid = 1'b0;
            wait_cnt  = 0;
            while (!got_valid && wait_cnt < 20) begin
                @(posedge clk);
                #1;
                if (receipt_valid) begin
                    got_receipt = receipt;
                    got_valid   = 1'b1;
                end
                wait_cnt = wait_cnt + 1;
            end

            // Compute expected
            exp_rh      = hash3_golden(res_in, t_id, exp_wctr);
            exp_ml      = merkle_leaf_golden(exp_rh, res_in, t_id, exp_wctr);
            exp_receipt = {t_id, exp_wctr, exp_rh, exp_ml};

            if (!got_valid) begin
                $display("FAIL test %0d: no receipt_valid within timeout", t_num);
                fail_count = fail_count + 1;
            end else if (got_receipt !== exp_receipt) begin
                $display("FAIL test %0d: receipt mismatch", t_num);
                $display("  got  = %h", got_receipt);
                $display("  want = %h", exp_receipt);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS test %0d: tile=%0d wctr=%0d rh=%h ml=%h",
                         t_num, t_id, exp_wctr, exp_rh, exp_ml);
                pass_count = pass_count + 1;
            end
            test_num = test_num + 1;
        end
    endtask

    // -----------------------------------------------------------------------
    // LFSR — Fibonacci LFSR: x^32+x^22+x^2+x+1
    // -----------------------------------------------------------------------
    reg [31:0] lfsr_state;

    function [31:0] lfsr_next;
        input [31:0] s;
        reg bit_out;
        begin
            bit_out  = s[31] ^ s[21] ^ s[1] ^ s[0];
            lfsr_next = {s[30:0], bit_out};
        end
    endfunction

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    integer i;
    reg [31:0] det_results [0:7];

    initial begin
        // Deterministic result values for 8 fixed tests
        det_results[0] = 32'hDEAD_BEEF;
        det_results[1] = 32'hCAFE_BABE;
        det_results[2] = 32'h1234_5678;
        det_results[3] = 32'hFFFF_FFFF;
        det_results[4] = 32'h0000_0000;
        det_results[5] = 32'hA5A5_A5A5;
        det_results[6] = 32'h5A5A_5A5A;
        det_results[7] = 32'hBEEF_CAFE;

        pass_count   = 0;
        fail_count   = 0;
        test_num     = 0;
        window_valid = 0;
        tile_id      = 0;
        result       = 0;
        lfsr_state   = 32'hACE1_0001;

        // Reset
        rst_n = 1'b0;
        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        // ------------------------------------------------------------------
        // SECTION 1: 8 deterministic tests (tests 0-7), tile_id = 2'b01
        // ------------------------------------------------------------------
        $display("--- Section 1: 8 deterministic windows ---");
        for (i = 0; i < 8; i = i + 1) begin
            drive_window(2'b01, det_results[i], test_num);
            repeat(2) @(posedge clk);
        end

        // ------------------------------------------------------------------
        // SECTION 2: 60 LFSR-random result streams (tests 8-67), tile_id = 2'b10
        // ------------------------------------------------------------------
        $display("--- Section 2: 60 LFSR random windows ---");
        for (i = 0; i < 60; i = i + 1) begin
            lfsr_state = lfsr_next(lfsr_state);
            drive_window(2'b10, lfsr_state, test_num);
            repeat(2) @(posedge clk);
        end

        // ------------------------------------------------------------------
        // SECTION 3: 4 cross-tile receipts (tests 68-71), cycling tile_id
        // Single call per tile_id 0..3
        // ------------------------------------------------------------------
        $display("--- Section 3: 4 cross-tile receipts ---");
        begin
            // tile_id=0
            lfsr_state = lfsr_next(lfsr_state);
            drive_window(2'b00, lfsr_state, test_num);
            repeat(2) @(posedge clk);
            // tile_id=1
            lfsr_state = lfsr_next(lfsr_state);
            drive_window(2'b01, lfsr_state, test_num);
            repeat(2) @(posedge clk);
            // tile_id=2
            lfsr_state = lfsr_next(lfsr_state);
            drive_window(2'b10, lfsr_state, test_num);
            repeat(2) @(posedge clk);
            // tile_id=3
            lfsr_state = lfsr_next(lfsr_state);
            drive_window(2'b11, lfsr_state, test_num);
            repeat(2) @(posedge clk);
        end

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        $display("==================================================");
        $display("RESULTS: %0d PASS, %0d FAIL (total %0d tests)",
                 pass_count, fail_count, test_num);
        if (fail_count == 0 && test_num >= 72) begin
            $display("LEDGER_RECEIPT_V2_GREEN");
        end else begin
            $display("LEDGER_RECEIPT_V2_RED  (failures=%0d, tests=%0d)",
                     fail_count, test_num);
        end
        $display("==================================================");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("TIMEOUT: simulation exceeded 100us");
        $finish;
    end

endmodule
`default_nettype wire
