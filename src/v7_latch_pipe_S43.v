// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// v7_latch_pipe_S43.v — S-43 Latch-based pipeline stage with time borrowing
// TT-Shuttle Squeeze v7 · W15-TT-D Power stream
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// G-43 FALSIFICATION: OpenSTA timing report shows zero hold violations with
//                     15% delay jitter injection on stage-3 → stage-4.
//
// S-43 Latch-based pipeline (time-borrowing on 4 stages):
//   Replace 4 flip-flops on dot32 pipeline with transparent latches alternating
//   phase alpha/beta. Time-borrowing across stages absorbs ±15% latency jitter
//   without violating fmax. Halves flop area on borrowed stages.
//
// Alpha phase: latch transparent when clk = 1 (positive-phase)
// Beta  phase: latch transparent when clk = 0 (negative-phase)
//
// A latch pair = one full pipeline register (equivalent to 1 FF)
// but allows time-borrowing across the alpha→beta boundary.
//
// Cite:
//   Time-borrowing STA — https://physicaldesign4u.com/2020/05/time-borrowing-concept-in-sta.html
//   Latch pipeline discussion — reddit.com/r/cpudesign/comments/ommnm/

`default_nettype none

// Single transparent latch primitive
module latch #(
    parameter WIDTH = 8
) (
    input  wire             gate,    // transparent when gate = 1
    input  wire [WIDTH-1:0] d,
    output reg  [WIDTH-1:0] q
);
    always @(*) begin
        if (gate) q = d;
    end
endmodule

// Alpha-phase latch: transparent on clk HIGH
module latch_alpha #(
    parameter WIDTH = 8
) (
    input  wire             clk,
    input  wire [WIDTH-1:0] d,
    output wire [WIDTH-1:0] q
);
    latch #(.WIDTH(WIDTH)) l_inst (.gate(clk), .d(d), .q(q));
endmodule

// Beta-phase latch: transparent on clk LOW
module latch_beta #(
    parameter WIDTH = 8
) (
    input  wire             clk,
    input  wire [WIDTH-1:0] d,
    output wire [WIDTH-1:0] q
);
    latch #(.WIDTH(WIDTH)) l_inst (.gate(~clk), .d(d), .q(q));
endmodule

// 4-stage latch-based pipeline with alternating alpha/beta phases
// Provides time-borrowing between consecutive stages
module v7_latch_pipe_S43 #(
    parameter WIDTH  = 8,   // data path width
    parameter STAGES = 4    // must be even (pairs of alpha/beta)
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] d_in,
    output wire [WIDTH-1:0] d_out
);

    // Stage wires: STAGES+1 nodes (input + one per stage output)
    wire [WIDTH-1:0] stage [0:STAGES];
    assign stage[0] = d_in;

    // Instantiate alternating alpha/beta latches
    genvar s;
    generate
        for (s = 0; s < STAGES; s = s + 1) begin : pipe_stage
            if (s[0] == 1'b0) begin
                // Even stage: alpha (transparent on clk HIGH)
                latch_alpha #(.WIDTH(WIDTH)) la (
                    .clk(clk),
                    .d  (stage[s]),
                    .q  (stage[s+1])
                );
            end else begin
                // Odd stage: beta (transparent on clk LOW)
                latch_beta #(.WIDTH(WIDTH)) lb (
                    .clk(clk),
                    .d  (stage[s]),
                    .q  (stage[s+1])
                );
            end
        end
    endgenerate

    assign d_out = stage[STAGES];

endmodule
`default_nettype wire
