"""
Project Auris — Common DSP utilities.

Shared constants, fixed-point helpers, audiogram data structures, and
file-format writers used across the generator scripts in
``tools/``.

Submodules
----------
constants
    Physical system parameters, fixed-point configuration, and validation
    tolerances used throughout the toolchain.
fixed_point
    Q2.14 / Q0.14 fixed-point conversions and dB <-> linear helpers.
audiogram
    Audiogram dataclass and frequency / bin mapping helpers.
formats
    Output writers for hex, COE, MIF, $readmemb, JSON, and text tables.
"""

from .constants import (
    FS,
    N_FFT,
    N_BINS,
    BIN_WIDTH,
    FRAME_ADVANCE,
    FRAME_TIME_MS,
    Q_FRAC,
    Q_SCALE,
    Q_MIN,
    Q_MAX,
    AUDIOGRAM_FREQS,
    N_AUDIOGRAM_BANDS,
    GAIN_DB_MIN,
    GAIN_DB_MAX,
    GAIN_TABLE_DEPTH,
    WDRC_CHANNELS,
    WDRC_LOW_KNEE_DB,
    WDRC_HIGH_KNEE_DB,
    WDRC_LIMIT_DB,
    WDRC_CR_EXPANSION,
    WDRC_CR_COMPRESSION,
    WDRC_CR_LIMITER,
    WDRC_ATTACK_MS,
    WDRC_RELEASE_MS,
    MODES,
    LATENCY_TARGET_MS,
    LATENCY_BUDGET_MS,
    TOL_COEFF_LSB,
    TOL_FFT_LSB,
    TOL_GAIN_LSB,
    TOL_DB,
    TOL_PARSEVAL_DB,
)

from .fixed_point import (
    float_to_q2_14,
    q2_14_to_float,
    db_to_linear,
    linear_to_db,
    db_to_q0_14,
    saturate,
    batch_float_to_q2_14,
    batch_q2_14_to_float,
)

from .audiogram import (
    Audiogram,
    freq_to_bin,
    bin_to_freq,
    log_freq_interpolate,
)

from .formats import (
    write_hex,
    write_coe,
    write_mif,
    write_readmemb,
    write_txt_table,
    write_json,
    write_all,
)

__all__ = [
    # constants
    "FS", "N_FFT", "N_BINS", "BIN_WIDTH", "FRAME_ADVANCE", "FRAME_TIME_MS",
    "Q_FRAC", "Q_SCALE", "Q_MIN", "Q_MAX",
    "AUDIOGRAM_FREQS", "N_AUDIOGRAM_BANDS",
    "GAIN_DB_MIN", "GAIN_DB_MAX", "GAIN_TABLE_DEPTH",
    "WDRC_CHANNELS", "WDRC_LOW_KNEE_DB", "WDRC_HIGH_KNEE_DB", "WDRC_LIMIT_DB",
    "WDRC_CR_EXPANSION", "WDRC_CR_COMPRESSION", "WDRC_CR_LIMITER",
    "WDRC_ATTACK_MS", "WDRC_RELEASE_MS",
    "MODES", "LATENCY_TARGET_MS", "LATENCY_BUDGET_MS",
    "TOL_COEFF_LSB", "TOL_FFT_LSB", "TOL_GAIN_LSB", "TOL_DB", "TOL_PARSEVAL_DB",
    # fixed_point
    "float_to_q2_14", "q2_14_to_float", "db_to_linear", "linear_to_db",
    "db_to_q0_14", "saturate",
    "batch_float_to_q2_14", "batch_q2_14_to_float",
    # audiogram
    "Audiogram", "freq_to_bin", "bin_to_freq", "log_freq_interpolate",
    # formats
    "write_hex", "write_coe", "write_mif", "write_readmemb",
    "write_txt_table", "write_json", "write_all",
]
