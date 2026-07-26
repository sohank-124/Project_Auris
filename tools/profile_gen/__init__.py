"""
Project Auris — Gain profile and mode-table generators.

Submodules
----------
fitting_formulas
    Prescriptive fitting rules (NAL-R, NAL-NL2, DSL v5).
gen_gain_profile
    Audiogram -> per-bin gain table converter.
gen_default_tables
    Default gain tables for the four operating modes
    (general, hearing, speech, bypass).
gen_wdrc_tables
    Wide-Dynamic-Range-Compression channel I/O curves and envelope
    coefficients.
gen_noise_gate
    Per-channel open/close thresholds and gate envelope coefficients.
"""

from .fitting_formulas import (
    nal_r,
    nal_nl2,
    dsl_v5,
    compute,
)
from .gen_gain_profile import (
    audiogram_to_gain_table,
    gain_table_to_fixed,
)
from .gen_default_tables import (
    generate_general_mode,
    generate_hearing_mode,
    generate_speech_mode,
    generate_bypass_mode,
    generate_all_modes,
)
from .gen_wdrc_tables import (
    WDRCChannel,
    compute_channel_bands,
    compute_io_curve,
    compute_envelope_coeffs,
    generate_wdrc_tables,
)
from .gen_noise_gate import (
    compute_noise_gate_table,
    compute_gate_coefficients,
)

__all__ = [
    "nal_r", "nal_nl2", "dsl_v5", "compute",
    "audiogram_to_gain_table", "gain_table_to_fixed",
    "generate_general_mode", "generate_hearing_mode",
    "generate_speech_mode", "generate_bypass_mode", "generate_all_modes",
    "WDRCChannel", "compute_channel_bands", "compute_io_curve",
    "compute_envelope_coeffs", "generate_wdrc_tables",
    "compute_noise_gate_table", "compute_gate_coefficients",
]
