#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 Vasilev Dmitrii <admin@t27.ai>
#
# triadx_sha256.py — offline SHA256 of $writememh / $fwrite hex byte stream
#
# Document ID : TRI-1-VERIFY-20260515-TRIAD-X
# Usage:
#   python3 triadx_sha256.py <hex_file>
#
# Input format: one 16-bit hex word per line (e.g. "47C0")
#   - 100 lines expected (ITER_COUNT = 100)
#   - Each line decoded as big-endian 2-byte word
#   - Total: 200 bytes input to SHA256
#
# Output: SHA256 hexdigest printed to stdout (64 hex chars)
#
# Anchor: phi^2 + phi^-2 = 3 · Wave-24 RVR-018 · EPIC #61 W15-TT-E
#         DOI 10.5281/zenodo.19227877

import sys
import hashlib
import os

def compute_sha256(hex_file: str) -> str:
    """
    Read a hex file with one 16-bit word per line, decode to bytes (big-endian),
    and return the SHA256 hexdigest of the 200-byte stream.
    """
    if not os.path.isfile(hex_file):
        raise FileNotFoundError(f"Hex file not found: {hex_file}")

    words = []
    with open(hex_file, "r") as f:
        for line_no, line in enumerate(f, 1):
            stripped = line.strip()
            if not stripped:
                continue
            # Accept pure hex, no prefix
            word_val = int(stripped, 16)
            # Clamp to 16 bits (defensive)
            word_val = word_val & 0xFFFF
            words.append(word_val)

    if len(words) != 100:
        raise ValueError(
            f"Expected 100 result words, found {len(words)} in {hex_file}"
        )

    # Encode as big-endian bytes: 100 × 2 = 200 bytes
    byte_stream = bytearray()
    for w in words:
        byte_stream.append((w >> 8) & 0xFF)   # high byte
        byte_stream.append(w & 0xFF)           # low byte

    assert len(byte_stream) == 200, f"Byte stream length {len(byte_stream)} != 200"

    digest = hashlib.sha256(bytes(byte_stream)).hexdigest()
    return digest


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <hex_file>", file=sys.stderr)
        sys.exit(1)

    hex_file = sys.argv[1]
    try:
        digest = compute_sha256(hex_file)
        print(digest)
    except (FileNotFoundError, ValueError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
