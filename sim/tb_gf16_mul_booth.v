// ============================================================================
// TESTBENCH: tb_gf16_mul_booth
// DUT: gf16_mul_booth — Booth radix-4 10×10 unsigned multiplier
// Wave-24 RVR-016 dry-run · Charter Rule 2 compliance verification
//
// Test strategy:
//   1. Corner cases (explicit)  :  0×0, 1023×1023, 512×512, phi-derived pair
//   2. 1000 pseudo-random vectors via LFSR (NO `*` in oracle either)
//
// Oracle: pure shift+add (no * operator) — 10-bit unsigned multiply by
//   iterating over bits of b, conditionally adding a shifted version of a.
//
// Anchor: phi^2 + phi^-2 = 3 · Wave-24 RVR-016 dry-run · DOI 10.5281/zenodo.19227877
// ============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_gf16_mul_booth;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    reg  [9:0]  a;
    reg  [9:0]  b;
    wire [19:0] p;

    // -----------------------------------------------------------------------
    // Instantiate DUT
    // -----------------------------------------------------------------------
    gf16_mul_booth dut (
        .a(a),
        .b(b),
        .p(p)
    );

    // -----------------------------------------------------------------------
    // Oracle: shift-and-add 10×10 unsigned multiply (ZERO `*` operators)
    // Returns 20-bit product.
    // -----------------------------------------------------------------------
    function [19:0] oracle_mul;
        input [9:0] oa;
        input [9:0] ob;
        integer     i;
        reg [19:0]  acc;
        reg [19:0]  shifted;
        begin
            acc = 20'd0;
            for (i = 0; i < 10; i = i + 1) begin
                shifted = {10'd0, oa} << i;  // oa * 2^i
                if (ob[i])
                    acc = acc + shifted;
            end
            oracle_mul = acc;
        end
    endfunction

    // -----------------------------------------------------------------------
    // LFSR-32 for pseudo-random test vectors (NO `*` — XOR feedback only)
    // Polynomial: x^32 + x^22 + x^2 + x^1 + 1 (Galois form)
    // -----------------------------------------------------------------------
    reg [31:0] lfsr;

    task lfsr_next;
        begin
            lfsr = {lfsr[30:0], 1'b0} ^
                   ({32{lfsr[31]}} & 32'h80200003);
        end
    endtask

    // -----------------------------------------------------------------------
    // Test infrastructure
    // -----------------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    reg [19:0] expected;
    integer    vec_num;

    // Apply vector and check
    task check;
        input [9:0] ta;
        input [9:0] tb_in;
        input [9:0] vec_id;
        begin
            a = ta;
            b = tb_in;
            #1;  // combinational settle
            expected = oracle_mul(ta, tb_in);
            if (p === expected) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL vec=%0d  a=0x%03X b=0x%03X  expected=0x%05X  got=0x%05X",
                         vec_id, ta, tb_in, expected, p);
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    integer i;

    initial begin
        pass_count = 0;
        fail_count = 0;
        lfsr = 32'hDEAD_BEEF;  // deterministic seed
        a = 10'd0;
        b = 10'd0;
        vec_num = 0;

        $display("=======================================================");
        $display(" tb_gf16_mul_booth  Wave-24 RVR-016 dry-run");
        $display(" phi^2 + phi^-2 = 3  DOI 10.5281/zenodo.19227877");
        $display("=======================================================");

        // -------------------------------------------------------------------
        // CORNER CASES
        // -------------------------------------------------------------------
        $display("--- CORNER CASES ---");

        // CC-1: 0 × 0 = 0
        check(10'd0, 10'd0, vec_num); vec_num = vec_num + 1;

        // CC-2: 1023 × 1023 = 1046529
        check(10'd1023, 10'd1023, vec_num); vec_num = vec_num + 1;

        // CC-3: 512 × 512 = 262144
        check(10'd512, 10'd512, vec_num); vec_num = vec_num + 1;

        // CC-4: phi-derived pair  a=0x3FC (1020), b=0x278 (632)
        //   1020 × 632 = 644640  (phi ≈ 1.618; 0x3FC ≈ 1023*phi^-1, 0x278 ≈ 1023*phi^-2)
        check(10'h3FC, 10'h278, vec_num); vec_num = vec_num + 1;

        // CC-5: 1 × 0 = 0
        check(10'd1, 10'd0, vec_num); vec_num = vec_num + 1;

        // CC-6: 0 × 1023 = 0
        check(10'd0, 10'd1023, vec_num); vec_num = vec_num + 1;

        // CC-7: 1 × 1 = 1
        check(10'd1, 10'd1, vec_num); vec_num = vec_num + 1;

        // CC-8: 1023 × 1 = 1023
        check(10'd1023, 10'd1, vec_num); vec_num = vec_num + 1;

        // CC-9: 1 × 1023 = 1023
        check(10'd1, 10'd1023, vec_num); vec_num = vec_num + 1;

        // CC-10: all-ones mantissa × 1 = all-ones mantissa
        check(10'h3FF, 10'd1, vec_num); vec_num = vec_num + 1;

        // CC-11: LSB-only: 1 × 512
        check(10'd1, 10'd512, vec_num); vec_num = vec_num + 1;

        // CC-12: MSB-only: 512 × 1
        check(10'd512, 10'd1, vec_num); vec_num = vec_num + 1;

        // -------------------------------------------------------------------
        // 1000 PSEUDO-RANDOM VECTORS
        // -------------------------------------------------------------------
        $display("--- 1000 RANDOM VECTORS (LFSR seed=0xDEADBEEF) ---");

        for (i = 0; i < 1000; i = i + 1) begin
            lfsr_next;
            a = lfsr[9:0];
            lfsr_next;
            b = lfsr[9:0];
            #1;
            expected = oracle_mul(a, b);
            if (p === expected) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL rand[%0d]  a=0x%03X b=0x%03X  expected=0x%05X  got=0x%05X",
                         i, a, b, expected, p);
            end
            vec_num = vec_num + 1;
        end

        // -------------------------------------------------------------------
        // SUMMARY
        // -------------------------------------------------------------------
        $display("=======================================================");
        $display(" TOTAL VECTORS : %0d", vec_num);
        $display(" PASS          : %0d", pass_count);
        $display(" FAIL          : %0d", fail_count);
        if (fail_count == 0)
            $display(" RESULT        : *** ALL PASS ***");
        else
            $display(" RESULT        : *** FAIL (see above) ***");
        $display("=======================================================");
        $display(" phi^2 + phi^-2 = 3 · Wave-24 RVR-016 dry-run");
        $display(" DOI 10.5281/zenodo.19227877");
        $display("=======================================================");

        $finish;
    end

endmodule

`default_nettype wire
// ============================================================================
// END tb_gf16_mul_booth
// phi^2 + phi^-2 = 3 · Wave-24 RVR-016 dry-run · DOI 10.5281/zenodo.19227877
// ============================================================================
