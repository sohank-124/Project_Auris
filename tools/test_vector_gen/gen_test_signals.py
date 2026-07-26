"""
Project Auris — Reproducible test-signal generators.

Every generator returns a plain ``list[float]`` in the range
``[-amplitude, +amplitude]`` and is fully deterministic for a given
``seed`` (random number generators use NumPy with a fixed seed).

When invoked as a script the chosen signal is written to disk twice:

* ``<out>.txt``  — one float per line (human-readable)
* ``<out>.hex``  — Q2.14 fixed-point, 4 hex digits per line
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import List, Tuple

_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import FS, N_FFT
from common.fixed_point import batch_float_to_q2_14
from common.formats import write_hex


# ---------------------------------------------------------------------------
# Signal generators
# ---------------------------------------------------------------------------
def gen_sinusoid(freq_hz: float,
                 n_samples: int,
                 fs: float = FS,
                 amplitude: float = 1.0,
                 phase: float = 0.0) -> List[float]:
    """Generate a pure sinusoid."""
    if n_samples < 0:
        raise ValueError(f"gen_sinusoid: n_samples must be >= 0 (got {n_samples})")
    two_pi = 2.0 * math.pi
    return [amplitude * math.sin(two_pi * freq_hz * n / fs + phase)
            for n in range(n_samples)]


def gen_bin_centered_sinusoid(bin_idx: int,
                              n_samples: int,
                              fs: float = FS,
                              n_fft: int = N_FFT) -> List[float]:
    """Generate a sinusoid at the center frequency of FFT bin ``bin_idx``.

    A unit-amplitude cosine is returned so the FFT bin is real-only.
    """
    if not 0 <= bin_idx < n_fft // 2:
        raise ValueError(
            f"gen_bin_centered_sinusoid: bin_idx must be in [0, {n_fft // 2}) "
            f"(got {bin_idx})"
        )
    f = bin_idx * fs / n_fft
    return gen_sinusoid(f, n_samples, fs=fs, amplitude=1.0, phase=0.0)


def gen_impulse(n_samples: int,
                delay: int = 0,
                amplitude: float = 1.0) -> List[float]:
    """Generate an impulse at sample ``delay`` (0-padded elsewhere)."""
    if n_samples < 0:
        raise ValueError(f"gen_impulse: n_samples must be >= 0 (got {n_samples})")
    if delay < 0:
        raise ValueError(f"gen_impulse: delay must be >= 0 (got {delay})")
    if delay >= n_samples:
        return [0.0] * n_samples
    out = [0.0] * n_samples
    out[delay] = amplitude
    return out


def gen_step(n_samples: int,
             delay: int = 0,
             amplitude: float = 1.0) -> List[float]:
    """Generate a step function that turns on at sample ``delay``."""
    if n_samples < 0:
        raise ValueError(f"gen_step: n_samples must be >= 0 (got {n_samples})")
    if delay < 0:
        raise ValueError(f"gen_step: delay must be >= 0 (got {delay})")
    if delay >= n_samples:
        return [0.0] * n_samples
    return [0.0] * delay + [amplitude] * (n_samples - delay)


def gen_white_noise(n_samples: int,
                    seed: int = 42,
                    amplitude: float = 1.0) -> List[float]:
    """Generate unit-variance white noise using NumPy's default RNG.

    Output values are drawn from ``N(0, 1)`` and scaled by
    ``amplitude``.  The seed is set before generation so successive
    calls with the same ``n_samples`` and ``seed`` produce identical
    output.
    """
    try:
        import numpy as np
    except ImportError as exc:                                # pragma: no cover
        raise ImportError(
            "gen_white_noise requires numpy. Install with: pip install numpy"
        ) from exc
    if n_samples < 0:
        raise ValueError(f"gen_white_noise: n_samples must be >= 0 (got {n_samples})")
    rng = np.random.default_rng(seed)
    return [amplitude * float(x) for x in rng.standard_normal(n_samples)]


def gen_chirp(f_start: float,
              f_stop: float,
              n_samples: int,
              fs: float = FS) -> List[float]:
    """Generate a linear-frequency chirp from ``f_start`` to ``f_stop``.

    The instantaneous phase at sample ``n`` is

    .. math::

        \\phi(n) = 2\\pi \\left[ f_{start}\\,\\frac{n}{f_s}
                                 + \\frac{(f_{stop} - f_{start})\\,n^2}
                                        {2\\,f_s\\,N} \\right]

    where ``N = n_samples - 1``.
    """
    if n_samples < 0:
        raise ValueError(f"gen_chirp: n_samples must be >= 0 (got {n_samples})")
    if f_start < 0 or f_stop < 0:
        raise ValueError(
            f"gen_chirp: f_start, f_stop must be >= 0 (got {f_start}, {f_stop})"
        )
    if n_samples < 2:
        return [0.0] * n_samples
    N = n_samples - 1
    two_pi = 2.0 * math.pi
    out: List[float] = []
    for n in range(n_samples):
        t = n / fs
        phase = two_pi * (f_start * t
                          + 0.5 * (f_stop - f_start) * t * n / N)
        out.append(math.sin(phase))
    return out


def gen_band_limited_noise(f_low: float,
                           f_high: float,
                           n_samples: int,
                           fs: float = FS,
                           seed: int = 42) -> List[float]:
    """Generate white noise band-limited to ``[f_low, f_high]`` via FFT.

    The algorithm is:

    1. Generate ``n_samples`` of unit-variance white noise.
    2. Compute the FFT.
    3. Zero every bin whose frequency lies outside ``[f_low, f_high]``
       (the negative-frequency bins are paired with the positive ones).
    4. Inverse FFT and normalise so the peak absolute value is 1.0.
    """
    if n_samples < 0:
        raise ValueError(
            f"gen_band_limited_noise: n_samples must be >= 0 (got {n_samples})"
        )
    if f_low < 0 or f_high <= f_low:
        raise ValueError(
            f"gen_band_limited_noise: need 0 <= f_low < f_high "
            f"(got {f_low}, {f_high})"
        )
    if f_high >= fs / 2.0:
        raise ValueError(
            f"gen_band_limited_noise: f_high must be < fs/2 "
            f"(got f_high={f_high}, fs/2={fs / 2.0})"
        )
    if n_samples == 0:
        return []
    if n_samples == 1:
        return [0.0]

    try:
        import numpy as np
    except ImportError as exc:                                # pragma: no cover
        raise ImportError(
            "gen_band_limited_noise requires numpy. "
            "Install with: pip install numpy"
        ) from exc

    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(n_samples)
    spec = np.fft.fft(noise)
    freqs = np.fft.fftfreq(n_samples, d=1.0 / fs)

    mask = np.zeros_like(spec)
    for i, f in enumerate(freqs):
        af = abs(f)
        if f_low <= af <= f_high:
            mask[i] = 1.0
    filtered = np.fft.ifft(spec * mask).real

    peak = float(np.max(np.abs(filtered))) if filtered.size else 0.0
    if peak > 0.0:
        filtered = filtered / peak
    return [float(x) for x in filtered]


def gen_silence(n_samples: int) -> List[float]:
    """Return ``n_samples`` of zeros."""
    if n_samples < 0:
        raise ValueError(f"gen_silence: n_samples must be >= 0 (got {n_samples})")
    return [0.0] * n_samples


def gen_square_wave(freq_hz: float,
                    n_samples: int,
                    fs: float = FS,
                    amplitude: float = 1.0) -> List[float]:
    """Generate a 50% duty-cycle square wave of the given frequency."""
    if n_samples < 0:
        raise ValueError(
            f"gen_square_wave: n_samples must be >= 0 (got {n_samples})"
        )
    if freq_hz <= 0:
        raise ValueError(f"gen_square_wave: freq_hz must be > 0 (got {freq_hz})")
    period = fs / freq_hz
    out: List[float] = []
    for n in range(n_samples):
        phase = (n % period) / period        # 0..1
        out.append(amplitude if phase < 0.5 else -amplitude)
    return out


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
def _write_float(path: Path, sig: List[float], header: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        if header:
            for line in header.splitlines() or [""]:
                f.write(f"# {line}\n" if line else "#\n")
        for v in sig:
            f.write(f"{v:.9g}\n")


def _write_q14(path: Path, sig: List[float], header: str = "") -> None:
    q = batch_float_to_q2_14(sig)
    write_hex(q, path, header=header)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def _parse_params(params: List[str]) -> dict:
    """Parse ``--params key=value`` pairs from the command line."""
    out: dict = {}
    for kv in params or []:
        if "=" not in kv:
            raise SystemExit(f"bad --params entry (expected key=value): {kv}")
        k, v = kv.split("=", 1)
        try:
            out[k] = float(v)
        except ValueError:
            out[k] = v
    return out


def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Generate reproducible test signals.")
    p.add_argument("--type",
                   choices=("sinusoid", "bin_sin", "impulse", "step",
                            "noise", "chirp", "band_noise", "silence",
                            "square"),
                   required=True)
    p.add_argument("--n-samples", type=int, default=2048,
                   help="Number of samples (default: %(default)s)")
    p.add_argument("--fs", type=float, default=FS)
    p.add_argument("--params", nargs="*", default=[],
                   help="Signal parameters, e.g. freq_hz=1000 amplitude=0.5")
    p.add_argument("--out", type=Path, default=Path("test_signal"),
                   help="Output prefix (.txt + .hex are written).")
    args = p.parse_args(argv)
    params = _parse_params(args.params)

    def _f(name: str, default: float) -> float:
        v = params.get(name, default)
        try:
            return float(v)
        except (TypeError, ValueError):
            raise SystemExit(f"bad numeric value for {name}: {v}")

    def _i(name: str, default: int) -> int:
        v = params.get(name, default)
        try:
            return int(v)
        except (TypeError, ValueError):
            raise SystemExit(f"bad integer value for {name}: {v}")

    # Dispatch.
    if args.type == "sinusoid":
        sig = gen_sinusoid(_f("freq_hz", 1000.0), args.n_samples,
                           fs=args.fs,
                           amplitude=_f("amplitude", 1.0),
                           phase=_f("phase", 0.0))
        label = (f"sinusoid freq={params.get('freq_hz', 1000.0)}Hz "
                 f"amp={params.get('amplitude', 1.0)} N={args.n_samples}")
    elif args.type == "bin_sin":
        sig = gen_bin_centered_sinusoid(_i("bin_idx", 8), args.n_samples,
                                        fs=args.fs, n_fft=N_FFT)
        label = f"bin-centered sinusoid bin={params.get('bin_idx', 8)} N={args.n_samples}"
    elif args.type == "impulse":
        sig = gen_impulse(args.n_samples, delay=_i("delay", 0),
                          amplitude=_f("amplitude", 1.0))
        label = f"impulse delay={params.get('delay', 0)} N={args.n_samples}"
    elif args.type == "step":
        sig = gen_step(args.n_samples, delay=_i("delay", 0),
                       amplitude=_f("amplitude", 1.0))
        label = f"step delay={params.get('delay', 0)} N={args.n_samples}"
    elif args.type == "noise":
        sig = gen_white_noise(args.n_samples, seed=_i("seed", 42),
                              amplitude=_f("amplitude", 1.0))
        label = f"white noise seed={params.get('seed', 42)} N={args.n_samples}"
    elif args.type == "chirp":
        sig = gen_chirp(_f("f_start", 100.0), _f("f_stop", 10000.0),
                        args.n_samples, fs=args.fs)
        label = (f"chirp {params.get('f_start', 100.0)}->"
                 f"{params.get('f_stop', 10000.0)} Hz N={args.n_samples}")
    elif args.type == "band_noise":
        sig = gen_band_limited_noise(_f("f_low", 300.0),
                                     _f("f_high", 3400.0),
                                     args.n_samples, fs=args.fs,
                                     seed=_i("seed", 42))
        label = (f"band-limited noise {params.get('f_low', 300.0)}-"
                 f"{params.get('f_high', 3400.0)} Hz N={args.n_samples}")
    elif args.type == "silence":
        sig = gen_silence(args.n_samples)
        label = f"silence N={args.n_samples}"
    elif args.type == "square":
        sig = gen_square_wave(_f("freq_hz", 1000.0), args.n_samples,
                              fs=args.fs, amplitude=_f("amplitude", 1.0))
        label = f"square wave freq={params.get('freq_hz', 1000.0)}Hz N={args.n_samples}"
    else:                                                  # pragma: no cover
        raise SystemExit(f"unknown type: {args.type}")

    txt_path = Path(str(args.out) + ".txt")
    hex_path = Path(str(args.out) + ".hex")
    _write_float(txt_path, sig, header=label)
    _write_q14(hex_path, sig, header=f"{label} (Q2.14)")
    print(f"Generated {args.type} ({label})")
    print(f"  {txt_path}  ({txt_path.stat().st_size} bytes)")
    print(f"  {hex_path}  ({hex_path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
