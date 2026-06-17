# 🔬 TRI-1 Max — Deep Research v3: 8 NEW Squeeze-Vectors S-13..S-20

**Date:** 2026-05-14 22:38 +07
**Anchor:** φ² + φ⁻² = 3
**DOI:** [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)
**Shuttle:** TTSKY26b — **CLOSE 2026-05-18 23:59 UTC** (T-4 days)
**Internal submit gate:** 2026-05-17 22:00 UTC (T-3 days, 24 h buffer)
**MASTER-EPIC:** [trinity-fpga#61](https://github.com/gHashTag/trinity-fpga/issues/61)

---

## 0. Scope & R5-honesty preamble

This document specifies **eight new squeeze vectors S-13..S-20** that extend the v2
TTSKY26b shuttle plan (S-1..S-12 in `TTSKY26b_MAX_SQUEEZE.md`) with eight additional
post-place-and-route optimizations grounded in **seven 2025-2026 literature streams**.

**R5 honesty bound (TRI-NET-G1 charter, Rule 6):** All metrics in this document are
**predictions**, not claims, until 2026-12-16 chip-in-hand. Each vector is
falsifiable by a pre-registered Popper gate (G-13..G-20). On gate failure the vector
is dropped from the GDS and the lane records a `NULL` result in the as-flown matrix.

**Hard Rules upheld:** (1) no Linux in compute core; (2) no new hardware multipliers
(`*` token forbidden in synthesizable RTL); (3) USB-3 stays a FIFO boundary;
(4) mesh is off-chip at G1/G2; (5) TRI settlement is off-chip — FPGA emits receipts
only; (6) no AGI / Hailo / Axelera / JEPA-on-silicon claims.

---

## 1. Seven new literature streams (sources)

| # | Stream | 2025-2026 source | Distilled finding |
|---|---|---|---|
| 1 | SKY130 cell density | [SkyWater PDK docs](https://skywater-pdk.readthedocs.io/en/main/contents/libraries/foundry-provided.html) | `hd` lib = 266 kGates/mm²; `hdll` = 200 kGates/mm² with **10× lower leakage** |
| 2 | Clock gating (OpenROAD) | [Antmicro 2025 `cgt` flow](https://antmicro.com/blog/2025/07/automatic-clock-gating-in-openroad/) | Automatic CGT yields **8–15 % power savings** on Ibex CPU @ SKY130 |
| 3 | Near-threshold logic | [Blaauw 130 nm Subliminal](https://blaauw.engin.umich.edu/wp-content/uploads/sites/342/2017/11/378.pdf) | **2.6 pJ/instr @ 360 mV** with low-VT cells |
| 4 | Sparse-BitNet | [arXiv 2603.05168 (2026-03)](https://arxiv.org/html/2603.05168v1) | BitNet 1.58 has **42 % natural zero weights** + **6:8 N:M sparsity → 1.30× speedup** |
| 5 | Digital SRAM CIM | [JSSC 2025 CIM survey](https://github.com/BUAA-CI-LAB/Literatures-on-SRAM-based-CIM) | **109–249 TFLOPS/W** in digital SRAM CIM @ 22–28 nm |
| 6 | Inter-tile NoC on TT | [Mini AIE 2×2 CGRA TT07](https://tinytapeout.com/runs/tt07/tt_um_mini_aie_2x2) | Working precedent: **ring-NoC on Tiny Tapeout**, packet-routed |
| 7 | Systolic Tensor Array | [arXiv 2005.08098](https://arxiv.org/pdf/2005.08098) | STA: **−2.08× area, −1.36× power, 3.14× sparse boost** vs clock-gated SA |
| 8 | EpochCore SSM | [arXiv 2507.21394 (2025-08)](https://arxiv.org/html/2507.21394v3) | LIMA-PE **dual-gated clocks decouple load + compute → 45× energy** reduction |

---

## 2. Eight new squeeze-vectors S-13..S-20

### S-13 — Dual-library `hd` + `hdll` zoning
- **Source:** [SkyWater PDK](https://skywater-pdk.readthedocs.io/en/main/contents/libraries/foundry-provided.html). `hd` = 266 kGates/mm² @ 0.86 nA/kGate leakage; `hdll` = 200 kGates/mm² @ 0.08 nA/kGate leakage (-90 %).
- **Plan:** Compute path (hot) → `sky130_fd_sc_hd`; control + ROM + Merkle → `sky130_fd_sc_hdll`.
- **Predicted gain:** −30 % total static power.
- **Area cost:** 0 % (zoning, not addition).
- **Falsification gate G-13:** Mixed-lib OpenLane2 run closes timing @ 50 MHz; else fall back to pure `hd`.

### S-14 — Automatic clock gating (OpenROAD `cgt`)
- **Source:** [Antmicro 2025](https://antmicro.com/blog/2025/07/automatic-clock-gating-in-openroad/) — 8–15 % power savings on Ibex.
- **Plan:** Enable `cgt` in `flow.tcl` for all registers except PLL and scan-chain.
- **Predicted gain:** −12 % dynamic power → +14 % TOPS/W at no perf cost.
- **Area cost:** +3 % (enable-gate insertion).
- **Falsification gate G-14:** `cgt` identifies ≥ 80 candidate registers; else manual CGT on hot regs only.

### S-15 — Dual-rail Vdd (1.8 V compute + 0.9 V SRAM/control)
- **Source:** [Blaauw Subliminal 130 nm](https://blaauw.engin.umich.edu/wp-content/uploads/sites/342/2017/11/378.pdf). Energy ∝ V² → −75 % energy at 0.9 V vs 1.8 V on slow paths.
- **Plan:** Add on-die LDO for 0.9 V domain (ROM + scan-chain); level shifters at boundary.
- **Predicted gain:** −10 % total energy (control ~ 25 % of budget).
- **Area cost:** ~5 % of tile (LDO + level shifters).
- **Falsification gate G-15:** SKY130 low-VT cells produce clean waveforms @ 0.9 V in SPICE; else single-rail 1.8 V.

### S-16 — Zero-skip PE for 42 % natural ternary sparsity
- **Source:** [Sparse-BitNet, Microsoft Research 2026-03](https://arxiv.org/html/2603.05168v1) — BitNet 1.58 has 42 % zero weights naturally + 6:8 N:M sparsity → 1.30× speedup.
- **Plan:** Per PE add `if (weight == 0) skip cycle` FSM + N:M selector MUX.
- **Predicted gain:** **1.30–1.42× ops/cycle** (geometric mean of 42 % zeros and 6:8 N:M).
- **Area cost:** +8 % gates (skip-FSM + bypass MUX).
- **Falsification gate G-16:** Wave-14 Trinity models show actual sparsity ≥ 35 %; else feature gated off in scan-chain.

### S-17 — Popcount-tree in ROM periphery (digital-CIM-lite)
- **Source:** [JSSC 2025 digital SRAM CIM survey](https://github.com/BUAA-CI-LAB/Literatures-on-SRAM-based-CIM) — 109–249 TFLOPS/W; principle ports through popcount-tree in column periphery.
- **Plan:** ROM-synthesised weights (S-4) + popcount-tree in the same geometric column → XNOR-popcount without activation movement.
- **Predicted gain:** **2–3× TOPS/W** on INT8-act × ternary-weight kernels.
- **Area cost:** +15 % (popcount adder tree).
- **Falsification gate G-17:** Post-PnR routing congestion ≤ 80 %; else popcount-tree off, fall back to per-PE accumulators.

### S-18 — Ring-NoC across four 2×2 sub-meshes
- **Source:** [Mini AIE 2×2 CGRA TT07](https://tinytapeout.com/runs/tt07/tt_um_mini_aie_2x2) — working ring-NoC precedent on Tiny Tapeout.
- **Plan:** Re-partition 8×2 tile into **four 2×2 PE sub-meshes + ring-NoC** (4 stops, 4-byte packets).
- **Predicted gain:** 2× effective bandwidth for transformer FFN (local activation multicast).
- **Area cost:** +6 % (NoC routers + FIFO).
- **Falsification gate G-18:** Ring-NoC closes timing @ 125 MHz (PLL × 2.5); else throttle to 50 MHz (still net win on bandwidth).

### S-19 — Tensor-PE consolidation (STA from arXiv 2005.08098)
- **Source:** [Systolic Tensor Array, arXiv 2005.08098](https://arxiv.org/pdf/2005.08098) — −2.08× area, −1.36× power, 3.14× sparse boost vs clock-gated SA.
- **Plan:** Replace each PE with a tensor-PE running several parallel ternary ops through one register file.
- **Predicted gain:** **2× ops density** on identical gate budget.
- **Area cost:** −10 % (consolidation actually saves area).
- **Falsification gate G-19:** Tensor-PE synthesizes in ≤ 600 gates per PE; else fall back to standard PE.

### S-20 — Dual-gated clocks: load / compute decouple
- **Source:** [EpochCore LIMA-PE, arXiv 2507.21394](https://arxiv.org/html/2507.21394v3) — dual gated clocks decouple load + compute → 45× energy on SSM workloads.
- **Plan:** Two gated clock domains — `clk_load` (uio DDR FSM) + `clk_compute` (mesh) — each idle-gateable independently.
- **Predicted gain:** −25 % dynamic energy on overlap (S-8) workloads.
- **Area cost:** +2 % (extra gate cells).
- **Falsification gate G-20:** STA passes with dual clock domains + CDC verification; else collapse to single clock.

---

## 3. Cumulative effect v1 → v2 → v3 (predicted)

| Metric | rejunity baseline | TRI-1 Max v2 (S-1..S-12) | **TRI-1 Max v3 (S-1..S-20)** | v3 amplification |
|---|---|---|---|---|
| GigaOPS @ 50 MHz | 1.0 | 8.0 | **15–20** (S-16 + S-19 + S-17) | 15–20× |
| TOPS/W | ~10 | ~55 | **180–220** (S-13/S-14/S-15/S-20) | 18–22× |
| nJ/op | 0.05 | 0.018 | **0.005–0.007** | −86 % |
| Active model fit | < 1 B | 15 B | **20 B+** (S-17 CIM density) | 20× |
| Falsification gates | 0 | 5 (G-TT1..5) | **13** (G-TT1..5 + G-13..20) | full Popper R7 |
| 5-Levers score | 0 / 5 | 5 / 5 | **5 / 5 reinforced** | dominance locked |

All v3 numbers are **PRE-SILICON PREDICTIONS** under R5 — no claim is made until
2026-12-16 chip-in-hand. The competitor reference (rejunity/tiny-asic-1_58bit-matrix-mul,
1 GigaOPS / 0.2 mm² / 1.6 bpw) is used only as a reproducibility anchor.

---

## 4. Eight new falsification gates G-13..G-20

| Gate | H₁ hypothesis | Rollback path |
|---|---|---|
| **G-13** | Mixed `hd + hdll` closes timing @ 50 MHz | pure `hd` |
| **G-14** | `cgt` finds ≥ 80 candidate registers | manual CGT on hot regs only |
| **G-15** | SKY130 low-VT cells clean @ 0.9 V in SPICE | single-rail 1.8 V |
| **G-16** | Wave-14 models exhibit sparsity ≥ 35 % | zero-skip gated off |
| **G-17** | Post-PnR routing congestion ≤ 80 % | popcount-tree off |
| **G-18** | Ring-NoC closes timing @ 125 MHz | NoC @ 50 MHz |
| **G-19** | Tensor-PE ≤ 600 gates | standard PE |
| **G-20** | Dual-clock STA passes CDC | single clock |

---

## 5. Wave-15-TT-V3 — four parallel streams to 2026-05-18

The four streams below carve S-1..S-20 into disjoint branch namespaces and PR
queues so OpenLane2 runs don't fight for the same `runs/` directory.

| Stream | Vectors covered | Branch | Internal deadline |
|---|---|---|---|
| **W15-TT-A — Mesh + IO** | S-1, S-3, S-6, S-7, S-18 (ring-NoC) | `feat/tt-v3-mesh` | 2026-05-16 |
| **W15-TT-B — PLL + ROM + CIM** | S-2, S-4, S-10, S-17 (popcount tree) | `feat/tt-v3-rom-cim` | 2026-05-16 |
| **W15-TT-C — Guards + Sparse** | S-9, S-11, S-12, S-16 (zero-skip), S-19 (tensor-PE) | `feat/tt-v3-guards-sparse` | 2026-05-17 |
| **W15-TT-D — Power** | S-13 (hdll), S-14 (cgt), S-15 (dual-Vdd), S-20 (dual-clock) | `feat/tt-v3-power` | 2026-05-17 |
| **W15-TT-E — Submit** | merge all → GDS → [app.tinytapeout.com](https://app.tinytapeout.com) | — | **2026-05-17 22:00 UTC** |

24-hour buffer is preserved before the **2026-05-18 23:59 UTC** TTSKY26b hard close.

S-5 and S-8 (sequencing + overlap) remain Master-EPIC-level concerns and are not
assigned to a single stream — they thread through W15-TT-B and W15-TT-C as
verification objectives.

---

## 6. Issue map — what already exists

### `gHashTag/trinity-fpga`
- **MASTER-EPIC [#61](https://github.com/gHashTag/trinity-fpga/issues/61)** — Unified hub for S-1..S-20 + 13 gates (this document is its body)
- **EPIC [#49](https://github.com/gHashTag/trinity-fpga/issues/49)** — TRI-1 Triad TTSKY26b (Nano / Mid / Max)
- **L-DPC9 [#60](https://github.com/gHashTag/trinity-fpga/issues/60)** — TTSKY26b T-4 days (S-1..S-12 ONE SHOT)
- **L-DPC8 [#59](https://github.com/gHashTag/trinity-fpga/issues/59)** — TRI-1 Max v2 W15-W20 (`L-V2-S22..S33`)
- **L-DPC7 [#50](https://github.com/gHashTag/trinity-fpga/issues/50)** — TTIHP27a post-defense (`L-S20..S27`)
- **EPIC [#52](https://github.com/gHashTag/trinity-fpga/issues/52)** — TRI-1 v2 12 lanes (PhD-driven)
- **Lanes [#53–#58](https://github.com/gHashTag/trinity-fpga/issues/)** — `L-S25..L-S31` individual issues
- **EPIC [#19](https://github.com/gHashTag/trinity-fpga/issues/19)** — Parent dePIN-Compute Mesh
- **L-DPC6 [#48](https://github.com/gHashTag/trinity-fpga/issues/48)** — silicon-G1 Phase-1

### `gHashTag/tt-trinity-gf16`
- **Meta [#3](https://github.com/gHashTag/tt-trinity-gf16/issues/3)** — CROWN-ASIC roadmap
- **P0 [#4](https://github.com/gHashTag/tt-trinity-gf16/issues/4)** — LUT-only `gf16_mul` + Wallace dot4 + Yosys EQY (TTSKY26c)
- **PR [#9](https://github.com/gHashTag/tt-trinity-gf16/pull/9)** — silicon-G1 base (MERGED `a423ed5`)
- **PR [#10](https://github.com/gHashTag/tt-trinity-gf16/pull/10)** — SG1-09/10/11 + L-DPC7 draft (OPEN)

### `gHashTag/trios`
- **PR [#810](https://github.com/gHashTag/trios/pull/810)** — Wave-14b Trinity Loss
- **PR [#811](https://github.com/gHashTag/trios/pull/811)** — Wave-14a JEPA-T ingest
- **PR [#812](https://github.com/gHashTag/trios/pull/812)** — Wave-14c PhD round-3
- **PR [#784](https://github.com/gHashTag/trios/pull/784)** — PhD Ch.12 §4.5 silicon-G1
- **Throne [#264](https://github.com/gHashTag/trios/issues/264)** — Queen's Registry & Dispatch hub

---

## 7. ICAs registered for v3

- **ICA-V3-LANE-UNION** — S-1..S-12 (L-DPC9) and S-13..S-20 (L-DPC10) share the same `S-N` namespace family. Union is **intentional** (S-N is a single squeeze-vector family, not a lane allocator). Distinction is owned by L-DPC9 (v2 vectors) and L-DPC10 (v3 vectors). Cross-reference enforced via MASTER-EPIC #61.
- **ICA-V3-LIB-ZONING** — S-13 dual-library requires verified PDK install of both `hd` and `hdll` corners; staging step added to W15-TT-D.
- **ICA-V3-CDC** — S-20 introduces a CDC boundary; verification owned by W15-TT-D STA gate G-20 with explicit synchronizer cells.
- **ICA-SRAM-FIT** (carried from RVR-005) — superseded for v3: S-17 popcount-tree replaces SRAM macro intent; flop-ROM density assumption holds.

---

## 8. Anchor / DOI / honesty footer

φ² + φ⁻² = 3 (INV-22, algebraic identity firm; phi-prior on the empirical side
under L-DPC8 gate F-1). Defense 2026-06-15. Chip-in-hand 2026-12-16.
DOI [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877).

No "Helium / Hailo / Axelera competitor complete." No "AGI on a chip."
No "JEPA on silicon." Until 2026-12-16 chip-in-hand, every metric above is a
prediction bound by its falsification gate.

---

*Co-Authored-By: Trinity Agent <agent@trinity.local>*
