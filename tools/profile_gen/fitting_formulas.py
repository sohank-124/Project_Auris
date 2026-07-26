"""
Project Auris — Prescriptive hearing-aid fitting formulas.

Implements the three formulas used by Project Auris:

* **NAL-R**  (Byrne & Tonisson, 1976; revision 1) — the "half-gain"
  rule with frequency-specific offsets.
* **NAL-NL2** (Keidser et al., 2011) — a non-linear revision that
  weights the audiogram differently across bands.
* **DSL v5**  (Cornelisse et al., 1995) — a Desired Sensation Level
  variant used widely in paediatric fittings.

All formulas accept a 7-element list of dB-HL thresholds at the
standard audiometric frequencies (250, 500, 1k, 2k, 3k, 4k, 6k Hz)
and return a 7-element list of insertion-gain values in dB SPL (or
more precisely, dB relative to the unaided ear-canal level — the
two are equivalent for an insert phone with a 0 dB REUR).

The output of every function is clamped to
``[GAIN_DB_MIN, GAIN_DB_MAX]`` (see :mod:`common.constants`).
"""

from __future__ import annotations

from typing import Dict, List, Tuple

# Make ``python tools/profile_gen/fitting_formulas.py`` work from any cwd.
from pathlib import Path as _Path
import sys as _sys
_TOOLS_DIR = _Path(__file__).resolve().parent.parent
if str(_TOOLS_DIR) not in _sys.path:
    _sys.path.insert(0, str(_TOOLS_DIR))

from common.constants import (
    AUDIOGRAM_FREQS,
    GAIN_DB_MIN,
    GAIN_DB_MAX,
)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------
def _pta3(thresholds: List[float]) -> float:
    """Pure-tone average over 0.5, 1, 2 kHz — the standard NAL/DSL PTA3."""
    if len(thresholds) < 4:
        raise ValueError("Need at least 4 thresholds to compute PTA3")
    return (thresholds[1] + thresholds[2] + thresholds[3]) / 3.0


def _clamp(g: float,
           lo: float = GAIN_DB_MIN,
           hi: float = GAIN_DB_MAX) -> float:
    if g < lo:
        return lo
    if g > hi:
        return hi
    return g


# ---------------------------------------------------------------------------
# Formula tables
# ---------------------------------------------------------------------------
# NAL-R frequency-specific correction (X) values in dB.
_NAL_R_OFFSETS: Dict[int, float] = {
    250:  -17.0,
    500:   -8.0,
    1000:   1.0,
    2000:  -1.0,
    3000:  -4.0,
    4000:  -6.0,
    6000:  -3.0,
}

# NAL-NL2 frequency-specific weights (simplified scalar form).
_NAL_NL2_A: Dict[int, float] = {
    250:  0.30, 500: 0.35, 1000: 0.38, 2000: 0.40,
    3000: 0.42, 4000: 0.40, 6000: 0.35,
}
_NAL_NL2_B: Dict[int, float] = {
    250:  0.10, 500: 0.12, 1000: 0.10, 2000: 0.08,
    3000: 0.06, 4000: 0.05, 6000: 0.04,
}
_NAL_NL2_C: Dict[int, float] = {
    250:  -5.0, 500: -2.0, 1000:  0.0, 2000: -1.0,
    3000: -3.0, 4000: -4.0, 6000: -3.0,
}

# DSL v5 frequency-specific correction terms in dB.
_DSL_V5_CORRECTION: Dict[int, float] = {
    250:  -5.0, 500:  0.0, 1000:  2.0, 2000:  3.0,
    3000:  2.0, 4000:  0.0, 6000: -2.0,
}


# ---------------------------------------------------------------------------
# Formulas
# ---------------------------------------------------------------------------
def nal_r(thresholds: List[float],
          freqs: Tuple[int, ...] = AUDIOGRAM_FREQS) -> List[float]:
    """NAL-R insertion gain with the half-gain rule.

    gain[i] = 0.5 * (0.46 * HL[i] + 0.46 * PTA3 + X[f_i])
    """
    if len(thresholds) != len(freqs):
        raise ValueError(
            f"nal_r: thresholds length {len(thresholds)} != freqs length {len(freqs)}"
        )

    pta3 = _pta3(thresholds)
    gains: List[float] = []
    for hl, f in zip(thresholds, freqs):
        if f not in _NAL_R_OFFSETS:
            raise ValueError(f"nal_r: unsupported frequency {f} Hz")
        x = _NAL_R_OFFSETS[f]
        g = 0.5 * (0.46 * hl + 0.46 * pta3 + x)
        gains.append(_clamp(g))
    return gains


def nal_nl2(thresholds: List[float],
            freqs: Tuple[int, ...] = AUDIOGRAM_FREQS) -> List[float]:
    """Simplified scalar NAL-NL2 formula.

    gain[i] = a[f_i] * HL[i] + b[f_i] * PTA + c[f_i]

    This is the linear-decoupling approximation commonly used as a
    teaching reference; the full NAL-NL2 uses frequency-dependent
    loudness models and is significantly more complex.
    """
    if len(thresholds) != len(freqs):
        raise ValueError(
            f"nal_nl2: thresholds length {len(thresholds)} != freqs length {len(freqs)}"
        )

    pta = _pta3(thresholds)
    gains: List[float] = []
    for hl, f in zip(thresholds, freqs):
        if f not in _NAL_NL2_A:
            raise ValueError(f"nal_nl2: unsupported frequency {f} Hz")
        g = _NAL_NL2_A[f] * hl + _NAL_NL2_B[f] * pta + _NAL_NL2_C[f]
        gains.append(_clamp(g))
    return gains


def dsl_v5(thresholds: List[float],
           freqs: Tuple[int, ...] = AUDIOGRAM_FREQS) -> List[float]:
    """DSL v5 (child) formula — linear HL scaling with corrections.

    gain[i] = 0.6 * HL[i] + correction[f_i]
    """
    if len(thresholds) != len(freqs):
        raise ValueError(
            f"dsl_v5: thresholds length {len(thresholds)} != freqs length {len(freqs)}"
        )

    gains: List[float] = []
    for hl, f in zip(thresholds, freqs):
        if f not in _DSL_V5_CORRECTION:
            raise ValueError(f"dsl_v5: unsupported frequency {f} Hz")
        g = 0.6 * hl + _DSL_V5_CORRECTION[f]
        gains.append(_clamp(g))
    return gains


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
def compute(formula: str,
            thresholds: List[float],
            freqs: Tuple[int, ...] = AUDIOGRAM_FREQS) -> List[float]:
    """Dispatch to the requested prescriptive formula.

    Parameters
    ----------
    formula : str
        ``"nal_r"``, ``"nal_nl2"``, or ``"dsl_v5"``.
    thresholds : list of float
        dB HL at the 7 standard audiometric frequencies.
    freqs : tuple of int
        Reference frequencies (defaults to :data:`AUDIOGRAM_FREQS`).

    Returns
    -------
    list of float
        Insertion gain in dB (length 7).

    Raises
    ------
    ValueError
        If ``formula`` is not recognised.
    """
    f = formula.lower()
    if f == "nal_r":
        return nal_r(thresholds, freqs)
    if f == "nal_nl2":
        return nal_nl2(thresholds, freqs)
    if f == "dsl_v5":
        return dsl_v5(thresholds, freqs)
    raise ValueError(
        f"compute: unknown formula {formula!r} "
        "(expected 'nal_r', 'nal_nl2', or 'dsl_v5')"
    )


# ---------------------------------------------------------------------------
# CLI smoke test
# ---------------------------------------------------------------------------
def _cli() -> None:                 # pragma: no cover
    import argparse
    p = argparse.ArgumentParser(description="Prescriptive formula smoke test")
    p.add_argument("--audiogram",
                   default="0,0,10,25,35,40,45",
                   help="7 dB HL thresholds")
    p.add_argument("--formula", default="nal_r",
                   choices=("nal_r", "nal_nl2", "dsl_v5"))
    args = p.parse_args()

    th = [float(x) for x in args.audiogram.split(",")]
    gains = compute(args.formula, th)
    print(f"Formula: {args.formula}")
    print(f"Audiogram: {th} dB HL")
    for f, g in zip(AUDIOGRAM_FREQS, gains):
        print(f"  f = {f:5d} Hz  ->  gain = {g:+6.2f} dB")


if __name__ == "__main__":
    _cli()
