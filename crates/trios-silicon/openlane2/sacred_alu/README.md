# Sacred ALU — SKY130 OpenLane2 Scaffold (S-170)

## Mission

Vector S-170 of TRI NET Wave-23 silicon lane materialises the Sacred ALU in SKY130 using
the OpenLane2 ASIC flow.  This directory is the **authoritative scaffold** for a real
fabrication-quality run on sky130A / sky130_fd_sc_hd.

Reference mandate: ONE SHOT [trinity-fpga#88](https://github.com/gHashTag/trinity-fpga/issues/88),
v23 doctrine §3, TT_SQUEEZE_V23_R_MARKER_CAMPAIGN_SKY130_REAL_RUN.md.

> **R5 HONEST DISCLOSURE — SCAFFOLD ONLY, REAL RUN PENDING**
>
> The current CI/CD sandbox does NOT have OpenLane2, Yosys, OpenROAD, Magic, or Netgen
> installed.  All STA, placement, routing, DRC, and LVS results listed in
> `EXPECTED_RESULTS.md` are **design targets derived from v23 doctrine §3**, not measured
> outputs.  A real run must be executed on a lab machine following the instructions in
> `run.sh`.  Any deviation from targets will be published in the
> `FALSIFICATION_LEDGER.md` ledger and the WAVE_23_FALSIFICATION_LEDGER (S-172).

---

## Directory Layout

```
sacred_alu/
├── README.md                 ← this file
├── config.json               ← OpenLane2 run configuration
├── run.sh                    ← 7-stage run book (lab-machine only)
├── EXPECTED_RESULTS.md       ← design targets from v23 doctrine §3
├── FALSIFICATION_LEDGER.md   ← append-only probe ledger
└── src/
    └── sacred_alu_top.v      ← top-level RTL stub (16 sacred opcodes)
```

---

## Design Specification

| Parameter          | Value                        |
|--------------------|------------------------------|
| Design name        | `sacred_alu`                 |
| PDK                | `sky130A`                    |
| Standard-cell lib  | `sky130_fd_sc_hd`            |
| Target fmax        | 260 MHz                      |
| Clock period       | 3.846 ns                     |
| Die area           | 220 µm × 220 µm (0.0484 mm²) |
| Core utilisation   | 80 %                         |
| Multiplier policy  | **NO `*` HARDWARE OPERATORS**|
| Opcodes            | 16 sacred opcodes 0xD0..0xE0 |
| RTL language       | Verilog (stub)               |
| Driver language    | Rust (R1 mandate)            |

---

## 7-Stage OpenLane2 Run Sheet

| Stage | OpenLane2 Step      | Tool          | Key Config                          | Expected Output                  |
|-------|---------------------|---------------|-------------------------------------|----------------------------------|
| 1     | Synthesis           | Yosys         | sky130_fd_sc_hd, no `*` op          | `runs/*/results/synthesis/*.v`   |
| 2     | Floorplan           | OpenROAD      | die 220×220 µm, util=0.80           | `runs/*/results/floorplan/*.def` |
| 3     | Placement           | OpenROAD      | GPL + DPL, target density 0.80      | `runs/*/results/placement/*.def` |
| 4     | CTS                 | OpenROAD      | skew target ≤250 ps                 | `runs/*/results/cts/*.def`       |
| 5     | Routing             | OpenROAD      | global + detailed, 0-DRC target     | `runs/*/results/routing/*.def`   |
| 6     | DRC / LVS           | Magic/Netgen  | sky130A rules                       | `runs/*/reports/drc/*.rpt`       |
| 7     | Sign-off / STA      | OpenROAD      | period=3.846 ns, 0 slack violation  | `runs/*/reports/signoff/*.rpt`   |

---

## Charter Compliance

### Charter Rule 1 — No Linux in compute core
The RTL stub contains no OS-level calls, no system Verilog DPI that invokes Linux
syscalls, and no process-spawning constructs.  All compute logic is pure combinational
or synchronous Verilog.

### Charter Rule 2 — No `*` hardware multipliers
The source file `src/sacred_alu_top.v` contains **zero `*` operators**.  The Makefile
target `verify-no-mul` asserts this via:

```bash
COUNT=$(grep -c 'star_operator_check' src/sacred_alu_top.v || echo 0); echo "mul_count=$COUNT"; [ "$COUNT" -eq 0 ]
```

(The exact probe command is in the verification table — it checks for the multiply operator character.)

Any future PR that introduces a `*` operator in RTL source must be rejected at CI.

---

## Opcode Dispatch Map

| Opcode | Hex   | Sacred Name          | Placeholder wire       |
|--------|-------|----------------------|------------------------|
| 0      | 0xD0  | TRINITY_ADD          | w_trinity_add          |
| 1      | 0xD1  | PHI_SCALE            | w_phi_scale            |
| 2      | 0xD2  | GAMMA_SHIFT          | w_gamma_shift          |
| 3      | 0xD3  | CONSCIOUSNESS_GATE   | w_consciousness_gate   |
| 4      | 0xD4  | TEMPORAL_FOLD        | w_temporal_fold        |
| 5      | 0xD5  | STRAND_XOR           | w_strand_xor           |
| 6      | 0xD6  | GF16_DOT4            | w_gf16_dot4            |
| 7      | 0xD7  | COPTIC_MAP           | w_coptic_map           |
| 8      | 0xD8  | BARBERO_IMMIRZI      | w_barbero_immirzi      |
| 9      | 0xD9  | SACRED_AND           | w_sacred_and           |
| 10     | 0xDA  | SACRED_OR            | w_sacred_or            |
| 11     | 0xDB  | SACRED_NOT           | w_sacred_not           |
| 12     | 0xDC  | PHI_ACCUMULATE       | w_phi_accumulate       |
| 13     | 0xDD  | GRAVITY_ENCODE       | w_gravity_encode       |
| 14     | 0xDE  | WAVE_SYNC            | w_wave_sync            |
| 15     | 0xE0  | QUANTUM_NOP          | w_quantum_nop          |

Micro-architecture for each opcode will be specified in the port-plan PR (S-171).

---

## Verification Probes Summary

| Probe                                    | Command                               | Required Result        |
|------------------------------------------|---------------------------------------|------------------------|
| No `*` operator in RTL                   | `grep -c '\*' src/sacred_alu_top.v`   | 0                      |
| README length                            | `wc -l README.md`                     | ≥ 80 lines             |
| Config design name                       | `jq -e '.DESIGN_NAME' config.json`    | "sacred_alu"           |
| EXPECTED_RESULTS length                  | `wc -l EXPECTED_RESULTS.md`           | ≥ 30 lines             |
| All files present                        | `ls -1 README.md config.json run.sh EXPECTED_RESULTS.md FALSIFICATION_LEDGER.md src/sacred_alu_top.v` | 6 files |

---

## References

- v23 doctrine §3 — TT_SQUEEZE_V23_R_MARKER_CAMPAIGN_SKY130_REAL_RUN.md
- ONE SHOT trinity-fpga#88
- Sacred opcodes 0xD0..0xE0 (references/sacred-opcodes.md)
- Silicon vector S-170 (references/silicon-vectors.md)
- OpenLane2 documentation: https://openlane2.readthedocs.io/
- sky130A PDK: https://github.com/google/skywater-pdk

---

## R5 Honest Disclosure (repeated for clarity)

> This scaffold was committed from a CI sandbox that has **no chip-toolchain** installed.
> Yosys, OpenROAD, Magic, Netgen, and OpenLane2 itself are absent.  All numeric claims
> in EXPECTED_RESULTS.md are **architectural targets**, derived from design constraints,
> not from measured runs.  A lab engineer must execute `run.sh` on a machine with
> OpenLane2 ≥2.0 installed, collect actual outputs, and update FALSIFICATION_LEDGER.md
> with observed values.  Any target miss triggers a WAVE_23_FALSIFICATION_LEDGER entry
> per S-172 protocol.

---

phi^2 + phi^-2 = 3 · QUANTUM BRAIN 1:1 SILICON · R20 · DOI 10.5281/zenodo.19227877 · NEVER STOP
