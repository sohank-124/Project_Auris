"""
Project Auris — Audiogram regression test vectors.

This module defines a set of canonical audiograms (normal, mild / moderate
/ severe high-frequency loss, cookie-bite, reverse-slope, noise-notch)
and computes the expected insertion-gain and per-bin gain tables for
each.  The expected values are stored as JSON so the simulation test
bench can compare the actual FPGA output against the reference.

The "fitting formula" used here is the same simple half-gain
``gain = 0.5 * HL`` model adopted by :mod:`tools.profile_gen.gen_gain_profile`
(i.e. a NAL-R-style 2:1 compression).  More elaborate formulas (NAL-NL2,
DSL-v5) are routed to the same code path because the rest of the
toolchain computes the gains through :class:`tools.common.Audiogram`.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Dict, List

_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import (
    AUDIOGRAM_FREQS,
    N_BINS,
    FS,
    N_FFT,
    GAIN_DB_MIN,
    GAIN_DB_MAX,
)
from common.audiogram import Audiogram
from common.fixed_point import db_to_q0_14, q2_14_to_float
from common.formats import write_json, write_txt_table


# ---------------------------------------------------------------------------
# Reference audiograms
# ---------------------------------------------------------------------------
# Each entry is a 7-element list of dB-HL thresholds measured at the
# standard audiometric frequencies (250, 500, 1k, 2k, 3k, 4k, 6k Hz).
REFERENCE_AUDIOGRAMS: Dict[str, List[float]] = {
    "normal":        [0,  0,  0,  0,  0,  0,  0],
    "mild_flat":     [20, 20, 20, 20, 20, 20, 20],
    "mild_hf":       [0,  0, 10, 25, 35, 40, 45],
    "moderate_hf":   [10, 15, 25, 40, 55, 65, 70],
    "severe_hf":     [30, 35, 45, 60, 75, 85, 90],
    "cookie_bite":   [30, 20, 10,  5, 10, 20, 30],
    "reverse_slope": [50, 40, 30, 20, 10,  5,  0],
    "noise_notch":   [5,   5, 10, 30, 40, 25, 10],
}


# ---------------------------------------------------------------------------
# Gain computation
# ---------------------------------------------------------------------------
def _halfgain_insertion(thresholds: List[float]) -> List[float]:
    """Compute the NAL-R-style half-gain insertion gain at each band.

    ``gain_db[i] = 0.5 * HL[i]``, clipped to ``[GAIN_DB_MIN, GAIN_DB_MAX]``.
    """
    out: List[float] = []
    for hl in thresholds:
        g = 0.5 * hl
        if g < GAIN_DB_MIN:
            g = GAIN_DB_MIN
        if g > GAIN_DB_MAX:
            g = GAIN_DB_MAX
        out.append(g)
    return out


def generate_audiogram_test(name: str,
                            audiogram: List[float],
                            formula: str = "nal_r") -> Dict:
    """Generate a single audiogram test vector.

    Parameters
    ----------
    name : str
        Friendly name of the test case (e.g. ``"mild_hf"``).
    audiogram : list of float
        7-element list of dB-HL thresholds.
    formula : str
        Fitting formula name.  Currently the only path that does
        anything different from the default half-gain rule is
        ``"none"``, which returns zero insertion gain at every band.

    Returns
    -------
    dict
        ``{"name", "audiogram", "frequencies", "formula",
           "expected_gains_db", "expected_q14"}``.  ``expected_q14`` is
        the (mantissa, shift) pair returned by :func:`db_to_q0_14` for
        each band, suitable for direct comparison with the hardware's
        gain-table loader.
    """
    if len(audiogram) != 7:
        raise ValueError(
            f"generate_audiogram_test: audiogram must have 7 entries "
            f"(got {len(audiogram)})"
        )
    if formula == "none":
        gains_db = [0.0] * 7
    elif formula in ("nal_r", "nal_nl2", "dsl_v5"):
        # All three go through the same simple model for now; the
        # formula name is preserved for traceability.
        gains_db = _halfgain_insertion(audiogram)
    else:
        raise ValueError(
            f"generate_audiogram_test: unknown formula {formula!r}"
        )

    q14_pairs = [db_to_q0_14(g) for g in gains_db]
    bin_gains = Audiogram(audiogram, label=name).to_bin_gains(formula)

    return {
        "name": name,
        "audiogram": list(audiogram),
        "frequencies": list(AUDIOGRAM_FREQS),
        "formula": formula,
        "expected_gains_db": [round(g, 4) for g in gains_db],
        "expected_q14": [{"mantissa": m, "shift": s} for m, s in q14_pairs],
        "expected_bin_gains_db": [round(g, 4) for g in bin_gains],
        "n_bins": N_BINS,
    }


def generate_full_test_suite(out_dir: Path) -> List[Dict]:
    """Generate the full audiogram regression test suite.

    Writes:

    * ``audiogram_tests.json`` — the complete test-vector manifest.
    * ``audiogram_tests.txt``  — a human-readable table.

    Parameters
    ----------
    out_dir : Path
        Destination directory; created if it does not exist.

    Returns
    -------
    list of dict
        The per-case test vectors.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    suite: List[Dict] = []
    for name, th in REFERENCE_AUDIOGRAMS.items():
        suite.append(generate_audiogram_test(name, th, formula="nal_r"))

    write_json({
        "fs": FS,
        "n_fft": N_FFT,
        "n_bins": N_BINS,
        "formula": "nal_r",
        "cases": suite,
    }, out_dir / "audiogram_tests.json")

    # Human-readable table.
    rows = []
    for c in suite:
        for i, f in enumerate(AUDIOGRAM_FREQS):
            rows.append({
                "case": c["name"],
                "freq_hz": f,
                "hl_db": c["audiogram"][i],
                "gain_db": c["expected_gains_db"][i],
                "q14_mantissa": c["expected_q14"][i]["mantissa"],
                "q14_shift": c["expected_q14"][i]["shift"],
            })
    write_txt_table(rows, out_dir / "audiogram_tests.txt",
                    columns=["case", "freq_hz", "hl_db", "gain_db",
                             "q14_mantissa", "q14_shift"])
    return suite


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Audiogram regression test-vector generator.",
    )
    p.add_argument("--out-dir", type=Path,
                   default=Path("audiogram_test_vectors"),
                   help="Destination directory (default: %(default)s).")
    p.add_argument("--formula", choices=("nal_r", "nal_nl2", "dsl_v5", "none"),
                   default="nal_r",
                   help="Fitting formula (default: %(default)s).")
    args = p.parse_args(argv)

    suite = generate_full_test_suite(args.out_dir)
    print(f"Audiogram test suite written to {args.out_dir}")
    print(f"  audiogram_tests.json  ({len(suite)} cases)")
    print(f"  audiogram_tests.txt   (per-band table)")
    for c in suite:
        gains = c["expected_gains_db"]
        print(f"  {c['name']:14s} gains={['{:+5.1f}'.format(g) for g in gains]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
