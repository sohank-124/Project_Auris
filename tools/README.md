# Project Auris — `tools/` Subtree

This directory contains the **code-generation and validation toolchain**
for Project Auris, an open-source hearing-aid DSP platform.  All
artifacts produced here are consumed by the FPGA / firmware build:

* **Coefficient ROMs** (window, twiddle, gain tables) — emitted as
  ``$readmemh``-compatible ``.hex`` plus companion ``.coe`` /
  ``.txt`` / ``.m`` files.
* **Test vectors** (impulse responses, audiogram regressions,
  latency stimuli) — used by the simulation testbench to verify
  the RTL block-by-block.
* **Latency and validation reports** — used by the audio team to
  sign off each release.

The toolchain depends only on the Python 3.10+ standard library and
NumPy.  One module (``freq_resp_gen.gen_filter_coeffs``) optionally
uses SciPy for IIR filter design; if SciPy is missing that one
function is unavailable and the rest of the toolchain is unaffected.

---

## Module layout

```
tools/
├── __init__.py              # package marker
├── README.md                # this file
├── common/                  # shared constants, fixed-point, audiogram
│   ├── constants.py
│   ├── fixed_point.py
│   ├── audiogram.py
│   └── formats.py
├── win_gen/                 # window-coefficient generators
│   └── gen_hann_coeffs.py
├── profile_gen/             # audiogram → gain table, default tables
│   ├── gen_gain_profile.py
│   └── gen_default_tables.py
├── fft_gen/                 # FFT core wrapper
│   └── gen_fft.py
├── bitstream_utils/         # FPGA bitstream manipulation
├── freq_resp_gen/           # frequency-response utilities
│   ├── gen_band_centers.py
│   ├── gen_filter_coeffs.py
│   ├── gen_smoothing.py
│   └── validate_response.py
├── test_vector_gen/         # test-vector generators
│   ├── gen_test_signals.py
│   ├── gen_impulse_response.py
│   ├── gen_audiogram_tests.py
│   └── gen_latency_test.py
├── latency_analysis/        # latency budget + measurement + reports
│   ├── compute_latency.py
│   ├── measure_roundtrip.py
│   └── report_latency.py
├── validation/              # cross-stage sanity checks
│   ├── check_parseval.py
│   ├── check_cola.py
│   ├── check_gain_table.py
│   └── compare_bitstream.py
└── config/                  # hand-written YAML configuration
    ├── default_params.yaml
    └── test_vectors.yaml
```

---

## Subpackage overview

### `common/`
Shared building blocks used by every generator:

* `constants.py` — sample rate, FFT size, Q2.14 limits, WDRC
  parameters, validation tolerances.
* `fixed_point.py` — `float_to_q2_14`, `q2_14_to_float`,
  `db_to_q0_14`, plus batched wrappers.
* `audiogram.py` — `Audiogram` dataclass, frequency / bin mapping,
  log-frequency interpolation.
* `formats.py` — `write_hex`, `write_coe`, `write_mif`,
  `write_readmemb`, `write_txt_table`, `write_json`, `write_all`.

### `win_gen/`
Window coefficient generators.  `gen_hann_coeffs.py` produces
periodic / symmetric Hann windows in float, Q2.14, COE, and `$readmemb`
binary forms, with metrics (coherent gain, ENBW, scalloping loss,
peak sidelobe level).

### `profile_gen/`
Audiogram-to-gain-table conversion (`gen_gain_profile.py`) and the
three default mode tables — General, Hearing, Speech
(`gen_default_tables.py`).

### `fft_gen/`
Wrapper around the dblclockfft 256-point FFT core.

### `bitstream_utils/`
FPGA bitstream manipulation (load, verify, CRC).

### `freq_resp_gen/` (Phase 5)
Frequency-response utilities:

* `gen_band_centers.py` — ANSI S1.11 octave / fractional-octave
  band center generators.
* `gen_filter_coeffs.py` — IIR Butterworth and windowed-sinc FIR
  bandpass coefficient generators.
* `gen_smoothing.py` — fractional-octave, moving-average, and
  Gaussian smoothing kernels.
* `validate_response.py` — flatness, ripple, group-delay, and
  gain-response validation.

### `test_vector_gen/` (Phase 6)
Test-vector generators:

* `gen_test_signals.py` — sinusoids (including bin-centered), impulse,
  step, white / band-limited noise, chirp, square wave, silence.
* `gen_impulse_response.py` — identity, delay, lowpass IRs and a
  canonical regression suite.
* `gen_audiogram_tests.py` — eight reference audiograms and the
  expected gain tables for each.
* `gen_latency_test.py` — impulse / chirp / multi-marker latency
  stimuli.

### `latency_analysis/` (Phase 7)
Latency budget and measurement:

* `compute_latency.py` — static latency budget calculator with
  per-stage breakdown.
* `measure_roundtrip.py` — FFT-based cross-correlation with
  parabolic sub-sample peak interpolation.
* `report_latency.py` — JSON / HTML / text report generator and
  pass / fail check.

### `validation/` (Phase 8)
Cross-stage sanity checks:

* `check_parseval.py` — Parseval's theorem in float and Q2.14.
* `check_cola.py` — Constant Overlap-Add verification.
* `check_gain_table.py` — range / smoothness / DC-unity /
  monotonicity / audiogram-shape checks.
* `compare_bitstream.py` — hex / float file comparator and
  directory-level regression driver.

### `config/`
Hand-written YAML configuration and regression baselines.  No
external YAML library is required to parse them.

---

## Usage

Every generator is a self-contained Python script with an
`if __name__ == "__main__":` block and a small argparse CLI.
From the project root:

```bash
# Window coefficients
python tools/win_gen/gen_hann_coeffs.py --N 256 --norm cola --out-prefix hann_256

# Gain table for a specific audiogram
python tools/profile_gen/gen_gain_profile.py \
    --audiogram 0,0,10,25,35,40,45 --out-prefix gain_test

# Frequency-response utilities
python tools/freq_resp_gen/gen_band_centers.py --fraction 3 --out bands.csv
python tools/freq_resp_gen/gen_filter_coeffs.py \
    --type fir --f-low 300 --f-high 3400 --taps 64 --out speech_bp

# Test vectors
python tools/test_vector_gen/gen_test_signals.py \
    --type sinusoid --params freq_hz=1000 amplitude=0.5 \
    --n-samples 4096 --out test_1khz
python tools/test_vector_gen/gen_impulse_response.py --out-dir ir_tests

# Latency analysis
python tools/latency_analysis/compute_latency.py
python tools/latency_analysis/report_latency.py \
    --format html --out latency_report.html

# Validation
python tools/validation/check_parseval.py \
    --input-file signal.txt --fft-file fft.txt
python tools/validation/compare_bitstream.py \
    --reference-dir fpga/generated --test-dir fpga/generated_new
```

All scripts accept `--help` for the full argument list.

---

## Conventions

* All Python modules are typed-hinted and Python 3.10+ compatible.
* The `tools/` directory is the package root; relative imports are
  used throughout (e.g. `from common.constants import FS, N_FFT`).
* Every numeric constant in `common/constants.py` is the single
  source of truth — generators import rather than redefine.
* All output is written in portable text formats; no platform-
  specific binary blobs.
