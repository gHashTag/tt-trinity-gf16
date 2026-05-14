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
"""
isa_stability_check.py — CI guard for TVM-VTA ISA stability.

Compares tuned_schedule_hash.txt against the previous commit's hash.
If the ISA version changed AND the hash differs, requires explicit
--reload-cache flag to proceed.

Corrective action (ICA-V7-TVM-ISA-STABILITY):
  When ISA version is bumped (e.g., trinity-v7.0 → trinity-v8.0)
  the tuned schedule cache is invalidated. The --reload-cache flag
  must be passed explicitly to acknowledge the ISA change and permit
  CI to continue with fresh tuning.

Usage:
    python isa_stability_check.py [--reload-cache] [--hash-file PATH]
    python isa_stability_check.py --current-only [--hash-file PATH]

Exit codes:
    0 — stable (hash matches or --reload-cache passed with ISA change)
    1 — ISA version changed AND hash differs AND --reload-cache NOT passed
    2 — hash file missing or malformed
"""

import argparse
import json
import logging
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional, Tuple

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
ANCHOR = "phi^2 + phi^-2 = 3"
EXPECTED_ISA_VERSION = "trinity-v7.0"
DEFAULT_HASH_FILE = "tuned_schedule_hash.txt"


# ---------------------------------------------------------------------------
# Hash file parsing
# ---------------------------------------------------------------------------

def parse_hash_file(path: str) -> Tuple[Optional[str], Optional[str]]:
    """Parse a hash file and return (isa_version, sha256).

    File format (two lines):
        isa_version=trinity-v7.0
        sha256=<64-hex-chars>

    Returns (None, None) if file is missing or malformed.
    """
    if not os.path.exists(path):
        logger.warning("Hash file not found: %s", path)
        return None, None

    isa_version = None
    sha256 = None
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line.startswith("isa_version="):
                    isa_version = line.split("=", 1)[1]
                elif line.startswith("sha256="):
                    sha256 = line.split("=", 1)[1]
    except OSError as exc:
        logger.error("Failed to read hash file %s: %s", path, exc)
        return None, None

    return isa_version, sha256


# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

def get_previous_commit_hash_file(
    hash_file: str,
    ref: str = "HEAD~1",
) -> Optional[str]:
    """Retrieve hash file content from the previous git commit.

    Returns the raw string content, or None if unavailable.
    """
    try:
        result = subprocess.run(
            ["git", "show", f"{ref}:{hash_file}"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            return result.stdout
        logger.info(
            "git show %s:%s returned %d — file may not exist in previous commit.",
            ref, hash_file, result.returncode,
        )
        return None
    except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
        logger.warning("git not available or timed out: %s", exc)
        return None


def parse_hash_content(content: str) -> Tuple[Optional[str], Optional[str]]:
    """Parse hash file content string (same format as parse_hash_file)."""
    isa_version = None
    sha256 = None
    for line in content.splitlines():
        line = line.strip()
        if line.startswith("isa_version="):
            isa_version = line.split("=", 1)[1]
        elif line.startswith("sha256="):
            sha256 = line.split("=", 1)[1]
    return isa_version, sha256


# ---------------------------------------------------------------------------
# Tuned log ISA version extraction
# ---------------------------------------------------------------------------

def get_isa_from_log(log_file: str = "tuned_log.json") -> Optional[str]:
    """Extract isa_version from the tuned_log.json metadata."""
    if not os.path.exists(log_file):
        return None
    try:
        with open(log_file) as f:
            data = json.load(f)
        return data.get("meta", {}).get("isa_version")
    except (json.JSONDecodeError, OSError) as exc:
        logger.warning("Could not parse tuned_log.json: %s", exc)
        return None


# ---------------------------------------------------------------------------
# Core stability check
# ---------------------------------------------------------------------------

def check_stability(
    hash_file: str = DEFAULT_HASH_FILE,
    reload_cache: bool = False,
    current_only: bool = False,
) -> int:
    """Run ISA stability check.

    Args:
        hash_file:      Path to current tuned_schedule_hash.txt
        reload_cache:   If True, bypass hash mismatch on ISA version change
        current_only:   Only validate current hash file (no git comparison)

    Returns:
        0 — stable
        1 — ISA change + hash mismatch + no --reload-cache
        2 — missing/malformed files
    """
    # --- Parse current hash file ---
    current_isa, current_sha = parse_hash_file(hash_file)
    if current_isa is None or current_sha is None:
        logger.error(
            "Current hash file missing or malformed: %s "
            "(isa_version=%s, sha256=%s)",
            hash_file, current_isa, current_sha,
        )
        return 2

    logger.info("Current  ISA version : %s", current_isa)
    logger.info("Current  sha256      : %s", current_sha)

    # --- Validate expected ISA version ---
    if current_isa != EXPECTED_ISA_VERSION:
        logger.warning(
            "ISA version mismatch: got '%s', expected '%s'. "
            "Ensure vta_config.json isa_version is '%s'.",
            current_isa, EXPECTED_ISA_VERSION, EXPECTED_ISA_VERSION,
        )
        if not reload_cache:
            print(
                f"[FAIL] ISA version '{current_isa}' != expected '{EXPECTED_ISA_VERSION}'. "
                f"Pass --reload-cache to acknowledge.",
                file=sys.stderr,
            )
            return 1

    # --- Current-only mode: skip git comparison ---
    if current_only:
        print(f"[PASS] ISA stability check (current-only): isa={current_isa} sha256={current_sha[:12]}...")
        return 0

    # --- Get previous commit hash ---
    prev_content = get_previous_commit_hash_file(hash_file)
    if prev_content is None:
        logger.info(
            "No previous commit hash found for %s — first run, treating as stable.",
            hash_file,
        )
        print(f"[PASS] ISA stability check (first run): isa={current_isa}")
        return 0

    prev_isa, prev_sha = parse_hash_content(prev_content)
    logger.info("Previous ISA version : %s", prev_isa)
    logger.info("Previous sha256      : %s", prev_sha)

    # --- Stability logic ---
    isa_changed = (prev_isa != current_isa)
    hash_changed = (prev_sha != current_sha)

    if not isa_changed:
        # ISA unchanged — any hash drift is informational
        if hash_changed:
            logger.info(
                "Hash changed but ISA version unchanged (%s). "
                "Schedule was re-tuned; cache remains valid.",
                current_isa,
            )
        print(
            f"[PASS] ISA stable: isa={current_isa} "
            f"hash={'changed' if hash_changed else 'unchanged'}"
        )
        return 0

    # ISA version changed
    if hash_changed:
        if reload_cache:
            print(
                f"[PASS] ISA version changed ({prev_isa} → {current_isa}) "
                f"and hash differs — --reload-cache flag acknowledged. Cache invalidated."
            )
            logger.info(
                "ICA-V7-TVM-ISA-STABILITY: ISA changed %s → %s, cache reloaded.",
                prev_isa, current_isa,
            )
            return 0
        else:
            msg = (
                f"[FAIL] ICA-V7-TVM-ISA-STABILITY: ISA version changed "
                f"({prev_isa} → {current_isa}) AND hash differs "
                f"({prev_sha[:12]}... → {current_sha[:12]}...). "
                f"Pass --reload-cache to acknowledge ISA change and re-tune."
            )
            print(msg, file=sys.stderr)
            logger.error(msg)
            return 1
    else:
        # ISA changed but hash is the same — suspicious but permitted
        logger.warning(
            "ISA version changed (%s → %s) but hash is identical. "
            "Verify that ISA change is intentional and schedule is still valid.",
            prev_isa, current_isa,
        )
        print(
            f"[WARN] ISA version changed ({prev_isa} → {current_isa}) "
            f"but hash unchanged — verify manually."
        )
        return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    p = argparse.ArgumentParser(
        description="ISA stability check for TVM-VTA AutoTVM (ICA-V7-TVM-ISA-STABILITY)",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument(
        "--hash-file", default=DEFAULT_HASH_FILE,
        help="Path to tuned_schedule_hash.txt",
    )
    p.add_argument(
        "--reload-cache", action="store_true",
        help="Acknowledge ISA version change and allow hash mismatch",
    )
    p.add_argument(
        "--current-only", action="store_true",
        help="Only validate current hash file, skip git comparison",
    )
    p.add_argument(
        "--log-file", default="tuned_log.json",
        help="Path to tuned_log.json (for ISA version cross-check)",
    )
    p.add_argument(
        "--verbose", "-v", action="store_true",
        help="Enable verbose logging",
    )
    return p.parse_args()


def main() -> int:
    """Main entry point."""
    args = parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    logger.info("=== ISA Stability Check ===")
    logger.info("Anchor       : %s", ANCHOR)
    logger.info("Expected ISA : %s", EXPECTED_ISA_VERSION)
    logger.info("Hash file    : %s", args.hash_file)
    logger.info("Reload cache : %s", args.reload_cache)

    # Cross-check ISA in tuned_log.json
    log_isa = get_isa_from_log(args.log_file)
    if log_isa and log_isa != EXPECTED_ISA_VERSION:
        logger.warning(
            "tuned_log.json isa_version='%s' != expected '%s'",
            log_isa, EXPECTED_ISA_VERSION,
        )

    return check_stability(
        hash_file=args.hash_file,
        reload_cache=args.reload_cache,
        current_only=args.current_only,
    )


if __name__ == "__main__":
    sys.exit(main())
