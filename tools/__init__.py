"""
Project Auris — Code-generation and validation toolchain.

The ``tools/`` subtree produces the bitstream initialisation data
(window / twiddle / gain tables), test vectors, latency budgets, and
cross-stage validation reports that the FPGA / firmware build
consumes.  Every module is self-contained and has a small argparse
CLI; see ``tools/README.md`` for the full module listing and usage.

Subpackages
-----------
common
    Shared constants, fixed-point helpers, audiogram data structures,
    and file-format writers.
win_gen
    Window-coefficient generators (Hann, Hamming, Blackman, ...).
profile_gen
    Audiogram-to-gain-table, default-mode tables, WDRC tables, and
    noise-gate tables.
fft_gen
    FFT configuration and twiddle-table generators.
bitstream_utils
    FPGA bitstream manipulation (FPGA configuration, CRC, ...).
freq_resp_gen
    Frequency-response utilities (band centers, IIR / FIR filter
    design, smoothing kernels, response validation).
test_vector_gen
    Test-vector generators (signals, impulse responses, audiogram
    regressions, latency stimuli).
latency_analysis
    Static latency budget, FFT-based round-trip measurement, and
    report generation.
validation
    Cross-stage sanity checks (Parseval, COLA, gain-table shape,
    hex / float bitstream comparator).
config
    Hand-written YAML configuration and regression baselines.
"""

__all__ = [
    "common",
    "win_gen",
    "profile_gen",
    "fft_gen",
    "bitstream_utils",
    "freq_resp_gen",
    "test_vector_gen",
    "latency_analysis",
    "validation",
    "config",
]
