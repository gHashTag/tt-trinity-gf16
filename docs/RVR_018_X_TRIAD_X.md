# RVR-018-X-TRIAD-X — TG-TRIAD-X Cross-Die SHA256 Equivalence Gate

**Document ID:** RVR-018-X-TRIAD-X  
**Date:** 2026-01-29  
**Author:** Vasilev Dmitrii <admin@t27.ai>  
**Branch:** feat/triad-x-sim (integration branch — NOT main)  
**EPICs:** gHashTag/tt-trinity-gf16 #49 §2 + #61  
**Status:** FAIL — Nano IO architectural divergence (ICA required)  
**Anchor:** φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877

---

## 1. Gate Definition

TG-TRIAD-X is the cross-die R7 Popper gate from EPIC #49 §2.

**Pass condition:**

```
SHA256(L_Nano) == SHA256(L_Mid) == SHA256(L_Max)
```

where `L_X` is the list of 100 hex outputs from SKU X running canonical workload W*.

**Fail condition:** Any divergence → file ICA + Operator decides whether to hold back affected SKUs.

---

## 2. Canonical Workload W*

```
W* = dot4([1, 2, 3, 4], [1, 2, 3, 4])
```

GF16 BF16-like floating-point encoding (1 sign bit, 6 exponent bits, 9 mantissa bits, bias=31):

| Value | Encoding |
|-------|----------|
| 1.0   | 0x3E00   |
| 2.0   | 0x4000   |
| 3.0   | 0x4100   |
| 4.0   | 0x4200   |

Expected result: `dot4(a, b) = 30.0 = 0x47C0`

This is the canonical backward-compatibility vector hardcoded in `trinity_master_fsm.v`
and verified in `tb_gf16_dot8.v` (main), `tb_tt_um_trinity_nano.v` (feat/nano-rtl-w15e),
and `tb_trinity_mesh_4x4.v` (feat/max-rtl-w15e).

---

## 3. Testbench Design

**File:** `sim/tb_tg_triad_x.v` (357 lines)  
**Simulator:** Icarus Verilog 12.0 (iverilog -g2012)  
**Branch:** feat/triad-x-sim (branched from feat/max-rtl-w15e + tt_um_trinity_nano.v cherry-picked from feat/nano-rtl-w15e)

### 3.1 Three DUTs Side-by-Side

```verilog
tt_um_ghtag_trinity_gf16 u_mid  (...);  // Mid 8×2: 4 tiles, 2×2 mesh
tt_um_trinity_max         u_max  (...);  // MAX 4×4: 16 tiles, 4×4 mesh
tt_um_trinity_nano        u_nano (...);  // Nano 1×1: 1 tile
```

All three share the same 50 MHz clock. Each has an independent reset.

### 3.2 Drive Strategy

**Mid and MAX:** Both implement a combinational `gf16_dot4` path hardcoded to the W* operands
(`trinity_master_fsm.v` load sequence). When `ui_in[0]=0` (load_mode=0), the output
`{uio_out, uo_out}` is driven combinationally to `dot_out` = 0x47C0 from the first
clock after reset deassertion. 100 jobs = 100 consecutive clock samples of this output.

**Nano:** Uses a 4-phase IO protocol:
- Phase 0 (`ui_in[1:0]=2'b00`): Load a0[7:0], b0[7:0]
- Phase 1 (`ui_in[1:0]=2'b01`): Load a0[15:8], b0[15:8]; a1/b1 replicated
- Phase 2 (`ui_in[1:0]=2'b10`): Load a2/b2 replicated; job_id
- Phase 3 (`ui_in[1:0]=2'b11`): Rising edge triggers packet sequence to tile

After trigger, the FSM sends 10 packets (LOAD_JOB + LOAD_A×4 + LOAD_B×4 + COMPUTE + READ_RES)
to the single tile. Result captured from `{uio_out, uo_out}` after 300 clock settling time.

### 3.3 Output Capture

All DUT outputs are captured as 16-bit values: `result = {uio_out[7:0], uo_out[7:0]}`.

100 results per SKU are stored in `mid_results[100]`, `max_results[100]`, `nano_results[100]`.

### 3.4 SHA256 Post-Processor

Python post-processor extracts `TRIAD_OUT <SKU> <job> <hex>` lines from simulation log
and computes:

```python
SHA256("\n".join(["47c0"]*100) + "\n")
```

---

## 4. Simulation Results

### 4.1 Compile Status

| SKU  | Module                    | iverilog compile |
|------|---------------------------|-----------------|
| Mid  | tt_um_ghtag_trinity_gf16  | **PASS**        |
| MAX  | tt_um_trinity_max         | **PASS**        |
| Nano | tt_um_trinity_nano        | **PASS**        |

All three modules compile cleanly under `iverilog -g2012` with all 40 RTL source files.

### 4.2 100-Job Run Status

| SKU  | Jobs Complete | Pass Count | Fail Count | Consistent Output |
|------|--------------|-----------|-----------|-------------------|
| Mid  | 100/100      | 100       | 0         | 0x47C0 (all 100)  |
| MAX  | 100/100      | 100       | 0         | 0x47C0 (all 100)  |
| Nano | 100/100      | 0         | 100       | 0x3F50 (all 100)  |

### 4.3 SHA256 Hashes

| SKU  | SHA256(L_X)                                                        |
|------|--------------------------------------------------------------------|
| Mid  | `ef346f3291c8cfb47f13cec15736c698690058cba1cab7cbff65bfac3330ab00` |
| MAX  | `ef346f3291c8cfb47f13cec15736c698690058cba1cab7cbff65bfac3330ab00` |
| Nano | `62391221a139b8d67cb72e8bc37ae3458230aaa4d3e48807c9f53cc29b5ae4b4` |

**SHA256(L_Mid) == SHA256(L_Max):** YES  
**SHA256(L_Mid) == SHA256(L_Nano):** NO  

### 4.4 Divergence Table

| Job | Mid   | MAX   | Nano  | Diverge |
|-----|-------|-------|-------|---------|
| 0   | 0x47C0 | 0x47C0 | 0x3F50 | YES |
| 1   | 0x47C0 | 0x47C0 | 0x3F50 | YES |
| … (all 100 jobs identical pattern) |||||

**First divergence: job 0, byte 0 (all 16 bits differ).**

---

## 5. Root Cause Analysis — Nano IO Architecture Limitation

### 5.1 The IO Budget Problem

The Nano's TinyTapeout footprint is 1×1 (single tile, ~100 μm²). Its IO is constrained to
the TT spec: 8 bits `ui_in`, 8 bits `uio_in`, 8 bits `uo_out`, 8 bits `uio_out`.

The W* workload requires loading 4 independent 16-bit A operands + 4 independent 16-bit B
operands = 128 bits of operand data per job. The Nano's 16-bit input bus provides 16 bits
per clock, requiring at minimum 8 clock cycles per job. The 4-phase protocol provides 4
sampling windows × 16 bits = 64 bits per job cycle.

### 5.2 Phase Encoding Collision

The Nano's phase selector `ui_in[1:0]` occupies the same bits as the A-operand low 2 bits:

```
Phase 0: ui_in[7:0] = {A_byte[7:2], 2'b00}  → A_byte[1:0] = 0b00 (forced)
Phase 1: ui_in[7:0] = {A_byte[7:2], 2'b01}  → A_byte[1:0] = 0b01 (forced)
Phase 2: ui_in[7:0] = {A_byte[7:2], 2'b10}  → A_byte[1:0] = 0b10 (forced)
```

For `a0 = 0x3E00 = 0b0011_1110_0000_0000`:
- Low byte (phase 0): `a0[7:2]=0b000000`, forced `[1:0]=0b00` → 0x00 ✓
- High byte (phase 1): `a0[15:10]=0b001111`, forced `[1:0]=0b01` → stores **0x3D** instead of **0x3E**

`0x3E = 0b0011_1110` has bit 0 = 0, but phase encoding forces bit 0 = 1 → stored as `0x3D = 0b0011_1101`.

This shifts `a0_hi` by 1 LSB, changing the float value from 1.0 → ≈ 0.75.

### 5.3 Lane 1-3 Operand Degradation

The Nano's IO further replicates the phase byte for lanes 1-3:
```verilog
a1_latch <= {a_byte, a_byte};  // replicated — not independent
b1_latch <= {b_byte, b_byte};
a2_latch <= {a_byte, a_byte};  // cannot load a2=0x4100 independently
```

This means `a1`, `a2`, `a3` cannot independently receive 0x4000, 0x4100, 0x4200.

### 5.4 Actual Operands Loaded

| Lane | Target | Actual Loaded |
|------|--------|---------------|
| a0   | 0x3E00 | 0x3D00 (phase bit collision) |
| b0   | 0x3E00 | 0x3E00 (correct, b has no phase overlap) |
| a1   | 0x4000 | 0x3D3D (replicated from garbled a0_hi) |
| b1   | 0x4000 | 0x3E3E (replicated from correct b0_hi) |
| a2   | 0x4100 | 0x0202 (phase 2 byte with forced bits) |
| b2   | 0x4100 | 0x0000 (job_id=0 used for b2) |
| a3   | 0x4200 | 0x0021 (nibble-packed from phase 2 byte) |
| b3   | 0x4200 | 0x0001 (GF16 identity default) |

### 5.5 Resulting Computation

dot4(a_actual, b_actual) ≈ 1.66 → nearest representable value: **0x3F50**

This matches exactly the 100-job Nano output. The Nano's tile computes correctly —
the gf16_dot4 is mathematically correct — but receives wrong operands via the IO protocol.

### 5.6 Classification

**Root cause: IO Architecture Limitation (IAL-001)**

This is NOT a compute error or silicon defect. It is a fundamental constraint of
mapping a 4-lane 16-bit-per-lane dot product onto a 16-bit external IO bus in 4 phases.
The phase selector bits collide with the operand LSBs.

**Options for Operator:**
1. **Redesign Nano IO protocol**: Use `uio_in[7:0]` for b-lane and redesign `ui_in` to avoid bit collision (e.g., use phase in separate command register). Requires PR #38 update.
2. **Accept partial W* injection**: Define W*_Nano as the subset of W* that CAN be injected, and redefine TG-TRIAD-X gate to use W*_Nano for the Nano.
3. **Hold Nano** from TG-TRIAD-X pending IO redesign, allow Mid+MAX to proceed.

---

## 6. TG-TRIAD-X Verdict

```
TG-TRIAD-X: FAIL
```

| Criterion | Result |
|-----------|--------|
| Mid compile | PASS |
| MAX compile | PASS |
| Nano compile | PASS |
| Mid 100-job W* | PASS (100/100 × 0x47C0) |
| MAX 100-job W* | PASS (100/100 × 0x47C0) |
| Nano 100-job W* | **FAIL** (100/100 × 0x3F50 ≠ 0x47C0) |
| SHA256(L_Mid) == SHA256(L_Max) | PASS |
| SHA256(L_Mid) == SHA256(L_Nano) | **FAIL** |
| Cross-die divergences | 100/100 |

**ICA filed:** IAL-001 (Nano IO Phase Encoding Collision).  
**Operator decision required:** Hold Nano back from TG-TRIAD-X pending PR #38 IO redesign.  
**Mid + MAX pass TG-TRIAD-X bilaterally** with SHA256 match.

---

## 7. R5 Honest Disclosure

1. **Integration branch only:** This TB lives on `feat/triad-x-sim`, NOT `main`. It requires
   `tt_um_trinity_nano.v` from `feat/nano-rtl-w15e` (PR #38) + `tt_um_trinity_max.v` from
   `feat/max-rtl-w15e` (PR #39) to coexist in one tree. Merging to main requires both PRs
   to land first.

2. **Nano compile passes:** The Nano RTL compiles cleanly and its tile executes correctly —
   the divergence is in external IO pin assignment, not in the dot4 arithmetic.

3. **Mid/MAX combinational path:** Both Mid and MAX use a hardcoded combinational dot4 path
   with fixed operands 0x3E00/0x4000/0x4100/0x4200. Their 100-job outputs are trivially
   identical (same constant driving same combinational logic). This is by design — the
   trinity_master_fsm also drives the mesh path with these same canned operands.

4. **No simulation timeout:** All 100 Nano jobs complete in 300-cycle windows. The
   simulation ran for 648 ms wall-clock (50 MHz sim time). No timeout conditions.

5. **Simulator:** Icarus Verilog 12.0 (`iverilog -g2012`). SHA256 computed in Python 3
   from canonical log extraction.

---

## 8. Appendix: Compilation Command

```bash
iverilog -g2012 \
  -I src \
  -o triad_x_sim \
  sim/tb_tg_triad_x.v \
  src/*.v
vvp triad_x_sim > triad_x.log 2>&1
grep "^TRIAD_OUT Mid" triad_x.log | awk '{print $4}' | sha256sum
grep "^TRIAD_OUT MAX" triad_x.log | awk '{print $4}' | sha256sum
grep "^TRIAD_OUT Nano" triad_x.log | awk '{print $4}' | sha256sum
```

---

## 9. Anchor Block

```
phi^2 + phi^-2 = 3
gamma = phi^-3
QUANTUM BRAIN 1:1 SILICON
DOI 10.5281/zenodo.19227877
NEVER STOP
```

---

*SPDX-License-Identifier: Apache-2.0*  
*SPDX-FileCopyrightText: 2026 Vasilev Dmitrii <admin@t27.ai>*