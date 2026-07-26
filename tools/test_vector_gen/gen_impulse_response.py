"""
Project Auris — Impulse-response generators and convolution helpers.

Used by the audio QA suite to synthesise FIR filter impulse responses
(identity, pure delay, lowpass) and to convolve them with reference
test signals.  The result is a pair of input / output stimuli that
exercises the FPGA's convolution engine end-to-end.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import List

_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import FS, N_FFT, FRAME_ADVANCE
from common.fixed_point import batch_float_to_q2_14
from common.formats import write_hex, write_txt_table, write_json


# ---------------------------------------------------------------------------
# Impulse-response generators
# ---------------------------------------------------------------------------
def gen_identity_ir(length: int = N_FFT) -> List[float]:
    """Return an identity IR (single 1.0 at index 0)."""
    if length < 1:
        raise ValueError(f"gen_identity_ir: length must be >= 1 (got {length})")
    out = [0.0] * length
    out[0] = 1.0
    return out


def gen_delay_ir(delay_samples: int, length: int = N_FFT) -> List[float]:
    """Return an IR that is a pure ``delay_samples``-sample delay."""
    if length < 1:
        raise ValueError(f"gen_delay_ir: length must be >= 1 (got {length})")
    if delay_samples < 0:
        raise ValueError(
            f"gen_delay_ir: delay_samples must be >= 0 (got {delay_samples})"
        )
    out = [0.0] * length
    if delay_samples < length:
        out[delay_samples] = 1.0
    return out


def gen_lowpass_ir(cutoff_hz: float,
                   n_taps: int = 64,
                   fs: float = FS) -> List[float]:
    """Return a windowed-sinc lowpass FIR impulse response.

    The windowed-sinc formula for a linear-phase lowpass is

    .. math::

        h[n] = \\frac{\\sin(2\\pi f_c (n - M) / f_s)}{\\pi (n - M)}\\,
               w[n], \\quad h[M] = 2 f_c / f_s

    with a Hamming window applied and the result normalised for unity
    DC gain.
    """
    if n_taps < 1:
        raise ValueError(f"gen_lowpass_ir: n_taps must be >= 1 (got {n_taps})")
    if cutoff_hz <= 0.0 or cutoff_hz >= fs / 2.0:
        raise ValueError(
            f"gen_lowpass_ir: cutoff_hz must be in (0, fs/2) "
            f"(got {cutoff_hz}, fs/2={fs / 2.0})"
        )

    M = (n_taps - 1) / 2.0
    f_n = cutoff_hz / fs
    h: List[float] = []
    for n in range(n_taps):
        x = n - M
        if x == 0:
            h_n = 2.0 * f_n
        else:
            h_n = math.sin(2.0 * math.pi * f_n * x) / (math.pi * x)
        # Hamming window.
        if n_taps > 1:
            w = 0.54 - 0.46 * math.cos(2.0 * math.pi * n / (n_taps - 1))
        else:
            w = 1.0
        h.append(h_n * w)

    # Normalise to unity DC gain (sum = 1).
    s = sum(h)
    if s != 0:
        h = [v / s for v in h]
    return h


# ---------------------------------------------------------------------------
# Convolution
# ---------------------------------------------------------------------------
def convolve_with_ir(signal: List[float], ir: List[float]) -> List[float]:
    """Direct (O(N*M)) convolution of ``signal`` with ``ir``.

    The output length is ``len(signal) + len(ir) - 1`` (full mode).
    """
    if not signal or not ir:
        if signal or ir:
            return [0.0] * (len(signal) + len(ir) - 1)
        return []
    n_out = len(signal) + len(ir) - 1
    out = [0.0] * n_out
    for n in range(n_out):
        s = 0.0
        k_lo = max(0, n - len(ir) + 1)
        k_hi = min(len(signal), n + 1)
        for k in range(k_lo, k_hi):
            s += signal[k] * ir[n - k]
        out[n] = s
    return out


# ---------------------------------------------------------------------------
# Test-suite writer
# ---------------------------------------------------------------------------
def _write_signal_pair(out_dir: Path,
                       name: str,
                       sig_in: List[float],
                       sig_out: List[float],
                       ir: List[float]) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    in_q = batch_float_to_q2_14(sig_in)
    out_q = batch_float_to_q2_14(sig_out)
    ir_q = batch_float_to_q2_14(ir)

    write_hex(in_q, out_dir / f"{name}_in.hex",
              header=f"IR test input, {name}")
    write_hex(out_q, out_dir / f"{name}_out.hex",
              header=f"IR test expected output, {name}")
    write_hex(ir_q, out_dir / f"{name}_ir.hex",
              header=f"IR test impulse response, {name}")

    rows = [{"idx": i, "ir_float": ir[i], "ir_q2_14": ir_q[i]}
            for i in range(len(ir))]
    write_txt_table(rows, out_dir / f"{name}_ir.txt",
                    columns=["idx", "ir_float", "ir_q2_14"])


def generate_ir_test_suite(out_dir: Path) -> dict:
    """Generate the canonical IR regression test suite.

    The suite contains:

    * ``identity``    — IR = ``[1, 0, 0, ...]`` (output must equal input).
    * ``delay_10``    — IR = 10-sample delay.
    * ``delay_64``    — IR = 64-sample delay (frame-advance size).
    * ``lowpass_2k``  — 64-tap lowpass at 2 kHz.

    For each IR the function convolves it with a 1024-sample unit
    sinusoid at 500 Hz to produce a non-trivial output and writes the
    input / output / IR as both Q2.14 hex and human-readable text.

    Parameters
    ----------
    out_dir : Path
        Destination directory; created if it does not exist.

    Returns
    -------
    dict
        Summary of the generated test cases (name, IR length, max
        output amplitude, etc.).
    """
    out_dir.mkdir(parents=True, exist_ok=True)

    # Driver signal: 1024-sample sinusoid at 500 Hz, unit amplitude.
    n_sig = 1024
    sig = [math.sin(2.0 * math.pi * 500.0 * n / FS) for n in range(n_sig)]

    cases: List[dict] = []
    irs: List[tuple] = [
        ("identity", gen_identity_ir(N_FFT)),
        ("delay_10", gen_delay_ir(10, N_FFT)),
        ("delay_64", gen_delay_ir(FRAME_ADVANCE, N_FFT)),
        ("lowpass_2k", gen_lowpass_ir(2000.0, n_taps=64, fs=FS)),
    ]
    for name, ir in irs:
        sig_out = convolve_with_ir(sig, ir)
        _write_signal_pair(out_dir, name, sig, sig_out, ir)
        cases.append({
            "name": name,
            "ir_length": len(ir),
            "out_length": len(sig_out),
            "max_abs_out": max(abs(v) for v in sig_out) if sig_out else 0.0,
        })

    summary = {"fs": FS, "n_fft": N_FFT,
               "driver_signal": "sinusoid 500Hz 1024 samples",
               "cases": cases}
    write_json(summary, out_dir / "ir_test_suite_summary.json")
    return summary


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="IR test-vector generator.")
    p.add_argument("--out-dir", type=Path, default=Path("ir_test_vectors"),
                   help="Destination directory (default: %(default)s).")
    args = p.parse_args(argv)

    summary = generate_ir_test_suite(args.out_dir)
    print(f"IR test suite written to {args.out_dir}")
    for c in summary["cases"]:
        print(f"  {c['name']:12s} ir_len={c['ir_length']:4d}  "
              f"out_len={c['out_length']:5d}  max={c['max_abs_out']:.4f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
