"""
Project Auris — Window-function sanity checks.

Provides COLA, symmetry, DC-response, and energy-conservation checks
for arbitrary window functions.  Used to validate the generated
``window_rom`` contents against the streaming-OLA expectations of the
DSP pipeline (50% overlap, N_FFT/2 hop).
"""

from __future__ import annotations

import math
from typing import Dict, List, Tuple


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------
def check_cola(w: List[float],
               hop: int = 128,
               tol: float = 1e-6) -> Tuple[bool, float]:
    """Constant-Overlap-Add check.

    Simulates an overlap-add of the window with itself at the given
    hop and reports the maximum deviation from a constant value.

    Parameters
    ----------
    w : list of float
        Window samples.
    hop : int
        Hop size in samples.  Default ``128`` matches the project
        256-point FFT / 50% overlap configuration.
    tol : float
        Absolute tolerance on the deviation from constancy.

    Returns
    -------
    (ok, max_dev)
        ``ok`` is True if the deviation is within ``tol``;
        ``max_dev`` is the maximum deviation observed (always
        non-negative).
    """
    n = len(w)
    if hop <= 0:
        raise ValueError(f"check_cola: hop must be positive (got {hop})")
    if n < hop:
        raise ValueError(
            f"check_cola: window length ({n}) must be >= hop ({hop})"
        )

    # The OLA sum, computed for each output sample in the "steady-state"
    # region (i.e. after the first and last hops have contributed).
    # Use a long overlap-add (multiple frames) so the central overlap
    # region is well-populated and the steady-state constancy is
    # actually measured, rather than just 2 frames at the edge.
    n_frames = (n // hop) * 4 + 8
    ola = [0.0] * (n_frames * hop + n)
    for k in range(n_frames):
        offset = k * hop
        for i in range(n):
            if offset + i < len(ola):
                ola[offset + i] += w[i]

    # Extract the steady-state region (interior, away from edge effects).
    steady = ola[n:-n] if len(ola) > 2 * n else ola[n:]
    max_val = max(steady) if steady else 0.0
    min_val = min(steady) if steady else 0.0
    deviation = max_val - min_val
    passed = deviation < tol
    return (passed, deviation)


def check_symmetry(w: List[float],
                   tol: float = 1e-9) -> Tuple[bool, float]:
    """Verify ``w`` is symmetric (linear-phase) about its centre.

    Returns
    -------
    (ok, max_dev)
        ``ok`` is True if the maximum deviation is within ``tol``;
        ``max_dev`` is the largest ``|w[i] - w[N-1-i]|``.
    """
    n = len(w)
    if n == 0:
        raise ValueError("check_symmetry: empty window")

    dev = 0.0
    for i in range(n // 2):
        d = abs(w[i] - w[n - 1 - i])
        if d > dev:
            dev = d
    return (dev <= tol, float(dev))


def check_dc_response(w: List[float],
                      expected: float | None = None
                      ) -> Tuple[bool, float]:
    """Check the DC (sum) response of the window.

    The DC response of an N-point window is ``sum(w)/N``.  For a
    periodic Hann window with 50% overlap and COLA normalisation the
    expected value is 1.0; for an un-normalised Hann the expected
    value is 0.5.

    Parameters
    ----------
    w : list of float
        Window samples.
    expected : float, optional
        Expected DC value.  If ``None`` (default), the test is treated
        as informational and always returns ``ok=True`` (the actual
        value is reported in ``max_dev``).

    Returns
    -------
    (ok, dc)
        ``dc`` is the measured DC response.  ``ok`` is True if
        ``expected`` is ``None`` or if ``|dc - expected| <= 1e-6``.
    """
    n = len(w)
    if n == 0:
        raise ValueError("check_dc_response: empty window")

    dc = sum(w) / n
    if expected is None:
        return (True, float(dc))
    return (abs(dc - expected) <= 1e-6, float(dc))


def check_energy(w: List[float],
                 expected_enbw: float = 1.5,
                 tol: float = 0.01) -> Tuple[bool, float]:
    """Check the Equivalent Noise BandWidth (ENBW) of the window.

    The Hann window's analytic ENBW is exactly 1.5 bins; this check
    allows a small tolerance for floating-point round-off.

    Returns
    -------
    (ok, enbw)
        ``enbw`` is the measured ENBW in bins;
        ``ok`` is True if ``|enbw - expected_enbw| <= tol``.
    """
    n = len(w)
    if n == 0:
        raise ValueError("check_energy: empty window")
    s = sum(w)
    e = sum(x * x for x in w)
    if s <= 0 or e <= 0:
        raise ValueError("check_energy: zero-energy or non-positive-sum window")

    # ENBW (in bins) = N * sum(w^2) / (sum(w))^2
    enbw = (n * e) / (s * s)
    return (abs(enbw - expected_enbw) <= tol, float(enbw))


# ---------------------------------------------------------------------------
# Aggregate
# ---------------------------------------------------------------------------
def validate_all(w: List[float], hop: int = 128) -> Dict[str, object]:
    """Run every check and return a structured report.

    Returns
    -------
    dict
        ``{"cola": (ok, dev), "symmetry": (ok, dev), "dc": (ok, val),
            "energy": (ok, enbw), "all_ok": bool}``
    """
    cola = check_cola(w, hop=hop)
    sym = check_symmetry(w)
    dc = check_dc_response(w)
    energy = check_energy(w)

    all_ok = all(r[0] for r in (cola, sym, dc, energy))

    return {
        "cola": cola,
        "symmetry": sym,
        "dc": dc,
        "energy": energy,
        "all_ok": all_ok,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def _cli() -> int:                  # pragma: no cover
    import argparse
    import sys
    from pathlib import Path

    p = argparse.ArgumentParser(description="Window-function validator")
    p.add_argument("--window-hex", type=Path, default=None,
                   help="Path to a $readmemh hex file (16-bit values per line)")
    p.add_argument("--N", type=int, default=256,
                   help="Window length for the default Hann generator")
    p.add_argument("--variant", choices=("periodic", "symmetric"),
                   default="periodic")
    p.add_argument("--hop", type=int, default=128)
    args = p.parse_args()

    if args.window_hex is not None:
        vals: List[float] = []
        with open(args.window_hex, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("//"):
                    continue
                v = int(line, 16)
                if v & 0x8000:
                    v -= 0x10000
                vals.append(v / 16384.0)
        w = vals
    else:
        # Local import to avoid an unconditional dependency.
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from gen_hann_coeffs import generate_hann
        w = generate_hann(args.N, variant=args.variant)

    report = validate_all(w, hop=args.hop)
    print("Validation report:")
    for name, val in report.items():
        if name == "all_ok":
            print(f"  {name:10s}  = {val}")
            continue
        ok, metric = val
        print(f"  {name:10s}  ok={ok}  value={metric:.6e}")
    return 0 if report["all_ok"] else 1


if __name__ == "__main__":
    raise SystemExit(_cli())
