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
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import FS, N_FFT, FRAME_ADVANCE, LATENCY_TARGET_MS


# ---------------------------------------------------------------------------
# Data class
# ---------------------------------------------------------------------------
@dataclass
class LatencyBudget:
    """Per-stage latency breakdown in milliseconds.

    All times are in milliseconds; the ``total_ms`` field is the
    sum of the listed contributions and represents the
    conditional serial-path estimate, not a measured round trip.
    """

    codec_adc_ms: float
    buffer_fill_ms: float
    fft_ms: float
    processing_ms: float
    ifft_ms: float
    ola_ms: float
    codec_dac_ms: float
    total_ms: float
    output_wait_ms: float = 0.0


# ---------------------------------------------------------------------------
# Computation
# ---------------------------------------------------------------------------
def compute_theoretical_latency(
    n_fft: int = N_FFT,
    frame_advance: int = FRAME_ADVANCE,
    fs: float = FS,
    pipeline_stages: Optional[int] = None,
    codec_delay_ms: float = 0.5,
    *,
    dsp_clock_hz: float = 96_000_000,
    fft_cycles: Optional[int] = None,
    ifft_cycles: Optional[int] = None,
    processing_cycles: int = 7,
    ola_cycles: int = 2,
    output_wait_samples: Optional[float] = None,
) -> LatencyBudget:
    """Conditional serial-path estimate, not measured end-to-end latency.

    Acquisition assumes one complete N-sample frame; hop duration is a cadence,
    not an extra OLA delay. FFT/IFFT cycle counts must describe the chosen
    input-to-output latency boundary consistently (including any frame wait).
    Processing defaults to the seven registered spectral stages. Codec delay
    is a supplied assumption per codec. Output wait must be supplied separately
    in audio sample periods; include transport/queue waits in that budget.
    Overlapping stage service times must not be added as serial delays.
    """
    if pipeline_stages is not None:
        raise ValueError("pipeline_stages is obsolete; supply FFT/IFFT latency cycles")
    if n_fft < 2 or n_fft & (n_fft - 1) or not 1 <= frame_advance <= n_fft:
        raise ValueError("Require power-of-two n_fft >= 2 and 1 <= hop <= n_fft")
    for name, value in (("fs", fs), ("dsp_clock_hz", dsp_clock_hz)):
        if not math.isfinite(value) or value <= 0:
            raise ValueError(f"{name} must be finite and positive")
    for name, value in (
        ("fft_cycles", fft_cycles),
        ("ifft_cycles", ifft_cycles),
        ("processing_cycles", processing_cycles),
        ("ola_cycles", ola_cycles),
    ):
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise ValueError(f"Supply nonnegative integer {name}")
    for name, value in (
        ("codec_delay_ms", codec_delay_ms),
        ("output_wait_samples", output_wait_samples),
    ):
        if value is None or not math.isfinite(value) or value < 0:
            raise ValueError(f"Supply finite nonnegative {name}")
    sample_ms = 1000.0 / fs
    cycle_ms = 1000.0 / dsp_clock_hz
    fill = n_fft * sample_ms
    fft = fft_cycles * cycle_ms
    processing = processing_cycles * cycle_ms
    ifft = ifft_cycles * cycle_ms
    ola = ola_cycles * cycle_ms
    output_wait = output_wait_samples * sample_ms
    return LatencyBudget(
        codec_adc_ms=codec_delay_ms,
        buffer_fill_ms=fill,
        fft_ms=fft,
        processing_ms=processing,
        ifft_ms=ifft,
        ola_ms=ola,
        codec_dac_ms=codec_delay_ms,
        output_wait_ms=output_wait,
        total_ms=2 * codec_delay_ms
        + fill
        + fft
        + processing
        + ifft
        + ola
        + output_wait,
    )


# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------
def format_latency_table(
    budget: LatencyBudget, target_ms: float = LATENCY_TARGET_MS
) -> str:
    """Return a formatted ASCII table showing the latency breakdown."""
    rows = [
        ("codec_adc", budget.codec_adc_ms),
        ("buffer_fill", budget.buffer_fill_ms),
        ("fft", budget.fft_ms),
        ("processing", budget.processing_ms),
        ("ifft", budget.ifft_ms),
        ("ola", budget.ola_ms),
        ("codec_dac", budget.codec_dac_ms),
        ("output_wait", budget.output_wait_ms),
    ]
    width_name = max(len(n) for n, _ in rows)
    lines = [
        "MODEL ESTIMATE: supplied delays, not measured hardware latency",
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
    lines.append(
        f"target: {target_ms:.3f} ms  margin: {margin:+.4f} ms  status: {status}"
    )
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
    p.add_argument("--dsp-clock-hz", type=float, default=96_000_000)
    p.add_argument("--fft-cycles", type=int, required=True)
    p.add_argument("--ifft-cycles", type=int, required=True)
    p.add_argument("--output-wait-samples", type=float, required=True)
    p.add_argument(
        "--codec-delay-ms",
        type=float,
        default=0.5,
        help="Per-codec-stage delay in ms (default: %(default)s)",
    )
    p.add_argument(
        "--target-ms",
        type=float,
        default=LATENCY_TARGET_MS,
        help="Pass / fail target in ms (default: %(default)s)",
    )
    args = p.parse_args(argv)

    budget = compute_theoretical_latency(
        n_fft=args.n_fft,
        frame_advance=args.frame_advance,
        fs=args.fs,
        dsp_clock_hz=args.dsp_clock_hz,
        fft_cycles=args.fft_cycles,
        ifft_cycles=args.ifft_cycles,
        output_wait_samples=args.output_wait_samples,
        codec_delay_ms=args.codec_delay_ms,
    )
    print(
        f"Latency budget (fs={args.fs:g} Hz, N_FFT={args.n_fft}, "
        f"hop={args.frame_advance}, dsp_clock={args.dsp_clock_hz:g} Hz):"
    )
    print()
    print(format_latency_table(budget, target_ms=args.target_ms))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
