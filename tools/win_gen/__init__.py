"""
Project Auris — Window-coefficient generators.

Submodules
----------
gen_hann_coeffs
    Hann window generation with periodic/symmetric variants, multiple
    normalisation modes, and metric reporting.
validate_window
    COLA, symmetry, DC-response, and energy-conservation sanity checks
    for any window function.
"""

from .gen_hann_coeffs import (
    generate_hann,
    normalize_window,
    compute_window_metrics,
)

from .validate_window import (
    check_cola,
    check_symmetry,
    check_dc_response,
    check_energy,
    validate_all,
)

__all__ = [
    "generate_hann", "normalize_window", "compute_window_metrics",
    "check_cola", "check_symmetry", "check_dc_response",
    "check_energy", "validate_all",
]
