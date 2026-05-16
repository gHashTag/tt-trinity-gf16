`default_nettype none
// tb_wallace_popcount_16.v — exhaustive testbench for wallace_popcount_16
// Tests all 65536 input patterns and verifies popcount correctness.
// Pure Verilog-2005, no * operator.
//
// ANCHOR: φ²+φ⁻²=3 · DOI 10.5281/zenodo.19227877 · Apache-2.0

module tb_wallace_popcount_16;

    // Inputs / outputs
    reg  [15:0] in;
    wire [4:0]  out;

    // Instantiate DUT
    wallace_popcount_16 dut (
        .in  (in),
        .out (out)
    );

    // Reference popcount: count set bits using shift-and-add (no *)
    function [4:0] ref_popcount;
        input [15:0] v;
        reg [4:0] cnt;
        reg [15:0] tmp;
        integer j;
        begin
            cnt = 5'b0;
            tmp = v;
            for (j = 0; j < 16; j = j + 1) begin
                cnt = cnt + {4'b0, tmp[0]};
                tmp = tmp >> 1;
            end
            ref_popcount = cnt;
        end
    endfunction

    integer i;
    integer errors;
    reg [4:0] expected;

    initial begin
        $display("Starting exhaustive Wallace popcount test (65536 patterns)...");
        errors = 0;

        for (i = 0; i < 65536; i = i + 1) begin
            in = i[15:0];
            #1; // small propagation delay

            expected = ref_popcount(in);
            if (out !== expected) begin
                $display("FAIL: in=0x%04x  expected=%0d  got=%0d", in, expected, out);
                errors = errors + 1;
            end
        end

        if (errors == 0) begin
            $display("PASS: all 65536 patterns correct.");
        end else begin
            $display("FAIL: %0d errors detected.", errors);
            $finish;
        end
        $finish;
    end

endmodule
