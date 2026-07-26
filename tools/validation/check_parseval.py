"""
Project Auris — Parseval's theorem checker.

Parseval's theorem for the DFT states

.. math::

    \\sum_{n=0}^{N-1} |x[n]|^2 = \\frac{1}{N} \\sum_{k=0}^{N-1} |X[k]|^2

where ``x`` is a length-``N`` time-domain signal and ``X`` is its
length-``N`` DFT.  This module checks the theorem in two regimes:

* :func:`check_parseval_time_freq` — float input / complex DFT.
* :func:`check_parseval_fixed_point` — Q2.14 input / Q2.14 DFT bins.
  Because the fixed-point DFT has per-bin quantisation noise we
  expect the energy to differ by a few LSBs; the tolerance is in
  LSB units.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import List, Tuple

_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import N_FFT, TOL_PARSEVAL_DB


# ---------------------------------------------------------------------------
# Float version
# ---------------------------------------------------------------------------
def check_parseval_time_freq(x_time: List[float],
                             X_freq: List[complex],
                             n_fft: int = N_FFT,
                             tol: float = 1e-6) -> Tuple[bool, float, float]:
    """Verify Parseval's theorem for a real signal and its DFT.

    Parameters
    ----------
    x_time : list of float
        Time-domain signal.
    X_freq : list of complex
        DFT of ``x_time``, length ``n_fft``.
    n_fft : int
        DFT length.
    tol : float
        Absolute tolerance on the energy ratio ``E_time / E_freq``.

    Returns
    -------
    (ok, e_time, e_freq) : Tuple[bool, float, float]
        ``ok`` is True if the energies match to within ``tol``.
    """
    if not x_time:
        return (True, 0.0, 0.0)
    if len(X_freq) != n_fft:
        raise ValueError(
            f"check_parseval_time_freq: X_freq must have length {n_fft} "
            f"(got {len(X_freq)})"
        )

    e_time = sum(float(x) * float(x) for x in x_time)
    e_freq = sum(abs(X) ** 2 for X in X_freq) / n_fft
    diff = abs(e_time - e_freq)
    # Use a relative tolerance for large energies.
    denom = max(abs(e_time), abs(e_freq), 1e-12)
    ok = (diff / denom) <= tol
    return (ok, float(e_time), float(e_freq))


# ---------------------------------------------------------------------------
# Fixed-point version
# ---------------------------------------------------------------------------
def check_parseval_fixed_point(x_q14: List[int],
                               X_q14: List[int],
                               n_fft: int = N_FFT,
                               tol_lsbs: int = 4) -> Tuple[bool, int, int]:
    """Verify Parseval's theorem for a Q2.14 time / frequency pair.

    The time-domain energy is computed as the sum of squared
    Q2.14 samples (no re-scaling), and the frequency-domain energy
    is the sum of squared Q2.14 bins divided by ``n_fft``.  Both
    are reported in Q2.14 LSB units; the difference is compared
    against ``tol_lsbs``.

    The result is *not* expected to be exact: each FFT butterfly
    introduces a few LSBs of quantisation noise, and the final
    output bins are usually scaled by a power of two.  The default
    tolerance of 4 LSBs is empirically sufficient for a Q2.14
    256-point FFT.
    """
    if not x_q14:
        return (True, 0, 0)
    if len(X_q14) != n_fft:
        raise ValueError(
            f"check_parseval_fixed_point: X_q14 must have length {n_fft} "
            f"(got {len(X_q14)})"
        )

    e_time = 0
    for v in x_q14:
        e_time += int(v) * int(v)

    e_freq = 0
    for v in X_q14:
        e_freq += int(v) * int(v)
    e_freq = e_freq // n_fft

    diff = abs(e_time - e_freq)
    return (diff <= tol_lsbs, int(e_time), int(e_freq))


# ---------------------------------------------------------------------------
# I/O helpers
# ---------------------------------------------------------------------------
def _read_float_signal(path: Path) -> List[float]:
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


def _read_hex_signal(path: Path) -> List[int]:
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
        description="Parseval's theorem checker (float and Q2.14).",
    )
    p.add_argument("--input-file", type=Path, required=True,
                   help="Time-domain signal file (.txt or .hex).")
    p.add_argument("--fft-file", type=Path, required=True,
                   help="Frequency-domain DFT file (.txt or .hex).")
    p.add_argument("--tol", type=float, default=TOL_PARSEVAL_DB,
                   help="Tolerance (relative for float, LSBs for hex).")
    args = p.parse_args(argv)

    suffix_in = args.input_file.suffix.lower()
    suffix_fft = args.fft_file.suffix.lower()

    if suffix_in == ".hex" and suffix_fft == ".hex":
        x = _read_hex_signal(args.input_file)
        X = _read_hex_signal(args.fft_file)
        ok, e_t, e_f = check_parseval_fixed_point(
            x, X, n_fft=len(X), tol_lsbs=int(args.tol)
        )
        kind = "fixed-point (Q2.14 LSBs)"
    else:
        x = _read_float_signal(args.input_file)
        X_raw = _read_float_signal(args.fft_file)
        X = [complex(re, 0.0) for re in X_raw]
        ok, e_t, e_f = check_parseval_time_freq(
            x, X, n_fft=len(X), tol=args.tol
        )
        kind = "float (relative)"

    print(f"Parseval check ({kind}):")
    print(f"  E_time  = {e_t:.6f}")
    print(f"  E_freq  = {e_f:.6f}")
    print(f"  diff    = {abs(e_t - e_f):.6e}")
    print(f"  status  = {'PASS' if ok else 'FAIL'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
