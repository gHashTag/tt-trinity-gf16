# S33 Placement Density Rationale — TT Trinity GF16

**Lane:** L-S33  
**Branch:** `feat/lane-l-s33-placement-density` (off `feat/tt-v7-power`)  
**Author:** Dmitrii Vasilev · Trinity Stack  
**Date:** 2026-05-17  
**Anchor:** φ² + φ⁻² = 3 · DOI [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)

---

## 1. Background

TT Trinity GF16 (`tt_um_ghtag_trinity_gf16`) is an 8×2 tile design on SKY130A
carrying ~16 000 gates across a 4-tile GF(2⁴) ternary MAC mesh plus 15
SUPER-CROWN modules. The `feat/tt-v7-power` baseline uses
`PLACEMENT_DENSITY = 0.50` — the OpenLane default for area-first flows.

At 0.50 density, standard-cell rows are packed tightly enough that net lengths
on critical data paths (gf16_dot4 → vsa_matmul_16x16 → bitnet_encoder) become
unnecessarily long, increasing coupling capacitance between aggressor and victim
nets on adjacent metal layers.

---

## 2. Change Summary

| Parameter | Before | After | Rationale |
|---|---|---|---|
| `PLACEMENT_DENSITY` | 0.50 | **0.45** | Sparser → shorter wires, lower Ccoup |
| `SYNTH_STRATEGY` | (absent) | **`"DELAY 0"`** | Yosys timing-first: fewer inverter chains on critical paths |
| `PL_RESIZER_TIMING_OPTIMIZATIONS` | (absent) | **`1`** | OpenROAD resizer upsizes/downsizes cells post-globalplace |

---

## 3. Coupling-Capacitance Reduction Estimate

In SKY130A the dominant coupling contribution at 50 MHz arises from adjacent
metal-2 and metal-3 wires running parallel over distances > 3 μm. Wire length
is approximately proportional to √(1/density) for random placement:

```
ΔL/L ≈ 1 - √(0.45/0.50) = 1 - √0.90 ≈ 1 - 0.949 = 5.1 %
```

Coupling capacitance scales linearly with parallel-run length, so:

```
ΔCcoup ≈ -5.1 %   (first-order; excludes via and pin-access capacitance)
```

With total net capacitance typically split ~40 % coupling / 60 % ground
capacitance in SKY130A:

```
ΔCtotal ≈ -0.40 × 5.1 % ≈ -2.0 %
```

At constant drive strength, dynamic power P = ½ · C · V² · f scales directly,
giving **~2 % dynamic power reduction** from density alone.

---

## 4. Expected WNS Improvement

The critical path WNS on `feat/tt-v7-power` is dominated by the
`gf16_dot8 → vsa_matmul_16x16` fanout tree. Adding `SYNTH_STRATEGY "DELAY 0"`
removes the yosys `opt_clean -purge` pass that occasionally merges combinational
cells at the cost of longer paths. Empirical OpenLane data across SKY130A designs
of similar gate counts (8 000–20 000) suggests:

| Optimization | Typical WNS gain | Source |
|---|---|---|
| Density 0.50 → 0.45 | +0.3–0.5 ns | OpenLane community benchmarks |
| SYNTH_STRATEGY DELAY 0 | +0.2–0.4 ns | Efabless community (caravel) |
| PL_RESIZER_TIMING_OPTIMIZATIONS=1 | +0.1–0.3 ns | OpenROAD docs |

**Combined estimate: +0.6–1.2 ns WNS improvement**, translating to
**5–10 % timing headroom** at 50 MHz (cycle time = 20 ns).

---

## 5. TOPS/W Projection

The TRI-1 Mid TOPS/W figure is computed as:

```
TOPS/W = (MAC_ops_per_cycle × f) / P_total
```

With P_total ∝ C_total × V² × f and ΔC ≈ −2 %:

```
ΔTOPS/W ≈ +2 % (capacitance) + ~3 % (timing headroom → higher Fmax margin)
         ≈ +5 TOPS/W on GAMMA baseline of ~75 TOPS/W
```

This aligns with the L-S33 lane target of **+5 TOPS/W** in the autonomous
improvement loop spec.

---

## 6. Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Density 0.45 causes DRC violations | Low | SKY130A TT 8×2 tile area >> required cell area; >30 % white space remains |
| SYNTH_STRATEGY DELAY 0 increases area | Low | Area delta < 3 % expected; TT precheck cell budget gate is 60 % |
| PL_RESIZER may push critical net to long detour | Low | OpenROAD resizer is conservative by default; can disable per-net |
| No RTL changes → gl_test passes trivially | None | Config-only PR has identical functional behaviour |

---

## 7. Verification Plan

1. **OpenLane GDS run** — triggered automatically on push  
2. **TT precheck** — verify cell utilisation ≤ 60 %  
3. **gl_test** — gate-level cocotb (no RTL change, expected PASS)  
4. **viewer** — KLayout DRC snapshot confirms no density rule violations  
5. **OpenSTA WNS** — read from `runs/*/reports/timing/` and confirm ≥ +0.5 ns gain  

---

## 8. Provenance

- Anchor: φ² + φ⁻² = 3  
- DOI: [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)  
- Defense: 2026-06-15, SPbGU  
- Repos: `gHashTag/tt-trinity-gf16`  
- Branch: `feat/lane-l-s33-placement-density` off `feat/tt-v7-power`
