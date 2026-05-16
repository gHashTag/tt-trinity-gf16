// tb_gf16_dot4_pipelined.v
// Testbench: 1000 random vectors verify that gf16_dot4_pipelined
// produces the same outputs as the unpipelined gf16_dot4 reference
// after accounting for the 1-cycle pipeline latency.
//
// Pass/fail reported as:  PASS: all 1000 vectors matched
//                      or FAIL: <N> mismatches detected
//
// Verilog-2005 only. R-SI-1 compliant (no arithmetic *).
`default_nettype none
`timescale 1ns/1ps

module tb_gf16_dot4_pipelined;

    // ---------------------------------------------------------------
    // Clock generation: 35 MHz → period ≈ 28.57 ns (use 28 ns)
    // ---------------------------------------------------------------
    reg clk;
    initial clk = 0;
    always #14 clk = ~clk;

    // ---------------------------------------------------------------
    // DUT ports
    // ---------------------------------------------------------------
    reg  [15:0] a0, a1, a2, a3;
    reg  [15:0] b0, b1, b2, b3;
    wire [15:0] pipelined_result;

    gf16_dot4_pipelined dut (
        .clk(clk),
        .a0(a0), .a1(a1), .a2(a2), .a3(a3),
        .b0(b0), .b1(b1), .b2(b2), .b3(b3),
        .result(pipelined_result)
    );

    // ---------------------------------------------------------------
    // Reference results: pre-compute and store for 1-cycle delay check
    // We store the reference output of the PREVIOUS clock's inputs.
    // ---------------------------------------------------------------
    wire [15:0] ref_result_comb;

    gf16_dot4 ref_dut (
        .a0(a0), .a1(a1), .a2(a2), .a3(a3),
        .b0(b0), .b1(b1), .b2(b2), .b3(b3),
        .result(ref_result_comb)
    );

    // Pipeline the reference by 1 cycle to match DUT latency
    reg [15:0] ref_result_d1;
    always @(posedge clk)
        ref_result_d1 <= ref_result_comb;

    // ---------------------------------------------------------------
    // PRNG: 32-bit LFSR (taps 32,22,2,1)
    // ---------------------------------------------------------------
    reg [31:0] lfsr;

    task lfsr_next;
        begin
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
        end
    endtask

    // ---------------------------------------------------------------
    // Stimulus + checker
    // ---------------------------------------------------------------
    integer i;
    integer fail_count;

    initial begin
        fail_count = 0;
        lfsr = 32'hDEAD_BEEF;
        a0 = 0; a1 = 0; a2 = 0; a3 = 0;
        b0 = 0; b1 = 0; b2 = 0; b3 = 0;

        // Cycle 0: present first vector
        @(posedge clk); #1;

        // Apply vectors for cycles 1..1000
        // After each posedge, pipelined_result = result from 1 cycle earlier
        // ref_result_d1 = ref result from 1 cycle earlier (same delay)
        for (i = 0; i < 1000; i = i + 1) begin
            // Drive new inputs
            lfsr_next; a0 = lfsr[15:0];
            lfsr_next; a1 = lfsr[15:0];
            lfsr_next; a2 = lfsr[15:0];
            lfsr_next; a3 = lfsr[15:0];
            lfsr_next; b0 = lfsr[15:0];
            lfsr_next; b1 = lfsr[15:0];
            lfsr_next; b2 = lfsr[15:0];
            lfsr_next; b3 = lfsr[15:0];

            @(posedge clk); #1;

            // From cycle 1 onwards both outputs are valid
            if (i >= 1) begin
                if (pipelined_result !== ref_result_d1) begin
                    $display("MISMATCH vector %0d: pipelined=%04h ref=%04h",
                             i - 1, pipelined_result, ref_result_d1);
                    fail_count = fail_count + 1;
                end
            end
        end

        // One final clock to flush the last vector
        @(posedge clk); #1;
        if (pipelined_result !== ref_result_d1) begin
            $display("MISMATCH vector 999: pipelined=%04h ref=%04h",
                     pipelined_result, ref_result_d1);
            fail_count = fail_count + 1;
        end

        if (fail_count == 0)
            $display("PASS: all 1000 vectors matched");
        else
            $display("FAIL: %0d mismatches detected", fail_count);

        $finish;
    end

endmodule
`default_nettype wire
