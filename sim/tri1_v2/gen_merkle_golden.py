#!/usr/bin/env python3
# gen_merkle_golden.py — Golden reference for trinity_merkle_agg 3-round XOR+rotate combiner
# Apache-2.0  |  DOI: 10.5281/zenodo.19227877
#
# Produces $readmemh-compatible hex files for the testbench.
# Usage: python3 gen_merkle_golden.py
#        → merkle_stim.mem  (leaf0 leaf1 leaf2 leaf3  per line, space-separated hex)
#        → merkle_gold.mem  (expected root per line, hex)

import struct, sys, os

MASK64 = (1 << 64) - 1

def rotl64(x, n):
    return ((x << n) | (x >> (64 - n))) & MASK64

def hash_combine(a, b):
    """3-round XOR+rotate — must match trinity_merkle_agg.v exactly."""
    s0  = (a ^ b) & MASK64
    s1  = rotl64(s0, 5)  ^ a & MASK64;  s1 &= MASK64
    s2  = rotl64(s1, 11) ^ b & MASK64;  s2 &= MASK64
    out = rotl64(s2, 22) ^ a ^ b;       out &= MASK64
    return out

def merkle_root(l0, l1, l2, l3):
    n01 = hash_combine(l0, l1)
    n23 = hash_combine(l2, l3)
    return hash_combine(n01, n23)

# -----------------------------------------------------------
# Deterministic test vectors (8)
# -----------------------------------------------------------
det_vectors = [
    # (leaf0, leaf1, leaf2, leaf3, label)
    (0x0000000000000000, 0x0000000000000000,
     0x0000000000000000, 0x0000000000000000, "all_zero"),

    (0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF,
     0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF, "all_ones"),

    (0x0000000000000001, 0x0000000000000000,
     0x0000000000000000, 0x0000000000000000, "single_bit_L0"),

    (0x0000000000000000, 0x8000000000000000,
     0x0000000000000000, 0x0000000000000000, "single_bit_L1"),

    (0x0001020304050607, 0x08090A0B0C0D0E0F,
     0x1011121314151617, 0x18191A1B1C1D1E1F, "ascending"),

    (0xF8F9FAFBFCFDFEFF, 0xF0F1F2F3F4F5F6F7,
     0xE8E9EAEBECEDEEEF, 0xE0E1E2E3E4E5E6E7, "descending"),

    (0xDEADBEEFCAFEBABE, 0x0123456789ABCDEF,
     0xFEDCBA9876543210, 0xA5A5A5A5A5A5A5A5, "mixed"),

    (0x5555555555555555, 0xAAAAAAAAAAAAAAAA,
     0x3333333333333333, 0xCCCCCCCCCCCCCCCC, "alternating"),
]

# -----------------------------------------------------------
# LFSR random vectors (80) — 16-bit Galois LFSR, poly x^16+x^15+x^13+x^4+1
# Four consecutive LFSR values form one 64-bit leaf
# -----------------------------------------------------------
def lfsr16_next(state):
    bit = state & 1
    state >>= 1
    if bit:
        state ^= 0xB400   # taps: 15,13,12,10 → 0xB400
    return state & 0xFFFF

def lfsr_leaf(state):
    words = []
    for _ in range(4):
        state = lfsr16_next(state)
        words.append(state)
    val = (words[0] << 48) | (words[1] << 32) | (words[2] << 16) | words[3]
    return val & MASK64, state

lfsr_state = 0xACE1  # seed
rand_vectors = []
for i in range(80):
    l0, lfsr_state = lfsr_leaf(lfsr_state)
    l1, lfsr_state = lfsr_leaf(lfsr_state)
    l2, lfsr_state = lfsr_leaf(lfsr_state)
    l3, lfsr_state = lfsr_leaf(lfsr_state)
    rand_vectors.append((l0, l1, l2, l3, f"lfsr_{i:02d}"))

all_vectors = det_vectors + rand_vectors

# -----------------------------------------------------------
# Write stim + gold mem files
# -----------------------------------------------------------
out_dir = os.path.dirname(os.path.abspath(__file__))
stim_path = os.path.join(out_dir, "merkle_stim.mem")
gold_path = os.path.join(out_dir, "merkle_gold.mem")

with open(stim_path, "w") as fs, open(gold_path, "w") as fg:
    for (l0, l1, l2, l3, label) in all_vectors:
        root = merkle_root(l0, l1, l2, l3)
        fs.write(f"{l0:016x} {l1:016x} {l2:016x} {l3:016x}  // {label}\n")
        fg.write(f"{root:016x}  // root({label})\n")

print(f"Wrote {len(all_vectors)} vectors to:")
print(f"  {stim_path}")
print(f"  {gold_path}")

# Also print as Verilog include-able `localparam` block for embedded golden
print("\n// Verilog golden reference (first 10 vectors):")
for (l0, l1, l2, l3, label) in all_vectors[:10]:
    root = merkle_root(l0, l1, l2, l3)
    print(f"// {label}: root=64'h{root:016X}")
