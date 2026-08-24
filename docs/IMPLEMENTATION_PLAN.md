# Project Auris — Implementation Plan

> **⚠️ SUPERSEDED — 2026-08-12 FPGA-only migration.** This
> document was authored for the pre-migration ESP32 + FPGA
> architecture. The implementation plan below describes the
> ESP32 firmware integration, the SPI control plane, the
> Phase 4 BLE telemetry, and the Phase 5 LiPo battery /
> enclosure path. None of those are in the current build.
>
> **The current architecture is FPGA-only** (the Spartan-7
> FPGA does all signal processing, all control, and is the I²S
> clock master). Onboard push buttons (BTN0–BTN3) drive inline
> mode and volume FSMs in `top.sv`. There is no ESP32, no SPI
> host interface, no BLE, no NVS, no firmware at runtime.
>
> **For the current architecture, see**
> [`docs/fpga_only_architecture.md`](fpga_only_architecture.md).
> **For a narrative of what changed, see**
> [`docs/migration_summary.md`](migration_summary.md).
>
> This document is retained verbatim for the historical record
> (it describes how the project *used to* be structured). Do
> not implement anything described in the Phase 0–6 plan
> below; the corresponding phases have already landed in the
> FPGA-only build.

> **Status:** Skeleton complete. Phase 0 (toolchain) starting.
> **Last updated:** 2026-07 (banner added 2026-08-12)

This document is the single source of truth for the repository layout, the
phased development plan, the build & tooling instructions, and pointers to
all skeleton code. Read it top-to-bottom on your first day; thereafter,
refer back to specific sections as needed.

---

## Table of Contents

1. [Repository Structure](#1-repository-structure)
2. [Development Phases & Milestones](#2-development-phases--milestones)
3. [Build & Tooling Instructions](#3-build--tooling-instructions)
4. [Code Skeleton Reference](#4-code-skeleton-reference)
5. [College Application Milestones](#5-college-application-milestones)
6. [Risk Mitigation](#6-risk-mitigation)

---

## 1. Repository Structure

```
project-auris/
├── README.md                         # Project front door (build commands, status)
├── LICENSE                           # MIT
├── Makefile                          # Top-level orchestrator (tools + fpga + esp)
│
├── docs/
│   ├── IMPLEMENTATION_PLAN.md        # THIS FILE
│   ├── architecture/                 # Block diagrams, clock-domain analysis
│   │   └── README.md
│   ├── hardware/                     # Pin maps, schematics references
│   │   └── README.md
│   ├── phase_reports/                # End-of-phase reflections
│   │   └── README.md
│   └── college_app/                  # Essay topics, demo script, portfolio tips
│       └── README.md
│
├── tools/                            # Code generators (Python)
│   ├── fft_gen/
│   │   └── gen_fft.py                # 256-pt FFT core wrapper (stub)
│   ├── win_gen/
│   │   └── gen_hann_coeffs.py        # Hann window Q2.14 .hex generator (complete)
│   ├── profile_gen/
│   │   ├── gen_gain_profile.py       # Audiogram -> 128-bin gain table (skeleton)
│   │   └── gen_default_tables.py     # General/Hearing/Speech defaults
│   └── bitstream_utils/              # (Phase 3) Bitstream manipulation helpers
│
├── fpga/                             # SystemVerilog RTL, sim, build
│   ├── rtl/                          # All synthesizable SystemVerilog
│   │   ├── top.sv                    # Top-level wrapper (skeleton)
│   │   ├── clk_gen.sv                # MMCM wrapper (stub, Phase 1)
│   │   ├── pkg/
│   │   │   └── auris_pkg.sv          # Global types & register map
│   │   ├── io/                       # External interfaces
│   │   │   ├── i2s_rx.sv             # I2S slave receiver
│   │   │   ├── i2s_tx.sv             # I2S slave transmitter
│   │   │   └── spi_slave.sv          # SPI Mode-0 slave, 32-bit frames
│   │   ├── cdc/                      # Clock-domain crossing
│   │   │   ├── cdc_i2s_to_dsp.sv     # Async FIFO skeleton
│   │   │   ├── cdc_dsp_to_i2s.sv     # Async FIFO skeleton
│   │   │   └── cdc_spi_to_dsp.sv     # 2-FF sync (stub)
│   │   ├── ctrl/                     # Control & status
│   │   │   ├── reg_file.sv           # 128x24 register file
│   │   │   ├── mode_ctrl.sv          # Mode-driven gain table loader
│   │   │   └── status_mon.sv         # Heartbeat + clip latch (stub)
│   │   └── dsp/                      # DSP pipeline
│   │       ├── dsp_pipeline.sv       # Pipeline top-level
│   │       ├── input_buffer.sv       # Ping-pong BRAM input
│   │       ├── output_buffer.sv      # Ping-pong BRAM output
│   │       ├── window_apply.sv       # Hann window multiplier
│   │       ├── window_rom.sv         # 256x16 Hann coefficient ROM
│   │       ├── fft_256.sv            # AXI-Stream FFT wrapper (Phase 4)
│   │       ├── ifft_256.sv           # AXI-Stream IFFT wrapper (Phase 4)
│   │       ├── overlap_add.sv        # 50% OLA reconstructor
│   │       └── spectral/
│   │           └── spectral_proc.sv  # Per-bin gain + noise gate
│   ├── sim/
│   │   ├── testbenches/
│   │   │   ├── tb_i2s_rx.sv          # I2S RX testbench
│   │   │   └── tb_spi_slave.sv       # SPI slave testbench
│   │   ├── waveforms/                # .vcd / .wdb outputs
│   │   └── scripts/                  # (older convention; we use fpga/scripts/)
│   ├── constraints/
│   │   └── arty_s7_25.xdc            # Pin assignments + timing
│   ├── ip/                           # Generated IP cores
│   │   ├── clk_gen/                  # MMCM .xci
│   │   ├── fft_256/                  # xfft .xci
│   │   └── window_rom/               # Distributed ROM (no IP)
│   ├── scripts/
│   │   ├── build_project.tcl         # Vivado non-project build
│   │   ├── sim_i2s_rx.tcl            # Run tb_i2s_rx
│   │   └── sim_spi_slave.tcl         # Run tb_spi_slave
│   └── generated/                    # Python tool outputs (checked in)
│       ├── hann_256.hex              #   Hann window for $readmemh
│       ├── hann_256.coe              #   Same, .coe for IP init
│       ├── hann_256.txt              #   Human-readable
│       ├── gain_table_general.hex
│       ├── gain_table_hearing.hex
│       └── gain_table_speech.hex
│
├── firmware/                         # ESP-IDF C firmware
│   ├── CMakeLists.txt                # Top-level
│   ├── sdkconfig.defaults            # Default config
│   ├── partitions.csv                # NVS partition
│   ├── main/
│   │   ├── CMakeLists.txt
│   │   └── main.c                    # Entry point + task scheduler
│   └── components/
│       ├── spi_master/
│       │   ├── CMakeLists.txt
│       │   ├── spi_master.h
│       │   └── spi_master.c          # Low-level SPI driver
│       ├── fpga_config/
│       │   ├── CMakeLists.txt
│       │   ├── fpga_config.h         # Register address constants
│       │   └── fpga_config.c         # High-level config API
│       ├── mode_manager/
│       │   ├── CMakeLists.txt
│       │   ├── mode_manager.h
│       │   └── mode_manager.c        # Mode state machine
│       ├── button_handler/
│       │   ├── CMakeLists.txt
│       │   ├── button_handler.h
│       │   └── button_handler.c      # 3-button debounce
│       ├── audio_driver/
│       │   ├── CMakeLists.txt
│       │   ├── audio_driver.h
│       │   └── audio_driver.c        # I2S master, BCLK 3.072 MHz
│       ├── led_indicator/
│       │   ├── CMakeLists.txt
│       │   ├── led_indicator.h
│       │   └── led_indicator.c
│       ├── volume_ctrl/
│       │   ├── CMakeLists.txt
│       │   ├── volume_ctrl.h
│       │   └── volume_ctrl.c         # 0..31 steps, 2 dB each
│       ├── profile_store/
│       │   ├── CMakeLists.txt
│       │   ├── profile_store.h
│       │   └── profile_store.c       # NVS persistence
│       ├── telemetry/                # Phase 2
│       │   ├── CMakeLists.txt
│       │   ├── telemetry.h
│       │   └── telemetry.c
│       ├── battery_mon/              # Phase 3
│       │   ├── CMakeLists.txt
│       │   ├── battery_mon.h
│       │   └── battery_mon.c
│       └── bt_audio/                 # Phase 3
│           ├── CMakeLists.txt
│           ├── bt_audio.h
│           └── bt_audio.c
│
└── hardware/                         # Physical design
    ├── schematics/                   # KiCad / PDF schematics
    ├── bom/                          # Bill of materials
    └── mechanical/                   # 3D-printed enclosure notes
```

### MVP / Phase 2 / Phase 3 file map

| File / module                            | Phase  | Why                                              |
|------------------------------------------|--------|--------------------------------------------------|
| `fpga/rtl/top.sv`                        | MVP    | Integration point                                |
| `fpga/rtl/pkg/auris_pkg.sv`              | MVP    | Shared types                                     |
| `fpga/rtl/io/i2s_rx.sv`                  | MVP    | Required for audio                               |
| `fpga/rtl/io/i2s_tx.sv`                  | MVP    | Required for audio                               |
| `fpga/rtl/io/spi_slave.sv`               | MVP    | Required for control                             |
| `fpga/rtl/ctrl/reg_file.sv`              | MVP    | Required for control                             |
| `fpga/rtl/ctrl/mode_ctrl.sv`             | MVP    | Required for mode switching                      |
| `fpga/rtl/dsp/dsp_pipeline.sv`           | MVP    | Pipeline top                                     |
| `fpga/rtl/dsp/window_apply.sv`           | MVP    | Required                                         |
| `fpga/rtl/dsp/window_rom.sv`             | MVP    | Required                                         |
| `fpga/rtl/dsp/input_buffer.sv`           | MVP    | Required                                         |
| `fpga/rtl/dsp/output_buffer.sv`          | MVP    | Required                                         |
| `fpga/rtl/dsp/overlap_add.sv`            | MVP    | Required                                         |
| `fpga/rtl/dsp/fft_256.sv`                | MVP    | Required                                         |
| `fpga/rtl/dsp/ifft_256.sv`               | MVP    | Required                                         |
| `fpga/rtl/dsp/spectral/spectral_proc.sv`  | MVP    | Required                                         |
| `fpga/rtl/cdc/cdc_*.sv`                  | MVP    | Required (stub initially)                        |
| `fpga/rtl/ctrl/status_mon.sv`            | MVP    | Heartbeat only                                   |
| `fpga/rtl/clk_gen.sv`                    | MVP    | MMCM                                             |
| `fpga/constraints/arty_s7_25.xdc`        | MVP    | Pin map                                          |
| `fpga/sim/testbenches/tb_*.sv`           | MVP    | Required for verification                        |
| `firmware/main/main.c`                   | MVP    | Entry point                                      |
| `firmware/components/spi_master/`        | MVP    | Required for control                             |
| `firmware/components/fpga_config/`       | MVP    | Required for control                             |
| `firmware/components/mode_manager/`      | MVP    | Required for mode switching                      |
| `firmware/components/button_handler/`    | MVP    | Required for input                               |
| `firmware/components/audio_driver/`      | MVP    | Required for audio                               |
| `firmware/components/led_indicator/`     | MVP    | Required for feedback                            |
| `firmware/components/volume_ctrl/`       | MVP    | Required                                         |
| `firmware/components/profile_store/`     | MVP    | Required (NVS)                                   |
| `tools/win_gen/gen_hann_coeffs.py`       | MVP    | Required                                         |
| `tools/profile_gen/gen_gain_profile.py`  | MVP    | Required                                         |
| `tools/profile_gen/gen_default_tables.py`| MVP    | Required                                         |
| `firmware/components/telemetry/`         | Phase 2| FPGA status polling                              |
| `firmware/components/battery_mon/`       | Phase 3| Battery monitoring                               |
| `firmware/components/bt_audio/`          | Phase 3| Bluetooth A2DP                                   |
| `tools/fft_gen/gen_fft.py`               | Phase 4| Replace Vivado IP with dblclockfft if desired    |
| `tools/bitstream_utils/`                 | Phase 3| Helpers for batch testing / programming          |

---

## 2. Development Phases & Milestones

| Phase | Title                            | Weeks | Goal                                                                |
|-------|----------------------------------|-------|---------------------------------------------------------------------|
| 0     | Toolchain setup                  | 1     | Vivado + ESP-IDF installed; "hello world" builds on both            |
| 1     | FPGA blink                       | 1–2   | Confirm Arty S7-25 is functional; LED blink @ 1 Hz from MMCM        |
| 2     | ESP32 ↔ FPGA SPI link            | 1–2   | Read/write the FPGA register file from the ESP32; loopback test     |
| 3     | I2S audio passthrough            | 2–3   | Mic → FPGA → DAC, no DSP, just verify analog path                  |
| 4     | **MVP** — DSP with one mode      | 3–4   | 256-pt FFT pipeline running, General mode (flat gain) working       |
| 5     | Modes & polish                   | 2–3   | Hearing + Speech modes; NVS persistence; college-app material       |
| 6     | Bluetooth, telemetry, DRC        | 4+    | Bluetooth audio in, DRC LUT, telemetry dashboard                    |

### Detailed phase plans

#### Phase 0 — Toolchain setup (1 week)

**Goals**
- Vivado 2024.x installed and licenses verified
- ESP-IDF v5.x installed, `idf.py build` works on a hello-world
- Git workflow set up (GitHub repo, branching)

**Tasks**
1. Install Vivado (WebPack / free edition is fine for XC7S25).
2. Install ESP-IDF v5.x per official guide; run `idf.py create-project` to
   create a blank project and build.
3. Create GitHub repo. Push initial commit (skeleton).
4. Verify Arty S7-25 driver: connect via USB, run Vivado Hardware Manager.

**Deliverable**
- `make all` runs both Vivado and ESP-IDF (though both will be no-ops for now)
- Commit history shows working directory tree

**Validation**
- `idf.py build` produces a .bin file under `firmware/build/`
- `vivado -mode batch -source fpga/scripts/build_project.tcl` produces
  a bitstream under `fpga/vivado_proj/auris.runs/synth_1/top.bit`

**Risk / go-no-go checkpoint**
- If Vivado install is too slow or license issues arise, consider the
  open-source Symbiflow toolchain as a fallback (limited support for
  Spartan-7, so this is a real risk — don't skip this checkpoint).

#### Phase 1 — FPGA blink (1–2 weeks)

**Goals**
- Confirm the FPGA toolchain can target the Arty S7-25
- Establish a clean synthesis/implementation flow

**Tasks**
1. Implement `top.sv` with the MMCM and the RGB LED.
2. Generate the MMCM IP (`clk_gen.xci`) via Vivado IP catalog.
3. Run a 1 Hz heartbeat from a divided MMCM clock.
4. Flash the bitstream via Vivado Hardware Manager.
5. Write a phase report (`docs/phase_reports/phase_1.md`).

**Deliverable**
- `clk_gen.sv` properly instantiated (not stubbed)
- Bitstream programmed; RGB LED blinks

**Validation**
- LED blinks at exactly 1 Hz (verify with phone stopwatch)
- Resource utilization report shows MMCM (1) + minimal logic

#### Phase 2 — ESP32 ↔ FPGA SPI link (1–2 weeks)

**Goals**
- Verify the SPI cable is wired correctly
- Read/write a register on the FPGA from the ESP32

**Tasks**
1. Wire Arty S7 Pmod JA ↔ ESP32 DevKit (5 wires: SCLK, MOSI, MISO, CS, GND).
2. Implement `spi_slave.sv` and `tb_spi_slave.sv`. Get the testbench to pass
   in xsim.
3. Implement `reg_file.sv` with a minimal subset (just `REG_VERSION`,
   `REG_SCRATCH`, `REG_LOOPBACK`).
4. Implement `spi_master.c` and `fpga_config.c` on the ESP32 side.
5. ESP-IDF test app: write 0xDEADBEEF to `REG_SCRATCH`, read it back, log.

**Deliverable**
- SPI loopback works at 10 MHz
- ESP32 log line: "FPGA SPI test passed"

**Validation**
- `REG_LOOPBACK` round-trip: write 0x123456, read 0x123456
- Scope the SPI lines; verify mode 0 timing

**Risk / go-no-go checkpoint**
- If SPI fails repeatedly, simplify to bit-bang GPIO from the ESP32
  (much slower but useful for debugging). This is a 2-day detour.

**College application milestone**
- *"Built a working SPI bus between microcontroller and FPGA"*
  — great for a short essay or a portfolio piece.

#### Phase 3 — I2S audio passthrough (2–3 weeks)

**Goals**
- Audio flows: mic → FPGA → DAC → headphones, with no DSP yet
- ESP32 generates BCLK/LRCLK; FPGA is slave

**Tasks**
1. Wire INMP441, PCM5102A, and the FPGA Pmod JB.
2. Implement `i2s_rx.sv` and `i2s_tx.sv`. Get `tb_i2s_rx.sv` passing.
3. Implement `cdc_i2s_to_dsp.sv` (start with a 1-deep handshake; refine
   later if needed).
4. Implement `audio_driver.c` on the ESP32.
5. Test: speak into mic, hear yourself in headphones.

**Deliverable**
- `top.sv` instantiated; bitstream + ESP32 firmware run together
- Round-trip audio works (with a couple ms latency)

**Validation**
- Tone generator → mic input → headphones output (test in 1 kHz range)
- `fpga_reg_read(REG_STATUS)` shows I2S_LOCKED bit

**Risk / go-no-go checkpoint**
- If round-trip audio is distorted or missing, suspect:
  - LRCLK polarity (INMP441 vs PCM5102A conventions differ)
  - BCLK not exactly 3.072 MHz (check with scope)
  - I2S RX/TX swap (left vs right alignment)

**College application milestone**
- *"Real-time audio path through an FPGA"* — the moment the project
  becomes "real" rather than abstract. Demo video material.

#### Phase 4 — MVP: DSP with one mode (3–4 weeks)

**Goals**
- The 256-pt FFT/IFFT pipeline is running
- General mode (flat 0 dB gain) is functional and audibly transparent
- This is the **minimum viable product** for college applications

**Tasks**
1. Generate the FFT IP (`fft_256.xci`) using the Vivado IP catalog.
   Recommended settings: pipelined streaming I/O, 256-pt, 16-bit data,
   block-floating-point scaling.
2. Run `gen_hann_coeffs.py` to generate `hann_256.hex`.
3. Implement `window_apply.sv` and `window_rom.sv`. Wire to FFT.
4. Implement `input_buffer.sv` and `output_buffer.sv` (ping-pong BRAM).
5. Implement `overlap_add.sv` (50% OLA).
6. Implement `spectral_proc.sv` with master gain + per-bin gain (no
   noise gate yet).
7. Wire `dsp_pipeline.sv` to `top.sv`.
8. Update `mode_ctrl.sv` so MODE_GENERAL loads a flat gain table.
9. Run all testbenches; pass.

**Deliverable**
- A bitstream + firmware that processes audio through the FFT pipeline
  with flat gain
- Resource utilization: ~9k LUTs, ~50 DSPs, ~30 BRAMs (within budget)

**Validation**
- Speak into mic; hear yourself with no noticeable coloration
- Apply a +6 dB master gain; volume increases
- Apply a per-bin gain (e.g., +12 dB at 4 kHz only); verify with
  spectrum analyzer on the output

**Risk / go-no-go checkpoint**
- The biggest risk here is fitting in the LUT budget. If post-route
  utilization is >95%:
  - Switch to the dblclockfft generator (smaller but more work)
  - Use 12-bit data instead of 16-bit (loses SNR but halves LUTs)
  - Share the FFT/IFFT (saves ~1500 LUTs but adds complexity)
- If timing fails at 96 MHz, lower the DSP clock to 64 MHz; latency
  increases by 50% but is still acceptable.

**College application milestone**
- *"Working FFT-based audio processor on FPGA"* — this is the **headline
  feature**. Plan to record a demo at the end of this phase.

#### Phase 5 — Modes & polish (2–3 weeks)

**Goals**
- All three modes (General, Hearing, Speech) work
- Settings persist across reboots
- Final PCB / enclosure / demo material

**Tasks**
1. Run `gen_default_tables.py` to generate the three default gain tables.
2. Implement `mode_ctrl.sv` so each mode loads the right table.
3. Implement NVS persistence in `profile_store.c`.
4. Build the enclosure (3D print or off-the-shelf).
5. Write a 6-page IEEE-format paper (`docs/college_app/technical_report.md`).
6. Record a 3-minute demo video.

**Deliverable**
- Polished, working prototype
- College application material ready

**Validation**
- Reboot the device with hearing loss compensation active — it should
  come up in the same mode and volume
- The user can change modes by pressing the button; LED color changes

#### Phase 6 — Bluetooth, telemetry, DRC (4+ weeks)

**Goals**
- Bluetooth audio input (phone → ESP32 → FPGA → headphones)
- DRC (dynamic range compression) via LUT
- Telemetry dashboard (peak levels, clip counter)

**Tasks**
1. Implement `bt_audio.c` using ESP-IDF A2DP API.
2. Implement `telemetry.c` (periodic reads from FPGA status registers).
3. Implement DRC LUT (256-entry, indexed by short-term RMS).
4. Optimize resource utilization; consider shared FFT/IFFT.

**Deliverable**
- Production-quality device
- Publication-quality technical report

**Validation**
- Stream Spotify over Bluetooth → FPGA processes → headphones
- DRC test: play loud/quiet passages, verify output level is compressed

---

## 3. Build & Tooling Instructions

### Prerequisites

- **Vivado 2024.1+** (WebPack / free edition works for XC7S25)
- **ESP-IDF v5.1+** with the ESP32 toolchain
- **Python 3.9+** for the tools
- **Git**
- **Arty S7-25** board + Micro-USB cable
- **ESP32 DevKit v1** + micro-USB cable
- (Phase 3 onward) **INMP441**, **PCM5102A**, breadboard, jumpers

### First-time setup

```bash
# 1. Clone the repository
git clone https://github.com/<you>/project-auris.git
cd project-auris

# 2. Generate window + gain tables
make tools

# 3. Build the FPGA bitstream
make fpga

# 4. Build the ESP32 firmware
make esp
```

### Day-to-day development

```bash
# Edit SystemVerilog
vim fpga/rtl/dsp/spectral/spectral_proc.sv

# Run only the I2S testbench
vivado -mode batch -source fpga/scripts/sim_i2s_rx.tcl

# Rebuild the bitstream
make fpga

# Open Vivado GUI for interactive debug
vivado fpga/vivado_proj/auris.xpr

# Flash the ESP32
make esp-flash ESP_PORT=/dev/ttyUSB0
# (On Windows: ESP_PORT=COM3)

# Monitor ESP32 serial
make esp-monitor ESP_PORT=/dev/ttyUSB0
```

### Simulation workflow

The project uses Vivado's built-in xsim simulator. Each testbench is
invoked via a separate `.tcl` file:

```bash
vivado -mode batch -source fpga/scripts/sim_i2s_rx.tcl
```

Waveforms are dumped to `fpga/sim/waveforms/*.vcd` and can be viewed in
GTKWave (free) or Vivado's waveform viewer.

For a faster iteration loop, you can also use Verilator:

```bash
verilator --binary -j 0 -sv \
    fpga/rtl/pkg/auris_pkg.sv \
    fpga/rtl/io/i2s_rx.sv \
    fpga/sim/testbenches/tb_i2s_rx.sv
./obj_dir/Vtb_i2s_rx
```

### Running the tools

```bash
# Hann window
python tools/win_gen/gen_hann_coeffs.py

# Single gain profile from an audiogram
python tools/profile_gen/gen_gain_profile.py \
    --audiogram 10,15,20,30,40,50,60 \
    --out-prefix gain_profile_demo

# All three default mode tables
python tools/profile_gen/gen_default_tables.py
```

### Flashing the FPGA

Use Vivado Hardware Manager:

1. Open Vivado → Open Hardware Manager → Open Target → Auto Connect
2. Right-click the XC7S25 → Program Device
3. Select `top.bit`

Or, for command-line programming, use `openFPGALoader` (open source):

```bash
openFPGALoader -b arty_s7 top.bit
```

### Flashing the ESP32

```bash
make esp-flash ESP_PORT=COM3   # Windows
make esp-flash ESP_PORT=/dev/ttyUSB0   # Linux
```

---

## 4. Code Skeleton Reference

This section is an index of every skeleton file in the repository, with a
one-line description. Each file has its own detailed header comment.

### FPGA — SystemVerilog

| File                                         | Purpose                                           | Status     |
|----------------------------------------------|---------------------------------------------------|------------|
| `fpga/rtl/pkg/auris_pkg.sv`                  | Global types, register map, constants             | Reference  |
| `fpga/rtl/top.sv`                            | Top-level wrapper, all port defs & instantiations | Skeleton   |
| `fpga/rtl/clk_gen.sv`                        | MMCM wrapper (12 MHz → 96 MHz)                    | Stub       |
| `fpga/rtl/io/i2s_rx.sv`                      | I2S slave receiver                                | Skeleton   |
| `fpga/rtl/io/i2s_tx.sv`                      | I2S slave transmitter                             | Skeleton   |
| `fpga/rtl/io/spi_slave.sv`                   | SPI Mode-0 slave, 32-bit framed                   | Skeleton   |
| `fpga/rtl/cdc/cdc_i2s_to_dsp.sv`             | Async FIFO (I2S → DSP)                            | Skeleton   |
| `fpga/rtl/cdc/cdc_dsp_to_i2s.sv`             | Async FIFO (DSP → I2S)                            | Skeleton   |
| `fpga/rtl/cdc/cdc_spi_to_dsp.sv`             | 2-FF synchronizer (SPI → DSP)                    | Skeleton   |
| `fpga/rtl/ctrl/reg_file.sv`                  | 128 × 24-bit register file                        | Skeleton   |
| `fpga/rtl/ctrl/mode_ctrl.sv`                 | Mode-driven gain table loader                     | Skeleton   |
| `fpga/rtl/ctrl/status_mon.sv`                | 1 Hz heartbeat + clip latch                       | Stub       |
| `fpga/rtl/dsp/dsp_pipeline.sv`               | Pipeline top-level                                | Skeleton   |
| `fpga/rtl/dsp/input_buffer.sv`               | Ping-pong BRAM input                              | Skeleton   |
| `fpga/rtl/dsp/output_buffer.sv`              | Ping-pong BRAM output                             | Skeleton   |
| `fpga/rtl/dsp/window_apply.sv`               | Hann window multiplier                            | Skeleton   |
| `fpga/rtl/dsp/window_rom.sv`                 | 256 × 16-bit Hann coefficient ROM                 | Skeleton   |
| `fpga/rtl/dsp/fft_256.sv`                    | AXI-Stream FFT wrapper                            | Stub       |
| `fpga/rtl/dsp/ifft_256.sv`                   | AXI-Stream IFFT wrapper                           | Stub       |
| `fpga/rtl/dsp/overlap_add.sv`                | 50% OLA reconstructor                             | Skeleton   |
| `fpga/rtl/dsp/spectral/spectral_proc.sv`     | Per-bin gain + noise gate                         | Skeleton   |
| `fpga/constraints/arty_s7_25.xdc`            | Pin map + timing constraints                      | Reference  |
| `fpga/sim/testbenches/tb_i2s_rx.sv`          | I2S RX testbench                                  | Skeleton   |
| `fpga/sim/testbenches/tb_spi_slave.sv`       | SPI slave testbench                               | Skeleton   |
| `fpga/scripts/build_project.tcl`             | Vivado non-project build                          | Skeleton   |
| `fpga/scripts/sim_i2s_rx.tcl`                | Run tb_i2s_rx                                     | Skeleton   |
| `fpga/scripts/sim_spi_slave.tcl`             | Run tb_spi_slave                                  | Skeleton   |

### ESP32 — C

| File                                          | Purpose                                            | Status   |
|-----------------------------------------------|----------------------------------------------------|----------|
| `firmware/main/main.c`                        | Entry point, FreeRTOS task scheduler               | Skeleton |
| `firmware/components/spi_master/spi_master.h` | SPI driver header                                  | Reference|
| `firmware/components/spi_master/spi_master.c` | SPI driver implementation                          | Skeleton |
| `firmware/components/fpga_config/fpga_config.h` | Register address constants                      | Reference|
| `firmware/components/fpga_config/fpga_config.c` | High-level FPGA API                              | Skeleton |
| `firmware/components/mode_manager/mode_manager.h` | Mode enum, getter/setter                       | Reference|
| `firmware/components/mode_manager/mode_manager.c` | Mode state machine                             | Skeleton |
| `firmware/components/button_handler/button_handler.h` | Button event types                         | Reference|
| `firmware/components/button_handler/button_handler.c` | 3-button debounce                          | Skeleton |
| `firmware/components/audio_driver/audio_driver.h`   | I2S pin map                                | Reference|
| `firmware/components/audio_driver/audio_driver.c`   | I2S master init                            | Skeleton |
| `firmware/components/led_indicator/led_indicator.h` | LED API                                   | Reference|
| `firmware/components/led_indicator/led_indicator.c` | RGB LED driver                            | Stub     |
| `firmware/components/volume_ctrl/volume_ctrl.h`     | Volume API                                 | Reference|
| `firmware/components/volume_ctrl/volume_ctrl.c`     | Volume control                             | Skeleton |
| `firmware/components/profile_store/profile_store.h` | NVS API                                    | Reference|
| `firmware/components/profile_store/profile_store.c` | NVS persistence                            | Skeleton |
| `firmware/components/telemetry/*`                   | FPGA status polling (Phase 2)             | Stub     |
| `firmware/components/battery_mon/*`                 | Battery sense (Phase 3)                   | Stub     |
| `firmware/components/bt_audio/*`                    | Bluetooth A2DP (Phase 3)                  | Stub     |

### Tools — Python

| File                                                  | Purpose                              | Status   |
|-------------------------------------------------------|--------------------------------------|----------|
| `tools/win_gen/gen_hann_coeffs.py`                    | 256-pt Hann Q2.14 hex generator      | Complete |
| `tools/profile_gen/gen_gain_profile.py`               | Audiogram → 128-bin gain table       | Skeleton |
| `tools/profile_gen/gen_default_tables.py`             | General/Hearing/Speech default tables| Skeleton |
| `tools/fft_gen/gen_fft.py`                            | dblclockfft wrapper (stub)           | Stub     |

---

## 5. College Application Milestones

The following points are natural places to pause and document progress
for college applications. Each milestone produces one or more artifacts
listed in `docs/college_app/`.

| Milestone | Phase | Artifacts                                    |
|-----------|-------|----------------------------------------------|
| Toolchain works end-to-end           | 0   | Initial commit on GitHub                    |
| FPGA blinks, you understand MMCMs    | 1   | Short blog post + photo of LED blinking     |
| SPI link works                       | 2   | Essay: *"Debugging a 4-wire protocol"*      |
| Audio passthrough                    | 3   | Demo video: *"Hello from the FPGA"*         |
| **MVP: FFT-based audio processor**   | 4   | **Headline demo video + technical report**  |
| Three modes + persistence            | 5   | Updated demo + portfolio site               |
| Bluetooth + DRC                      | 6   | Publication-quality paper                   |

---

## 6. Risk Mitigation

### Identified risks

1. **Toolchain install (Vivado)** — Vivado is large (~50 GB) and licensing
   can be slow. **Mitigation:** start the download in Phase 0; if WebPack
   license fails, fall back to Symbiflow (limited but works for XC7S25).
2. **LUT budget overflow** — the FFT + spectral processing can exceed
   14,600 LUTs. **Mitigation:** in Phase 4, post a checkpoint where
   utilization is reviewed; if >90%, switch to 12-bit data or
   resource-shared FFT/IFFT.
3. **Timing closure at 96 MHz** — the DSP path is tight. **Mitigation:**
   drop to 64 MHz; use registered multipliers; pipeline aggressively.
4. **FFT IP integration** — Xilinx xfft IP has a learning curve.
   **Mitigation:** in Phase 4, use the simplest config (pipelined
   streaming I/O) and avoid advanced features (CORDIC, etc.) for MVP.
5. **I2S audio quality** — debugging audio issues is hard. **Mitigation:**
   in Phase 3, test with a known-good tone first; if the FPGA pass-through
   sounds bad, simplify the BCLK/LRCLK path before debugging anything
   else.
6. **Schedule slip** — a high school student has school, AP exams,
   activities, etc. **Mitigation:** aim for "MVP by end of summer" rather
   than "complete device"; the MVP (Phase 4) is sufficient for college
   applications.
7. **Part availability** — INMP441 and PCM5102A can be out of stock.
   **Mitigation:** Phase 1–2 do not require them; only Phase 3 does.
   Order the parts in Phase 2 so they arrive by Phase 3.

### Go / no-go checkpoints

| Checkpoint | Phase | Decision                                                        |
|------------|-------|-----------------------------------------------------------------|
| Vivado bitstream generates successfully          | 0  | If not: try Symbiflow or Vivado Lab Edition                  |
| FPGA + ESP32 + SPI link reliable                 | 2  | If not: fall back to bit-bang GPIO, or fix wiring             |
| Round-trip audio clear                           | 3  | If not: simplify pipeline; check I2S polarity                |
| **MVP: FFT passthrough audibly transparent**     | 4  | **If yes: this is a strong college-app artifact. STOP HERE if you need more time for applications.** |
| All three modes working                          | 5  | If not: ship with General + one other mode                   |
| Bluetooth, DRC, telemetry                        | 6  | Optional polish                                               |

---

## Next Steps

1. Read this entire document (it should take ~30 min).
2. Set up the toolchain (Phase 0). Start the Vivado download immediately —
   it's the long pole.
3. Order hardware: Arty S7-25, ESP32 DevKit v1, INMP441, PCM5102A,
   breadboard, jumpers.
4. Open `fpga/rtl/top.sv` and read it through. Open the package file
   (`auris_pkg.sv`) and internalize the register map. From there, follow
   the data flow: I2S RX → buffer → window → FFT → spectral → IFFT → OLA →
   I2S TX.
5. After every phase, write a phase report in `docs/phase_reports/`.
6. When you hit Phase 4, record the demo video. That's your headline.

Good luck — this is a great project. Keep the code clean, commit often,
and write things down. The artifacts you produce along the way
(diagrams, reports, videos) are the actual deliverable for college
applications, not just the working device.
