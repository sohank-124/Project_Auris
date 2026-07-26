"""
Project Auris — Filter coefficient generators.

Generates IIR Butterworth or windowed-sinc FIR bandpass coefficients
suitable for loading into the FPGA's per-channel equaliser biquad or
convolution engine.  Coeffs are returned as Python ``list`` of floats
in **floating-point** form; quantisation to Q2.14 is handled by
:func:`quantize_coeffs` in this module.

The IIR path requires SciPy; the FIR path is implemented from first
principles (no external dependency) so that the generator is usable
in a minimal environment.
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

from common.constants import FS, Q_FRAC, Q_SCALE, Q_MIN, Q_MAX
from common.fixed_point import float_to_q2_14, q2_14_to_float, saturate
from common.formats import write_hex, write_coe, write_txt_table


# ---------------------------------------------------------------------------
# Window functions for FIR design
# ---------------------------------------------------------------------------
def _window(n: int, kind: str) -> List[float]:
    """Return an ``n``-point window of the requested kind.

    Supported: ``"hamming"``, ``"hann"``, ``"blackman"``, ``"rect"``.
    """
    if n <= 0:
        return []
    if kind == "rect":
        return [1.0] * n
    if kind == "hamming":
        return [0.54 - 0.46 * math.cos(2.0 * math.pi * i / (n - 1))
                for i in range(n)]
    if kind == "hann":
        return [0.5 - 0.5 * math.cos(2.0 * math.pi * i / (n - 1))
               for i in range(n)]
    if kind == "blackman":
        return [(0.42
                 - 0.5 * math.cos(2.0 * math.pi * i / (n - 1))
                 + 0.08 * math.cos(4.0 * math.pi * i / (n - 1)))
                for i in range(n)]
    raise ValueError(f"_window: unknown kind {kind!r}")


# ---------------------------------------------------------------------------
# IIR Butterworth bandpass
# ---------------------------------------------------------------------------
def butter_bandpass(f_low: float,
                    f_high: float,
                    order: int = 4,
                    fs: float = FS) -> Tuple[List[float], List[float]]:
    """Design a Butterworth bandpass IIR filter (biquad cascade flattened).

    Uses :func:`scipy.signal.butter` with the bilinear transform and
    unpacks the second-order-sections into a flat (b, a) pair by
    convolving the section numerators / denominators.

    Parameters
    ----------
    f_low, f_high : float
        Passband edges in Hz.  Must satisfy ``0 < f_low < f_high < fs/2``.
    order : int
        Filter order (number of poles).  Final filter has ``order`` poles
        per lowpass prototype stage, so the bandpass is ``2*order``
        effective order.
    fs : float
        Sample rate in Hz.

    Returns
    -------
    (b, a) : Tuple[list[float], list[float]]
        Numerator and denominator coefficients, longest first.
        ``len(b) == len(a) == 2*order + 1`` (for an odd-order bandpass
        padded to even).

    Raises
    ------
    ImportError
        If SciPy is not installed.
    ValueError
        If any parameter is out of range.
    """
    if f_low <= 0.0 or f_high <= f_low:
        raise ValueError(
            f"butter_bandpass: need 0 < f_low < f_high "
            f"(got {f_low}, {f_high})"
        )
    if f_high >= fs / 2.0:
        raise ValueError(
            f"butter_bandpass: f_high must be < fs/2 "
            f"(got f_high={f_high}, fs/2={fs / 2.0})"
        )
    if order < 1:
        raise ValueError(f"butter_bandpass: order must be >= 1 (got {order})")

    try:
        from scipy.signal import butter, sos2tf  # type: ignore
    except Exception as exc:                                # pragma: no cover
        raise ImportError(
            "butter_bandpass requires scipy.signal. "
            "Install with: pip install scipy"
        ) from exc

    sos = butter(order, [f_low, f_high], btype="bandpass",
                 fs=fs, output="sos")
    b, a = sos2tf(sos)
    return [float(x) for x in b], [float(x) for x in a]


# ---------------------------------------------------------------------------
# FIR windowed-sinc bandpass
# ---------------------------------------------------------------------------
def fir_bandpass(f_low: float,
                 f_high: float,
                 n_taps: int = 64,
                 window: str = "hamming",
                 fs: float = FS) -> List[float]:
    """Design a linear-phase FIR bandpass via the windowed-sinc method.

    The ideal bandpass impulse response is

    .. math::

        h_d[n] = \\frac{\\sin(\\pi f_h (n-M)/f_s) - \\sin(\\pi f_l (n-M)/f_s)}
                       {\\pi (n-M)},

    with the centre tap value

    .. math::

        h_d[M] = (f_h - f_l) / f_s,

    where ``M = (n_taps - 1) / 2``.  The window is applied and the
    result is normalised so the passband gain is approximately 0 dB
    (peak response = 1.0 at the centre of the passband).

    Parameters
    ----------
    f_low, f_high : float
        Passband edges (Hz).  Must satisfy ``0 < f_low < f_high < fs/2``.
    n_taps : int
        Number of taps.  Must be odd for a linear-phase Type-I filter
        centred at zero; even values are accepted but warn that the
        resulting filter has a half-sample delay.
    window : str
        ``"hamming"`` (default), ``"hann"``, ``"blackman"``, or
        ``"rect"``.
    fs : float
        Sample rate in Hz.

    Returns
    -------
    list of float
        FIR coefficients of length ``n_taps``.
    """
    if n_taps < 1:
        raise ValueError(f"fir_bandpass: n_taps must be >= 1 (got {n_taps})")
    if f_low <= 0.0 or f_high <= f_low:
        raise ValueError(
            f"fir_bandpass: need 0 < f_low < f_high "
            f"(got {f_low}, {f_high})"
        )
    if f_high >= fs / 2.0:
        raise ValueError(
            f"fir_bandpass: f_high must be < fs/2 "
            f"(got f_high={f_high}, fs/2={fs / 2.0})"
        )

    M = (n_taps - 1) / 2.0
    f_low_n = f_low / fs
    f_high_n = f_high / fs

    h: List[float] = []
    for n in range(n_taps):
        x = n - M
        if x == 0:
            h_n = f_high_n - f_low_n
        else:
            h_n = (math.sin(math.pi * f_high_n * x)
                   - math.sin(math.pi * f_low_n * x)) / (math.pi * x)
        h.append(h_n)

    win = _window(n_taps, window)
    h = [hi * w for hi, w in zip(h, win)]

    # Normalise to unit peak gain (DC of the passband).
    peak = max(abs(v) for v in h) if h else 0.0
    if peak > 0.0:
        h = [v / peak for v in h]
    return h


# ---------------------------------------------------------------------------
# Quantisation
# ---------------------------------------------------------------------------
def quantize_coeffs(coeffs: List[float], width: int = 16) -> List[int]:
    """Quantise a list of floats to Q2.14 integers (16-bit signed).

    Parameters
    ----------
    coeffs : list of float
        Floating-point coefficients.  Values outside ``[-2.0, +1.99994]``
        are saturated.
    width : int
        Storage width in bits.  Only ``16`` is supported; other values
        raise :class:`ValueError`.  The parameter exists for API
        symmetry with the rest of the toolchain.
    """
    if width != 16:
        raise ValueError(
            f"quantize_coeffs: only width=16 (Q2.14) is supported "
            f"(got {width})"
        )
    return [float_to_q2_14(c) for c in coeffs]


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
def _write_outputs(coeffs: List[float],
                   q: List[int],
                   out_prefix: Path,
                   label: str) -> List[Path]:
    written: List[Path] = []
    p_hex = Path(str(out_prefix) + ".hex")
    write_hex(q, p_hex, header=f"{label} (Q2.14)")
    written.append(p_hex)

    p_coe = Path(str(out_prefix) + ".coe")
    write_coe(q, p_coe, radix=16, width=16)
    written.append(p_coe)

    rows = [
        {"idx": i, "float": c, "q2_14": qi,
         "hex": f"{(int(qi) & 0xFFFF):04X}"}
        for i, (c, qi) in enumerate(zip(coeffs, q))
    ]
    p_txt = Path(str(out_prefix) + ".txt")
    write_txt_table(rows, p_txt, columns=["idx", "float", "q2_14", "hex"])
    written.append(p_txt)

    return written


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Filter coefficient generator (IIR Butterworth or FIR).",
    )
    p.add_argument("--type", choices=("iir", "fir"), default="fir",
                   help="Filter kind (default: %(default)s)")
    p.add_argument("--f-low", type=float, required=True,
                   help="Lower passband edge in Hz.")
    p.add_argument("--f-high", type=float, required=True,
                   help="Upper passband edge in Hz.")
    p.add_argument("--order", type=int, default=4,
                   help="IIR Butterworth order (default: %(default)s)")
    p.add_argument("--taps", type=int, default=64,
                   help="FIR number of taps (default: %(default)s)")
    p.add_argument("--window", choices=("hamming", "hann", "blackman", "rect"),
                   default="hamming",
                   help="FIR window (default: %(default)s)")
    p.add_argument("--fs", type=float, default=FS,
                   help="Sample rate in Hz (default: %(default)s)")
    p.add_argument("--out", type=Path, default=Path("filter_coeffs"),
                   help="Output prefix (extensions .hex/.coe/.txt added).")
    args = p.parse_args(argv)

    print(f"Designing {args.type.upper()} bandpass: "
          f"{args.f_low:g}–{args.f_high:g} Hz @ {args.fs:g} Hz")

    if args.type == "iir":
        b, a = butter_bandpass(args.f_low, args.f_high,
                               order=args.order, fs=args.fs)
        # Concatenate b and a into a single flat table for the bitstream.
        coeffs = list(b) + list(a)
        q = quantize_coeffs(coeffs, width=16)
        print(f"  b ({len(b)} taps): "
              f"{[round(c, 6) for c in b]}")
        print(f"  a ({len(a)} taps): "
              f"{[round(c, 6) for c in a]}")
        label = (f"IIR Butterworth BPF {args.f_low:g}-{args.f_high:g} Hz "
                 f"order={args.order}")
        written = _write_outputs(coeffs, q, args.out, label)
    else:
        coeffs = fir_bandpass(args.f_low, args.f_high,
                              n_taps=args.taps, window=args.window, fs=args.fs)
        q = quantize_coeffs(coeffs, width=16)
        max_err = max(abs(q2_14_to_float(qi) - c)
                      for qi, c in zip(q, coeffs)) if coeffs else 0.0
        print(f"  {len(coeffs)} taps, window={args.window}, "
              f"max quant error = {max_err:.3e}")
        label = (f"FIR windowed-sinc BPF {args.f_low:g}-{args.f_high:g} Hz "
                 f"taps={args.taps} window={args.window}")
        written = _write_outputs(coeffs, q, args.out, label)

    print("Files written:")
    for path in written:
        print(f"  {path}  ({path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
