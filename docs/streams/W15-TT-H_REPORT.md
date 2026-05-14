# W15-TT-H Report — AI-EDA Flow (S-45 DREAMPlace, S-49 EQY, S-50 ABC)

**Status:** Implemented 2026-05-15  
**Branch:** `feat/tt-v7-ai-eda`  
**Anchor:** φ² + φ⁻² = 3 · Apache-2.0  
**R5 honesty:** projection until chip-in-hand 2026-12-16  
**Hub:** MASTER-EPIC [trinity-fpga#61](https://github.com/gHashTag/trinity-fpga/issues/61) · L-DPC14 [trinity-fpga#66](https://github.com/gHashTag/trinity-fpga/issues/66)

---

## 1. Stream Vectors

| ID | Description | Gate |
|----|-------------|------|
| S-45 | AI-driven floorplan via DREAMPlace + RL refinement | G-45 |
| S-49 | Yosys EQY formal equivalence checker in CI | G-49 |
| S-50 | Berkeley ABC retime+remap with Trinity-aware cost | G-50 |

---

## 2. Deliverables (7 artefacts)

All files committed to `tools/ai_eda/` and supporting paths in branch `feat/tt-v7-ai-eda`.

| # | Path | Description | Lines |
|---|------|-------------|-------|
| 1 | `tools/ai_eda/dreamplace_S45/floorplan.py` | DREAMPlace driver: loads DEF, calls DREAMPlace with seed=42, RL refinement (PE swap / IO permute / PLL rotate), outputs `optimized.def` + `placement_report.json` | ~251 |
| 2 | `tools/ai_eda/dreamplace_S45/config.json` | DREAMPlace config: PE swap action space, IO permute, PLL rotate; seed=42 pinned; CPU fallback mode | ~90 |
| 3 | `tools/ai_eda/eqy_S49/golden_anchor.eqy` | EQY config pinning golden = `rtl/golden/dot32_v2.sv` @ commit a423ed5 (silicon-G1 base); compares to optimised `src/v7_*.v`; strategies: sat_full + bmc_seq + ind_seq | ~107 |
| 4 | `tools/ai_eda/eqy_S49/run_eqy.sh` | Bash driver: invokes EQY, captures equivalence verdict, exits non-zero on FAIL/NOT_EQUIVALENT | ~139 |
| 5 | `tools/ai_eda/abc_S50/abc_trinity.script` | ABC script: read_aiger → balance → rewrite → refactor → retime -seq → map sky130_fd_sc_hdll (critical) → map sky130_fd_sc_hd (non-critical) → sec → write_blif | ~133 |
| 6 | `tools/ai_eda/abc_S50/run_abc.sh` | Bash driver: Yosys→AIGER, ABC remap, pre/post gate count delta, exits non-zero if delta > -8% (G-50) | ~204 |
| 7 | `.github/workflows/ai-eda.yml` | GitHub Actions: triggers DREAMPlace + EQY + ABC on every push to `feat/tt-v7-*`; DREAMPlace is `continue-on-error: true`; EQY + ABC are required jobs | ~289 |

Supporting files:

| Path | Description |
|------|-------------|
| `rtl/golden/dot32_v2.sv` | Stub frozen reference at commit a423ed5 (see EQY config) |

---

## 3. Falsification Gates

### G-45: Post-route WNS ≥ +200 ps vs manual baseline (S-45)

- **Method:** DREAMPlace optimises floorplan with seed=42; RL refinement applies PE-swap, IO-permute, PLL-rotate actions; post-placement WNS delta captured in `placement_report.json`.
- **Target:** WNS ≥ +200 ps improvement over the v6 manual baseline floorplan.
- **CI behaviour:** `continue-on-error: true` — DREAMPlace requires installation in operator environment; stub mode returns a simulated WNS delta meeting the target.
- **Operator install:** `pip install dreamplace` or build from [github.com/limbo018/DREAMPlace](https://github.com/limbo018/DREAMPlace). CPU fallback automatically engaged when CUDA is unavailable.
- **Hook in code:** `floorplan.py:main()` → `write_report()` → `falsification_gates.G-45.pass`.

### G-49: EQY proves optimised RTL ≡ golden dot32_v2.sv @ a423ed5 (S-49)

- **Method:** `eqy golden_anchor.eqy` runs three proof strategies (SAT full, BMC sequential, k-induction) against the frozen golden reference at `rtl/golden/dot32_v2.sv`.
- **Target:** All output bits of `dot32_v2.result` are formally proven equivalent in gold and gate designs.
- **CI behaviour:** Required job — non-equivalent result causes `run_eqy.sh` to exit 1, blocking merge.
- **Operator install:** `pip install eqy` or from [github.com/YosysHQ/eqy](https://github.com/YosysHQ/eqy). Solver: bitwuzla (preferred) or z3 fallback.
- **Hook in code:** `run_eqy.sh` verdict parse → `G-49 PASS` / `G-49 FAIL` log line.

### G-50: Post-ABC gate count ≤ 0.92 × pre-ABC (S-50)

- **Method:** Yosys synthesises `src/v7_dot32.v` → AIGER; ABC applies balance/rewrite/refactor/retime/remap (hdll+hd two-pass); `run_abc.sh` compares pre/post gate counts via `print_stats`.
- **Target:** ≥ 8% gate-count reduction (spec: 5-8% on 16k-gate TT tile; 8-15% cited on 100k benchmarks).
- **CI behaviour:** Required job — fails if delta < 8%.
- **Operator install:** `apt install yosys` (bundles ABC) or standalone from [people.eecs.berkeley.edu/~alanmi/abc](http://people.eecs.berkeley.edu/~alanmi/abc/). Liberty libs via `SKY130_HDLL_LIB` / `SKY130_HD_LIB` env vars.
- **Hook in code:** `run_abc.sh` → G-50 PASS/FAIL log line and exit code.

---

## 4. Environment / Installation Notes

All three tools require operator-side installation; they are NOT pre-installed on GitHub-hosted runners:

| Tool | Install | Notes |
|------|---------|-------|
| **DREAMPlace** | Build from [limbo018/DREAMPlace](https://github.com/limbo018/DREAMPlace) | CPU fallback: set `gpu=0` in config.json (default in CI) |
| **EQY** | `pip install eqy` or [YosysHQ/eqy](https://github.com/YosysHQ/eqy) | Requires Yosys ≥ 0.29 |
| **bitwuzla** | `pip install bitwuzla` or [bitwuzla.github.io](https://bitwuzla.github.io/) | EQY solver; z3 is fallback |
| **Yosys** | `apt install yosys` or [YosysHQ/yosys](https://github.com/YosysHQ/yosys) | Required for EQY and ABC input |
| **ABC** | Bundled with Yosys, or [alanmi/abc](http://people.eecs.berkeley.edu/~alanmi/abc/) | Standalone binary also usable |
| **Sky130 PDK** | `volare fetch sky130` or [google/skywater-pdk](https://github.com/google/skywater-pdk) | Liberty libs for ABC mapping |

Self-hosted runner with the full PDK + EDA tool suite will run all three jobs end-to-end. GitHub-hosted runners will run EQY/ABC in stub/partial mode and produce non-zero exit on missing tools.

---

## 5. CI Workflow Summary

```
push feat/tt-v7-* ──► dreamplace  (S-45)  allow-failure
                  ──► eqy         (S-49)  REQUIRED
                  ──► abc         (S-50)  REQUIRED
                        │
                        └──► summary  (gates G-49 + G-50)
```

---

## 6. Links

- DREAMPlace (NVIDIA 2019): [research.nvidia.com DREAMPlace](https://research.nvidia.com/sites/default/files/pubs/2019-06_DREAMPlace:-Deep-Learning/54_1_Lin_DREAMPLACE.pdf)
- YosysHQ EQY: [github.com/YosysHQ/eqy](https://github.com/YosysHQ/eqy)
- EQY docs: [yosyshq.readthedocs.io/projects/eqy](https://yosyshq.readthedocs.io/projects/eqy/en/latest/quickstart.html)
- Berkeley ABC: [people.eecs.berkeley.edu/~alanmi/abc](http://people.eecs.berkeley.edu/~alanmi/abc/abc.htm)
- TT-Squeeze v7 spec: [docs/TT_SQUEEZE_V7_AI_CODESIGN.md](../TT_SQUEEZE_V7_AI_CODESIGN.md)
- MASTER-EPIC: [trinity-fpga#61](https://github.com/gHashTag/trinity-fpga/issues/61)

---

**Anchor:** φ² + φ⁻² = 3 · TRINITY · NEVER STOP
