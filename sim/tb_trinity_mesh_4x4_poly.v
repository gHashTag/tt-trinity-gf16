// sim/tb_trinity_mesh_4x4_poly.v
// Testbench for trinity_mesh_4x4_poly — ports TG-Max-05 (dot4 sweep)
// and TG-Max-06 (RECEIPT) to the GF(2^4) polynomial mesh.
//
// NOTE: Expected dot4 results are GF(2^4) values, NOT fp16.
// Golden vectors computed from Python model (gf16_mul mod x^4+x+1).
//
// Anchor: phi^2+phi^-2=3  DOI 10.5281/zenodo.19227877
// Apache-2.0
// Author: Vasilev Dmitrii <admin@t27.ai>  ORCID 0009-0008-4294-6159
`timescale 1ns/1ps
`default_nettype none
`include "trinity_packet.vh"

module tb_trinity_mesh_4x4_poly;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    reg  clk, rst_n;
    reg  [`TRN_PKT_W-1:0] host_in_pkt;
    reg                   host_in_valid;
    wire                  host_in_ready;
    wire [`TRN_PKT_W-1:0] host_out_pkt;
    wire                  host_out_valid;
    reg                   host_out_ready;
    wire [15:0]           dbg_tile0_result;

    trinity_mesh_4x4_poly dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .host_in_pkt    (host_in_pkt),
        .host_in_valid  (host_in_valid),
        .host_in_ready  (host_in_ready),
        .host_out_pkt   (host_out_pkt),
        .host_out_valid (host_out_valid),
        .host_out_ready (host_out_ready),
        .dbg_tile0_result(dbg_tile0_result)
    );

    // ----------------------------------------------------------------
    // Clock — 10 ns period
    // ----------------------------------------------------------------
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Task: send one packet to the mesh
    // ----------------------------------------------------------------
    task send_pkt;
        input [`TRN_PKT_W-1:0] pkt;
        begin
            @(posedge clk);
            host_in_pkt   = pkt;
            host_in_valid = 1'b1;
            // Wait for ready
            while (!host_in_ready) @(posedge clk);
            @(posedge clk);
            host_in_valid = 1'b0;
            host_in_pkt   = {`TRN_PKT_W{1'b0}};
        end
    endtask

    // ----------------------------------------------------------------
    // Task: receive one packet with timeout
    // ----------------------------------------------------------------
    reg [`TRN_PKT_W-1:0] rcvd_pkt;
    task recv_pkt;
        input integer timeout;
        integer t;
        begin
            host_out_ready = 1'b1;
            t = 0;
            while (!host_out_valid && t < timeout) begin
                @(posedge clk);
                t = t + 1;
            end
            if (!host_out_valid) begin
                $display("TIMEOUT waiting for packet");
                rcvd_pkt = {`TRN_PKT_W{1'bx}};
            end else begin
                rcvd_pkt = host_out_pkt;
                @(posedge clk);
            end
            host_out_ready = 1'b0;
        end
    endtask

    // ----------------------------------------------------------------
    // Golden vectors for 256-entry dot4 sweep
    // golden[i] = dot4 result for test index i, using:
    //   a0=(i>>0)&0xF, a1=(i>>1)&0xF, a2=(i>>2)&0xF, a3=(i>>3)&0xF
    //   b0=(~i>>0)&0xF, b1=(~i>>1)&0xF, b2=(~i>>2)&0xF, b3=(~i>>3)&0xF
    // Python-generated, mod x^4+x+1 (0x13)
    // ----------------------------------------------------------------
    reg [3:0] golden [0:255];

    // ----------------------------------------------------------------
    // Counters
    // ----------------------------------------------------------------
    integer pass_count, fail_count;
    integer gi;

    // ----------------------------------------------------------------
    // Tile-0 addressing shortcuts
    // ----------------------------------------------------------------
    localparam [1:0] TILE0 = 2'd0;
    localparam [1:0] HOST  = 2'd3;  // host src id

    // ----------------------------------------------------------------
    // Test sequences
    // ----------------------------------------------------------------
    integer idx;
    reg [3:0] a0_v, a1_v, a2_v, a3_v;
    reg [3:0] b0_v, b1_v, b2_v, b3_v;
    reg [3:0] expected_dot4;
    reg [`TRN_PKT_W-1:0] result_pkt, receipt_pkt;
    reg [3:0] got_result;

    // RECEIPT verify
    reg [7:0]  exp_checksum;
    reg [7:0]  exp_job_id;
    reg [7:0]  got_checksum;
    reg [7:0]  got_job_id;
    reg [3:0]  got_tile_id;

    initial begin
        // ---- populate golden table ----
        golden[  0] = 4'h0;
        golden[  1] = 4'he;
        golden[  2] = 4'h7;
        golden[  3] = 4'h9;
        golden[  4] = 4'hd;
        golden[  5] = 4'h3;
        golden[  6] = 4'ha;
        golden[  7] = 4'h4;
        golden[  8] = 4'h0;
        golden[  9] = 4'he;
        golden[ 10] = 4'h7;
        golden[ 11] = 4'h9;
        golden[ 12] = 4'hd;
        golden[ 13] = 4'h3;
        golden[ 14] = 4'ha;
        golden[ 15] = 4'h4;
        golden[ 16] = 4'he;
        golden[ 17] = 4'h0;
        golden[ 18] = 4'h9;
        golden[ 19] = 4'h7;
        golden[ 20] = 4'h3;
        golden[ 21] = 4'hd;
        golden[ 22] = 4'h4;
        golden[ 23] = 4'ha;
        golden[ 24] = 4'he;
        golden[ 25] = 4'h0;
        golden[ 26] = 4'h9;
        golden[ 27] = 4'h7;
        golden[ 28] = 4'h3;
        golden[ 29] = 4'hd;
        golden[ 30] = 4'h4;
        golden[ 31] = 4'ha;
        golden[ 32] = 4'h7;
        golden[ 33] = 4'h9;
        golden[ 34] = 4'h0;
        golden[ 35] = 4'he;
        golden[ 36] = 4'ha;
        golden[ 37] = 4'h4;
        golden[ 38] = 4'hd;
        golden[ 39] = 4'h3;
        golden[ 40] = 4'h7;
        golden[ 41] = 4'h9;
        golden[ 42] = 4'h0;
        golden[ 43] = 4'he;
        golden[ 44] = 4'ha;
        golden[ 45] = 4'h4;
        golden[ 46] = 4'hd;
        golden[ 47] = 4'h3;
        golden[ 48] = 4'h9;
        golden[ 49] = 4'h7;
        golden[ 50] = 4'he;
        golden[ 51] = 4'h0;
        golden[ 52] = 4'h4;
        golden[ 53] = 4'ha;
        golden[ 54] = 4'h3;
        golden[ 55] = 4'hd;
        golden[ 56] = 4'h9;
        golden[ 57] = 4'h7;
        golden[ 58] = 4'he;
        golden[ 59] = 4'h0;
        golden[ 60] = 4'h4;
        golden[ 61] = 4'ha;
        golden[ 62] = 4'h3;
        golden[ 63] = 4'hd;
        golden[ 64] = 4'hd;
        golden[ 65] = 4'h3;
        golden[ 66] = 4'ha;
        golden[ 67] = 4'h4;
        golden[ 68] = 4'h0;
        golden[ 69] = 4'he;
        golden[ 70] = 4'h7;
        golden[ 71] = 4'h9;
        golden[ 72] = 4'hd;
        golden[ 73] = 4'h3;
        golden[ 74] = 4'ha;
        golden[ 75] = 4'h4;
        golden[ 76] = 4'h0;
        golden[ 77] = 4'he;
        golden[ 78] = 4'h7;
        golden[ 79] = 4'h9;
        golden[ 80] = 4'h3;
        golden[ 81] = 4'hd;
        golden[ 82] = 4'h4;
        golden[ 83] = 4'ha;
        golden[ 84] = 4'he;
        golden[ 85] = 4'h0;
        golden[ 86] = 4'h9;
        golden[ 87] = 4'h7;
        golden[ 88] = 4'h3;
        golden[ 89] = 4'hd;
        golden[ 90] = 4'h4;
        golden[ 91] = 4'ha;
        golden[ 92] = 4'he;
        golden[ 93] = 4'h0;
        golden[ 94] = 4'h9;
        golden[ 95] = 4'h7;
        golden[ 96] = 4'ha;
        golden[ 97] = 4'h4;
        golden[ 98] = 4'hd;
        golden[ 99] = 4'h3;
        golden[100] = 4'h7;
        golden[101] = 4'h9;
        golden[102] = 4'h0;
        golden[103] = 4'he;
        golden[104] = 4'ha;
        golden[105] = 4'h4;
        golden[106] = 4'hd;
        golden[107] = 4'h3;
        golden[108] = 4'h7;
        golden[109] = 4'h9;
        golden[110] = 4'h0;
        golden[111] = 4'he;
        golden[112] = 4'h4;
        golden[113] = 4'ha;
        golden[114] = 4'h3;
        golden[115] = 4'hd;
        golden[116] = 4'h9;
        golden[117] = 4'h7;
        golden[118] = 4'he;
        golden[119] = 4'h0;
        golden[120] = 4'h4;
        golden[121] = 4'ha;
        golden[122] = 4'h3;
        golden[123] = 4'hd;
        golden[124] = 4'h9;
        golden[125] = 4'h7;
        golden[126] = 4'he;
        golden[127] = 4'h0;
        golden[128] = 4'h0;
        golden[129] = 4'he;
        golden[130] = 4'h7;
        golden[131] = 4'h9;
        golden[132] = 4'hd;
        golden[133] = 4'h3;
        golden[134] = 4'ha;
        golden[135] = 4'h4;
        golden[136] = 4'h0;
        golden[137] = 4'he;
        golden[138] = 4'h7;
        golden[139] = 4'h9;
        golden[140] = 4'hd;
        golden[141] = 4'h3;
        golden[142] = 4'ha;
        golden[143] = 4'h4;
        golden[144] = 4'he;
        golden[145] = 4'h0;
        golden[146] = 4'h9;
        golden[147] = 4'h7;
        golden[148] = 4'h3;
        golden[149] = 4'hd;
        golden[150] = 4'h4;
        golden[151] = 4'ha;
        golden[152] = 4'he;
        golden[153] = 4'h0;
        golden[154] = 4'h9;
        golden[155] = 4'h7;
        golden[156] = 4'h3;
        golden[157] = 4'hd;
        golden[158] = 4'h4;
        golden[159] = 4'ha;
        golden[160] = 4'h7;
        golden[161] = 4'h9;
        golden[162] = 4'h0;
        golden[163] = 4'he;
        golden[164] = 4'ha;
        golden[165] = 4'h4;
        golden[166] = 4'hd;
        golden[167] = 4'h3;
        golden[168] = 4'h7;
        golden[169] = 4'h9;
        golden[170] = 4'h0;
        golden[171] = 4'he;
        golden[172] = 4'ha;
        golden[173] = 4'h4;
        golden[174] = 4'hd;
        golden[175] = 4'h3;
        golden[176] = 4'h9;
        golden[177] = 4'h7;
        golden[178] = 4'he;
        golden[179] = 4'h0;
        golden[180] = 4'h4;
        golden[181] = 4'ha;
        golden[182] = 4'h3;
        golden[183] = 4'hd;
        golden[184] = 4'h9;
        golden[185] = 4'h7;
        golden[186] = 4'he;
        golden[187] = 4'h0;
        golden[188] = 4'h4;
        golden[189] = 4'ha;
        golden[190] = 4'h3;
        golden[191] = 4'hd;
        golden[192] = 4'hd;
        golden[193] = 4'h3;
        golden[194] = 4'ha;
        golden[195] = 4'h4;
        golden[196] = 4'h0;
        golden[197] = 4'he;
        golden[198] = 4'h7;
        golden[199] = 4'h9;
        golden[200] = 4'hd;
        golden[201] = 4'h3;
        golden[202] = 4'ha;
        golden[203] = 4'h4;
        golden[204] = 4'h0;
        golden[205] = 4'he;
        golden[206] = 4'h7;
        golden[207] = 4'h9;
        golden[208] = 4'h3;
        golden[209] = 4'hd;
        golden[210] = 4'h4;
        golden[211] = 4'ha;
        golden[212] = 4'he;
        golden[213] = 4'h0;
        golden[214] = 4'h9;
        golden[215] = 4'h7;
        golden[216] = 4'h3;
        golden[217] = 4'hd;
        golden[218] = 4'h4;
        golden[219] = 4'ha;
        golden[220] = 4'he;
        golden[221] = 4'h0;
        golden[222] = 4'h9;
        golden[223] = 4'h7;
        golden[224] = 4'ha;
        golden[225] = 4'h4;
        golden[226] = 4'hd;
        golden[227] = 4'h3;
        golden[228] = 4'h7;
        golden[229] = 4'h9;
        golden[230] = 4'h0;
        golden[231] = 4'he;
        golden[232] = 4'ha;
        golden[233] = 4'h4;
        golden[234] = 4'hd;
        golden[235] = 4'h3;
        golden[236] = 4'h7;
        golden[237] = 4'h9;
        golden[238] = 4'h0;
        golden[239] = 4'he;
        golden[240] = 4'h4;
        golden[241] = 4'ha;
        golden[242] = 4'h3;
        golden[243] = 4'hd;
        golden[244] = 4'h9;
        golden[245] = 4'h7;
        golden[246] = 4'he;
        golden[247] = 4'h0;
        golden[248] = 4'h4;
        golden[249] = 4'ha;
        golden[250] = 4'h3;
        golden[251] = 4'hd;
        golden[252] = 4'h9;
        golden[253] = 4'h7;
        golden[254] = 4'he;
        golden[255] = 4'h0;

        // ---- init ----
        clk            = 0;
        rst_n          = 0;
        host_in_pkt    = {`TRN_PKT_W{1'b0}};
        host_in_valid  = 0;
        host_out_ready = 0;
        pass_count     = 0;
        fail_count     = 0;

        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // ================================================================
        // TG-Poly-05: GF(2^4) dot4 sweep — 256 vectors against tile 0
        // Operands encoded: a_k = (idx >> k) & 0xF, b_k = (~idx >> k) & 0xF
        // ================================================================
        $display("TG-Poly-05: 256-vector GF(2^4) dot4 sweep on tile 0...");

        for (idx = 0; idx < 256; idx = idx + 1) begin
            a0_v = (idx >> 0) & 4'hF;
            a1_v = (idx >> 1) & 4'hF;
            a2_v = (idx >> 2) & 4'hF;
            a3_v = (idx >> 3) & 4'hF;
            b0_v = (~idx >> 0) & 4'hF;
            b1_v = (~idx >> 1) & 4'hF;
            b2_v = (~idx >> 2) & 4'hF;
            b3_v = (~idx >> 3) & 4'hF;

            // LOAD_A lanes 0..3 to tile 0
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_A, TILE0, HOST, 4'h0, {12'h0, a0_v}));
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_A, TILE0, HOST, 4'h1, {12'h0, a1_v}));
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_A, TILE0, HOST, 4'h2, {12'h0, a2_v}));
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_A, TILE0, HOST, 4'h3, {12'h0, a3_v}));

            // LOAD_B lanes 0..3 to tile 0
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_B, TILE0, HOST, 4'h0, {12'h0, b0_v}));
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_B, TILE0, HOST, 4'h1, {12'h0, b1_v}));
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_B, TILE0, HOST, 4'h2, {12'h0, b2_v}));
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_B, TILE0, HOST, 4'h3, {12'h0, b3_v}));

            // COMPUTE
            send_pkt(`TRN_MK_PKT(`TRN_OP_COMPUTE, TILE0, HOST, 4'h0, 16'h0));

            // READ_RES
            send_pkt(`TRN_MK_PKT(`TRN_OP_READ_RES, TILE0, HOST, 4'h0, 16'h0));

            // Receive RESULT packet
            recv_pkt(50);
            result_pkt = rcvd_pkt;

            // Drain RECEIPT packet (don't check in this test)
            recv_pkt(50);
            receipt_pkt = rcvd_pkt;

            // Check result
            got_result   = result_pkt[3:0]; // low 4 bits of payload
            expected_dot4 = golden[idx];

            if (got_result === expected_dot4) begin
                pass_count = pass_count + 1;
            end else begin
                $display("TG-Poly-05 FAIL idx=%0d: got=4'h%h expected=4'h%h (a=[%0d,%0d,%0d,%0d] b=[%0d,%0d,%0d,%0d])",
                         idx, got_result, expected_dot4,
                         a0_v, a1_v, a2_v, a3_v,
                         b0_v, b1_v, b2_v, b3_v);
                fail_count = fail_count + 1;
            end
        end

        $display("TG-Poly-05: %0d/256 PASS, %0d FAIL", pass_count, fail_count);

        // ================================================================
        // TG-Poly-06: RECEIPT protocol verification
        // Loads job_id=0xAB, nonce=0x42, operands a=[3,5,7,9] b=[2,4,6,8]
        // Expected checksum = job_id ^ result[7:0] = 0xAB ^ dot4_result
        // ================================================================
        $display("TG-Poly-06: RECEIPT protocol verify...");
        begin
            reg [7:0] jid;
            reg [3:0] res_4bit;
            reg [7:0] exp_csum;
            reg [`TRN_PKT_W-1:0] rcpt;
            reg ok;

            jid = 8'hAB;
            ok  = 1'b1;

            // Set job_id and nonce on tile 0
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_JOB,   TILE0, HOST, 4'h0, {8'h0, jid}));
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_NONCE, TILE0, HOST, 4'h0, 16'h0042));

            // Load a=[3,5,7,9] b=[2,4,6,8]
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_A, TILE0, HOST, 4'h0, 16'h0003));
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_A, TILE0, HOST, 4'h1, 16'h0005));
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_A, TILE0, HOST, 4'h2, 16'h0007));
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_A, TILE0, HOST, 4'h3, 16'h0009));
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_B, TILE0, HOST, 4'h0, 16'h0002));
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_B, TILE0, HOST, 4'h1, 16'h0004));
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_B, TILE0, HOST, 4'h2, 16'h0006));
            send_pkt(`TRN_MK_PKT(`TRN_OP_LOAD_B, TILE0, HOST, 4'h3, 16'h0008));

            // COMPUTE and READ_RES
            send_pkt(`TRN_MK_PKT(`TRN_OP_COMPUTE,  TILE0, HOST, 4'h0, 16'h0));
            send_pkt(`TRN_MK_PKT(`TRN_OP_READ_RES, TILE0, HOST, 4'h0, 16'h0));

            // Receive RESULT
            recv_pkt(50);
            result_pkt = rcvd_pkt;
            res_4bit   = result_pkt[3:0];

            // Receive RECEIPT
            recv_pkt(50);
            rcpt = rcvd_pkt;

            // Expected: dot4([3,5,7,9],[2,4,6,8]) in GF(2^4) mod x^4+x+1
            // Python: 3*2 ^ 5*4 ^ 7*6 ^ 9*8
            //       = 6 ^ 7 ^ 1 ^ 4  (from table)  = 6^7^1^4 = 4
            // Verified: gf16_mul(3,2)=6, gf16_mul(5,4)=7, gf16_mul(7,6)=1, gf16_mul(9,8)=4
            //           6^7^1^4 = 4 (0x4)
            if (res_4bit !== 4'h4) begin
                $display("TG-Poly-06 FAIL: dot4([3,5,7,9],[2,4,6,8]) got=4'h%h expected=4'h4", res_4bit);
                ok = 1'b0;
            end

            // Verify RECEIPT fields
            exp_csum = jid ^ {4'h0, res_4bit}; // job_id ^ result[7:0]
            got_checksum = `TRN_RCPT_PKT_CHECKSUM(rcpt);
            got_job_id   = `TRN_RCPT_PKT_JOB_LO(rcpt);
            got_tile_id  = {2'h0, `TRN_RCPT_PKT_TILE(rcpt)};

            if (`TRN_PKT_OP(rcpt) !== `TRN_OP_RECEIPT) begin
                $display("TG-Poly-06 FAIL: expected RECEIPT op, got op=4'h%h",
                         `TRN_PKT_OP(rcpt));
                ok = 1'b0;
            end
            if (got_checksum !== exp_csum) begin
                $display("TG-Poly-06 FAIL: checksum got=0x%02h expected=0x%02h",
                         got_checksum, exp_csum);
                ok = 1'b0;
            end
            if (got_job_id !== jid) begin
                $display("TG-Poly-06 FAIL: job_id_lo got=0x%02h expected=0x%02h",
                         got_job_id, jid);
                ok = 1'b0;
            end
            if (got_tile_id !== 4'd0) begin
                $display("TG-Poly-06 FAIL: tile_id got=%0d expected=0",
                         got_tile_id);
                ok = 1'b0;
            end

            if (ok) begin
                $display("TG-Poly-06: PASS — dot4=4'h2, checksum=0x%02h, job_id=0x%02h, tile=0",
                         got_checksum, got_job_id);
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end

        // ================================================================
        // Summary
        // ================================================================
        $display("tb_trinity_mesh_4x4_poly: %0d PASS, %0d FAIL",
                 pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAILURES DETECTED");

        $finish;
    end

endmodule
