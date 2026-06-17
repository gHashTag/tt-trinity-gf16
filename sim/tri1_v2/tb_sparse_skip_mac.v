`default_nettype none
`timescale 1ns/1ps
// tb_sparse_skip_mac.v — Testbench for sparse_skip_mac (L-S34)
// Apache-2.0 · TRI-1 v2
//
// Tests:
//   T1: both non-zero → MAC executed, skipped=0
//   T2: a=0            → skipped=1, dot_out=0
//   T3: b=0            → skipped=1, dot_out=0
//   T4: 100 random cycles, ~33% zero-a → skip_count ≈ 33
//   T5: saturating counter at 0xFFFF
// Gate: SPARSE_SKIP_MAC_GREEN: N/N PASS

module tb_sparse_skip_mac;

    // DUT ports
    reg         clk;
    reg         rst_n;
    reg  [15:0] a_trits;
    reg  [15:0] b_trits;
    reg         valid_in;
    wire [7:0]  dot_out;
    wire        valid_out;
    wire        skipped;
    wire [15:0] skip_count;

    // Instantiate DUT
    sparse_skip_mac dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .a_trits    (a_trits),
        .b_trits    (b_trits),
        .valid_in   (valid_in),
        .dot_out    (dot_out),
        .valid_out  (valid_out),
        .skipped    (skipped),
        .skip_count (skip_count)
    );

    // Clock: 10 ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Counters
    integer pass_count;
    integer fail_count;

    // Captured outputs after each apply
    reg  cap_skipped;
    reg  cap_valid;
    reg  [7:0] cap_dot;
    reg  [15:0] cap_sc;

    // -----------------------------------------------------------------------
    // Task: drive inputs for one valid cycle, capture registered outputs
    // Inputs are set before posedge; outputs are sampled one cycle later.
    // -----------------------------------------------------------------------
    task apply_and_capture;
        input [15:0] ta, tb;
        begin
            // Drive inputs and valid_in high; latch on next posedge
            @(negedge clk);
            a_trits  = ta;
            b_trits  = tb;
            valid_in = 1'b1;
            @(posedge clk); // DUT latches here
            #1; // small delay for output settle
            @(negedge clk);
            valid_in = 1'b0;
            // Sample outputs (they are now stable, registered on that posedge)
            cap_skipped = skipped;
            cap_valid   = valid_out;
            cap_dot     = dot_out;
            cap_sc      = skip_count;
        end
    endtask

    integer random_skipped;
    integer j, k;
    reg [15:0] rnd_a, rnd_b;
    integer seed;

    initial begin
        pass_count    = 0;
        fail_count    = 0;
        random_skipped = 0;
        seed          = 42;

        // ----------------------------------------------------------------
        // Reset
        // ----------------------------------------------------------------
        rst_n    = 1'b0;
        a_trits  = 16'h0000;
        b_trits  = 16'h0000;
        valid_in = 1'b0;
        repeat (4) @(posedge clk);
        #1;
        rst_n = 1'b1;
        @(posedge clk); #1;

        // ----------------------------------------------------------------
        // T1: Both operands non-zero → skipped=0
        // ----------------------------------------------------------------
        apply_and_capture(16'hA5A5, 16'h5A5A);
        if (!cap_skipped && cap_valid) begin
            $display("T1 PASS: both non-zero, skipped=%0b dot_out=0x%02X",
                     cap_skipped, cap_dot);
            pass_count = pass_count + 1;
        end else begin
            $display("T1 FAIL: skipped=%0b valid_out=%0b dot_out=0x%02X",
                     cap_skipped, cap_valid, cap_dot);
            fail_count = fail_count + 1;
        end

        // ----------------------------------------------------------------
        // T2: a_trits = 0 → skipped=1, dot_out=0
        // ----------------------------------------------------------------
        apply_and_capture(16'h0000, 16'h1234);
        if (cap_skipped && (cap_dot == 8'h00) && cap_valid) begin
            $display("T2 PASS: a=0 → skipped=%0b dot_out=0x%02X skip_count=%0d",
                     cap_skipped, cap_dot, cap_sc);
            pass_count = pass_count + 1;
        end else begin
            $display("T2 FAIL: skipped=%0b dot_out=0x%02X valid_out=%0b",
                     cap_skipped, cap_dot, cap_valid);
            fail_count = fail_count + 1;
        end

        // ----------------------------------------------------------------
        // T3: b_trits = 0 → skipped=1
        // ----------------------------------------------------------------
        apply_and_capture(16'hDEAD, 16'h0000);
        if (cap_skipped && (cap_dot == 8'h00) && cap_valid) begin
            $display("T3 PASS: b=0 → skipped=%0b dot_out=0x%02X skip_count=%0d",
                     cap_skipped, cap_dot, cap_sc);
            pass_count = pass_count + 1;
        end else begin
            $display("T3 FAIL: skipped=%0b dot_out=0x%02X valid_out=%0b",
                     cap_skipped, cap_dot, cap_valid);
            fail_count = fail_count + 1;
        end

        // ----------------------------------------------------------------
        // T4: 100 random cycles — exactly 34 of them zero-a (j%3==0)
        //     so j=0,3,6,...,99 → 34 zero-a cycles  (j=0..99, multiples of 3)
        //     Expected skip_count grows from T2/T3 skips + these 34
        // ----------------------------------------------------------------
        random_skipped = 0;
        for (j = 0; j < 100; j = j + 1) begin
            if ((j % 3) == 0) begin
                rnd_a = 16'h0000;  // force zero → skip
            end else begin
                // pseudo-random non-zero
                rnd_a = ($random(seed) & 16'hFFFE) | 16'h0001;
            end
            rnd_b = ($random(seed) & 16'hFFFE) | 16'h0001; // non-zero b

            apply_and_capture(rnd_a, rnd_b);
            if (cap_skipped) random_skipped = random_skipped + 1;
        end
        // j=0..99, multiples of 3: 0,3,6,...,99 → floor(99/3)+1=34 zeros
        if (random_skipped >= 25 && random_skipped <= 45) begin
            $display("T4 PASS: %0d/100 cycles skipped (~33%% expected), skip_count=%0d",
                     random_skipped, cap_sc);
            pass_count = pass_count + 1;
        end else begin
            $display("T4 FAIL: %0d/100 cycles skipped (expected ~33), skip_count=%0d",
                     random_skipped, cap_sc);
            fail_count = fail_count + 1;
        end

        // ----------------------------------------------------------------
        // T5: Saturating counter — soft-reset then 65537 skip cycles
        // ----------------------------------------------------------------
        @(negedge clk);
        rst_n    = 1'b0;
        valid_in = 1'b0;
        repeat (4) @(posedge clk); #1;
        rst_n = 1'b1;
        @(posedge clk); #1;

        for (k = 0; k < 65537; k = k + 1) begin
            @(negedge clk);
            a_trits  = 16'h0000;
            b_trits  = 16'hBEEF;
            valid_in = 1'b1;
            @(posedge clk); #1;
        end
        @(negedge clk);
        valid_in = 1'b0;
        @(posedge clk); #1;

        if (skip_count == 16'hFFFF) begin
            $display("T5 PASS: saturating counter held at 0xFFFF after overflow");
            pass_count = pass_count + 1;
        end else begin
            $display("T5 FAIL: skip_count=0x%04X (expected 0xFFFF)", skip_count);
            fail_count = fail_count + 1;
        end

        // ----------------------------------------------------------------
        // Gate token
        // ----------------------------------------------------------------
        $display("");
        $display("SPARSE_SKIP_MAC_GREEN: %0d/%0d PASS",
                 pass_count, pass_count + fail_count);
        if (fail_count != 0)
            $display("SPARSE_SKIP_MAC GATE FAILED (%0d failures)", fail_count);
        $finish;
    end

    // Timeout watchdog – 20 ms sim time
    initial begin
        #20000000;
        $display("TIMEOUT — SPARSE_SKIP_MAC_GREEN: 0/5 PASS");
        $finish;
    end

endmodule
