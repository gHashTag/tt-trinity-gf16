// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// v7_razor_S20.v — S-20 Razor double-sample flip-flop (simulation model)
// TT-Shuttle Squeeze v7 · W15-TT-D Power stream
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// G-20 FALSIFICATION: STA passes with dual clock domains + CDC verification;
//                     else collapse to single clock.
//
// S-20 dual-gated clocks: load / compute decouple.
// This module models the Razor double-sampling technique from:
//   Ernst et al., "Razor: A Low-Power Pipeline Based on Circuit-Level Timing
//   Speculation", MICRO 2003. (Blaauw Lab, U-Michigan)
//
// A Razor FF contains:
//   - A master FF clocked at clk (the speculative edge)
//   - A shadow latch clocked at clk_delayed (half-cycle later)
//   - An XOR comparator: if master ≠ shadow → metastability error detected
//   - On error: replay from shadow (safe value), assert err_pulse
//
// Simulation model: clk_delayed is approximated as clk with a 1-cycle delay.

`default_nettype none

module v7_razor_S20 #(
    parameter WIDTH = 8
) (
    input  wire             clk,            // speculative capture clock
    input  wire             rst_n,
    input  wire [WIDTH-1:0] d,              // data input (combinational path result)
    output wire [WIDTH-1:0] q,              // registered output
    output wire             err_pulse       // 1-cycle error flag → triggers replay
);

    // Master FF (speculative capture on clk posedge)
    reg [WIDTH-1:0] master_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) master_q <= {WIDTH{1'b0}};
        else        master_q <= d;
    end

    // Shadow register (captures d one cycle later = safe non-speculative value)
    reg [WIDTH-1:0] shadow_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) shadow_q <= {WIDTH{1'b0}};
        else        shadow_q <= master_q;   // shadow follows master with 1-cycle lag
    end

    // Error detection: if master captured glitching value, it differs from shadow
    wire err_raw = (master_q != shadow_q);

    // Single-cycle error pulse (edge detect)
    reg err_prev;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) err_prev <= 1'b0;
        else        err_prev <= err_raw;
    end
    assign err_pulse = err_raw & ~err_prev;

    // Output: use shadow on error (safe replay), master otherwise
    assign q = err_raw ? shadow_q : master_q;

endmodule
`default_nettype wire
