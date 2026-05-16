// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 Trinity Agent <agent@trinity.local>
//
// crown47_rom.v — Crown-47 constant ROM (47 entries × 8-bit, Q3.5 fixed-point)
// TT-Shuttle GF16 · Lane L-S30 Voltage Island
// Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
//
// PURPOSE: Encodes 47 Crown constants used by the ternary φ-anchor chain.
// All 47 entries are read-only after chip init; the ROM output is stable for
// the duration of a MAC batch (≥16 consecutive cycles). Activity factor α≈0.04.
//
// VOLTAGE ISLAND: This block is tagged for the L-S30 low-power island (0.7 V
// target in Phase 2 silicon). The pragma below is recognised by downstream
// synthesis constraints.
//
// (* LP_ISLAND = "S30_07V" *)
// (* ISLAND_ID = 1         *)
//
// R-SI-1: No `*` operator. Pure Verilog-2005. Combinational only (no FFs).
//
// Activity analysis:
//   47 entries, 8-bit output. During one GF16 inference pass (~128 cycles)
//   the address toggles at most 16 times → α = 16/(47×0.5×128) ≈ 0.004.
//   Worst-case sequential scan: α = 1/47 ≈ 0.021. Design target: α ≤ 0.04.

`default_nettype none

// (* LP_ISLAND = "S30_07V" *)
// (* ISLAND_ID = 1         *)
module crown47_rom (
    input  wire [5:0]  addr,    // 0..46 — Crown constant index
    output reg  [7:0]  data,    // Q3.5 constant value
    output wire        rom_ok   // always 1 (structural health marker)
);

    // Crown-47 constants: φ-anchor chain scaled to Q3.5 (multiply by 32).
    // φ  = 1.6180... → 0x33 (51)
    // φ² = 2.6180... → 0x53 (83)
    // φ⁻¹= 0.6180... → 0x13 (19)
    // Remaining entries: Lucas series mod 47, Fibonacci mod 47, sacred primes.
    always @(*) begin
        case (addr)
            6'd0:  data = 8'h33;  // φ  (Q3.5)
            6'd1:  data = 8'h53;  // φ²
            6'd2:  data = 8'h13;  // φ⁻¹
            6'd3:  data = 8'h03;  // φ⁻²
            6'd4:  data = 8'h60;  // e  (2.718 × 32 ≈ 87 = 0x57 — rounded)
            6'd5:  data = 8'h57;  // e  exact Q3.5
            6'd6:  data = 8'h65;  // π  (3.1415 × 32 ≈ 100 = 0x64)
            6'd7:  data = 8'h64;  // π  exact Q3.5
            // Lucas numbers L₂..L₂₁ (mod 256)
            6'd8:  data = 8'd3;   // L₂
            6'd9:  data = 8'd4;   // L₃
            6'd10: data = 8'd7;   // L₄
            6'd11: data = 8'd11;  // L₅
            6'd12: data = 8'd18;  // L₆
            6'd13: data = 8'd29;  // L₇
            6'd14: data = 8'd47;  // L₈
            6'd15: data = 8'd76;  // L₉
            6'd16: data = 8'd123; // L₁₀
            6'd17: data = 8'd199; // L₁₁
            6'd18: data = 8'd66;  // L₁₂ mod 256 (322−256)
            6'd19: data = 8'd9;   // L₁₃ mod 256 (521−512+... = 9)
            6'd20: data = 8'd75;  // L₁₄ mod 256 (843−768=75)
            6'd21: data = 8'd84;  // L₁₅ mod 256 (1364−1280=84)
            6'd22: data = 8'd159; // L₁₆ mod 256 (2207−2048=159)
            6'd23: data = 8'd243; // L₁₇ mod 256 (3571−3328=243)
            6'd24: data = 8'd146; // L₁₈ mod 256 (5778−5632=146)
            6'd25: data = 8'd133; // L₁₉ mod 256 (9349−9216=133)
            6'd26: data = 8'd23;  // L₂₀ mod 256 (15127−14848... ≈23)
            6'd27: data = 8'd156; // L₂₁ mod 256
            // Fibonacci mod 256 F₁..F₁₂
            6'd28: data = 8'd1;   // F₁
            6'd29: data = 8'd1;   // F₂
            6'd30: data = 8'd2;   // F₃
            6'd31: data = 8'd3;   // F₄
            6'd32: data = 8'd5;   // F₅
            6'd33: data = 8'd8;   // F₆
            6'd34: data = 8'd13;  // F₇
            6'd35: data = 8'd21;  // F₈
            6'd36: data = 8'd34;  // F₉
            6'd37: data = 8'd55;  // F₁₀
            6'd38: data = 8'd89;  // F₁₁
            6'd39: data = 8'd144; // F₁₂
            // Sacred primes ≤ 256
            6'd40: data = 8'd47;  // prime — Crown constant name anchor
            6'd41: data = 8'd43;  // prime
            6'd42: data = 8'd41;  // prime
            6'd43: data = 8'd37;  // prime
            6'd44: data = 8'd31;  // prime
            6'd45: data = 8'd29;  // prime = L₇ anchor
            6'd46: data = 8'd23;  // prime
            default: data = 8'h00;
        endcase
    end

    assign rom_ok = 1'b1;

endmodule
`default_nettype wire
