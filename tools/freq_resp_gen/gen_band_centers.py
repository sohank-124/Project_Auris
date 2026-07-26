"""
Project Auris — ANSI S1.11 fractional-octave band-center generator.

Generates octave, third-octave, and sixth-octave band center frequencies
according to ANSI S1.11-2004 / IEC 61260: the center of band ``i`` is

    f[i] = 1000 * 10 ** (3 * i / (10 * fraction))

where ``fraction`` is 1 (full octave), 3 (third octave), 6 (sixth
octave), 12 (twelfth octave), etc.

The index range is computed from the requested ``f_min`` / ``f_max``
limits so the returned list always contains at least one center and
typically spans just beyond the requested range.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
from typing import List

# Allow running this file directly: ``python tools/freq_resp_gen/gen_band_centers.py``.
_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
import sys
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
def octave_bands(fraction: int = 1,
                 f_min: float = 20.0,
                 f_max: float = 24000.0) -> List[float]:
    """Return a list of ANSI S1.11 fractional-octave band centers.

    Parameters
    ----------
    fraction : int
        Octave fraction. ``1`` = octave, ``3`` = third-octave, ``6`` =
        sixth-octave, ``12`` = twelfth-octave, etc. Must be a positive
        integer.
    f_min : float
        Lower bound in Hz. Centers strictly below this are dropped.
    f_max : float
        Upper bound in Hz. Centers strictly above this are dropped.

    Returns
    -------
    list of float
        Center frequencies in ascending order.

    Notes
    -----
    * The reference frequency is 1 kHz (band index 0).  Band ``i`` is
      ``f[i] = 1000 * 10^(3*i/(10*fraction))``.
    * When ``f_max`` exceeds the maximum band that the requested
      ``fraction`` can fit under 24 kHz the result is truncated at the
      highest representable band.
    """
    if fraction < 1:
        raise ValueError(f"octave_bands: fraction must be >= 1 (got {fraction})")
    if f_min <= 0.0 or f_max <= 0.0:
        raise ValueError(
            f"octave_bands: f_min and f_max must be positive "
            f"(got {f_min}, {f_max})"
        )
    if f_min > f_max:
        raise ValueError(
            f"octave_bands: f_min ({f_min}) must be <= f_max ({f_max})"
        )

    # The relationship between consecutive centers is a factor of
    # 10 ** (3 / (10 * fraction)) = 2 ** (1 / fraction).
    factor = 10.0 ** (3.0 / (10.0 * fraction))

    # Solve for the indices that bracket [f_min, f_max] around 1000 Hz.
    # i_min = ceil(log10(f_min/1000) * 10 * fraction / 3)
    # i_max = floor(log10(f_max/1000) * 10 * fraction / 3)
    if f_min <= 0:
        i_min = -1000
    else:
        ratio_min = f_min / 1000.0
        if ratio_min <= 0:
            i_min = -1000
        else:
            i_min = math.ceil(math.log10(ratio_min) * 10.0 * fraction / 3.0)

    ratio_max = f_max / 1000.0
    if ratio_max <= 0:
        i_max = -1000
    else:
        i_max = math.floor(math.log10(ratio_max) * 10.0 * fraction / 3.0)

    # Sanity: require at least one center even if the requested range is
    # degenerate (e.g. f_min == f_max at 1 kHz).
    if i_max < i_min:
        i_min, i_max = i_min, i_min

    centers: List[float] = []
    for i in range(i_min, i_max + 1):
        f = 1000.0 * (10.0 ** (3.0 * i / (10.0 * fraction)))
        if f_min <= f <= f_max:
            centers.append(f)

    return centers


def third_octave_bands(f_min: float = 20.0,
                       f_max: float = 24000.0) -> List[float]:
    """Convenience wrapper for ``octave_bands(fraction=3, ...)``."""
    return octave_bands(fraction=3, f_min=f_min, f_max=f_max)


def sixth_octave_bands(f_min: float = 20.0,
                       f_max: float = 24000.0) -> List[float]:
    """Convenience wrapper for ``octave_bands(fraction=6, ...)``."""
    return octave_bands(fraction=6, f_min=f_min, f_max=f_max)


def nearest_band_center(f_hz: float, centers: List[float]) -> float:
    """Return the center from ``centers`` that is closest to ``f_hz``.

    Parameters
    ----------
    f_hz : float
        Query frequency in Hz.
    centers : list of float
        Candidate band centers (Hz). Must be non-empty.

    Returns
    -------
    float
        The single center in ``centers`` with the smallest absolute
        distance to ``f_hz``.  Ties are broken in favour of the lower
        center.

    Raises
    ------
    ValueError
        If ``centers`` is empty.
    """
    if not centers:
        raise ValueError("nearest_band_center: centers list is empty")

    best = centers[0]
    best_d = abs(math.log(f_hz / best)) if f_hz > 0 and best > 0 else abs(f_hz - best)
    for c in centers[1:]:
        d = abs(math.log(f_hz / c)) if f_hz > 0 and c > 0 else abs(f_hz - c)
        if d < best_d:
            best = c
            best_d = d
    return best


# ---------------------------------------------------------------------------
# CLI helpers
# ---------------------------------------------------------------------------
def _print_table(fraction: int, centers: List[float]) -> None:
    if not centers:
        print("(no centers in requested range)")
        return
    print(f"# {len(centers)} band centers, fraction=1/{fraction}")
    print(f"# {'idx':>5s}  {'f_center_Hz':>14s}  {'ratio_to_1k':>14s}")
    for i, f in enumerate(centers):
        print(f"{i:6d}  {f:14.4f}  {f / 1000.0:14.6f}")


def _write_text(out_path: Path, fraction: int, centers: List[float]) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"# Project Auris — ANSI S1.11 1/{fraction}-octave band centers\n")
        f.write(f"# f_min={centers[0] if centers else '-'} Hz, "
                f"f_max={centers[-1] if centers else '-'} Hz\n")
        f.write("idx,f_center_hz,ratio_to_1k\n")
        for i, c in enumerate(centers):
            f.write(f"{i},{c:.6f},{c / 1000.0:.9f}\n")


def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="ANSI S1.11 fractional-octave band-center generator.",
    )
    p.add_argument("--fraction", type=int, default=3, choices=(1, 3, 6, 12, 24),
                   help="Octave fraction (default: %(default)s)")
    p.add_argument("--f-min", type=float, default=20.0,
                   help="Lower bound in Hz (default: %(default)s)")
    p.add_argument("--f-max", type=float, default=24000.0,
                   help="Upper bound in Hz (default: %(default)s)")
    p.add_argument("--out", type=Path, default=None,
                   help="Optional output file (CSV).")
    args = p.parse_args(argv)

    centers = octave_bands(args.fraction, args.f_min, args.f_max)
    print(f"Generated {len(centers)} band centers "
          f"(1/{args.fraction} octave, "
          f"{args.f_min:g}–{args.f_max:g} Hz)")
    _print_table(args.fraction, centers)

    if args.out is not None:
        _write_text(args.out, args.fraction, centers)
        print(f"Wrote {args.out} ({args.out.stat().st_size} bytes)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
