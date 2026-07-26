"""
Project Auris — Wide-Dynamic-Range-Compression (WDRC) table generator.

Implements the I/O curve and envelope coefficients for a multi-channel
WDRC compressor.  The default configuration has 16 logarithmically
spaced channels spanning 80 Hz to FS/2.

The I/O curve is a four-segment piecewise-linear function:

    * Below ``low_knee_db``  — expansion with ratio ``cr_expansion``
      (slope ``1 / cr_expansion``).
    * Between the knees       — linear (slope 1, the "linear" region).
    * Above ``high_knee_db``  — compression with ratio ``cr_compression``
      (slope ``1 / cr_compression``).
    * Above ``limit_db``      — limiting with ratio ``cr_limiter``.

Continuity is enforced at every knee point so the curve is C0
continuous (no audible "kinks" when the input level crosses a
threshold).
"""

from __future__ import annotations

import argparse
import math
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, List, Tuple

# Make direct invocation work.
_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import (
    FS,
    WDRC_CHANNELS,
    WDRC_LOW_KNEE_DB,
    WDRC_HIGH_KNEE_DB,
    WDRC_LIMIT_DB,
    WDRC_CR_EXPANSION,
    WDRC_CR_COMPRESSION,
    WDRC_CR_LIMITER,
    WDRC_ATTACK_MS,
    WDRC_RELEASE_MS,
)
from common.fixed_point import float_to_q2_14
from common.formats import write_hex, write_txt_table, write_json


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------
@dataclass
class WDRCChannel:
    """Static configuration of a single WDRC channel."""
    channel_idx: int
    f_low: float
    f_high: float
    low_knee_db: float
    high_knee_db: float
    limit_db: float
    cr_expansion: float
    cr_compression: float
    cr_limiter: float

    def band_width_oct(self) -> float:
        """Octave width of the channel band."""
        if self.f_low <= 0:
            return 0.0
        return math.log2(self.f_high / self.f_low)


# ---------------------------------------------------------------------------
# Band allocation
# ---------------------------------------------------------------------------
def compute_channel_bands(n_channels: int = WDRC_CHANNELS,
                          fs: float = FS,
                          f_low: float = 80.0,
                          f_high: float | None = None
                          ) -> List[Tuple[float, float]]:
    """Logarithmic band allocation from ``f_low`` to ``f_high`` (default ``fs/2``).

    Returns a list of ``(f_low_i, f_high_i)`` tuples, each band sharing a
    border with its neighbour.
    """
    if n_channels < 1:
        raise ValueError(f"compute_channel_bands: n_channels must be >= 1 (got {n_channels})")
    if f_low <= 0:
        raise ValueError("compute_channel_bands: f_low must be > 0")
    if f_high is None:
        f_high = fs / 2.0
    if f_high <= f_low:
        raise ValueError(
            f"compute_channel_bands: f_high ({f_high}) must be > f_low ({f_low})"
        )

    log_lo = math.log10(f_low)
    log_hi = math.log10(f_high)
    edges = [10.0 ** (log_lo + (log_hi - log_lo) * i / n_channels)
             for i in range(n_channels + 1)]
    return [(edges[i], edges[i + 1]) for i in range(n_channels)]


# ---------------------------------------------------------------------------
# I/O curves
# ---------------------------------------------------------------------------
def _piecewise_io(input_db: float,
                  low_knee: float,
                  high_knee: float,
                  limit_db: float,
                  cr_exp: float,
                  cr_comp: float,
                  cr_lim: float) -> float:
    """Four-segment piecewise-linear I/O curve.

    The anchor point is the linear region between the two knees: at
    ``input = high_knee`` the output is also ``high_knee`` (i.e. the
    unity line passes through the upper knee).  Continuity is enforced
    at every knee so the curve is C0 continuous.
    """
    if cr_exp <= 0 or cr_comp <= 0 or cr_lim <= 0:
        raise ValueError("_piecewise_io: compression ratios must be positive")

    # Compute the gain offset at the high knee so the linear segment is
    # unity: output = input at high_knee.
    g_at_high_knee = 0.0

    # Below low_knee: expansion with slope 1/cr_exp, anchored at (low_knee, low_knee).
    if input_db <= low_knee:
        # offset below low knee: g_at_low_knee = (1 - 1/cr_exp) * low_knee
        #                       + 1/cr_exp * low_knee ... actually slope 1/cr_exp through (low_knee, low_knee).
        # output = low_knee + (input - low_knee) / cr_exp
        return low_knee + (input_db - low_knee) / cr_exp

    # Between low_knee and high_knee: linear (slope 1).
    if input_db <= high_knee:
        return input_db

    # Between high_knee and limit_db: compression, slope 1/cr_comp,
    # anchored at (high_knee, high_knee) for continuity.
    if input_db <= limit_db:
        return high_knee + (input_db - high_knee) / cr_comp

    # Above limit_db: limiting, slope 1/cr_lim, anchored at (limit_db, output_at_limit).
    out_at_limit = high_knee + (limit_db - high_knee) / cr_comp
    return out_at_limit + (input_db - limit_db) / cr_lim


def compute_io_curve(channel: WDRCChannel,
                     n_points: int = 256) -> List[Tuple[float, float]]:
    """Compute a sampled I/O curve for the given channel.

    The input axis is sampled linearly from ``-10 dB`` to
    ``limit_db + 10 dB`` in ``n_points`` steps.
    """
    if n_points < 4:
        raise ValueError(f"compute_io_curve: n_points must be >= 4 (got {n_points})")

    in_min = -10.0
    in_max = channel.limit_db + 10.0
    step = (in_max - in_min) / (n_points - 1)

    curve: List[Tuple[float, float]] = []
    for i in range(n_points):
        x = in_min + i * step
        y = _piecewise_io(
            x,
            channel.low_knee_db,
            channel.high_knee_db,
            channel.limit_db,
            channel.cr_expansion,
            channel.cr_compression,
            channel.cr_limiter,
        )
        curve.append((x, y))
    return curve


# ---------------------------------------------------------------------------
# Envelope coefficients
# ---------------------------------------------------------------------------
def compute_envelope_coeffs(attack_ms: float,
                            release_ms: float,
                            fs: float = FS) -> Tuple[int, int]:
    """Compute Q2.14 alpha values for attack / release envelope followers.

    alpha = 1 - exp(-1 / (tau * fs))
    where tau = ms * 1e-3.

    Parameters
    ----------
    attack_ms, release_ms : float
        Time constants in milliseconds.
    fs : float
        Sample rate in Hz.

    Returns
    -------
    (alpha_attack, alpha_release) : Tuple[int, int]
        Both values are signed Q2.14 16-bit integers.
    """
    if attack_ms <= 0 or release_ms <= 0:
        raise ValueError(
            f"compute_envelope_coeffs: time constants must be positive "
            f"(got attack_ms={attack_ms}, release_ms={release_ms})"
        )
    if fs <= 0:
        raise ValueError(f"compute_envelope_coeffs: fs must be positive (got {fs})")

    tau_a = attack_ms * 1e-3
    tau_r = release_ms * 1e-3

    alpha_a = 1.0 - math.exp(-1.0 / (tau_a * fs))
    alpha_r = 1.0 - math.exp(-1.0 / (tau_r * fs))

    return (float_to_q2_14(alpha_a), float_to_q2_14(alpha_r))


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------
def generate_wdrc_tables(n_channels: int = WDRC_CHANNELS,
                         out_dir: Path | None = None,
                         fs: float = FS,
                         attack_ms: float = WDRC_ATTACK_MS,
                         release_ms: float = WDRC_RELEASE_MS,
                         low_knee_db: float = WDRC_LOW_KNEE_DB,
                         high_knee_db: float = WDRC_HIGH_KNEE_DB,
                         limit_db: float = WDRC_LIMIT_DB,
                         cr_expansion: float = WDRC_CR_EXPANSION,
                         cr_compression: float = WDRC_CR_COMPRESSION,
                         cr_limiter: float = WDRC_CR_LIMITER
                         ) -> Dict[str, object]:
    """Generate per-channel I/O curves and global envelope coefficients.

    If ``out_dir`` is given, the following files are written:

    * ``wdrc_channels.json``   — full configuration + all curves.
    * ``wdrc_envelope.hex``    — 2 Q2.14 values: attack, release.
    * ``wdrc_envelope.txt``    — human-readable counterpart.
    """
    if out_dir is not None:
        out_dir = Path(out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

    bands = compute_channel_bands(n_channels=n_channels, fs=fs)

    channels: List[WDRCChannel] = []
    curves: List[List[Tuple[float, float]]] = []
    for idx, (flo, fhi) in enumerate(bands):
        ch = WDRCChannel(
            channel_idx=idx,
            f_low=flo,
            f_high=fhi,
            low_knee_db=low_knee_db,
            high_knee_db=high_knee_db,
            limit_db=limit_db,
            cr_expansion=cr_expansion,
            cr_compression=cr_compression,
            cr_limiter=cr_limiter,
        )
        channels.append(ch)
        curves.append(compute_io_curve(ch))

    attack_q, release_q = compute_envelope_coeffs(attack_ms, release_ms, fs)

    if out_dir is not None:
        # JSON summary.
        summary = {
            "n_channels": n_channels,
            "fs": fs,
            "attack_ms": attack_ms,
            "release_ms": release_ms,
            "attack_q2_14": int(attack_q),
            "release_q2_14": int(release_q),
            "channels": [asdict(ch) for ch in channels],
            "curves": [
                [{"in_db": x, "out_db": y} for x, y in c] for c in curves
            ],
        }
        write_json(summary, out_dir / "wdrc_channels.json")

        # Envelope coefficient hex file (2 words: attack, release).
        env_path = out_dir / "wdrc_envelope.hex"
        write_hex([attack_q, release_q], env_path,
                  header=(f"WDRC envelope coefficients, "
                          f"attack={attack_ms}ms release={release_ms}ms @ {fs}Hz"))

        # Envelope coefficient text file.
        env_txt = out_dir / "wdrc_envelope.txt"
        rows = [
            {"name": "attack",  "ms": attack_ms,  "alpha": attack_q,
             "hex": f"{attack_q & 0xFFFF:04X}"},
            {"name": "release", "ms": release_ms, "alpha": release_q,
             "hex": f"{release_q & 0xFFFF:04X}"},
        ]
        write_txt_table(rows, env_txt,
                        columns=["name", "ms", "alpha", "hex"])

        # Per-channel I/O curves as .txt files (one per channel).
        for ch, curve in zip(channels, curves):
            rows = [{"in_db": x, "out_db": y} for x, y in curve]
            write_txt_table(
                rows,
                out_dir / f"wdrc_ch{ch.channel_idx:02d}_curve.txt",
                columns=["in_db", "out_db"],
            )
        print(f"  wrote {n_channels} channel curves + envelope coeffs "
              f"to {out_dir}")

    return {
        "channels": channels,
        "curves": curves,
        "attack_q": attack_q,
        "release_q": release_q,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Generate WDRC I/O curves and envelope coefficients.",
    )
    p.add_argument("--n-channels", type=int, default=WDRC_CHANNELS)
    p.add_argument("--fs", type=float, default=FS)
    p.add_argument("--attack-ms", type=float, default=WDRC_ATTACK_MS)
    p.add_argument("--release-ms", type=float, default=WDRC_RELEASE_MS)
    p.add_argument("--out-dir", type=Path, default=Path("fpga/generated"))
    args = p.parse_args(argv)

    print(f"Generating {args.n_channels}-channel WDRC tables "
          f"(attack={args.attack_ms}ms, release={args.release_ms}ms) "
          f"into {args.out_dir}...")
    result = generate_wdrc_tables(
        n_channels=args.n_channels,
        out_dir=args.out_dir,
        fs=args.fs,
        attack_ms=args.attack_ms,
        release_ms=args.release_ms,
    )
    print(f"  attack  Q2.14 = {result['attack_q']:#06x}")
    print(f"  release Q2.14 = {result['release_q']:#06x}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
