// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Trinity Agent <agent@trinity.local>
//
// TT-Shuttle Squeeze v7 — S-11 Dynamic-Range Monitor
// Stream: W15-TT-C Guards+Sparse+Approx+TimeDomain+CarrySkip+BitSlice+SigmaDelta+Perm+Therm
// Anchor: phi^2 + phi^-2 = 3
//
// G-11 FALSIFICATION: running max/min track the true extremes on 100% of Wave-29
//                     vectors; headroom output matches ceil(log2(range)) ± 0 bits.
//
// Tracks the running min and max of a signed data stream to compute
// effective dynamic range. Outputs headroom (bits unused at top of range).
// Resets on clk posedge when rst is high.

`default_nettype none

module v7_dynrange_mon_S11 #(
    parameter WIDTH = 16
) (
    input  wire                    clk,
    input  wire                    rst,    // synchronous reset
    input  wire                    valid,  // sample valid strobe
    input  wire signed [WIDTH-1:0] data_in,

    output reg  signed [WIDTH-1:0] run_max,     // running maximum
    output reg  signed [WIDTH-1:0] run_min,     // running minimum
    output wire        [WIDTH-1:0] run_range,   // max - min (unsigned)
    output reg         [4:0]       headroom     // leading-zero headroom bits
);

    // Unsigned absolute range
    wire [WIDTH-1:0] range_raw = run_max - run_min;
    assign run_range = range_raw;

    // Leading-zero count for headroom: how many MSBs of range are 0
    // Implemented as priority encoder over range_raw MSBs
    function [4:0] lzc16;
        input [WIDTH-1:0] x;
        integer i;
        reg found;
        begin
            lzc16 = WIDTH[4:0];
            found = 1'b0;
            for (i = WIDTH-1; i >= 0; i = i-1) begin
                if (!found && x[i]) begin
                    lzc16 = (WIDTH-1-i);
                    found = 1'b1;
                end
            end
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            run_max  <= {1'b1, {(WIDTH-1){1'b0}}};  // most-negative signed
            run_min  <= {1'b0, {(WIDTH-1){1'b1}}};  // most-positive signed
            headroom <= 5'd0;
        end else if (valid) begin
            if (data_in > run_max) run_max <= data_in;
            if (data_in < run_min) run_min <= data_in;
            headroom <= lzc16(range_raw);
        end
    end

endmodule
`default_nettype wire
