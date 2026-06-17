# Sacred ALU SKY130 — Expected Results (Design Targets)

## R5 HONEST DISCLOSURE

> **ALL VALUES IN THIS FILE ARE ARCHITECTURAL TARGETS DERIVED FROM V23 DOCTRINE §3.**
> They are NOT measured results from an actual OpenLane2 run.  The sandbox used to
> produce this scaffold has no chip toolchain installed (no Yosys, no OpenROAD, no
> Magic, no Netgen).
>
> When a lab engineer executes `run.sh` on a machine with OpenLane2 ≥ 2.0 installed,
> they must record observed values in `FALSIFICATION_LEDGER.md`.  Any target miss
> triggers a WAVE_23_FALSIFICATION_LEDGER entry per S-172 protocol.

---

## Stage-by-Stage Targets

### Stage 1 — Synthesis

| Metric                        | Target              | Doctrine ref      |
|-------------------------------|---------------------|-------------------|
| Flow exit code                | 0 (clean)           | v23 §3.1          |
| `*` operator occurrences      | 0                   | Charter Rule 2    |
| Cell count (approx)           | ≤ 500 cells         | v23 §3.1          |
| Yosys WNS (pre-STA estimate)  | ≥ 0 ns              | v23 §3.1          |
| Synth log warnings            | 0 critical          | R5                |

### Stage 2 — Floorplan

| Metric                        | Target              | Doctrine ref      |
|-------------------------------|---------------------|-------------------|
| Die area (µm²)                | 48 400 (220×220)    | v23 §3.2          |
| Core utilisation              | 0.80 (80%)          | v23 §3.2          |
| Floorplan DEF generated       | YES                 | v23 §3.2          |
| Power rail integrity          | CLEAN               | v23 §3.2          |

### Stage 3 — Placement

| Metric                        | Target              | Doctrine ref      |
|-------------------------------|---------------------|-------------------|
| Placement density             | ≤ 0.80              | v23 §3.3          |
| Overflow cells                | 0                   | v23 §3.3          |
| Placement DEF generated       | YES                 | v23 §3.3          |
| GPL converged                 | YES                 | v23 §3.3          |

### Stage 4 — Clock-Tree Synthesis (CTS)

| Metric                        | Target              | Doctrine ref      |
|-------------------------------|---------------------|-------------------|
| Clock skew                    | ≤ 250 ps            | v23 §3.4          |
| Clock insertion delay         | ≤ 500 ps            | v23 §3.4          |
| CTS DEF generated             | YES                 | v23 §3.4          |
| Hold slack (post-CTS)         | ≥ 0 ns              | v23 §3.4          |

### Stage 5 — Routing

| Metric                        | Target              | Doctrine ref      |
|-------------------------------|---------------------|-------------------|
| DRC violations in routed DEF  | 0                   | v23 §3.5          |
| Routing DEF generated         | YES                 | v23 §3.5          |
| Wire length (estimate)        | ≤ 15 000 µm         | v23 §3.5          |
| Via count (estimate)          | ≤ 3 000             | v23 §3.5          |

### Stage 6 — DRC / LVS

| Metric                        | Target              | Doctrine ref      |
|-------------------------------|---------------------|-------------------|
| Magic DRC errors              | 0                   | v23 §3.6          |
| Netgen LVS errors             | 0                   | v23 §3.6          |
| GDS generated                 | YES                 | v23 §3.6          |
| ERC errors                    | 0                   | v23 §3.6          |

### Stage 7 — Sign-off / STA

| Metric                        | Target              | Doctrine ref      |
|-------------------------------|---------------------|-------------------|
| Target fmax                   | ≥ 260 MHz           | v23 §3.7          |
| Worst Negative Slack (WNS)    | ≥ 0 ns at 260 MHz   | v23 §3.7          |
| Total Negative Slack (TNS)    | 0 ns                | v23 §3.7          |
| Hold Slack                    | ≥ 0 ns              | v23 §3.7          |
| Power (estimate, dynamic)     | ≤ 5 mW at 260 MHz   | v23 §3.7          |
| Area (post-route)             | ≤ 0.0484 mm²        | v23 §3.7          |

---

## Summary Target Card

| KPI                | Target               | Source             |
|--------------------|----------------------|--------------------|
| fmax               | ≥ 260 MHz            | v23 doctrine §3    |
| Die area           | 0.0484 mm²           | v23 doctrine §3    |
| DRC violations     | 0                    | v23 doctrine §3    |
| LVS violations     | 0                    | v23 doctrine §3    |
| Clock skew         | ≤ 250 ps             | v23 doctrine §3    |
| `*` operators      | 0                    | Charter Rule 2     |
| WNS                | ≥ 0 ns               | v23 doctrine §3    |

---

## Falsification Protocol

Any measured value that does not meet a target listed above constitutes a
**falsification event** under R5 honest reporting.  All falsification events are
published in:

- `FALSIFICATION_LEDGER.md` (local, append-only)
- `WAVE_23_FALSIFICATION_LEDGER` (repo-wide, S-172)
- A comment on trinity-fpga#88 citing the specific probe that failed

---

phi^2 + phi^-2 = 3 · QUANTUM BRAIN 1:1 SILICON · R20 · DOI 10.5281/zenodo.19227877 · NEVER STOP
