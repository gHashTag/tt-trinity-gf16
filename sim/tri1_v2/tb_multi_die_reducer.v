// SPDX-License-Identifier: Apache-2.0
// tb_multi_die_reducer.v — L-S48 Multi-Die Ledger Reducer Testbench (Wave-13b)
//
// 88 test patterns:
//   [00..07] — 8 deterministic 8-leaf patterns
//   [08..87] — 80 LFSR-seeded random 8-leaf streams
//
// Golden reference: Python gen_tb.py (3-round XOR+rotate, R1=5,R2=11,R3=22)
//   hash_combine(a,b):
//     s0  = a ^ b
//     s1  = rotl64(s0, 5)  ^ a
//     s2  = rotl64(s1, 11) ^ b
//     out = rotl64(s2, 22) ^ a ^ b
//
// 3-stage topology: 8->4->2->1 (Stage0 comb -> PipeReg1 -> Stage1 comb -> PipeReg2 -> Stage2 -> OutReg)
// Pipeline latency: 3 cycles
// Token: MULTI_DIE_REDUCER_GREEN
//
`default_nettype none
`timescale 1ns/1ps

module tb_multi_die_reducer;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    reg         clk;
    reg         rst_n;
    reg  [63:0] die0, die1, die2, die3;
    reg  [63:0] die4, die5, die6, die7;
    reg         dies_valid;
    wire [63:0] super_root;
    wire        super_root_valid;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    multi_die_reducer dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .die0             (die0),
        .die1             (die1),
        .die2             (die2),
        .die3             (die3),
        .die4             (die4),
        .die5             (die5),
        .die6             (die6),
        .die7             (die7),
        .dies_valid       (dies_valid),
        .super_root       (super_root),
        .super_root_valid (super_root_valid)
    );

    // ----------------------------------------------------------------
    // Clock: 10 ns period
    // ----------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Test vectors — 88 patterns
    // ----------------------------------------------------------------
    reg [63:0] stim_l0 [0:87];
    reg [63:0] stim_l1 [0:87];
    reg [63:0] stim_l2 [0:87];
    reg [63:0] stim_l3 [0:87];
    reg [63:0] stim_l4 [0:87];
    reg [63:0] stim_l5 [0:87];
    reg [63:0] stim_l6 [0:87];
    reg [63:0] stim_l7 [0:87];
    reg [63:0] gold    [0:87];

    integer i;
    integer pass_cnt, fail_cnt;
    integer chk_idx;

    // ----------------------------------------------------------------
    // Golden vector initialisation
    // ----------------------------------------------------------------
    initial begin
        // [00] all_zero
        stim_l0[0] = 64'h0000000000000000;
        stim_l1[0] = 64'h0000000000000000;
        stim_l2[0] = 64'h0000000000000000;
        stim_l3[0] = 64'h0000000000000000;
        stim_l4[0] = 64'h0000000000000000;
        stim_l5[0] = 64'h0000000000000000;
        stim_l6[0] = 64'h0000000000000000;
        stim_l7[0] = 64'h0000000000000000;
        gold[0] = 64'h0000000000000000;
        // [01] all_ones
        stim_l0[1] = 64'hFFFFFFFFFFFFFFFF;
        stim_l1[1] = 64'hFFFFFFFFFFFFFFFF;
        stim_l2[1] = 64'hFFFFFFFFFFFFFFFF;
        stim_l3[1] = 64'hFFFFFFFFFFFFFFFF;
        stim_l4[1] = 64'hFFFFFFFFFFFFFFFF;
        stim_l5[1] = 64'hFFFFFFFFFFFFFFFF;
        stim_l6[1] = 64'hFFFFFFFFFFFFFFFF;
        stim_l7[1] = 64'hFFFFFFFFFFFFFFFF;
        gold[1] = 64'h0000000000000000;
        // [02] single_bit_0
        stim_l0[2] = 64'h0000000000000001;
        stim_l1[2] = 64'h0000000000000000;
        stim_l2[2] = 64'h0000000000000000;
        stim_l3[2] = 64'h0000000000000000;
        stim_l4[2] = 64'h0000000000000000;
        stim_l5[2] = 64'h0000000000000000;
        stim_l6[2] = 64'h0000000000000000;
        stim_l7[2] = 64'h0000000000000000;
        gold[2] = 64'h0004214A00001005;
        // [03] single_bit_7
        stim_l0[3] = 64'h0000000000000000;
        stim_l1[3] = 64'h0000000000000000;
        stim_l2[3] = 64'h0000000000000000;
        stim_l3[3] = 64'h0000000000000000;
        stim_l4[3] = 64'h0000000000000000;
        stim_l5[3] = 64'h0000000000000000;
        stim_l6[3] = 64'h0000000000000000;
        stim_l7[3] = 64'h8000000000000000;
        gold[3] = 64'h8002082200220802;
        // [04] ascending
        stim_l0[4] = 64'h0000000000000000;
        stim_l1[4] = 64'h0101010101010101;
        stim_l2[4] = 64'h0202020202020202;
        stim_l3[4] = 64'h0303030303030303;
        stim_l4[4] = 64'h0404040404040404;
        stim_l5[4] = 64'h0505050505050505;
        stim_l6[4] = 64'h0606060606060606;
        stim_l7[4] = 64'h0707070707070707;
        gold[4] = 64'h6C6C6C6C6C6C6C6C;
        // [05] descending
        stim_l0[5] = 64'hF7F7F7F7F7F7F7F7;
        stim_l1[5] = 64'hF6F6F6F6F6F6F6F6;
        stim_l2[5] = 64'hF5F5F5F5F5F5F5F5;
        stim_l3[5] = 64'hF4F4F4F4F4F4F4F4;
        stim_l4[5] = 64'hF3F3F3F3F3F3F3F3;
        stim_l5[5] = 64'hF2F2F2F2F2F2F2F2;
        stim_l6[5] = 64'hF1F1F1F1F1F1F1F1;
        stim_l7[5] = 64'hF0F0F0F0F0F0F0F0;
        gold[5] = 64'h0505050505050505;
        // [06] mixed
        stim_l0[6] = 64'hDEADBEEFCAFEBABE;
        stim_l1[6] = 64'h0123456789ABCDEF;
        stim_l2[6] = 64'hFEDCBA9876543210;
        stim_l3[6] = 64'hA5A5A5A5A5A5A5A5;
        stim_l4[6] = 64'h1111111111111111;
        stim_l5[6] = 64'h2222222222222222;
        stim_l6[6] = 64'h4444444444444444;
        stim_l7[6] = 64'h8888888888888888;
        gold[6] = 64'h46C22EF98FAD3614;
        // [07] alternating
        stim_l0[7] = 64'h5555555555555555;
        stim_l1[7] = 64'hAAAAAAAAAAAAAAAA;
        stim_l2[7] = 64'h3333333333333333;
        stim_l3[7] = 64'hCCCCCCCCCCCCCCCC;
        stim_l4[7] = 64'hF0F0F0F0F0F0F0F0;
        stim_l5[7] = 64'h0F0F0F0F0F0F0F0F;
        stim_l6[7] = 64'hFF00FF00FF00FF00;
        stim_l7[7] = 64'h00FF00FF00FF00FF;
        gold[7] = 64'h8585858585858585;
        // [08] lfsr_00
        stim_l0[8] = 64'h8E70FD676F56DF77;
        stim_l1[8] = 64'h9F387EB3B7AB6FBB;
        stim_l2[8] = 64'h979C3F59DBD5B7DD;
        stim_l3[8] = 64'h93CE1FACEDEADBEE;
        stim_l4[8] = 64'h49E70FD676F56DF7;
        stim_l5[8] = 64'hFCF387EB3B7AB6FB;
        stim_l6[8] = 64'hA679C3F59DBD5B7D;
        stim_l7[8] = 64'h8B3CE1FACEDEADBE;
        gold[8] = 64'hB783E6F32E45C282;
        // [09] lfsr_01
        stim_l0[9] = 64'h459E70FD676F56DF;
        stim_l1[9] = 64'hFACF387EB3B7AB6F;
        stim_l2[9] = 64'hA5679C3F59DBD5B7;
        stim_l3[9] = 64'h8AB3CE1FACEDEADB;
        stim_l4[9] = 64'h9D59E70FD676F56D;
        stim_l5[9] = 64'h96ACF387EB3B7AB6;
        stim_l6[9] = 64'h4B5679C3F59DBD5B;
        stim_l7[9] = 64'hFDAB3CE1FACEDEAD;
        gold[9] = 64'h15B7F1F9DA982562;
        // [10] lfsr_02
        stim_l0[10] = 64'hA6D59E70FD676F56;
        stim_l1[10] = 64'h536ACF387EB3B7AB;
        stim_l2[10] = 64'hF1B5679C3F59DBD5;
        stim_l3[10] = 64'hA0DAB3CE1FACEDEA;
        stim_l4[10] = 64'h506D59E70FD676F5;
        stim_l5[10] = 64'hF036ACF387EB3B7A;
        stim_l6[10] = 64'h781B5679C3F59DBD;
        stim_l7[10] = 64'hE40DAB3CE1FACEDE;
        gold[10] = 64'hD7E418854D7F102B;
        // [11] lfsr_03
        stim_l0[11] = 64'h7206D59E70FD676F;
        stim_l1[11] = 64'hE1036ACF387EB3B7;
        stim_l2[11] = 64'hA881B5679C3F59DB;
        stim_l3[11] = 64'h8C40DAB3CE1FACED;
        stim_l4[11] = 64'h9E206D59E70FD676;
        stim_l5[11] = 64'h4F1036ACF387EB3B;
        stim_l6[11] = 64'hFF881B5679C3F59D;
        stim_l7[11] = 64'hA7C40DAB3CE1FACE;
        gold[11] = 64'h3CB7A4C2A779D36C;
        // [12] lfsr_04
        stim_l0[12] = 64'h53E206D59E70FD67;
        stim_l1[12] = 64'hF1F1036ACF387EB3;
        stim_l2[12] = 64'hA0F881B5679C3F59;
        stim_l3[12] = 64'h887C40DAB3CE1FAC;
        stim_l4[12] = 64'h443E206D59E70FD6;
        stim_l5[12] = 64'h221F1036ACF387EB;
        stim_l6[12] = 64'hC90F881B5679C3F5;
        stim_l7[12] = 64'hBC87C40DAB3CE1FA;
        gold[12] = 64'h007D14B2C8B68388;
        // [13] lfsr_05
        stim_l0[13] = 64'h5E43E206D59E70FD;
        stim_l1[13] = 64'hF721F1036ACF387E;
        stim_l2[13] = 64'h7B90F881B5679C3F;
        stim_l3[13] = 64'hE5C87C40DAB3CE1F;
        stim_l4[13] = 64'hAAE43E206D59E70F;
        stim_l5[13] = 64'h8D721F1036ACF387;
        stim_l6[13] = 64'h9EB90F881B5679C3;
        stim_l7[13] = 64'h975C87C40DAB3CE1;
        gold[13] = 64'hB8105B43BA2FB0A3;
        // [14] lfsr_06
        stim_l0[14] = 64'h93AE43E206D59E70;
        stim_l1[14] = 64'h49D721F1036ACF38;
        stim_l2[14] = 64'h24EB90F881B5679C;
        stim_l3[14] = 64'h1275C87C40DAB3CE;
        stim_l4[14] = 64'h093AE43E206D59E7;
        stim_l5[14] = 64'hDC9D721F1036ACF3;
        stim_l6[14] = 64'hB64EB90F881B5679;
        stim_l7[14] = 64'h83275C87C40DAB3C;
        gold[14] = 64'h3F08097611032809;
        // [15] lfsr_07
        stim_l0[15] = 64'h4193AE43E206D59E;
        stim_l1[15] = 64'h20C9D721F1036ACF;
        stim_l2[15] = 64'hC864EB90F881B567;
        stim_l3[15] = 64'hBC3275C87C40DAB3;
        stim_l4[15] = 64'h86193AE43E206D59;
        stim_l5[15] = 64'h9B0C9D721F1036AC;
        stim_l6[15] = 64'h4D864EB90F881B56;
        stim_l7[15] = 64'h26C3275C87C40DAB;
        gold[15] = 64'h3B2FA9EEDBF1E275;
        // [16] lfsr_08
        stim_l0[16] = 64'hCB6193AE43E206D5;
        stim_l1[16] = 64'hBDB0C9D721F1036A;
        stim_l2[16] = 64'h5ED864EB90F881B5;
        stim_l3[16] = 64'hF76C3275C87C40DA;
        stim_l4[16] = 64'h7BB6193AE43E206D;
        stim_l5[16] = 64'hE5DB0C9D721F1036;
        stim_l6[16] = 64'h72ED864EB90F881B;
        stim_l7[16] = 64'hE176C3275C87C40D;
        gold[16] = 64'hF1CA59F45C1B34BA;
        // [17] lfsr_09
        stim_l0[17] = 64'hA8BB6193AE43E206;
        stim_l1[17] = 64'h545DB0C9D721F103;
        stim_l2[17] = 64'hF22ED864EB90F881;
        stim_l3[17] = 64'hA1176C3275C87C40;
        stim_l4[17] = 64'h508BB6193AE43E20;
        stim_l5[17] = 64'h2845DB0C9D721F10;
        stim_l6[17] = 64'h1422ED864EB90F88;
        stim_l7[17] = 64'h0A1176C3275C87C4;
        gold[17] = 64'h15809D85130920B9;
        // [18] lfsr_10
        stim_l0[18] = 64'h0508BB6193AE43E2;
        stim_l1[18] = 64'h02845DB0C9D721F1;
        stim_l2[18] = 64'hD9422ED864EB90F8;
        stim_l3[18] = 64'h6CA1176C3275C87C;
        stim_l4[18] = 64'h36508BB6193AE43E;
        stim_l5[18] = 64'h1B2845DB0C9D721F;
        stim_l6[18] = 64'hD59422ED864EB90F;
        stim_l7[18] = 64'hB2CA1176C3275C87;
        gold[18] = 64'h11948D216C923B78;
        // [19] lfsr_11
        stim_l0[19] = 64'h816508BB6193AE43;
        stim_l1[19] = 64'h98B2845DB0C9D721;
        stim_l2[19] = 64'h9459422ED864EB90;
        stim_l3[19] = 64'h4A2CA1176C3275C8;
        stim_l4[19] = 64'h2516508BB6193AE4;
        stim_l5[19] = 64'h128B2845DB0C9D72;
        stim_l6[19] = 64'h09459422ED864EB9;
        stim_l7[19] = 64'hDCA2CA1176C3275C;
        gold[19] = 64'hFAB1F5D52A225D61;
        // [20] lfsr_12
        stim_l0[20] = 64'h6E516508BB6193AE;
        stim_l1[20] = 64'h3728B2845DB0C9D7;
        stim_l2[20] = 64'hC39459422ED864EB;
        stim_l3[20] = 64'hB9CA2CA1176C3275;
        stim_l4[20] = 64'h84E516508BB6193A;
        stim_l5[20] = 64'h42728B2845DB0C9D;
        stim_l6[20] = 64'hF939459422ED864E;
        stim_l7[20] = 64'h7C9CA2CA1176C327;
        gold[20] = 64'hEB4A12AF1B4E9AB4;
        // [21] lfsr_13
        stim_l0[21] = 64'hE64E516508BB6193;
        stim_l1[21] = 64'hAB2728B2845DB0C9;
        stim_l2[21] = 64'h8D939459422ED864;
        stim_l3[21] = 64'h46C9CA2CA1176C32;
        stim_l4[21] = 64'h2364E516508BB619;
        stim_l5[21] = 64'hC9B2728B2845DB0C;
        stim_l6[21] = 64'h64D939459422ED86;
        stim_l7[21] = 64'h326C9CA2CA1176C3;
        gold[21] = 64'hDD9B03A4F3DC28DC;
        // [22] lfsr_14
        stim_l0[22] = 64'hC1364E516508BB61;
        stim_l1[22] = 64'hB89B2728B2845DB0;
        stim_l2[22] = 64'h5C4D939459422ED8;
        stim_l3[22] = 64'h2E26C9CA2CA1176C;
        stim_l4[22] = 64'h171364E516508BB6;
        stim_l5[22] = 64'h0B89B2728B2845DB;
        stim_l6[22] = 64'hDDC4D939459422ED;
        stim_l7[22] = 64'hB6E26C9CA2CA1176;
        gold[22] = 64'h7F9D1B03DED8477D;
        // [23] lfsr_15
        stim_l0[23] = 64'h5B71364E516508BB;
        stim_l1[23] = 64'hF5B89B2728B2845D;
        stim_l2[23] = 64'hA2DC4D939459422E;
        stim_l3[23] = 64'h516E26C9CA2CA117;
        stim_l4[23] = 64'hF0B71364E516508B;
        stim_l5[23] = 64'hA05B89B2728B2845;
        stim_l6[23] = 64'h882DC4D939459422;
        stim_l7[23] = 64'h4416E26C9CA2CA11;
        gold[23] = 64'hEB6ED432EE955C17;
        // [24] lfsr_16
        stim_l0[24] = 64'hFA0B71364E516508;
        stim_l1[24] = 64'h7D05B89B2728B284;
        stim_l2[24] = 64'h3E82DC4D93945942;
        stim_l3[24] = 64'h1F416E26C9CA2CA1;
        stim_l4[24] = 64'hD7A0B71364E51650;
        stim_l5[24] = 64'h6BD05B89B2728B28;
        stim_l6[24] = 64'h35E82DC4D9394594;
        stim_l7[24] = 64'h1AF416E26C9CA2CA;
        gold[24] = 64'h990B3EDE4C7B34CA;
        // [25] lfsr_17
        stim_l0[25] = 64'h0D7A0B71364E5165;
        stim_l1[25] = 64'hDEBD05B89B2728B2;
        stim_l2[25] = 64'h6F5E82DC4D939459;
        stim_l3[25] = 64'hEFAF416E26C9CA2C;
        stim_l4[25] = 64'h77D7A0B71364E516;
        stim_l5[25] = 64'h3BEBD05B89B2728B;
        stim_l6[25] = 64'hC5F5E82DC4D93945;
        stim_l7[25] = 64'hBAFAF416E26C9CA2;
        gold[25] = 64'h74A9A94E0DF53879;
        // [26] lfsr_18
        stim_l0[26] = 64'h5D7D7A0B71364E51;
        stim_l1[26] = 64'hF6BEBD05B89B2728;
        stim_l2[26] = 64'h7B5F5E82DC4D9394;
        stim_l3[26] = 64'h3DAFAF416E26C9CA;
        stim_l4[26] = 64'h1ED7D7A0B71364E5;
        stim_l5[26] = 64'hD76BEBD05B89B272;
        stim_l6[26] = 64'h6BB5F5E82DC4D939;
        stim_l7[26] = 64'hEDDAFAF416E26C9C;
        gold[26] = 64'h64754A429D8BDAFC;
        // [27] lfsr_19
        stim_l0[27] = 64'h76ED7D7A0B71364E;
        stim_l1[27] = 64'h3B76BEBD05B89B27;
        stim_l2[27] = 64'hC5BB5F5E82DC4D93;
        stim_l3[27] = 64'hBADDAFAF416E26C9;
        stim_l4[27] = 64'h856ED7D7A0B71364;
        stim_l5[27] = 64'h42B76BEBD05B89B2;
        stim_l6[27] = 64'h215BB5F5E82DC4D9;
        stim_l7[27] = 64'hC8ADDAFAF416E26C;
        gold[27] = 64'hB2145FA284E21F9A;
        // [28] lfsr_20
        stim_l0[28] = 64'h6456ED7D7A0B7136;
        stim_l1[28] = 64'h322B76BEBD05B89B;
        stim_l2[28] = 64'hC115BB5F5E82DC4D;
        stim_l3[28] = 64'hB88ADDAFAF416E26;
        stim_l4[28] = 64'h5C456ED7D7A0B713;
        stim_l5[28] = 64'hF622B76BEBD05B89;
        stim_l6[28] = 64'hA3115BB5F5E82DC4;
        stim_l7[28] = 64'h5188ADDAFAF416E2;
        gold[28] = 64'h1C328389D06AB102;
        // [29] lfsr_21
        stim_l0[29] = 64'h28C456ED7D7A0B71;
        stim_l1[29] = 64'hCC622B76BEBD05B8;
        stim_l2[29] = 64'h663115BB5F5E82DC;
        stim_l3[29] = 64'h33188ADDAFAF416E;
        stim_l4[29] = 64'h198C456ED7D7A0B7;
        stim_l5[29] = 64'hD4C622B76BEBD05B;
        stim_l6[29] = 64'hB263115BB5F5E82D;
        stim_l7[29] = 64'h813188ADDAFAF416;
        gold[29] = 64'h193CE4ABC1022EE5;
        // [30] lfsr_22
        stim_l0[30] = 64'h4098C456ED7D7A0B;
        stim_l1[30] = 64'hF84C622B76BEBD05;
        stim_l2[30] = 64'hA4263115BB5F5E82;
        stim_l3[30] = 64'h5213188ADDAFAF41;
        stim_l4[30] = 64'hF1098C456ED7D7A0;
        stim_l5[30] = 64'h7884C622B76BEBD0;
        stim_l6[30] = 64'h3C4263115BB5F5E8;
        stim_l7[30] = 64'h1E213188ADDAFAF4;
        gold[30] = 64'hB3581E3DB18253EB;
        // [31] lfsr_23
        stim_l0[31] = 64'h0F1098C456ED7D7A;
        stim_l1[31] = 64'h07884C622B76BEBD;
        stim_l2[31] = 64'hDBC4263115BB5F5E;
        stim_l3[31] = 64'h6DE213188ADDAFAF;
        stim_l4[31] = 64'hEEF1098C456ED7D7;
        stim_l5[31] = 64'hAF7884C622B76BEB;
        stim_l6[31] = 64'h8FBC4263115BB5F5;
        stim_l7[31] = 64'h9FDE213188ADDAFA;
        gold[31] = 64'h4F02612E68BA5BFF;
        // [32] lfsr_24
        stim_l0[32] = 64'h4FEF1098C456ED7D;
        stim_l1[32] = 64'hFFF7884C622B76BE;
        stim_l2[32] = 64'h7FFBC4263115BB5F;
        stim_l3[32] = 64'hE7FDE213188ADDAF;
        stim_l4[32] = 64'hABFEF1098C456ED7;
        stim_l5[32] = 64'h8DFF7884C622B76B;
        stim_l6[32] = 64'h9EFFBC4263115BB5;
        stim_l7[32] = 64'h977FDE213188ADDA;
        gold[32] = 64'hE23F0704154B5B8B;
        // [33] lfsr_25
        stim_l0[33] = 64'h4BBFEF1098C456ED;
        stim_l1[33] = 64'hFDDFF7884C622B76;
        stim_l2[33] = 64'h7EEFFBC4263115BB;
        stim_l3[33] = 64'hE777FDE213188ADD;
        stim_l4[33] = 64'hABBBFEF1098C456E;
        stim_l5[33] = 64'h55DDFF7884C622B7;
        stim_l6[33] = 64'hF2EEFFBC4263115B;
        stim_l7[33] = 64'hA1777FDE213188AD;
        gold[33] = 64'hA723B37AF813920C;
        // [34] lfsr_26
        stim_l0[34] = 64'h88BBBFEF1098C456;
        stim_l1[34] = 64'h445DDFF7884C622B;
        stim_l2[34] = 64'hFA2EEFFBC4263115;
        stim_l3[34] = 64'hA51777FDE213188A;
        stim_l4[34] = 64'h528BBBFEF1098C45;
        stim_l5[34] = 64'hF145DDFF7884C622;
        stim_l6[34] = 64'h78A2EEFFBC426311;
        stim_l7[34] = 64'hE451777FDE213188;
        gold[34] = 64'hFD86D04905371EC3;
        // [35] lfsr_27
        stim_l0[35] = 64'h7228BBBFEF1098C4;
        stim_l1[35] = 64'h39145DDFF7884C62;
        stim_l2[35] = 64'h1C8A2EEFFBC42631;
        stim_l3[35] = 64'hD6451777FDE21318;
        stim_l4[35] = 64'h6B228BBBFEF1098C;
        stim_l5[35] = 64'h359145DDFF7884C6;
        stim_l6[35] = 64'h1AC8A2EEFFBC4263;
        stim_l7[35] = 64'hD56451777FDE2131;
        gold[35] = 64'hFE7DBA8BE64A2D1D;
        // [36] lfsr_28
        stim_l0[36] = 64'hB2B228BBBFEF1098;
        stim_l1[36] = 64'h5959145DDFF7884C;
        stim_l2[36] = 64'h2CAC8A2EEFFBC426;
        stim_l3[36] = 64'h1656451777FDE213;
        stim_l4[36] = 64'hD32B228BBBFEF109;
        stim_l5[36] = 64'hB1959145DDFF7884;
        stim_l6[36] = 64'h58CAC8A2EEFFBC42;
        stim_l7[36] = 64'h2C656451777FDE21;
        gold[36] = 64'h066F3E919167A272;
        // [37] lfsr_29
        stim_l0[37] = 64'hCE32B228BBBFEF10;
        stim_l1[37] = 64'h671959145DDFF788;
        stim_l2[37] = 64'h338CAC8A2EEFFBC4;
        stim_l3[37] = 64'h19C656451777FDE2;
        stim_l4[37] = 64'h0CE32B228BBBFEF1;
        stim_l5[37] = 64'hDE71959145DDFF78;
        stim_l6[37] = 64'h6F38CAC8A2EEFFBC;
        stim_l7[37] = 64'h379C656451777FDE;
        gold[37] = 64'h9B1676D233C04F64;
        // [38] lfsr_30
        stim_l0[38] = 64'h1BCE32B228BBBFEF;
        stim_l1[38] = 64'hD5E71959145DDFF7;
        stim_l2[38] = 64'hB2F38CAC8A2EEFFB;
        stim_l3[38] = 64'h8179C656451777FD;
        stim_l4[38] = 64'h98BCE32B228BBBFE;
        stim_l5[38] = 64'h4C5E71959145DDFF;
        stim_l6[38] = 64'hFE2F38CAC8A2EEFF;
        stim_l7[38] = 64'hA7179C656451777F;
        gold[38] = 64'h82AB86EAF47E76AC;
        // [39] lfsr_31
        stim_l0[39] = 64'h8B8BCE32B228BBBF;
        stim_l1[39] = 64'h9DC5E71959145DDF;
        stim_l2[39] = 64'h96E2F38CAC8A2EEF;
        stim_l3[39] = 64'h937179C656451777;
        stim_l4[39] = 64'h91B8BCE32B228BBB;
        stim_l5[39] = 64'h90DC5E71959145DD;
        stim_l6[39] = 64'h906E2F38CAC8A2EE;
        stim_l7[39] = 64'h4837179C65645177;
        gold[39] = 64'h1493F907310A8F71;
        // [40] lfsr_32
        stim_l0[40] = 64'hFC1B8BCE32B228BB;
        stim_l1[40] = 64'hA60DC5E71959145D;
        stim_l2[40] = 64'h8B06E2F38CAC8A2E;
        stim_l3[40] = 64'h45837179C6564517;
        stim_l4[40] = 64'hFAC1B8BCE32B228B;
        stim_l5[40] = 64'hA560DC5E71959145;
        stim_l6[40] = 64'h8AB06E2F38CAC8A2;
        stim_l7[40] = 64'h455837179C656451;
        gold[40] = 64'hC54493C27C56BC26;
        // [41] lfsr_33
        stim_l0[41] = 64'hFAAC1B8BCE32B228;
        stim_l1[41] = 64'h7D560DC5E7195914;
        stim_l2[41] = 64'h3EAB06E2F38CAC8A;
        stim_l3[41] = 64'h1F55837179C65645;
        stim_l4[41] = 64'hD7AAC1B8BCE32B22;
        stim_l5[41] = 64'h6BD560DC5E719591;
        stim_l6[41] = 64'hEDEAB06E2F38CAC8;
        stim_l7[41] = 64'h76F55837179C6564;
        gold[41] = 64'h6C24C8C4BCE32B6A;
        // [42] lfsr_34
        stim_l0[42] = 64'h3B7AAC1B8BCE32B2;
        stim_l1[42] = 64'h1DBD560DC5E71959;
        stim_l2[42] = 64'hD6DEAB06E2F38CAC;
        stim_l3[42] = 64'h6B6F55837179C656;
        stim_l4[42] = 64'h35B7AAC1B8BCE32B;
        stim_l5[42] = 64'hC2DBD560DC5E7195;
        stim_l6[42] = 64'hB96DEAB06E2F38CA;
        stim_l7[42] = 64'h5CB6F55837179C65;
        gold[42] = 64'hAB2DB1311D60D6F6;
        // [43] lfsr_35
        stim_l0[43] = 64'hF65B7AAC1B8BCE32;
        stim_l1[43] = 64'h7B2DBD560DC5E719;
        stim_l2[43] = 64'hE596DEAB06E2F38C;
        stim_l3[43] = 64'h72CB6F55837179C6;
        stim_l4[43] = 64'h3965B7AAC1B8BCE3;
        stim_l5[43] = 64'hC4B2DBD560DC5E71;
        stim_l6[43] = 64'hBA596DEAB06E2F38;
        stim_l7[43] = 64'h5D2CB6F55837179C;
        gold[43] = 64'hE26B2671D594E170;
        // [44] lfsr_36
        stim_l0[44] = 64'h2E965B7AAC1B8BCE;
        stim_l1[44] = 64'h174B2DBD560DC5E7;
        stim_l2[44] = 64'hD3A596DEAB06E2F3;
        stim_l3[44] = 64'hB1D2CB6F55837179;
        stim_l4[44] = 64'h80E965B7AAC1B8BC;
        stim_l5[44] = 64'h4074B2DBD560DC5E;
        stim_l6[44] = 64'h203A596DEAB06E2F;
        stim_l7[44] = 64'hC81D2CB6F5583717;
        gold[44] = 64'hBEF2F3B3489EAE33;
        // [45] lfsr_37
        stim_l0[45] = 64'hBC0E965B7AAC1B8B;
        stim_l1[45] = 64'h86074B2DBD560DC5;
        stim_l2[45] = 64'h9B03A596DEAB06E2;
        stim_l3[45] = 64'h4D81D2CB6F558371;
        stim_l4[45] = 64'hFEC0E965B7AAC1B8;
        stim_l5[45] = 64'h7F6074B2DBD560DC;
        stim_l6[45] = 64'h3FB03A596DEAB06E;
        stim_l7[45] = 64'h1FD81D2CB6F55837;
        gold[45] = 64'hC14E2C286F13CF1D;
        // [46] lfsr_38
        stim_l0[46] = 64'hD7EC0E965B7AAC1B;
        stim_l1[46] = 64'hB3F6074B2DBD560D;
        stim_l2[46] = 64'h81FB03A596DEAB06;
        stim_l3[46] = 64'h40FD81D2CB6F5583;
        stim_l4[46] = 64'hF87EC0E965B7AAC1;
        stim_l5[46] = 64'hA43F6074B2DBD560;
        stim_l6[46] = 64'h521FB03A596DEAB0;
        stim_l7[46] = 64'h290FD81D2CB6F558;
        gold[46] = 64'h2080C5B2F7A9C455;
        // [47] lfsr_39
        stim_l0[47] = 64'h1487EC0E965B7AAC;
        stim_l1[47] = 64'h0A43F6074B2DBD56;
        stim_l2[47] = 64'h0521FB03A596DEAB;
        stim_l3[47] = 64'hDA90FD81D2CB6F55;
        stim_l4[47] = 64'hB5487EC0E965B7AA;
        stim_l5[47] = 64'h5AA43F6074B2DBD5;
        stim_l6[47] = 64'hF5521FB03A596DEA;
        stim_l7[47] = 64'h7AA90FD81D2CB6F5;
        gold[47] = 64'h5A016A509A93C3E1;
        // [48] lfsr_40
        stim_l0[48] = 64'hE55487EC0E965B7A;
        stim_l1[48] = 64'h72AA43F6074B2DBD;
        stim_l2[48] = 64'hE15521FB03A596DE;
        stim_l3[48] = 64'h70AA90FD81D2CB6F;
        stim_l4[48] = 64'hE055487EC0E965B7;
        stim_l5[48] = 64'hA82AA43F6074B2DB;
        stim_l6[48] = 64'h8C15521FB03A596D;
        stim_l7[48] = 64'h9E0AA90FD81D2CB6;
        gold[48] = 64'hC11AE9A7A86C09D3;
        // [49] lfsr_41
        stim_l0[49] = 64'h4F055487EC0E965B;
        stim_l1[49] = 64'hFF82AA43F6074B2D;
        stim_l2[49] = 64'hA7C15521FB03A596;
        stim_l3[49] = 64'h53E0AA90FD81D2CB;
        stim_l4[49] = 64'hF1F055487EC0E965;
        stim_l5[49] = 64'hA0F82AA43F6074B2;
        stim_l6[49] = 64'h507C15521FB03A59;
        stim_l7[49] = 64'hF03E0AA90FD81D2C;
        gold[49] = 64'h9D70C24E76FB8E44;
        // [50] lfsr_42
        stim_l0[50] = 64'h781F055487EC0E96;
        stim_l1[50] = 64'h3C0F82AA43F6074B;
        stim_l2[50] = 64'hC607C15521FB03A5;
        stim_l3[50] = 64'hBB03E0AA90FD81D2;
        stim_l4[50] = 64'h5D81F055487EC0E9;
        stim_l5[50] = 64'hF6C0F82AA43F6074;
        stim_l6[50] = 64'h7B607C15521FB03A;
        stim_l7[50] = 64'h3DB03E0AA90FD81D;
        gold[50] = 64'h356C0291A3B5D99C;
        // [51] lfsr_43
        stim_l0[51] = 64'hC6D81F055487EC0E;
        stim_l1[51] = 64'h636C0F82AA43F607;
        stim_l2[51] = 64'hE9B607C15521FB03;
        stim_l3[51] = 64'hACDB03E0AA90FD81;
        stim_l4[51] = 64'h8E6D81F055487EC0;
        stim_l5[51] = 64'h4736C0F82AA43F60;
        stim_l6[51] = 64'h239B607C15521FB0;
        stim_l7[51] = 64'h11CDB03E0AA90FD8;
        gold[51] = 64'hEA35454652E23520;
        // [52] lfsr_44
        stim_l0[52] = 64'h08E6D81F055487EC;
        stim_l1[52] = 64'h04736C0F82AA43F6;
        stim_l2[52] = 64'h0239B607C15521FB;
        stim_l3[52] = 64'hD91CDB03E0AA90FD;
        stim_l4[52] = 64'hB48E6D81F055487E;
        stim_l5[52] = 64'h5A4736C0F82AA43F;
        stim_l6[52] = 64'hF5239B607C15521F;
        stim_l7[52] = 64'hA291CDB03E0AA90F;
        gold[52] = 64'h24BA839F910640DE;
        // [53] lfsr_45
        stim_l0[53] = 64'h8948E6D81F055487;
        stim_l1[53] = 64'h9CA4736C0F82AA43;
        stim_l2[53] = 64'h965239B607C15521;
        stim_l3[53] = 64'h93291CDB03E0AA90;
        stim_l4[53] = 64'h49948E6D81F05548;
        stim_l5[53] = 64'h24CA4736C0F82AA4;
        stim_l6[53] = 64'h1265239B607C1552;
        stim_l7[53] = 64'h093291CDB03E0AA9;
        gold[53] = 64'hB9D4114F3BCDB260;
        // [54] lfsr_46
        stim_l0[54] = 64'hDC9948E6D81F0554;
        stim_l1[54] = 64'h6E4CA4736C0F82AA;
        stim_l2[54] = 64'h37265239B607C155;
        stim_l3[54] = 64'hC393291CDB03E0AA;
        stim_l4[54] = 64'h61C9948E6D81F055;
        stim_l5[54] = 64'hE8E4CA4736C0F82A;
        stim_l6[54] = 64'h747265239B607C15;
        stim_l7[54] = 64'hE2393291CDB03E0A;
        gold[54] = 64'h50D932AA1D9E9770;
        // [55] lfsr_47
        stim_l0[55] = 64'h711C9948E6D81F05;
        stim_l1[55] = 64'hE08E4CA4736C0F82;
        stim_l2[55] = 64'h7047265239B607C1;
        stim_l3[55] = 64'hE02393291CDB03E0;
        stim_l4[55] = 64'h7011C9948E6D81F0;
        stim_l5[55] = 64'h3808E4CA4736C0F8;
        stim_l6[55] = 64'h1C047265239B607C;
        stim_l7[55] = 64'h0E02393291CDB03E;
        gold[55] = 64'hE5E0385CD925A153;
        // [56] lfsr_48
        stim_l0[56] = 64'h07011C9948E6D81F;
        stim_l1[56] = 64'hDB808E4CA4736C0F;
        stim_l2[56] = 64'hB5C047265239B607;
        stim_l3[56] = 64'h82E02393291CDB03;
        stim_l4[56] = 64'h997011C9948E6D81;
        stim_l5[56] = 64'h94B808E4CA4736C0;
        stim_l6[56] = 64'h4A5C047265239B60;
        stim_l7[56] = 64'h252E02393291CDB0;
        gold[56] = 64'h40A4700EB5AA876C;
        // [57] lfsr_49
        stim_l0[57] = 64'h1297011C9948E6D8;
        stim_l1[57] = 64'h094B808E4CA4736C;
        stim_l2[57] = 64'h04A5C047265239B6;
        stim_l3[57] = 64'h0252E02393291CDB;
        stim_l4[57] = 64'hD9297011C9948E6D;
        stim_l5[57] = 64'hB494B808E4CA4736;
        stim_l6[57] = 64'h5A4A5C047265239B;
        stim_l7[57] = 64'hF5252E02393291CD;
        gold[57] = 64'h60B1C513BA2EB19A;
        // [58] lfsr_50
        stim_l0[58] = 64'hA29297011C9948E6;
        stim_l1[58] = 64'h51494B808E4CA473;
        stim_l2[58] = 64'hF0A4A5C047265239;
        stim_l3[58] = 64'hA05252E02393291C;
        stim_l4[58] = 64'h5029297011C9948E;
        stim_l5[58] = 64'h281494B808E4CA47;
        stim_l6[58] = 64'hCC0A4A5C04726523;
        stim_l7[58] = 64'hBE05252E02393291;
        gold[58] = 64'hDA214BF460304278;
        // [59] lfsr_51
        stim_l0[59] = 64'h87029297011C9948;
        stim_l1[59] = 64'h4381494B808E4CA4;
        stim_l2[59] = 64'h21C0A4A5C0472652;
        stim_l3[59] = 64'h10E05252E0239329;
        stim_l4[59] = 64'hD07029297011C994;
        stim_l5[59] = 64'h68381494B808E4CA;
        stim_l6[59] = 64'h341C0A4A5C047265;
        stim_l7[59] = 64'hC20E05252E023932;
        gold[59] = 64'h1BCBECD4B29E3116;
        // [60] lfsr_52
        stim_l0[60] = 64'h6107029297011C99;
        stim_l1[60] = 64'hE88381494B808E4C;
        stim_l2[60] = 64'h7441C0A4A5C04726;
        stim_l3[60] = 64'h3A20E05252E02393;
        stim_l4[60] = 64'hC5107029297011C9;
        stim_l5[60] = 64'hBA88381494B808E4;
        stim_l6[60] = 64'h5D441C0A4A5C0472;
        stim_l7[60] = 64'h2EA20E05252E0239;
        gold[60] = 64'h793A955248C12F17;
        // [61] lfsr_53
        stim_l0[61] = 64'hCF5107029297011C;
        stim_l1[61] = 64'h67A88381494B808E;
        stim_l2[61] = 64'h33D441C0A4A5C047;
        stim_l3[61] = 64'hC1EA20E05252E023;
        stim_l4[61] = 64'hB8F5107029297011;
        stim_l5[61] = 64'h847A88381494B808;
        stim_l6[61] = 64'h423D441C0A4A5C04;
        stim_l7[61] = 64'h211EA20E05252E02;
        gold[61] = 64'h13993F231C92805B;
        // [62] lfsr_54
        stim_l0[62] = 64'h108F510702929701;
        stim_l1[62] = 64'hD047A88381494B80;
        stim_l2[62] = 64'h6823D441C0A4A5C0;
        stim_l3[62] = 64'h3411EA20E05252E0;
        stim_l4[62] = 64'h1A08F51070292970;
        stim_l5[62] = 64'h0D047A88381494B8;
        stim_l6[62] = 64'h06823D441C0A4A5C;
        stim_l7[62] = 64'h03411EA20E05252E;
        gold[62] = 64'hE2A207149B58A920;
        // [63] lfsr_55
        stim_l0[63] = 64'h01A08F5107029297;
        stim_l1[63] = 64'hD8D047A88381494B;
        stim_l2[63] = 64'hB46823D441C0A4A5;
        stim_l3[63] = 64'h823411EA20E05252;
        stim_l4[63] = 64'h411A08F510702929;
        stim_l5[63] = 64'hF88D047A88381494;
        stim_l6[63] = 64'h7C46823D441C0A4A;
        stim_l7[63] = 64'h3E23411EA20E0525;
        gold[63] = 64'h19F29E3945655B84;
        // [64] lfsr_56
        stim_l0[64] = 64'hC711A08F51070292;
        stim_l1[64] = 64'h6388D047A8838149;
        stim_l2[64] = 64'hE9C46823D441C0A4;
        stim_l3[64] = 64'h74E23411EA20E052;
        stim_l4[64] = 64'h3A711A08F5107029;
        stim_l5[64] = 64'hC5388D047A883814;
        stim_l6[64] = 64'h629C46823D441C0A;
        stim_l7[64] = 64'h314E23411EA20E05;
        gold[64] = 64'h25E84738268B8CB0;
        // [65] lfsr_57
        stim_l0[65] = 64'hC0A711A08F510702;
        stim_l1[65] = 64'h605388D047A88381;
        stim_l2[65] = 64'hE829C46823D441C0;
        stim_l3[65] = 64'h7414E23411EA20E0;
        stim_l4[65] = 64'h3A0A711A08F51070;
        stim_l5[65] = 64'h1D05388D047A8838;
        stim_l6[65] = 64'h0E829C46823D441C;
        stim_l7[65] = 64'h07414E23411EA20E;
        gold[65] = 64'h26F5D3944FCDC6FD;
        // [66] lfsr_58
        stim_l0[66] = 64'h03A0A711A08F5107;
        stim_l1[66] = 64'hD9D05388D047A883;
        stim_l2[66] = 64'hB4E829C46823D441;
        stim_l3[66] = 64'h827414E23411EA20;
        stim_l4[66] = 64'h413A0A711A08F510;
        stim_l5[66] = 64'h209D05388D047A88;
        stim_l6[66] = 64'h104E829C46823D44;
        stim_l7[66] = 64'h0827414E23411EA2;
        gold[66] = 64'hFAD74CEEC255525D;
        // [67] lfsr_59
        stim_l0[67] = 64'h0413A0A711A08F51;
        stim_l1[67] = 64'hDA09D05388D047A8;
        stim_l2[67] = 64'h6D04E829C46823D4;
        stim_l3[67] = 64'h36827414E23411EA;
        stim_l4[67] = 64'h1B413A0A711A08F5;
        stim_l5[67] = 64'hD5A09D05388D047A;
        stim_l6[67] = 64'h6AD04E829C46823D;
        stim_l7[67] = 64'hED6827414E23411E;
        gold[67] = 64'hC2EB840C5A90D40F;
        // [68] lfsr_60
        stim_l0[68] = 64'h76B413A0A711A08F;
        stim_l1[68] = 64'hE35A09D05388D047;
        stim_l2[68] = 64'hA9AD04E829C46823;
        stim_l3[68] = 64'h8CD6827414E23411;
        stim_l4[68] = 64'h9E6B413A0A711A08;
        stim_l5[68] = 64'h4F35A09D05388D04;
        stim_l6[68] = 64'h279AD04E829C4682;
        stim_l7[68] = 64'h13CD6827414E2341;
        gold[68] = 64'hEF121B34B952BD4E;
        // [69] lfsr_61
        stim_l0[69] = 64'hD1E6B413A0A711A0;
        stim_l1[69] = 64'h68F35A09D05388D0;
        stim_l2[69] = 64'h3479AD04E829C468;
        stim_l3[69] = 64'h1A3CD6827414E234;
        stim_l4[69] = 64'h0D1E6B413A0A711A;
        stim_l5[69] = 64'h068F35A09D05388D;
        stim_l6[69] = 64'hDB479AD04E829C46;
        stim_l7[69] = 64'h6DA3CD6827414E23;
        gold[69] = 64'h6C1F69A796C197C9;
        // [70] lfsr_62
        stim_l0[70] = 64'hEED1E6B413A0A711;
        stim_l1[70] = 64'hAF68F35A09D05388;
        stim_l2[70] = 64'h57B479AD04E829C4;
        stim_l3[70] = 64'h2BDA3CD6827414E2;
        stim_l4[70] = 64'h15ED1E6B413A0A71;
        stim_l5[70] = 64'hD2F68F35A09D0538;
        stim_l6[70] = 64'h697B479AD04E829C;
        stim_l7[70] = 64'h34BDA3CD6827414E;
        gold[70] = 64'hEA8DF843DE2E66F7;
        // [71] lfsr_63
        stim_l0[71] = 64'h1A5ED1E6B413A0A7;
        stim_l1[71] = 64'hD52F68F35A09D053;
        stim_l2[71] = 64'hB297B479AD04E829;
        stim_l3[71] = 64'h814BDA3CD6827414;
        stim_l4[71] = 64'h40A5ED1E6B413A0A;
        stim_l5[71] = 64'h2052F68F35A09D05;
        stim_l6[71] = 64'hC8297B479AD04E82;
        stim_l7[71] = 64'h6414BDA3CD682741;
        gold[71] = 64'h0EAADA36E528F8DE;
        // [72] lfsr_64
        stim_l0[72] = 64'hEA0A5ED1E6B413A0;
        stim_l1[72] = 64'h75052F68F35A09D0;
        stim_l2[72] = 64'h3A8297B479AD04E8;
        stim_l3[72] = 64'h1D414BDA3CD68274;
        stim_l4[72] = 64'h0EA0A5ED1E6B413A;
        stim_l5[72] = 64'h075052F68F35A09D;
        stim_l6[72] = 64'hDBA8297B479AD04E;
        stim_l7[72] = 64'h6DD414BDA3CD6827;
        gold[72] = 64'h9EFEA77A9B12B704;
        // [73] lfsr_65
        stim_l0[73] = 64'hEEEA0A5ED1E6B413;
        stim_l1[73] = 64'hAF75052F68F35A09;
        stim_l2[73] = 64'h8FBA8297B479AD04;
        stim_l3[73] = 64'h47DD414BDA3CD682;
        stim_l4[73] = 64'h23EEA0A5ED1E6B41;
        stim_l5[73] = 64'hC9F75052F68F35A0;
        stim_l6[73] = 64'h64FBA8297B479AD0;
        stim_l7[73] = 64'h327DD414BDA3CD68;
        gold[73] = 64'h7A3EA68DE57E0662;
        // [74] lfsr_66
        stim_l0[74] = 64'h193EEA0A5ED1E6B4;
        stim_l1[74] = 64'h0C9F75052F68F35A;
        stim_l2[74] = 64'h064FBA8297B479AD;
        stim_l3[74] = 64'hDB27DD414BDA3CD6;
        stim_l4[74] = 64'h6D93EEA0A5ED1E6B;
        stim_l5[74] = 64'hEEC9F75052F68F35;
        stim_l6[74] = 64'hAF64FBA8297B479A;
        stim_l7[74] = 64'h57B27DD414BDA3CD;
        gold[74] = 64'h6C4BEE72412A5BED;
        // [75] lfsr_67
        stim_l0[75] = 64'hF3D93EEA0A5ED1E6;
        stim_l1[75] = 64'h79EC9F75052F68F3;
        stim_l2[75] = 64'hE4F64FBA8297B479;
        stim_l3[75] = 64'hAA7B27DD414BDA3C;
        stim_l4[75] = 64'h553D93EEA0A5ED1E;
        stim_l5[75] = 64'h2A9EC9F75052F68F;
        stim_l6[75] = 64'hCD4F64FBA8297B47;
        stim_l7[75] = 64'hBEA7B27DD414BDA3;
        gold[75] = 64'h38ED10E8A53D9A98;
        // [76] lfsr_68
        stim_l0[76] = 64'h8753D93EEA0A5ED1;
        stim_l1[76] = 64'h9BA9EC9F75052F68;
        stim_l2[76] = 64'h4DD4F64FBA8297B4;
        stim_l3[76] = 64'h26EA7B27DD414BDA;
        stim_l4[76] = 64'h13753D93EEA0A5ED;
        stim_l5[76] = 64'hD1BA9EC9F75052F6;
        stim_l6[76] = 64'h68DD4F64FBA8297B;
        stim_l7[76] = 64'hEC6EA7B27DD414BD;
        gold[76] = 64'h7288BFEBF573E5E4;
        // [77] lfsr_69
        stim_l0[77] = 64'hAE3753D93EEA0A5E;
        stim_l1[77] = 64'h571BA9EC9F75052F;
        stim_l2[77] = 64'hF38DD4F64FBA8297;
        stim_l3[77] = 64'hA1C6EA7B27DD414B;
        stim_l4[77] = 64'h88E3753D93EEA0A5;
        stim_l5[77] = 64'h9C71BA9EC9F75052;
        stim_l6[77] = 64'h4E38DD4F64FBA829;
        stim_l7[77] = 64'hFF1C6EA7B27DD414;
        gold[77] = 64'h63529644E43E8CA9;
        // [78] lfsr_70
        stim_l0[78] = 64'h7F8E3753D93EEA0A;
        stim_l1[78] = 64'h3FC71BA9EC9F7505;
        stim_l2[78] = 64'hC7E38DD4F64FBA82;
        stim_l3[78] = 64'h63F1C6EA7B27DD41;
        stim_l4[78] = 64'hE9F8E3753D93EEA0;
        stim_l5[78] = 64'h74FC71BA9EC9F750;
        stim_l6[78] = 64'h3A7E38DD4F64FBA8;
        stim_l7[78] = 64'h1D3F1C6EA7B27DD4;
        gold[78] = 64'h0033B03CB569D1BD;
        // [79] lfsr_71
        stim_l0[79] = 64'h0E9F8E3753D93EEA;
        stim_l1[79] = 64'h074FC71BA9EC9F75;
        stim_l2[79] = 64'hDBA7E38DD4F64FBA;
        stim_l3[79] = 64'h6DD3F1C6EA7B27DD;
        stim_l4[79] = 64'hEEE9F8E3753D93EE;
        stim_l5[79] = 64'h7774FC71BA9EC9F7;
        stim_l6[79] = 64'hE3BA7E38DD4F64FB;
        stim_l7[79] = 64'hA9DD3F1C6EA7B27D;
        gold[79] = 64'h21C088EEC15AB0D6;
        // [80] lfsr_72
        stim_l0[80] = 64'h8CEE9F8E3753D93E;
        stim_l1[80] = 64'h46774FC71BA9EC9F;
        stim_l2[80] = 64'hFB3BA7E38DD4F64F;
        stim_l3[80] = 64'hA59DD3F1C6EA7B27;
        stim_l4[80] = 64'h8ACEE9F8E3753D93;
        stim_l5[80] = 64'h9D6774FC71BA9EC9;
        stim_l6[80] = 64'h96B3BA7E38DD4F64;
        stim_l7[80] = 64'h4B59DD3F1C6EA7B2;
        gold[80] = 64'hF5B1230B7E7ED3D6;
        // [81] lfsr_73
        stim_l0[81] = 64'h25ACEE9F8E3753D9;
        stim_l1[81] = 64'hCAD6774FC71BA9EC;
        stim_l2[81] = 64'h656B3BA7E38DD4F6;
        stim_l3[81] = 64'h32B59DD3F1C6EA7B;
        stim_l4[81] = 64'hC15ACEE9F8E3753D;
        stim_l5[81] = 64'hB8AD6774FC71BA9E;
        stim_l6[81] = 64'h5C56B3BA7E38DD4F;
        stim_l7[81] = 64'hF62B59DD3F1C6EA7;
        gold[81] = 64'h32C501AF9709A9A9;
        // [82] lfsr_74
        stim_l0[82] = 64'hA315ACEE9F8E3753;
        stim_l1[82] = 64'h898AD6774FC71BA9;
        stim_l2[82] = 64'h9CC56B3BA7E38DD4;
        stim_l3[82] = 64'h4E62B59DD3F1C6EA;
        stim_l4[82] = 64'h27315ACEE9F8E375;
        stim_l5[82] = 64'hCB98AD6774FC71BA;
        stim_l6[82] = 64'h65CC56B3BA7E38DD;
        stim_l7[82] = 64'hEAE62B59DD3F1C6E;
        gold[82] = 64'h492360536BB409B8;
        // [83] lfsr_75
        stim_l0[83] = 64'h757315ACEE9F8E37;
        stim_l1[83] = 64'hE2B98AD6774FC71B;
        stim_l2[83] = 64'hA95CC56B3BA7E38D;
        stim_l3[83] = 64'h8CAE62B59DD3F1C6;
        stim_l4[83] = 64'h4657315ACEE9F8E3;
        stim_l5[83] = 64'hFB2B98AD6774FC71;
        stim_l6[83] = 64'hA595CC56B3BA7E38;
        stim_l7[83] = 64'h52CAE62B59DD3F1C;
        gold[83] = 64'h8508284B0121DCBF;
        // [84] lfsr_76
        stim_l0[84] = 64'h29657315ACEE9F8E;
        stim_l1[84] = 64'h14B2B98AD6774FC7;
        stim_l2[84] = 64'hD2595CC56B3BA7E3;
        stim_l3[84] = 64'hB12CAE62B59DD3F1;
        stim_l4[84] = 64'h809657315ACEE9F8;
        stim_l5[84] = 64'h404B2B98AD6774FC;
        stim_l6[84] = 64'h202595CC56B3BA7E;
        stim_l7[84] = 64'h1012CAE62B59DD3F;
        gold[84] = 64'h44B4FBE74A7CDAB5;
        // [85] lfsr_77
        stim_l0[85] = 64'hD009657315ACEE9F;
        stim_l1[85] = 64'hB004B2B98AD6774F;
        stim_l2[85] = 64'h8002595CC56B3BA7;
        stim_l3[85] = 64'h98012CAE62B59DD3;
        stim_l4[85] = 64'h94009657315ACEE9;
        stim_l5[85] = 64'h92004B2B98AD6774;
        stim_l6[85] = 64'h49002595CC56B3BA;
        stim_l7[85] = 64'h248012CAE62B59DD;
        gold[85] = 64'h4FA48F376C8A6312;
        // [86] lfsr_78
        stim_l0[86] = 64'hCA4009657315ACEE;
        stim_l1[86] = 64'h652004B2B98AD677;
        stim_l2[86] = 64'hEA9002595CC56B3B;
        stim_l3[86] = 64'hAD48012CAE62B59D;
        stim_l4[86] = 64'h8EA4009657315ACE;
        stim_l5[86] = 64'h4752004B2B98AD67;
        stim_l6[86] = 64'hFBA9002595CC56B3;
        stim_l7[86] = 64'hA5D48012CAE62B59;
        gold[86] = 64'h842F2C3DA033F9EF;
        // [87] lfsr_79
        stim_l0[87] = 64'h8AEA4009657315AC;
        stim_l1[87] = 64'h45752004B2B98AD6;
        stim_l2[87] = 64'h22BA9002595CC56B;
        stim_l3[87] = 64'hC95D48012CAE62B5;
        stim_l4[87] = 64'hBCAEA4009657315A;
        stim_l5[87] = 64'h5E5752004B2B98AD;
        stim_l6[87] = 64'hF72BA9002595CC56;
        stim_l7[87] = 64'h7B95D48012CAE62B;
        gold[87] = 64'hA404FF0CBB87ADBB;
    end

    // ----------------------------------------------------------------
    // Main stimulus + checker
    // ----------------------------------------------------------------
    initial begin
        rst_n      = 0;
        die0       = 0; die1 = 0; die2 = 0; die3 = 0;
        die4       = 0; die5 = 0; die6 = 0; die7 = 0;
        dies_valid = 0;
        pass_cnt   = 0;
        fail_cnt   = 0;

        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // ---- Drive all 88 test vectors, one per cycle ----
        for (i = 0; i < 88; i = i + 1) begin
            die0       = stim_l0[i];
            die1       = stim_l1[i];
            die2       = stim_l2[i];
            die3       = stim_l3[i];
            die4       = stim_l4[i];
            die5       = stim_l5[i];
            die6       = stim_l6[i];
            die7       = stim_l7[i];
            dies_valid = 1;
            @(posedge clk); #1;
        end

        // Drain pipeline: 3 extra cycles for latency (3 pipeline regs)
        dies_valid = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;  // safety margin

        // Report
        $display("");
        $display("=== multi_die_reducer sim results ===");
        $display("  Total tests : 88");
        $display("  PASS        : %0d", pass_cnt);
        $display("  FAIL        : %0d", fail_cnt);
        if (fail_cnt == 0 && pass_cnt == 88) begin
            $display("MULTI_DIE_REDUCER_GREEN");
            $display("Hash combiner: 3-round XOR+rotate (R1=5, R2=11, R3=22)");
            $display("Topology: 3-stage 8->4->2->1 merkle with 2 pipeline regs + output reg");
            $display("Byte-match: super_root matches Python golden ref byte-for-byte.");
        end else begin
            $display("MULTI_DIE_REDUCER_FAIL — %0d failures", fail_cnt);
        end
        $finish;
    end

    // ----------------------------------------------------------------
    // Output checker — fires on every super_root_valid assertion
    // ----------------------------------------------------------------
    initial chk_idx = 0;

    always @(posedge clk) begin
        if (super_root_valid && rst_n) begin
            if (super_root === gold[chk_idx]) begin
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL [%0d]: super_root=64'h%016h  expected=64'h%016h",
                         chk_idx, super_root, gold[chk_idx]);
                fail_cnt = fail_cnt + 1;
            end
            chk_idx = chk_idx + 1;
        end
    end

    // ----------------------------------------------------------------
    // Timeout watchdog
    // ----------------------------------------------------------------
    initial begin
        #50000;
        $display("TIMEOUT — simulation did not finish");
        $finish;
    end

endmodule
`default_nettype wire
