// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// tb_voltage_island_marker.v — Testbench for voltage_island_marker
// TT-Shuttle GF16 · Lane L-S30 Voltage Island
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// Verifies:
//   T1: island_en all-zeros → lp_island_status all-zeros, island_active=0
//   T2: island_en all-ones, all blocks healthy → lp_island_status=3'b111,
//       island_active=1, marker_ok=1
//   T3: island_en[1]=1 only (restraint_ctrl) → only bit[1] set
//   T4: island_en[2]=1 but k3_alu_ok=0 (unhealthy) → status[2]=0, marker_ok=0
//   T5: island_id always = 2'b01
//   T6: crown47_rom ROM content spot-checks (addr 0=φ, addr 14=L₈=47)
//   T7: restraint_ctrl FSM: throttle asserts after 256+1 warn cycles, releases
//
// Pure Verilog-2005. No SystemVerilog.

`default_nettype none
`timescale 1ns/1ps

module tb_voltage_island_marker;

    // DUT ports
    reg         clk;
    reg         rst_n;
    reg         crown47_ok_r;
    reg         restraint_ok_r;
    reg         k3_alu_ok_r;
    reg  [2:0]  island_en_r;

    wire [2:0]  lp_island_status;
    wire        island_active;
    wire [1:0]  island_id;
    wire        marker_ok;

    // crown47_rom DUT
    reg  [5:0]  rom_addr;
    wire [7:0]  rom_data;
    wire        rom_ok_w;

    // restraint_ctrl DUT
    reg         entropy_warn_r;
    reg         entropy_ok_r;
    wire        throttle_en_w;
    wire [1:0]  state_dbg_w;
    wire        ctrl_ok_w;

    // Instantiate marker
    voltage_island_marker u_marker (
        .clk              (clk),
        .rst_n            (rst_n),
        .crown47_ok       (crown47_ok_r),
        .restraint_ok     (restraint_ok_r),
        .k3_alu_ok        (k3_alu_ok_r),
        .island_en        (island_en_r),
        .lp_island_status (lp_island_status),
        .island_active    (island_active),
        .island_id        (island_id),
        .marker_ok        (marker_ok)
    );

    // Instantiate crown47_rom
    crown47_rom u_rom (
        .addr   (rom_addr),
        .data   (rom_data),
        .rom_ok (rom_ok_w)
    );

    // Instantiate restraint_ctrl
    restraint_ctrl u_rctrl (
        .clk          (clk),
        .rst_n        (rst_n),
        .entropy_warn (entropy_warn_r),
        .entropy_ok   (entropy_ok_r),
        .throttle_en  (throttle_en_w),
        .state_dbg    (state_dbg_w),
        .ctrl_ok      (ctrl_ok_w)
    );

    // Clock: 10 ns period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Test counter
    integer pass_cnt;
    integer fail_cnt;

    task check;
        input [63:0] got;
        input [63:0] exp;
        input [127:0] label;
        begin
            if (got === exp) begin
                $display("  PASS %s : got %0d", label, got);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL %s : got %0d, expected %0d", label, got, exp);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // Helper: cycle
    task tick;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge clk);
        end
    endtask

    integer j;

    initial begin
        pass_cnt      = 0;
        fail_cnt      = 0;
        rst_n         = 1'b0;
        crown47_ok_r  = 1'b0;
        restraint_ok_r= 1'b0;
        k3_alu_ok_r   = 1'b0;
        island_en_r   = 3'b000;
        entropy_warn_r= 1'b0;
        entropy_ok_r  = 1'b1;
        rom_addr      = 6'd0;

        // Release reset
        @(posedge clk); #1;
        rst_n = 1'b1;
        @(posedge clk); #1;

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== T1: island_en=0, all blocks healthy ===");
        island_en_r   = 3'b000;
        crown47_ok_r  = 1'b1;
        restraint_ok_r= 1'b1;
        k3_alu_ok_r   = 1'b1;
        #1;
        check(lp_island_status, 3'b000,  "T1 lp_island_status");
        check(island_active,    1'b0,    "T1 island_active");
        check(marker_ok,        1'b1,    "T1 marker_ok");

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== T2: island_en=3'b111, all blocks healthy ===");
        island_en_r   = 3'b111;
        crown47_ok_r  = 1'b1;
        restraint_ok_r= 1'b1;
        k3_alu_ok_r   = 1'b1;
        #1;
        check(lp_island_status, 3'b111,  "T2 lp_island_status");
        check(island_active,    1'b1,    "T2 island_active");
        check(marker_ok,        1'b1,    "T2 marker_ok");
        check(island_id,        2'b01,   "T2 island_id=S30");

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== T3: only restraint_ctrl in island ===");
        island_en_r   = 3'b010;
        crown47_ok_r  = 1'b1;
        restraint_ok_r= 1'b1;
        k3_alu_ok_r   = 1'b1;
        #1;
        check(lp_island_status, 3'b010,  "T3 lp_island_status");
        check(island_active,    1'b1,    "T3 island_active");
        check(lp_island_status[0], 1'b0, "T3 crown47 not in island");
        check(lp_island_status[2], 1'b0, "T3 k3_alu not in island");

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== T4: k3_alu enabled but unhealthy ===");
        island_en_r   = 3'b100;
        crown47_ok_r  = 1'b1;
        restraint_ok_r= 1'b1;
        k3_alu_ok_r   = 1'b0;   // unhealthy
        #1;
        check(lp_island_status[2], 1'b0, "T4 status[2]=0 when unhealthy");
        check(marker_ok,           1'b0, "T4 marker_ok=0 when enabled block unhealthy");

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== T5: island_id static check ===");
        island_en_r = 3'b000;
        #1;
        check(island_id, 2'b01, "T5 island_id=2'b01 always");

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== T6: crown47_rom content spot-checks ===");
        rom_addr = 6'd0;  #1; check(rom_data, 8'h33, "T6 addr0=phi(0x33)");
        rom_addr = 6'd1;  #1; check(rom_data, 8'h53, "T6 addr1=phi2(0x53)");
        rom_addr = 6'd8;  #1; check(rom_data, 8'd3,  "T6 addr8=L2=3");
        rom_addr = 6'd14; #1; check(rom_data, 8'd47, "T6 addr14=L8=47");
        rom_addr = 6'd40; #1; check(rom_data, 8'd47, "T6 addr40=prime47");
        rom_addr = 6'd46; #1; check(rom_data, 8'd23, "T6 addr46=prime23");
        check(rom_ok_w,    1'b1,   "T6 rom_ok=1");

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== T7: restraint_ctrl FSM — throttle after 256 warn cycles ===");
        // Reset FSM
        rst_n = 1'b0; tick(2); rst_n = 1'b1; tick(1);

        // Apply entropy_warn for 256 + a few extra cycles → should enter THROTTLE
        entropy_warn_r = 1'b1;
        entropy_ok_r   = 1'b0;

        // After reset, state=IDLE → WATCH after first warn
        tick(1);
        check(state_dbg_w, 2'b01, "T7 state=WATCH after warn");

        // Tick 255 more (total 256 warn cycles in WATCH)
        tick(255);
        // On cycle 256 (guard_cnt==0xFF), state should go to THROTTLE
        tick(1);
        check(state_dbg_w, 2'b10, "T7 state=THROTTLE after 256 warn cycles");
        check(throttle_en_w, 1'b1, "T7 throttle_en asserted");

        // Now assert entropy_ok → should go to RELEASE
        entropy_warn_r = 1'b0;
        entropy_ok_r   = 1'b1;
        tick(1);
        check(state_dbg_w, 2'b11, "T7 state=RELEASE on entropy_ok");
        check(throttle_en_w, 1'b1, "T7 throttle still asserted during RELEASE");

        // Wait 256 release cycles → IDLE
        tick(256);
        check(state_dbg_w, 2'b00, "T7 state=IDLE after 256 release cycles");
        check(throttle_en_w, 1'b0, "T7 throttle deasserted in IDLE");

        // ─────────────────────────────────────────────────────────────────
        $display("\n=== Summary ===");
        $display("PASS: %0d  FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("ALL TESTS PASSED — L-S30 voltage island marker verified");
        else
            $display("FAILURES DETECTED — review output above");

        $finish;
    end

    // Watchdog: abort if stuck
    initial begin
        #200000;
        $display("TIMEOUT — watchdog fired");
        $finish;
    end

endmodule
`default_nettype wire
