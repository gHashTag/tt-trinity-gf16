// sim/tb_gf16_poly_mul.v
// Exhaustive 256/256 testbench for gf16_poly_mul
// GF(2^4), irreducible polynomial x^4+x+1 (0x13)
// Anchor: phi^2+phi^-2=3  DOI 10.5281/zenodo.19227877
// Apache-2.0
// Author: Vasilev Dmitrii <admin@t27.ai>  ORCID 0009-0008-4294-6159
`timescale 1ns/1ps
`default_nettype none

module tb_gf16_poly_mul;

    reg  [3:0] a, b;
    wire [3:0] y;

    gf16_poly_mul dut (
        .a(a),
        .b(b),
        .y(y)
    );

    // Golden table: GF(2^4) multiply mod x^4+x+1
    // Indexed as expected[a*16+b]
    reg [3:0] expected [0:255];

    integer pass_count, fail_count;
    integer i, j;

    initial begin
        // Populate golden table (Python-generated, verified commutative+distributive)
        expected[  0] = 4'h0; // 0*0=0
        expected[  1] = 4'h0; // 0*1=0
        expected[  2] = 4'h0; // 0*2=0
        expected[  3] = 4'h0; // 0*3=0
        expected[  4] = 4'h0; // 0*4=0
        expected[  5] = 4'h0; // 0*5=0
        expected[  6] = 4'h0; // 0*6=0
        expected[  7] = 4'h0; // 0*7=0
        expected[  8] = 4'h0; // 0*8=0
        expected[  9] = 4'h0; // 0*9=0
        expected[ 10] = 4'h0; // 0*10=0
        expected[ 11] = 4'h0; // 0*11=0
        expected[ 12] = 4'h0; // 0*12=0
        expected[ 13] = 4'h0; // 0*13=0
        expected[ 14] = 4'h0; // 0*14=0
        expected[ 15] = 4'h0; // 0*15=0
        expected[ 16] = 4'h0; // 1*0=0
        expected[ 17] = 4'h1; // 1*1=1
        expected[ 18] = 4'h2; // 1*2=2
        expected[ 19] = 4'h3; // 1*3=3
        expected[ 20] = 4'h4; // 1*4=4
        expected[ 21] = 4'h5; // 1*5=5
        expected[ 22] = 4'h6; // 1*6=6
        expected[ 23] = 4'h7; // 1*7=7
        expected[ 24] = 4'h8; // 1*8=8
        expected[ 25] = 4'h9; // 1*9=9
        expected[ 26] = 4'ha; // 1*10=10
        expected[ 27] = 4'hb; // 1*11=11
        expected[ 28] = 4'hc; // 1*12=12
        expected[ 29] = 4'hd; // 1*13=13
        expected[ 30] = 4'he; // 1*14=14
        expected[ 31] = 4'hf; // 1*15=15
        expected[ 32] = 4'h0; // 2*0=0
        expected[ 33] = 4'h2; // 2*1=2
        expected[ 34] = 4'h4; // 2*2=4
        expected[ 35] = 4'h6; // 2*3=6
        expected[ 36] = 4'h8; // 2*4=8
        expected[ 37] = 4'ha; // 2*5=10
        expected[ 38] = 4'hc; // 2*6=12
        expected[ 39] = 4'he; // 2*7=14
        expected[ 40] = 4'h3; // 2*8=3
        expected[ 41] = 4'h1; // 2*9=1
        expected[ 42] = 4'h7; // 2*10=7
        expected[ 43] = 4'h5; // 2*11=5
        expected[ 44] = 4'hb; // 2*12=11
        expected[ 45] = 4'h9; // 2*13=9
        expected[ 46] = 4'hf; // 2*14=15
        expected[ 47] = 4'hd; // 2*15=13
        expected[ 48] = 4'h0; // 3*0=0
        expected[ 49] = 4'h3; // 3*1=3
        expected[ 50] = 4'h6; // 3*2=6
        expected[ 51] = 4'h5; // 3*3=5
        expected[ 52] = 4'hc; // 3*4=12
        expected[ 53] = 4'hf; // 3*5=15
        expected[ 54] = 4'ha; // 3*6=10
        expected[ 55] = 4'h9; // 3*7=9
        expected[ 56] = 4'hb; // 3*8=11
        expected[ 57] = 4'h8; // 3*9=8
        expected[ 58] = 4'hd; // 3*10=13
        expected[ 59] = 4'he; // 3*11=14
        expected[ 60] = 4'h7; // 3*12=7
        expected[ 61] = 4'h4; // 3*13=4
        expected[ 62] = 4'h1; // 3*14=1
        expected[ 63] = 4'h2; // 3*15=2
        expected[ 64] = 4'h0; // 4*0=0
        expected[ 65] = 4'h4; // 4*1=4
        expected[ 66] = 4'h8; // 4*2=8
        expected[ 67] = 4'hc; // 4*3=12
        expected[ 68] = 4'h3; // 4*4=3
        expected[ 69] = 4'h7; // 4*5=7
        expected[ 70] = 4'hb; // 4*6=11
        expected[ 71] = 4'hf; // 4*7=15
        expected[ 72] = 4'h6; // 4*8=6
        expected[ 73] = 4'h2; // 4*9=2
        expected[ 74] = 4'he; // 4*10=14
        expected[ 75] = 4'ha; // 4*11=10
        expected[ 76] = 4'h5; // 4*12=5
        expected[ 77] = 4'h1; // 4*13=1
        expected[ 78] = 4'hd; // 4*14=13
        expected[ 79] = 4'h9; // 4*15=9
        expected[ 80] = 4'h0; // 5*0=0
        expected[ 81] = 4'h5; // 5*1=5
        expected[ 82] = 4'ha; // 5*2=10
        expected[ 83] = 4'hf; // 5*3=15
        expected[ 84] = 4'h7; // 5*4=7
        expected[ 85] = 4'h2; // 5*5=2
        expected[ 86] = 4'hd; // 5*6=13
        expected[ 87] = 4'h8; // 5*7=8
        expected[ 88] = 4'he; // 5*8=14
        expected[ 89] = 4'hb; // 5*9=11
        expected[ 90] = 4'h4; // 5*10=4
        expected[ 91] = 4'h1; // 5*11=1
        expected[ 92] = 4'h9; // 5*12=9
        expected[ 93] = 4'hc; // 5*13=12
        expected[ 94] = 4'h3; // 5*14=3
        expected[ 95] = 4'h6; // 5*15=6
        expected[ 96] = 4'h0; // 6*0=0
        expected[ 97] = 4'h6; // 6*1=6
        expected[ 98] = 4'hc; // 6*2=12
        expected[ 99] = 4'ha; // 6*3=10
        expected[100] = 4'hb; // 6*4=11
        expected[101] = 4'hd; // 6*5=13
        expected[102] = 4'h7; // 6*6=7
        expected[103] = 4'h1; // 6*7=1
        expected[104] = 4'h5; // 6*8=5
        expected[105] = 4'h3; // 6*9=3
        expected[106] = 4'h9; // 6*10=9
        expected[107] = 4'hf; // 6*11=15
        expected[108] = 4'he; // 6*12=14
        expected[109] = 4'h8; // 6*13=8
        expected[110] = 4'h2; // 6*14=2
        expected[111] = 4'h4; // 6*15=4
        expected[112] = 4'h0; // 7*0=0
        expected[113] = 4'h7; // 7*1=7
        expected[114] = 4'he; // 7*2=14
        expected[115] = 4'h9; // 7*3=9
        expected[116] = 4'hf; // 7*4=15
        expected[117] = 4'h8; // 7*5=8
        expected[118] = 4'h1; // 7*6=1
        expected[119] = 4'h6; // 7*7=6
        expected[120] = 4'hd; // 7*8=13
        expected[121] = 4'ha; // 7*9=10
        expected[122] = 4'h3; // 7*10=3
        expected[123] = 4'h4; // 7*11=4
        expected[124] = 4'h2; // 7*12=2
        expected[125] = 4'h5; // 7*13=5
        expected[126] = 4'hc; // 7*14=12
        expected[127] = 4'hb; // 7*15=11
        expected[128] = 4'h0; // 8*0=0
        expected[129] = 4'h8; // 8*1=8
        expected[130] = 4'h3; // 8*2=3
        expected[131] = 4'hb; // 8*3=11
        expected[132] = 4'h6; // 8*4=6
        expected[133] = 4'he; // 8*5=14
        expected[134] = 4'h5; // 8*6=5
        expected[135] = 4'hd; // 8*7=13
        expected[136] = 4'hc; // 8*8=12
        expected[137] = 4'h4; // 8*9=4
        expected[138] = 4'hf; // 8*10=15
        expected[139] = 4'h7; // 8*11=7
        expected[140] = 4'ha; // 8*12=10
        expected[141] = 4'h2; // 8*13=2
        expected[142] = 4'h9; // 8*14=9
        expected[143] = 4'h1; // 8*15=1
        expected[144] = 4'h0; // 9*0=0
        expected[145] = 4'h9; // 9*1=9
        expected[146] = 4'h1; // 9*2=1
        expected[147] = 4'h8; // 9*3=8
        expected[148] = 4'h2; // 9*4=2
        expected[149] = 4'hb; // 9*5=11
        expected[150] = 4'h3; // 9*6=3
        expected[151] = 4'ha; // 9*7=10
        expected[152] = 4'h4; // 9*8=4
        expected[153] = 4'hd; // 9*9=13
        expected[154] = 4'h5; // 9*10=5
        expected[155] = 4'hc; // 9*11=12
        expected[156] = 4'h6; // 9*12=6
        expected[157] = 4'hf; // 9*13=15
        expected[158] = 4'h7; // 9*14=7
        expected[159] = 4'he; // 9*15=14
        expected[160] = 4'h0; // 10*0=0
        expected[161] = 4'ha; // 10*1=10
        expected[162] = 4'h7; // 10*2=7
        expected[163] = 4'hd; // 10*3=13
        expected[164] = 4'he; // 10*4=14
        expected[165] = 4'h4; // 10*5=4
        expected[166] = 4'h9; // 10*6=9
        expected[167] = 4'h3; // 10*7=3
        expected[168] = 4'hf; // 10*8=15
        expected[169] = 4'h5; // 10*9=5
        expected[170] = 4'h8; // 10*10=8
        expected[171] = 4'h2; // 10*11=2
        expected[172] = 4'h1; // 10*12=1
        expected[173] = 4'hb; // 10*13=11
        expected[174] = 4'h6; // 10*14=6
        expected[175] = 4'hc; // 10*15=12
        expected[176] = 4'h0; // 11*0=0
        expected[177] = 4'hb; // 11*1=11
        expected[178] = 4'h5; // 11*2=5
        expected[179] = 4'he; // 11*3=14
        expected[180] = 4'ha; // 11*4=10
        expected[181] = 4'h1; // 11*5=1
        expected[182] = 4'hf; // 11*6=15
        expected[183] = 4'h4; // 11*7=4
        expected[184] = 4'h7; // 11*8=7
        expected[185] = 4'hc; // 11*9=12
        expected[186] = 4'h2; // 11*10=2
        expected[187] = 4'h9; // 11*11=9
        expected[188] = 4'hd; // 11*12=13
        expected[189] = 4'h6; // 11*13=6
        expected[190] = 4'h8; // 11*14=8
        expected[191] = 4'h3; // 11*15=3
        expected[192] = 4'h0; // 12*0=0
        expected[193] = 4'hc; // 12*1=12
        expected[194] = 4'hb; // 12*2=11
        expected[195] = 4'h7; // 12*3=7
        expected[196] = 4'h5; // 12*4=5
        expected[197] = 4'h9; // 12*5=9
        expected[198] = 4'he; // 12*6=14
        expected[199] = 4'h2; // 12*7=2
        expected[200] = 4'ha; // 12*8=10
        expected[201] = 4'h6; // 12*9=6
        expected[202] = 4'h1; // 12*10=1
        expected[203] = 4'hd; // 12*11=13
        expected[204] = 4'hf; // 12*12=15
        expected[205] = 4'h3; // 12*13=3
        expected[206] = 4'h4; // 12*14=4
        expected[207] = 4'h8; // 12*15=8
        expected[208] = 4'h0; // 13*0=0
        expected[209] = 4'hd; // 13*1=13
        expected[210] = 4'h9; // 13*2=9
        expected[211] = 4'h4; // 13*3=4
        expected[212] = 4'h1; // 13*4=1
        expected[213] = 4'hc; // 13*5=12
        expected[214] = 4'h8; // 13*6=8
        expected[215] = 4'h5; // 13*7=5
        expected[216] = 4'h2; // 13*8=2
        expected[217] = 4'hf; // 13*9=15
        expected[218] = 4'hb; // 13*10=11
        expected[219] = 4'h6; // 13*11=6
        expected[220] = 4'h3; // 13*12=3
        expected[221] = 4'he; // 13*13=14
        expected[222] = 4'ha; // 13*14=10
        expected[223] = 4'h7; // 13*15=7
        expected[224] = 4'h0; // 14*0=0
        expected[225] = 4'he; // 14*1=14
        expected[226] = 4'hf; // 14*2=15
        expected[227] = 4'h1; // 14*3=1
        expected[228] = 4'hd; // 14*4=13
        expected[229] = 4'h3; // 14*5=3
        expected[230] = 4'h2; // 14*6=2
        expected[231] = 4'hc; // 14*7=12
        expected[232] = 4'h9; // 14*8=9
        expected[233] = 4'h7; // 14*9=7
        expected[234] = 4'h6; // 14*10=6
        expected[235] = 4'h8; // 14*11=8
        expected[236] = 4'h4; // 14*12=4
        expected[237] = 4'ha; // 14*13=10
        expected[238] = 4'hb; // 14*14=11
        expected[239] = 4'h5; // 14*15=5
        expected[240] = 4'h0; // 15*0=0
        expected[241] = 4'hf; // 15*1=15
        expected[242] = 4'hd; // 15*2=13
        expected[243] = 4'h2; // 15*3=2
        expected[244] = 4'h9; // 15*4=9
        expected[245] = 4'h6; // 15*5=6
        expected[246] = 4'h4; // 15*6=4
        expected[247] = 4'hb; // 15*7=11
        expected[248] = 4'h1; // 15*8=1
        expected[249] = 4'he; // 15*9=14
        expected[250] = 4'hc; // 15*10=12
        expected[251] = 4'h3; // 15*11=3
        expected[252] = 4'h8; // 15*12=8
        expected[253] = 4'h7; // 15*13=7
        expected[254] = 4'h5; // 15*14=5
        expected[255] = 4'ha; // 15*15=10

        pass_count = 0;
        fail_count = 0;

        // Exhaustive sweep: all 256 (a,b) pairs
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                a = i[3:0];
                b = j[3:0];
                #1; // propagation delay
                if (y === expected[i*16+j]) begin
                    pass_count = pass_count + 1;
                end else begin
                    $display("FAIL: a=4'h%h b=4'h%h got=4'h%h expected=4'h%h",
                             a, b, y, expected[i*16+j]);
                    fail_count = fail_count + 1;
                end
            end
        end

        $display("tb_gf16_poly_mul: %0d/256 PASS, %0d FAIL", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL PASS (256/256) — GF(2^4) poly mul exhaustive VERIFIED");
        else
            $display("FAILURES DETECTED — check implementation");

        $finish;
    end

endmodule
