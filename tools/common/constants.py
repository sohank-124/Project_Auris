"""
Project Auris — Physical and system constants.

All numeric parameters that govern the system behaviour (sample rate,
FFT size, fixed-point format, audiogram frequencies, gain table depth,
WDRC parameters, latency budget, and validation tolerances) live here.

Generators should import from this module rather than redefining values
inline, so the source of truth is centralised and a single change
propagates to all consumers.
"""

# -- Audio / DSP frame -------------------------------------------------------
# 48 kHz / 256-point FFT / 50% overlap => 128-sample frames (~2.67 ms)
FS: int = 48000                # Sample rate in Hz
N_FFT: int = 256               # FFT length
N_BINS: int = 128              # Number of unique positive-frequency bins
BIN_WIDTH: float = 187.5       # FS / N_FFT  (Hz per bin)
FRAME_ADVANCE: int = 128       # Samples per frame (50% overlap with N_FFT)
FRAME_TIME_MS: float = 2.6667  # 1000 * FRAME_ADVANCE / FS  (ms)

# -- Q2.14 fixed-point --------------------------------------------------------
# Range: [-2.0, +1.99994]  with 14 fractional bits, 2 integer bits
# (including sign). One LSB = 1 / 2^14 ~= 6.1035e-5
Q_FRAC: int = 14               # Fractional bits
Q_SCALE: int = 1 << Q_FRAC     # 16384
Q_MIN: int = -32768            # -2^15
Q_MAX: int = 32767             # 2^15 - 1

# -- Audiogram ----------------------------------------------------------------
# Standard audiometric frequencies (Hz) per ANSI S3.21 / ISO 8253-1.
AUDIOGRAM_FREQS: tuple = (250, 500, 1000, 2000, 3000, 4000, 6000)
N_AUDIOGRAM_BANDS: int = len(AUDIOGRAM_FREQS)  # 7

# -- Gain table ---------------------------------------------------------------
# Q2.14 cannot represent gains >= 2.0, so gain values in dB are stored
# as (mantissa, shift) where mantissa is unsigned Q0.14 in [0, 16384]
# and shift is a power-of-2 exponent (0..15). This gives an effective
# range of [0, ~131072 x].
GAIN_DB_MIN: float = -24.0     # Lower bound of insertion gain
GAIN_DB_MAX: float = 24.0      # Upper bound of insertion gain
GAIN_TABLE_DEPTH: int = 128    # Number of bins in the gain table

# -- WDRC (Wide Dynamic Range Compression) -----------------------------------
WDRC_CHANNELS: int = 16
WDRC_LOW_KNEE_DB: float = 25.0
WDRC_HIGH_KNEE_DB: float = 65.0
WDRC_LIMIT_DB: float = 85.0
WDRC_CR_EXPANSION: float = 1.5
WDRC_CR_COMPRESSION: float = 2.0
WDRC_CR_LIMITER: float = 8.0
WDRC_ATTACK_MS: float = 5.0
WDRC_RELEASE_MS: float = 100.0

# -- Operating modes ----------------------------------------------------------
MODES: tuple = ("general", "hearing", "speech", "bypass")

# -- Latency ------------------------------------------------------------------
# The DSP pipeline (window -> FFT -> gain -> IFFT -> OLA) must fit inside
# the round-trip audio latency budget.
LATENCY_TARGET_MS: float = 10.0
LATENCY_BUDGET_MS: float = 10.0

# -- Validation tolerances ----------------------------------------------------
# Tolerances are expressed in LSBs of the relevant fixed-point format unless
# otherwise noted.
TOL_COEFF_LSB: float = 0.5       # Coefficient (window, twiddle) tolerance
TOL_FFT_LSB: float = 2.0         # FFT bin tolerance
TOL_GAIN_LSB: float = 5.0        # Gain table tolerance
TOL_DB: float = 0.1              # Generic dB tolerance
TOL_PARSEVAL_DB: float = 0.5     # Parseval / energy conservation tolerance
