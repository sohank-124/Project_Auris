"""
Project Auris — FFT configuration and twiddle-table generators.

Submodules
----------
gen_fft
    Reference DFT/IDFT, FFT configuration dataclass, and Vivado TCL
    emitter for the Xilinx xfft IP core.
gen_twiddle
    Twiddle-factor table generator in Q2.14 (cos / sin).
validate_fft
    Parseval, linearity, known-signal, and bin-mapping checks for
    arbitrary FFT implementations.
"""

from .gen_fft import (
    FFTConfig,
    reference_dft,
    reference_idft,
    generate_fft_config,
    generate_vivado_tcl,
)
from .gen_twiddle import (
    generate_twiddle_table,
    generate_twiddle_file,
    twiddle_to_complex,
)
from .validate_fft import (
    check_parseval,
    check_linearity,
    check_known_signal,
    check_bin_frequency_mapping,
    validate_all,
)

__all__ = [
    "FFTConfig", "reference_dft", "reference_idft",
    "generate_fft_config", "generate_vivado_tcl",
    "generate_twiddle_table", "generate_twiddle_file", "twiddle_to_complex",
    "check_parseval", "check_linearity", "check_known_signal",
    "check_bin_frequency_mapping", "validate_all",
]
