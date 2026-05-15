// tb_tri_w158_unpack.v — Exhaustive 81-case test for tri_w158_unpack
// Every (w0,w1,w2,w3) ∈ {-1,0,+1}^4 packs and unpacks to identity.
// Author: Vasilev Dmitrii <admin@t27.ai> ORCID 0009-0008-4294-6159

`timescale 1ns/1ps

module tb_tri_w158_unpack;

    // DUT connections
    reg  [6:0] code_in;
    wire [1:0] w0, w1, w2, w3;
    wire       valid;

    tri_w158_unpack dut (
        .code_in (code_in),
        .w0     (w0),
        .w1     (w1),
        .w2     (w2),
        .w3     (w3),
        .valid  (valid)
    );

    // -----------------------------------------------------------------------
    // Encoding helper function (pure Verilog, mirrors RTL convention)
    // symbol = weight + 1  (so -1→0, 0→1, +1→2)
    // code   = s0*27 + s1*9 + s2*3 + s3
    // -----------------------------------------------------------------------
    function [6:0] pack4;
        input signed [1:0] a0, a1, a2, a3;
        reg [2:0] s0, s1, s2, s3;
        begin
            // Convert 2-bit signed: 2'b11=-1→0, 2'b00=0→1, 2'b01=+1→2
            case (a0) 2'b11: s0=0; 2'b00: s0=1; 2'b01: s0=2; default: s0=0; endcase
            case (a1) 2'b11: s1=0; 2'b00: s1=1; 2'b01: s1=2; default: s1=0; endcase
            case (a2) 2'b11: s2=0; 2'b00: s2=1; 2'b01: s2=2; default: s2=0; endcase
            case (a3) 2'b11: s3=0; 2'b00: s3=1; 2'b01: s3=2; default: s3=0; endcase
            // s0*27 = s0*(16+8+2+1)
            pack4 = s0*27 + s1*9 + s2*3 + s3;
        end
    endfunction

    // Test counters
    integer pass_count;
    integer fail_count;
    integer test_num;

    // Enumerate all 81 valid combinations
    integer i0, i1, i2, i3;
    reg signed [1:0] tw0, tw1, tw2, tw3;
    reg [6:0]  code;
    reg signed [1:0] sym_arr [0:2];

    initial begin
        pass_count = 0;
        fail_count = 0;
        test_num   = 0;

        sym_arr[0] = 2'sb11;  // -1
        sym_arr[1] = 2'sb00;  //  0
        sym_arr[2] = 2'sb01;  // +1

        $display("=== tb_tri_w158_unpack: Exhaustive 81-case roundtrip test ===");

        for (i0 = 0; i0 < 3; i0 = i0 + 1) begin
          for (i1 = 0; i1 < 3; i1 = i1 + 1) begin
            for (i2 = 0; i2 < 3; i2 = i2 + 1) begin
              for (i3 = 0; i3 < 3; i3 = i3 + 1) begin

                tw0 = sym_arr[i0];
                tw1 = sym_arr[i1];
                tw2 = sym_arr[i2];
                tw3 = sym_arr[i3];

                code = pack4(tw0, tw1, tw2, tw3);

                // Drive DUT
                code_in = code;
                #10;  // combinational settle

                test_num = test_num + 1;

                // Check valid flag
                if (!valid) begin
                    $display("FAIL[%0d]: code=%0d valid=0 for (%0d,%0d,%0d,%0d)",
                             test_num, code,
                             $signed(tw0), $signed(tw1), $signed(tw2), $signed(tw3));
                    fail_count = fail_count + 1;
                end else if (w0 === tw0 && w1 === tw1 && w2 === tw2 && w3 === tw3) begin
                    pass_count = pass_count + 1;
                    $display("PASS[%0d]: code=%2d (%sd,%sd,%sd,%sd)",
                             test_num, code,
                             (tw0==2'b11)?"-1":((tw0==2'b00)?"0":"+1"),
                             (tw1==2'b11)?"-1":((tw1==2'b00)?"0":"+1"),
                             (tw2==2'b11)?"-1":((tw2==2'b00)?"0":"+1"),
                             (tw3==2'b11)?"-1":((tw3==2'b00)?"0":"+1"));
                end else begin
                    fail_count = fail_count + 1;
                    $display("FAIL[%0d]: code=%0d expected (%0d,%0d,%0d,%0d) got (%0d,%0d,%0d,%0d)",
                             test_num, code,
                             $signed(tw0), $signed(tw1), $signed(tw2), $signed(tw3),
                             $signed(w0),  $signed(w1),  $signed(w2),  $signed(w3));
                end

              end
            end
          end
        end

        // ---------------------------------------------------------------
        // Also verify codes 81..127 are flagged invalid
        // ---------------------------------------------------------------
        $display("\n=== Checking invalid codes 81..127 ===");
        begin : inv_check
            integer k;
            for (k = 81; k < 128; k = k + 1) begin
                code_in = k[6:0];
                #10;
                if (valid) begin
                    $display("FAIL: code=%0d should be invalid but valid=1", k);
                    fail_count = fail_count + 1;
                end else begin
                    pass_count = pass_count + 1;
                end
            end
        end

        // ---------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------
        $display("\n============================================================");
        $display("tb_tri_w158_unpack RESULT: %0d PASS / %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("STATUS: ALL 81 ROUNDTRIP TESTS PASSED — 0 errors");
        else
            $display("STATUS: %0d FAILURES", fail_count);
        $display("============================================================\n");

        $finish;
    end

    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
