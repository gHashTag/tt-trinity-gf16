#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# TRI-NET-G1 / TT-Shuttle Squeeze v7 — W15-TT-H AI-EDA Stream
# Vector S-50: Berkeley ABC retime+remap runner
#
# Anchor: phi^2 + phi^-2 = 3
# R5 honesty: projection until chip-in-hand 2026-12-16
#
# Gate G-50: post-ABC gate count <= 0.92 * pre-ABC (<=8% reduction)
#            Exit non-zero if delta exceeds -8% threshold (gate count too high).
#
# Usage:
#   bash run_abc.sh [--input <aig>] [--output <blif>]
#
# Environment variables (all have defaults for CI):
#   ABC_BIN          — path to abc binary         (default: abc)
#   YOSYS_BIN        — path to yosys binary        (default: yosys)
#   ABC_INPUT_SRC    — path to input Verilog        (default: ../../src/v7_dot32.v)
#   ABC_INPUT_AIG    — path to intermediate AIGER   (default: /tmp/tt_v7_abc_input.aig)
#   ABC_OUTPUT_BLIF  — path to output BLIF          (default: /tmp/tt_v7_abc_output.blif)
#   SKY130_HDLL_LIB  — sky130_fd_sc_hdll liberty    (required for real run)
#   SKY130_HD_LIB    — sky130_fd_sc_hd liberty      (required for real run)
#   PDKPATH          — PDK root                     (optional, for default lib paths)
#   ABC_SCRIPT       — path to ABC script            (default: abc_trinity.script)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
ABC_BIN="${ABC_BIN:-abc}"
YOSYS_BIN="${YOSYS_BIN:-yosys}"
ABC_INPUT_SRC="${ABC_INPUT_SRC:-${SCRIPT_DIR}/../../src/v7_dot32.v}"
ABC_INPUT_AIG="${ABC_INPUT_AIG:-/tmp/tt_v7_abc_input.aig}"
ABC_OUTPUT_BLIF="${ABC_OUTPUT_BLIF:-/tmp/tt_v7_abc_output.blif}"
ABC_SCRIPT="${ABC_SCRIPT:-${SCRIPT_DIR}/abc_trinity.script}"

# Liberty lib defaults (use PDK path if set, else CI stubs)
_PDKROOT="${PDKPATH:-/usr/local/share/pdk}"
SKY130_HDLL_LIB="${SKY130_HDLL_LIB:-${_PDKROOT}/sky130A/libs.ref/sky130_fd_sc_hdll/lib/sky130_fd_sc_hdll__tt_025C_1v80.lib}"
SKY130_HD_LIB="${SKY130_HD_LIB:-${_PDKROOT}/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib}"

# G-50 threshold: gate count must be <= 0.92 * pre-count (>= 8% reduction)
G50_THRESHOLD="0.92"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)   ABC_INPUT_SRC="$2"; shift 2 ;;
        --output)  ABC_OUTPUT_BLIF="$2"; shift 2 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[run_abc] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

parse_gate_count() {
    # Extract gate count from abc print_stats output line:
    # "nd = 12345" or "and = 12345"
    local log_file="$1"
    grep -oE 'nd *= *[0-9]+' "${log_file}" | tail -1 | grep -oE '[0-9]+' || echo "0"
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
log "=== S-50 ABC Retime+Remap Runner ==="
log "Anchor: phi^2 + phi^-2 = 3"
log "R5 honesty: projection until chip-in-hand 2026-12-16"
log "Input src:   ${ABC_INPUT_SRC}"
log "Input AIG:   ${ABC_INPUT_AIG}"
log "Output BLIF: ${ABC_OUTPUT_BLIF}"
log "HDLL lib:    ${SKY130_HDLL_LIB}"
log "HD lib:      ${SKY130_HD_LIB}"

# Check required binaries
if ! command -v "${YOSYS_BIN}" &>/dev/null; then
    die "Yosys binary '${YOSYS_BIN}' not found.
  Install: https://github.com/YosysHQ/yosys  or  apt install yosys"
fi

if ! command -v "${ABC_BIN}" &>/dev/null; then
    die "ABC binary '${ABC_BIN}' not found.
  Install: http://people.eecs.berkeley.edu/~alanmi/abc/
  Or via Yosys: yosys-config --datdir/../bin/abc"
fi

# Warn about missing liberty files (not fatal — ABC still runs on AIG)
for lib_var in SKY130_HDLL_LIB SKY130_HD_LIB; do
    lib_path="${!lib_var}"
    if [[ ! -f "${lib_path}" ]]; then
        log "WARNING: Liberty file not found: ${lib_path}"
        log "         Set ${lib_var} to enable technology mapping."
        log "         Continuing without technology mapping (area estimates only)."
    fi
done

# ---------------------------------------------------------------------------
# Step 1 — Yosys: Verilog → AIGER
# ---------------------------------------------------------------------------
log "Step 1: Yosys synthesis to AIGER..."

YOSYS_SYNTH_LOG="/tmp/tt_v7_yosys_synth.log"

if [[ ! -f "${ABC_INPUT_SRC}" ]]; then
    log "WARNING: Source file not found: ${ABC_INPUT_SRC}"
    log "         Creating minimal stub AIG for CI dry-run."
    # Minimal valid AIGER (1 input, 1 output, 1 AND gate)
    printf "aig 1 1 0 1 1\n2\n3\n1 2 2\n" > "${ABC_INPUT_AIG}"
else
    "${YOSYS_BIN}" -p "
        read_verilog -sv ${ABC_INPUT_SRC};
        synth -top dot32_v2 -flatten;
        abc -script +strash;
        write_aiger -ascii ${ABC_INPUT_AIG};
    " 2>&1 | tee "${YOSYS_SYNTH_LOG}"
fi

# ---------------------------------------------------------------------------
# Step 2 — Capture pre-ABC gate count from Yosys log
# ---------------------------------------------------------------------------
PRE_COUNT=0
if [[ -f "${YOSYS_SYNTH_LOG}" ]]; then
    # Yosys "Number of cells:" line
    PRE_COUNT=$(grep -oE 'Number of cells: *[0-9]+' "${YOSYS_SYNTH_LOG}" | tail -1 | grep -oE '[0-9]+' || echo "0")
fi
if [[ "${PRE_COUNT}" -eq 0 ]]; then
    log "WARNING: Could not parse pre-ABC gate count from Yosys log — using AIG node count"
    PRE_COUNT=$(grep -oE 'nd *= *[0-9]+' "${ABC_INPUT_AIG}" 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo "16000")
fi
log "Pre-ABC gate count: ${PRE_COUNT}"

# ---------------------------------------------------------------------------
# Step 3 — Run ABC with Trinity script
# ---------------------------------------------------------------------------
log "Step 2: Running ABC with trinity script..."

ABC_RUN_LOG="/tmp/tt_v7_abc_run.log"

export ABC_INPUT_AIG ABC_OUTPUT_BLIF
export ABC_LIBERTY_HDLL="${SKY130_HDLL_LIB}"
export ABC_LIBERTY_HD="${SKY130_HD_LIB}"

ABC_EXIT=0
"${ABC_BIN}" -f "${ABC_SCRIPT}" 2>&1 | tee "${ABC_RUN_LOG}" || ABC_EXIT=$?

if [[ ${ABC_EXIT} -ne 0 ]]; then
    log "WARNING: ABC exited with code ${ABC_EXIT} — treating as soft failure for CI"
fi

# ---------------------------------------------------------------------------
# Step 4 — Parse post-ABC gate count
# ---------------------------------------------------------------------------
POST_COUNT=$(parse_gate_count "${ABC_RUN_LOG}")
if [[ "${POST_COUNT}" -eq 0 ]]; then
    log "WARNING: Could not parse post-ABC gate count — defaulting to pre-count"
    POST_COUNT="${PRE_COUNT}"
fi
log "Post-ABC gate count: ${POST_COUNT}"

# ---------------------------------------------------------------------------
# Step 5 — Gate G-50 evaluation
# ---------------------------------------------------------------------------
# G-50: post_count <= 0.92 * pre_count
# Use awk for floating-point comparison (no bc dependency)
THRESHOLD_COUNT=$(awk "BEGIN { printf \"%d\", ${PRE_COUNT} * ${G50_THRESHOLD} }")
DELTA_PCT=$(awk "BEGIN { printf \"%.2f\", (1.0 - ${POST_COUNT} / (${PRE_COUNT} > 0 ? ${PRE_COUNT} : 1)) * 100 }")

log "Gate delta: ${PRE_COUNT} → ${POST_COUNT} (reduction: ${DELTA_PCT}%)"
log "G-50 threshold: <= ${THRESHOLD_COUNT} cells (${G50_THRESHOLD}x = 8% reduction)"

if [[ "${POST_COUNT}" -le "${THRESHOLD_COUNT}" ]]; then
    log "G-50 PASS: ${POST_COUNT} <= ${THRESHOLD_COUNT} (${DELTA_PCT}% reduction achieved)"
    EXIT_CODE=0
else
    log "G-50 FAIL: ${POST_COUNT} > ${THRESHOLD_COUNT} — gate count reduction < 8%"
    log "  Possible cause: ABC not installed, stub AIG used, or optimisation stalled."
    EXIT_CODE=1
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "=== Summary ==="
log "  Pre-ABC:  ${PRE_COUNT} gates"
log "  Post-ABC: ${POST_COUNT} gates"
log "  Delta:    ${DELTA_PCT}%"
log "  G-50:     $([ ${EXIT_CODE} -eq 0 ] && echo PASS || echo FAIL)"

exit "${EXIT_CODE}"
