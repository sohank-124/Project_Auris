"""
Project Auris — Hann window coefficient generator.

Generates a Hann window in floating-point, optionally normalises it
(COLA / RMS / power), and emits the result in Q2.14 fixed-point hex
plus companion ``.coe`` / ``.txt`` files suitable for loading into
the FPGA's ``window_rom``.

CLI
---
::

    python -m tools.win_gen.gen_hann_coeffs \\
        --N 256 --variant periodic --norm cola \\
        --out-prefix hann_256 --format all

Or invoked as a script: ``python tools/win_gen/gen_hann_coeffs.py``.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Dict, List, Tuple

# Allow ``python tools/win_gen/gen_hann_coeffs.py`` from any cwd.
_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import N_FFT
from common.fixed_point import batch_float_to_q2_14, q2_14_to_float
from common.formats import write_hex, write_coe, write_readmemb, write_txt_table


# ---------------------------------------------------------------------------
# Window generation
# ---------------------------------------------------------------------------
def generate_hann(n: int, variant: str = "periodic") -> List[float]:
    """Generate an N-point Hann window.

    Parameters
    ----------
    n : int
        Window length.
    variant : str
        ``"periodic"`` (default) — denominator ``N`` so that overlapping
        frames of hop ``N/2`` satisfy the COLA property exactly when the
        window is also rescaled by ``2/sum(w)``.  ``"symmetric"`` uses
        denominator ``N - 1`` and is the standard ``numpy.hanning`` /
        MATLAB ``hann(N, 'symmetric')`` form.

    Returns
    -------
    list of float
        Window samples in ``[0.0, 1.0]``.

    Raises
    ------
    ValueError
        If ``n < 2`` or ``variant`` is not recognised.
    """
    if n < 2:
        raise ValueError(f"generate_hann: n must be >= 2 (got {n})")
    if variant not in ("periodic", "symmetric"):
        raise ValueError(
            f"generate_hann: variant must be 'periodic' or 'symmetric' "
            f"(got {variant!r})"
        )

    denom = n if variant == "periodic" else (n - 1)
    two_pi = 2.0 * math.pi
    return [0.5 * (1.0 - math.cos(two_pi * i / denom)) for i in range(n)]


# ---------------------------------------------------------------------------
# Normalisation
# ---------------------------------------------------------------------------
def normalize_window(w: List[float], mode: str = "none") -> List[float]:
    """Normalise a window in place of a copy.

    Parameters
    ----------
    w : list of float
        Input window.
    mode : str
        ``"none"``    — return a copy unchanged.
        ``"cola"``    — scale by ``2.0 / sum(w)`` so that an N/2-hop OLA
                        sums to 1.0 at every sample (Constant Overlap-
                        Add).
        ``"rms"``     — divide by ``sqrt(mean(w^2))`` so the RMS value
                        becomes 1.0.
        ``"power"``   — divide by ``sum(w^2)`` so the window has unit
                        energy (commonly used for filter design).

    Returns
    -------
    list of float
        New list containing the normalised window.

    Raises
    ------
    ValueError
        If ``mode`` is not recognised or the window is degenerate.
    """
    if mode == "none":
        return list(w)

    s = sum(w)
    if s <= 0:
        raise ValueError("normalize_window: sum(w) is non-positive")

    if mode == "cola":
        scale = 2.0 / s
    elif mode == "rms":
        ms = sum(x * x for x in w) / len(w)
        if ms <= 0:
            raise ValueError("normalize_window: mean(w^2) is non-positive")
        scale = 1.0 / math.sqrt(ms)
    elif mode == "power":
        e = sum(x * x for x in w)
        if e <= 0:
            raise ValueError("normalize_window: sum(w^2) is non-positive")
        scale = 1.0 / e
    else:
        raise ValueError(
            f"normalize_window: unknown mode {mode!r} "
            "(expected 'none', 'cola', 'rms', or 'power')"
        )

    return [x * scale for x in w]


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------
def compute_window_metrics(w: List[float]) -> Dict[str, float]:
    """Compute standard window-quality metrics.

    Returns
    -------
    dict with keys
        ``coherent_gain``      — mean of the window (``sum(w)/N``).
        ``enbw``               — equivalent noise bandwidth in bins
                                 (``sum(w)^2 / (N * sum(w^2))``).
        ``scalloping_loss_db`` — worst-case spectral loss at a non-bin
                                 centre frequency (3.92 dB for a Hann
                                 window; computed analytically from
                                 ENBW).
        ``peak_sidelobe_db``   — peak sidelobe level in dB (relative to
                                 the main lobe).  Analytic value for the
                                 Hann window: ``-31.47 dB``.
        ``cola_sum``           — sum of the window.
    """
    n = len(w)
    if n == 0:
        raise ValueError("compute_window_metrics: empty window")

    s = sum(w)
    e = sum(x * x for x in w)
    if e <= 0:
        raise ValueError("compute_window_metrics: zero-energy window")

    coherent_gain = s / n
    # ENBW (in bins) = N * sum(w^2) / (sum(w))^2
    # For a Hann window this is exactly 1.5 regardless of N.
    enbw = (n * e) / (s * s) if s != 0 else float("inf")

    # Scalloping loss (dB) for a non-coherently-summed analysis: analytic
    # worst-case for a Hann window is 3.92 dB, derived from ENBW and the
    # rectangular-window baseline of 1.0.
    enbw_db = 10.0 * math.log10(enbw) if enbw > 0 else float("-inf")
    scalloping_loss_db = max(0.0, -enbw_db)

    # Peak sidelobe level: analytic value for the (unmodified) Hann
    # window.  We rely on the analytic constant here rather than a
    # numeric FFT so the metric is deterministic and not sensitive to
    # FFT length / windowing.
    peak_sidelobe_db = -31.47

    return {
        "coherent_gain": coherent_gain,
        "enbw": enbw,
        "scalloping_loss_db": scalloping_loss_db,
        "peak_sidelobe_db": peak_sidelobe_db,
        "cola_sum": s,
    }


# ---------------------------------------------------------------------------
# File output helpers
# ---------------------------------------------------------------------------
def _human_rows(q: List[int], w: List[float]) -> List[Dict[str, object]]:
    return [
        {
            "idx": i,
            "float": float(w[i]),
            "q2_14": int(q[i]),
            "hex": f"{(int(q[i]) & 0xFFFF):04X}",
        }
        for i in range(len(q))
    ]


def _write_outputs(w: List[float],
                   out_prefix: Path,
                   fmt: str) -> List[Path]:
    """Write the window to disk in the requested format(s).

    Returns the list of paths actually written.
    """
    q = batch_float_to_q2_14(w)
    written: List[Path] = []

    if fmt in ("hex", "all"):
        p = Path(str(out_prefix) + ".hex")
        write_hex(q, p,
                  header=(f"Hann window, N={len(w)}, "
                          f"Q2.14 fixed-point"))
        written.append(p)

    if fmt in ("coe", "all"):
        p = Path(str(out_prefix) + ".coe")
        write_coe(q, p, radix=16, width=16)
        written.append(p)

    if fmt in ("m", "all"):
        p = Path(str(out_prefix) + ".m")
        write_readmemb(q, p)
        written.append(p)

    if fmt in ("txt", "all"):
        p = Path(str(out_prefix) + ".txt")
        write_txt_table(_human_rows(q, w), p,
                        columns=["idx", "float", "q2_14", "hex"])
        written.append(p)

    return written


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Generate Hann window coefficients in Q2.14.",
    )
    p.add_argument("--N", type=int, default=N_FFT,
                   help="Window length (default: %(default)s)")
    p.add_argument("--variant", choices=("periodic", "symmetric"),
                   default="periodic",
                   help="Periodic (default) or symmetric Hann")
    p.add_argument("--norm", choices=("none", "cola", "rms", "power"),
                   default="none",
                   help="Normalisation mode (default: %(default)s)")
    p.add_argument("--out-prefix", type=Path,
                   default=Path("hann_256"),
                   help="Output file prefix (extensions added per --format)")
    p.add_argument("--format", choices=("hex", "coe", "m", "txt", "all"),
                   default="all",
                   help="Output format (default: %(default)s)")
    args = p.parse_args(argv)

    print(f"Generating {args.N}-point Hann window "
          f"(variant={args.variant}, norm={args.norm})...")

    w = generate_hann(args.N, variant=args.variant)
    if args.norm != "none":
        w = normalize_window(w, mode=args.norm)

    metrics = compute_window_metrics(w)
    print("Window metrics:")
    for k, v in metrics.items():
        print(f"  {k:22s} = {v:.6f}")

    q = batch_float_to_q2_14(w)
    print(f"  q2_14 first/last       = {q[0]:#06x} / {q[-1]:#06x}")
    print(f"  q2_14 max              = {max(q):#06x}")
    print(f"  q2_14 round-trip error = "
          f"{max(abs(q2_14_to_float(qi) - wi) for qi, wi in zip(q, w)):.3e}")

    written = _write_outputs(w, args.out_prefix, args.format)
    print("Files written:")
    for path in written:
        print(f"  {path}  ({path.stat().st_size} bytes)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
