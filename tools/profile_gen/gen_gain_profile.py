"""
Project Auris — Audiogram to per-bin gain-table converter.

Takes an :class:`~common.audiogram.Audiogram` (or a raw 7-element list
of dB HL values) and emits a 128-bin gain table in dB and / or
16-bit Q2.14 fixed-point.  The output is suitable for direct loading
into the FPGA's gain-table BRAM via ``$readmemh`` and for streaming
to REG_GAIN_DATA over SPI.

M19: Each gain entry is now a single 16-bit Q2.14 word (signed, two's
complement).  The previous mantissa+shift pair representation has
been removed; the hardware gain table is 128 x 16 bits and is loaded
as plain 16-bit words via REG_GAIN_DATA.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import List

# Make ``python tools/profile_gen/gen_gain_profile.py`` work from any cwd.
_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.audiogram import Audiogram, log_freq_interpolate
from common.constants import (
    AUDIOGRAM_FREQS,
    FS,
    N_FFT,
    N_BINS,
    GAIN_DB_MIN,
    GAIN_DB_MAX,
)
from common.fixed_point import db_to_q2_14_signed
from common.formats import write_hex, write_txt_table, write_json


# ---------------------------------------------------------------------------
# Conversion
# ---------------------------------------------------------------------------
def audiogram_to_gain_table(audiogram: Audiogram,
                            formula: str = "nal_r",
                            n_bins: int = N_BINS,
                            apply_rolloff: bool = True) -> List[float]:
    """Convert an :class:`Audiogram` to a per-bin gain table in dB.

    This is a thin wrapper around :meth:`Audiogram.to_bin_gains` that
    guarantees the return type is a plain list and applies an explicit
    DC=0 dB clamp.  See :meth:`Audiogram.to_bin_gains` for details.
    """
    if not isinstance(audiogram, Audiogram):
        audiogram = Audiogram(list(audiogram))
    gains = audiogram.to_bin_gains(formula=formula,
                                   n_bins=n_bins,
                                   apply_rolloff=apply_rolloff)
    if gains:
        gains[0] = 0.0                         # force DC to 0 dB
    return list(gains)


def gain_table_to_fixed(gains_db: List[float]) -> List[int]:
    """Quantise a dB gain table to a list of 16-bit Q2.14 signed words.

    M19: replaces the old (mantissa, shift) pair return with a single
    list of 16-bit Q2.14 words, one per bin.  See
    :func:`common.fixed_point.db_to_q2_14_signed` for the encoding.
    """
    return [db_to_q2_14_signed(g) & 0xFFFF for g in gains_db]


# ---------------------------------------------------------------------------
# File writers
# ---------------------------------------------------------------------------
def _write_outputs(gains_db: List[float],
                   out_prefix: Path,
                   also_json: bool) -> List[Path]:
    """Write the gain table to .hex, .txt, and (optionally) .json files.

    M19: The .hex file contains one 16-bit Q2.14 word per bin
    (single-word, signed two's-complement).  The FPGA gain table is
    128 x 16 bits and is loaded as plain 16-bit words via the
    REG_GAIN_DATA SPI register; see ``fpga/rtl/ctrl/reg_file.sv`` for
    the consumer.
    """
    q14_words = gain_table_to_fixed(gains_db)

    written: List[Path] = []
    hex_path = Path(str(out_prefix) + ".hex")
    write_hex(q14_words, hex_path,
              header=(f"Gain table, N={len(gains_db)}, "
                      f"Q2.14 signed, 1 word per bin "
                      f"(16 bits, two's complement)"))
    written.append(hex_path)

    txt_path = Path(str(out_prefix) + ".txt")
    rows = []
    for k, g in enumerate(gains_db):
        rows.append({
            "bin": k,
            "freq_hz": k * FS / N_FFT,
            "gain_db": g,
            "q2_14": q14_words[k],
            "hex": f"{q14_words[k] & 0xFFFF:04X}",
        })
    write_txt_table(rows, txt_path,
                    columns=["bin", "freq_hz", "gain_db",
                             "q2_14", "hex"])
    written.append(txt_path)

    if also_json:
        json_path = Path(str(out_prefix) + ".json")
        write_json({
            "fs": FS,
            "n_fft": N_FFT,
            "n_bins": len(gains_db),
            "gains_db": gains_db,
            "q2_14": q14_words,
        }, json_path)
        written.append(json_path)

    return written


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Convert an audiogram to a per-bin gain table.",
    )
    p.add_argument("--audiogram", default="0,0,0,0,0,0,0",
                   help="7 dB HL values at 250,500,1k,2k,3k,4k,6k Hz")
    p.add_argument("--formula", default="nal_r",
                   choices=("nal_r", "nal_nl2", "dsl_v5"),
                   help="Prescriptive formula (default: %(default)s)")
    p.add_argument("--n-bins", type=int, default=N_BINS)
    p.add_argument("--apply-rolloff", action="store_true", default=True)
    p.add_argument("--no-rolloff", dest="apply_rolloff", action="store_false")
    p.add_argument("--out-prefix", type=Path, default=Path("gain_table"))
    p.add_argument("--json", action="store_true",
                   help="Also write a .json sidecar with raw values")
    args = p.parse_args(argv)

    th = [float(x) for x in args.audiogram.split(",")]
    if len(th) != len(AUDIOGRAM_FREQS):
        raise SystemExit(
            f"audiogram must have {len(AUDIOGRAM_FREQS)} values (got {len(th)})"
        )

    audio = Audiogram(th)
    print(f"Audiogram (dB HL): {th}")
    print(f"Formula: {args.formula}")
    print(f"Bins: {args.n_bins}, apply_rolloff: {args.apply_rolloff}")

    gains = audiogram_to_gain_table(audio, formula=args.formula,
                                    n_bins=args.n_bins,
                                    apply_rolloff=args.apply_rolloff)

    print(f"Gain range: [{min(gains):+.2f}, {max(gains):+.2f}] dB")
    print(f"Gain range clamped: [{GAIN_DB_MIN:+.2f}, {GAIN_DB_MAX:+.2f}] dB")

    written = _write_outputs(gains, args.out_prefix, also_json=args.json)
    print("Files written:")
    for path in written:
        print(f"  {path}  ({path.stat().st_size} bytes)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
