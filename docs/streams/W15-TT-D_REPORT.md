# W15-TT-D Power Stream Report

**Stream:** W15-TT-D — Power+Razor+RBB+VStack+PowerGate+Latch  
**Branch:** `feat/tt-v7-power`  
**Repo:** `gHashTag/tt-trinity-gf16` · Apache-2.0  
**Anchor:** φ² + φ⁻² = 3 · DOI [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)  
**Vectors:** S-13, S-14, S-15, S-20, S-26, S-27, S-28, S-29, S-38, S-42, S-43  
**Deadline:** 2026-05-17 22:00 UTC (TTSKY26b submit gate)

---

## R5 Honesty Bound

All metrics below are **pre-silicon predictions**, not claims. Each vector is
falsifiable by a pre-registered Popper gate (G-N). On gate failure the vector
is dropped from GDS and the lane records a `NULL` in the as-flown matrix.

---

## Module Inventory

| Module file | Vector | Description |
|---|---|---|
| `src/v7_clock_gate_S13.v` | S-13 | Per-PE ICG cell (hdll latch + hd AND gate) |
| `src/v7_dvfs_ctrl_S14.v` | S-14 | DVFS controller stub — BPB error tier reporter |
| `src/v7_pwr_island_S15.v` | S-15 | Power island isolator + level-shifter wrappers |
| `src/v7_razor_S20.v` | S-20 | Razor double-sample FF simulation model |
| `src/v7_clk_tree_S26.v` | S-26 | Fine-grain clock tree (N_PE ICGs, 2-stage balanced) |
| `src/v7_leakage_mon_S27.v` | S-27 | Leakage/activity monitor — suggest host freq change |
| `src/v7_stoch_mac_S28.v` | S-28 | Stochastic lane: XNOR + counter bit-stream multiplier |
| `src/v7_rbb_ctrl_S29.v` | S-29 | RBB controller — `body_bias_level[3:0]` + SPICE anchor |
| `src/v7_vstack_S38.v` | S-38 | Voltage stacking 2-tier mid-rail driver + level-shifter |
| `src/v7_regate_S42.v` | S-42 | ReGate 1-cycle wake FSM (SLEEP/WAKE/ACTIVE) |
| `src/v7_latch_pipe_S43.v` | S-43 | Latch pipeline: alpha/beta alternating phases, 4 stages |

---

## Falsification Gate Hooks

### G-13 — Clock Gating (S-13)
- **Condition:** Mixed `hd`+`hdll` OpenLane2 run closes timing @ 50 MHz
- **Rollback:** Fall back to pure `sky130_fd_sc_hd` library
- **RTL hook:** `v7_clock_gate_S13` ICG latch annotated `(* SYNTHESIS_CELL_LIB = "sky130_fd_sc_hdll" *)`
- **FALSIFICATION:** `// G-13 FALSIFICATION: Mixed hd+hdll OpenLane2 run closes timing @ 50 MHz`

### G-14 — DVFS Controller (S-14)
- **Condition:** `cgt` identifies ≥ 80 candidate registers
- **Rollback:** Manual CGT on hot registers only
- **RTL hook:** `v7_dvfs_ctrl_S14` reports `dvfs_tier[1:0]` on `uio[1:0]`; `clk_gate_hint` feeds ICG enables
- **FALSIFICATION:** `// G-14 FALSIFICATION: cgt identifies ≥ 80 candidate registers`

### G-15 — Power Island (S-15)
- **Condition:** SKY130 low-VT cells produce clean waveforms @ 0.9 V in SPICE
- **Rollback:** Single-rail 1.8 V
- **RTL hook:** `v7_pwr_island_S15` provides isolation clamp + level-shifter structural wrappers
- **FALSIFICATION:** `// G-15 FALSIFICATION: SKY130 low-VT cells clean @ 0.9V in SPICE`

### G-20 — Razor Double-Sample (S-20)
- **Condition:** STA passes with dual clock domains + CDC verification
- **Rollback:** Collapse to single clock
- **RTL hook:** `v7_razor_S20` exposes `err_pulse`; ties to BPB error counter in `v7_dvfs_ctrl_S14`
- **FALSIFICATION:** `// G-20 FALSIFICATION: STA passes with dual clock domains + CDC`

### G-26 — Fine-Grain Clock Tree (S-26)
- **Condition:** Razor error rate < 0.1% on dot4 traffic @ 180 MHz post-route
- **Rollback:** Conservative 125 MHz
- **RTL hook:** `v7_clk_tree_S26` instantiates one `v7_clock_gate_S13` per PE; tree is 2-stage balanced
- **FALSIFICATION:** `// G-26 FALSIFICATION: Razor error rate < 0.1% @ 180 MHz post-route`

### G-27 — Leakage Monitor (S-27)
- **Condition:** Host-driven DVFS cycles clk_in 25 → 50 → 125 MHz with ≤ 1 µs settling
- **Rollback:** DVFS disabled
- **RTL hook:** `v7_leakage_mon_S27` drives `suggest_down` / `suggest_up` → fed to host via uio
- **FALSIFICATION:** `// G-27 FALSIFICATION: DVFS cycles 25→50→125 MHz ≤ 1µs settling`

### G-28 — Stochastic MAC (S-28)
- **Condition:** Stochastic lane within 2% BPB of exact lane on Wave-29 sample
- **Rollback:** Stochastic lane gated off in scan-chain
- **RTL hook:** `v7_stoch_mac_S28` controlled by `stoch_enable`; gating from `v7_dvfs_ctrl_S14` BPB threshold
- **FALSIFICATION:** `// G-28 FALSIFICATION: stochastic lane within 2% BPB of exact on Wave-29`

### G-29 — RBB Controller (S-29)
- **Condition:** SPICE on 1 idle PE @ RBB = +0.5 V shows ≥ 4× leakage drop vs nominal
- **Rollback:** RBB disabled (body_bias_level = 0)
- **RTL hook:** `v7_rbb_ctrl_S29` drives `body_bias_level[3:0]`; SPICE-anchor comment block in module header
- **FALSIFICATION:** `// G-29 FALSIFICATION: SPICE idle PE @ RBB +0.5V ≥ 4× leakage drop`

### G-38 — Voltage Stacking (S-38)
- **Condition:** SPICE: external Vdd supply current ≤ 60% of flat-supply baseline
- **Rollback:** Single-rail 1.8 V fallback
- **RTL hook:** `v7_vstack_S38` wraps level-shifter boundary; SPICE-anchor comment block in module header
- **FALSIFICATION:** `// G-38 FALSIFICATION: SPICE I_ext ≤ 60% flat-supply at same MAC throughput`

### G-42 — ReGate Power Gating (S-42)
- **Condition:** SPICE: gated PE static current ≤ 1 nA @ 25°C nominal
- **Rollback:** Power gating disabled
- **RTL hook:** `v7_regate_S42` receives `nz_detect` from S-16; drives `pe_clk_en` into `v7_clock_gate_S13`
- **Combined:** When S-29 RBB + S-42 ReGate both active → sub-pA idle leakage target
- **FALSIFICATION:** `// G-42 FALSIFICATION: SPICE gated PE ≤ 1 nA @ 25°C nominal`

### G-43 — Latch Pipeline (S-43)
- **Condition:** OpenSTA timing report shows zero hold violations with 15% delay jitter on stage-3→4
- **Rollback:** Standard FF pipeline (no time borrowing)
- **RTL hook:** `v7_latch_pipe_S43` uses alternating `latch_alpha` / `latch_beta` instances
- **FALSIFICATION:** `// G-43 FALSIFICATION: OpenSTA zero hold violations @ 15% jitter stage-3→4`

---

## Integration Notes

### S-42 → S-13 dependency
`v7_regate_S42.pe_clk_en` feeds `v7_clock_gate_S13.enable` per PE. The ReGate
FSM is the authoritative clock-enable source; it combines the nz_detect sparsity
flag (S-16) with the 1-cycle wake-up state machine.

### S-29 → S-42 combined idle
When `v7_regate_S42.state_q == SLEEP` AND `v7_rbb_ctrl_S29.body_bias_level == 4'h4`,
the PE is simultaneously clock-gated, power-gated, and reverse-body-biased.
Expected combined idle leakage: sub-pA (SPICE target).

### S-27 → S-14 DVFS loop
`v7_leakage_mon_S27.suggest_down` and `.suggest_up` are routed to `uio[7:6]`
alongside `v7_dvfs_ctrl_S14.dvfs_tier[1:0]` on `uio[1:0]`. The host-side DVFS
controller (off-chip) reads both signals to drive `clk_in` scaling.

### S-28 → S-14 stochastic enable
`v7_stoch_mac_S28.stoch_enable` is driven by a threshold comparator on
`v7_dvfs_ctrl_S14.dvfs_tier`: asserted when `tier == 2'b00` (lowest power mode).

### S-38 level-shifter and S-15 LDO
`v7_vstack_S38` level-shifters and `v7_pwr_island_S15` isolation cells are
co-designed: S-15 provides the 0.9 V island boundary; S-38 stacks two such
islands to halve the external supply current. The mid-rail (VDD_MID = 0.9 V)
is shared.

---

## Compliance Checklist

- [x] No `*` token in any synthesisable RTL module
- [x] R5 honesty — all metrics are predictions under falsification gates
- [x] Apache-2.0 SPDX header in every module
- [x] PhD anchor `φ² + φ⁻² = 3` in every module header
- [x] `` `default_nettype none `` at top of every module file
- [x] `// G-N FALSIFICATION: <condition>` comment in every module
- [x] S-29 RBB: `body_bias_level[3:0]` output + SPICE-anchor comment block
- [x] S-38 VStack: mid-rail driver model + level-shifter wrappers + SPICE-anchor
- [x] S-42 ReGate: sleep transistor enable driven from S-16 `nz_detect`; 1-cycle FSM
- [x] S-43 Latch: explicit `latch` module with transparent latch + alpha/beta phase split
- [x] S-28 Stochastic: XNOR + counter bit-stream multiplier

---

*Co-Authored-By: Trinity Agent <agent@trinity.local>*  
*φ² + φ⁻² = 3 · TRINITY · NEVER STOP · DOI 10.5281/zenodo.19227877*
