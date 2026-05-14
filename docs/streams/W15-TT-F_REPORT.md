# W15-TT-F Stream Report — Async-lab + Self-Healing

**Stream:** W15-TT-F · Branch `feat/tt-v7-async-heal`
**Vectors:** S-22, S-23, S-34, S-35
**Wave:** W15 · TT-Shuttle Squeeze v7
**Anchor:** φ² + φ⁻² = 3 · Apache-2.0 · DOI [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)
**Status:** ✅ RTL delivered — 2026-05-17

---

## Honesty Notice

All modules in this stream implement a **self-healing model** for fault tolerance.
No claims of trusted execution, secure enclaves, or hardware security guarantees
are made. Every metric is a prediction bound by its falsification gate.

---

## Modules Delivered

### 1. `src/v7_async_handshake_S22.v` — S-22 Async Handshake
**Lines:** ~206 | **License:** Apache-2.0

Implements a 4-phase bundled-data handshake protocol for inter-tile dot32
data transfer. Supports clock-domain crossing via two-stage synchronisers on
both the request and acknowledge lines.

**4-phase protocol:**

| Phase | Sender | Receiver |
|-------|--------|----------|
| 0 | `req=0`, data stable (null) | idle |
| 1 | `req=1`, data valid | wait req, capture data, `ack=1` |
| 2 | `req=0` (after seeing ack) | wait req de-assert |
| 3 | idle, `send_ready=1` | `ack=0` (both lines reset) |

**Sender FSM states:** `IDLE → ASSERT_REQ → WAIT_ACK → DEASSERT_REQ → WAIT_NACK → IDLE`

**Receiver FSM states:** `IDLE → WAIT_REQ → CAPTURE → ASSERT_ACK → WAIT_DEASSERT → DEASSERT_ACK → IDLE`

**Parameters:** `DATA_W = 32` (dot32 transfer width, configurable)

**Gate hook G-22 FALSIFICATION:** async lane completes 1 000 dot4 ops without
handshake violations in simulation → else lane scheduled for Wave-16 follow-up.

---

### 2. `src/v7_c_element_S23.v` — S-23 Muller C-element
**Lines:** ~106 | **License:** Apache-2.0

Implements the Muller C-element gate primitive used as the fundamental
synchronisation element in Null Convention Logic (NCL) / 4-phase async pipelines.

**Boolean equation:**
```
out_next = (a & b) | (b & out) | (out & a)
```

Behaviour:
- **Set** (out→1): when both inputs high
- **Reset** (out→0): when both inputs low
- **Hold**: when inputs differ (hysteresis / memory)

**Variants provided:**

| Module | Description |
|--------|-------------|
| `v7_c_element` | 1-bit, clocked (synthesis-safe, feedback through FF) |
| `v7_c_element_latch` | 1-bit combinational model (SPICE / analogue simulation) |
| `v7_c_element_3` | 3-input generalised C-element (set when all=1, reset when all=0) |

**Gate hook G-23 FALSIFICATION:** C-element output matches majority(a, b, q_prev)
truth table on all 8 input combinations → else S-23 dropped.

---

### 3. `src/v7_fortalesa_tmr_S34.v` — S-34 FORTALESA Selective TMR Voter
**Lines:** ~159 | **License:** Apache-2.0

Selective Triple Modular Redundancy voter for 8-bit accumulator PEs, following
the FORTALESA methodology ([arXiv 2503.04426](https://arxiv.org/html/2503.04426v1)).

**TMR voter equation:**
```verilog
voted = (a & b) | (b & c) | (a & c)   // majority
err   = (a ^ b) | (b ^ c)              // any disagreement
```

**Architecture:**

- `v7_tmr_voter_1b` — single-bit majority voter cell
- `v7_tmr_voter_8b` — 8-bit voter (8 × `v7_tmr_voter_1b`, explicit instantiation)
- `v7_fortalesa_tmr_S34` — top-level selective wrapper (NUM_PE=4 by default)

**`protect_en` control (per-PE):**

| `protect_en[i]` | Behaviour |
|-----------------|-----------|
| `1` | TMR voter active — 3 redundant copies voted |
| `0` | Bypass — single `acc_a[i]` passed through (no area overhead) |

Per FORTALESA analysis: TMR on all 4 critical MAC PEs adds ~+12% area and
+12% power, but tolerates 1 stuck-at fault per PE.

**Gate hook G-34 FALSIFICATION:** stuck-at-0 fault injection on any TMR'd PE —
output remains correct → else TMR scope reduced or dropped.

---

### 4. `src/v7_auto_healer_S35.v` — S-35 Auto-Healer FSM
**Lines:** ~243 | **License:** Apache-2.0

Auto-Healer FSM that monitors PE error flags, bypasses faulty PEs via a hot-spare
mux, and measures MTTR (Mean Time to Repair). Implements fault injection port for
G-35 testbench validation.

**FSM states:**

```
NORMAL → FAULT_DETECT → BYPASS → RECOVER → NORMAL
                                 ↓ (3 retries failed)
                              PERMANENT
```

| State | Description |
|-------|-------------|
| `NORMAL` | All PEs healthy; monitoring error inputs |
| `FAULT_DETECT` | Error detected; latch faulted PE mask |
| `BYPASS` | Faulted PE replaced by spare; countdown 40 cycles |
| `RECOVER` | Test if fault cleared; retry up to 3× |
| `PERMANENT` | Fault declared permanent; bypass held indefinitely |

**MTTR timing (@ 1 GHz = 1 ns/cycle):**

| Event | Cycles | Latency |
|-------|--------|---------|
| Transient fault recovery | 40 | 40 ns |
| Permanent fault (3 retries) | 3 × 40 = 120 | 120 ns |

**Fault injection port:**
- `fault_inject[N]=1` forces `pe_err[N]=1` permanently (testbench / G-35 gate)

**Bypass mux:**
- Faulted PE output replaced by `spare_pe_out` in `healed_out`
- `bypass_active[N]` asserted while PE[N] is bypassed

**Parameters:** `NUM_PE=4`, `DATA_W=8`, `MTTR_CYCLES=40`, `MTTR_CNT_W=6`

**Gate hook G-35 FALSIFICATION:** inject permanent stuck-at fault on PE[3] →
recovery in ≤ 120 ns measured at output port → else Auto-Healer scope reduced.

---

## Falsification Gate Summary

| Gate | Condition | Rollback |
|------|-----------|----------|
| **G-22** | Async lane completes 1 000 dot4 ops without handshake violations | Move S-22 to Wave-16 |
| **G-23** | C-element matches majority(a,b,q_prev) truth table on all 8 combos | Drop S-23 |
| **G-34** | Stuck-at-0 on any TMR'd PE — voted output remains correct | Reduce TMR scope |
| **G-35** | Permanent fault on PE[3] → recovery ≤ 120 ns at output port | Reduce healer scope |

---

## Design Constraints Met

- [x] `\`default_nettype none` in all modules
- [x] No `*` in synthesisable RTL (all ports explicitly connected)
- [x] Apache-2.0 SPDX header in every file
- [x] 4-phase bundled-data signalling (S-22)
- [x] `out = ab + bc + ca` with feedback (S-23)
- [x] `out = (a&b)|(b&c)|(a&c)` voter, error `(a^b)|(b^c)` (S-34)
- [x] FSM states {NORMAL, FAULT_DETECT, BYPASS, RECOVER, NORMAL} (S-35)
- [x] 40-cycle MTTR @ 1 GHz = 40 ns (S-35)
- [x] Fault inject + bypass mux (S-35)
- [x] R5 honesty: "self-healing model" — no trusted execution claims

---

## File List

| File | Vectors | Lines |
|------|---------|-------|
| `src/v7_async_handshake_S22.v` | S-22 | ~206 |
| `src/v7_c_element_S23.v` | S-23 | ~106 |
| `src/v7_fortalesa_tmr_S34.v` | S-34 | ~159 |
| `src/v7_auto_healer_S35.v` | S-35 | ~243 |
| `docs/streams/W15-TT-F_REPORT.md` | All | — |

---

*φ² + φ⁻² = 3 · TRINITY · NEVER STOP · DOI 10.5281/zenodo.19227877*
*Co-Authored-By: Trinity Agent <agent@trinity.local>*
