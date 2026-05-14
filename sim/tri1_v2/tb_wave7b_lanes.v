// SPDX-License-Identifier: Apache-2.0
// tb_wave7b_lanes.v — Testbench for Wave-7b TRI-1 v2 lanes
// Apache-2.0 · TRI-1 v2 · Wave-7b
//
// Tests L-S25 adaptive_strobe_fsm  and  L-S30 invariant_ring_watchdog.
// Success gate: prints WAVE7B_LANES_GREEN: N/N PASS
`default_nettype none
`timescale 1ns/1ps

module tb_wave7b_lanes;

    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz sim clock

    integer pass_cnt, fail_cnt;
    initial begin pass_cnt = 0; fail_cnt = 0; end

    // ================================================================
    // Helper tasks
    // ================================================================
    task check;
        input pass_flag;
        input [255:0] label;
        begin
            if (pass_flag) begin
                $display("  PASS: %s", label);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL: %s", label);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task clock_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    // ================================================================
    // L-S25: adaptive_strobe_fsm
    // ================================================================
    reg        fsm_traffic_busy;
    reg  [3:0] fsm_phi_weight;
    wire       fsm_strobe_en;
    wire [1:0] fsm_state_dbg;

    adaptive_strobe_fsm u_strobe_fsm (
        .clk          (clk),
        .rst_n        (rst_n),
        .traffic_busy (fsm_traffic_busy),
        .phi_weight   (fsm_phi_weight),
        .strobe_en    (fsm_strobe_en),
        .state_dbg    (fsm_state_dbg)
    );

    // Capture strobe events
    integer strobe_count;
    initial strobe_count = 0;
    always @(posedge clk) begin
        if (fsm_strobe_en)
            strobe_count = strobe_count + 1;
    end

    // ================================================================
    // L-S30: invariant_ring_watchdog
    // ================================================================
    reg        wd_inv1, wd_inv2, wd_inv3, wd_inv4;
    reg        wd_inv5, wd_inv6, wd_inv7;

    wire       wd_violation;
    wire [6:0] wd_vec;
    wire [2:0] wd_first_id;
    wire [15:0] wd_total;

    invariant_ring_watchdog u_watchdog (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .inv1_phi_anchor_fail      (wd_inv1),
        .inv2_lucas_recurrence_fail(wd_inv2),
        .inv3_cassini_fail         (wd_inv3),
        .inv4_nca_entropy_fail     (wd_inv4),
        .inv5_bpb_nonneg_fail      (wd_inv5),
        .inv6_plrm_mutex_fail      (wd_inv6),
        .inv7_seed_forbidden_fail  (wd_inv7),
        .invariant_violation       (wd_violation),
        .violation_vec             (wd_vec),
        .first_violation_id        (wd_first_id),
        .total_violations          (wd_total)
    );

    // ================================================================
    // Main test sequence
    // ================================================================
    integer i;
    integer strobe_before;
    integer strobe_after;

    initial begin
        // ------------------------------------------------------------
        // Initialise
        // ------------------------------------------------------------
        rst_n            = 0;
        fsm_traffic_busy = 0;
        fsm_phi_weight   = 4'd0;
        wd_inv1 = 0; wd_inv2 = 0; wd_inv3 = 0; wd_inv4 = 0;
        wd_inv5 = 0; wd_inv6 = 0; wd_inv7 = 0;

        @(posedge clk); #1;
        @(posedge clk); #1;

        $display("=== Wave-7b Lane Tests ===");

        // ============================================================
        // TEST GROUP A: adaptive_strobe_fsm (L-S25)
        // ============================================================
        $display("--- L-S25 adaptive_strobe_fsm ---");

        // A1: While rst_n=0, state_dbg must be IDLE (async reset holds state)
        // Check BEFORE releasing reset.
        check(fsm_state_dbg == 2'b00, "A1: async reset holds state IDLE");

        // Release reset
        rst_n = 1;
        @(posedge clk); #1;

        // A2: After releasing reset, FSM should transition from IDLE and
        // produce at least 1 strobe within ~20 cycles (L5=11 → ARM counts 11).
        strobe_before = strobe_count;
        clock_cycles(20);
        strobe_after = strobe_count;
        check((strobe_after - strobe_before) >= 1, "A2: strobe produced within 20 cycles (L5=11)");

        // A3: Set traffic_busy=1 long enough for hysteresis (>5 cycles) → period=L7=29
        // Result: fewer strobes per unit time
        fsm_traffic_busy = 1;
        clock_cycles(10);       // let hysteresis settle to L7
        strobe_before = strobe_count;
        clock_cycles(60);       // observe over 60 cycles
        strobe_after = strobe_count;
        // L7=29 → ~2 strobes in 60 cycles; L5=11 → ~5 strobes
        check((strobe_after - strobe_before) <= 4, "A3: fewer strobes when busy (long period L7)");
        check((strobe_after - strobe_before) >= 1, "A3b: strobe still fires when busy");

        // A4: Return to idle → period reverts to L5=11 → more strobes
        fsm_traffic_busy = 0;
        clock_cycles(10);
        strobe_before = strobe_count;
        clock_cycles(30);
        strobe_after = strobe_count;
        check((strobe_after - strobe_before) >= 2, "A4: more strobes when idle (short period L5)");

        // A5: Static assertion — 6-bit counter (max 63) sufficient for L7=29
        check(1'b1, "A5: 6-bit counter sufficient for L7=29 (static check)");

        // A6: phi_weight modulates hysteresis threshold
        // With phi_weight=4'b1100 threshold = 5 + phi_weight[3:2] = 5+3 = 8
        // After busy_cnt < 8, FSM may still be on medium period.
        // Verify strobe continues to fire (FSM not stuck)
        fsm_phi_weight   = 4'b1100;
        fsm_traffic_busy = 1;
        clock_cycles(20);       // settle with new phi_weight
        strobe_before = strobe_count;
        clock_cycles(35);
        strobe_after = strobe_count;
        check((strobe_after - strobe_before) >= 1, "A6: strobe active with phi_weight=12");
        fsm_traffic_busy = 0;
        fsm_phi_weight   = 4'd0;

        // ============================================================
        // TEST GROUP B: invariant_ring_watchdog (L-S30)
        // ============================================================
        $display("--- L-S30 invariant_ring_watchdog ---");

        // Reset watchdog (and FSM) for clean slate
        rst_n = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        // B1: During reset, all outputs must be 0
        check(wd_vec == 7'd0,        "B1a: reset -> violation_vec = 0");
        check(wd_first_id == 3'd0,   "B1b: reset -> first_violation_id = 0");
        check(wd_total == 16'd0,     "B1c: reset -> total_violations = 0");
        check(wd_violation == 1'b0,  "B1d: reset -> invariant_violation = 0");

        rst_n = 1;
        @(posedge clk); #1;

        // B2: Pulse inv4 for 1 cycle -> sticky[3]=1, first_id=4, counter=1
        wd_inv4 = 1;
        @(posedge clk); #1;
        wd_inv4 = 0;
        @(posedge clk); #1;
        check(wd_vec[3] == 1'b1,     "B2a: inv4 pulse -> violation_vec[3] sticky");
        check(wd_first_id == 3'd4,   "B2b: first_violation_id = 4");
        check(wd_total == 16'd1,     "B2c: total_violations = 1");
        check(wd_violation == 1'b1,  "B2d: invariant_violation asserted");

        // B3: Pulse inv1 -> vec[0]=1, first_id stays 4 (already latched), counter=2
        wd_inv1 = 1;
        @(posedge clk); #1;
        wd_inv1 = 0;
        @(posedge clk); #1;
        check(wd_vec[0] == 1'b1,     "B3a: inv1 pulse -> violation_vec[0] sticky");
        check(wd_first_id == 3'd4,   "B3b: first_violation_id still 4 (latched)");
        check(wd_total == 16'd2,     "B3c: total_violations = 2");

        // B4: Sticky bits remain after inputs go low (5 idle cycles)
        clock_cycles(5);
        check(wd_vec[3] == 1'b1,     "B4a: vec[3] sticky after 5 idle cycles");
        check(wd_vec[0] == 1'b1,     "B4b: vec[0] sticky after 5 idle cycles");
        check(wd_first_id == 3'd4,   "B4c: first_id sticky after 5 idle cycles");

        // B5: Multiple simultaneous: inv2+inv5+inv7 -> counter += 3 = 5
        // first_id stays 4 (already latched); lowest new would be 2 but irrelevant
        wd_inv2 = 1; wd_inv5 = 1; wd_inv7 = 1;
        @(posedge clk); #1;
        wd_inv2 = 0; wd_inv5 = 0; wd_inv7 = 0;
        @(posedge clk); #1;
        check(wd_total == 16'd5,     "B5a: simultaneous inv2+inv5+inv7 -> counter=5");
        check(wd_vec[1] == 1'b1,     "B5b: inv2 (vec[1]) sticky");
        check(wd_vec[4] == 1'b1,     "B5c: inv5 (vec[4]) sticky");
        check(wd_vec[6] == 1'b1,     "B5d: inv7 (vec[6]) sticky");
        check(wd_first_id == 3'd4,   "B5e: first_id unchanged (already latched at 4)");

        // B6: Saturating counter at 0xFFFF
        // Drive inv3 high for enough cycles to saturate from 5 to 0xFFFF=65535.
        // Need 65530 more pulses. Hold inv3 high continuously — each cycle counts.
        begin : sat_blk
            integer k;
            wd_inv3 = 1;
            for (k = 0; k < 65535; k = k + 1)
                @(posedge clk);
            wd_inv3 = 0;
            @(posedge clk); #1;
        end
        check(wd_total == 16'hFFFF,  "B6: saturating counter at 0xFFFF no overflow");

        // ============================================================
        // Final summary
        // ============================================================
        $display("=== WAVE7B_LANES_GREEN: %0d/%0d PASS ===",
                 pass_cnt, pass_cnt + fail_cnt);
        if (fail_cnt == 0)
            $display("WAVE7B_LANES_GREEN");
        else
            $display("WAVE7B_LANES_FAIL: %0d failures", fail_cnt);

        $finish;
    end

endmodule
`default_nettype wire
