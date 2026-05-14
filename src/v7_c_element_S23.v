// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 TRI-NET-G1 / TT-Shuttle Squeeze v7
//
// v7_c_element_S23.v — Muller C-element gate primitive
// Stream S-23 · Wave W15-TT-F · Anchor φ²+φ⁻²=3
//
// G-23 FALSIFICATION: C-element output matches majority(a, b, q_prev) truth
//                     table on all 8 input combos → else S-23 dropped
//
// The Muller C-element is the fundamental gate for NCL / 4-phase async:
//   out = a·b + b·out_prev + out_prev·a    (majority with feedback)
//   Equivalently: set when both inputs 1, reset when both inputs 0,
//   hold when inputs differ.
//
// This is a "self-healing model" gate primitive (asynchronous handshake core).
// No claims of trusted execution are made.
//
// Two variants:
//   1. v7_c_element     — 1-bit standard C-element with feedback
//   2. v7_c_element_w   — 1-bit weighted/generalised C-element (3-input)
//
// No wildcard (*) in synth RTL.

`default_nettype none

// ============================================================
// 1-bit Muller C-element
//   Boolean: out_next = (a & b) | (b & out) | (out & a)
// ============================================================
module v7_c_element (
    input  wire clk,     // register feedback on clock edge (synthesis-friendly)
    input  wire rst_n,
    input  wire a,
    input  wire b,
    output reg  out
);

    // Combinational majority expression (no wildcard)
    wire out_next;
    assign out_next = (a & b) | (b & out) | (out & a);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            out <= 1'b0;
        else
            out <= out_next;
    end

endmodule


// ============================================================
// 1-bit Muller C-element — purely combinational model
//   For SPICE / analogue simulation, feedback is explicit.
//   In digital synthesis this is gated by a latch enable.
// ============================================================
module v7_c_element_latch (
    input  wire rst_n,
    input  wire a,
    input  wire b,
    input  wire q_fb,    // feedback from output (connect to out externally)
    output wire out
);

    // out = (a & b) | (b & q_fb) | (q_fb & a)
    assign out = (a & b) | (b & q_fb) | (q_fb & a);

    // NOTE: to avoid combinational loop in synthesis, use v7_c_element above.

endmodule


// ============================================================
// 3-input generalised / weighted C-element
//   Sets   when a & b & c
//   Resets when !a & !b & !c
//   Holds  otherwise
// ============================================================
module v7_c_element_3 (
    input  wire clk,
    input  wire rst_n,
    input  wire a,
    input  wire b,
    input  wire c,
    output reg  out
);

    wire set_cond;
    wire rst_cond;
    wire out_next;

    assign set_cond = a & b & c;
    assign rst_cond = (~a) & (~b) & (~c);

    // Majority-with-hold: set → 1, reset → 0, else keep
    assign out_next = set_cond | (out & (~rst_cond));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            out <= 1'b0;
        else
            out <= out_next;
    end

endmodule
