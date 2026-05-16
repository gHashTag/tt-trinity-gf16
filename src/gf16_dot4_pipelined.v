// gf16_dot4_pipelined.v
// Lane L-S31: Pipeline register inserted after multiply stage
// to balance the multiply->accumulate critical path.
//
// Original (combinational):  mul + add + add + add  ~25ns  →  ~25MHz
// Pipelined (2 stages):
//   Stage 1:  mul × 4                               ~12ns
//   Stage 2:  add + add + add                       ~13ns
//   → enables 35MHz operation, WNS improvement +13ns
//
// Interface change: added clk port; output is valid 1 cycle after inputs.
// Cell overhead: 4 × 16-bit registers = 4×16 = 64 FFs (~50 extra cells).
//
// Constraints: pure Verilog-2005, R-SI-1 (no arithmetic * at this level).
`default_nettype none

module gf16_dot4_pipelined (
    input  wire        clk,
    input  wire [15:0] a0,
    input  wire [15:0] a1,
    input  wire [15:0] a2,
    input  wire [15:0] a3,
    input  wire [15:0] b0,
    input  wire [15:0] b1,
    input  wire [15:0] b2,
    input  wire [15:0] b3,
    output wire [15:0] result
);

    // ---------------------------------------------------------------
    // Stage 1 combinational: four parallel GF16 multiplies
    // ---------------------------------------------------------------
    wire [15:0] p0_comb;
    wire [15:0] p1_comb;
    wire [15:0] p2_comb;
    wire [15:0] p3_comb;

    gf16_mul m0 (.a(a0), .b(b0), .result(p0_comb));
    gf16_mul m1 (.a(a1), .b(b1), .result(p1_comb));
    gf16_mul m2 (.a(a2), .b(b2), .result(p2_comb));
    gf16_mul m3 (.a(a3), .b(b3), .result(p3_comb));

    // ---------------------------------------------------------------
    // Pipeline register: capture multiply results at end of Stage 1
    // This is the inserted retiming register that splits the 25ns path.
    // ---------------------------------------------------------------
    reg [15:0] p0_r;
    reg [15:0] p1_r;
    reg [15:0] p2_r;
    reg [15:0] p3_r;

    always @(posedge clk) begin
        p0_r <= p0_comb;
        p1_r <= p1_comb;
        p2_r <= p2_comb;
        p3_r <= p3_comb;
    end

    // ---------------------------------------------------------------
    // Stage 2 combinational: accumulate (add tree)
    // ---------------------------------------------------------------
    wire [15:0] s01;
    wire [15:0] s23;

    gf16_add a01    (.a(p0_r),  .b(p1_r),  .result(s01));
    gf16_add a23    (.a(p2_r),  .b(p3_r),  .result(s23));
    gf16_add a_final(.a(s01),   .b(s23),   .result(result));

endmodule
`default_nettype wire
