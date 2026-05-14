// SPDX-License-Identifier: Apache-2.0
// tb_d2d_serdes_stub.v — Testbench for d2d_serdes_stub (L-S47)
//
// Tests:
//   Group A: 8 deterministic ctrl/data patterns
//   Group B: 50 LFSR random payload streams TX→RX loopback (byte-identical)
//   Group C: 4 handshake stall tests
//   Total  : 62 minimum tests; passes print D2D_SERDES_STUB_GREEN
//
// Author: Dmitrii Vasilev <admin@t27.ai>
// DOI: 10.5281/zenodo.19227877
// Anchor: φ² + φ⁻² = 3

`timescale 1ns/1ps

module tb_d2d_serdes_stub;

    // -----------------------------------------------------------
    // Clock & reset
    // -----------------------------------------------------------
    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz

    // -----------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------
    reg  [7:0]  tx_payload;
    reg  [1:0]  tx_ctrl;
    reg         tx_valid;
    wire        tx_ready;
    wire [9:0]  tx_line;
    wire        tx_line_valid;

    // Registered 1-cycle loopback: tx_line → rx_line (next cycle)
    reg  [9:0]  rx_line_reg;
    reg         rx_line_valid_reg;

    wire [7:0]  rx_payload;
    wire [1:0]  rx_ctrl;
    wire        rx_valid;
    reg         rx_ready;

    d2d_serdes_stub dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .tx_payload    (tx_payload),
        .tx_ctrl       (tx_ctrl),
        .tx_valid      (tx_valid),
        .tx_ready      (tx_ready),
        .tx_line       (tx_line),
        .tx_line_valid (tx_line_valid),
        .rx_line       (rx_line_reg),
        .rx_line_valid (rx_line_valid_reg),
        .rx_payload    (rx_payload),
        .rx_ctrl       (rx_ctrl),
        .rx_valid      (rx_valid),
        .rx_ready      (rx_ready)
    );

    // -----------------------------------------------------------
    // Test bookkeeping
    // -----------------------------------------------------------
    integer pass_cnt, fail_cnt, test_num;

    // -----------------------------------------------------------
    // Helper: drive one TX word and loop it back
    // TX pipeline: input → registered tx_line (1 cycle)
    // RX pipeline: rx_line_reg → registered rx_payload (1 cycle)
    //
    // Sequence:
    //   negedge: assert tx signals
    //   posedge clk1: TX latches → tx_line valid
    //   between clk1 and clk2: sample tx_line, update rx_line_reg
    //   posedge clk2: RX latches → rx_payload valid
    //   after clk2+1: check rx_payload
    // -----------------------------------------------------------
    task drive_and_check_loopback;
        input [7:0] pay;
        input [1:0] ctl;
        begin
            // Assert TX inputs before next posedge
            @(negedge clk);
            tx_payload = pay;
            tx_ctrl    = ctl;
            tx_valid   = 1'b1;
            rx_ready   = 1'b1;

            @(posedge clk); #1; // TX pipeline fires → tx_line updated
            // Propagate to RX
            rx_line_reg       = tx_line;
            rx_line_valid_reg = tx_line_valid;
            tx_valid = 1'b0;

            @(posedge clk); #1; // RX pipeline fires → rx_payload updated

            // Check
            test_num = test_num + 1;
            if (rx_payload === pay && rx_ctrl === ctl && rx_valid === 1'b1) begin
                $display("PASS  [%0d] pay=%02h ctrl=%02b loopback OK", test_num, pay, ctl);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL  [%0d] exp pay=%02h ctrl=%02b  got pay=%02h ctrl=%02b valid=%0b",
                         test_num, pay, ctl, rx_payload, rx_ctrl, rx_valid);
                fail_cnt = fail_cnt + 1;
            end

            // Clear RX loopback line
            @(negedge clk);
            rx_line_reg       = 10'b0;
            rx_line_valid_reg = 1'b0;
            @(posedge clk); #1; // let RX drain
        end
    endtask

    // -----------------------------------------------------------
    // LFSR (Galois 8-bit) for pseudo-random test patterns
    // poly x^8+x^6+x^5+x^4+1 = 0x71
    // -----------------------------------------------------------
    function [7:0] lfsr_next;
        input [7:0] s;
        reg fb;
        begin
            fb = s[0];
            lfsr_next = {1'b0, s[7:1]};
            if (fb) lfsr_next = lfsr_next ^ 8'h71;
        end
    endfunction

    // -----------------------------------------------------------
    // Handshake stall helper
    // Drives TX word, holds rx_ready=0 for stall_cyc cycles,
    // then releases and checks data integrity.
    // Each call produces 2 checks: valid-held + data-after-release.
    // -----------------------------------------------------------
    task stall_test;
        input [7:0] pay;
        input [1:0] ctl;
        input integer stall_cyc;
        integer i;
        begin
            // TX phase
            @(negedge clk);
            tx_payload = pay;
            tx_ctrl    = ctl;
            tx_valid   = 1'b1;
            rx_ready   = 1'b0;   // downstream not ready
            @(posedge clk); #1;  // TX latches
            rx_line_reg       = tx_line;
            rx_line_valid_reg = tx_line_valid;
            tx_valid = 1'b0;

            @(posedge clk); #1;  // RX latches word, but cannot drain (rx_ready=0)

            // Hold stall
            for (i = 1; i < stall_cyc; i = i + 1) begin
                @(posedge clk); #1;
            end

            // Check rx_valid is held while stalled
            test_num = test_num + 1;
            if (rx_valid === 1'b1) begin
                $display("PASS  [%0d] stall=%0d cyc, rx_valid held", test_num, stall_cyc);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL  [%0d] stall=%0d cyc, rx_valid lost (got %0b)", test_num, stall_cyc, rx_valid);
                fail_cnt = fail_cnt + 1;
            end

            // Release downstream
            rx_ready = 1'b1;
            @(posedge clk); #1;

            // Check correct data was preserved
            test_num = test_num + 1;
            if (rx_payload === pay && rx_ctrl === ctl) begin
                $display("PASS  [%0d] stall release: pay=%02h ctrl=%02b OK", test_num, pay, ctl);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL  [%0d] stall release: exp pay=%02h ctrl=%02b got pay=%02h ctrl=%02b",
                         test_num, pay, ctl, rx_payload, rx_ctrl);
                fail_cnt = fail_cnt + 1;
            end

            // Clear loopback line
            @(negedge clk);
            rx_line_reg       = 10'b0;
            rx_line_valid_reg = 1'b0;
            rx_ready          = 1'b1;
            @(posedge clk); #1;
        end
    endtask

    // -----------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------
    integer i;
    reg [7:0] lfsr_state;

    initial begin
        pass_cnt      = 0;
        fail_cnt      = 0;
        test_num      = 0;

        // Reset
        rst_n             = 1'b0;
        tx_payload        = 8'h00;
        tx_ctrl           = 2'b00;
        tx_valid          = 1'b0;
        rx_ready          = 1'b1;
        rx_line_reg       = 10'b0;
        rx_line_valid_reg = 1'b0;

        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        // =======================================================
        // GROUP A: 8 Deterministic ctrl/data patterns
        // =======================================================
        $display("=== GROUP A: Deterministic patterns ===");

        // A1: IDLE word (ctrl=00, payload=0x00)
        drive_and_check_loopback(8'h00, 2'b00);

        // A2: K-comma (ctrl=11, payload=0xBC = K28.5 data byte)
        drive_and_check_loopback(8'hBC, 2'b11);

        // A3: K-SOS Start-of-Stream (ctrl=10, payload=0xFB)
        drive_and_check_loopback(8'hFB, 2'b10);

        // A4: K-EOS End-of-Stream (ctrl=01, payload=0xFD)
        drive_and_check_loopback(8'hFD, 2'b01);

        // A5: Data burst — all-ones payload (ctrl=00)
        drive_and_check_loopback(8'hFF, 2'b00);

        // A6: Data burst — all-ones with ctrl=11
        drive_and_check_loopback(8'hFF, 2'b11);

        // A7: Alternating pattern 0xAA (ctrl=01)
        drive_and_check_loopback(8'hAA, 2'b01);

        // A8: Alternating pattern 0x55 (ctrl=10)
        drive_and_check_loopback(8'h55, 2'b10);

        // =======================================================
        // GROUP B: 50 LFSR random payload streams TX→RX loopback
        // =======================================================
        $display("=== GROUP B: LFSR loopback (50 words) ===");
        lfsr_state = 8'hA5; // seed
        for (i = 0; i < 50; i = i + 1) begin
            lfsr_state = lfsr_next(lfsr_state);
            // ctrl = low 2 bits of payload (exercises all ctrl combinations)
            drive_and_check_loopback(lfsr_state, lfsr_state[1:0]);
        end

        // =======================================================
        // GROUP C: 4 Handshake stall tests (2 checks each = 8 total)
        // =======================================================
        $display("=== GROUP C: Handshake stall tests ===");

        // C1: Stall 1 cycle
        stall_test(8'hDE, 2'b10, 1);

        // C2: Stall 2 cycles
        stall_test(8'hAD, 2'b01, 2);

        // C3: Stall 3 cycles
        stall_test(8'hBE, 2'b11, 3);

        // C4: Stall 4 cycles
        stall_test(8'hEF, 2'b00, 4);

        // =======================================================
        // Summary
        // =======================================================
        $display("=== SUMMARY: %0d PASS  %0d FAIL  (total %0d) ===",
                 pass_cnt, fail_cnt, pass_cnt + fail_cnt);

        if (fail_cnt == 0 && (pass_cnt + fail_cnt) >= 62) begin
            $display("D2D_SERDES_STUB_GREEN");
        end else begin
            $display("D2D_SERDES_STUB_RED: fail=%0d pass=%0d (need>=62 total)", fail_cnt, pass_cnt);
        end

        $finish;
    end

endmodule
