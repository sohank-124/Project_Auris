"""
Project Auris — Gain-table smoothing.

Three smoothing strategies used to post-process a 128-bin per-channel
gain table before it is loaded into the FPGA:

* :func:`smooth_fractional_octave` — for each bin, average the gain
  across all bins that fall within the per-bin fractional-octave
  bandwidth.  This emulates what a real ear / measurement microphone
  "sees" and is the standard psychoacoustic smoothing.
* :func:`smooth_moving_average` — simple N-bin boxcar.
* :func:`smooth_gaussian` — Gaussian-kernel smoothing with a specified
  sigma (in bins).
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import List

_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import FS, N_FFT, N_BINS


# ---------------------------------------------------------------------------
# Smoothing kernels
# ---------------------------------------------------------------------------
def smooth_fractional_octave(gains_db: List[float],
                             fraction: int = 3,
                             fs: float = FS,
                             n_fft: int = N_FFT) -> List[float]:
    """Smooth a per-bin gain curve using a fractional-octave kernel.

    For each bin ``k`` with center frequency ``f_k = k * fs / n_fft`` the
    bandwidth is

    .. math::

        B(f_k) = f_k \\left(2^{1/(2 \\cdot \\text{fraction})}
                            - 2^{-1/(2 \\cdot \\text{fraction})}\\right).

    The smoothed gain is the arithmetic mean of all bin gains whose
    center frequency lies inside ``[f_k - B/2, f_k + B/2]``.  At DC
    (``f_k == 0``) the kernel collapses to the single point, and at the
    Nyquist bin (``f_k == fs/2``) we clamp the upper edge to ``fs/2``.

    Parameters
    ----------
    gains_db : list of float
        Input gain in dB.  Must contain ``n_fft // 2`` entries.
    fraction : int
        Octave fraction (1 = octave, 3 = third-octave, 6 = sixth-octave,
        ...).  Must be >= 1.
    fs : float
        Sample rate in Hz.
    n_fft : int
        FFT length.

    Returns
    -------
    list of float
        Smoothed gains in dB (same length as ``gains_db``).

    Raises
    ------
    ValueError
        If ``fraction < 1`` or ``gains_db`` does not have ``n_fft // 2``
        entries.
    """
    if fraction < 1:
        raise ValueError(
            f"smooth_fractional_octave: fraction must be >= 1 (got {fraction})"
        )
    n_bins_expected = n_fft // 2
    if len(gains_db) != n_bins_expected:
        raise ValueError(
            f"smooth_fractional_octave: gains_db must have {n_bins_expected} "
            f"entries (got {len(gains_db)})"
        )

    # Pre-compute center frequencies and bandwidths.
    bin_freqs = [k * fs / n_fft for k in range(n_bins_expected)]
    upper = 2.0 ** (1.0 / (2.0 * fraction))
    lower = 2.0 ** (-1.0 / (2.0 * fraction))
    bandwidths = [f * (upper - lower) for f in bin_freqs]

    out: List[float] = []
    for k, f_k in enumerate(bin_freqs):
        b_k = bandwidths[k]
        if b_k <= 0:
            # DC bin: average only the DC bin itself.
            out.append(float(gains_db[k]))
            continue

        f_lo = max(0.0, f_k - b_k / 2.0)
        f_hi = min(fs / 2.0, f_k + b_k / 2.0)
        if f_lo == f_hi:
            out.append(float(gains_db[k]))
            continue

        acc = 0.0
        cnt = 0
        for j, f_j in enumerate(bin_freqs):
            if f_lo <= f_j <= f_hi:
                acc += gains_db[j]
                cnt += 1
        out.append(acc / cnt if cnt else float(gains_db[k]))
    return out


def smooth_moving_average(gains_db: List[float],
                          window_size: int = 5) -> List[float]:
    """Boxcar (uniform) moving average of a gain curve.

    The window is centred on the current sample; for even ``window_size``
    the centre is at ``(window_size - 1) / 2`` (still integer truncation
    downward) and the kernel is asymmetric by one sample on the right.

    Edge samples are mirrored (i.e. the input is implicitly extended
    with reflected copies so the kernel stays full near the ends).
    """
    n = len(gains_db)
    if n == 0:
        return []
    if window_size < 1:
        raise ValueError(
            f"smooth_moving_average: window_size must be >= 1 (got {window_size})"
        )
    if window_size == 1:
        return list(gains_db)

    half = window_size // 2
    out: List[float] = []
    for i in range(n):
        acc = 0.0
        for j in range(window_size):
            idx = i + j - half
            if idx < 0:
                idx = -idx
            elif idx >= n:
                idx = 2 * (n - 1) - idx
            acc += gains_db[idx]
        out.append(acc / window_size)
    return out


def smooth_gaussian(gains_db: List[float],
                    sigma_bins: float = 2.0) -> List[float]:
    """Gaussian-kernel smoothing of a gain curve.

    The kernel is ``g[j] = exp(-0.5 * (j/sigma_bins)^2)`` truncated to
    ``+/- ceil(3 * sigma_bins)`` and renormalised to sum to 1.  Edges
    use the same mirror extension as :func:`smooth_moving_average`.
    """
    n = len(gains_db)
    if n == 0:
        return []
    if sigma_bins <= 0:
        raise ValueError(
            f"smooth_gaussian: sigma_bins must be > 0 (got {sigma_bins})"
        )

    half = max(1, int(math.ceil(3.0 * sigma_bins)))
    kernel = [math.exp(-0.5 * (j / sigma_bins) ** 2)
              for j in range(-half, half + 1)]
    ksum = sum(kernel)
    if ksum > 0:
        kernel = [k / ksum for k in kernel]

    out: List[float] = []
    for i in range(n):
        acc = 0.0
        for j, kj in enumerate(kernel):
            idx = i + j - half
            if idx < 0:
                idx = -idx
            elif idx >= n:
                idx = 2 * (n - 1) - idx
            acc += gains_db[idx] * kj
        out.append(acc)
    return out


# ---------------------------------------------------------------------------
# I/O helpers
# ---------------------------------------------------------------------------
def _read_gain_file(path: Path) -> List[float]:
    """Read a gain file: one float per line; ``#`` and blank lines are skipped."""
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


def _write_gain_file(path: Path, gains: List[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# Project Auris — smoothed gain table\n")
        f.write("# idx, gain_db\n")
        for i, g in enumerate(gains):
            f.write(f"{i},{g:.6f}\n")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Gain-table smoothing.")
    p.add_argument("--method", choices=("fractional", "moving", "gaussian"),
                   default="fractional")
    p.add_argument("--fraction", type=int, default=3,
                   help="Fraction for fractional-octave smoothing (default: 3)")
    p.add_argument("--window", type=int, default=5,
                   help="Window size for moving-average smoothing (default: 5)")
    p.add_argument("--sigma", type=float, default=2.0,
                   help="Sigma (in bins) for Gaussian smoothing (default: 2.0)")
    p.add_argument("--input-file", type=Path, required=True,
                   help="Path to input gain file (one float per line).")
    p.add_argument("--out", type=Path, default=None,
                   help="Output file path (default: stdout table).")
    args = p.parse_args(argv)

    gains = _read_gain_file(args.input_file)
    if not gains:
        raise SystemExit(f"error: no data read from {args.input_file}")
    print(f"Read {len(gains)} gain values from {args.input_file}")

    if args.method == "fractional":
        out = smooth_fractional_octave(gains, fraction=args.fraction)
    elif args.method == "moving":
        out = smooth_moving_average(gains, window_size=args.window)
    else:                                            # gaussian
        out = smooth_gaussian(gains, sigma_bins=args.sigma)

    # Quick numeric summary.
    n = min(16, len(out))
    print(f"First {n} smoothed values: "
          f"{[round(g, 3) for g in out[:n]]}")

    if args.out is not None:
        _write_gain_file(args.out, out)
        print(f"Wrote {args.out} ({args.out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
