# Changelog

All notable changes to Project Auris will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial repository skeleton with the canonical five-directory layout:
  `fpga/`, `firmware/`, `tools/`, `hardware/`, and `docs/`.
- Top-level `Makefile` orchestrating `tools`, `fpga`, `fpga-sim`,
  `fpga-clean`, `esp`, `esp-flash`, `esp-monitor`, `all`, and `clean`
  targets.
- MIT `LICENSE` file, scoped to "Project Auris Contributors" for 2026.
- Documentation scaffold with one `README.md` per major subtree
  (`docs/architecture/`, `docs/hardware/`, `docs/phase_reports/`,
  `docs/college_app/`) and a top-level `docs/IMPLEMENTATION_PLAN.md`
  serving as the single source of truth.
- SystemVerilog skeleton RTL on the FPGA side: `top.sv`, the global
  `auris_pkg.sv` types and register map, I2S RX and TX, SPI slave,
  register file, mode controller, status monitor, clock generator
  wrapper, CDC FIFOs and synchronizers, the DSP pipeline top, input
  and output ping-pong BRAM buffers, window apply and Hann window ROM,
  FFT-256 and IFFT-256 wrappers, 50% overlap-add, and the spectral
  processor with per-bin gain and gating.
- FPGA support infrastructure: `cmod_s7_25.xdc` pin map and timing
  constraints, Vivado non-project build script, two xsim testbench
  runner scripts, and testbench skeletons for the I2S RX and SPI slave
  modules.
- ESP-IDF C firmware skeleton: `main.c` entry point with the FreeRTOS
  task scheduler, plus components for `spi_master`, `fpga_config`,
  `mode_manager`, `button_handler`, `audio_driver` (I2S master, BCLK
  3.072 MHz), `led_indicator`, `volume_ctrl`, and `profile_store` (NVS
  persistence). Stubs left in place for the Phase 3+ `telemetry`,
  `battery_mon`, and `bt_audio` components.
- ESP-IDF support files: top-level `CMakeLists.txt`, `sdkconfig.defaults`,
  and `partitions.csv` reserving an NVS partition.
- Python tooling: a working `tools/win_gen/gen_hann_coeffs.py` that
  emits the 256-point Hann window as a Q2.14 `.hex` file (and matching
  `.coe` and human-readable `.txt`), a skeleton
  `tools/profile_gen/gen_gain_profile.py` for audiogram-to-128-bin
  gain tables, and a skeleton `tools/profile_gen/gen_default_tables.py`
  for the General / Hearing / Speech defaults.
- Pre-generated window and gain-table artefacts under
  `fpga/generated/` so the build is reproducible from a fresh clone
  even before the Python toolchain has been installed.
- Repository meta files at the root: `README.md`, `CONTRIBUTING.md`
  (with the full DCO v1.1 text and sign-off instructions), `CHANGELOG.md`,
  `CODEOWNERS`, `CITATION.cff`, and `.gitattributes` with explicit text
  and binary classifications for every file type the project produces.

### Changed
- Replaced the placeholder `README.md` with a full project front door
  including badge row, Mermaid architecture diagram, prerequisites, build
  and flash instructions, repository structure table, documentation
  table, and a phase status table aligned with the implementation plan.

### Notes
- This release contains skeleton code only. No bitstream has been
  generated, no firmware has been flashed, and no audio has been
  processed yet. See the "Project Status" table in `README.md` for
  per-phase progress.

## [0.1.0] - 2026-07-01

### Added
- Reserved initial release tag. Identical contents to `[Unreleased]`
  above; created so that downstream consumers can pin to a specific
  commit family. The first release with runnable bitstream and
  firmware will be `0.2.0` after Phase 0 of the implementation plan
  closes.
