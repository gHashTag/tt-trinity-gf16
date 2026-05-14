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
bitnet_4layer.py — Synthetic 4-layer BitNet block using TVM Relay.

Architecture:
    Input → Linear(ternary) → BatchNorm-like → SignActivation
          → Linear(ternary) → BatchNorm-like → SignActivation
          → Linear(ternary) → BatchNorm-like → SignActivation
          → Linear(ternary) → Output

Ternary weights encoded as 2-bit (sign, valid) per S-52 2-hot scheme.
Batch dimension is 1 for inference (batch_size=1 from VTA config).

PEP-8 compliant. TVM imports wrapped in try/except for soft-fail.
"""

import os
import json
import logging
from typing import Tuple, Dict, Any, Optional

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Soft-import TVM
# ---------------------------------------------------------------------------
try:
    import tvm
    import tvm.relay as relay
    import tvm.relay.transform as transform
    from tvm import nd
    import numpy as np
    TVM_AVAILABLE = True
except ImportError:
    TVM_AVAILABLE = False
    logger.warning(
        "TVM not installed — bitnet_4layer.py runs in stub mode. "
        "Install Apache TVM to enable full Relay graph construction."
    )

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
ANCHOR = "phi^2 + phi^-2 = 3"
ISA_VERSION = "trinity-v7.0"
RANDOM_SEED = 42

# Default BitNet layer dimensions for 4x(2x2) PE mesh
# Chosen to be multiples of tile_w=8 and tile_h=2
DEFAULT_LAYER_DIMS = [
    (128, 64),   # Layer 0: in=128, out=64
    (64, 64),    # Layer 1: in=64,  out=64
    (64, 64),    # Layer 2: in=64,  out=64
    (64, 32),    # Layer 3: in=64,  out=32
]

# ---------------------------------------------------------------------------
# Ternary weight helpers (numpy, for reference / simulation)
# ---------------------------------------------------------------------------

def generate_ternary_weights(
    shape: Tuple[int, ...],
    seed: int = RANDOM_SEED,
) -> "np.ndarray":
    """Generate random ternary weight matrix in {-1, 0, +1}.

    Uses NumPy with pinned seed=42 for DREAMPlace / AutoTVM consistency.
    """
    if not TVM_AVAILABLE:
        raise RuntimeError("NumPy not available without TVM environment.")
    rng = np.random.default_rng(seed)
    raw = rng.integers(-1, 2, size=shape)  # uniform in {-1, 0, +1}
    return raw.astype(np.int8)


def ternary_to_2hot(weights: "np.ndarray") -> Tuple["np.ndarray", "np.ndarray"]:
    """Encode ternary weights as (sign, valid) 2-hot per S-52.

    sign  = 1 if weight == -1 else 0
    valid = 1 if weight != 0  else 0
    """
    sign = (weights < 0).astype(np.uint8)
    valid = (weights != 0).astype(np.uint8)
    return sign, valid


def pack_ternary_2bit(weights: "np.ndarray") -> "np.ndarray":
    """Pack ternary weights into 2-bit format: bit1=sign, bit0=valid.

    Output dtype is uint8, each element stores one packed 2-bit value.
    """
    sign, valid = ternary_to_2hot(weights)
    packed = (sign << 1) | valid
    return packed.astype(np.uint8)


# ---------------------------------------------------------------------------
# Relay graph construction
# ---------------------------------------------------------------------------

def _make_dense_ternary(
    x: "relay.Expr",
    weight_data: "np.ndarray",
    out_features: int,
    layer_name: str,
) -> "relay.Expr":
    """Create a dense (fully-connected) layer with ternary weights.

    The weight is quantized to int8 (values in {-1, 0, +1}).
    In the actual VTA flow, these would be further lowered to 2-bit.
    """
    w_const = relay.const(weight_data, dtype="int8")
    # Dense: (batch, in_features) x (out_features, in_features)^T
    out = relay.nn.dense(x, w_const, out_dtype="int32")
    return out


def _make_batchnorm_like(
    x: "relay.Expr",
    num_features: int,
    layer_name: str,
) -> "relay.Expr":
    """Batch-normalization-like layer: scale + bias (affine only, no running stats).

    Implemented as element-wise multiply + add, matching VTA ALU_MUL / ALU_ADD opcodes.
    """
    # Unit scale and zero bias for structural correctness in relay graph
    scale = relay.const(
        np.ones((num_features,), dtype="float32"), dtype="float32"
    )
    bias = relay.const(
        np.zeros((num_features,), dtype="float32"), dtype="float32"
    )
    # Cast accumulator to float32 for BN
    x_f = relay.cast(x, "float32")
    x_scaled = relay.multiply(x_f, scale)
    x_biased = relay.add(x_scaled, bias)
    return x_biased


def _make_sign_activation(x: "relay.Expr", layer_name: str) -> "relay.Expr":
    """Ternary sign activation: out = sign(x).

    Maps to ALU_SIGN opcode.  For relay representation we use:
        sign_activation(x) = clip(floor(x * inf + 0.5), -1, 1)
    approximated via relay.sign (when available) or custom op.
    """
    # relay.sign returns {-1, 0, +1} for negative, zero, positive
    if hasattr(relay, "sign"):
        return relay.sign(x)
    # Fallback: tanh(large_scale * x) rounded — structural placeholder
    scaled = relay.multiply(x, relay.const(1e6, dtype="float32"))
    return relay.clip(relay.cast(relay.round(scaled), "float32"),
                      a_min=-1.0, a_max=1.0)


def build_bitnet_4layer(
    layer_dims: Optional[list] = None,
    seed: int = RANDOM_SEED,
    batch_size: int = 1,
) -> Tuple["relay.Function", Dict[str, Any]]:
    """Build a 4-layer ternary BitNet block in TVM Relay.

    Returns:
        (relay_func, params_dict)

    The graph structure is:
        input → [Linear(ternary) → BN-like → SignAct] x3 → Linear(ternary) → output

    Weights are random ternary (int8 in {-1,0,+1}) with pinned seed=42.
    """
    if not TVM_AVAILABLE:
        raise RuntimeError(
            "TVM is required to build the Relay graph. "
            "Install Apache TVM: https://tvm.apache.org/docs/install/"
        )

    if layer_dims is None:
        layer_dims = DEFAULT_LAYER_DIMS

    assert len(layer_dims) == 4, "Expected exactly 4 (in, out) layer dimension pairs."

    in_features = layer_dims[0][0]
    # Input: shape (batch_size, in_features), dtype int8 (ternary input)
    x = relay.var("input", shape=(batch_size, in_features), dtype="int8")

    # Precompute weights (ternary int8)
    weights = []
    for i, (in_f, out_f) in enumerate(layer_dims):
        w = generate_ternary_weights(
            (out_f, in_f), seed=seed + i  # vary seed per layer
        )
        weights.append(w)

    # Build layers
    h = x
    for i in range(3):  # First 3 layers: Linear → BN → Sign
        in_f, out_f = layer_dims[i]
        h = _make_dense_ternary(h, weights[i], out_f, f"layer{i}")
        h = _make_batchnorm_like(h, out_f, f"layer{i}_bn")
        h = _make_sign_activation(h, f"layer{i}_act")

    # Layer 3: Linear only (output logits)
    in_f, out_f = layer_dims[3]
    h = _make_dense_ternary(h, weights[3], out_f, "layer3")

    # Wrap in relay function
    func = relay.Function(relay.analysis.free_vars(h), h)
    func = relay.ir.build_module.bind_params_by_name(func, {})

    params: Dict[str, Any] = {
        f"layer{i}_weight": weights[i] for i in range(4)
    }

    logger.info(
        "Built 4-layer BitNet Relay graph: dims=%s, isa=%s, anchor=%s",
        layer_dims, ISA_VERSION, ANCHOR,
    )
    return func, params


def get_relay_module(
    layer_dims: Optional[list] = None,
    seed: int = RANDOM_SEED,
    batch_size: int = 1,
) -> Tuple["tvm.IRModule", Dict[str, Any]]:
    """Wrap build_bitnet_4layer into a full tvm.IRModule.

    This is the entry point used by autotune_S51.py.
    """
    if not TVM_AVAILABLE:
        raise RuntimeError("TVM not available.")

    func, params = build_bitnet_4layer(layer_dims, seed, batch_size)
    mod = tvm.IRModule.from_expr(func)
    # Apply standard relay passes: type inference + dead code elimination
    mod = transform.InferType()(mod)
    mod = transform.EliminateCommonSubexpr()(mod)
    return mod, params


def describe_workload(layer_dims: Optional[list] = None) -> Dict[str, Any]:
    """Return a JSON-serialisable description of the BitNet workload.

    Used for logging and ISA stability tracking.
    """
    if layer_dims is None:
        layer_dims = DEFAULT_LAYER_DIMS
    return {
        "isa_version": ISA_VERSION,
        "anchor": ANCHOR,
        "stream": "W15-TT-I / S-51",
        "batch_size": 1,
        "num_layers": 4,
        "layer_dims": layer_dims,
        "weight_bits": 2,
        "input_bits": 2,
        "accum_bits": 16,
        "encoding": "ternary-2hot",
        "seed": RANDOM_SEED,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    """Print workload description and attempt to build Relay module."""
    logging.basicConfig(level=logging.INFO)
    desc = describe_workload()
    print(json.dumps(desc, indent=2))

    if TVM_AVAILABLE:
        mod, params = get_relay_module()
        print("\nRelay module (pretty-printed):")
        print(mod)
        print(f"\nParam keys: {list(params.keys())}")
    else:
        print("\n[WARN] TVM not installed — Relay graph not built (stub mode).")


if __name__ == "__main__":
    main()
