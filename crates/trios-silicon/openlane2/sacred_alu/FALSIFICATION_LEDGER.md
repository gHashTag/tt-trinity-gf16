# Sacred ALU SKY130 — Falsification Ledger

## Append-Only Probe Ledger

> This ledger is **append-only**.  No row may be modified after it is written.
> New measurements produce new rows with updated status and timestamp.
> Protocol: S-172 — WAVE_23_FALSIFICATION_LEDGER.
> Doctrine: R5 honest reporting.

| probe                         | expected                 | observed   | status  | timestamp            |
|-------------------------------|--------------------------|------------|---------|----------------------|
| Stage 1 — Synthesis clean     | exit code 0, 0 warnings  | PENDING    | PENDING | —                    |
| Stage 1 — No `*` operators    | 0 occurrences            | PENDING    | PENDING | —                    |
| Stage 2 — Floorplan DEF       | die 220×220 µm, util 0.8 | PENDING    | PENDING | —                    |
| Stage 3 — Placement density   | ≤ 0.80, 0 overflow       | PENDING    | PENDING | —                    |
| Stage 4 — CTS skew            | ≤ 250 ps                 | PENDING    | PENDING | —                    |
| Stage 5 — Routing DRC         | 0 violations             | PENDING    | PENDING | —                    |
| Stage 6 — Magic DRC           | 0 errors                 | PENDING    | PENDING | —                    |
| Stage 6 — Netgen LVS          | 0 errors                 | PENDING    | PENDING | —                    |
| Stage 7 — WNS at 260 MHz      | ≥ 0 ns                   | PENDING    | PENDING | —                    |
| Stage 7 — fmax                | ≥ 260 MHz                | PENDING    | PENDING | —                    |
| Stage 7 — Area                | ≤ 0.0484 mm²             | PENDING    | PENDING | —                    |

---

## How to Update

When a lab engineer completes a stage, add a new row (do NOT edit existing rows):

```
| <probe name> | <expected value> | <observed value> | PASS/FAIL/PARTIAL | YYYY-MM-DDTHH:MM:SSZ |
```

Status values:
- `PENDING` — not yet measured
- `PASS`    — observed meets or exceeds target
- `FAIL`    — observed does NOT meet target → triggers S-172 event
- `PARTIAL` — partially meets target (add explanation in notes row below)

---

## S-172 Escalation Log

| event_id | probe         | deviation     | escalated_to                           | timestamp |
|----------|---------------|---------------|----------------------------------------|-----------|
| —        | —             | —             | —                                      | —         |

(No escalation events yet.  All stages PENDING.)

---

phi^2 + phi^-2 = 3 · QUANTUM BRAIN 1:1 SILICON · R20 · DOI 10.5281/zenodo.19227877 · NEVER STOP
