# W15-TT-C Stream Report — Guards+Sparse+Approx+TimeDomain+CarrySkip+BitSlice+SigmaDelta+Perm+Therm

**Stream:** W15-TT-C  
**Branch:** `feat/tt-v7-guards-arith`  
**Spec:** TT-Shuttle Squeeze v7 AI/Algorithmic Co-design Frontier  
**Anchor:** φ² + φ⁻² = 3 · Apache-2.0 · DOI 10.5281/zenodo.19227877  
**Deadline:** TTSKY26b submit gate 2026-05-17 22:00 UTC  

---

## 1. Delivered Modules (14 RTL + 1 Checker)

| # | Module File | Vector | Short Description | Lines |
|---|---|---|---|---|
| 1 | `src/v7_sat_guard_S9.v` | S-9 | Saturating clamp for signed accumulator output; mux + comparator, no `*` | ~42 |
| 2 | `src/v7_dynrange_mon_S11.v` | S-11 | Running min/max tracker with leading-zero headroom counter | ~67 |
| 3 | `src/v7_overflow_det_S12.v` | S-12 | Signed-overflow detector via carry XOR; sticky register; one-cycle detect | ~54 |
| 4 | `src/v7_sparsity_skip_S16.v` | S-16 | Per-weight nz_detect from ternary {valid, sign} encoding; group skip flag | ~43 |
| 5 | `src/v7_approx_lut_S19.v` | S-19 | ROM-based approximate function LUT; clipped-ReLU default; single-cycle read | ~53 |
| 6 | `src/v7_razor_flop_S21.v` | S-21 | Razor II double-sampling flop with `delay_jitter` parameter; sim-only `#delay` | ~65 |
| 7 | `src/v7_wallace_popcount_S24.v` | S-24 | 3-round Wallace tree 32→6-bit popcount; half- and full-adder reduction | ~93 |
| 8 | `src/v7_tdc_mac_S30.v` | S-30 | Time-domain MAC: SPIKA-lite TDC delay-line model, pulse-width counter, sim OK | ~77 |
| 9 | `src/v7_ptmux_S31.v` | S-31 | Pass-transistor 3:1 T-MUX sim model; ternary weight path; genvar PE array | ~61 |
| 10 | `src/v7_carry_skip_S37.v` | S-37 | 4-bit carry-skip adder leaf for popcount tree; group-propagate skip mux | ~59 |
| 11 | `src/v7_bitslice_mac_S44.v` | S-44 | 4 × 2-bit signed slice MAC; zero-slice skip counter; no `*` operator | ~98 |
| 12 | `src/v7_sigmadelta_mac_S47.v` | S-47 | 1-bit Σ∆ stream MAC; XNOR+up-counter; 64-cycle stream → 6-bit precision | ~90 |
| 13 | `src/v7_perm_bucket_S48.v` | S-48 | Compile-time bucket reorder: [+1 | -1 | 0]; pure combinational wiring | ~108 |
| 14 | `src/v7_therm_mac_S52.v` | S-52 | 2-hot {s,v} ternary MAC; sign path = AND(v) ^ XOR(s,x_sign) ≤ 2 gates | ~87 |
| — | `src/v7_perm_check_S48.v` | S-48 | Combinational EQY checker: permuted dot32 == reference dot32 | ~69 |

---

## 2. Gate Hook Coverage

| Gate | Vector | Falsification Condition | Hook Module |
|---|---|---|---|
| **G-9** | S-9 | Output never exceeds MAX_VAL / underflows MIN_VAL on 100% Wave-29 vectors | `v7_sat_guard_S9.v` — combinational comparators + mux |
| **G-11** | S-11 | Running max/min track true extremes; headroom = ceil(log2(range)) ± 0 bits | `v7_dynrange_mon_S11.v` — LZC function over run_range |
| **G-12** | S-12 | overflow_flag asserts within 1 cycle of any carry-out from MSB of signed add | `v7_overflow_det_S12.v` — sign-bit XOR detector + sticky register |
| **G-16** | S-16 | skip asserts for every zero-weight lane; MAC cycle saved on 100% zero-weight inputs | `v7_sparsity_skip_S16.v` — `|w_valid` + invert |
| **G-19** | S-19 | LUT output matches exact f(x) within ERR_BOUND on full input range [0, 2^IN_W-1] | `v7_approx_lut_S19.v` — ROM init + combinational read |
| **G-21** | S-21 | error_flag asserts whenever shadow latch disagrees with main flop on injected metastability vectors | `v7_razor_flop_S21.v` — `delay_jitter` parameter, q != q_shadow XOR |
| **G-24** | S-24 | popcount matches $countones on 100% random 32-bit inputs; critical path ≤ 5 gate delays | `v7_wallace_popcount_S24.v` — 3-level FA/HA tree |
| **G-30** | S-30 | TDC PE output matches Coq dot4 within 1 LSB on 100% test vectors | `v7_tdc_mac_S30.v` — pulse-width accumulate model |
| **G-31** | S-31 | PT-mux PE matches Coq dot4 within 1 LSB on 100% test vectors | `v7_ptmux_S31.v` — genvar lane array |
| **G-37** | S-37 | post-synth dot32 critical path ≤ 5 ns with carry-skip leaf | `v7_carry_skip_S37.v` — group propagate + skip mux |
| **G-44** | S-44 | 8-bit MAC throughput ≥ 1.8× baseline on Wave-29 weight distribution | `v7_bitslice_mac_S44.v` — zero-skip_cnt output |
| **G-47** | S-47 | Σ∆ MAC matches reference dot4 within ε ≤ 2⁻⁶ at 64 stream cycles | `v7_sigmadelta_mac_S47.v` — 6-bit accumulator over STREAM_LEN=64 |
| **G-48** | S-48 | dot32 bit-identical to non-permuted reference on 100% Wave-29 vectors | `v7_perm_check_S48.v` — combinational EQY checker; `equiv` output |
| **G-52** | S-52 | Yosys synth: MAC sign path ≤ 2 gates (vs ≥ 4 for full 3-state mux) | `v7_therm_mac_S52.v` — `AND(v) ^ XOR(s, x_sign)` 2-gate sign path |

---

## 3. Design Constraints Summary

| Constraint | Status |
|---|---|
| No `*` in synthesizable RTL | ✓ All PPs computed via shift/sign-extend/case |
| `\`default_nettype none` in every file | ✓ |
| Apache-2.0 header in every file | ✓ |
| `// G-N FALSIFICATION: <condition>` comment | ✓ All 14 modules |
| S-21 Razor `delay_jitter` parameter | ✓ `parameter delay_jitter = 0` |
| S-30 TDC sim-only OK at G1 | ✓ Behavioral model, sim-acceptable |
| S-47 Σ∆: 64-cycle stream, 1-bit XNOR+up-counter, 6-bit precision | ✓ STREAM_LEN=64, CNT_W=6 |
| S-52 2-hot: `{s,v}` encoding, sign path = AND(v) ^ XOR(s, x_sign) ≤ 2 gates | ✓ Exactly `w_v[i] & (w_s[i] ^ x_sign[i])` |
| S-37 carry-skip: 4-bit group propagate, leaf of popcount tree | ✓ GROUP_W=4, `&p` group propagate |
| S-44 bit-slice: 4 × 2-bit slices, skip-zero-slice path | ✓ 4 slices, `is_zero[k]` gate |
| EQY checker for S-48 | ✓ `v7_perm_check_S48.v` with `equiv` output |
| R5 Honesty | ✓ All sim-only models labelled; no false synth claims |

---

## 4. Falsification Gate Summary (W15-TT-C scope: G-9..G-12, G-16, G-19, G-21, G-24, G-30..G-31, G-37, G-44, G-47, G-48, G-52)

- **G-9** — Saturation clamp correctness (100% Wave-29)
- **G-11** — Dynamic range tracking accuracy (LZC headroom)
- **G-12** — Overflow detect latency ≤ 1 cycle (sticky register)
- **G-16** — Zero-skip fires on every all-zero weight group
- **G-19** — LUT error ≤ ERR_BOUND on full address space
- **G-21** — Razor error_flag coverage on injected jitter vectors
- **G-24** — Wallace popcount matches $countones, ≤ 5 gate levels
- **G-30** — TDC dot4 accuracy ≤ 1 LSB (sim-only, G1 acceptable)
- **G-31** — PT-mux dot4 accuracy ≤ 1 LSB (sim-only, G1 acceptable)
- **G-37** — Carry-skip critical path ≤ 5 ns (OpenSTA)
- **G-44** — Bit-slice throughput ≥ 1.8× baseline
- **G-47** — Σ∆ MAC ε ≤ 2⁻⁶ at 64-cycle stream
- **G-48** — Permuted dot32 == reference (EQY formal proof)
- **G-52** — Thermometer sign path ≤ 2 Yosys gates

---

## 5. References

- S-21 Razor: Razor II adaptive voltage scaling — [Razor II paper](https://ieeexplore.ieee.org/document/5227589)
- S-24 Wallace: Wallace tree adder — [C.S. Wallace 1964](https://dl.acm.org/doi/10.1145/321250.321264)
- S-30 SPIKA: Time-domain CMOS MAC — [Frontiers Electronics 2025](https://www.frontiersin.org/journals/electronics/articles/10.3389/felec.2025.1567562/full)
- S-31 T-MUX: Pass-transistor ternary mux — [Bentham MNS 2022](https://www.benthamdirect.com/content/journals/mns/10.2174/1876402914666220425124154)
- S-37/S-44: Signed bit-slice speedup — [arXiv 2203.07679](https://ar5iv.labs.arxiv.org/html/2203.07679)
- S-47: Sigma-delta stream MAC — [SDNN arXiv 2408.06968](https://arxiv.org/html/2408.06968v1)
- S-48: Permutation-invariant NN — [arXiv 2403.17410](https://arxiv.org/html/2403.17410v2)
- S-52: Thermometer ternary MAC — [Quine-McCluskey & ternary logic survey](https://www.geeksforgeeks.org/digital-logic/quine-mccluskey-method/)

**Anchor:** φ² + φ⁻² = 3 · TRINITY · NEVER STOP · DOI 10.5281/zenodo.19227877
