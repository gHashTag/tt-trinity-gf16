// SPDX-License-Identifier: Apache-2.0
// Author: Dmitrii Vasilev <admin@t27.ai>
//
// tb_sram_ternary_bridge.v — Testbench for L-S39 sram_ternary_bridge
//
// Tests:
//   8  deterministic write-then-read patterns (DET_0 .. DET_7)
//   80 LFSR-random streams (LFSR_0 .. LFSR_79)
//   Total = 88 tests
//
// PASS token: SRAM_TERN_BRIDGE_GREEN
//
// Golden reference: phi_prior_quantizer rule (Wave-9b L-S37 byte-for-byte):
//   |w| >= 12533 (Q1.15) => sign(w): +1 => 2'b00, -1 => 2'b10
//   |w| <  12533         => 0            => 2'b01
//
// Write timing:
//   t=0 : wr_valid=1, wr_fp_in=X  → quantizer starts (combinational)
//   t=1 : quantizer pipe register captures result
//   t=1 : wr_valid_d=1, wr_lane_cnt advances
//   t=1 (if lane 7): sram_we registered
//   t=2 : SRAM word written
//   → for a burst of 8 writes starting at cycle 0, SRAM word ready at cycle 10
//
// Read timing:
//   t=N : rd_en=1 → rd_data valid at t=N+1

`default_nettype none
`timescale 1ns/1ps

module tb_sram_ternary_bridge;

    // ------------------------------------------------------------------
    // Clock / reset
    // ------------------------------------------------------------------
    reg clk, rst_n;
    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // ------------------------------------------------------------------
    // DUT signals
    // ------------------------------------------------------------------
    reg         wr_valid;
    reg  [15:0] wr_fp_in;
    reg         rd_en;
    wire [15:0] rd_data;
    wire        full, empty;

    sram_ternary_bridge #(
        .N_CELLS (16384),
        .LANES   (8)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_valid (wr_valid),
        .wr_fp_in (wr_fp_in),
        .rd_en    (rd_en),
        .rd_data  (rd_data),
        .full     (full),
        .empty    (empty)
    );

    // ------------------------------------------------------------------
    // Golden quantizer reference (pure combinational function)
    // ------------------------------------------------------------------
    localparam signed [15:0] PHI_INV_SQ = 16'sd12533;

    function [1:0] golden_quant;
        input signed [15:0] w;
        reg signed [16:0] w_wide;
        reg signed [16:0] thr_wide;
        begin
            w_wide  = {{1{w[15]}}, w};
            thr_wide = {{1{PHI_INV_SQ[15]}}, PHI_INV_SQ};
            if (w_wide >= thr_wide)
                golden_quant = 2'b00;  // +1
            else if (w_wide <= -thr_wide)
                golden_quant = 2'b10;  // -1
            else
                golden_quant = 2'b01;  // 0
        end
    endfunction

    // Build expected 16-bit word from 8 FP values
    function [15:0] golden_word;
        input signed [15:0] w0, w1, w2, w3, w4, w5, w6, w7;
        begin
            golden_word = { golden_quant(w7), golden_quant(w6),
                            golden_quant(w5), golden_quant(w4),
                            golden_quant(w3), golden_quant(w2),
                            golden_quant(w1), golden_quant(w0) };
        end
    endfunction

    // ------------------------------------------------------------------
    // Test counters
    // ------------------------------------------------------------------
    integer pass_cnt, fail_cnt, test_id;
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        test_id  = 0;
    end

    // ------------------------------------------------------------------
    // Task: write 8 FP values and read back, check against golden
    // ------------------------------------------------------------------
    // fp_vals[0..7] stored as a 128-bit vector (FP0 at [15:0])
    task write_read_check;
        input [127:0] fp_vec;   // fp_vec[15:0]=w0 .. fp_vec[127:112]=w7
        input [31:0]  tid;
        reg  [15:0] w [0:7];
        reg  [15:0] expected;
        reg  [15:0] got;
        integer k;
        begin
            // Unpack
            w[0] = fp_vec[15:0];
            w[1] = fp_vec[31:16];
            w[2] = fp_vec[47:32];
            w[3] = fp_vec[63:48];
            w[4] = fp_vec[79:64];
            w[5] = fp_vec[95:80];
            w[6] = fp_vec[111:96];
            w[7] = fp_vec[127:112];

            expected = golden_word(w[0], w[1], w[2], w[3],
                                   w[4], w[5], w[6], w[7]);

            // Reset DUT for clean state
            @(negedge clk);
            rst_n    = 1'b0;
            wr_valid = 1'b0;
            rd_en    = 1'b0;
            @(negedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            @(negedge clk);

            // Write 8 FP values on consecutive cycles
            for (k = 0; k < 8; k = k + 1) begin
                wr_valid = 1'b1;
                wr_fp_in = w[k];
                @(negedge clk);
            end
            wr_valid = 1'b0;
            wr_fp_in = 16'd0;

            // Wait for SRAM write to complete:
            // write latency = 1 (quant pipe) + 1 (lane_hold update aligned with sram_we_d)
            // sram_we fires after lane 7 captured → SRAM written 1 more cycle later
            // Total cycles after last wr_valid de-asserted: 3 extra cycles
            @(negedge clk);
            @(negedge clk);
            @(negedge clk);

            // Read word 0
            rd_en = 1'b1;
            @(negedge clk);
            rd_en = 1'b0;
            @(negedge clk);  // rd_data valid now
            got = rd_data;

            if (got === expected) begin
                pass_cnt = pass_cnt + 1;
                $display("PASS [%0d] tid=%0d expected=%04h got=%04h", pass_cnt + fail_cnt, tid, expected, got);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("FAIL [%0d] tid=%0d expected=%04h got=%04h", pass_cnt + fail_cnt, tid, expected, got);
            end
            test_id = test_id + 1;
        end
    endtask

    // ------------------------------------------------------------------
    // LFSR: 16-bit Fibonacci LFSR (taps 16,15,13,4)
    // poly: x^16 + x^15 + x^13 + x^4 + 1
    // ------------------------------------------------------------------
    function [15:0] lfsr_next;
        input [15:0] state;
        reg feedback;
        begin
            feedback  = state[15] ^ state[14] ^ state[12] ^ state[3];
            lfsr_next = {state[14:0], feedback};
        end
    endfunction

    function [15:0] lfsr_n;
        input [15:0] seed;
        input [7:0]  n;
        integer i;
        reg [15:0] s;
        begin
            s = seed;
            for (i = 0; i < n; i = i + 1)
                s = lfsr_next(s);
            lfsr_n = s;
        end
    endfunction

    // ------------------------------------------------------------------
    // 8 Deterministic tests
    // ------------------------------------------------------------------
    // DET_0: all zeros → all 0 ternary → 0101_0101_0101_0101 = 0x5555
    // DET_1: all +1 (max positive = 0x7FFF) → all +1 ternary → 0000...0000 = 0x0000
    // DET_2: all -1 (most negative = 0x8000) → all -1 ternary → 1010...1010 = 0xAAAA
    // DET_3: all just at threshold +12533 → +1 → 0x0000
    // DET_4: all just below threshold +12532 → 0 → 0x5555
    // DET_5: all just at negative threshold -12533 → -1 → 0xAAAA
    // DET_6: all just above negative threshold -12532 → 0 → 0x5555
    // DET_7: mixed {+12534, -12534, +12532, -12532, 0, 0x7FFF, 0x8001, 1}
    //        expected: +1(-1, 0, 0, 01,+1,-1, 0)
    //        w0=+12534→+1(00), w1=-12534→-1(10), w2=+12532→0(01), w3=-12532→0(01)
    //        w4=0→0(01), w5=0x7FFF=+32767→+1(00), w6=0x8001=-32767→-1(10), w7=1→0(01)
    //        word = {01,10,00,01,01,01,10,00} = bits[15:0]:
    //        lane7=01, lane6=10, lane5=00, lane4=01, lane3=01, lane2=01, lane1=10, lane0=00
    //        = 01_10_00_01_01_01_10_00 = 0110 0001 0101 1000 = wait, let me be careful
    //        assembled[1:0]=w0=00(+1), [3:2]=w1=10(-1), [5:4]=w2=01(0),
    //                       [7:6]=w3=01(0), [9:8]=w4=01(0), [11:10]=w5=00(+1),
    //                       [13:12]=w6=10(-1), [15:14]=w7=01(0)
    //        = 01_10_00_01_01_01_10_00
    //        = 0110 0001 0101 1000 → 0x6158? Let me compute:
    //        bit15-14=01=0x4000, bit13-12=10=0x2000, bit11-10=00=0, bit9-8=01=0x0100,
    //        bit7-6=01=0x0040, bit5-4=01=0x0010, bit3-2=10=0x0008, bit1-0=00=0
    //        = 0x4000+0x2000+0x0100+0x0040+0x0010+0x0008 = 0x6158
    // (golden_word function handles this correctly — no need to manually verify)

    // ------------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------------
    integer lfsr_seed;
    integer lfsr_i;
    reg [15:0] lv [0:7];
    reg [127:0] fp_vec;
    integer lfs;

    initial begin
        $dumpfile("tb_sram_ternary_bridge.vcd");
        $dumpvars(0, tb_sram_ternary_bridge);

        wr_valid = 1'b0;
        wr_fp_in = 16'd0;
        rd_en    = 1'b0;
        rst_n    = 1'b0;

        @(negedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // ============================================================
        // DETERMINISTIC TESTS (8)
        // ============================================================

        // DET_0: all zeros → 0x5555
        write_read_check(128'h0000_0000_0000_0000_0000_0000_0000_0000, 32'd0);

        // DET_1: all 0x7FFF (+32767) → 0x0000
        write_read_check(128'h7FFF_7FFF_7FFF_7FFF_7FFF_7FFF_7FFF_7FFF, 32'd1);

        // DET_2: all 0x8000 (-32768) → 0xAAAA
        write_read_check(128'h8000_8000_8000_8000_8000_8000_8000_8000, 32'd2);

        // DET_3: all +12533 (0x30F5) → +1 → 0x0000
        write_read_check(128'h30F5_30F5_30F5_30F5_30F5_30F5_30F5_30F5, 32'd3);

        // DET_4: all +12532 (0x30F4) → 0 → 0x5555
        write_read_check(128'h30F4_30F4_30F4_30F4_30F4_30F4_30F4_30F4, 32'd4);

        // DET_5: all -12533 (signed: 16'sd-12533 = 16'hCF0B) → -1 → 0xAAAA
        // -12533 in two's complement 16-bit: 65536 - 12533 = 53003 = 0xCF0B
        write_read_check(128'hCF0B_CF0B_CF0B_CF0B_CF0B_CF0B_CF0B_CF0B, 32'd5);

        // DET_6: all -12532 (0xCF0C) → 0 → 0x5555
        // -12532: 65536 - 12532 = 53004 = 0xCF0C
        write_read_check(128'hCF0C_CF0C_CF0C_CF0C_CF0C_CF0C_CF0C_CF0C, 32'd6);

        // DET_7: mixed pattern (golden_word handles the expected value)
        // w0=+12534(0x30F6), w1=-12534(0xCF0A), w2=+12532(0x30F4), w3=-12532(0xCF0C)
        // w4=0(0x0000), w5=+32767(0x7FFF), w6=-32767(0x8001), w7=+1(0x0001)
        write_read_check(128'h0001_8001_7FFF_0000_CF0C_30F4_CF0A_30F6, 32'd7);

        // ============================================================
        // LFSR RANDOM TESTS (80)
        // ============================================================
        // Seeds spaced 820 apart starting at 200 to guarantee
        // each stream contains at least one +1 or -1 ternary value,
        // providing comprehensive coverage of all ternary symbols.
        for (lfsr_seed = 0; lfsr_seed < 80; lfsr_seed = lfsr_seed + 1) begin
            // seed = 200 + lfsr_seed * 820 (mod 65536)
            lfs = (200 + lfsr_seed * 820) & 16'hFFFF;
            // Generate 8 values by iterating LFSR
            lv[0] = lfsr_n(lfs[15:0], 8'd1);
            lv[1] = lfsr_n(lfs[15:0], 8'd2);
            lv[2] = lfsr_n(lfs[15:0], 8'd3);
            lv[3] = lfsr_n(lfs[15:0], 8'd4);
            lv[4] = lfsr_n(lfs[15:0], 8'd5);
            lv[5] = lfsr_n(lfs[15:0], 8'd6);
            lv[6] = lfsr_n(lfs[15:0], 8'd7);
            lv[7] = lfsr_n(lfs[15:0], 8'd8);

            fp_vec = { lv[7], lv[6], lv[5], lv[4],
                       lv[3], lv[2], lv[1], lv[0] };
            write_read_check(fp_vec, 32'd8 + lfsr_seed);
        end

        // ============================================================
        // Final result
        // ============================================================
        $display("----------------------------------------------");
        $display("RESULTS: PASS=%0d  FAIL=%0d  TOTAL=%0d",
                  pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0 && pass_cnt == 88)
            $display("SRAM_TERN_BRIDGE_GREEN");
        else
            $display("SRAM_TERN_BRIDGE_RED fail=%0d pass=%0d", fail_cnt, pass_cnt);
        $finish;
    end

    // Timeout watchdog: 200000 ns
    initial begin
        #200000;
        $display("TIMEOUT: SRAM_TERN_BRIDGE_RED");
        $finish;
    end

endmodule

`default_nettype wire
