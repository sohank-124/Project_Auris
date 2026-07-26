"""
Project Auris — Frequency response generators.

Submodules
----------
gen_band_centers
    ANSI S1.11 octave / fractional-octave band center generators.
gen_filter_coeffs
    IIR Butterworth and windowed-sinc FIR filter design with
    fixed-point quantisation.
gen_smoothing
    Fractional-octave, moving-average, and Gaussian smoothing kernels
    for gain-table post-processing.
validate_response
    Flatness, ripple, and group-delay measurements plus gain-response
    validation against a reference curve.
"""

__all__ = [
    "gen_band_centers",
    "gen_filter_coeffs",
    "gen_smoothing",
    "validate_response",
]
