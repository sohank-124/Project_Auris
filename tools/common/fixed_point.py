"""
Project Auris — Q2.14 fixed-point and dB conversion utilities.

The Project Auris DSP fabric operates in **Q2.14** signed fixed-point
format: 2 integer bits (including sign) and 14 fractional bits, stored
in a 16-bit two's-complement word. The representable range is
``[-2.0, +1.99994]`` with an LSB of ``1 / 2^14 ~= 6.1035e-5``.

M19: Gain tables are now emitted as single 16-bit Q2.14 words per bin
(not the previous mantissa+shift pair).  ``db_to_q2_14_signed``
replaces the old ``db_to_q0_14`` for the production toolchain; the
latter is retained as a deprecated stub for backward compatibility.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path
from typing import Iterable, List, Tuple

# Make ``python tools/common/fixed_point.py`` work from any cwd.
_TOOLS_DIR = Path(__file__).resolve().parent.parent
if str(_TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOLS_DIR))

try:
    from .constants import (
        Q_FRAC,
        Q_SCALE,
        Q_MIN,
        Q_MAX,
        GAIN_DB_MIN,
        GAIN_DB_MAX,
    )
except ImportError:
    from common.constants import (
        Q_FRAC,
        Q_SCALE,
        Q_MIN,
        Q_MAX,
        GAIN_DB_MIN,
        GAIN_DB_MAX,
    )


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------
def _check_finite(x: float, name: str = "value") -> None:
    """Reject NaN; coerce -inf to ``-2.0`` (the most negative Q2.14)."""
    if x != x:                       # NaN check (x != x only for NaN)
        raise ValueError(f"{name} is NaN")
    if x == float("-inf"):
        # Caller can detect this if it wants, but we return early below.
        return


# ---------------------------------------------------------------------------
# Q2.14 <-> float
# ---------------------------------------------------------------------------
def float_to_q2_14(x: float, round_mode: str = "round") -> int:
    """Convert ``x`` to a Q2.14 signed 16-bit integer.

    Parameters
    ----------
    x : float
        Real value to convert. Theoretically in ``[-2.0, +1.99994]``.
    round_mode : str
        ``"round"`` uses banker's rounding (via :func:`round`);
        ``"floor"`` truncates toward negative infinity;
        ``"truncate"`` truncates toward zero.

    Returns
    -------
    int
        Saturated, two's-complement 16-bit value in ``[-32768, 32767]``.

    Notes
    -----
    * ``NaN`` raises :class:`ValueError`.
    * ``-inf`` is clamped to ``-2.0`` (the most negative Q2.14 value).
    * ``+inf`` and finite values ``>= 2.0`` saturate to ``+1.99994``.
    """
    if x != x:                       # NaN
        raise ValueError(f"float_to_q2_14: x is NaN")
    if x == float("-inf"):
        x = -2.0
    if x == float("+inf"):
        x = 1.99993896484375         # 32767 / 16384

    # Clamp to representable range (using Q_MAX / Q_SCALE for the upper bound
    # so we never accidentally encode a 2.0 which would overflow back to 0).
    upper = Q_MAX / Q_SCALE
    lower = Q_MIN / Q_SCALE         # -2.0 exactly
    if x > upper:
        x = upper
    if x < lower:
        x = lower

    if round_mode == "round":
        v = int(round(x * Q_SCALE))
    elif round_mode == "floor":
        v = math.floor(x * Q_SCALE)
    elif round_mode == "truncate":
        v = int(x * Q_SCALE)         # truncates toward zero
    else:
        raise ValueError(
            f"float_to_q2_14: unknown round_mode {round_mode!r} "
            "(expected 'round', 'floor', or 'truncate')"
        )

    return saturate(v)


def q2_14_to_float(v: int) -> float:
    """Convert a Q2.14 16-bit integer back to a float.

    The value is interpreted as a signed 16-bit two's-complement integer
    (so any raw unsigned 16-bit value can be passed in; the function
    applies the sign extension internally).
    """
    v = int(v) & 0xFFFF
    if v & 0x8000:
        v -= 0x10000
    return v / Q_SCALE


def saturate(v: int, lo: int = Q_MIN, hi: int = Q_MAX) -> int:
    """Clamp integer ``v`` to the closed interval ``[lo, hi]``."""
    if v < lo:
        return lo
    if v > hi:
        return hi
    return v


# ---------------------------------------------------------------------------
# Batched Q2.14 conversions
# ---------------------------------------------------------------------------
def batch_float_to_q2_14(xs: Iterable[float],
                          round_mode: str = "round") -> List[int]:
    """Vectorised wrapper around :func:`float_to_q2_14`."""
    return [float_to_q2_14(x, round_mode=round_mode) for x in xs]


def batch_q2_14_to_float(vs: Iterable[int]) -> List[float]:
    """Vectorised wrapper around :func:`q2_14_to_float`."""
    return [q2_14_to_float(v) for v in vs]


# ---------------------------------------------------------------------------
# dB <-> linear
# ---------------------------------------------------------------------------
def db_to_linear(db: float) -> float:
    """Convert decibels to a linear amplitude ratio.

    ``db_to_linear(0) == 1.0``, ``db_to_linear(-20) == 0.1``,
    ``db_to_linear(+20) == 10.0``.
    """
    return 10.0 ** (db / 20.0)


def linear_to_db(lin: float) -> float:
    """Convert a linear amplitude ratio to decibels.

    Returns ``-inf`` for ``lin == 0`` and preserves the sign of ``lin``
    (i.e. ``linear_to_db(-1) == 0.0``). For an unsigned signal the
    caller should pass ``abs(lin)``.
    """
    if lin == 0.0:
        return float("-inf")
    return 20.0 * math.log10(abs(lin))


# ---------------------------------------------------------------------------
# Gain table: dB -> Q2.14 signed
# ---------------------------------------------------------------------------
def db_to_q2_14_signed(db: float, round_mode: str = "round") -> int:
    """Convert a gain in dB to a single 16-bit Q2.14 signed word.

    M19: replaces the deprecated ``db_to_q0_14`` (mantissa+shift pair)
    for the production toolchain.  Each gain bin is now a single
    16-bit Q2.14 word.  The signed format covers ``[-2.0, +1.99994]``
    which is sufficient for the project's ``[-24, +24] dB`` gain range
    (since gain = 10**(dB/20) maps to ``[0.0631, 15.85]``).

    Parameters
    ----------
    db : float
        Gain in dB; clamped to ``[GAIN_DB_MIN, GAIN_DB_MAX]`` before
        conversion.
    round_mode : str
        Forwarded to :func:`float_to_q2_14`.

    Returns
    -------
    int
        16-bit signed Q2.14 value in ``[-32768, 32767]`` (mask to 16
        bits at the call site if a raw unsigned word is needed).
    """
    if db != db:                    # NaN
        raise ValueError("db_to_q2_14_signed: db is NaN")

    # Clamp to the supported range.
    if db < GAIN_DB_MIN:
        db = GAIN_DB_MIN
    if db > GAIN_DB_MAX:
        db = GAIN_DB_MAX

    lin = db_to_linear(db)
    return float_to_q2_14(lin, round_mode=round_mode)


# ---------------------------------------------------------------------------
# Deprecated: db_to_q0_14 (mantissa+shift pair) -- retained for callers
# that have not yet migrated to db_to_q2_14_signed.  Issues a warning.
# ---------------------------------------------------------------------------
def db_to_q0_14(db: float) -> Tuple[int, int]:  # pragma: no cover
    """DEPRECATED.  Use :func:`db_to_q2_14_signed` instead.

    This function is retained for backward compatibility with callers
    that still expect the mantissa+shift representation.  M19: the
    production toolchain now emits single 16-bit Q2.14 words per bin.
    """
    import warnings
    warnings.warn(
        "db_to_q0_14 is deprecated; use db_to_q2_14_signed instead "
        "(M19: single 16-bit Q2.14 word per gain bin).",
        DeprecationWarning,
        stacklevel=2,
    )
    if db != db:
        raise ValueError("db_to_q0_14: db is NaN")
    if db < GAIN_DB_MIN:
        db = GAIN_DB_MIN
    if db > GAIN_DB_MAX:
        db = GAIN_DB_MAX
    lin = db_to_linear(db)
    shift = 0
    while lin >= 2.0 and shift < 15:
        lin *= 0.5
        shift += 1
    while lin < 1.0 and shift > 0:
        lin *= 2.0
        shift -= 1
    if shift < 0:
        shift = 0
    if shift > 15:
        shift = 15
    mantissa = int(round(lin * Q_SCALE))
    if mantissa < 0:
        mantissa = 0
    if mantissa > 0x7FFF:
        mantissa = 0x7FFF
    return (mantissa, shift)


# ---------------------------------------------------------------------------
# CLI smoke test
# ---------------------------------------------------------------------------
def _cli() -> None:                 # pragma: no cover
    import argparse
    p = argparse.ArgumentParser(
        description="Q2.14 conversion smoke test",
    )
    p.add_argument("--db", type=float, default=0.0,
                   help="dB value to convert (Q2.14 signed path)")
    p.add_argument("--float", type=float, default=None,
                   help="float value to convert (Q2.14 path)")
    args = p.parse_args()

    if args.float is not None:
        q = float_to_q2_14(args.float)
        print(f"float {args.float:+.6f} -> Q2.14 {q:6d} (0x{q & 0xFFFF:04X}) "
              f"-> {q2_14_to_float(q):+.6f}")
    else:
        q = db_to_q2_14_signed(args.db)
        lin = db_to_linear(args.db)
        recon = q2_14_to_float(q)
        print(f"db {args.db:+.2f} -> linear {lin:.6f}  "
              f"= Q2.14 {q:6d} (0x{q & 0xFFFF:04X})  "
              f"reconstructed {recon:.6f}  "
              f"error {(recon - lin):+.3e}")


if __name__ == "__main__":
    _cli()
