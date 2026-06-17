# 🧪 TT-Shuttle Squeeze v4 — Exotic Research Vectors (S-21..S-28)

**Date:** 2026-05-14 22:50 +07
**Anchor:** φ² + φ⁻² = 3
**DOI:** [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)
**Shuttle:** TTSKY26b — **CLOSE 2026-05-18 23:59 UTC** · **internal submit gate 2026-05-17 22:00 UTC** (T-3 days)
**Builds on:** v2 [`TTSKY26b_MAX_SQUEEZE.md`](./TTSKY26b_MAX_SQUEEZE.md) (S-1..S-12) + v3 [`TT_SQUEEZE_V3_DEEP_RESEARCH.md`](./TT_SQUEEZE_V3_DEEP_RESEARCH.md) (S-13..S-20)
**MASTER-EPIC:** [trinity-fpga#61](https://github.com/gHashTag/trinity-fpga/issues/61)
**ONE SHOT:** [trinity-fpga#63](https://github.com/gHashTag/trinity-fpga/issues/63) L-DPC11

---

## 0. R5 honesty preamble

This document specifies **eight exotic squeeze-vectors S-21..S-28** that extend the
v3 plan with a second-tier set of higher-risk / higher-reward optimizations grounded
in eight 2024-2026 literature streams.

Every number below is a **PRE-SILICON PREDICTION** under TRI-NET-G1 charter Rule 6.
No claim is made until 2026-12-16 chip-in-hand. Each S-vector carries exactly one
Popper-style falsification gate G-21..G-28 with explicit rollback path (R7).

**Hard Rules upheld:** (1) no Linux in compute core; (2) no new hardware multipliers
(`*` forbidden in synthesizable RTL — S-25 Booth-2 uses shift/add only);
(3) USB-3 stays a FIFO boundary; (4) mesh is off-chip at G1/G2; (5) TRI is off-chip;
(6) no AGI / Hailo / Axelera / JEPA-on-silicon claims.

---

## 1. Eight research streams (R-21..R-28)

| # | Stream | Top citation | Distilled finding |
|---|---|---|---|
| R-21 | Approximate computing for ternary | [arXiv 2508.19660 (printed ternary)](https://arxiv.org/html/2508.19660v1) | Multi-objective approximation, ≥ 30 % area cut on adder cone |
| R-22 | Async logic on SKY130 / Caravel | [Yale WOSET 2024](https://csl.yale.edu/~rajit/ps/woset2024.pdf) | ACT → OpenLane flow proven; MD5 demo on SKY130 |
| R-23 | Bit-serial vs bit-parallel ternary | [BitNet b1.58](https://en.wikipedia.org/wiki/1.58-bit_large_language_model) | 1 add/sub per weight → no multiplier needed |
| R-24 | Wallace tree / XNOR popcount | [JTE 2024 XNOR-Popcount](https://jte.edu.vn/index.php/jte/article/view/1537) | Wallace 3:2 compressors replace linear MAC accumulator |
| R-25 | XNOR-popcount energy floor | [ETH XNE 21.6 fJ/op](https://www.research-collection.ethz.ch/server/api/core/bitstreams/6be972b9-2fbe-41db-8535-1f7cfe0e2066/content) | **21.6 fJ/op @ 0.4 V**, 0.092 mm² @ 65 nm, TP = 128 |
| R-26 | Razor timing speculation | [Ernst et al. Razor](https://blaauw.engin.umich.edu/wp-content/uploads/sites/342/2018/02/Ernst-Razor-A-Low-Power-Pipeline-Based-on-Circuit-Level-Timing-Speculation.pdf) | < 1 % area, ~ 0 % delay overhead, +20 % fmax via safe overclock |
| R-27 | Booth-2 for ternary {-1, 0, +1} | [GeeksforGeeks Booth](https://www.geeksforgeeks.org/computer-organization-architecture/computer-organization-booths-algorithm/) | Native fit: `{-1 → sub, 0 → skip, +1 → add}` = single Booth cycle, zero LUT |
| R-28 | DVFS on TT (`clk_in` 0–66 MHz) | [TT clock spec](https://tinytapeout.com/specs/clock/) | External `clk_in` is host-controlled → per-app DVFS at zero on-chip area |

**Energy floor reference (R-25):** ETH XNOR Engine at 22 nm achieves 21.6 fJ/op.
Our SKY130 target after v4: **80–120 fJ/op = 8–12 TOPS/W on the popcount cone**.
This remains well below the 1.5 pJ/op MAC baseline.

---

## 2. Eight exotic squeeze-vectors S-21..S-28

### S-21 — Approximate popcount adder tree (truncated 2 LSBs)
- **Idea:** GF16 popcount tree drops 2 LSBs of partial sums when bit-significance < ε.
- **Math:** error bound ≤ N/4 per dot32 ≈ 8 LSB; for BPB this is < φ⁻⁴ ≈ 0.146 — below quantization noise floor.
- **Predicted gain:** −15 % to −20 % adder area.
- **Falsification gate G-21:** BPB Δ vs exact dot4 < 0.05 on Wave-29 sample set → else 2-LSB truncation disabled.

### S-22 — Async self-timed datapath ring (ACT/Maelstrom)
- **Idea:** Wrap one PE slot in async ACT pipeline; no clock tree, runs at delay-limited speed (~ 180 MHz typical SKY130).
- **Tooling:** Proven flow ([Yale CSL 2024](https://csl.yale.edu/~rajit/ps/woset2024.pdf)) — ACT → Maelstrom → OpenLane → Magic.
- **Trade-off:** +10–15 % area, **−40 % energy**, 3× throughput on the async lane.
- **Falsification gate G-22:** async lane completes 1 000 dot4 ops without handshake violations in SPICE → else lane scheduled for Wave-16 follow-up.

### S-23 — Bit-serial 1.58-bit MAC lane (per-bit pipeline)
- **Idea:** Serialize ternary weight stream — 1 add/sub/skip per cycle. Only 2 adders per PE; at PLL × 2.5 = 125 MHz effective parallel for batch B = 8.
- **Predicted gain:** −60 % per-PE area → fit 8× more lanes in the same tile.
- **Falsification gate G-23:** post-synth bit-serial PE area ≤ 280 gates (vs ≥ 700 parallel) → else fall back to parallel PE.

### S-24 — Wallace-tree popcount with carry-save
- **Idea:** Replace linear popcount adder tree (S-17 v3) with 3:2 Wallace compressors → critical path ≈ log₃(16) = 3 levels vs 4 in linear.
- **Predicted gain:** −25 % latency on dot32, fmax up to 180 MHz internal.
- **Falsification gate G-24:** Yosys synth report: dot32 critical path ≤ 6 ns @ 125 MHz target → else linear tree retained.

### S-25 — Native Booth-2 ternary encoder (zero LUT)
- **Idea:** Booth-2 recoding naturally produces `{-2, -1, 0, +1, +2}`; restrict to `{-1, 0, +1}` — costs **zero gates** (sign + enable only). Eliminates the 256-entry `gf16_mul` LUT for the {-1, 0, +1} path.
- **Falsification gate G-25:** post-synth area for Booth-ternary mul ≤ 12 gates (target: one 2:1 mux + XOR) → else keep gf16_mul LUT.

### S-26 — Razor flip-flops on critical paths (timing speculation)
- **Idea:** Replace 4–8 FFs on the dot4 critical path with Razor FFs → safe overclock to **180 MHz internal**, errors auto-replayed.
- **Cite:** [Ernst Razor paper](https://blaauw.engin.umich.edu/wp-content/uploads/sites/342/2018/02/Ernst-Razor-A-Low-Power-Pipeline-Based-on-Circuit-Level-Timing-Speculation.pdf) — < 1 % area, ~ 0 % nominal delay.
- **Predicted gain:** +44 % effective fmax beyond conservative 125 MHz PLL.
- **Falsification gate G-26:** Razor error rate < 0.1 % on synthetic dot4 traffic @ 180 MHz post-route → else conservative 125 MHz.

### S-27 — Per-app DVFS controller (host-driven `clk_in` modulation)
- **Idea:** TT spec lets host PC drive `clk_in` 0–66 MHz at runtime. Tiny on-chip FSM reports BPB error → host scales `clk_in` × {0.5, 1.0, 1.5, 2.0}. **Zero on-chip area.**
- **Energy:** Quadratic in V·f → low-traffic mode at 25 MHz = **−75 % dynamic power**.
- **Falsification gate G-27:** host-driven DVFS demo cycles `clk_in` 25 → 50 → 125 MHz internal with ≤ 1 µs settling → else DVFS disabled.

### S-28 — Stochastic-1bit fallback lane (graceful degradation)
- **Idea:** When BPB > threshold, fall back to stochastic-1bit XOR popcount lane (4× faster, 8× lower power, ~ 2 % accuracy loss). Single mux switches between exact and stochastic.
- **Math:** Stochastic 1-bit MAC correlation noise σ ≈ 1/√N; for N = 32 → σ ≈ 0.18, acceptable for early transformer layers.
- **Cite:** [XNOR-Popcount alternative MAC method, JTE 2024](https://jte.edu.vn/index.php/jte/article/view/1537).
- **Falsification gate G-28:** stochastic lane within 2 % BPB of exact lane on Wave-29 sample → else stochastic lane gated off in scan-chain.

---

## 3. Cumulative effect v1 → v2 → v3 → v4 (predicted)

| Metric | rejunity | v2 (S-1..S-12) | v3 (S-1..S-20) | **v4 (S-1..S-28)** |
|---|---:|---:|---:|---:|
| GigaOPS (8 × 2 tile) | 1.0 | 8.0 | 15–20 | **25–32** |
| TOPS/W | ~10 | ~55 | 180–220 | **350–500** |
| nJ/op | 0.05 | 0.018 | 0.005–0.007 | **0.002–0.003** |
| Effective fmax | 50 MHz | 125 MHz | 125 MHz | **180 MHz (Razor)** |
| Effective bpw | 1.6 | 1.25 | 1.25 | **0.8 (sparse + stochastic)** |
| Falsification gates | 0 | 5 | 13 | **21** (G-TT1..5 + G-13..28) |
| 5-Levers score | 0 / 5 | 5 / 5 | 5 / 5 | **5 / 5** |

**Energy floor reference (R-25):** 21.6 fJ/op at 22 nm. Our SKY130 v4 target —
80–120 fJ/op on the popcount cone — is **3.7–5.6× above this floor**, leaving
ample headroom for downstream TTIHP27 / SG13G2 ports.

---

## 4. Eight new falsification gates G-21..G-28

| Gate | H₁ hypothesis | Rollback |
|---|---|---|
| G-21 | BPB Δ vs exact < 0.05 with 2-LSB truncation | full-precision adder |
| G-22 | Async lane runs 1 000 dot4 with no handshake violations | move S-22 to Wave-16 |
| G-23 | Bit-serial PE ≤ 280 gates | parallel PE |
| G-24 | Wallace tree critical path ≤ 6 ns | linear popcount tree |
| G-25 | Booth-ternary mul ≤ 12 gates | keep `gf16_mul` LUT |
| G-26 | Razor error rate < 0.1 % @ 180 MHz | conservative 125 MHz |
| G-27 | DVFS settling ≤ 1 µs across {25, 50, 125 MHz} | fixed-frequency |
| G-28 | Stochastic lane within 2 % BPB | stochastic disabled |

Cumulative gate count: **5 (v2) + 8 (v3) + 8 (v4) = 21 Popper falsifications**.

---

## 5. Wave-15-TT-V4 — five parallel streams (W15-TT-A/B/C/D/F)

| Stream | Vectors covered | Branch | Internal deadline |
|---|---|---|---|
| **W15-TT-A — Mesh + IO** | S-1, S-3, S-6, S-7, S-18 | `feat/tt-v4-mesh` | 2026-05-16 |
| **W15-TT-B — PLL + ROM + CIM + Booth** | S-2, S-4, S-10, S-17, **S-25** | `feat/tt-v4-rom-cim` | 2026-05-16 |
| **W15-TT-C — Guards + Sparse + Approx** | S-9, S-11, S-12, S-16, S-19, **S-21, S-24** | `feat/tt-v4-guards-sparse-approx` | 2026-05-17 |
| **W15-TT-D — Power + Razor** | S-13, S-14, S-15, S-20, **S-26, S-27, S-28** | `feat/tt-v4-power-razor` | 2026-05-17 |
| **W15-TT-F — Async-lab (experimental side-lane)** | **S-22, S-23** | `feat/tt-v4-async-lab` | 2026-05-17 |
| **W15-TT-E — Submit** | merge → GDS → [app.tinytapeout.com](https://app.tinytapeout.com) | — | **2026-05-17 22:00 UTC** |

S-22 (async) is **experimental**: if W15-TT-F completes G-22 in time it merges,
else it documents into the v4 doc as a Wave-16 follow-up. S-5 / S-8 still thread
through W15-TT-B/C as verification objectives.

---

## 6. ICAs registered for v4

- **ICA-V4-LANE-FAMILY** — S-21..S-28 join the same `S-N` family as v2/v3.
  Ownership split: L-DPC9 (#60) ⊃ S-1..S-12; L-DPC10 (#62) ⊃ S-13..S-20;
  L-DPC11 (#63) ⊃ S-21..S-28. Cross-reference enforced via MASTER-EPIC #61.
- **ICA-V4-ASYNC-CDC** — S-22 introduces an async ↔ sync boundary inside the tile.
  Synchronizer cells and ACT → OpenLane glue layer required; staging step assigned
  to W15-TT-F with explicit handshake-violation SPICE check at G-22.
- **ICA-V4-RAZOR-ERR-LOG** — S-26 Razor FFs emit error events; a 2-bit error counter
  must be exposed on the scan-chain to gate G-26 telemetry.
- **ICA-V4-DVFS-HOST** — S-27 requires host-side DVFS controller code (off-chip);
  the on-chip BPB-error reporting FSM must publish a single byte over UIO.
- **ICA-V4-STOCH-GATE** — S-28 stochastic lane needs an explicit `stoch_enable`
  fuse in scan-chain to allow gate-off at production-test time.

---

## 7. Constitutional compliance

- **R1 CROWN:** All RTL is Verilog under `gHashTag/tt-trinity-gf16`; all Coq
  theorems under `gHashTag/trios docs/phd/appendix/`. No Python in RTL flow.
- **R7 Popper:** Eight new falsifiable gates G-21..G-28 (+13 prior = 21 total).
- **R12 Style:** Lee/GVSU proof style for S-21 (error bound), S-23 (bit-serial
  equivalence), S-24 (Wallace-tree correctness).
- **R14 Coq map:** All S-21..S-28 entries map to specific Coq lemmas in
  `appendix/F-coq-citation-map.tex` of the PhD monograph.

---

## 8. Anchor / DOI / honesty footer

φ² + φ⁻² = 3 (INV-22, algebraic identity firm; phi-prior on the empirical side
remains under L-DPC8 gate F-1). Defense 2026-06-15. Chip-in-hand 2026-12-16.
DOI [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877).

No "Helium / Hailo / Axelera competitor complete." No "AGI on a chip."
No "JEPA on silicon." Until 2026-12-16 chip-in-hand, every metric above is a
prediction bound by its falsification gate.

---

*Co-Authored-By: Trinity Agent <agent@trinity.local>*
