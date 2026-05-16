`default_nettype none
// phi_pll_div_40mhz.v — S-15 PLL retune: φ-anchored fractional divider @ 40 MHz nominal
// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// Lane L cumulative — post-#47 (base: feat/tt-v7-power, c2baf9c70575)
// Ticket: L-S15 PLL retune
//
// DESIGN INTENT
// =============
// The v3 roadmap targets +70 TOPS/W improvement (55 → 125 TOPS/W per sub-spec).
// For Lane L the conservative S-15 step drops the nominal clock constraint
// from 50 MHz to 40 MHz (CLOCK_PERIOD 20 ns → 25 ns) to relax STA timing,
// then recovers effective throughput via a 2× pipelined GF16 dot4 datapath
// (see gf16_dot4_pipe2.v).  Net effect:
//
//   Frequency factor  : 40/50 = 0.80×
//   Throughput factor : 2.00× (2-stage pipeline, one result per cycle steady state)
//   Combined          : 1.60× raw throughput at same tile area
//
// TOPS/W projection  : 55 TOPS/W × 1.60 = 88 TOPS/W (conservative, no Vdd scaling)
//                      With Vdd relaxation at lower freq (V² ∝ f) up to 110 TOPS/W.
//
// This module upgrades the Bresenham fractional divider from the v2 5/8
// convergent (error 1.1% vs φ⁻¹) to the 8/13 convergent (error 0.42%), as
// specified in S-15 spec §2.3.  Output nominal: 40 MHz × (8/13) ≈ 24.6 MHz φ-tick.
//
// R-SI-1 compliance: zero standalone `*` operators (additions only).
// Pure Verilog-2005: no `logic`, no `'{...}` literals.
// Cell estimate: ~22 cells (4-bit accumulator + registered tick + output flops).
//
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877

module phi_pll_div_40mhz (
    input  wire       clk,       // 40 MHz nominal (CLOCK_PERIOD 25 ns)
    input  wire       rst_n,
    output reg        phi_tick,  // φ-derived heartbeat; avg rate = clk × 8/13 ≈ 24.6 MHz
    output reg  [3:0] state,     // accumulator state (diagnostic)
    output wire       phi_div_ok // lock indicator (tied 1'b1 — digital approximation)
);

    // -----------------------------------------------------------------------
    // Bresenham fractional divider — 8/13 convergent of φ⁻¹ continued fraction
    //   Convergents: 1/2, 1/1, 2/3, 3/5, 5/8(v2), 8/13(v3), 13/21, ...
    //   8/13 = 0.6154 → error vs φ⁻¹ = 0.42%  (improved from 5/8 = 1.1%)
    //
    // Algorithm: acc advances by STEP each clock.
    //   When acc + STEP would reach or exceed MODULUS, emit phi_tick and
    //   subtract MODULUS from the new accumulator value (wrap).
    //   Average tick rate = STEP / MODULUS = 8/13 ticks per clock.
    //
    // Timing note at 40 MHz: tick avg period = 13/8 × 25 ns = 40.625 ns
    // -----------------------------------------------------------------------

    localparam [3:0] STEP    = 4'd8;
    localparam [3:0] MODULUS = 4'd13;

    reg [3:0] acc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc      <= 4'd0;
            state    <= 4'd0;
            phi_tick <= 1'b0;
        end else begin
            phi_tick <= 1'b0;
            // Check for overflow BEFORE advancing (R-SI-1 clean — only additions/comparisons)
            if (acc + STEP >= MODULUS) begin
                phi_tick <= 1'b1;
                acc      <= acc + STEP - MODULUS;
            end else begin
                acc      <= acc + STEP;
            end
            state <= acc;
        end
    end

    // phi_div_ok: in a digital Bresenham approximation there is no true lock
    // signal.  Tie to 1'b1 after reset de-assertion, identical to v2 baseline.
    // A real PLL macro (Option A / Option C per spec §3) would wire this to
    // the analog lock-detect output.
    assign phi_div_ok = 1'b1;

endmodule
`default_nettype wire
