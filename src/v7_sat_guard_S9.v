// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Trinity Agent <agent@trinity.local>
//
// TT-Shuttle Squeeze v7 — S-9 Saturation Guard / Clamp
// Stream: W15-TT-C Guards+Sparse+Approx+TimeDomain+CarrySkip+BitSlice+SigmaDelta+Perm+Therm
// Anchor: phi^2 + phi^-2 = 3
//
// G-9 FALSIFICATION: post-synth output never exceeds MAX_VAL or underflows MIN_VAL
//                    on 100% of Wave-29 vectors (else clamp logic is broken).
//
// Saturating clamp for signed accumulator output.
// Clamps acc_in[WIDTH-1:0] to [MIN_VAL, MAX_VAL] range.
// No multiplier. Pure mux tree with comparators.

`default_nettype none

module v7_sat_guard_S9 #(
    parameter WIDTH   = 16,
    parameter MAX_VAL = 32767,   // 2^(WIDTH-1)-1 for signed 16-bit
    parameter MIN_VAL = -32768   // -2^(WIDTH-1)   for signed 16-bit
) (
    input  wire signed [WIDTH-1:0] acc_in,   // raw accumulator value
    output wire signed [WIDTH-1:0] acc_out,  // clamped output
    output wire                    sat_hi,   // saturation flag: clamped high
    output wire                    sat_lo    // saturation flag: clamped low
);

    // Compare against bounds using signed arithmetic
    wire overflow  = acc_in > $signed(MAX_VAL[WIDTH-1:0]);
    wire underflow = acc_in < $signed(MIN_VAL[WIDTH-1:0]);

    // Saturate output
    assign acc_out = overflow  ? $signed(MAX_VAL[WIDTH-1:0]) :
                     underflow ? $signed(MIN_VAL[WIDTH-1:0]) :
                                 acc_in;

    assign sat_hi = overflow;
    assign sat_lo = underflow;

endmodule
`default_nettype wire
