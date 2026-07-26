"""
Project Auris — Audiogram data structures and frequency / bin helpers.

An audiogram is a vector of hearing thresholds in dB HL measured at a
standard set of audiometric frequencies (250, 500, 1000, 2000, 3000,
4000, 6000 Hz). The :class:`Audiogram` dataclass wraps these thresholds
and provides conversions to insertion-gain and per-bin gain tables.
"""

from __future__ import annotations

import math
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

# Make ``python tools/common/audiogram.py`` work from any cwd.
_TOOLS_DIR = Path(__file__).resolve().parent.parent
if str(_TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOLS_DIR))

try:
    from .constants import (
        AUDIOGRAM_FREQS,
        N_FFT,
        N_BINS,
        FS,
        GAIN_DB_MIN,
        GAIN_DB_MAX,
    )
except ImportError:
    from common.constants import (
        AUDIOGRAM_FREQS,
        N_FFT,
        N_BINS,
        FS,
        GAIN_DB_MIN,
        GAIN_DB_MAX,
    )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def freq_to_bin(f_hz: float, fs: float = FS, n_fft: int = N_FFT) -> int:
    """Convert a frequency in Hz to the nearest FFT bin index.

    The mapping is the standard ``k = round(f * N / fs)``, which gives
    the bin whose center is closest to ``f_hz``.
    """
    return int(round(f_hz * n_fft / fs))


def bin_to_freq(k: int, fs: float = FS, n_fft: int = N_FFT) -> float:
    """Return the center frequency (Hz) of FFT bin ``k``."""
    return k * fs / n_fft


def log_freq_interpolate(ref_freqs: Sequence[float],
                         ref_vals: Sequence[float],
                         target_freqs: Sequence[float]) -> List[float]:
    """Piecewise-linear interpolation in log10(f) space.

    Parameters
    ----------
    ref_freqs : sequence of float
        Strictly increasing reference frequencies in Hz. All values
        must be strictly positive.
    ref_vals : sequence of float
        Reference values, same length as ``ref_freqs``.
    target_freqs : sequence of float
        Frequencies to evaluate at.

    Returns
    -------
    list of float
        Interpolated values, same length as ``target_freqs``.

    Behaviour outside the reference range
    ------------------------------------
    * ``f <= 0``            -> 0.0
    * ``0 < f < f_ref[0]``  -> linear extrapolation from
      ``(f_ref[0], ref_vals[0])`` to ``(0, 0)``.  In log domain this is a
      straight line in ``log10(f)``.
    * ``f_ref[-1] < f <= fs/2`` -> linear rolloff from
      ``(f_ref[-1], ref_vals[-1])`` to ``(fs/2, 0)``.  The ``fs/2`` is
      taken as the larger of the two end-points' neighbour or 2 *
      ``f_ref[-1]`` (typical: 12 kHz for a 6 kHz reference).
    """
    if len(ref_freqs) != len(ref_vals):
        raise ValueError(
            f"log_freq_interpolate: ref_freqs and ref_vals must be equal length "
            f"({len(ref_freqs)} vs {len(ref_vals)})"
        )
    if len(ref_freqs) < 2:
        raise ValueError("log_freq_interpolate: need at least 2 reference points")

    for f in ref_freqs:
        if f <= 0:
            raise ValueError("log_freq_interpolate: ref_freqs must be strictly positive")

    # Sort by frequency (and reorder values) in case the caller did not.
    pairs = sorted(zip(ref_freqs, ref_vals), key=lambda p: p[0])
    ref_freqs_sorted = [p[0] for p in pairs]
    ref_vals_sorted = [p[1] for p in pairs]
    log_refs = [math.log10(f) for f in ref_freqs_sorted]

    f_low = ref_freqs_sorted[0]
    f_high = ref_freqs_sorted[-1]

    # Choose the rolloff endpoint above f_high.  The standard choice is
    # fs/2 (Nyquist).  Fall back to 2 * f_high if Nyquist is not available.
    f_rolloff_high = FS / 2.0
    if f_rolloff_high <= f_high:
        f_rolloff_high = 2.0 * f_high
    log_f_high = math.log10(f_high)
    log_f_rolloff = math.log10(f_rolloff_high)
    val_at_f_high = ref_vals_sorted[-1]

    log_f_low = log_refs[0]
    val_at_f_low = ref_vals_sorted[0]

    out: List[float] = []
    for f in target_freqs:
        if f <= 0.0:
            out.append(0.0)
            continue

        log_f = math.log10(f)

        if log_f <= log_f_low:
            # Linear rolloff to 0 at DC in log domain.
            if log_f_low == log_f:
                out.append(val_at_f_low)
            else:
                # In log10(f) space, "linear" interpolation between
                # (log10(0+) = -inf, 0) and (log_f_low, val_at_f_low)
                # is undefined; we use the linear-in-f rolloff as a
                # pragmatic choice: g = val_at_f_low * (f / f_low).
                g = val_at_f_low * (f / f_low)
                out.append(g)
            continue

        if log_f >= log_f_rolloff:
            out.append(0.0)
            continue

        if log_f >= log_f_high:
            # Linear rolloff in linear-f from (f_high, val_at_f_high)
            # to (f_rolloff_high, 0).
            t = (f - f_high) / (f_rolloff_high - f_high)
            g = val_at_f_high * (1.0 - t)
            out.append(g)
            continue

        # Find bracketing index.
        idx = None
        for i in range(len(log_refs) - 1):
            if log_refs[i] <= log_f <= log_refs[i + 1]:
                idx = i
                break
        if idx is None:
            # Should not happen.
            out.append(0.0)
            continue

        lo_f, hi_f = log_refs[idx], log_refs[idx + 1]
        lo_v, hi_v = ref_vals_sorted[idx], ref_vals_sorted[idx + 1]
        t = (log_f - lo_f) / (hi_f - lo_f) if hi_f != lo_f else 0.0
        out.append((1.0 - t) * lo_v + t * hi_v)

    return out


# ---------------------------------------------------------------------------
# Audiogram dataclass
# ---------------------------------------------------------------------------
@dataclass
class Audiogram:
    """Hearing thresholds in dB HL at the 7 standard audiometric frequencies.

    Attributes
    ----------
    thresholds : list of float
        ``len == 7``; values in ``[0, 120]`` dB HL.
    frequencies : tuple of int
        The reference frequencies in Hz. Defaults to :data:`AUDIOGRAM_FREQS`.
    label : str, optional
        A free-form label (e.g. ``"left_ear"`` or ``"mild_high_freq"``).
    """

    thresholds: List[float]
    frequencies: Tuple[int, ...] = AUDIOGRAM_FREQS
    label: str = "default"

    def __post_init__(self) -> None:
        self.validate()

    # ------------------------------------------------------------------ API
    def validate(self) -> None:
        """Validate length, range, and finiteness of thresholds.

        Raises
        ------
        ValueError
            If any threshold is not finite, the list is not exactly 7
            entries long, or any value lies outside ``[0, 120]`` dB HL.
        """
        if len(self.thresholds) != len(self.frequencies):
            raise ValueError(
                f"Audiogram.validate: expected {len(self.frequencies)} "
                f"thresholds, got {len(self.thresholds)}"
            )
        for i, t in enumerate(self.thresholds):
            if t != t:                            # NaN
                raise ValueError(
                    f"Audiogram.validate: threshold {i} is NaN"
                )
            if t == float("inf") or t == float("-inf"):
                raise ValueError(
                    f"Audiogram.validate: threshold {i} is infinite"
                )
            if t < 0.0 or t > 120.0:
                raise ValueError(
                    f"Audiogram.validate: threshold {i} ({t}) is out of "
                    f"range [0, 120] dB HL"
                )

    # --------------- conversions
    def to_insertion_gain(self,
                          formula: str = "nal_r"
                          ) -> List[float]:
        """Compute insertion gain in dB at each audiometric frequency.

        Delegates to :mod:`tools.profile_gen.fitting_formulas` (imported
        lazily to avoid a circular dependency and to support direct
        script execution of ``audiogram.py``).
        """
        try:
            from ..profile_gen.fitting_formulas import compute
        except (ImportError, ValueError):
            # Fall back to absolute import when this module is being
            # executed as a script (no parent package context).
            import sys
            from pathlib import Path
            tools_dir = Path(__file__).resolve().parent.parent
            if str(tools_dir) not in sys.path:
                sys.path.insert(0, str(tools_dir))
            from profile_gen.fitting_formulas import compute
        return compute(formula, list(self.thresholds), self.frequencies)

    def to_bin_gains(self,
                     formula: str = "nal_r",
                     n_bins: int = N_BINS,
                     apply_rolloff: bool = True) -> List[float]:
        """Convert to a per-bin gain table (dB).

        Parameters
        ----------
        formula : str
            Prescriptive formula name (``"nal_r"``, ``"nal_nl2"``,
            ``"dsl_v5"``).
        n_bins : int
            Number of FFT bins to produce (defaults to 128).
        apply_rolloff : bool
            If True, force DC to 0 dB and apply a high-frequency rolloff
            above 6 kHz as defined in :func:`log_freq_interpolate`.

        Returns
        -------
        list of float
            ``n_bins`` gain values in dB.
        """
        gains = self.to_insertion_gain(formula)

        # Target bin frequencies.
        target_freqs = [k * FS / N_FFT for k in range(n_bins)]

        if apply_rolloff:
            interpolated = log_freq_interpolate(
                list(self.frequencies), gains, target_freqs
            )
            # Force DC to 0 dB.
            if interpolated:
                interpolated[0] = 0.0
        else:
            interpolated = log_freq_interpolate(
                list(self.frequencies), gains, target_freqs
            )

        # Clamp to the supported gain range.
        interpolated = [
            max(GAIN_DB_MIN, min(GAIN_DB_MAX, g)) for g in interpolated
        ]
        return interpolated


# ---------------------------------------------------------------------------
# CLI smoke test
# ---------------------------------------------------------------------------
def _cli() -> None:                 # pragma: no cover
    import argparse
    p = argparse.ArgumentParser(description="Audiogram utility smoke test")
    p.add_argument("--audiogram",
                   default="0,0,10,25,35,40,45",
                   help="7 dB HL thresholds at 250,500,1k,2k,3k,4k,6k Hz")
    p.add_argument("--formula", default="nal_r",
                   choices=("nal_r", "nal_nl2", "dsl_v5"))
    args = p.parse_args()

    th = [float(x) for x in args.audiogram.split(",")]
    a = Audiogram(th)
    print(f"Audiogram: {a.thresholds} dB HL  (label={a.label!r})")
    print(f"Insertion gain ({args.formula}): "
          f"{[round(g, 2) for g in a.to_insertion_gain(args.formula)]}")
    bins = a.to_bin_gains(args.formula)
    print(f"Bin gains (dB, first 16): {[round(g, 2) for g in bins[:16]]}")


if __name__ == "__main__":
    _cli()
