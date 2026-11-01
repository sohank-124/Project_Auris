# Analysis tools and coefficient exports

Python helpers support coefficient inspection, signal generation, fixed-point conversion, and numerical/latency
analysis. They are not a runtime FPGA host. Python 3.10+ is the documented baseline; NumPy is required where imported,
SciPy is optional for selected filter design functions. No pinned complete Python environment is claimed.

## Hardware versus analysis assets

- `win_gen/gen_hann_coeffs.py` exports the periodic 256-point Hann by default, normalization none, all formats, prefix
  `fpga/generated/hann_256` anchored to the repository. Active window_rom computes its coefficients internally.
- `profile_gen/gen_default_tables.py` exports the exact embedded mode_ctrl words, in order General/Speech/Music/Hearing,
  to repository-relative `fpga/generated/`. Curve-generation helpers are experimental, not the default hardware tables.
- Explicit relative output overrides are relative to the caller's working directory. Editing exports does not change
  active RTL or the bitstream.
- `profile_gen/gen_gain_profile.py`, fitting, WDRC, filter and smoothing helpers are offline analysis. Their presence
  does not mean those algorithms are instantiated in the current FPGA pipeline.
- `fft_gen/` and `validation/` provide numerical helpers. They do not implement the vendor FFT hardware or certify the
  full chain merely by running a Python model.
- `test_vector_gen/` produces analysis stimuli; see each HDL bench for the stimulus it actually consumes.
- `latency_analysis/compute_latency.py` and `report_latency.py` produce conditional estimates from supplied
  cycle/queue/codec inputs. `measure_roundtrip.py` analyzes supplied recordings, not live hardware acquisition.

[Recorded coefficient equivalence](../docs/verification/evidence/export-equivalence/README.md) checks actual ROM output
and all embedded profile words. Generated exports belong in the ignored `fpga/generated/` directory; selected analysis
results belong under [research](../docs/research/README.md) or
[verification](../docs/verification/VERIFICATION_STATUS.md) with source identity and limitations.

## Commands

Inspection exports (write generated files; not required for FPGA coefficient initialization):

```sh
python tools/win_gen/gen_hann_coeffs.py
python tools/profile_gen/gen_default_tables.py
```

These commands have recorded F30 execution evidence. CLI help and lightweight checks run during cleanup are listed in
[cleanup validation](../docs/verification/CLEANUP_VALIDATION.md). See [build/test
guidance](../docs/verification/REPRODUCING.md) for the maintained HDL entries and Python/Tcl runner contract test.
