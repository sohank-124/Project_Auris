# Changelog

All notable changes to Project Auris will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **FPGA-only architecture** (`ADR-009` in `docs/DESIGN_DECISIONS.md`). The FPGA is now the sole signal- processing,
  control, and I/O-master entity. There is no external microcontroller, no host processor, and no firmware to flash.
- **`btn_debounce.sv`** (under `fpga/rtl/io/`). 20 ms debounce for the four active-low onboard push buttons, with press
  and release edge pulse outputs.
- **`volume_ctrl.sv`** (under `fpga/rtl/dsp/`). Q2.14 multiply of audio samples by the 5-bit volume level; sat24 at the
  output; mute at level 0. Wired into `dsp_pipeline.sv` between overlap-add and output buffer.
- **Inline FSMs in `top.sv`**: a 2-bit mode counter (wraps on BTN0/BTN1) and a 5-bit volume counter (saturates on
  BTN2/BTN3). Mode and volume changes are entirely internal to `CD_DSP`.
- **`clk_gen.sv` enhancement.** Previously a stub for the MMCM only. Now also generates the fractional divide-by-31.25
  BCLK (3.072 MHz) and the ÷64 LRCLK (48 kHz). The FPGA is the I²S clock master for both the INMP441 and the PCM5102A.
- **Pre-computed per-mode gain tables** in `mode_ctrl.sv`. Four 128-entry Q2.14 tables (General, Speech, Music, Hearing)
  shipped as constant data inside the RTL. Each mode change loads the new table into the inactive bank of
  `spectral_proc`'s dual-port BRAM and atomically commits the swap (no audible click).
- **`docs/fpga_only_architecture.md`** — single-pane-of-glass overview of the current FPGA-only architecture.

### Changed

- **`top.sv`** rewritten as an FPGA-only top-level: no SPI host interface, no register file, no SPI↔DSP CDC. RGB LED
  decoder and LRCLK 2-FF synchroniser are inline in `top.sv`.
- **`dsp_pipeline.sv`** now consumes the 5-bit `volume_i` input from `top.sv` and routes it through `volume_ctrl.sv`.
  Bypass mode (`dsp_enable_i = 0`) defaults to active (tied to 1 inside `top.sv`); bypass is exercised at bring-up via
  direct manipulation of the wire.
- **`mode_ctrl.sv`** now ships with four pre-computed per-mode gain tables. The `default_*_o` outputs are unused in the
  FPGA-only build (tied to hardcoded defaults in `top.sv`).
- **`fpga/constraints/arty_s7_25.xdc`**. BCLK and LRCLK are now FPGA _outputs_ (FPGA is the I2S master). BTN2 takes over
  F13 (formerly LED[1] on the Digilent master XDC); the clip indicator moves from LED[1] to LED[2] (G15). Header
  comments were not updated in this sweep (the XDC is out of scope for the documentation pass).
- **`docs/hardware/WIRING.md`** — full rewrite for the FPGA-only build. Removed the ESP32 pin assignment reference,
  ESP-IDF steps, and ESP32 brownout troubleshooting.
- **`docs/hardware/README.md`** — full rewrite: pin map matches the canonical XDC; ESP32 entries removed.
- **`tools/README.md`** — full rewrite: removes `bitstream_utils/` reference (no such directory exists in `tools/`),
  removes the `dblclockfft` claim (the design uses Xilinx xfft v9.1), removes ESP-IDF / FreeRTOS references.
- **`hardware/schematics/README.md`** — full rewrite for the FPGA-only build.
- **`docs/hardware/BOM.md`** — ESP32 line item removed; total recalculated to ~$106.60.
- **`hardware/bom/bom.csv`** — ESP32 designators removed (U2, ANT1, ESP32 USB cable).
- **`hardware/bom/README.md`**, **`hardware/mechanical/README.md`** — ESP32 references removed.
- **`docs/MEASUREMENT_METHODOLOGY.md`** — ESP32 power/BLE/NVS sections removed. Bypass is now `dsp_enable_i` in
  `top.sv`.
- **`docs/architecture/dsp_pipeline.md`** — `REG_*` references replaced with FPGA-only equivalents (`mode_ctrl` gain
  tables for gate thresholds, `volume_ctrl` for volume). Volume stage added to the signal chain.
- **`docs/architecture/resource_budget.md`** — SPI slave, CDC SPI, register file rows removed; two-domain timing model
  adopted; `btn_debounce` + `volume_ctrl` rows added (estimated).
- **`docs/architecture/README.md`** — index updated: current docs listed explicitly; `register_map.md` and
  `firmware_arch.md` reclassified as historical.
- **`docs/architecture/register_map.md`** — archival banner refreshed; fixed false claims in banner/notes about the
  firmware tree still being on disk as archive and the new mode numbering (General/Speech/Music/Hearing).
- **`docs/DESIGN_DECISIONS.md`** — ADR-002 and ADR-007 marked Superseded by ADR-009 (FPGA-Only Architecture) on
  2026-08-12. ADR-009 added with full Context / Decision / Consequences / Alternatives. ADR index updated. Existing
  numbering preserved.
- **`README.md`** — Project Status table now reflects the FPGA-only implementation reality; repo structure table
  corrected (no `bitstream_utils/` entry; `firmware/` described as archived); IMPLEMENTATION_PLAN link noted as
  historical; link to `docs/fpga_only_architecture.md` added.
- **`CONTRIBUTING.md`** — firmware workflow steps, ESP-IDF clang-format row, and the `/firmware/` ownership row removed;
  replaced with FPGA-only equivalents.
- **`.github/ISSUE_TEMPLATE/bug_report.md`**, **`.github/ISSUE_TEMPLATE/feature_request.md`**,
  **`.github/PULL_REQUEST_TEMPLATE.md`** — ESP-IDF/firmware environment rows, firmware checkboxes, and `idf.py build`
  rows removed; FPGA-only equivalents.
- **`ENGINEERING_DESIGN.md`** — banner added near the top pointing to `docs/fpga_only_architecture.md`. ESP32-era
  sections (§1.1, §1.2, §1.3, §1.4, §2.1, §2.2, §2.3, §2.4, §3.4, §3.7, §3.8, §3.9, §5.1, §6 reset diagram, §8 register
  map, §10.2, §10.5, §13.1, §15.5 clock table) annotated with `[FPGA-only 2026-08-12: …]` markers; pre-migration text
  retained verbatim for the historical record.
- **`verification_coverage_audit.md`** — banner added at top noting the SPI slave / register file / SPI CDC modules are
  no longer in the build; verification focus updated to `btn_debounce`, `volume_ctrl`, `mode_ctrl`.

### Removed

- ESP32 host from the architecture. No external microcontroller, no host processor, no firmware.
- SPI control plane. `spi_slave.sv`, `reg_file.sv`, `cdc_spi_to_dsp.sv`, `cdc_dsp_to_spi.sv` are no longer in the build
  (source preserved under `archive/rtl/`).
- The 128 × 24-bit SPI register file. There is no host interface to read or write registers at runtime; mode and volume
  are driven by onboard push buttons.
- ESP-IDF firmware tree. The `firmware/` directory is retained on disk (per the migration brief) and is identical to the
  canonical archive under `archive/firmware/`. It is not part of the build.
- BLE / Bluetooth / NVS / FreeRTOS. Not applicable to the FPGA-only build.
- ESP32 line items from `hardware/bom/bom.csv` (U2 module, ANT1 antenna, ESP32 USB cable).
- ESP32 line items from the cost summary in `docs/hardware/BOM.md`.

### Superseded

- `docs/architecture/firmware_arch.md` — banner added; body retained as historical.
- `docs/architecture/register_map.md` — banner preserved and refreshed; body retained as historical.
- ADR-002 ("Use ESP32 as Controller") — superseded by ADR-009.
- ADR-007 ("SPI Register File for ESP32 → FPGA Configuration") — superseded by ADR-009.

### Notes

- This release contains the FPGA-only architecture sweep. The FPGA's RTL, testbenches, constraints, and build scripts
  were **not** modified by this documentation pass. The documentation sweep is docs-only per the migration brief.
- CI and simulation configuration should be checked against the current FPGA testbench list when modified.

## [0.1.0] - 2026-07-01

### Added

- Reserved initial release tag. Identical contents to `[Unreleased]` above; created so that downstream consumers can pin
  to a specific commit family. The first release with runnable bitstream and firmware will be `0.2.0` after Phase 0 of
  the implementation plan closes.
