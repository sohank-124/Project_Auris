"""
Project Auris — Noise-gate table generator.

Each WDRC channel has an associated noise gate that mutes the channel
whenever the estimated input level drops below an "open" threshold and
only re-mutes after the level has also fallen below a "close" threshold
(hysteresis to prevent gate flutter on near-threshold signals).

This module computes:

* Per-channel open / close thresholds in dB (split out into a JSON
  table for verification).
* Q2.14 envelope coefficients for the attack and release of the gate
  itself (typically faster attack / slower release than the WDRC
  envelope).
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Dict, List, Tuple

# Allow direct invocation.
_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import (
    FS,
    WDRC_CHANNELS,
    N_BINS,
    N_FFT,
)
from common.fixed_point import float_to_q2_14
from common.formats import write_hex, write_txt_table, write_json

try:
    from .gen_wdrc_tables import compute_channel_bands
except ImportError:
    from gen_wdrc_tables import compute_channel_bands


# ---------------------------------------------------------------------------
# Per-channel open/close thresholds
# ---------------------------------------------------------------------------
def compute_noise_gate_table(thresholds_db: List[float] | None = None,
                             hysteresis_db: float = 3.0,
                             n_channels: int = WDRC_CHANNELS,
                             f_low: float = 80.0,
                             f_high: float | None = None,
                             fs: float = FS) -> Dict[str, object]:
    """Compute per-channel open/close thresholds with hysteresis.

    If ``thresholds_db`` is given, it must have length ``n_channels``
    and is used verbatim.  Otherwise a frequency-dependent default is
    synthesised: low-frequency channels get higher thresholds (to reject
    mains hum and handling noise) and high-frequency channels get
    lower thresholds (to preserve speech consonants).

    Returns a dict with the band edges, open/close thresholds, and
    derived quantities.
    """
    if n_channels < 1:
        raise ValueError("compute_noise_gate_table: n_channels must be >= 1")
    if hysteresis_db < 0:
        raise ValueError("compute_noise_gate_table: hysteresis_db must be >= 0")

    bands = compute_channel_bands(n_channels=n_channels, fs=fs,
                                  f_low=f_low, f_high=f_high)
    centers = [math.sqrt(lo * hi) for lo, hi in bands]

    if thresholds_db is None:
        # Default frequency-dependent threshold (dB SPL):
        #   fc <  200 Hz -> -45 dB
        #   fc > 4000 Hz -> -65 dB
        # linear in log-frequency between.
        thresholds_db = []
        for fc in centers:
            if fc <= 200.0:
                thresholds_db.append(-45.0)
            elif fc >= 4000.0:
                thresholds_db.append(-65.0)
            else:
                t = (math.log10(fc) - math.log10(200.0)) / (
                    math.log10(4000.0) - math.log10(200.0)
                )
                thresholds_db.append(-45.0 + (-65.0 - (-45.0)) * t)

    if len(thresholds_db) != n_channels:
        raise ValueError(
            f"compute_noise_gate_table: thresholds_db length "
            f"{len(thresholds_db)} != n_channels {n_channels}"
        )

    opens = list(thresholds_db)
    closes = [o - hysteresis_db for o in opens]

    return {
        "n_channels": n_channels,
        "hysteresis_db": hysteresis_db,
        "fs": fs,
        "bands": [{"f_low": lo, "f_high": hi, "f_center": c}
                  for (lo, hi), c in zip(bands, centers)],
        "open_db": opens,
        "close_db": closes,
    }


# ---------------------------------------------------------------------------
# Envelope coefficients
# ---------------------------------------------------------------------------
def compute_gate_coefficients(attack_ms: float = 2.0,
                              release_ms: float = 50.0,
                              fs: float = FS) -> Tuple[int, int]:
    """Compute Q2.14 attack / release alphas for the noise-gate envelope.

    Same conversion as :func:`tools.profile_gen.gen_wdrc_tables.compute_envelope_coeffs`,
    kept here as a separate function so the gate's time constants are
    not coupled to the WDRC's.
    """
    if attack_ms <= 0 or release_ms <= 0:
        raise ValueError(
            f"compute_gate_coefficients: time constants must be positive "
            f"(got attack_ms={attack_ms}, release_ms={release_ms})"
        )
    if fs <= 0:
        raise ValueError("compute_gate_coefficients: fs must be positive")

    tau_a = attack_ms * 1e-3
    tau_r = release_ms * 1e-3
    alpha_a = 1.0 - math.exp(-1.0 / (tau_a * fs))
    alpha_r = 1.0 - math.exp(-1.0 / (tau_r * fs))
    return (float_to_q2_14(alpha_a), float_to_q2_14(alpha_r))


# ---------------------------------------------------------------------------
# Driver (optional convenience writer)
# ---------------------------------------------------------------------------
def write_gate_table(table: Dict[str, object],
                     env_attack_q: int,
                     env_release_q: int,
                     out_dir: Path) -> List[Path]:
    """Write the noise-gate table to ``out_dir``.

    Produces:

    * ``noise_gate_channels.json`` — full threshold table.
    * ``noise_gate_envelope.hex``  — 2 Q2.14 values: attack, release.
    * ``noise_gate_envelope.txt``  — human-readable counterpart.
    * ``noise_gate_channels.txt``  — per-channel thresholds.
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    written: List[Path] = []

    # JSON
    json_path = out_dir / "noise_gate_channels.json"
    payload = dict(table)
    payload["attack_q2_14"] = int(env_attack_q)
    payload["release_q2_14"] = int(env_release_q)
    write_json(payload, json_path)
    written.append(json_path)

    # Envelope hex
    env_hex = out_dir / "noise_gate_envelope.hex"
    write_hex([env_attack_q, env_release_q], env_hex,
              header="Noise-gate envelope coefficients: attack, release (Q2.14)")
    written.append(env_hex)

    # Envelope text
    env_txt = out_dir / "noise_gate_envelope.txt"
    rows = [
        {"name": "attack",  "alpha": env_attack_q,
         "hex": f"{env_attack_q & 0xFFFF:04X}"},
        {"name": "release", "alpha": env_release_q,
         "hex": f"{env_release_q & 0xFFFF:04X}"},
    ]
    write_txt_table(rows, env_txt, columns=["name", "alpha", "hex"])
    written.append(env_txt)

    # Per-channel text
    ch_txt = out_dir / "noise_gate_channels.txt"
    rows = []
    for i, (lo, hi) in enumerate([(b["f_low"], b["f_high"])
                                  for b in table["bands"]]):
        rows.append({
            "channel": i,
            "f_low": lo,
            "f_high": hi,
            "open_db":  table["open_db"][i],
            "close_db": table["close_db"][i],
        })
    write_txt_table(rows, ch_txt,
                    columns=["channel", "f_low", "f_high",
                             "open_db", "close_db"])
    written.append(ch_txt)

    return written


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Generate noise-gate threshold and envelope tables.",
    )
    p.add_argument("--n-channels", type=int, default=WDRC_CHANNELS)
    p.add_argument("--hysteresis-db", type=float, default=3.0)
    p.add_argument("--attack-ms", type=float, default=2.0)
    p.add_argument("--release-ms", type=float, default=50.0)
    p.add_argument("--fs", type=float, default=FS)
    p.add_argument("--thresholds", type=str, default=None,
                   help="Optional comma-separated dB SPL values (one per channel)")
    p.add_argument("--out-dir", type=Path, default=Path("fpga/generated"))
    args = p.parse_args(argv)

    thresholds: List[float] | None = None
    if args.thresholds is not None:
        thresholds = [float(x) for x in args.thresholds.split(",")]
        if len(thresholds) != args.n_channels:
            raise SystemExit(
                f"--thresholds has {len(thresholds)} values, "
                f"expected {args.n_channels}"
            )

    print(f"Generating {args.n_channels}-channel noise-gate tables "
          f"(hysteresis={args.hysteresis_db} dB, "
          f"attack={args.attack_ms}ms, release={args.release_ms}ms) "
          f"into {args.out_dir}...")

    table = compute_noise_gate_table(
        thresholds_db=thresholds,
        hysteresis_db=args.hysteresis_db,
        n_channels=args.n_channels,
        fs=args.fs,
    )
    att_q, rel_q = compute_gate_coefficients(args.attack_ms,
                                             args.release_ms,
                                             args.fs)
    table["attack_q2_14"] = int(att_q)
    table["release_q2_14"] = int(rel_q)

    written = write_gate_table(table, att_q, rel_q, args.out_dir)
    for p_ in written:
        print(f"  wrote {p_}")
    print(f"  open  range: [{min(table['open_db']):.1f}, {max(table['open_db']):.1f}] dB")
    print(f"  close range: [{min(table['close_db']):.1f}, {max(table['close_db']):.1f}] dB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
