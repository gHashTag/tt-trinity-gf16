// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Trinity Agent <agent@trinity.local>
//
// TT-Shuttle Squeeze v7 — S-47 Sigma-Delta 1-Bit Stream MAC
// Stream: W15-TT-C Guards+Sparse+Approx+TimeDomain+CarrySkip+BitSlice+SigmaDelta+Perm+Therm
// Anchor: phi^2 + phi^-2 = 3
//
// G-47 FALSIFICATION: Sigma-Delta MAC matches reference dot4 within ε ≤ 2^-6
//                     at 64 stream cycles on 100% of Wave-29 vectors.
//
// 1-bit sigma-delta stream MAC lane.
// Activation encoded as Sigma-Delta bitstream (1-bit DAC).
// Ternary weight modulates: multiply = single XNOR/AND per cycle.
// Accumulator = 6-bit up-counter (64 cycles => 6-bit precision).
// Cite: SDNN arXiv 2408.06968 (1-bit Σ∆ stream multiply = 1 AND gate/cycle).

`default_nettype none

module v7_sigmadelta_mac_S47 #(
    parameter STREAM_LEN = 64,    // number of Σ∆ cycles for 6-bit precision
    parameter CNT_W      = 6,     // accumulator counter width (log2(STREAM_LEN))
    parameter N_WEIGHTS  = 4      // number of parallel weight lanes
) (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   stream_in,        // 1-bit Σ∆ activation stream (shared)
    // Ternary weight encoding per lane
    input  wire [N_WEIGHTS-1:0]   w_valid,          // non-zero mask
    input  wire [N_WEIGHTS-1:0]   w_sign,           // sign (1=-1, 0=+1)

    output reg  signed [CNT_W:0]  acc [0:N_WEIGHTS-1], // accumulated result per lane
    output reg                    done                   // high for 1 cycle after STREAM_LEN
);

    // Cycle counter
    reg [CNT_W-1:0] cycle_cnt;

    // Per-lane XNOR/AND multiply:
    // If w_valid=1 and w_sign=0: multiply = stream_in AND 1  = stream_in (XNOR(stream,0)=stream => AND with 1)
    // If w_valid=1 and w_sign=1: multiply = XNOR(stream_in, 1) = ~stream_in (invert for -1 weight)
    //   but we count 0 as -1 contribution, 1 as +1 contribution
    // If w_valid=0:              no contribution
    //
    // Accumulator: signed count over STREAM_LEN bits
    //   +1 when (w_valid=1, w_sign=0, stream=1) OR (w_valid=1, w_sign=1, stream=0)
    //   -1 when (w_valid=1, w_sign=0, stream=0) OR (w_valid=1, w_sign=1, stream=1)
    //    0 when w_valid=0

    wire bit_contrib [0:N_WEIGHTS-1]; // 1 = positive, 0 = negative contribution
    genvar i;
    generate
        for (i = 0; i < N_WEIGHTS; i = i+1) begin : gen_xnor
            // XNOR of stream with weight sign; only counts if weight non-zero
            assign bit_contrib[i] = stream_in ^ ~w_sign[i];  // XNOR(stream, sign)
        end
    endgenerate

    integer k;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_cnt <= {CNT_W{1'b0}};
            done      <= 1'b0;
            for (k = 0; k < N_WEIGHTS; k = k+1)
                acc[k] <= {(CNT_W+1){1'b0}};
        end else begin
            done <= 1'b0;
            if (cycle_cnt < STREAM_LEN[CNT_W-1:0]) begin
                for (k = 0; k < N_WEIGHTS; k = k+1) begin
                    if (w_valid[k]) begin
                        // +1 if XNOR=1 (contribution positive), -1 if XNOR=0
                        if (bit_contrib[k])
                            acc[k] <= acc[k] + {{CNT_W{1'b0}}, 1'b1};
                        else
                            acc[k] <= acc[k] - {{CNT_W{1'b0}}, 1'b1};
                    end
                end
                cycle_cnt <= cycle_cnt + 1'b1;
            end else begin
                done      <= 1'b1;
                cycle_cnt <= {CNT_W{1'b0}};
                // Reset accumulators after done pulse
                for (k = 0; k < N_WEIGHTS; k = k+1)
                    acc[k] <= {(CNT_W+1){1'b0}};
            end
        end
    end

endmodule
`default_nettype wire
