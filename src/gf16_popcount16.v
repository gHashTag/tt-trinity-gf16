`default_nettype none
// gf16_popcount16.v — 3-stage pipelined XOR-popcount for 16-element ternary dot product
// Apache-2.0
//
// L-S19: Variant of gf16_popcount for N_ELEMS=16 (used by vsa_matmul_16x16).
//        LATENCY = 3 cycles. Fmax target: 150 MHz.
//        valid_out arrives 3 clock edges after valid_in.
//
// L-Z05: Stage 2 adder tree replaced with wallace_popcount_16 (Wallace tree).
//        16 1-bit inputs → 5-bit count in ~6 XOR stages (vs ~8 XOR for RCA tree).
//        Reduces critical path, enabling higher Fmax → +6 TOPS/W.
//        Cell budget: ~120 cells (vs ~150 for RCA tree).
//
// ANCHOR: φ²+φ⁻²=3 · DOI 10.5281/zenodo.19227877 · Apache-2.0 · EPIC gHashTag/trinity-fpga#51
//
// Pipeline stages:
//   Stage 1: Decode 16 element pairs → same[15:0], diff[15:0]; register + valid
//   Stage 2: Wallace popcount (16→5 bits) via wallace_popcount_16; register + valid
//   Stage 3: Final subtraction → signed 8-bit result; register + valid_out
//
// Parameters:
//   N_ELEMS = 16
//   LATENCY = 3

module gf16_popcount16 #(
    parameter N_ELEMS = 16,
    parameter LATENCY = 3
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [31:0] a_row,     // 16 elements × 2 bits
    input  wire [31:0] b_row,     // 16 elements × 2 bits
    output reg         valid_out,
    output reg  [7:0]  result
);

    // -------------------------------------------------------------------
    // Stage 1: combinational decode, register
    // -------------------------------------------------------------------
    wire [15:0] s1_same_comb;
    wire [15:0] s1_diff_comb;

    genvar k;
    generate
        for (k = 0; k < 16; k = k + 1) begin : gen_decode
            wire [1:0] ae = a_row[2*k +: 2];
            wire [1:0] be = b_row[2*k +: 2];
            wire active = ~ae[1] & ~be[1];
            assign s1_same_comb[k] = active & ~(ae[0] ^ be[0]);
            assign s1_diff_comb[k] = active &  (ae[0] ^ be[0]);
        end
    endgenerate

    (* keep = "true" *) (* no_retiming = "true" *) reg [15:0] s1_same, s1_diff;
    (* keep = "true" *) (* no_retiming = "true" *) reg        s1_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_same  <= 16'b0;
            s1_diff  <= 16'b0;
            s1_valid <= 1'b0;
        end else begin
            s1_same  <= s1_same_comb;
            s1_diff  <= s1_diff_comb;
            s1_valid <= valid_in;
        end
    end

    // -------------------------------------------------------------------
    // Stage 2: Wallace tree popcount — L-Z05 replacement for RCA adder tree
    // wallace_popcount_16: 16 1-bit inputs → 5-bit count, ~6 XOR stages
    // -------------------------------------------------------------------
    wire [4:0] cnt_pos_comb;
    wire [4:0] cnt_neg_comb;

    wallace_popcount_16 u_wpc_pos (
        .in  (s1_same),
        .out (cnt_pos_comb)
    );

    wallace_popcount_16 u_wpc_neg (
        .in  (s1_diff),
        .out (cnt_neg_comb)
    );

    (* keep = "true" *) (* no_retiming = "true" *) reg [4:0] s2_cnt_pos, s2_cnt_neg;
    (* keep = "true" *) (* no_retiming = "true" *) reg       s2_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_cnt_pos <= 5'b0;
            s2_cnt_neg <= 5'b0;
            s2_valid   <= 1'b0;
        end else begin
            s2_cnt_pos <= cnt_pos_comb;
            s2_cnt_neg <= cnt_neg_comb;
            s2_valid   <= s1_valid;
        end
    end

    // -------------------------------------------------------------------
    // Stage 3: final subtraction
    // result ∈ [-16..+16], needs 6 bits signed; sign-extend to 8 bits
    // -------------------------------------------------------------------
    wire signed [5:0] sub_comb = {1'b0, s2_cnt_pos} - {1'b0, s2_cnt_neg};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result    <= 8'b0;
            valid_out <= 1'b0;
        end else begin
            result    <= {{2{sub_comb[5]}}, sub_comb};
            valid_out <= s2_valid;
        end
    end

endmodule
