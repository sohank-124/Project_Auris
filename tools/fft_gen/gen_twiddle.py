"""
Project Auris — Twiddle-factor table generator.

Produces the (cos, sin) pairs needed by the synthesised FFT in Q2.14
fixed-point.  Only ``k = 0 .. N/2 - 1`` is required because the
remaining twiddles are derivable by quadrant / sign symmetry.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import List, Tuple

# Make direct invocation work.
_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import N_FFT
from common.fixed_point import float_to_q2_14
from common.formats import write_hex, write_coe, write_txt_table


# ---------------------------------------------------------------------------
# Table generation
# ---------------------------------------------------------------------------
def generate_twiddle_table(n: int = N_FFT,
                           width: int = 16) -> Tuple[List[int], List[int]]:
    """Generate Q2.14 twiddle table for ``k = 0 .. N/2 - 1``.

    For each ``k`` the twiddle is ``W_N^k = exp(-j * 2 * pi * k / N)``,
    quantised to ``width``-bit fixed-point.  ``cos`` and ``sin`` are
    returned as separate lists (each of length ``N/2``) of Q2.14
    16-bit signed integers.
    """
    if n < 2 or (n & (n - 1)):
        raise ValueError(f"generate_twiddle_table: n must be a power of two >= 2 (got {n})")
    if width != 16:
        raise ValueError(f"generate_twiddle_table: only width=16 is supported (got {width})")

    cos_q: List[int] = []
    sin_q: List[int] = []
    for k in range(n // 2):
        theta = -2.0 * math.pi * k / n
        cos_q.append(float_to_q2_14(math.cos(theta)))
        sin_q.append(float_to_q2_14(math.sin(theta)))
    return (cos_q, sin_q)


def twiddle_to_complex(cos_q: List[int], sin_q: List[int]) -> List[complex]:
    """Convert Q2.14 (cos, sin) pairs back to a list of complex twiddles.

    Useful for verification: the reconstructed complex numbers should
    match ``exp(-j*2*pi*k/N)`` up to one LSB of quantisation.
    """
    out: List[complex] = []
    for c, s in zip(cos_q, sin_q):
        # Sign-extend the 16-bit two's-complement value first, then
        # convert to float.  This is the inverse of
        # :func:`common.fixed_point.float_to_q2_14`.
        c_raw = int(c) & 0xFFFF
        if c_raw & 0x8000:
            c_raw -= 0x10000
        s_raw = int(s) & 0xFFFF
        if s_raw & 0x8000:
            s_raw -= 0x10000
        out.append(complex(c_raw / 16384.0, s_raw / 16384.0))
    return out


# ---------------------------------------------------------------------------
# File writers
# ---------------------------------------------------------------------------
def generate_twiddle_file(n: int,
                          out_path: Path,
                          fmt: str = "hex") -> None:
    """Generate the twiddle table and write it to ``out_path``.

    Three formats are supported:

    * ``"hex"``  (default) — one 16-bit hex word per line, alternating
      cos / sin starting with cos.  Use ``$readmemh`` and a paired
      counter in the RTL to demultiplex.
    * ``"coe"``  — Xilinx COE format (hex).
    * ``"txt"``  — human-readable ``k, cos, sin, cos_hex, sin_hex``.
    """
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    cos_q, sin_q = generate_twiddle_table(n)

    if fmt == "hex":
        # Interleave cos / sin so the RTL can stream them sequentially.
        interleaved: List[int] = []
        for c, s in zip(cos_q, sin_q):
            interleaved.append(c)
            interleaved.append(s)
        write_hex(interleaved, out_path,
                  header=(f"Twiddle table for {n}-point FFT, "
                          f"interleaved (cos, sin) Q2.14, N/2={n // 2} pairs"))
    elif fmt == "coe":
        interleaved: List[int] = []
        for c, s in zip(cos_q, sin_q):
            interleaved.append(c)
            interleaved.append(s)
        write_coe(interleaved, out_path, radix=16, width=16)
    elif fmt == "txt":
        rows = []
        for k, (c, s) in enumerate(zip(cos_q, sin_q)):
            rows.append({
                "k": k,
                "theta_rad": -2.0 * math.pi * k / n,
                "cos_q": c,
                "sin_q": s,
                "cos_hex": f"{c & 0xFFFF:04X}",
                "sin_hex": f"{s & 0xFFFF:04X}",
            })
        write_txt_table(rows, out_path,
                        columns=["k", "theta_rad", "cos_q", "sin_q",
                                 "cos_hex", "sin_hex"])
    else:
        raise ValueError(f"generate_twiddle_file: unknown format {fmt!r}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Generate FFT twiddle-factor tables.",
    )
    p.add_argument("--N", type=int, default=N_FFT,
                   help="FFT length (default: %(default)s)")
    p.add_argument("--format", choices=("hex", "coe", "txt"),
                   default="hex")
    p.add_argument("--out", type=Path, default=Path("twiddle.hex"))
    args = p.parse_args(argv)

    print(f"Generating {args.N}-point twiddle table ({args.format})...")
    generate_twiddle_file(args.N, args.out, fmt=args.format)
    size = args.out.stat().st_size
    print(f"  wrote {args.out}  ({size} bytes)")

    # Verification: max error between quantised and analytic twiddles.
    cos_q, sin_q = generate_twiddle_table(args.N)
    cmpx = twiddle_to_complex(cos_q, sin_q)
    max_err = 0.0
    for k, z in enumerate(cmpx):
        exact = complex(
            math.cos(-2.0 * math.pi * k / args.N),
            math.sin(-2.0 * math.pi * k / args.N),
        )
        err = abs(z - exact)
        if err > max_err:
            max_err = err
    print(f"  max quantisation error: {max_err:.3e}  "
          f"(1 LSB = {1.0 / 16384.0:.3e})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
