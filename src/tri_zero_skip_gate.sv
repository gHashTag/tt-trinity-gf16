// SPDX-License-Identifier: Apache-2.0
// tri_zero_skip_gate.sv — NorthPole-style zero-skip v2 clock-enable gate
// Apache-2.0
//
// Wave-16a · feat/wave-16a-zero-skip-experimental
// Author: Vasilev Dmitrii <admin@t27.ai> ORCID 0009-0008-4294-6159
//
// DESCRIPTION
// -----------
// Combinational clock-enable generator that suppresses PE pipeline activity
// when the incoming GF16 weight word is the zero value (4'b0000).
//
// This is "zero-skip v2" in the NorthPole sense:
//   v1 (W8 sparsity-skip) = multiplexer/operand-gate only (gf16_dot4_sparse pattern).
//   v2 (this module)      = CLOCK-ENABLE gating — the downstream PE register
//                           is held stable (no toggling) when weight == 0,
//                           eliminating even adder dynamic power.
//
// The downstream PE implements the behavioural ICG pattern:
//   always_ff @(posedge clk) if (pe_clk_en) begin ... end
// In SG13G2 physical mapping this is lowered to a latch+AND ICG cell per
// standard cell library convention (sg13g2_icg / sc7p5t_CLKBUF).
// The behavioural `if (pe_clk_en)` guard is the simulation/synthesis proxy.
//
// INTERFACE
// ---------
//   weight   [3:0]  — 4-bit GF16 weight field (ternary: 0000=zero, others non-zero)
//   clk             — system clock (unused in comb path; present for ICG anchor)
//   pe_clk_en       — clock-enable output; 1 = PE may clock, 0 = hold registers
//
// LOGIC
// -----
//   pe_clk_en = (weight != 4'b0000)
//   Comb-only; no flip-flops in this module.
//
// POWER ESTIMATE
// --------------
//   At sparsity ratio s (fraction of zero weights):
//     P_saved ≈ s × P_baseline_dynamic
//   NorthPole reference: 30–50% TOPS/W gain at s=0.33–0.50 (GF16 ternary typical).
//   Source: IBM NorthPole Science 2023 (doi:10.1126/science.adh1174),
//           research_northpole_levers.md §5 Lever A, §6 Lever 2.
//
// R-SI-1: zero `*` operators in synthesisable code. Safe: YES.
// ANCHOR: φ²+φ⁻²=3 · DOI 10.5281/zenodo.19227877 · R5

`default_nettype none

module tri_zero_skip_gate (
    // weight operand — 4-bit GF16 field (ternary: 0=zero, 1=+1, F/-1=other)
    input  wire [3:0] weight,
    // system clock — not used in combinational path; retained for ICG anchor
    // and downstream clock-enable instantiation context
    input  wire       clk,
    // pe_clk_en: 1 when weight is non-zero (PE allowed to clock)
    //            0 when weight == 4'b0000 (PE registers held, zero dynamic power)
    output wire       pe_clk_en
);

    // Combinational zero detection — single NOR4 equivalent gate.
    // pe_clk_en goes LOW only when all 4 weight bits are 0.
    assign pe_clk_en = (weight != 4'b0000);

    // Synthesis note for SG13G2 ICG mapping:
    //   The downstream PE should instantiate an ICG latch+AND cell:
    //     sg13g2_icg u_icg (.CLK(clk), .EN(pe_clk_en), .ENCLK(pe_gated_clk));
    //   and use pe_gated_clk as the register clock.
    //   For behavioural simulation the `if (pe_clk_en)` always_ff guard suffices.

endmodule
// phi^2 + phi^-2 = 3 · Wave-16a · DOI 10.5281/zenodo.19227877
`default_nettype wire
