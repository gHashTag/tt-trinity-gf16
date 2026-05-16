// SPDX-License-Identifier: Apache-2.0
// sim/tb_l_z02_operand_iso.v — L-Z02 Operand Isolation testbench
//
// Verifies that toggle activity into gf16_dot4 collapses to zero when
// operand_iso_en=0, and that correct results are still produced when enabled.
//
// PASS criteria:
//   1. When enable=0: out === {N{1'b0}} for any in.
//   2. When enable=1: out === in (transparent).
//   3. Toggle count on 'out' is 0 across 100 random vectors with enable=0.
//   4. Toggle count on 'out' is > 0 across same vectors with enable=1.
//
// Pure Verilog-2005. No `*` operator. R-SI-1 clean.

`default_nettype none
`timescale 1ns/1ps

module tb_l_z02_operand_iso;

    // ---- DUT: operand_iso_buf N=16 ----
    reg         enable;
    reg  [15:0] in_bus;
    wire [15:0] out_bus;

    operand_iso_buf #(.N(16)) dut (
        .enable (enable),
        .in     (in_bus),
        .out    (out_bus)
    );

    // Toggle counter on out_bus
    integer toggle_count;
    reg [15:0] out_prev;

    // Pseudo-random vector generation (LFSR-32, Galois, no * used)
    reg [31:0] lfsr;
    task lfsr_step;
        begin
            lfsr = {lfsr[30:0], 1'b0} ^ (lfsr[31] ? 32'hB4BCD35C : 32'h0);
        end
    endtask

    integer i;
    integer pass_count;
    integer fail_count;

    initial begin
        $dumpfile("tb_l_z02_operand_iso.fst");
        $dumpvars(0, tb_l_z02_operand_iso);

        pass_count   = 0;
        fail_count   = 0;
        toggle_count = 0;
        out_prev     = 16'h0;
        lfsr         = 32'hDEAD_BEEF;

        // ---- Test 1: enable=0, output must be all-zero for any input ----
        enable = 1'b0;
        in_bus = 16'hFFFF;
        #1;
        if (out_bus === 16'h0000) begin
            $display("PASS T1a: enable=0, in=0xFFFF -> out=0x0000");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL T1a: enable=0, in=0xFFFF -> out=0x%04h (expected 0x0000)", out_bus);
            fail_count = fail_count + 1;
        end

        in_bus = 16'hA5A5;
        #1;
        if (out_bus === 16'h0000) begin
            $display("PASS T1b: enable=0, in=0xA5A5 -> out=0x0000");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL T1b: enable=0, in=0xA5A5 -> out=0x%04h (expected 0x0000)", out_bus);
            fail_count = fail_count + 1;
        end

        // ---- Test 2: enable=1, output must equal input ----
        enable = 1'b1;
        in_bus = 16'h3E00;  // GF16 1.0
        #1;
        if (out_bus === 16'h3E00) begin
            $display("PASS T2a: enable=1, in=0x3E00 (GF16 1.0) -> out=0x3E00");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL T2a: enable=1, in=0x3E00 -> out=0x%04h", out_bus);
            fail_count = fail_count + 1;
        end

        in_bus = 16'h47C0;  // GF16 30.0 canonical result
        #1;
        if (out_bus === 16'h47C0) begin
            $display("PASS T2b: enable=1, in=0x47C0 (GF16 30.0) -> out=0x47C0");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL T2b: enable=1, in=0x47C0 -> out=0x%04h", out_bus);
            fail_count = fail_count + 1;
        end

        // ---- Test 3: Toggle count with enable=0 must be 0 ----
        enable = 1'b0;
        in_bus = 16'h0000;
        #1;
        // Settle: after enable=0 output is zero regardless of in; capture stable out_prev.
        out_prev = out_bus;
        toggle_count = 0;
        for (i = 0; i < 100; i = i + 1) begin
            lfsr_step;
            in_bus = lfsr[15:0];
            #1;
            // Count bit-level transitions
            if (out_bus !== out_prev)
                toggle_count = toggle_count + 1;
            out_prev = out_bus;
        end
        if (toggle_count === 0) begin
            $display("PASS T3: enable=0 → 0 toggles on out_bus across 100 random vectors");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL T3: enable=0 → %0d toggles (expected 0)", toggle_count);
            fail_count = fail_count + 1;
        end

        // ---- Test 4: Toggle count with enable=1 must be > 0 ----
        enable = 1'b1;
        out_prev = out_bus;
        toggle_count = 0;
        // re-seed same sequence so comparison is fair
        lfsr = 32'hDEAD_BEEF;
        for (i = 0; i < 100; i = i + 1) begin
            lfsr_step;
            in_bus = lfsr[15:0];
            #1;
            if (out_bus !== out_prev)
                toggle_count = toggle_count + 1;
            out_prev = out_bus;
        end
        if (toggle_count > 0) begin
            $display("PASS T4: enable=1 → %0d toggles on out_bus (>0 as expected)", toggle_count);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL T4: enable=1 → 0 toggles (expected > 0, LFSR may be stuck)");
            fail_count = fail_count + 1;
        end

        // ---- Summary ----
        $display("=== L-Z02 Operand Isolation TB: %0d PASS / %0d FAIL ===",
                 pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED — operand isolation verified");
        else
            $display("FAILURES DETECTED — review above");

        $finish;
    end

endmodule
`default_nettype wire
