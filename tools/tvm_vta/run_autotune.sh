#!/usr/bin/env bash
# Copyright 2024 Trinity / TRI-NET-G1 Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Anchor: phi^2 + phi^-2 = 3 (TRINITY)
# Stream: W15-TT-I / S-51 TVM-VTA AutoTVM
# NOTE: AutoTVM throughput projection until silicon validated 2026-12-16 (R5 honesty)
#
# run_autotune.sh — Bash driver for AutoTVM S-51 tuning pipeline.
#
# Usage:
#   bash run_autotune.sh [--dry-run] [--n-trial N]
#
# Outputs:
#   tuned_log.json           — enriched AutoTVM log with throughput metadata
#   tuned_schedule_hash.txt  — sha256 + isa_version for ISA stability check
#
# Exits non-zero if tuned throughput < 1.3x baseline (G-51 gate).

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants (pinned seed=42 for DREAMPlace consistency)
# ---------------------------------------------------------------------------
SEED=42
LOG_FILE="tuned_log.json"
HASH_FILE="tuned_schedule_hash.txt"
N_TRIAL=200
DRY_RUN=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISA_VERSION="trinity-v7.0"

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --n-trial)
            N_TRIAL="$2"
            shift 2
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        --hash-file)
            HASH_FILE="$2"
            shift 2
            ;;
        *)
            echo "[run_autotune.sh] Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo "======================================================"
echo "  TRI-NET-G1 W15-TT-I AutoTVM Driver"
echo "  ISA: ${ISA_VERSION}  |  Anchor: phi^2 + phi^-2 = 3"
echo "  Seed: ${SEED}  |  N-trial: ${N_TRIAL}"
echo "  Dry-run: ${DRY_RUN}"
echo "======================================================"

# ---------------------------------------------------------------------------
# Detect Python
# ---------------------------------------------------------------------------
PYTHON="${PYTHON:-python3}"
if ! command -v "${PYTHON}" &>/dev/null; then
    echo "[ERROR] Python not found: ${PYTHON}" >&2
    exit 1
fi
echo "[INFO] Python: $(${PYTHON} --version)"

# ---------------------------------------------------------------------------
# Check TVM availability (soft-fail: set DRY_RUN=1 if not installed)
# ---------------------------------------------------------------------------
if ! "${PYTHON}" -c "import tvm" 2>/dev/null; then
    echo "[WARN] TVM not installed — switching to dry-run mode."
    DRY_RUN=1
fi

# ---------------------------------------------------------------------------
# Run AutoTVM driver
# ---------------------------------------------------------------------------
AUTOTUNE_SCRIPT="${SCRIPT_DIR}/autotune_S51.py"
if [[ ! -f "${AUTOTUNE_SCRIPT}" ]]; then
    echo "[ERROR] autotune_S51.py not found at ${AUTOTUNE_SCRIPT}" >&2
    exit 1
fi

CMD=(
    "${PYTHON}" "${AUTOTUNE_SCRIPT}"
    --n-trial  "${N_TRIAL}"
    --log-file "${LOG_FILE}"
    --hash-file "${HASH_FILE}"
    --seed     "${SEED}"
    --cost-model xgboost
)
if [[ "${DRY_RUN}" -eq 1 ]]; then
    CMD+=(--dry-run)
fi

echo "[INFO] Running: ${CMD[*]}"
"${CMD[@]}"
AUTOTUNE_EXIT=$?

# ---------------------------------------------------------------------------
# Validate outputs
# ---------------------------------------------------------------------------
if [[ ! -f "${LOG_FILE}" ]]; then
    echo "[ERROR] tuned_log.json not generated." >&2
    exit 1
fi
if [[ ! -f "${HASH_FILE}" ]]; then
    echo "[ERROR] tuned_schedule_hash.txt not generated." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Check G-51 gate: throughput >= 1.3x baseline
# ---------------------------------------------------------------------------
echo ""
echo "------ G-51 Gate Check ------"
SPEEDUP=$("${PYTHON}" - <<'PY_EOF'
import json, sys
try:
    with open("tuned_log.json") as f:
        data = json.load(f)
    sp = data.get("throughput", {}).get("speedup", 0.0)
    print(f"{sp:.6f}")
except Exception as e:
    print(f"0.0", file=sys.stderr)
    print("0.0")
PY_EOF
)

echo "[INFO] Speedup: ${SPEEDUP}x"

# Python comparison for float
GATE_PASS=$("${PYTHON}" -c "print(1 if float('${SPEEDUP}') >= 1.3 else 0)")

if [[ "${GATE_PASS}" -eq 1 ]]; then
    echo "[PASS] G-51: speedup=${SPEEDUP}x >= 1.3x threshold"
    echo "       Hash: $(cat ${HASH_FILE} | grep sha256 | cut -d= -f2)"
    exit 0
else
    echo "[FAIL] G-51: speedup=${SPEEDUP}x < 1.3x threshold" >&2
    echo "       Increase --n-trial or review PE-mesh config." >&2
    exit 1
fi
