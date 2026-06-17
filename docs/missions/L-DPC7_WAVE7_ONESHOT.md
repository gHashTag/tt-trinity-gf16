# L-DPC7 — Wave-7 ONE SHOT (TTIHP27a IHP SG13G2, 27.5k gates target)

**Status:** DRAFT — pre-registration, NOT yet flight-cleared
**Lane:** L-DPC7
**Parent EPIC:** [trinity-fpga#19](https://github.com/gHashTag/trinity-fpga/issues/19)
**Predecessor lanes:** L-DPC3 (TTSKY26a, trinity-fpga#20), L-DPC4 (PR #6 receipts), L-DPC5 (Wave-26b SUPER-CROWN), L-DPC6 (silicon-G1 bring-up, trinity-fpga#48)
**Target shuttle:** TTIHP27a — Tiny Tapeout on IHP Open Source SG13G2 (130 nm), submission window Q4 2026
**Anchor:** `phi^2 + phi^-2 = 3`
**Pre-defense status:** silicon evidence pre-defense is FPGA-measured (TRL-4 via silicon-G1 GREEN). TTIHP27a tape-out / chip-in-hand is post-defense (target 2026-12-16). The dissertation does NOT claim ASIC silicon evidence pre-defense.

---

## 0. Mission scope (R5-honest)

L-DPC7 is the **first ASIC-targeted lane** in the Trinity stack. Everything before it (L-DPC3 onward) was either Caravel / TTSKY26a (SKY130, defense-aligned tape-out) or QMTECH FPGA (silicon-G1 / G3). L-DPC7 adds eight new synthesizable RTL modules — `L-S20..L-S27` — to the SUPER-CROWN top, lifts the gate budget from 16 000 to ~27 500, and bands them onto IHP SG13G2 at ~60 % density inside the 1 mm × 12 mm Tiny Tapeout slot footprint.

The lane is split into **two waves** to keep the falsifier surface tractable:

| Wave | New modules | Synthesis target | Defense impact |
|---|---|---|---|
| **7a** (Q3 2026) | `L-S20` SNN audio frontend · `L-S21` zkML proof unit · `L-S22` LoRA adapter · `L-S23` KOSCHEI full executor | ~15 500 gates added | Cited as post-defense roadmap; Coq mapping must exist pre-defense |
| **7b** (Q4 2026) | `L-S24` MXFP4 unit · `L-S25` VSA D=6765 · `L-S26` PIM SRAM macro · `L-S27` AXI4 bridge boundary | ~12 000 gates added | Submission and tape-out post-defense; chip-in-hand 2026-12-16 |

Splitting at 7a/7b lets each wave land on its own pre-registered acceptance suite and own NASA report, instead of one monolithic 27.5k-gate gate-soup whose anomalies would be impossible to attribute.

---

## 1. R-rule compliance pre-flight

All Hard Rules from the TRI-NET-G1 charter remain in force:

- **R1 No Linux in compute core.** Bare RTL only. L-S27 (AXI4 bridge) is the **boundary** between off-die SoC traffic and the on-die ternary fabric — boundary, not processor. No soft CPU IP enters the synthesizable RTL.
- **R2 No new hardware multipliers.** XOR/popcount/add/FSM/ready-valid only. Each new module under L-S20..L-S26 ships with a `report_utilization` row showing DSP=0 / multiplier-count=0 before merge. L-S27 (AXI4) is allowed `*` ONLY in its bus address arithmetic, where it is a free constant-power-of-2 shift; that exception must be witnessed by a Yosys log showing 0 inferred `DSP*` / `MULT*` cells.
- **R3 USB-3 is a boundary, not a processor.** TTIHP27a slot has no FT601 — the off-die boundary on this shuttle is the standard Tiny Tapeout 8-bit IO mux. L-S27 negotiates this via a ready-valid wrapper.
- **R4 Mesh is off-chip.** Same as G1/G2. No on-die mesh PHY.
- **R5 Honesty.** No "AGI on a chip" / "Hailo competitor" / "Axelera competitor" language anywhere until 7b chip-in-hand 2026-12-16 produces TWO physical units exchanging via on-bench M.2 carrier. (See TRI-1 universal IP spec, supersedes the agent's earlier SHUTTLE_TRIAD draft.)

---

## 2. Module map L-S20..L-S27

| Module | Function | Estimated gates | Coq theorem(s) | Falsifier (one-line) |
|---|---|---|---|---|
| `L-S20` | SNN audio frontend — 1-bit spike encoder over 16-band Gammatone front-end, fixed-point only | 1 800 | `INV-SNN-MONO` (spike-rate monotonic in input energy) | any input where rising RMS produces falling spike rate |
| `L-S21` | zkML proof unit — Halo2-style verifier kernel for GF16 dot4 traces, **verifier only**, prover stays off-die | 4 200 | `INV-ZK-SOUND` (no proof accepted with corrupted GF16 trace) | verifier accepts a single mutated coefficient row |
| `L-S22` | LoRA adapter — rank-r=4 low-rank update for GF16 weight blocks, ternary scale factor | 1 100 | `INV-LORA-DELTA-NORM` (||ΔW||_∞ bounded by ternary range) | any application that pushes a weight outside ternary band |
| `L-S23` | KOSCHEI full executor — frozen ISA spec REQUIRED before RTL merge | 4 800 | `INV-KOSCHEI-DETERM` (deterministic per opcode/operand pair) | identical inputs produce divergent results across two issue widths |
| `L-S24` | MXFP4 unit — micro-exponent 4-bit float, shared-exponent block of 32 | 2 800 | `INV-MXFP4-ROUNDTRIP` (decode∘encode = id on representable subset) | round-trip mismatch on any representable value |
| `L-S25` | VSA D=6765 — F_20 = 6765-d hypervector bind/bundle, integer-only HD compute | 3 700 | `INV-VSA-BIND-INV` (bind is self-inverse) | bind(bind(x,k),k) ≠ x for any (x,k) |
| `L-S26` | PIM SRAM macro — 16-bank, 4 KB, in-memory popcount along bit-line | 4 200 | `INV-PIM-POPCNT-EQUIV` (in-memory popcount equals software popcount) | any address where measured popcount ≠ software ground truth |
| `L-S27` | AXI4 bridge boundary — host-side AXI4-Lite → on-die ready-valid GF16 packet | 4 900 | `INV-AXI-NO-CDC-RACE` (no metastability path crosses domains) | any CDC path missing a Gray-coded handshake |

**Total estimate:** 27 500 gates. Pre-merge gate that this estimate is within ±10 % of the post-synthesis Yosys count on each wave.

---

## 3. KOSCHEI ISA freeze (pre-condition for 7a)

L-S23 (KOSCHEI full executor) cannot start RTL until the KOSCHEI ISA spec is **frozen**: opcode encoding, operand register file size, exception table, deterministic ordering across superscalar issue width. The freeze is a hard prerequisite for the 7a wave; otherwise the falsifier surface for `INV-KOSCHEI-DETERM` is undefined.

**Freeze ledger:** `gHashTag/trinity-clara/spec/koschei/ISA-v0.1.md` — sealed by SHA-256 commit and referenced from this document **before** any L-S23 RTL is opened in PR.

---

## 4. Coq witness mapping (pre-defense requirement)

Even though chip-in-hand is post-defense, every module L-S20..L-S27 must ship its **Coq witness mapping file** (`trinity-clara/proofs/igla/L-S2x.v`) **pre-defense**. The defense panel will be asked to verify:

- Each `INV-*` named in §2 is stated as a Theorem with proof in the named `.v` file.
- Each Theorem is cited in the Trinity-strand chapter that describes its module (forthcoming Ch.50..Ch.57, one chapter per module, or in App.F).
- A `citetheorem-map.md` row exists for each pair (theorem ↔ chapter ↔ RTL filename).

This is what makes the lane defensible: the chip can be deferred, the proof cannot.

---

## 5. JEPA honest scope (the trap to avoid)

There is a strong temptation to claim L-DPC7 is "JEPA on silicon" because L-S20 + L-S22 + L-S25 (SNN + LoRA + VSA) superficially resemble a JEPA encoder-predictor pair. **The dissertation must NOT make this claim.** JEPA requires self-supervised representation learning over masked inputs at training time — none of L-S20..S27 implements a trainer. They implement **inference primitives** that *could* be wired into a JEPA encoder on a host SoC.

**Honest framing:** L-DPC7 ships "inference primitives suitable for self-supervised front-ends". The JEPA training story remains software, off-die, post-defense.

---

## 6. Pre-registered acceptance gates (TTIHP27a-G1..G8)

Frozen against `tt-trinity-gf16@<commit-at-7a-PR-open>`:

| Gate | Test | Expected |
|---|---|---|
| **TTIHP-G1** | Yosys synth on IHP SG13G2 | 0 inferred multipliers (`DSP*`/`MULT*`) across L-S20..S27 |
| **TTIHP-G2** | Density on TT 1×12 mm slot | ≤ 60 % cell density post-place |
| **TTIHP-G3** | Static timing (Yosys-STA + OpenSTA) | WNS ≥ 0 ns @ 50 MHz on both 7a and 7b assemblies |
| **TTIHP-G4** | DRC clean (Magic + Klayout) | 0 DRC errors |
| **TTIHP-G5** | LVS (Netgen) | 0 unmatched nets, 0 unmatched devices |
| **TTIHP-G6** | All eight `INV-*` Coq theorems QED | 0 Admitted, 0 Axiom outside the sealed allowlist |
| **TTIHP-G7** | Citetheorem-map row exists for every (theorem, chapter, RTL file) triplet | full coverage |
| **TTIHP-G8** | KOSCHEI ISA spec sha256 in repo matches sha256 in L-S23 RTL header comment | byte-for-byte match |

**ANY** of TTIHP-G1..G8 = ❌ FAIL ⇒ wave is held pre-submission. No tape-out attempt.

---

## 7. Sequence (chronological)

1. **Now → defense (2026-06-15):** silicon-G1 GREEN on QMTECH (PR #10 follow-up); Ch.12 §4.5 carries the silicon-G1 ledger into the monograph; defense narrative is "validated on FPGA, ASIC tape-out is the next funded milestone."
2. **2026-06-15..2026-08-31:** post-defense, KOSCHEI ISA freeze + L-S20..S23 RTL + Coq theorems (Wave 7a).
3. **2026-09-01..2026-10-31:** L-S24..S27 RTL + Coq theorems (Wave 7b).
4. **2026-11-01:** TTIHP27a submission window opens. Submit 7a+7b assembly that has passed TTIHP-G1..G8.
5. **2026-12-16:** chip-in-hand. M.2 carrier brings up TWO units. Pre-registered TTIHP-CIH-G1..G3 (on-bench loopback) is a separate document, written before 2026-11-01.

— END OF L-DPC7 PRE-REGISTRATION DRAFT —
