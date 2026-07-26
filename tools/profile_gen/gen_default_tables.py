"""
Project Auris — Default gain tables for the four operating modes.

Each operating mode is mapped to a 128-bin gain table in dB:

* ``general``  — flat 0 dB.
* ``hearing``  — NAL-R for a "typical" mild high-frequency loss.
* ``speech``   — +6 dB shelf in 300-3400 Hz, attenuated at the band
                 edges for noise control.
* ``bypass``   — flat 0 dB (identical to ``general``; included for
                 clarity in the mode-select mux).

M19: The .hex output is one 16-bit Q2.14 word per bin (signed,
two's-complement), not the previous mantissa+shift pair.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Dict, List

# Allow running this file directly from anywhere.
_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.audiogram import Audiogram
from common.constants import FS, N_FFT, N_BINS
from common.formats import write_hex, write_txt_table

try:
    from .gen_gain_profile import (
        audiogram_to_gain_table,
        gain_table_to_fixed,
    )
except ImportError:
    # Direct script execution — fall back to a path-based import.
    from gen_gain_profile import (
        audiogram_to_gain_table,
        gain_table_to_fixed,
    )


# ---------------------------------------------------------------------------
# Reference audiogram used for the "hearing" mode.
# ---------------------------------------------------------------------------
DEFAULT_HEARING_AUDIOGRAM_DBHL: List[float] = [0.0, 0.0, 10.0, 25.0, 35.0, 40.0, 45.0]


# ---------------------------------------------------------------------------
# Per-mode generators
# ---------------------------------------------------------------------------
def generate_general_mode(n_bins: int = N_BINS) -> List[float]:
    """Flat 0 dB — the identity gain table."""
    return [0.0] * n_bins


def generate_hearing_mode(audiogram: Audiogram = None,
                          formula: str = "nal_r",
                          n_bins: int = N_BINS) -> List[float]:
    """NAL-R gain table for the default hearing-loss audiogram."""
    if audiogram is None:
        audiogram = Audiogram(list(DEFAULT_HEARING_AUDIOGRAM_DBHL))
    return audiogram_to_gain_table(audiogram, formula=formula, n_bins=n_bins)


def generate_speech_mode(n_bins: int = N_BINS,
                         fs: float = FS,
                         n_fft: int = N_FFT,
                         shelf_db: float = 6.0,
                         low_cutoff_hz: float = 100.0,
                         low_atten_db: float = -12.0,
                         high_cutoff_hz: float = 6000.0,
                         high_atten_db: float = -6.0,
                         shelf_low_hz: float = 300.0,
                         shelf_high_hz: float = 3400.0) -> List[float]:
    """Speech-shaped gain: shelf in the speech band, attenuated elsewhere.

    The shape is:
        * ``+shelf_db`` (default +6 dB) between ``shelf_low_hz`` and
          ``shelf_high_hz``.
        * Linear ramp in log-frequency from ``+shelf_db`` to
          ``low_atten_db`` between ``shelf_low_hz`` and ``low_cutoff_hz``.
        * Linear ramp in log-frequency from ``+shelf_db`` to
          ``high_atten_db`` between ``shelf_high_hz`` and ``high_cutoff_hz``.
        * ``low_atten_db`` below ``low_cutoff_hz`` and ``high_atten_db``
          above ``high_cutoff_hz`` (the implementation extrapolates the
          linear ramps a small amount beyond the cutoffs to avoid
          discontinuities at the band edges).
    """
    gains: List[float] = []
    for k in range(n_bins):
        f = k * fs / n_fft
        if f <= 0.0:
            gains.append(0.0)
            continue

        if shelf_low_hz <= f <= shelf_high_hz:
            g = shelf_db
        elif f < shelf_low_hz:
            # Log-linear ramp from (shelf_low, shelf_db) toward
            # (low_cutoff, low_atten_db).  If f is below low_cutoff
            # we hold at low_atten_db.
            if f <= low_cutoff_hz:
                g = low_atten_db
            else:
                log_t = (math.log10(f) - math.log10(low_cutoff_hz)) / (
                    math.log10(shelf_low_hz) - math.log10(low_cutoff_hz)
                )
                log_t = max(0.0, min(1.0, log_t))
                g = low_atten_db + (shelf_db - low_atten_db) * log_t
        else:
            # f > shelf_high
            if f >= high_cutoff_hz:
                g = high_atten_db
            else:
                log_t = (math.log10(f) - math.log10(shelf_high_hz)) / (
                    math.log10(high_cutoff_hz) - math.log10(shelf_high_hz)
                )
                log_t = max(0.0, min(1.0, log_t))
                g = shelf_db + (high_atten_db - shelf_db) * log_t
        gains.append(g)
    return gains


def generate_bypass_mode(n_bins: int = N_BINS) -> List[float]:
    """Flat 0 dB — the bypass mode is functionally identical to general."""
    return [0.0] * n_bins


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
def generate_all_modes(out_dir: Path,
                       n_bins: int = N_BINS) -> Dict[str, List[float]]:
    """Generate all four mode tables and write their .hex / .txt files.

    Returns a dict mapping mode name to the corresponding gain table.
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    tables: Dict[str, List[float]] = {
        "general": generate_general_mode(n_bins),
        "hearing": generate_hearing_mode(n_bins=n_bins),
        "speech":  generate_speech_mode(n_bins=n_bins),
        "bypass":  generate_bypass_mode(n_bins=n_bins),
    }

    for name, gains in tables.items():
        prefix = out_dir / f"gain_table_{name}"

        # M19: pack as one 16-bit Q2.14 word per bin (matches the RTL
        # gain table, which is 128 x 16 bits, and the SPI REG_GAIN_DATA
        # payload which is 16 bits wide).
        q14_words = gain_table_to_fixed(gains)
        write_hex(q14_words, Path(str(prefix) + ".hex"),
                  header=f"Mode={name!r}, N={n_bins}, Q2.14 signed")

        rows = []
        for k, g in enumerate(gains):
            rows.append({
                "bin": k,
                "freq_hz": k * FS / N_FFT,
                "gain_db": g,
                "q2_14": q14_words[k],
            })
        write_txt_table(rows, Path(str(prefix) + ".txt"),
                        columns=["bin", "freq_hz", "gain_db", "q2_14"])
        print(f"  wrote {prefix}.hex  ({n_bins} entries, mode={name!r})")

    return tables


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Generate the four default mode gain tables.",
    )
    p.add_argument("--out-dir", type=Path,
                   default=Path("fpga/generated"),
                   help="Destination directory (default: %(default)s)")
    p.add_argument("--n-bins", type=int, default=N_BINS)
    args = p.parse_args(argv)

    print(f"Generating default mode tables into {args.out_dir}...")
    tables = generate_all_modes(args.out_dir, n_bins=args.n_bins)
    print(f"Generated {len(tables)} mode tables: "
          f"{', '.join(sorted(tables.keys()))}")
    for name, g in tables.items():
        print(f"  {name:8s}  range [{min(g):+5.2f}, {max(g):+5.2f}] dB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
