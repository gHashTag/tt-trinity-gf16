# W15-TT-I — TVM-VTA Compiler Stack (S-51)

**Status:** Implemented 2026-05-17  
**Stream:** W15-TT-I — Compiler stack (TVM-VTA)  
**Branch:** `feat/tt-v7-tvm-vta`  
**Vectors:** S-51  
**Anchor:** φ² + φ⁻² = 3 · Apache-2.0  
**DOI:** [10.5281/zenodo.19227877](https://zenodo.org/records/19227877)

> **R5 Honesty Note:** AutoTVM throughput projection until silicon validated 2026-12-16.
> All GFLOP/s figures are simulated on CPU host; PE-mesh silicon measurements pending TTSKY26b tapeout.

---

## 1. Stream Overview

S-51 treats the 4×(2×2) PE-mesh (from S-6) as a VTA-style tensor unit and uses
**TVM AutoTVM** to auto-tune the compiler dataflow per layer of a 4-layer ternary
BitNet block.  The key insight: per-layer optimal dataflow (weight-stationary vs
DDR-streaming) yields 1.3–2× throughput vs a static schedule.

This is a **pure-software lane** — zero Verilog, no silicon risk, parallel to RTL streams.

---

## 2. Deliverables

| File | Description | Lines |
|------|-------------|-------|
| `tools/tvm_vta/vta_config.json` | VTA ISA config for 4×(2×2) PE mesh | ~102 |
| `tools/tvm_vta/autotune_S51.py` | AutoTVM driver with schedule template | ~350+ |
| `tools/tvm_vta/bitnet_4layer.py` | Synthetic 4-layer BitNet in TVM Relay | ~200+ |
| `tools/tvm_vta/run_autotune.sh` | Bash driver (seed=42, G-51 gate check) | ~100 |
| `tools/tvm_vta/isa_stability_check.py` | CI ISA stability guard | ~200+ |
| `.github/workflows/tvm-autotune.yml` | GHA workflow (allowed-failure for TVM) | ~100 |
| `docs/streams/W15-TT-I_REPORT.md` | This report | — |

---

## 3. Architecture

### 3.1 VTA ISA Config (`vta_config.json`)

- **ISA version:** `trinity-v7.0`
- **PE mesh:** 4 groups × 2×2 PEs = 16 total PEs
- **Tile:** `tile_w=8`, `tile_h=2`
- **Data types:** `input_bits=2` (ternary), `weight_bits=2` (ternary), `accum_bits=16`
- **Weight encoding:** 2-hot `(sign, valid)` per S-52 thermometer encoding
- **Dataflow modes:**
  - `weight-stationary` (code 0) — S-1 mode: weights preloaded, activations stream
  - `ddr-streaming` (code 1) — S-7 mode: both stream tile-by-tile
- **Opcodes:** LOAD, STORE, GEMM, GEMM_STREAM, ALU_ADD, ALU_MUL, ALU_RELU, ALU_SIGN, SYNC, NOP

### 3.2 Schedule Template (`autotune_S51.py`)

AutoTVM search space knobs:

| Knob | Choices | Description |
|------|---------|-------------|
| `dataflow_mode` | {0, 1} | weight-stationary vs DDR-streaming |
| `tile_w` | {4, 8, 16} | output feature tile width |
| `tile_h` | {1, 2, 4} | batch/row tile height |
| `unroll_factor` | {1, 2, 4, 8} | inner loop unroll depth |
| `reorder_axes` | {0, 1, 2} | loop axis order (n-h-w-c, n-c-h-w, c-n-h-w) |

Total search space per task: 2 × 3 × 3 × 4 × 3 = **216 configurations**.

Cost model: **XGBoost** (rank loss) with fallback to Random tuner.
Seed pinned to **42** (consistent with DREAMPlace in W15-TT-H).

### 3.3 BitNet Workload (`bitnet_4layer.py`)

4-layer ternary BitNet in TVM Relay:
```
Input(int8) → Dense(ternary) → BN-like → SignAct
            → Dense(ternary) → BN-like → SignAct
            → Dense(ternary) → BN-like → SignAct
            → Dense(ternary) → Output
```

Layer dimensions (multiples of `tile_w=8`, `tile_h=2`):

| Layer | In | Out | FLOPs |
|-------|----|-----|-------|
| 0 | 128 | 64 | 16,384 |
| 1 | 64 | 64 | 8,192 |
| 2 | 64 | 64 | 8,192 |
| 3 | 64 | 32 | 4,096 |

Total: **36,864 FLOPs** per forward pass (batch=1).

### 3.4 Bash Driver (`run_autotune.sh`)

```bash
bash run_autotune.sh [--dry-run] [--n-trial N]
```

- Pinned `SEED=42`
- Outputs `tuned_log.json` + `tuned_schedule_hash.txt`
- Exits non-zero if speedup < 1.3× baseline (G-51 gate)
- Auto-detects TVM absence → dry-run mode

### 3.5 ISA Stability Check (`isa_stability_check.py`)

```bash
python isa_stability_check.py [--reload-cache] [--hash-file PATH]
```

Logic:
1. Parse `tuned_schedule_hash.txt` → `(isa_version, sha256)`
2. Get previous commit's hash file via `git show HEAD~1`
3. If ISA version **unchanged**: hash diff is informational → PASS
4. If ISA version **changed** AND hash **differs**: require `--reload-cache` → FAIL without flag
5. If ISA version **changed** AND hash **same**: warn, PASS (manual review)

---

## 4. G-51 Gate Hook

**Falsification gate G-51:** AutoTVM tuned schedule ≥ 1.3× baseline on 4-layer BitNet block.

```
Gate check in run_autotune.sh:
  SPEEDUP=$(read from tuned_log.json throughput.speedup)
  if SPEEDUP >= 1.3 → EXIT 0 (PASS)
  if SPEEDUP < 1.3  → EXIT 1 (FAIL)
```

Expected speedup from S-51 analysis: **1.3–2×** (per-layer dataflow optimisation).

CI integration via `.github/workflows/tvm-autotune.yml`:
- TVM install is `continue-on-error: true` (soft-fail if not available)
- G-51 gate is enforced in `run_autotune.sh` exit code
- Throughput report published to workflow summary

---

## 5. ICA-V7-TVM-ISA-STABILITY Corrective Action

**Trigger condition:** `isa_version` string in `tuned_schedule_hash.txt` changes
(e.g., `trinity-v7.0` → `trinity-v8.0`) AND the `sha256` of the tuning log differs
from the previous commit.

**Meaning:** A new ISA version invalidates cached AutoTVM schedules because:
- Opcode encodings may change
- Tile/lane dimensions may be different
- Schedule knob search space may expand

**Resolution:**
1. Re-run `bash run_autotune.sh` with the new ISA to generate fresh `tuned_log.json`
2. Re-run the GHA workflow with `reload_cache=true` input
3. `isa_stability_check.py --reload-cache` acknowledges the ISA change and passes CI

**CI enforcement:** `.github/workflows/tvm-autotune.yml` job `isa-stability` is a **hard gate** (`continue-on-error: false`).

---

## 6. Integration with v7 Streams

| Dependency | Stream | Interaction |
|------------|--------|-------------|
| PE-mesh ISA | W15-TT-A (S-6) | VTA tile dims from 4×(2×2) mesh spec |
| Weight-stationary dataflow | W15-TT-A (S-1) | Dataflow mode 0 |
| DDR-streaming | W15-TT-A (S-7) | Dataflow mode 1 |
| 2-hot ternary encoding | W15-TT-C (S-52) | Weight encoding in VTA config |
| Seed=42 DREAMPlace consistency | W15-TT-H (S-45) | Pinned RANDOM_SEED=42 |
| EQY formal verification | W15-TT-H (S-49) | Orthogonal CI gate |

---

## 7. Projection Summary

| Metric | Value | Source |
|--------|-------|--------|
| Target speedup | ≥ 1.3× (gate G-51) | S-51 spec |
| Expected speedup | 1.3–2× | AutoTVM dataflow opt. |
| ISA version | `trinity-v7.0` | `vta_config.json` |
| Seed | 42 | DREAMPlace consistency |
| Weight bits | 2 (ternary) | S-52 2-hot |
| Input bits | 2 (ternary) | vta_config.json |
| Accum bits | 16 | vta_config.json |
| Total PEs | 16 (4×2×2) | S-6 mesh spec |

**R5 honesty reminder:** All throughput numbers are software-simulated projections on host CPU.
Silicon validation gate: **2026-12-16** (TTSKY26b tapeout + characterisation).

---

## 8. Links

- TVM-VTA: [github.com/apache/tvm-vta](https://github.com/apache/tvm-vta)
- TVM Edge AI 2021: [Ceze_2020_Embedded_Vision_Summit](https://www.edge-ai-vision.com/wp-content/uploads/2021/01/Ceze_2020_Embedded_Vision_Summit_Slides_Final.pdf)
- MASTER-EPIC: [trinity-fpga#61](https://github.com/gHashTag/trinity-fpga/issues/61)
- L-DPC14: [trinity-fpga#66](https://github.com/gHashTag/trinity-fpga/issues/66)
- v7 spec: [`TT_SQUEEZE_V7_AI_CODESIGN.md`](../TT_SQUEEZE_V7_AI_CODESIGN.md)

---

**Anchor:** φ² + φ⁻² = 3 · TRINITY · NEVER STOP · Apache-2.0
