"""
Project Auris — Latency analysis utilities.

Submodules
----------
compute_latency
    Static latency budget calculator from the DSP pipeline
    parameters.
measure_roundtrip
    FFT-based cross-correlation and sub-sample peak interpolation
    for measuring end-to-end round-trip latency on a recorded
    input / output pair.
report_latency
    Human-readable report generation (JSON / HTML / plain text) and
    pass / fail check against the system target.
"""

__all__ = [
    "compute_latency",
    "measure_roundtrip",
    "report_latency",
]
