"""
Project Auris — Latency test-signal generators.

Three kinds of stimuli are produced for round-trip latency
characterisation of the DSP pipeline:

* :func:`gen_latency_impulse` — a single impulse at ``marker_pos``
  followed by silence.  Used to measure the bulk pipeline delay
  with a peak-pick algorithm.
* :func:`gen_latency_chirp` — a wideband linear chirp.  Cross-
  correlating the input with the output gives the group delay.
* :func:`gen_latency_marker_signal` — four pulses at 1 kHz intervals.
  Used to measure per-stage latency contributions in the
  simulation testbench.

All signals are returned as ``list[float]`` and can be written out
as float ``.txt`` or Q2.14 ``.hex`` via the CLI driver.
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

from common.constants import FS
from common.fixed_point import batch_float_to_q2_14
from common.formats import write_hex


# ---------------------------------------------------------------------------
# Latency stimuli
# ---------------------------------------------------------------------------
def gen_latency_impulse(n_samples: int = 4096,
                        marker_pos: int = 256) -> Tuple[List[float], int]:
    """Return ``(signal, marker_pos)`` — a single impulse + zeros.

    The marker position is the index of the impulse peak; the
    testbench searches for the corresponding peak in the output
    to determine round-trip delay.
    """
    if n_samples < 1:
        raise ValueError(f"gen_latency_impulse: n_samples must be >= 1 (got {n_samples})")
    if marker_pos < 0 or marker_pos >= n_samples:
        raise ValueError(
            f"gen_latency_impulse: marker_pos must be in [0, n_samples) "
            f"(got {marker_pos}, n_samples={n_samples})"
        )
    sig = [0.0] * n_samples
    sig[marker_pos] = 1.0
    return sig, marker_pos


def gen_latency_chirp(n_samples: int = 4096,
                      f_start: float = 100.0,
                      f_stop: float = 10000.0) -> List[float]:
    """Generate a wideband linear chirp for group-delay measurement.

    The instantaneous phase at sample ``n`` is

    .. math::

        \\phi(n) = 2\\pi \\left[ f_0\\, t
                              + \\frac{(f_1 - f_0)\\, t\\, n}
                                     {2 (N - 1)} \\right]

    where ``t = n / f_s`` and ``N = n_samples``.
    """
    if n_samples < 2:
        raise ValueError(
            f"gen_latency_chirp: n_samples must be >= 2 (got {n_samples})"
        )
    if f_start <= 0 or f_stop <= 0:
        raise ValueError(
            f"gen_latency_chirp: f_start, f_stop must be > 0 "
            f"(got {f_start}, {f_stop})"
        )
    two_pi = 2.0 * math.pi
    out: List[float] = []
    N = n_samples - 1
    for n in range(n_samples):
        t = n / FS
        phase = two_pi * (f_start * t + 0.5 * (f_stop - f_start) * t * n / N)
        out.append(math.sin(phase))
    return out


def gen_latency_marker_signal(n_samples: int = 4096
                              ) -> Tuple[List[float], List[int]]:
    """Return ``(signal, marker_positions)`` — a multi-pulse test signal.

    Four narrow pulses are placed at 1024-sample intervals starting at
    sample 256.  The default positions are ``[256, 1280, 2304, 3328]``;
    the testbench can independently measure the delay of each marker
    to localise per-stage contributions.
    """
    if n_samples < 1:
        raise ValueError(
            f"gen_latency_marker_signal: n_samples must be >= 1 "
            f"(got {n_samples})"
        )
    # Default positions: 256, 256+1024, 256+2*1024, 256+3*1024.
    positions = [256, 1280, 2304, 3328]
    # Clip any positions that would land outside the buffer.
    positions = [p for p in positions if 0 <= p < n_samples]
    sig = [0.0] * n_samples
    for p in positions:
        sig[p] = 1.0
    return sig, positions


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
def _write_float(path: Path, sig: List[float], header: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        if header:
            for line in header.splitlines() or [""]:
                f.write(f"# {line}\n" if line else "#\n")
        for v in sig:
            f.write(f"{v:.9g}\n")


def _write_q14(path: Path, sig: List[float], header: str = "") -> None:
    q = batch_float_to_q2_14(sig)
    write_hex(q, path, header=header)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Latency test-signal generator.",
    )
    p.add_argument("--type", choices=("impulse", "chirp", "markers"),
                   required=True)
    p.add_argument("--n-samples", type=int, default=4096)
    p.add_argument("--marker-pos", type=int, default=256,
                   help="Impulse position (impulse type only).")
    p.add_argument("--f-start", type=float, default=100.0)
    p.add_argument("--f-stop", type=float, default=10000.0)
    p.add_argument("--out", type=Path, default=Path("latency_signal"),
                   help="Output prefix (.txt + .hex are written).")
    args = p.parse_args(argv)

    if args.type == "impulse":
        sig, mp = gen_latency_impulse(args.n_samples, args.marker_pos)
        label = f"impulse N={args.n_samples} marker={mp}"
    elif args.type == "chirp":
        sig = gen_latency_chirp(args.n_samples, args.f_start, args.f_stop)
        label = (f"chirp {args.f_start:g}->{args.f_stop:g} Hz "
                 f"N={args.n_samples}")
    else:                                                # markers
        sig, positions = gen_latency_marker_signal(args.n_samples)
        label = (f"multi-marker N={args.n_samples} "
                 f"positions={positions}")

    txt_path = Path(str(args.out) + ".txt")
    hex_path = Path(str(args.out) + ".hex")
    _write_float(txt_path, sig, header=label)
    _write_q14(hex_path, sig, header=f"{label} (Q2.14)")
    print(f"Generated {args.type} ({label})")
    print(f"  {txt_path}  ({txt_path.stat().st_size} bytes)")
    print(f"  {hex_path}  ({hex_path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
