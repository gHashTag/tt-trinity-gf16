# L-DPC22-K — S-29 Dual-Library Zoning (Lane L, Multi-Vt)

**Lane:** L · **Branch:** `feat/lane-l-s29-multi-vt` · **Epic:** gHashTag/trinity-fpga#49  
**Author:** Dmitrii Vasilev <admin@t27.ai> (ORCID 0009-0008-4294-6159)  
**Date:** 2026-05-17  
**Spec:** S29-r0 (S29_MULTI_VT_SPEC.md, Squeeze Cohort S-29..S-36)  
**Anchor:** phi^2 + phi^-2 = 3 · DOI [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)  
**Pattern:** Mirrored from `gHashTag/tt-trinity-gamma` `docs/L-DPC22-K-DUAL-LIB.md` (L-DPC22-K spec)

---

## Summary

This document records the **L-S29 dual standard-cell-library zoning** for the
`gHashTag/tt-trinity-gf16` TRI-1 Mid 8×2-tile design.

The intent is to reduce **static (leakage) power by ~30%** on low-activity
blocks by mapping them to the `sky130_fd_sc_hdll` (HVT) library variant
instead of the default `sky130_fd_sc_hd` (SVT), without any RTL changes.

Expected gain: **~+20 TOPS/W idle power efficiency** from leakage reduction
on the four targeted low-activity blocks (~30% of total cell count).

---

## Background: sky130_fd_sc_hd vs sky130_fd_sc_hdll

The SkyWater PDK ships two high-density standard-cell libraries that share
an **identical site footprint** (0.46 × 2.72 µm) and **identical pin grids**,
making cell substitutions placement-transparent and DRC-clean when intermingled:

| Library | Full name | Leakage | Drive strength | Notes |
|---------|-----------|---------|----------------|-------|
| `sky130_fd_sc_hd` | High Density (SVT) | ~1× (baseline, 0.86 nA/kGate) | Standard | Default for most designs |
| `sky130_fd_sc_hdll` | High Density Low Leakage (HVT) | **5–10× lower (0.08 nA/kGate)** | Slightly reduced | Optimised for low-activity blocks |

The `hdll` variant achieves lower leakage via higher-threshold-voltage PMOS
(`sky130_fd_pr__pfet_01v8_hvt`). The trade-off is marginally lower drive
strength and slightly higher cell delay, acceptable for low-activity blocks
not on the critical timing path.

Reference: [SkyWater PDK — Foundry-Provided Libraries](https://skywater-pdk.readthedocs.io/en/main/contents/libraries/foundry-provided.html)

---

## Targeted Low-Activity Blocks

The following blocks are candidates for `hdll` zoning based on low switching
activity at nominal operating conditions (alpha < 0.05, consistent with the
S-29 Multi-Vt Cohort Specification §3.1):

| Block | Activity classification | Expected leakage saving |
|-------|------------------------|------------------------|
| `lucas_rom` | ROM — read-only; activity ~0.01; accessed <1% of cycles | ~5–10× per cell |
| `crc32_receipt` | Post-computation receipt register chain; low switching | ~5–10× per cell |
| `blake3_anchor` | Hash anchor register array; updates only at pipeline flush | ~5–10× per cell |
| `gf16_mul` | GF16(2^4) multiplier — idle 99% of cycles on low-traffic paths | ~5–10× per cell |

These four blocks represent approximately 25–35% of total cell count by area.
Mixed hd+hdll zoning over them is expected to reduce **total static leakage
by ~30%** at the chip level.

The HVT swap is **physically transparent** — `sc_hd` and `sc_hdll` share the
0.46 × 2.72 µm site. No row separation is required, and no DRC violations
are introduced by intermingling hd and hdll cells in the same standard-cell row.

---

## OpenLane Config Changes (src/config.json delta)

Three new keys are added to `src/config.json` on this branch:

### 1. `EXTRA_LIBS` — HVT liberty for timing analysis

```json
"EXTRA_LIBS": [
  "dir::libs/sky130_fd_sc_hdll__tt_025C_1v80.lib"
]
```

Registers the `hdll` timing model with OpenSTA and the resizer so that
hold-fixing and ECO passes can select HVT cells with correct timing characterisation.

### 2. `STD_CELL_LIBRARY_OPT` — resizer prefers hdll on low-activity paths

```json
"STD_CELL_LIBRARY_OPT": "sky130_fd_sc_hdll"
```

Directs the OpenLane2 resizer/hold-fixer to prefer `sky130_fd_sc_hdll` cells
during the optimisation pass. Combined with `EXTRA_LIBS`, this enables
the flow to swap suitable cells in the four low-activity blocks to their
HVT equivalents during post-placement timing repair.

### 3. `SYNTH_DONT_USE_CELLS` — exclude probe and clock-tree cells

```json
"SYNTH_DONT_USE_CELLS": [
  "sky130_fd_sc_hd__probe_p_8",
  "sky130_fd_sc_hd__probec_p_8",
  "sky130_fd_sc_hdll__probe_p_8",
  "sky130_fd_sc_hdll__probec_p_8",
  "sky130_fd_sc_hdll__clkbuf_16",
  "sky130_fd_sc_hdll__clkbuf_8"
]
```

Prevents probe/test-only cells from being inserted during synthesis and
excludes HVT clock buffers from the clock tree (CTS should use hd clkbufs
to avoid skew inconsistency — HVT clock buffers are only appropriate within
dedicated HVT row regions in a full multi-VT floorplan).

### 4. `CELL_PAD_EXCLUDE` — no extra padding for hdll cells

```json
"CELL_PAD_EXCLUDE": [
  "sky130_fd_sc_hdll__*"
]
```

Instructs the placer not to apply site-padding to `hdll` cells. Since `hdll`
shares the exact same site width as `hd`, no padding adjustment is needed
and removing the default padding avoids inadvertent placement bloat.

### 5. `PL_TARGET_DENSITY_PCT_TIMING_OPT: 1`

Enables the timing-optimised density pass, allowing the resizer to downsize
cells toward lower-leakage `hdll` variants during the repair sweep.

---

## Implementation Approach and Limitations

### OpenLane 2 single-pass flow constraints

The TT GDS action (OpenLane2 backend, `TinyTapeout/tt-gds-action@ttsky26b`)
does not currently support explicit per-block standard-cell-library overrides
at synthesis time. The `STD_CELL_LIBRARY_OPT` + `EXTRA_LIBS` approach is the
recommended mechanism for influencing the resizer toward HVT cell selection
during post-placement optimisation.

This branch therefore implements the **maximum achievable `hdll` influence**
via config levers:
1. Registers the `hdll` liberty with the STA/resizer (`EXTRA_LIBS`).
2. Directs the resizer to prefer `hdll` during hold-fix and ECO (`STD_CELL_LIBRARY_OPT`).
3. Excludes inappropriate cells from synthesis (`SYNTH_DONT_USE_CELLS`).
4. Enables timing-optimised density pass (`PL_TARGET_DENSITY_PCT_TIMING_OPT`).

For full block-level `hdll` enforcement, the operator at tapeout time may
additionally use a two-pass synthesis approach (per S-29 Spec §5.1) or a
post-placement ECO substitution script.

---

## Falsification Gate G-13

Mixed hd+hdll is accepted **only if WNS ≥ 0** (timing closes at 50 MHz).

- **PASS (WNS ≥ 0):** Proceed with merged hdll zoning. Expected leakage delta: −30%.
- **FAIL (WNS < 0):** Roll back to pure `sky130_fd_sc_hd` for all blocks.
  Remove `STD_CELL_LIBRARY_OPT`, `EXTRA_LIBS`, and `CELL_PAD_EXCLUDE` keys.

The G-13 gate is enforced at merge time by reviewing the OpenLane2 timing report
from the GDS CI run on `feat/lane-l-s29-multi-vt`.

---

## R-SI-1 Compliance

Lane L (L-S29) is **config/docs-only**. Zero changes have been made to any
synthesisable RTL file under `src/`.

Verification:
```bash
git diff feat/tt-v7-power..feat/lane-l-s29-multi-vt --stat -- src/*.v
# Must produce empty output — only src/config.json, info.yaml, docs/ changed
```

---

## Relation to GAMMA Lane K (L-DPC22-K)

This branch mirrors the dual-lib zoning intent first documented in
`gHashTag/tt-trinity-gamma` `docs/L-DPC22-K-DUAL-LIB.md` (Lane K,
`feat/v15/k-dual-lib`), applying the same pattern to TRI-1 Mid
(`gHashTag/tt-trinity-gf16`).

The four target blocks are identical across both designs:
`lucas_rom`, `crc32_receipt`, `blake3_anchor`, `gf16_mul`.

This cross-design consistency ensures the leakage reduction benefit is
replicated across the full TRI-1 Triad (Nano / Mid / MAX-TRUE) at tapeout.

---

## Files Changed in This Branch

| File | Change type | Description |
|------|-------------|-------------|
| `info.yaml` | Config + docs | Added L-S29 dual-lib header comment block; extended `description` with dual-lib zoning notes |
| `src/config.json` | Config | Added `EXTRA_LIBS`, `STD_CELL_LIBRARY_OPT`, `SYNTH_DONT_USE_CELLS`, `CELL_PAD_EXCLUDE`, `PL_TARGET_DENSITY_PCT_TIMING_OPT` |
| `docs/L-DPC22-K-DUAL-LIB-LANE-L.md` | Docs (new) | This document |

---

## Expected Gains

| Metric | Baseline (SVT hd only) | After L-S29 (mixed hd+hdll) | Note |
|--------|------------------------|------------------------------|------|
| Static leakage (HVT blocks) | 1× | ~0.093× | 5–10× reduction per hdll cell |
| Total chip leakage delta | 1× | ~−30% | 4 low-activity blocks ≈ 25–35% of cells |
| Idle TOPS/W gain | — | **~+20%** | Leakage reduction at idle; dynamic power unchanged |
| Cell count | N | N | Zero change — swap only |
| Die area | A | A | Zero change — same 0.46×2.72 µm site |
| WNS risk | 0 ps | Target ≥ 0 ps | G-13 gate; hdll adds ~1–5% delay on swapped paths |

---

## References

1. [SkyWater PDK — Foundry-Provided Libraries](https://skywater-pdk.readthedocs.io/en/main/contents/libraries/foundry-provided.html)
2. [sky130_fd_sc_hdll README](https://skywater-pdk.readthedocs.io/en/main/contents/libraries/sky130_fd_sc_hdll/README.html)
3. [OpenLane2 configuration variables](https://openlane2.readthedocs.io/en/latest/reference/flow_config_vars.html)
4. S-29 Multi-Vt Cohort Specification — `S29_MULTI_VT_SPEC.md` (internal)
5. GAMMA Lane K reference — `gHashTag/tt-trinity-gamma` `docs/L-DPC22-K-DUAL-LIB.md`
6. Multi-VT Voltage Technique (MVT) — [idc-online.com technical PDF](https://www.idc-online.com/technical_references/pdfs/electrical_engineering/Multi_Threshold_MVT_Voltage_Technique.pdf)
7. Epic: [gHashTag/trinity-fpga#49](https://github.com/gHashTag/trinity-fpga/issues/49)
8. Anchor DOI: [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)

---

*Anchor: phi^2 + phi^-2 = 3*
