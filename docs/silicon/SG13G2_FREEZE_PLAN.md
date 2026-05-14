# SG13G2 Silicon Freeze Plan — Wave-10a 2×2 GF16 Mesh

**TRL-7 / 2027 MPW Freeze Preparation**  
**PDK:** IHP SG13G2 — 130 nm BiCMOS (Apache-2.0 open-source)  
**Top module:** `gf16_mesh_2x2_top`  
**Author:** Dmitrii Vasilev \<admin@t27.ai\>  
**SPDX-License-Identifier:** Apache-2.0

---

## 1. Target Specifications

| Parameter | Value | Notes |
|-----------|-------|-------|
| Target frequency | **250 MHz** | 4.00 ns clock period |
| Clock uncertainty | 0.20 ns | 150 ps skew + 50 ps jitter |
| Die area | **1.2 × 1.2 mm** | 1.44 mm² |
| Core area | 1.08 × 1.08 mm | 60 µm margin all sides |
| Technology | IHP SG13G2 130 nm BiCMOS | sg13g2_sc9rs_hd std-cell lib |
| Tiles | 4 × `trinity_gf16_tile` (GF16 dot4) | NW/NE/SW/SE quadrants |
| Router | 1 × `trinity_router_2x2` | Central 120 × 120 µm region |
| SRAM bridge | 1 × `sram_ternary_bridge` | West strip, 120 × 1080 µm |
| Supply voltage | 1.2 V (core) / 3.3 V (IO) | SG13G2 nominal |

---

## 2. Area Budget Estimate

| Block | Estimated Cells | Estimated Area (µm²) |
|-------|----------------|----------------------|
| `trinity_gf16_tile` × 4 | ~2 000 std-cell eq. each | 4 × 38 000 = 152 000 |
| `trinity_router_2x2` | ~500 sce | 8 000 |
| SRAM bridge + pads | SRAM macro + glue | ~30 000 |
| PDN / IO ring / margins | — | ~30 000 |
| **Total (estimate)** | **~8 500 sce** | **~220 000 µm² (0.22 mm²)** |

Core utilisation estimate: ~19 % of 1.166 mm² usable core.  
Comfortable margin for post-synthesis growth and CTS buffers.

---

## 3. Power Budget Estimate (250 MHz, 1.2 V)

| Domain | Estimate | Method |
|--------|----------|--------|
| Dynamic (tiles × 4) | ~12 mW | 0.5 × α × C × V² × f, α=0.2 |
| Dynamic (router) | ~1 mW | same method |
| Static leakage | ~2 mW | SG13G2 130 nm leakage estimate |
| IO / SRAM bridge | ~3 mW | |
| **Total estimate** | **~18 mW** | Best-effort pre-PnR |

> Note: Power numbers are pre-PnR estimates only. Accurate numbers require  
> post-PnR netlist simulation with SG13G2 liberty characterisation data.

---

## 4. 2027 MPW Submission Window

IHP SG13G2 runs through the [IHP Open MPW programme](https://www.ihp-solutions.com/technology/sg13g2/).  
Target submission window: **Q2 2027** (April–June 2027).

Key milestones:

| Milestone | Target Date | Status |
|-----------|-------------|--------|
| RTL freeze (Wave-10a) | 2026-Q3 | In progress |
| Constraint set complete (Wave-11a) | 2026-Q3 | This PR |
| Synthesis + STA baseline | 2026-Q4 | Pending |
| Place-and-route draft | 2026-Q4 | Pending |
| LVS/DRC clean | 2027-Q1 | Pending |
| Tape-out GDS submission | 2027-Q2 | Target |
| MPW shuttle return (estimate) | 2027-Q4 | Pending |

---

## 5. Freeze Readiness Checklist

### RTL / Constraints
- [x] `gf16_mesh_2x2_top` top-level Verilog present (`src/gf16_mesh_2x2_top.v`)
- [x] `create_clock -period 4.00 -name clk` in `constraints/sg13g2/timing.sdc`
- [x] Input/output delay margins (25 % of period = 1.00 ns) set on all ports
- [x] `set_clock_uncertainty 0.20` applied
- [x] False path on async reset (`rst_n`)
- [x] Multicycle path 2× on NoC req/ack handshake stubs
- [x] Floorplan stub with 6 named regions (NW/NE/SW/SE tiles, router, SRAM bridge)
- [x] SRAM bridge placed on west side

### Open Items — Must Resolve Before Tape-Out
- [ ] **STA sign-off**: Run full synthesis with SG13G2 liberty files; confirm all WNS/TNS ≤ 0
- [ ] **SRAM macro selection**: Choose IHP SG13G2 compatible SRAM macro or custom SRAM compiler output
- [ ] **IO ring**: Define padring (VDD/VSS, clk input buffer, data IO pads)
- [ ] **DRC/LVS**: Full clean required before GDS submission
- [ ] **Antenna rules**: SG13G2 antenna violation check on all metal layers
- [ ] **ESD protection**: Verify IO pad ESD compliance per IHP design rules
- [ ] **Clock tree synthesis**: CTS with SG13G2 library; verify 150 ps skew budget
- [ ] **PDN analysis**: EM/IR drop with actual current density
- [ ] **Thermal review**: 18 mW estimate; verify no hot-spot risk on 130 nm process
- [ ] **Signoff corner**: Confirm slow/fast corners; min-path hold check
- [ ] **GDSII export**: Merge all layers; validate against IHP layer map
- [ ] **MPW submission checklist**: Complete IHP submission form; confirm die size fits allocated area

### Nice-to-Have (Post-First-Spin)
- [ ] Formal equivalence check (RTL vs gate-level netlist)
- [ ] UPF/CPF multi-voltage domain spec
- [ ] BIST insertion for SRAM

---

## 6. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| STA fails at 250 MHz | Medium | High | Reduce to 200 MHz fallback; insert pipeline stage in tile |
| SRAM macro unavailable | Low | High | Use register-file fallback; engage IHP SRAM compiler |
| Area exceeds allocated MPW slot | Low | Medium | Core utilisation estimate ~19 %; 5× headroom |
| IHP PDK updates break constraints | Low | Low | Pin PDK version; re-verify before submission |
| 2027 Q2 window missed | Low | Medium | Target Q4 2027 as fallback shuttle |

---

## 7. References

- IHP SG13G2 PDK: <https://github.com/IHP-GmbH/IHP-Open-PDK>
- OpenROAD Flow: <https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts>
- Wave-10a RTL: `src/gf16_mesh_2x2_top.v` (this repo, feat/tri1-v2-mesh-2x2)
- SDC constraints: `constraints/sg13g2/timing.sdc` (this PR)
- Floorplan stub: `constraints/sg13g2/floorplan.tcl` (this PR)
- IHP Open MPW programme: <https://www.ihp-solutions.com/technology/sg13g2/>

---

*Document maintained by Dmitrii Vasilev \<admin@t27.ai\> — Wave-11a, L-S41*
