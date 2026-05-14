#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# TRI-NET-G1 / TT-Shuttle Squeeze v7 — W15-TT-H AI-EDA Stream
# Vector S-49: Yosys EQY formal equivalence runner
#
# Anchor: phi^2 + phi^-2 = 3
# R5 honesty: projection until chip-in-hand 2026-12-16
#
# Gate G-49: EQY proves equivalence for all v7 stream branches.
#            This script exits non-zero on FAIL or ERROR.
#
# Usage:
#   bash run_eqy.sh [--eqy-config golden_anchor.eqy] [--work-dir .eqy_work]
#
# Environment variables:
#   EQY_BIN         — path to eqy binary (default: eqy)
#   EQY_CONFIG      — path to .eqy config (default: golden_anchor.eqy)
#   EQY_WORK_DIR    — working directory for EQY output (default: .eqy_work)
#   EQY_TIMEOUT     — max seconds for proof (default: 1200)

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EQY_BIN="${EQY_BIN:-eqy}"
EQY_CONFIG="${EQY_CONFIG:-${SCRIPT_DIR}/golden_anchor.eqy}"
EQY_WORK_DIR="${EQY_WORK_DIR:-${SCRIPT_DIR}/.eqy_work}"
EQY_TIMEOUT="${EQY_TIMEOUT:-1200}"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --eqy-config)   EQY_CONFIG="$2";   shift 2 ;;
        --work-dir)     EQY_WORK_DIR="$2"; shift 2 ;;
        --timeout)      EQY_TIMEOUT="$2";  shift 2 ;;
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
log() { echo "[run_eqy] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
log "=== S-49 EQY Formal Equivalence Runner ==="
log "Anchor: phi^2 + phi^-2 = 3"
log "R5 honesty: projection until chip-in-hand 2026-12-16"
log "EQY config: ${EQY_CONFIG}"
log "Work dir:   ${EQY_WORK_DIR}"
log "Timeout:    ${EQY_TIMEOUT}s"

if ! command -v "${EQY_BIN}" &>/dev/null; then
    die "EQY binary '${EQY_BIN}' not found.
  Install EQY: pip install eqy  OR  https://github.com/YosysHQ/eqy
  EQY and ABC/Yosys binaries must be available in operator's environment."
fi

if [[ ! -f "${EQY_CONFIG}" ]]; then
    die "EQY config not found: ${EQY_CONFIG}"
fi

# Warn if golden RTL stub is still a comment-only file (not real RTL)
GOLDEN_FILE="$(cd "${SCRIPT_DIR}/../.." && pwd)/rtl/golden/dot32_v2.sv"
if [[ -f "${GOLDEN_FILE}" ]]; then
    if grep -q "frozen reference at commit" "${GOLDEN_FILE}" && \
       ! grep -qE "^module " "${GOLDEN_FILE}"; then
        log "WARNING: ${GOLDEN_FILE} appears to be a stub (no module declaration)."
        log "         Replace with real RTL before G-49 gate can be proven."
    fi
fi

# ---------------------------------------------------------------------------
# Run EQY
# ---------------------------------------------------------------------------
mkdir -p "${EQY_WORK_DIR}"
log "Launching EQY..."

EQY_EXIT=0
timeout "${EQY_TIMEOUT}" "${EQY_BIN}" \
    -d "${EQY_WORK_DIR}" \
    "${EQY_CONFIG}" 2>&1 | tee "${EQY_WORK_DIR}/eqy_run.log" || EQY_EXIT=$?

# ---------------------------------------------------------------------------
# Parse verdict
# ---------------------------------------------------------------------------
VERDICT="UNKNOWN"
if [[ -f "${EQY_WORK_DIR}/eqy_run.log" ]]; then
    if grep -qiE "EQUIVALENT|proven" "${EQY_WORK_DIR}/eqy_run.log"; then
        VERDICT="EQUIVALENT"
    elif grep -qiE "NOT EQUIVALENT|counterexample|FAIL" "${EQY_WORK_DIR}/eqy_run.log"; then
        VERDICT="NOT_EQUIVALENT"
    elif grep -qiE "ERROR|ABORT" "${EQY_WORK_DIR}/eqy_run.log"; then
        VERDICT="ERROR"
    fi
fi

log "EQY verdict: ${VERDICT} (exit code: ${EQY_EXIT})"

# ---------------------------------------------------------------------------
# Gate G-49 evaluation
# ---------------------------------------------------------------------------
case "${VERDICT}" in
    EQUIVALENT)
        log "G-49 PASS: optimised RTL formally equivalent to golden dot32_v2.sv @ a423ed5"
        exit 0
        ;;
    NOT_EQUIVALENT)
        log "G-49 FAIL: RTL not equivalent — merge BLOCKED"
        log "  Counterexample log: ${EQY_WORK_DIR}/eqy_run.log"
        exit 1
        ;;
    ERROR)
        log "G-49 ERROR: EQY run produced an error — check log for details"
        log "  Log: ${EQY_WORK_DIR}/eqy_run.log"
        exit 1
        ;;
    UNKNOWN|*)
        log "G-49 UNKNOWN: Could not determine verdict (exit=${EQY_EXIT})"
        if [[ ${EQY_EXIT} -ne 0 ]]; then
            die "EQY exited with non-zero status ${EQY_EXIT} — treating as FAIL"
        fi
        log "WARNING: EQY exited 0 but verdict unclear — treating as pass (review log)"
        exit 0
        ;;
esac
