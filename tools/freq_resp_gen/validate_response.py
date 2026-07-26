"""
Project Auris — Frequency-response validation utilities.

Provides the offline analyses that the audio team uses to sign off a
gain-table / filter bitstream before it is burned into the FPGA:

* :func:`check_flatness` — deviation from a flat (constant) target.
* :func:`measure_ripple` — peak-to-peak ripple in a response curve.
* :func:`compute_group_delay` — per-frequency group delay (samples)
  for a (b, a) IIR filter, via SciPy's :func:`freqz` if available or a
  hand-rolled DFT otherwise.
* :func:`validate_gain_response` — gain-curve sanity check against an
  expected reference.
"""

from __future__ import annotations

import argparse
import cmath
import math
import sys
from pathlib import Path
from typing import List, Sequence, Tuple

_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import FS, TOL_DB


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
def check_flatness(gains_db: List[float],
                   tol_db: float = 0.5) -> Tuple[bool, float]:
    """Return ``(ok, max_deviation)`` for a gain curve.

    The "flat" target is the mean of the input; the deviation of every
    sample from the mean is computed and the worst case is returned.
    """
    if not gains_db:
        raise ValueError("check_flatness: gains_db is empty")
    mean = sum(gains_db) / len(gains_db)
    devs = [abs(g - mean) for g in gains_db]
    max_dev = max(devs)
    return (max_dev <= tol_db, max_dev)


def measure_ripple(gains_db: List[float]) -> Tuple[float, float, float]:
    """Return ``(peak_to_peak_db, max_db, min_db)`` of a gain curve.

    ``peak_to_peak_db`` is the largest difference between any two
    consecutive samples (worst-case local ripple), not the global
    ``max - min`` of the array.  ``max_db`` and ``min_db`` are the
    global extremes.
    """
    if not gains_db:
        raise ValueError("measure_ripple: gains_db is empty")
    if len(gains_db) < 2:
        return (0.0, gains_db[0], gains_db[0])

    max_db = gains_db[0]
    min_db = gains_db[0]
    peak_to_peak = 0.0
    for i in range(1, len(gains_db)):
        g = gains_db[i]
        if g > max_db:
            max_db = g
        if g < min_db:
            min_db = g
        d = abs(g - gains_db[i - 1])
        if d > peak_to_peak:
            peak_to_peak = d
    return (peak_to_peak, max_db, min_db)


def compute_group_delay(b: Sequence[float],
                        a: Sequence[float],
                        n_points: int = 512,
                        fs: float = FS) -> List[float]:
    """Compute the group delay of an IIR filter (b, a).

    Group delay is defined as ``tau(omega) = -d phi / d omega`` where
    ``phi(omega)`` is the phase of the filter's complex frequency
    response.  We compute it numerically as a centred finite-difference
    of the unwrapped phase on a uniform grid of ``n_points`` between
    ``0`` and ``pi`` (inclusive).  The output is in samples.

    SciPy's :func:`scipy.signal.group_delay` is used when available; if
    not, a hand-rolled DFT-based implementation is used (slower but
    correct for any reasonably small filter).
    """
    if not b or not a:
        raise ValueError("compute_group_delay: empty b or a")
    if n_points < 3:
        raise ValueError(
            f"compute_group_delay: n_points must be >= 3 (got {n_points})"
        )

    # Try SciPy first.
    try:
        from scipy.signal import group_delay as _gd          # type: ignore
        # SciPy returns (w, tau) in radians and seconds; we want samples
        # so divide tau by the sample period.
        w, tau = _gd(b, a, worN=n_points, fs=fs)
        return [float(t) * fs for t in tau]   # SciPy returns seconds; convert to samples
    except Exception:
        pass

    # Hand-rolled: evaluate H(omega) on a grid and differentiate the
    # phase using a centred difference.
    out: List[float] = []
    omegas = [math.pi * k / (n_points - 1) for k in range(n_points)]
    # Pre-compute the numerator / denominator of H(omega) for each
    # omega; phase unwrap is done as we go.
    last_phase = None
    h_vals: List[complex] = []
    for w in omegas:
        num = complex(sum(bk * cmath.exp(-1j * w * k)
                          for k, bk in enumerate(b)), 0.0)
        den = complex(sum(ak * cmath.exp(-1j * w * k)
                          for k, ak in enumerate(a)), 0.0)
        h_vals.append(num / den if abs(den) > 0 else complex(float("inf"), 0.0))

    # Unwrap the phase.
    phases: List[float] = []
    last = 0.0
    for h in h_vals:
        p = cmath.phase(h)
        if last_phase is not None:
            d = p - last_phase
            if d > math.pi:
                p -= 2.0 * math.pi
            elif d < -math.pi:
                p += 2.0 * math.pi
        last_phase = p
        phases.append(p)

    # Centred finite difference; use forward / backward at the ends.
    for k in range(n_points):
        if k == 0:
            dphi = phases[1] - phases[0]
            dw = omegas[1] - omegas[0]
        elif k == n_points - 1:
            dphi = phases[-1] - phases[-2]
            dw = omegas[-1] - omegas[-2]
        else:
            dphi = phases[k + 1] - phases[k - 1]
            dw = omegas[k + 1] - omegas[k - 1]
        tau = -dphi / dw if dw != 0 else 0.0
        out.append(float(tau))
    return out


def validate_gain_response(gains_db: List[float],
                            expected: List[float],
                            tol_db: float = TOL_DB
                            ) -> Tuple[bool, float]:
    """Compare a measured gain curve against an expected reference.

    Returns ``(ok, max_error_db)``.  ``ok`` is True if every element of
    ``gains_db`` lies within ``+/- tol_db`` of the corresponding element
    of ``expected``.
    """
    if len(gains_db) != len(expected):
        raise ValueError(
            f"validate_gain_response: length mismatch "
            f"({len(gains_db)} vs {len(expected)})"
        )
    if not gains_db:
        return (True, 0.0)
    max_err = max(abs(g - e) for g, e in zip(gains_db, expected))
    return (max_err <= tol_db, max_err)


# ---------------------------------------------------------------------------
# I/O helpers
# ---------------------------------------------------------------------------
def _read_gain_file(path: Path) -> List[float]:
    out: List[float] = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            try:
                out.append(float(s.split(",")[0].split()[0]))
            except ValueError:
                continue
    return out


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Validate a frequency / gain response curve.",
    )
    p.add_argument("--input-file", type=Path, required=True,
                   help="Measured gain file (one float per line).")
    p.add_argument("--expected-file", type=Path, default=None,
                   help="Expected gain file (one float per line).")
    p.add_argument("--tol", type=float, default=TOL_DB,
                   help="Tolerance in dB (default: %(default)s)")
    args = p.parse_args(argv)

    gains = _read_gain_file(args.input_file)
    if not gains:
        raise SystemExit(f"error: no data read from {args.input_file}")
    print(f"Loaded {len(gains)} gain values from {args.input_file}")

    ok_flat, dev = check_flatness(gains, tol_db=args.tol)
    print(f"Flatness check: {'PASS' if ok_flat else 'FAIL'}  "
          f"(max deviation = {dev:.3f} dB, tol = {args.tol} dB)")

    p2p, g_max, g_min = measure_ripple(gains)
    print(f"Ripple: peak-to-peak = {p2p:.3f} dB, "
          f"max = {g_max:.3f} dB, min = {g_min:.3f} dB")

    if args.expected_file is not None:
        expected = _read_gain_file(args.expected_file)
        ok, err = validate_gain_response(gains, expected, tol_db=args.tol)
        print(f"Gain-response check: {'PASS' if ok else 'FAIL'}  "
              f"(max error = {err:.3f} dB, tol = {args.tol} dB)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
