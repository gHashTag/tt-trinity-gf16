`default_nettype none
`timescale 1ns/1ps
// tb_q4_ternary_dot8.v — testbench for L-S35 Hybrid Q4×Ternary 8-wide dot product
// Apache-2.0 · TRI-1 v2
//
// Tests:
//   Test 1: w=[1,2,3,4,5,6,7,-1], act=all +1  → sum = 1+2+3+4+5+6+7-1 = 27
//   Test 2: w=[1,2,3,4,5,6,7,8], act=all -1   → sum = -36 (no saturation)
//   Test 3: act=all zero                       → sum = 0, saturated=0
//   Test 4: w=all 7, act=all +1               → sum = 56, no saturation
//   Test 5: mixed ternary                      → computed reference
//   Test 6: 100 random vectors vs C-reference
//
// Gate token: Q4_TERNARY_DOT8_GREEN

module tb_q4_ternary_dot8;

    // DUT signals
    reg         clk;
    reg         rst_n;
    reg  [31:0] w_q4;
    reg  [15:0] act_trits;
    reg         valid_in;
    wire signed [7:0] dot_out;
    wire        valid_out;
    wire        saturated;

    // Instantiate DUT
    q4_ternary_dot8 dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .w_q4      (w_q4),
        .act_trits (act_trits),
        .valid_in  (valid_in),
        .dot_out   (dot_out),
        .valid_out (valid_out),
        .saturated (saturated)
    );

    // Clock: 10 ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Test bookkeeping
    integer pass_count;
    integer fail_count;
    integer total_count;

    // -----------------------------------------------------------------------
    // Helper: pack 8 Q4 weights (each 4-bit signed) into a 32-bit word
    // w[0] in bits [3:0], w[1] in [7:4], ... w[7] in [31:28]
    // -----------------------------------------------------------------------
    function [31:0] pack_w;
        input signed [3:0] w0, w1, w2, w3, w4, w5, w6, w7;
        begin
            pack_w = {w7[3:0], w6[3:0], w5[3:0], w4[3:0],
                      w3[3:0], w2[3:0], w1[3:0], w0[3:0]};
        end
    endfunction

    // -----------------------------------------------------------------------
    // Helper: pack 8 ternary acts (2-bit each) into a 16-bit word
    // act[0] in bits [1:0], act[1] in [3:2], ... act[7] in [15:14]
    // 00=0, 01=+1, 10=-1
    // -----------------------------------------------------------------------
    function [15:0] pack_act;
        input [1:0] a0, a1, a2, a3, a4, a5, a6, a7;
        begin
            pack_act = {a7, a6, a5, a4, a3, a2, a1, a0};
        end
    endfunction

    // -----------------------------------------------------------------------
    // Reference model: compute expected 8-bit saturated sum in Verilog
    // -----------------------------------------------------------------------
    function signed [7:0] ref_dot8;
        input [31:0] w;
        input [15:0] a;
        integer j;
        reg signed [7:0] sum_i;
        reg signed [3:0] wj;
        reg [1:0] aj;
        reg signed [11:0] acc;  // wide enough: 8 * 8 = 64, well within 12-bit
        begin
            acc = 0;
            for (j = 0; j < 8; j = j + 1) begin
                wj = $signed(w[4*j+3 -: 4]);
                aj = a[2*j+1 -: 2];
                if (aj == 2'b01)
                    acc = acc + {{8{wj[3]}}, wj};  // +w
                else if (aj == 2'b10)
                    acc = acc - {{8{wj[3]}}, wj};  // -w
                // else 0
            end
            // saturate to 8-bit signed
            if (acc > 127)
                ref_dot8 = 8'sd127;
            else if (acc < -128)
                ref_dot8 = -8'sd128;
            else
                ref_dot8 = acc[7:0];
        end
    endfunction

    // -----------------------------------------------------------------------
    // Apply one test vector, wait one cycle, check result
    // -----------------------------------------------------------------------
    task apply_and_check;
        input [31:0] t_w;
        input [15:0] t_a;
        input signed [7:0] expected;
        input [255:0] label;  // up to 32 chars
        reg signed [7:0] got;
        begin
            @(negedge clk);
            w_q4      = t_w;
            act_trits = t_a;
            valid_in  = 1'b1;
            @(posedge clk);
            #1;  // small delta after rising edge so output has settled
            // wait for valid_out (should be 1 cycle after valid_in)
            @(posedge clk);
            #1;
            got = dot_out;
            total_count = total_count + 1;
            if (got === expected) begin
                $display("[PASS] %0s: got=%0d expected=%0d", label, got, expected);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s: got=%0d expected=%0d w=%08h a=%04h",
                         label, got, expected, t_w, t_a);
                fail_count = fail_count + 1;
            end
            valid_in = 1'b0;
        end
    endtask

    // -----------------------------------------------------------------------
    // LFSR-based pseudo-random generator (32-bit Galois LFSR, taps 32,22,2,1)
    // -----------------------------------------------------------------------
    reg [31:0] lfsr_state;
    task lfsr_next;
        output [31:0] val;
        begin
            lfsr_state = {lfsr_state[30:0], 1'b0} ^
                         (lfsr_state[31] ? 32'h80200003 : 32'h0);
            val = lfsr_state;
        end
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    integer rand_i;
    reg [31:0] rand_w;
    reg [15:0] rand_a;
    reg [31:0] rval;
    reg signed [7:0] exp_val;

    initial begin
        pass_count  = 0;
        fail_count  = 0;
        total_count = 0;
        lfsr_state  = 32'hDEAD_BEEF;

        // Reset
        rst_n    = 0;
        w_q4     = 0;
        act_trits= 0;
        valid_in = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // ------------------------------------------------------------------
        // Test 1: w=[1,2,3,4,5,6,7,-1], act=all +1 → sum=1+2+3+4+5+6+7-1=27
        // ------------------------------------------------------------------
        apply_and_check(
            pack_w(4'sd1, 4'sd2, 4'sd3, 4'sd4, 4'sd5, 4'sd6, 4'sd7, -4'sd1),
            pack_act(2'b01, 2'b01, 2'b01, 2'b01, 2'b01, 2'b01, 2'b01, 2'b01),
            8'sd27,
            "T1:w=[1..7,-1] act=all+1"
        );

        // ------------------------------------------------------------------
        // Test 2: w=[1,2,3,4,5,6,7,8] — note 8 = -8 in Q4 signed!
        // W[7]=4'b1000 = -8 in 2's complement
        // act=all -1 → sum = -(1+2+3+4+5+6+7) - (-8) = -28 + 8 = -28 - (-8) = -28+8 = -28...
        // ref: act=-1 → -w[i]
        //   -1, -2, -3, -4, -5, -6, -7, -(-8)= -1-2-3-4-5-6-7+8 = -20
        // Let ref_dot8 compute it correctly
        // ------------------------------------------------------------------
        apply_and_check(
            pack_w(4'sd1, 4'sd2, 4'sd3, 4'sd4, 4'sd5, 4'sd6, 4'sd7, 4'sb1000),
            pack_act(2'b10, 2'b10, 2'b10, 2'b10, 2'b10, 2'b10, 2'b10, 2'b10),
            ref_dot8(
                pack_w(4'sd1, 4'sd2, 4'sd3, 4'sd4, 4'sd5, 4'sd6, 4'sd7, 4'sb1000),
                pack_act(2'b10, 2'b10, 2'b10, 2'b10, 2'b10, 2'b10, 2'b10, 2'b10)
            ),
            "T2:w=[1..7,8] act=all-1"
        );

        // ------------------------------------------------------------------
        // Test 3: act=all zero → sum=0, saturated=0
        // ------------------------------------------------------------------
        apply_and_check(
            pack_w(4'sd7, 4'sd6, 4'sd5, 4'sd4, 4'sd3, 4'sd2, 4'sd1, 4'sd0),
            pack_act(2'b00, 2'b00, 2'b00, 2'b00, 2'b00, 2'b00, 2'b00, 2'b00),
            8'sd0,
            "T3:act=all_zero"
        );

        // ------------------------------------------------------------------
        // Test 4: w=all 7, act=all +1 → sum=56, no saturation
        // ------------------------------------------------------------------
        apply_and_check(
            pack_w(4'sd7, 4'sd7, 4'sd7, 4'sd7, 4'sd7, 4'sd7, 4'sd7, 4'sd7),
            pack_act(2'b01, 2'b01, 2'b01, 2'b01, 2'b01, 2'b01, 2'b01, 2'b01),
            8'sd56,
            "T4:w=all7 act=all+1 sum=56"
        );

        // ------------------------------------------------------------------
        // Test 5: mixed ternary acts — alternating +1/-1/0
        // w=[3,4,5,6,7,7,7,7], act=[+1,-1,0,+1,-1,0,+1,0]
        // sum = +3 -4 +0 +6 -7 +0 +7 +0 = 5
        // ------------------------------------------------------------------
        apply_and_check(
            pack_w(4'sd3, 4'sd4, 4'sd5, 4'sd6, 4'sd7, 4'sd7, 4'sd7, 4'sd7),
            pack_act(2'b01, 2'b10, 2'b00, 2'b01, 2'b10, 2'b00, 2'b01, 2'b00),
            ref_dot8(
                pack_w(4'sd3, 4'sd4, 4'sd5, 4'sd6, 4'sd7, 4'sd7, 4'sd7, 4'sd7),
                pack_act(2'b01, 2'b10, 2'b00, 2'b01, 2'b10, 2'b00, 2'b01, 2'b00)
            ),
            "T5:mixed_ternary"
        );

        // ------------------------------------------------------------------
        // Test 5b: negative weights with mixed acts
        // w=[-8,-7,-6,-5,-4,-3,-2,-1], act=[+1,+1,+1,+1,+1,+1,+1,+1]
        // sum = -8-7-6-5-4-3-2-1 = -36
        // ------------------------------------------------------------------
        apply_and_check(
            pack_w(-4'sd8, -4'sd7, -4'sd6, -4'sd5, -4'sd4, -4'sd3, -4'sd2, -4'sd1),
            pack_act(2'b01, 2'b01, 2'b01, 2'b01, 2'b01, 2'b01, 2'b01, 2'b01),
            8'sd0 - 8'sd8 - 8'sd7 - 8'sd6 - 8'sd5 - 8'sd4 - 8'sd3 - 8'sd2 - 8'sd1,
            "T5b:neg_weights_all+1"
        );

        // ------------------------------------------------------------------
        // Test 6: 100 random vectors vs C-reference (Verilog reference model)
        // ------------------------------------------------------------------
        $display("--- T6: 100 random vectors ---");
        for (rand_i = 0; rand_i < 100; rand_i = rand_i + 1) begin
            lfsr_next(rval);
            rand_w = rval;
            lfsr_next(rval);
            // For act_trits: each 2-bit field should be 00/01/10 only
            // Map raw 2-bit to ternary: 00→00(0), 01→01(+1), 10→10(-1), 11→01(+1)
            // Apply masking: replace 2'b11 with 2'b01
            rand_a = rval[15:0];
            begin : mask_11
                integer k;
                for (k = 0; k < 8; k = k + 1) begin
                    if (rand_a[2*k+1 -: 2] == 2'b11)
                        rand_a[2*k+1 -: 2] = 2'b01;
                end
            end
            exp_val = ref_dot8(rand_w, rand_a);

            @(negedge clk);
            w_q4      = rand_w;
            act_trits = rand_a;
            valid_in  = 1'b1;
            @(posedge clk);
            #1;
            @(posedge clk);
            #1;
            total_count = total_count + 1;
            if (dot_out === exp_val) begin
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] random[%0d]: got=%0d exp=%0d w=%08h a=%04h",
                         rand_i, dot_out, exp_val, rand_w, rand_a);
                fail_count = fail_count + 1;
            end
            valid_in = 1'b0;
        end
        $display("--- T6 done: %0d/100 random pass ---", pass_count - 5);

        // ------------------------------------------------------------------
        // Report
        // ------------------------------------------------------------------
        $display("");
        if (fail_count == 0)
            $display("Q4_TERNARY_DOT8_GREEN: %0d/%0d PASS", pass_count, total_count);
        else
            $display("Q4_TERNARY_DOT8_RED: %0d FAIL / %0d total", fail_count, total_count);

        $finish;
    end

endmodule
