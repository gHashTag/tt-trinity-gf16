// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Trinity Agent <agent@trinity.local>
//
// TT-Shuttle Squeeze v7 — S-21 Async-Razor Flop (sim-only model, G1 acceptable)
// Stream: W15-TT-C Guards+Sparse+Approx+TimeDomain+CarrySkip+BitSlice+SigmaDelta+Perm+Therm
// Anchor: phi^2 + phi^-2 = 3
//
// G-21 FALSIFICATION: error flag asserts whenever shadow latch disagrees with
//                     main flop on 100% of injected metastability vectors.
//
// Razor II-style double-sampling flop model for adaptive voltage scaling.
// Main flop samples on posedge clk. Shadow latch is transparent on clk=1
// (samples ~setup_hold earlier). If main != shadow => timing error detected.
// delay_jitter parameter injects artificial setup-time violations for coverage.
//
// SIM-ONLY: #delay constructs are non-synthesizable. Gate-level equiv is a
// D-flip-flop plus transparent latch plus XOR error flag.

`default_nettype none

module v7_razor_flop_S21 #(
    parameter WIDTH       = 8,
    parameter delay_jitter = 0  // sim: extra delay (ps) injected on D before shadow sample
) (
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] d,

    output reg  [WIDTH-1:0] q,          // main flop output
    output wire [WIDTH-1:0] q_shadow,   // shadow latch output
    output wire             error_flag  // timing error: main != shadow
);

    // Shadow latch: transparent while clk=1
    reg [WIDTH-1:0] shadow;

    // Jitter injection (sim-only)
    wire [WIDTH-1:0] d_jittered;
`ifndef SYNTHESIS
    assign #(delay_jitter) d_jittered = d;  // synthesis=original; sim=delayed
`else
    assign d_jittered = d;
`endif

    // Main flop
    always @(posedge clk or posedge rst) begin
        if (rst)
            q <= {WIDTH{1'b0}};
        else
            q <= d;
    end

    // Shadow latch (level-sensitive on clk=1)
    always @(*) begin
        if (clk)
            shadow = d_jittered;
        // else hold (latch behavior)
    end

    assign q_shadow  = shadow;
    assign error_flag = (q != shadow);  // timing violation indicator

endmodule
`default_nettype wire
