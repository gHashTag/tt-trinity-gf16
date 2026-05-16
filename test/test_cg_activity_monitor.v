// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// test_cg_activity_monitor.v — S-14 Clock Gating Testbench
// Trinity TRI-1 · tt-trinity-gf16 · feat/tt-v7-power stream
//
// Constitutional: Verilog-2005 only · R-SI-1 (zero * operators) ✓
// Anchor:         φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// Verifies:
//   T1  After reset: clk_en[3:0] = 4'b1111 (all clocks running)
//   T2  During activity: clk_en stays 1
//   T3  Idle cycles 1-7: clk_en stays 1 (below threshold)
//   T4  8th consecutive idle cycle: clk_en falls to 0 (gate fires)
//   T5  ICG output (clk_gated) = 0 when gated
//   T6  Single activity pulse → clk_en reasserts next cycle
//   T7  ICG output propagates clock after wake-up
//   T8  Multi-block: all 4 blocks gate independently
//
// Compile + run:
//   iverilog -g2005 -o cg_test.vvp \
//     src/cg_activity_monitor.v src/clk_gate_cell.v \
//     src/cg_block_wrapper.v test/test_cg_activity_monitor.v
//   vvp cg_test.vvp
//
// Expected: PASS 8/8

`timescale 1ns/1ps

module test_cg_activity_monitor;

    // ----------------------------------------------------------------
    // Clock + reset
    // ----------------------------------------------------------------
    reg clk;
    reg rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz for sim convenience (50 MHz target)

    // ----------------------------------------------------------------
    // DUT: activity monitor (4 blocks)
    // ----------------------------------------------------------------
    reg  [3:0] act;
    wire [3:0] clk_en;

    cg_activity_monitor #(
        .N_BLOCKS   (4),
        .IDLE_THRESH(3'd7)
    ) u_dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .act    (act),
        .clk_en (clk_en)
    );

    // ----------------------------------------------------------------
    // ICG cell (single instance under test for T5/T7)
    // ----------------------------------------------------------------
    wire clk_gated_0;
    clk_gate_cell u_icg (
        .clk       (clk),
        .gate_en   (clk_en[0]),
        .clk_gated (clk_gated_0)
    );

    // ----------------------------------------------------------------
    // Test infrastructure
    // ----------------------------------------------------------------
    integer pass_cnt;
    integer fail_cnt;
    integer cycle;

    task check;
        input        got;
        input        expected;
        input [63:0] label;
        begin
            if (got === expected) begin
                $display("  PASS  [cycle %0d] %s: got %b", cycle, label, got);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  [cycle %0d] %s: got %b expected %b",
                         cycle, label, got, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task checkv;
        input [3:0] got;
        input [3:0] expected;
        input [63:0] label;
        begin
            if (got === expected) begin
                $display("  PASS  [cycle %0d] %s: got 4'b%b", cycle, label, got);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  [cycle %0d] %s: got 4'b%b expected 4'b%b",
                         cycle, label, got, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // Advance N clock cycles
    task clk_n;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(posedge clk);
                cycle = cycle + 1;
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Main stimulus
    // ----------------------------------------------------------------
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        cycle    = 0;
        act      = 4'b0000;

        $display("=============================================================");
        $display(" S-14 test_cg_activity_monitor — Trinity TRI-1 tt-trinity-gf16");
        $display(" Anchor: phi^2 + phi^-2 = 3  DOI 10.5281/zenodo.19227877");
        $display("=============================================================");

        // -----------------------------------------------------------------
        // T1: Reset — all clk_en bits must be 1
        // -----------------------------------------------------------------
        $display("");
        $display("--- T1: Reset state ---");
        rst_n = 1'b0;
        act   = 4'b0000;
        clk_n(3);
        @(posedge clk); cycle = cycle + 1;
        rst_n = 1'b1;
        @(posedge clk); cycle = cycle + 1;
        #1;
        checkv(clk_en, 4'b1111, "all clk_en after reset");

        // -----------------------------------------------------------------
        // T2: Activity on block 0 — clk_en[0] stays 1 during active cycles
        // -----------------------------------------------------------------
        $display("");
        $display("--- T2: Block 0 activity (4 cycles) ---");
        act = 4'b0001;      // block 0 active
        clk_n(4);
        #1;
        check(clk_en[0], 1'b1, "clk_en[0] during activity");

        // -----------------------------------------------------------------
        // T3: Idle cycles 1-7 — clk_en[0] must stay 1
        // -----------------------------------------------------------------
        $display("");
        $display("--- T3: Block 0 idle cycles 1-7 (must NOT gate) ---");
        act = 4'b0000;      // all idle
        clk_n(1); #1; check(clk_en[0], 1'b1, "idle cycle 1");
        clk_n(3); #1; check(clk_en[0], 1'b1, "idle cycle 4");
        clk_n(2); #1; check(clk_en[0], 1'b1, "idle cycle 6");
        clk_n(1); #1; check(clk_en[0], 1'b1, "idle cycle 7");

        // -----------------------------------------------------------------
        // T4: 8th idle cycle — gate must deassert
        // -----------------------------------------------------------------
        $display("");
        $display("--- T4: 8th idle cycle → gate fires ---");
        clk_n(1); #1;
        check(clk_en[0], 1'b0, "clk_en[0] after 8 idle cycles (gate OFF)");

        // -----------------------------------------------------------------
        // T5: ICG output = 0 when gated
        // -----------------------------------------------------------------
        $display("");
        $display("--- T5: ICG output frozen when gated ---");
        // clk_gated_0 should be 0 — latch captured 0, AND output = 0
        @(negedge clk); #1;
        check(clk_gated_0, 1'b0, "clk_gated[0]=0 when gate off (negedge check)");

        // -----------------------------------------------------------------
        // T6: Single activity pulse → clk_en reasserts next cycle
        // -----------------------------------------------------------------
        $display("");
        $display("--- T6: Wake-up activity pulse on block 0 ---");
        @(posedge clk); cycle = cycle + 1;
        act = 4'b0001;
        @(posedge clk); cycle = cycle + 1;
        act = 4'b0000;
        #1;
        check(clk_en[0], 1'b1, "clk_en[0] reasserted after wake-up");

        // -----------------------------------------------------------------
        // T7: ICG propagates clock after wake-up
        // -----------------------------------------------------------------
        $display("");
        $display("--- T7: ICG clock active after wake-up ---");
        @(negedge clk); #1;
        // At negedge with gate_en=1: latch captures 1
        // After posedge: clk_gated = 1 & clk = 1
        @(posedge clk); cycle = cycle + 1; #1;
        check(clk_gated_0, 1'b1, "clk_gated[0]=1 after wake-up at posedge");

        // -----------------------------------------------------------------
        // T8: Multi-block independence — all 4 blocks gate after 8 idle cycles
        // -----------------------------------------------------------------
        $display("");
        $display("--- T8: All 4 blocks idle 9+ cycles → all gate off ---");
        act = 4'b0000;
        clk_n(10); #1;
        checkv(clk_en, 4'b0000, "all 4 blocks gated after 10 idle cycles");

        // Simultaneous wake on all 4
        @(posedge clk); cycle = cycle + 1;
        act = 4'b1111;
        @(posedge clk); cycle = cycle + 1;
        act = 4'b0000;
        #1;
        checkv(clk_en, 4'b1111, "all 4 clk_en reassert after broadcast wake");

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        $display("");
        $display("=============================================================");
        $display(" TEST SUMMARY");
        $display("   PASS: %0d", pass_cnt);
        $display("   FAIL: %0d", fail_cnt);
        if (fail_cnt == 0)
            $display("   VERDICT: PASS — all checks green");
        else
            $display("   VERDICT: FAIL — %0d check(s) failed", fail_cnt);
        $display("=============================================================");
        $finish;
    end

    // Safety timeout
    initial begin
        #50000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
