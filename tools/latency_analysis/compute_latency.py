"""
Project Auris — Static latency budget calculator.

The DSP pipeline (window -> FFT -> gain -> IFFT -> overlap-add) plus
the codec ADC / DAC round trip contribute a fixed number of sample
periods to the total end-to-end audio latency.  This module aggregates
those contributions into a :class:`LatencyBudget` and exposes a small
CLI to print the breakdown as an ASCII table.
"""

from __future__ import annotations

import argparse
import math
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional

_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import FS, N_FFT, N_BINS, FRAME_ADVANCE, LATENCY_TARGET_MS


# ---------------------------------------------------------------------------
# Data class
# ---------------------------------------------------------------------------
@dataclass
class LatencyBudget:
    """Per-stage latency breakdown in milliseconds.

    All times are in milliseconds; the ``total_ms`` field is the
    sum of the seven individual stages and represents the
    end-to-end round-trip latency.
    """

    codec_adc_ms: float
    buffer_fill_ms: float
    fft_ms: float
    processing_ms: float
    ifft_ms: float
    ola_ms: float
    codec_dac_ms: float
    total_ms: float


# ---------------------------------------------------------------------------
# Computation
# ---------------------------------------------------------------------------
def compute_theoretical_latency(n_fft: int = N_FFT,
                                frame_advance: int = FRAME_ADVANCE,
                                fs: float = FS,
                                pipeline_stages: int = 3,
                                codec_delay_ms: float = 0.5
                                ) -> LatencyBudget:
    """Compute the static latency budget of the DSP pipeline.

    The contributions are:

    * ``buffer_fill`` — the time required to accumulate one FFT
      frame: ``n_fft / fs * 1000``.
    * ``fft``         — the time to perform a single ``n_fft``-point
      FFT, modelled as ``n_fft / fs * 1000 * log2(n_fft) /
      pipeline_stages``.  ``pipeline_stages`` is the number of
      butterfly stages that can be pipelined in parallel on the
      FPGA fabric (3 = the radix-4 / radix-2 mix used by the
      dblclockfft core).
    * ``processing``  — per-bin gain application, modelled as
      ``n_bins / fs * 1000``.  This is an underestimate (real gain
      calculation is a few cycles per bin) but is a useful lower
      bound.
    * ``ifft``        — same as ``fft``.
    * ``ola``         — the overlap-add wait: ``frame_advance /
      fs * 1000``.  This is the time until the next frame is fully
      overlapped in.
    * ``codec``       — combined ADC + DAC delay, modelled as
      ``2 * codec_delay_ms``.

    Parameters
    ----------
    n_fft : int
        FFT length.
    frame_advance : int
        Samples between successive frames (hop size).
    fs : float
        Sample rate in Hz.
    pipeline_stages : int
        Number of parallel butterfly stages in the FFT core.
    codec_delay_ms : float
        Per-codec-stage delay (ADC or DAC) in ms.

    Returns
    -------
    LatencyBudget
        The per-stage and total latency in milliseconds.
    """
    if n_fft < 1:
        raise ValueError(f"compute_theoretical_latency: n_fft must be >= 1 (got {n_fft})")
    if frame_advance < 1:
        raise ValueError(
            f"compute_theoretical_latency: frame_advance must be >= 1 (got {frame_advance})"
        )
    if fs <= 0:
        raise ValueError(f"compute_theoretical_latency: fs must be > 0 (got {fs})")
    if pipeline_stages < 1:
        raise ValueError(
            f"compute_theoretical_latency: pipeline_stages must be >= 1 "
            f"(got {pipeline_stages})"
        )
    if codec_delay_ms < 0:
        raise ValueError(
            f"compute_theoretical_latency: codec_delay_ms must be >= 0 "
            f"(got {codec_delay_ms})"
        )

    n_bins = n_fft // 2

    sample_ms = 1000.0 / fs
    buffer_fill = n_fft * sample_ms
    # Streaming pipelined FFT: one sample in per clock cycle,
    # plus log2(N)/pipeline_stages cycles of pipeline fill.
    fft_t = n_fft * sample_ms + (math.log2(n_fft) / pipeline_stages) * sample_ms
    processing = n_bins * sample_ms
    ifft_t = fft_t
    ola = frame_advance * sample_ms
    codec_total = 2.0 * codec_delay_ms
    total = buffer_fill + fft_t + processing + ifft_t + ola + codec_total

    return LatencyBudget(
        codec_adc_ms=codec_delay_ms,
        buffer_fill_ms=buffer_fill,
        fft_ms=fft_t,
        processing_ms=processing,
        ifft_ms=ifft_t,
        ola_ms=ola,
        codec_dac_ms=codec_delay_ms,
        total_ms=total,
    )


# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------
def format_latency_table(budget: LatencyBudget,
                         target_ms: float = LATENCY_TARGET_MS) -> str:
    """Return a formatted ASCII table showing the latency breakdown."""
    rows = [
        ("codec_adc",   budget.codec_adc_ms),
        ("buffer_fill", budget.buffer_fill_ms),
        ("fft",         budget.fft_ms),
        ("processing",  budget.processing_ms),
        ("ifft",        budget.ifft_ms),
        ("ola",         budget.ola_ms),
        ("codec_dac",   budget.codec_dac_ms),
    ]
    width_name = max(len(n) for n, _ in rows)
    lines = [
        f"{'Stage':<{width_name}s}  {'ms':>10s}  {'%':>6s}",
        f"{'-' * width_name}  {'-' * 10}  {'-' * 6}",
    ]
    total = max(budget.total_ms, 1e-12)
    for name, ms in rows:
        pct = 100.0 * ms / total
        lines.append(f"{name:<{width_name}s}  {ms:10.4f}  {pct:5.1f}%")
    lines.append(f"{'-' * width_name}  {'-' * 10}  {'-' * 6}")
    lines.append(
        f"{'total':<{width_name}s}  {budget.total_ms:10.4f}  "
        f"{100.0 * budget.total_ms / total:5.1f}%"
    )
    margin = target_ms - budget.total_ms
    status = "PASS" if budget.total_ms <= target_ms else "FAIL"
    lines.append("")
    lines.append(f"target: {target_ms:.3f} ms  margin: {margin:+.4f} ms  "
                 f"status: {status}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: Optional[list] = None) -> int:
    p = argparse.ArgumentParser(
        description="Compute the static DSP pipeline latency budget.",
    )
    p.add_argument("--n-fft", type=int, default=N_FFT)
    p.add_argument("--frame-advance", type=int, default=FRAME_ADVANCE)
    p.add_argument("--fs", type=float, default=FS)
    p.add_argument("--pipeline-stages", type=int, default=3,
                   help="FFT butterfly pipeline depth (default: %(default)s)")
    p.add_argument("--codec-delay-ms", type=float, default=0.5,
                   help="Per-codec-stage delay in ms (default: %(default)s)")
    p.add_argument("--target-ms", type=float, default=LATENCY_TARGET_MS,
                   help="Pass / fail target in ms (default: %(default)s)")
    args = p.parse_args(argv)

    budget = compute_theoretical_latency(
        n_fft=args.n_fft,
        frame_advance=args.frame_advance,
        fs=args.fs,
        pipeline_stages=args.pipeline_stages,
        codec_delay_ms=args.codec_delay_ms,
    )
    print(f"Latency budget (fs={args.fs:g} Hz, N_FFT={args.n_fft}, "
          f"hop={args.frame_advance}, stages={args.pipeline_stages}):")
    print()
    print(format_latency_table(budget, target_ms=args.target_ms))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
