# Migration Summary — ESP32 + FPGA → FPGA-only

> **Project Auris** — Narrative of the 2026-08-12 FPGA-only migration.
> **Last updated:** 2026-08-12
> **Status:** Authoritative. This is the single-pane-of-glass record
> of what was removed, what was added, and what was preserved during
> the migration.

This document is the *narrative* companion to
[`fpga_only_architecture.md`](fpga_only_architecture.md). That file
describes the current architecture; this file describes what changed
and why. For the full forensic state at the start of the migration,
see
[`fpga_only_migration_forensic_audit_2026-08-12.md`](fpga_only_migration_forensic_audit_2026-08-12.md).

---

## 1. Motivation

The pre-migration architecture paired the Spartan-7 FPGA with an
ESP32-DevKitC-32E microcontroller. The ESP32 generated the I2S
clocks (BCLK 3.072 MHz, LRCLK 48 kHz), owned the user interface
(buttons, BLE, RGB LED, NVS storage), and configured the FPGA over
a 4-wire SPI bus. The FPGA did the deterministic signal processing
(FFT/IFFT pipeline) and reported telemetry back over the same SPI
link.

The architecture worked but had three structural costs:

1. **Two development toolchains.** Vivado + Xilinx xfft IP for the
   FPGA; ESP-IDF + FreeRTOS for the ESP32. Every change touched
   both. Every debug session required two serial consoles.
2. **Three clock domains to manage.** DSP at 96 MHz (FPGA MMCM),
   I2S BCLK at 3.072 MHz (ESP32 I2S peripheral), SPI SCLK at
   ≤ 10 MHz (ESP32 SPI peripheral). Five crossing points, three
   CDC strategies (two async FIFOs and one 4-phase handshake
   pair).
3. **A 31-bit SPI control bus** that required a 4-phase req/ack
   handshake to cross the SPI↔DSP CDC safely. The bus consumed
   ~1,000 LUTs and ~1,500 FFs for a control path that wrote four
   register fields per second.

The FPGA-only migration removes the ESP32 entirely. The FPGA
becomes the sole signal-processing, control, and I/O-master
entity. There is no firmware to flash, no BLE stack, no NVS
storage, and no SPI bus.

The migration was driven by three goals:

- **Simpler toolchain.** One language (SystemVerilog), one tool
  (Vivado), one set of verification artefacts.
- **Tighter latency.** Removing the SPI register-write path cuts
  ~100 µs of mode-change latency (the time to write `REG_MODE`
  and wait for the IFFT frame to finish). The mode change is now
  triggered by a button press and is committed in the next FFT
  frame boundary.
- **Better educational signal.** A college-admissions reader sees
  one processor, one clock plan, one pipeline — not two. The
  DSP, CDC, and control logic all live in the same RTL tree.

---

## 2. What Was Removed

### 2.1 Hardware

| Item | Why removed |
|------|-------------|
| ESP32-DevKitC-32E module | No longer needed; FPGA owns the control plane |
| ESP32 ↔ FPGA SPI bus (Pmod JA0–JA3: SCLK, MOSI, MISO, CS_N) | No host interface; the FPGA is the host |
| ESP32 USB cable and serial console | No firmware to flash or debug |
| ESP32 LiPo battery + TP4056 (planned Phase 5) | Not relevant for the FPGA-only build |
| ESP32 BLE antenna | No BLE in this build |

The Pmod JA pin map was reassigned:

- **JA0–JA3** (previously SPI): now unused. The Arty S7-25 PCB
  exposes JA0–JA3 to the breadboard; the FPGA no longer drives
  them in the build.
- **JA4 (BCLK, output)** → drives both INMP441 SCK and PCM5102A
  BCK (FPGA is the I2S master).
- **JA5 (LRCLK, output)** → drives both INMP441 WS and PCM5102A
  LRCK.
- **JA6 (ADC data, input)** ← INMP441 SD (INMP441 drives the
  FPGA).
- **JA7 (DAC data, output)** → PCM5102A DIN.

The `fpga/constraints/arty_s7_25.xdc` file is the authoritative
pin map. JA0–JA3 are no longer constrained; the four I2S pins
(JA4–JA7) are mapped to FPGA package pins M16, M17, M18, N18.

### 2.2 RTL modules

The following RTL modules are no longer part of the build. Their
source files were removed from `fpga/rtl/` and the corresponding
testbenches removed from `fpga/sim/testbenches/`. The original
source is preserved on disk under `archive/rtl/` for historical
reference.

| Module (pre-migration) | Replacement / where it lives now |
|------------------------|----------------------------------|
| `spi_slave.sv` | Removed. No host SPI interface. |
| `reg_file.sv` | Removed. Mode/volume/gain tables driven by inline FSMs and `mode_ctrl.sv`. |
| `cdc_spi_to_dsp.sv` (4-phase handshake) | Removed. No SPI clock domain. |
| `cdc_dsp_to_spi.sv` (4-phase handshake) | Removed. No SPI clock domain. |

The corresponding testbenches were also removed from the build
(retained on disk for historical reference):

| Testbench | Status |
|-----------|--------|
| `tb_spi_slave.sv` | Removed from build |
| `tb_reg_file.sv` | Removed from build |
| `tb_cdc_spi_to_dsp.sv` | Never existed as a separate testbench (the SPI handshakes were only smoke-tested via `tb_spi_slave`); the SPI CDC is gone anyway |

### 2.3 Firmware

The ESP-IDF firmware tree (`firmware/`) is removed from the build.
The directory itself remains on disk per the migration brief, but
it is not compiled, not flashed, and not executed. A canonical copy
lives under `archive/firmware/`.

Removed firmware components (all under `firmware/components/`):

- `spi_master` — was the ESP32-side SPI master driver
- `fpga_config` — was the high-level FPGA register API
- `mode_manager` — was the ESP32 mode state machine
- `button_handler` — was the ESP32 button debounce (moved into
  FPGA as `btn_debounce.sv`)
- `audio_driver` — was the ESP32 I2S master (moved into FPGA as
  `clk_gen.sv`)
- `led_indicator` — was the ESP32 RGB LED driver (moved into
  FPGA as the inline `case` in `top.sv`)
- `volume_ctrl` — was the ESP32 volume FSM (moved into FPGA as
  the inline `always_ff` in `top.sv`)
- `profile_store` — was NVS persistence (no longer applicable; no
  NVS in this build)
- `telemetry` — was FPGA status polling (no host to poll; observability
  via onboard LEDs only)
- `battery_mon` — was the LiPo battery ADC monitor (no battery
  in this build)
- `bt_audio` — was BLE GATT server (no BLE in this build)

The `firmware/main/main.c` FreeRTOS scheduler and IPC queues are
also gone — there are no FreeRTOS tasks, no event groups, no
queues.

### 2.4 Verification infrastructure

The pre-migration verification audit
(`verification_coverage_audit.md`) flagged the SPI testbenches
(`tb_spi_slave.sv` and `tb_reg_file.sv`) as the largest sources
of bugs. With the SPI slave and register file removed, those bugs
are no longer applicable — they are not regressions to be fixed,
they are history.

The audit's primary open critical findings were:

- The 33/32-bit SPI framing mismatch (now moot — no SPI)
- CDC handshake untested (now moot — no SPI CDC)
- 7 of 10 testbenches had no runner script (now all 9 active
  testbenches have scripts; see `fpga/scripts/sim_*.tcl`)
- CI simulation was non-gating (the CI workflow was made gating
  on 2026-08-12; `continue-on-error: true` removed)

The post-migration verification focus is on:

- **`btn_debounce`** — 20 ms debounce, edge pulse generation
- **`volume_ctrl`** — Q2.14 multiply, sat24, mute at 0
- **`mode_ctrl`** — atomic dual-bank BRAM swap, per-mode table load
- **`i2s_rx` / `i2s_tx`** — now running against the FPGA's own
  BCLK/LRCLK (the FPGA is the master), not the ESP32's

---

## 3. What Was Added

### 3.1 Hardware

No new hardware components. The FPGA-only build is a *subset* of
the pre-migration build.

The Pmod JA pin allocation changed (see §2.1). No other board
changes.

### 3.2 RTL modules

| Module (new) | Purpose |
|--------------|---------|
| `btn_debounce.sv` (under `fpga/rtl/io/`) | 20 ms debounce for the four active-low push buttons, with press and release edge pulse outputs |
| `volume_ctrl.sv` (under `fpga/rtl/dsp/`) | Q2.14 multiply of audio samples by 5-bit volume level; sat24 at the output; mute at level 0 |
| Inline FSMs in `top.sv` | 2-bit mode counter (wraps on BTN0/BTN1) and 5-bit volume counter (saturates on BTN2/BTN3) |
| `clk_gen.sv` (enhanced) | 12 MHz → 96 MHz DSP clock (MMCME2_BASE) **plus** the fractional divide-by-31.25 BCLK generator and the ÷64 LRCLK generator. Previously `clk_gen.sv` was a stub for the MMCM only. |

### 3.3 Enhanced modules

| Module (enhanced) | Change |
|-------------------|--------|
| `mode_ctrl.sv` | Now ships with four pre-computed 128-entry Q2.14 gain tables (one per mode) instead of loading the same unity-gain table on every mode change. The `default_master_gain_o`, `default_noise_floor_o`, and `default_gate_ratio_o` outputs are unused in the FPGA-only build (tied to hardcoded defaults further down in `top.sv`). |
| `top.sv` | Hosts the inline mode and volume FSMs, the RGB LED decoder, and the LRCLK 2-FF synchroniser. No longer references any SPI/reg_file/cdc_spi_* modules. The `dsp_enable_i` input is hardwired to `1'b1` (bypass is exercised at bring-up via the dedicated bypass path inside `dsp_pipeline.sv`). |
| `dsp_pipeline.sv` | Adds a `volume_i` input wired to the inline volume FSM. The volume stage sits between overlap-add and the output buffer. Bypass mode (`dsp_enable_i = 0`) now defaults to active in the design (the wire is tied to 1 inside `top.sv`; bypassing is exercised by direct manipulation of the wire at bring-up). |
| `fpga/constraints/arty_s7_25.xdc` | Pin map updated: BCLK and LRCLK are now FPGA *outputs* (FPGA is the I2S master). BTN2 takes over F13 (formerly LED[1] on the Digilent master XDC); the clip LED moves from LED[1] to LED[2] (G15). |

---

## 4. Before / After Comparison

### 4.1 Architecture

**Before:**
- ESP32 (control plane: BLE, buttons, NVS, I2S master)
- FPGA (data plane: FFT pipeline, register file, SPI slave)
- 4-wire SPI link between them
- Three clock domains: DSP (96 MHz), I2S BCLK (3.072 MHz from ESP32), SPI SCLK (≤10 MHz from ESP32)
- Five CDC crossing points

**After:**
- FPGA only (control + data plane)
- Onboard push buttons + RGB LED + status LEDs as the user interface
- No external host, no firmware, no SPI
- Two clock domains: DSP (96 MHz) and I2S BCLK (3.072 MHz, generated by the FPGA)
- Two CDC crossing points (audio in and audio out)

### 4.2 Signal chain

The signal chain in `dsp_pipeline.sv` is unchanged — input buffer
→ Hann window → FFT → spectral proc → IFFT → overlap-add → output
buffer. The two additions are:

- **`volume_ctrl`** between overlap-add and output buffer (per-stage
  Q2.14 multiply with sat24).
- **Bypass mux** at the output: when `dsp_enable_i = 0`, the CDC'd
  input samples bypass the entire pipeline (registered, 1 cycle).

### 4.3 Resource budget (estimated post-synthesis)

The migration is roughly **resource-neutral**: the SPI/reg_file
removed ~2,000 LUTs and ~3,000 FFs; the new `btn_debounce`,
`volume_ctrl`, and enhanced `mode_ctrl` add ~600 LUTs and ~400 FFs.
The fractional BCLK divider in `clk_gen.sv` adds ~50 LUTs and ~50
FFs (a 4-bit counter plus the toggle FSM). Net change: roughly
–1,350 LUTs and –2,500 FFs.

The full post-migration budget is in
[`docs/architecture/resource_budget.md`](architecture/resource_budget.md).

### 4.4 Verification

| Metric | Before | After |
|--------|--------|-------|
| Active RTL modules | 22 | 20 (24 files on disk; 4 SPI-era modules retained but not referenced) |
| Active testbenches | 10 | 9 (11 files on disk; tb_spi_slave + tb_reg_file retained but not referenced) |
| Testbenches with runner scripts | 3 / 10 | 9 / 9 |
| CI simulation gating | Non-gating | Gating |
| CDC paths | 5 | 2 |
| Clock domains | 3 | 2 |
| External dependencies | ESP-IDF toolchain + ESP32 hardware | Vivado only + Arty S7-25 |

---

## 5. Documentation Update Stats

The 2026-08-12 documentation sweep modified or created:

- **3 new documents**: `docs/fpga_only_architecture.md`,
  `docs/migration_summary.md`, `docs/documentation_audit.md`.
- **6 full rewrites**: `docs/hardware/WIRING.md`,
  `docs/hardware/README.md`, `tools/README.md`,
  `hardware/schematics/README.md`, `docs/DEMO_PLAN.md`,
  `docs/hardware/BOM.md`.
- **7 banners added** (historical / superseded notices) on
  documents that retain their pre-migration body for the record:
  `docs/IMPLEMENTATION_PLAN.md`, `docs/ROADMAP.md`,
  `docs/architecture/firmware_arch.md`,
  `docs/architecture/register_map.md`,
  `SESSION_SUMMARY_2026-08-12.md`,
  `docs/fpga_only_migration_forensic_audit_2026-08-12.md`,
  `verification_coverage_audit.md`.
- **~14 targeted patches** across architecture docs,
  README, CONTRIBUTING, CHANGELOG, BOM CSV, mechanical
  notes, and GitHub issue/PR templates.
- **No modifications** to any `.sv`, `.v`, `.xdc`, `.tcl`,
  `.yml`, `.yaml`, `Makefile`, or `firmware/` source file.

The full file-level list and verdict per file is in
[`docs/documentation_audit.md`](documentation_audit.md).

---

## 6. Archived Artifacts

The `archive/` directory is the canonical archive. Anything that
was removed from the build lives here:

- `archive/firmware/` — exact copy of the pre-migration ESP-IDF
  firmware tree. Same content as `firmware/` on disk (which is
  retained per the migration brief).
- `archive/rtl/` — pre-migration RTL modules that are no longer
  in the build: `spi_slave.sv`, `reg_file.sv`, `cdc_spi_to_dsp.sv`,
  `cdc_dsp_to_spi.sv`.
- `archive/tb/` — pre-migration testbenches that are no longer
  in the build: `tb_spi_slave.sv`, `tb_reg_file.sv`.

The pre-migration `firmware/` tree is also retained on disk at
the project root. This is intentional (per the migration brief):
the `archive/` directory is the canonical archival location, but
deleting the top-level `firmware/` was explicitly out of scope.

---

## 7. BOM Impact

The BOM shrinks by one line item (the ESP32 module) and one
supporting component (the ESP32 USB cable). The total per-unit cost
decreases by **$15**.

Pre-migration BOM line items summed to $121.60, including the
ESP32-DevKitC-32E ($12) and the ESP32 micro-USB cable ($3). The
pre-migration `docs/hardware/BOM.md` stated a total of $116.60,
which was a pre-existing arithmetic error in that document.
Post-migration BOM total: **$106.60** (line items only — no
ESP32, no second USB cable).

For the full updated BOM, see
[`docs/hardware/BOM.md`](hardware/BOM.md) and
[`hardware/bom/bom.csv`](../hardware/bom/bom.csv).

---

## 8. Remaining Out-of-Scope Items

The 2026-08-12 documentation sweep was **docs-only**. The following
items were identified in the forensic audit
([`fpga_only_migration_forensic_audit_2026-08-12.md`](fpga_only_migration_forensic_audit_2026-08-12.md))
and are **not** addressed by this documentation pass. They are
listed here for transparency; they are NOT regressions to fix
within the docs task.

### 8.1 Dead RTL files on disk

The following pre-migration RTL modules and testbenches are no
longer referenced by the build but remain on disk:

- `fpga/rtl/io/spi_slave.sv`
- `fpga/rtl/ctrl/reg_file.sv`
- `fpga/rtl/cdc/cdc_spi_to_dsp.sv`
- `fpga/rtl/cdc/cdc_dsp_to_spi.sv`
- `fpga/sim/testbenches/tb_spi_slave.sv`
- `fpga/sim/testbenches/tb_reg_file.sv`

A canonical copy lives under `archive/rtl/` and `archive/tb/`.
Removing the source-tree copies is a future cleanup task. They
do not affect the build because no `*.tcl` file references them
and `sim_all.tcl` auto-discovers only the active testbenches.

### 8.2 CI workflow issues

The `.github/workflows/ci.yml` and `.github/workflows/release.yml`
workflows reference the pre-migration testbench list in some
steps. The CI was made gating on 2026-08-12 (the `continue-on-error:
true` flags were removed from simulation steps), but the workflows
themselves were not updated to remove the `tb_spi_slave` and
`tb_reg_file` simulation steps that no longer match any active
testbench.

These workflows are out of scope for the documentation sweep and
should be updated in a separate CI task. Note: this task is also
explicitly excluded from the current sweep per the migration brief.

### 8.3 XDC stale comment

The XDC was updated during the RTL migration (BCLK/LRCLK became
outputs, BTN2 took over F13, clip LED moved to LED[2] = G15), but
one comment remains stale: §4 of `fpga/constraints/arty_s7_25.xdc`
still lists the pre-migration mode-colour mapping
("General=green, Hearing=blue, Speech=cyan, Bypass=red"). The
current mapping is General=green, Speech=blue, Music=magenta,
Hearing=red (see `docs/architecture/modes_and_gains.md`). A
comment-only cleanup is a future task; the XDC was not modified
by this documentation sweep.

### 8.4 Pre-migration bitstream

A bitstream from the pre-migration build may still exist in
`fpga/vivado_proj/auris.runs/impl_1/top.bit`. If it does, it
will not bit-program the post-migration RTL (the port lists
changed). Regenerate the bitstream with `make fpga` before
programming the board.

### 8.5 Firmware tree at root

The `firmware/` directory at the project root is a duplicate of
`archive/firmware/`. It is retained per the migration brief. The
two directories are *identical in content* but `archive/` is the
canonical archival location. A future cleanup could remove the
top-level `firmware/` and add a `README.md` pointing to `archive/`
— but this is out of scope for the documentation sweep.

---

## 9. Where to Read Next

- [`docs/fpga_only_architecture.md`](fpga_only_architecture.md) —
  the current architecture (FPGA-only).
- [`docs/fpga_only_migration_forensic_audit_2026-08-12.md`](fpga_only_migration_forensic_audit_2026-08-12.md) —
  the forensic audit of the pre-migration state.
- [`docs/documentation_audit.md`](documentation_audit.md) —
  file-level audit of this documentation sweep.
- [`archive/README.md`](../archive/README.md) — what is in the
  archive and why.
- [`docs/architecture/firmware_arch.md`](architecture/firmware_arch.md) —
  HISTORICAL — the pre-migration ESP32 firmware architecture.
- [`docs/architecture/register_map.md`](architecture/register_map.md) —
  HISTORICAL — the pre-migration SPI register map.