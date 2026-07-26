"""
Project Auris — Constant Overlap-Add (COLA) checker.

When a window ``w`` of length ``N`` is used with hop size ``H`` and
overlap-added, the reconstructed sum is

.. math::

    s[m] = \\sum_{k} w[m - kH]

The COLA condition is satisfied iff ``s[m]`` is constant for all
``m`` in the overlap region.  The constant-overlap-add property is
required for the OLA-based synthesis filterbank in the FPGA to
reconstruct the output without amplitude modulation.

We check COLA in two regimes:

* :func:`check_cola_condition` — float window, float tolerance.
* :func:`check_cola_fixed_point` — Q2.14 window, tolerance in LSBs.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import List, Tuple

_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import FRAME_ADVANCE


# ---------------------------------------------------------------------------
# Float version
# ---------------------------------------------------------------------------
def check_cola_condition(window: List[float],
                         hop_size: int = FRAME_ADVANCE,
                         tol: float = 1e-6) -> Tuple[bool, float, List[float]]:
    """Check the COLA condition for a window / hop-size pair.

    The function simulates a long overlap-add: a length-``N`` window
    is shifted and added at intervals of ``hop_size`` for ``K``
    frames (where ``K`` is large enough that the central overlap
    region is well-populated).  The maximum absolute deviation of
    the reconstructed sum from its mean is compared against ``tol``.

    Returns
    -------
    (ok, max_dev, sums) : Tuple[bool, float, list[float]]
        ``sums`` is the full reconstruction array (useful for
        debugging).
    """
    if not window:
        return (True, 0.0, [])
    if hop_size < 1:
        raise ValueError(f"check_cola_condition: hop_size must be >= 1 (got {hop_size})")

    n = len(window)
    n_frames = (n // hop_size) * 4 + 8
    total_len = n_frames * hop_size + n
    sums = [0.0] * total_len
    for k in range(n_frames):
        offset = k * hop_size
        for i, w in enumerate(window):
            sums[offset + i] += w
    # Restrict to the interior: drop the first and last N samples so the
    # overlap region is fully populated.
    interior = sums[n:-n] if total_len > 2 * n else sums
    if not interior:
        return (True, 0.0, sums)
    mean = sum(interior) / len(interior)
    max_dev = max(abs(v - mean) for v in interior)
    return (max_dev <= tol, max_dev, sums)


# ---------------------------------------------------------------------------
# Fixed-point version
# ---------------------------------------------------------------------------
def check_cola_fixed_point(window_q14: List[int],
                           hop_size: int = FRAME_ADVANCE,
                           tol_lsbs: int = 2) -> Tuple[bool, int, List[int]]:
    """Fixed-point COLA check.

    The window coefficients are taken as Q2.14 signed integers.  The
    reconstructed sum is a series of integer values whose units are
    "Q2.14 LSBs".  The maximum absolute deviation from the integer
    mean is compared against ``tol_lsbs``.
    """
    if not window_q14:
        return (True, 0, [])
    if hop_size < 1:
        raise ValueError(
            f"check_cola_fixed_point: hop_size must be >= 1 (got {hop_size})"
        )

    n = len(window_q14)
    n_frames = (n // hop_size) * 4 + 8
    total_len = n_frames * hop_size + n
    sums = [0] * total_len
    for k in range(n_frames):
        offset = k * hop_size
        for i, w in enumerate(window_q14):
            sums[offset + i] += int(w)
    interior = sums[n:-n] if total_len > 2 * n else sums
    if not interior:
        return (True, 0, sums)
    # Mean as float then round to nearest integer.
    mean = sum(interior) / len(interior)
    mean_int = int(round(mean))
    max_dev = max(abs(v - mean_int) for v in interior)
    return (max_dev <= tol_lsbs, max_dev, sums)


# ---------------------------------------------------------------------------
# I/O helpers
# ---------------------------------------------------------------------------
def _read_float_window(path: Path) -> List[float]:
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


def _read_hex_window(path: Path) -> List[int]:
    out: List[int] = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("//") or s.startswith("#"):
                continue
            try:
                v = int(s, 16) & 0xFFFF
                if v & 0x8000:
                    v -= 0x10000
                out.append(v)
            except ValueError:
                continue
    return out


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Check the COLA condition for a window / hop pair.",
    )
    p.add_argument("--window-file", type=Path, required=True,
                   help="Window file (.txt = float, .hex = Q2.14).")
    p.add_argument("--hop", type=int, default=FRAME_ADVANCE,
                   help="Hop size in samples (default: %(default)s)")
    p.add_argument("--tol", type=float, default=1e-6,
                   help="Tolerance (relative for float, LSBs for hex).")
    args = p.parse_args(argv)

    if args.window_file.suffix.lower() == ".hex":
        w = _read_hex_window(args.window_file)
        ok, dev, _ = check_cola_fixed_point(
            w, hop_size=args.hop, tol_lsbs=int(args.tol)
        )
        kind = "fixed-point (Q2.14 LSBs)"
    else:
        w = _read_float_window(args.window_file)
        ok, dev, _ = check_cola_condition(
            w, hop_size=args.hop, tol=args.tol
        )
        kind = "float (absolute)"

    print(f"COLA check ({kind}):")
    print(f"  N = {len(w)}, hop = {args.hop}, "
          f"# overlapping frames = {len(w) // args.hop + 1}")
    print(f"  max deviation = {dev}")
    print(f"  status        = {'PASS' if ok else 'FAIL'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
