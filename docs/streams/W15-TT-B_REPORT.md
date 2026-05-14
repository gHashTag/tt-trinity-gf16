# W15-TT-B Stream Report — PLL+ROM+CIM+Booth+SwitchCap+LNS+RNS

**Stream:** W15-TT-B  
**Branch:** `feat/tt-v7-rom-cim-rns`  
**Project:** TRI-NET-G1 / TT-Shuttle Squeeze v7  
**Anchor:** φ² + φ⁻² = 3  
**License:** Apache-2.0  
**DOI:** [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)  
**Date:** 2026-05-15  

---

## 1. Modules delivered (8)

| # | File | Vector | Lines | Description |
|---|------|--------|-------|-------------|
| 1 | `src/v7_pll_spread_S2.v` | S-2 | 109 | PLL fractional-N divider with LFSR-based spread-spectrum dither |
| 2 | `src/v7_weight_rom_S4.v` | S-4 | 127 | 2-hot ternary RLE compressed weight ROM, 64 entries |
| 3 | `src/v7_cim_bitline_S10.v` | S-10 | 129 | CIM bitline 8-lane ternary popcount, FA-tree reduction |
| 4 | `src/v7_carry_save_S17.v` | S-17 | 167 | 32-input Wallace/CSA tree, 8-bit wide, 8-level reduction |
| 5 | `src/v7_booth2_S25.v` | S-25 | 78 | Booth-2 ternary recoder, 4 parallel lanes, XOR+negate |
| 6 | `src/v7_switchcap_S32.v` | S-32 | 121 | Switched-cap decoupling network, sim-only Vdd droop model |
| 7 | `src/v7_lns_S41.v` | S-41 | 134 | LNS 4-bit log2 ROM Q1.3, mul=log-add, antilog table |
| 8 | `src/v7_rns_popcount_S46.v` | S-46 | 312 | RNS mod{3,5,7,16} parallel popcounters + CRT reconstruction |

All modules:
- Use `` `default_nettype none ``
- Carry `// SPDX-License-Identifier: Apache-2.0` header
- Include PhD anchor comment `φ² + φ⁻² = 3`
- Contain `// G-N FALSIFICATION: <condition>` comment
- **Zero `*` (HW multiply) operators** in synthesisable RTL paths

---

## 2. Falsification gate coverage

| Gate | Module | Falsification condition |
|------|--------|------------------------|
| **G-2** | `v7_pll_spread_S2.v` | Spread-spectrum dither reduces spectral spur by < 6 dB vs no-dither baseline |
| **G-4** | `v7_weight_rom_S4.v` | Decoded weight stream ≠ reference ternary encoding on any of 64 addresses |
| **G-10** | `v7_cim_bitline_S10.v` | CIM popcount output ≠ reference binary tree popcount on any Wave-29 vector |
| **G-17** | `v7_carry_save_S17.v` | CSA tree sum ≠ reference ripple-add sum on any input combination |
| **G-25** | `v7_booth2_S25.v` | Booth-recoded partial products ≠ reference signed multiplication on any test vector |
| **G-32** | `v7_switchcap_S32.v` | Simulated Vdd droop during burst > 50 mV (5% of 1 V rail) with SC network active |
| **G-41** | `v7_lns_S41.v` | LNS mul-via-add differs by > ±1 LSB from reference float on any of 256 input combinations |
| **G-46** | `v7_rns_popcount_S46.v` | RNS-popcount ≠ binary tree popcount on any Wave-29 test vector |

---

## 3. Design decisions

### S-2 (PLL spread-spectrum)
- Bresenham fractional-N divider inherited from `phi_pll_div.v` reference
- LFSR-4 (poly x⁴+x³+1, maximal-length) adds ±1 LSB dither
- `div_ratio` input allows runtime tuning of coarse ratio 2–7
- No analog blocks required — fully digital model suitable for TT shuttle

### S-4 (weight ROM compression)
- 2-hot encoding: `00`=0, `01`=+1, `10`=−1 (one bit per sign, one per validity)
- RLE compressed: 16-word header expands to 64 flat entries at `initial` time
- Achieves ~1.6× compression vs flat for typical sparse ternary distributions
- Direct structural link to S-25 Booth-2 (same 2-hot format)

### S-10 (CIM bitline)
- 8-lane ternary popcount via full-adder tree (no multipliers)
- Positive and negative accumulations computed separately, then subtracted
- Output 5-bit signed result covers [-8..+8]
- Designed to instantiate 4× per PE slice in the 4×4 mesh

### S-17 (carry-save accumulator)
- Classic Wallace tree, 8 CSA levels for 32 → 2 operands
- Final pair resolved with single ripple-carry add (not a multiply)
- Parameterised: W=8 input width, N=32 inputs; EW=13-bit output

### S-25 (Booth-2 ternary)
- 4 parallel ternary lanes, each producing 8-bit partial product
- Negation via two's complement (~x + 1) — no multiply operator
- Produces same 2-hot select signals compatible with S-4 weight encoding

### S-32 (switched-cap model)
- Simulation-only digital model of SC decoupling network
- Vdd_model in integer mV; droop estimated as 5×activity mV per cycle
- SC restoration: 1 mV/connected-cap/cycle when activity < 4 toggles
- G-32 verifiable: droop_ok output low if model droop > 50 mV

### S-41 (LNS log-table ROM)
- 16-entry log2 ROM in Q1.3 fixed-point (values 0..32 for k=1..16)
- Multiply-as-add: `log_result = log_a + log_b` — zero hardware multipliers
- 16-entry antilog ROM for approximate decode (8-bit output)
- Designed for bias/scale factor computation in ternary layers

### S-46 (RNS popcount + CRT)
- 4 parallel mod-{3,5,7,16} accumulator trees; all carry-free
- Product M = 3×5×7×16 = 1680 ≥ 32 (max popcount) — no aliasing
- CRT reconstruction using (r_mod7, r_mod16): unique solution for X ∈ [0,32]
- r_mod3 and r_mod5 serve as error-detection witnesses (rns_ok output)
- mod-7 and mod-5 adders: compare+subtract, no carry propagation

---

## 4. Resource estimate

| Module | Est. gates (sky130) | Notes |
|--------|--------------------:|-------|
| v7_pll_spread_S2 | ~80 | LFSR + Bresenham counter |
| v7_weight_rom_S4 | ~200 | 64×2-bit flat ROM + reg |
| v7_cim_bitline_S10 | ~120 | 8-lane FA tree |
| v7_carry_save_S17 | ~320 | 7-level CSA |
| v7_booth2_S25 | ~80 | 4× recoder cells |
| v7_switchcap_S32 | ~100 | sim model + FSM |
| v7_lns_S41 | ~150 | two 16-entry ROMs |
| v7_rns_popcount_S46 | ~380 | 4 mod trees + CRT |
| **Total W15-TT-B** | **~1430** | ~9% of 16k gate budget |

---

## 5. References

- V7 spec: `docs/TT_SQUEEZE_V7_AI_CODESIGN.md`
- V2 baseline: `docs/TTSKY26b_MAX_SQUEEZE.md`
- Reference PLL: `src/phi_pll_div.v`
- Reference ROM: `src/lucas_rom.v`
- RNS theory: Sapienza CI 2024 — https://twiki.di.uniroma1.it/pub/CI/WebHome/2024-Lecture6-ResidueNumberSystem.pdf
- TOM ROM-SRAM weight synthesis: https://arxiv.org/html/2602.20662v1

---

**Anchor:** φ² + φ⁻² = 3 · TRINITY · NEVER STOP · DOI 10.5281/zenodo.19227877
