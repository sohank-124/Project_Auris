"""
Project Auris — Round-trip latency measurement via cross-correlation.

For an end-to-end latency test the FPGA / simulator is fed a known
stimulus and the corresponding output is recorded.  The two signals
are cross-correlated to find the integer-sample delay; parabolic
interpolation around the correlation peak gives sub-sample
accuracy.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import List, Tuple

_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import FS


# ---------------------------------------------------------------------------
# Cross-correlation
# ---------------------------------------------------------------------------
def cross_correlate(x: List[float], y: List[float]) -> List[float]:
    """Compute the (non-normalised) cross-correlation ``R[k]``.

    Uses the FFT for speed: ``R = IFFT(FFT(x_padded) * conj(FFT(y_padded)))``.
    The output has length ``len(x) + len(y) - 1``.  Convention:
    ``R[k]`` corresponds to a lag of ``k - (len(y) - 1)`` samples,
    i.e. positive lags mean ``y`` lags ``x`` by that many samples.

    The raw FFT result has the peak at index ``(len(y) - 1) - delay``
    in the ``len(y) + len(x) - 1``-element "n - k" convention; we
    re-arrange the indices so the caller's intuition (``R[delay +
    (len(y) - 1)]`` is the correlation when ``y`` is delayed by
    ``delay``) is preserved.
    """
    if not x or not y:
        return []
    n_out = len(x) + len(y) - 1
    n_fft = 1
    while n_fft < n_out:
        n_fft <<= 1

    try:
        import numpy as np
    except ImportError as exc:                                # pragma: no cover
        raise ImportError(
            "cross_correlate requires numpy. Install with: pip install numpy"
        ) from exc

    xp = np.zeros(n_fft, dtype=np.float64)
    yp = np.zeros(n_fft, dtype=np.float64)
    xp[:len(x)] = x
    yp[:len(y)] = y

    R_fft = np.fft.ifft(np.fft.fft(xp) * np.conj(np.fft.fft(yp))).real
    # Rearrange so that R[k] is the cross-correlation at lag k - (M - 1),
    # i.e. positive k corresponds to y delayed by (k - (M-1)) samples.
    m = len(y)
    idx = (m - 1 - np.arange(n_out)) % n_fft
    return [float(v) for v in R_fft[idx]]


# ---------------------------------------------------------------------------
# Peak picking
# ---------------------------------------------------------------------------
def measure_delay(input_signal: List[float],
                  output_signal: List[float],
                  fs: float = FS) -> Tuple[int, float]:
    """Measure the delay (samples, then sub-samples) between two signals.

    The cross-correlation is computed; the integer peak position is
    found, then parabolic interpolation is applied using the three
    samples surrounding the peak:

    .. math::

        \\delta = \\frac{1}{2}\\,\\frac{\\alpha - \\gamma}
                                       {\\alpha - 2\\beta + \\gamma}

    where ``alpha = R[peak-1]``, ``beta = R[peak]``, ``gamma =
    R[peak+1]``.  ``delta`` is in samples; the final delay is
    ``peak - (len(y) - 1) + delta``.

    Returns
    -------
    (int_delay, sub_sample_delay) : Tuple[int, float]
        ``int_delay`` is the integer-sample delay (number of output
        samples that lag the input).  ``sub_sample_delay`` is the
        same value with parabolic interpolation applied.
    """
    if not input_signal or not output_signal:
        raise ValueError("measure_delay: empty input or output signal")

    R = cross_correlate(input_signal, output_signal)
    n = len(R)
    if n == 0:
        raise ValueError("measure_delay: empty correlation result")

    # Find the integer peak.
    peak_idx = 0
    peak_val = R[0]
    for i in range(1, n):
        if R[i] > peak_val:
            peak_val = R[i]
            peak_idx = i

    # Sub-sample parabolic interpolation.
    if 0 < peak_idx < n - 1:
        alpha = R[peak_idx - 1]
        beta = R[peak_idx]
        gamma = R[peak_idx + 1]
        denom = alpha - 2.0 * beta + gamma
        if denom != 0.0:
            delta = 0.5 * (alpha - gamma) / denom
        else:
            delta = 0.0
    else:
        delta = 0.0

    sub_peak = peak_idx + delta
    n_y = len(output_signal)
    # The "lag" convention: index k in R corresponds to lag k - (n_y - 1).
    int_delay = peak_idx - (n_y - 1)
    sub_delay = sub_peak - (n_y - 1)
    return int_delay, sub_delay


# ---------------------------------------------------------------------------
# I/O helpers
# ---------------------------------------------------------------------------
def _read_signal_file(path: Path) -> List[float]:
    """Read a text signal file (one float per line, ``#`` comments OK)."""
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
# Top-level driver
# ---------------------------------------------------------------------------
def measure_roundtrip_latency(input_path: Path,
                              output_path: Path,
                              fs: float = FS) -> dict:
    """Read two signal files, measure their relative delay, and report.

    Parameters
    ----------
    input_path, output_path : Path
        Paths to the recorded input and output signal files.
    fs : float
        Sample rate used to convert sample counts to milliseconds.

    Returns
    -------
    dict
        ``{"input_path", "output_path", "fs", "int_delay_samples",
           "sub_sample_delay_samples", "delay_ms", "peak_correlation"}``.
    """
    sig_in = _read_signal_file(input_path)
    sig_out = _read_signal_file(output_path)
    if not sig_in or not sig_out:
        raise ValueError(
            f"measure_roundtrip_latency: empty signal "
            f"({len(sig_in)} in, {len(sig_out)} out)"
        )
    int_delay, sub_delay = measure_delay(sig_in, sig_out, fs=fs)
    R = cross_correlate(sig_in, sig_out)
    peak = max(R) if R else 0.0
    return {
        "input_path": str(input_path),
        "output_path": str(output_path),
        "fs": fs,
        "int_delay_samples": int(int_delay),
        "sub_sample_delay_samples": float(sub_delay),
        "delay_ms": 1000.0 * sub_delay / fs,
        "peak_correlation": float(peak),
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Measure round-trip latency from input / output signal files.",
    )
    p.add_argument("--input", type=Path, required=True,
                   help="Path to recorded input signal.")
    p.add_argument("--output", type=Path, required=True,
                   help="Path to recorded output signal.")
    p.add_argument("--fs", type=float, default=FS)
    p.add_argument("--out", type=Path, default=None,
                   help="Optional JSON report output.")
    args = p.parse_args(argv)

    result = measure_roundtrip_latency(args.input, args.output, fs=args.fs)
    print(f"Round-trip latency: {result['delay_ms']:.4f} ms  "
          f"({result['sub_sample_delay_samples']:.3f} samples @ "
          f"{result['fs']:.0f} Hz)")
    print(f"  integer delay  = {result['int_delay_samples']} samples")
    print(f"  peak |R|       = {result['peak_correlation']:.3e}")
    if args.out is not None:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2)
            f.write("\n")
        print(f"  wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
