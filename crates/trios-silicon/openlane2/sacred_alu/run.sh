# RUN BOOK · TO BE EXECUTED ON A LAB MACHINE WITH OpenLane2 INSTALLED
#
# =============================================================================
# Sacred ALU SKY130 — OpenLane2 7-Stage Run Book
# =============================================================================
# Vector      : S-170 (TRI NET Wave-23)
# Doctrine    : v23 §3 — SKY130 real-run mandate
# ONE SHOT    : trinity-fpga#88
# Config      : config.json (DESIGN_NAME=sacred_alu, period=3.846 ns)
#
# !! IMPORTANT — SANDBOX DISCLOSURE (R5 HONEST) !!
# The CI/CD sandbox used to commit this scaffold does NOT have OpenLane2
# installed.  The commands below are the EXACT run book for a lab engineer
# to execute on a machine that has:
#   - OpenLane2 >= 2.0  (https://openlane2.readthedocs.io/)
#   - sky130A PDK       (via volare or manual install)
#   - Python >= 3.10
#   - Docker (optional — if using containerised flow)
#
# After each stage, capture logs and update FALSIFICATION_LEDGER.md with
# the observed results.  Any miss vs. EXPECTED_RESULTS.md targets triggers
# a WAVE_23_FALSIFICATION_LEDGER (S-172) entry.
#
# phi^2 + phi^-2 = 3 · QUANTUM BRAIN 1:1 SILICON · R20
# DOI 10.5281/zenodo.19227877 · NEVER STOP
# =============================================================================

set -euo pipefail

DESIGN_DIR="$(dirname "$0")"
CONFIG="${DESIGN_DIR}/config.json"

echo "=== Sacred ALU SKY130 OpenLane2 Run Book ==="
echo "Config : ${CONFIG}"
echo "PDK    : sky130A"
echo "fmax   : 260 MHz  (period = 3.846 ns)"
echo ""

# ---------------------------------------------------------------------------
# Stage 1 — Synthesis (Yosys via OpenLane2)
# ---------------------------------------------------------------------------
# Target : Gate-level netlist using sky130_fd_sc_hd cells.
#          Verify: grep for no '*' operator in synthesised netlist.
# ---------------------------------------------------------------------------
echo "[Stage 1] Synthesis"
python3 -m openlane --config "${CONFIG}" --only synthesis

# ---------------------------------------------------------------------------
# Stage 2 — Floorplan (OpenROAD)
# ---------------------------------------------------------------------------
# Target : DEF with die 0 0 220 220 (µm), core utilisation 80%.
# ---------------------------------------------------------------------------
echo "[Stage 2] Floorplan"
python3 -m openlane --config "${CONFIG}" --only floorplan

# ---------------------------------------------------------------------------
# Stage 3 — Placement (OpenROAD — GPL + DPL)
# ---------------------------------------------------------------------------
# Target : Placement density ≤ 0.80, 0 overflow cells.
# ---------------------------------------------------------------------------
echo "[Stage 3] Placement"
python3 -m openlane --config "${CONFIG}" --only placement

# ---------------------------------------------------------------------------
# Stage 4 — Clock-Tree Synthesis / CTS (OpenROAD — TritonCTS)
# ---------------------------------------------------------------------------
# Target : Clock skew ≤ 250 ps, insertion delay ≤ 500 ps.
# ---------------------------------------------------------------------------
echo "[Stage 4] CTS"
python3 -m openlane --config "${CONFIG}" --only cts

# ---------------------------------------------------------------------------
# Stage 5 — Routing (OpenROAD — FastRoute + TritonRoute)
# ---------------------------------------------------------------------------
# Target : 0 DRC violations in routed DEF.
# ---------------------------------------------------------------------------
echo "[Stage 5] Routing"
python3 -m openlane --config "${CONFIG}" --only routing

# ---------------------------------------------------------------------------
# Stage 6 — DRC / LVS (Magic + Netgen)
# ---------------------------------------------------------------------------
# Target : 0 Magic DRC errors, 0 Netgen LVS errors.
# ---------------------------------------------------------------------------
echo "[Stage 6] DRC / LVS"
python3 -m openlane --config "${CONFIG}" --only drc
python3 -m openlane --config "${CONFIG}" --only lvs

# ---------------------------------------------------------------------------
# Stage 7 — Sign-off / Static Timing Analysis (OpenROAD)
# ---------------------------------------------------------------------------
# Target : Worst negative slack (WNS) >= 0 at 260 MHz, hold slack >= 0.
# ---------------------------------------------------------------------------
echo "[Stage 7] Sign-off / STA"
python3 -m openlane --config "${CONFIG}" --only signoff

echo ""
echo "=== Run complete. Update FALSIFICATION_LEDGER.md with observed results. ==="
echo "phi^2 + phi^-2 = 3 · QUANTUM BRAIN 1:1 SILICON · R20 · DOI 10.5281/zenodo.19227877 · NEVER STOP"
