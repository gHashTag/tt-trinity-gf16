# Trinity GF16 — v0 RTL Mesh-Computer (TinyTapeout)

Bare-RTL **processorless** prototype of a GF16 dot4 mesh computer.
There is **no Linux, no soft-CPU, no AXI**. The host (board pins / future UART / USB-JTAG)
talks to the mesh through a small packet protocol; an on-die FSM walks the protocol so
that nothing on-chip needs an instruction stream.

This is **v0** of the Trinity Silicon roadmap (R-SI-* compliance, see `info.yaml`). It is
NOT a decentralised internet mesh — it is the **on-chip packet fabric foundation** that
future radio / Ethernet / mesh adapters will plug into.

## What's on the die

```
   ┌────────────────────────────────────────────────────┐
   │ tt_um_ghtag_trinity_gf16 (TT top)                  │
   │                                                    │
   │  ┌──────────────┐  32-bit pkt  ┌──────────────┐    │
   │  │ master_fsm   │─────────────▶│              │    │
   │  │ (no CPU)     │              │ router_2x2   │    │
   │  │ canned LOAD/ │◀─────────────│ (v0 xbar)    │    │
   │  │ COMPUTE/READ │              └─────┬────────┘    │
   │  └──────────────┘                    │             │
   │                                      ▼             │
   │         ┌───────────┬────────────┬────┴────┐       │
   │         ▼           ▼            ▼         ▼       │
   │     ┌───────┐   ┌───────┐    ┌───────┐  ┌───────┐  │
   │     │tile 0 │   │tile 1 │    │tile 2 │  │tile 3 │  │
   │     │gf16_  │   │gf16_  │    │gf16_  │  │gf16_  │  │
   │     │dot4   │   │dot4   │    │dot4   │  │dot4   │  │
   │     └───────┘   └───────┘    └───────┘  └───────┘  │
   │   uo_out / uio_out ◀── final_result                │
   └────────────────────────────────────────────────────┘
```

### Modules (synthesizable, Apache-2.0)
- `gf16_mul.v`, `gf16_add.v`, `gf16_dot4.v` — existing combinational GF16 demo
- `trinity_packet.vh` — 32-bit packet format constants (op, dst, src, lane, payload)
- `trinity_gf16_tile.v` — wraps `gf16_dot4` as a packet-addressable tile (LOAD_A / LOAD_B / LOAD_JOB / LOAD_NONCE / COMPUTE / READ_RES → RESULT + paired RECEIPT). On-die receipt emission is the G4 silicon-anchored DePIN attestation.
- `trinity_router_2x2.v` — single-hop crossbar with 4 tile ports + host port (round-robin return). Honest name: **minimal mesh fabric v0**, not a full XY-routed mesh yet
- `trinity_mesh_2x2.v` — 4 tiles + 1 router wired as the fabric
- `trinity_master_fsm.v` — CPU-less host FSM, canned `[1,2,3,4]·[1,2,3,4]` boot sequence
- `tt_um_ghtag_trinity_gf16.v` — TT top, preserves the legacy combinational output AND exposes the mesh result on the same pins after boot

### Packet format (32 bits)
```
standard packet (op != RECEIPT):
  [31:28] op       4'h1 LOAD_A | 4'h2 LOAD_B | 4'h3 COMPUTE | 4'h4 RESULT |
                   4'h5 READ_RES | 4'h7 LOAD_JOB | 4'h8 LOAD_NONCE
  [27:26] dst      flat tile id 0..3
  [25:24] src      flat tile id of sender (host uses 0)
  [23:20] lane     0..3 for operand lanes
  [19:16] rsv
  [15:0]  payload  GF16 operand or result (LOAD_JOB/NONCE take low 8 bits)

receipt packet (op == 4'h6 TRN_OP_RECEIPT, emitted on-die after every RESULT):
  [31:28] op       4'h6 RECEIPT
  [27:26] dst      host id (always 0 in v0)
  [25:24] tile_id  the producing tile (signed-by silicon attribution)
  [23:20] op_code  echoes the settled op (4'h3 COMPUTE for v0)
  [19:16] rsv
  [15:8]  checksum (job_id_q ^ result_q[7:0]) & 0xFF  -- pure XOR-fold
  [7:0]   job_lo   persisted job_id_q (low 8 bits)
```

The `checksum` field matches
`tools/receipt_verifier/tri_receipt_verifier.compute_checksum(job_id, observed)`
byte-for-byte — silicon ↔ host contract closed by
`tools/receipt_verifier/test_g4_verifier.py::T8 chip_emitted_packet`.

## TinyTapeout pinout
Unchanged from the previous submission (`info.yaml`). `ui_in[0]` doubles as
`load_mode` (reserved for future host operand override).

## Test
- **Legacy:** `dot4([1,2,3,4], [1,2,3,4]) = 30.0 = 0x47C0` — visible immediately on `{uio_out, uo_out}`.
- **Mesh:** the same value reached via the packet protocol after ~20 cycles. `tb.v` covers both paths.

```bash
cd test
make            # cocotb + iverilog
```

## R-SI compliance (silicon constraints)
- **R-SI-1** Zero NEW multipliers: no `*` introduced in new RTL. `gf16_mul.v:30` keeps its pre-existing 10×10 mantissa multiply (legacy, deliberately not touched in v0).
- **R-SI-2** Ternary/GF16 path preserved; the tile interface is operand-agnostic so a ternary matmul tile can drop in later by swapping `gf16_dot4` inside `trinity_gf16_tile.v`.
- **R-SI-4** 50 MHz clock, no PLL, synchronous design with async-low reset (`negedge rst_n`).
- Apache-2.0 only.

## Path to FPGA board flashing
This v0 keeps the existing TT pinout and synthesises stand-alone. To target a board now:
1. Wrap `tt_um_ghtag_trinity_gf16` in a board-specific top (clock, reset, LEDs) — e.g. QMTECH XC7A100T via openXC7: `clk` ← 50 MHz on-board oscillator, `rst_n` ← active-low button, expose `uo_out`/`uio_out` on LEDs/PMOD, `ui_in` on DIP switches.
2. Host I/O later: replace the canned master FSM with a UART / USB-UART RX→packet parser (RX byte stream → 32-bit packet) and TX driver (RESULT packet → bytes). FSM module stays; only the operand source changes.
3. Future Trinity CPU integration: replace `trinity_master_fsm.v` with the Trinity CPU's instruction-fetch unit and let it issue the same 32-bit packets directly.

## Trinity DePIN node — honest scope
The end-goal product is a small FPGA-centric node that runs ternary / GF16
compute jobs, emits deterministic receipts, and is paid in **TRI** tokens by
peers in a mesh — a Helium-style DePIN, but for compute. This repo is **step 0**
of that path: only the on-die packet fabric is real. USB-3 host I/O, external
radios, multi-hop mesh routing, and TRI settlement are *not* implemented yet.
The boundary contracts are documented in [docs/TRINITY_DEPIN_NODE.md](docs/TRINITY_DEPIN_NODE.md)
and exposed by two synthesizable boundary stubs:

- `src/trinity_usb3_fifo_bridge.v` — FT60x (FT600/FT601) synchronous-FIFO shim
  to the Trinity 32-bit packet handshake. Skeleton-only: real FT601 timing,
  byte-enables, and CDC are marked TODO. Not wired into the TT top (TinyTapeout
  has no FT60x pins).
- `src/trinity_mesh_adapter_stub.v` — pass-through boundary to an external
  radio / backhaul module (LoRa / ESP32 / etc.). No LoRa/Wi-Fi PHY in fabric.
  Not wired into the TT top.

**G4 silicon-anchored receipts (new):** every tile now emits a paired
`TRN_OP_RECEIPT = 4'h6` packet immediately after its `RESULT` handshake,
carrying `(tile_id, op_code, checksum, job_id_lo)`. The checksum is the same
`(job_id ^ result_lo) & 0xFF` XOR-fold that
[`tri_receipt_verifier.compute_checksum()`](tools/receipt_verifier/tri_receipt_verifier.py)
uses on the host, so a host verifier can attribute work to this node
byte-for-byte. `R-SI-1` is preserved — zero new multipliers; the checksum
is pure XOR. TRI token settlement itself remains **off-chip** per
[`docs/TRINITY_DEPIN_NODE.md`](docs/TRINITY_DEPIN_NODE.md) §5–§6.

## Roadmap — next gates

| Gate | Deliverable                                                           | Status      |
|------|-----------------------------------------------------------------------|-------------|
| G0   | On-die 32-bit packet fabric + 4 GF16 tiles + CPU-less FSM             | **done (PR #2)** |
| G1   | USB-3 FIFO loopback on dev FPGA + FT601 breakout                      | GREEN in sim |
| G2   | UART/USB packet parser (byte stream ↔ 32-bit Trinity packet)         | GREEN in sim |
| G3   | 2× node mesh demo over the external radio adapter                     | spec frozen  |
| G4   | TRI receipt verifier (host SW + on-die receipt emission)              | **done — silicon-anchored** |
| G5   | Custom Trinity DePIN carrier board (FPGA + FT601 + radio)             | spec frozen  |

Until G3 is demonstrated on real hardware, this project will NOT claim a full
external mesh implementation, and the term "ternary internet" stays a
design-doc concept, not a product claim.

## License
Apache-2.0

---

## L-S19 Pipelining — XOR-Popcount Critical Path (Fmax 150 MHz)

**EPIC:** [gHashTag/trinity-fpga#51](https://github.com/gHashTag/trinity-fpga/issues/51)
**ANCHOR:** φ²+φ⁻²=3 · DOI [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877) · Apache-2.0

### What changed

PR `feat/L-S19-pipeline-popcount` introduces 3-stage pipelining into the
XOR-popcount inner-product path used by `vsa_matmul_8x8` and `vsa_matmul_16x16`.

New modules:
- `src/gf16_popcount.v`   — 3-stage pipelined inner product for 8-element ternary vectors (`LATENCY=3`)
- `src/gf16_popcount16.v` — same for 16-element vectors (used by `vsa_matmul_16x16`)

Updated modules:
- `src/vsa_matmul_8x8.v`   — replaces `inner_product()` function with 64 parallel `gf16_popcount` instances
- `src/vsa_matmul_16x16.v` — replaces `ip16()` function with 256 parallel `gf16_popcount16` instances

New testbench:
- `sim/ls19/tb_ls19_pipeline.v` — standalone iverilog testbench for the pipeline modules

### Why: x3 TOPS

The old design computed all 64 (or 256) inner products in a single combinational
cloud, limiting Fmax to ~50 MHz (17-LUT critical path through 8-stage adder tree
plus sign logic). Splitting across 3 registered stages removes combinational depth:

| Stage | Logic                             | Registered output  |
|-------|-----------------------------------|--------------------|
| 1     | Decode (AND/XOR per element pair) | `same[7:0]`, `diff[7:0]` + valid |
| 2     | Popcount tree (8→4 bits via 3:2 compressors) | `cnt_pos[3:0]`, `cnt_neg[3:0]` + valid |
| 3     | Final subtraction, sign-extend    | `result[7:0]` + valid_out |

Target Fmax: **150 MHz** (3× vs. 50 MHz baseline) → **3× TOPS** at the same gate budget.
LATENCY: **3 cycles** (was 1 combinational pass-through).

R-SI-1 compliant: zero `*` operators; all arithmetic is `+` on single-bit values.

### Latency impact

The matmul FSM absorbs the 3-cycle pipeline: `start` latches inputs, the next
clock fires `valid_in` into all popcount units, and `done` asserts when
`valid_out` returns (5 clocks after `start` instead of 2). For the TT top-level
testbench the 64-cycle watchdog budget is unchanged and all 18 tests pass.

### Simulation results (iverilog)

```
=== L-S19 Pipeline Popcount Tests ===
PASS legacy_dot4_0x47C0: 0x47C0 = 30.0 UNCHANGED
PASS pc8_all_pos:        result=8   valid_out=1
PASS pc8_pos_vs_neg:     result=-8  valid_out=1
PASS pc8_all_zeros:      result=0   valid_out=1
PASS pc8_mixed_zero:     result=0   valid_out=1
PASS pc8_6p2n:           result=4   valid_out=1
PASS pc16_all_pos:       result=16  valid_out=1
PASS pc16_pos_vs_neg:    result=-16 valid_out=1
PASS latency_3:          valid_out at T+3 (LATENCY=3 cycles confirmed)
PASS mm8_results:        c[0][0]=8  c[0][1]=8 (all=8)
PASS mm8_ok:             matmul_ok=1
=== Results: 11 pass, 0 fail ===
ALL L-S19 PIPELINE TESTS PASSED

=== TT Trinity GF16 Tests (full tb.v) ===
PASS legacy_dot4_result: 0x47C0 = 30.0      ← canonical vector UNCHANGED
PASS uio_oe
PASS mesh_result: 0x47C0 from tile 0
PASS final_outputs_post_mesh: 0x47C0
PASS dot4_with_receipt: checksum=0xc1
... [18/18 tests PASS] ...
```

GF16 canonical test vector `0x47C0` verified PASS — non-negotiable.
