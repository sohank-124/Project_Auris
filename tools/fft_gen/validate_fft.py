"""
Project Auris — FFT validation helpers.

These checks are written against the **reference DFT** in
:mod:`tools.fft_gen.gen_fft`; pass the synthesised hardware FFT
through a cosim testbench and feed its outputs back to these checks
to validate the implementation.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path
from typing import Callable, Dict, List, Tuple

# Make ``python tools/fft_gen/validate_fft.py`` work from any cwd.
_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import FS, N_FFT, TOL_PARSEVAL_DB
try:
    from .gen_fft import reference_dft
except ImportError:
    # Direct script execution — fall back to a path-based import.
    from gen_fft import reference_dft


# ---------------------------------------------------------------------------
# Parseval
# ---------------------------------------------------------------------------
def check_parseval(x: List[float],
                   X: List[complex],
                   tol: float = 1e-6) -> Tuple[bool, float]:
    """Check Parseval's theorem: sum(|x|^2) = (1/N) * sum(|X|^2).

    Returns
    -------
    (ok, ratio_db)
        ``ratio_db`` is the deviation in dB between the time- and
        frequency-domain energies.
    """
    n = len(x)
    if n != len(X):
        raise ValueError(
            f"check_parseval: length mismatch (x={n}, X={len(X)})"
        )
    if n == 0:
        return (True, 0.0)

    e_time = sum(float(xi) ** 2 for xi in x)
    e_freq = sum(abs(Xk) ** 2 for Xk in X) / n
    if e_time <= 0:
        return (True, 0.0)               # trivial (all-zero input)

    ratio = e_freq / e_time
    ratio_db = 10.0 * math.log10(ratio) if ratio > 0 else float("-inf")
    return (abs(ratio_db) <= tol, float(ratio_db))


# ---------------------------------------------------------------------------
# Linearity
# ---------------------------------------------------------------------------
def check_linearity(fft_func: Callable[[List[complex]], List[complex]],
                    n: int = 256) -> Tuple[bool, float]:
    """Check FFT linearity: FFT{a*x + b*y} == a*FFT{x} + b*FFT{y}.

    ``fft_func`` must take a list of complex samples and return a list
    of complex bins, both of length ``n``.  We use a unit impulse and
    a unit step, with random complex coefficients ``a`` and ``b``.
    """
    if n < 2 or (n & (n - 1)):
        raise ValueError(f"check_linearity: n must be a power of two >= 2 (got {n})")

    x = [1.0] + [0.0] * (n - 1)            # impulse
    y = [1.0] * n                           # DC
    a = complex(0.7, 0.3)
    b = complex(-0.4, 0.9)

    lhs = fft_func([a * xi + b * yi for xi, yi in zip(x, y)])
    rhs = [a * Xk + b * Yk
           for Xk, Yk in zip(fft_func(x), fft_func(y))]

    max_dev = 0.0
    for L, R in zip(lhs, rhs):
        d = abs(L - R)
        if d > max_dev:
            max_dev = d
    tol = 1e-6 * max(1.0, abs(a) + abs(b))
    return (max_dev <= tol, float(max_dev))


# ---------------------------------------------------------------------------
# Known signals
# ---------------------------------------------------------------------------
def check_known_signal(fft_func: Callable[[List[complex]], List[complex]],
                       signal_type: str = "sinusoid",
                       n: int = 256) -> Tuple[bool, float]:
    """Validate the FFT on a known closed-form signal.

    Supported signals:

    * ``"impulse"``   — ``x[0] = 1, x[i!=0] = 0``.  Expected spectrum:
      ``X[k] = 1`` for all ``k``.
    * ``"dc"``        — ``x[i] = 1`` for all ``i``.  Expected:
      ``X[0] = N, X[k != 0] = 0``.
    * ``"sinusoid"``  — ``x[i] = cos(2*pi*i/N)``.  Expected spectrum:
      ``X[1] = X[-1] = N/2`` (real form).
    """
    if n < 2 or (n & (n - 1)):
        raise ValueError(
            f"check_known_signal: n must be a power of two >= 2 (got {n})"
        )

    st = signal_type.lower()
    if st == "impulse":
        x = [1.0] + [0.0] * (n - 1)
        X = fft_func(x)
        expected = [1.0 + 0j] * n
        tol = 1e-6
    elif st == "dc":
        x = [1.0 + 0j] * n
        X = fft_func(x)
        expected = [float(n) + 0j] + [0.0 + 0j] * (n - 1)
        tol = 1e-6
    elif st == "sinusoid":
        # Use the real-form convention: x[i] = cos(2*pi*i*1/N).
        # Expected: X[1] = X[-1] = N/2 (real, in the complex DFT both
        # bins carry half the energy).
        x = [complex(math.cos(2.0 * math.pi * i / n), 0.0) for i in range(n)]
        X = fft_func(x)
        expected = [0j] * n
        expected[1] = complex(n / 2.0, 0.0)
        expected[-1] = complex(n / 2.0, 0.0)
        tol = 1e-6 * n
    else:
        raise ValueError(f"check_known_signal: unknown signal_type {signal_type!r}")

    max_dev = 0.0
    for Xk, Ek in zip(X, expected):
        d = abs(Xk - Ek)
        if d > max_dev:
            max_dev = d
    return (max_dev <= tol, float(max_dev))


# ---------------------------------------------------------------------------
# Bin frequency mapping
# ---------------------------------------------------------------------------
def check_bin_frequency_mapping(fs: float = FS,
                                n_fft: int = N_FFT) -> List[float]:
    """Return the list of bin-center frequencies for the given FFT size."""
    return [k * fs / n_fft for k in range(n_fft // 2)]


# ---------------------------------------------------------------------------
# Aggregate
# ---------------------------------------------------------------------------
def validate_all(fft_func: Callable[[List[complex]], List[complex]],
                 n: int = 256,
                 fs: float = FS) -> Dict[str, object]:
    """Run all checks against the supplied FFT function.

    ``fft_func`` should have signature
    ``[complex, ...] -> [complex, ...]`` with both lists of length ``n``.
    """
    impulse = [1.0] + [0.0] * (n - 1)
    X = fft_func(impulse)

    parseval = check_parseval([xi.real for xi in impulse], X)
    linearity = check_linearity(fft_func, n=n)
    impulse_check = check_known_signal(fft_func, "impulse", n=n)
    dc_check = check_known_signal(fft_func, "dc", n=n)
    sinusoid_check = check_known_signal(fft_func, "sinusoid", n=n)
    bin_freqs = check_bin_frequency_mapping(fs=fs, n_fft=n)

    all_ok = all(r[0] for r in (parseval, linearity, impulse_check,
                                dc_check, sinusoid_check))

    return {
        "parseval": parseval,
        "linearity": linearity,
        "impulse": impulse_check,
        "dc": dc_check,
        "sinusoid": sinusoid_check,
        "bin_freqs": bin_freqs,
        "all_ok": all_ok,
    }


# ---------------------------------------------------------------------------
# CLI smoke test
# ---------------------------------------------------------------------------
def _cli() -> int:                  # pragma: no cover
    import argparse
    p = argparse.ArgumentParser(description="FFT validator (against reference DFT)")
    p.add_argument("--N", type=int, default=256)
    args = p.parse_args()

    print(f"Validating reference DFT (N={args.N})...")
    report = validate_all(reference_dft, n=args.N)
    for name, val in report.items():
        if name == "bin_freqs":
            print(f"  bin_freqs (first 8) = "
                  f"{[round(f, 1) for f in val[:8]]}  ...")
            continue
        if name == "all_ok":
            print(f"  all_ok              = {val}")
            continue
        ok, v = val
        print(f"  {name:18s}  ok={ok}  metric={v:.3e}")
    return 0 if report["all_ok"] else 1


if __name__ == "__main__":
    raise SystemExit(_cli())
