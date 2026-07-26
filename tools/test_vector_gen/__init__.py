"""
Project Auris — Test-vector generators.

Submodules
----------
gen_test_signals
    Reproducible test-signal generators (sinusoids, impulses, noise,
    chirps, square waves, silence) with both float and Q2.14 outputs.
gen_impulse_response
    Synthetic impulse responses (identity, delay, lowpass) for FIR /
    convolution regression tests.
gen_audiogram_tests
    Pre-defined audiograms and the expected NAL-R / NAL-NL2 / DSL-v5
    gain tables that the system should produce.
gen_latency_test
    Single-shot impulse, chirp, and multi-marker latency stimuli.
"""

__all__ = [
    "gen_test_signals",
    "gen_impulse_response",
    "gen_audiogram_tests",
    "gen_latency_test",
]
