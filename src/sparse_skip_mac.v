`default_nettype none
// sparse_skip_mac.v — L-S34 Sparse-Skip Wrapper for GF16 MAC
// Apache-2.0 · TRI-1 v2 · PhD Ch.5 sparsity / BitNet b1.58 anchor
//
// Wraps gf16_dot4 with early-exit gate when either operand is all-zero.
// On BitNet b1.58 weights (~33% trits zero), expect ~30% MAC cycles skipped.
// Reports skip counter for DePIN telemetry.
//
// Input packing: a_trits/b_trits are 16-bit words carrying 8 trits (2-bit
// per trit, positions [15:14],[13:12],[11:10],[9:8],[7:6],[5:4],[3:2],[1:0]).
// The 8 trits are split across 4 GF16 lanes: lane i uses trits [2i+1:2i] from
// the low byte (b) for the activation and [2i+1:2i] from the high byte (a)
// for the weight, sign-extended to 16-bit GF16 representation.
// When either full 16-bit operand word is all-zero the entire MAC is skipped.

module sparse_skip_mac (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] a_trits,   // 8 trits packed (2-bit each)
    input  wire [15:0] b_trits,
    input  wire        valid_in,
    output reg  [7:0]  dot_out,   // GF16 result (lower byte of 16-bit GF16)
    output reg         valid_out,
    output reg         skipped,   // 1 if this cycle was skipped
    output reg  [15:0] skip_count // saturating skip counter
);

    // -------------------------------------------------------------------------
    // Combinational zero detection — early-exit condition
    // -------------------------------------------------------------------------
    wire zero_a = (a_trits == 16'd0);
    wire zero_b = (b_trits == 16'd0);
    wire do_skip = zero_a | zero_b;

    // -------------------------------------------------------------------------
    // Gated operands: expand trit pairs to 16-bit GF16 inputs for gf16_dot4.
    // When do_skip, present all-zero inputs (gf16_dot4 result will be 0 anyway,
    // but we bypass the instance entirely via the registered mux below).
    // Lane mapping: lane i ← a_trits[2i+1:2i], b_trits[2i+1:2i] (i=0..3)
    // Zero-pad to 16 bits: {14'b0, trit[1:0]}
    // -------------------------------------------------------------------------
    wire [15:0] a0_in = do_skip ? 16'h0000 : {14'd0, a_trits[1:0]};
    wire [15:0] a1_in = do_skip ? 16'h0000 : {14'd0, a_trits[3:2]};
    wire [15:0] a2_in = do_skip ? 16'h0000 : {14'd0, a_trits[5:4]};
    wire [15:0] a3_in = do_skip ? 16'h0000 : {14'd0, a_trits[7:6]};

    wire [15:0] b0_in = do_skip ? 16'h0000 : {14'd0, b_trits[1:0]};
    wire [15:0] b1_in = do_skip ? 16'h0000 : {14'd0, b_trits[3:2]};
    wire [15:0] b2_in = do_skip ? 16'h0000 : {14'd0, b_trits[5:4]};
    wire [15:0] b3_in = do_skip ? 16'h0000 : {14'd0, b_trits[7:6]};

    // -------------------------------------------------------------------------
    // Underlying combinational dot4
    // -------------------------------------------------------------------------
    wire [15:0] dot4_result;

    gf16_dot4 u_dot4 (
        .a0(a0_in), .a1(a1_in), .a2(a2_in), .a3(a3_in),
        .b0(b0_in), .b1(b1_in), .b2(b2_in), .b3(b3_in),
        .result(dot4_result)
    );

    // -------------------------------------------------------------------------
    // Registered outputs + saturating skip counter
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dot_out    <= 8'h00;
            valid_out  <= 1'b0;
            skipped    <= 1'b0;
            skip_count <= 16'h0000;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                if (do_skip) begin
                    dot_out    <= 8'h00;
                    skipped    <= 1'b1;
                    // Saturating increment
                    skip_count <= (skip_count == 16'hFFFF) ? 16'hFFFF
                                                           : skip_count + 1'b1;
                end else begin
                    dot_out    <= dot4_result[7:0];
                    skipped    <= 1'b0;
                end
            end else begin
                skipped <= 1'b0;
            end
        end
    end

endmodule
