# Development Roadmap

> **Project Auris** — 6-phase development plan from toolchain to demo.
> **Last updated:** 2026-07
> **Status:** Authoritative summary of the 6-phase plan. The full
> source of truth (per-phase file map, build commands, go/no-go
> checkpoints) is in [`docs/IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md).
> Per-phase reflections live in [`docs/phase_reports/`](phase_reports/).

This document is a one-page summary of *what we are building, in what
order, and what "done" looks like for each step*. It is meant for
three audiences: (1) the author, who needs a checklist, (2) a
collaborator, who needs a 5-minute onboarding, and (3) a college
admissions reader, who needs to see that the project is well-scoped
and well-progressed. The detailed risk register in §4 is the second
most-important section; it is the place where the project's honesty
about its limitations lives.

---

## 1. Phase Summary

| Phase | Name | Goal | Status | Key Deliverables |
|-------|------|------|--------|------------------|
| **0** | Toolchain Setup | Vivado + ESP-IDF + Python toolchain working end-to-end | 🔧 In Progress | Blink LED on the FPGA, MMCM lock verified, ESP32 "hello world" serial output, all tools build with `make all` |
| **1** | I2S Audio Loopback | Audio flows mic → FPGA → DAC, with no DSP yet | ⬜ Planned | I2S RX → I2S TX passthrough, hear audio in headphones, `REG_I2S_LOCKED` status bit set, round-trip latency < 1 ms (Bypass mode) |
| **2** | FFT Pipeline | 256-pt FFT + IFFT + Hann overlap-add working | ⬜ Planned | Spectral analysis visible in an ILA waveform, reconstruction audibly transparent in Bypass, end-to-end latency ~5.33 ms |
| **3** | Spectral Processing | Per-bin gain tables + noise gate working in all three modes | ⬜ Planned | General (flat 1.0), Hearing (audiogram-derived), Speech (noise-gated + speech-band boost) modes all audibly distinct, `REG_MODE` switching works, gain table writes via SPI |
| **4** | ESP32 Control | ESP32 fully controls the FPGA over SPI; BLE and buttons operational; NVS persistence | ⬜ Planned | Full system integration: mode change by button or BLE, volume control, profile persistence across reboots, telemetry polling at 1 Hz |
| **5** | Enclosure + Demo | 3D-printed case, polished demo material, ready to ship | ⬜ Planned | Portable device, printed block diagram + BOM, demo video, technical report, college-application material |

> **Status icons:** 🔧 In Progress · ✅ Complete · ⬜ Planned · ⏸ Paused · ❌ Cancelled

### 1.1 Phase 0 detail (the current phase)

Phase 0 is the only phase that has started. The state of the world
at the time of this writing:

- ✅ Repository skeleton committed (all top-level directories,
  `README.md`, `LICENSE`, `CONTRIBUTING.md`, `CODEOWNERS`,
  `CITATION.cff`)
- ✅ All FPGA RTL stub files in place under `fpga/rtl/` with
  header comments
- ✅ All ESP32 firmware component files in place under
  `firmware/components/`
- ✅ All Python tool files in place under `tools/`
- ✅ Architecture documentation complete: `block_diagram.md`,
  `dsp_pipeline.md`, `clock_domains.md`, `firmware_arch.md`,
  `register_map.md`, `resource_budget.md`
- ✅ Implementation plan committed
- ⬜ Vivado 2024.1+ installed and licence verified
- ⬜ ESP-IDF v5.2+ installed and `idf.py build` works on
  hello-world
- ⬜ FPGA bitstream generates and programs the Cmod S7-25
- ⬜ ESP32 firmware flashes and produces serial output

The exit criteria for Phase 0 are: `make all` succeeds end-to-end,
the FPGA blinks an LED at 1 Hz from a divided MMCM clock, and the
ESP32 prints "Aur is alive" on the serial monitor.

---

## 2. Detailed Milestones

The following subsections expand each phase into **entry criteria**,
**tasks** (a checklist), **exit criteria**, and **estimated
duration**. The exit criteria are the *contracts* with the next
phase: when the next phase begins, every line in the previous
phase's exit criteria must be true.

### 2.1 Phase 0 — Toolchain Setup

**Entry criteria:** none (this is the first phase).

**Tasks:**

- [ ] Install Vivado 2024.1+ (WebPack / free edition; sufficient
  for the XC7S25 device on the Cmod S7-25). Verify license.
- [ ] Install ESP-IDF v5.2+ with the ESP32 toolchain on `PATH`.
  Run `idf.py create-project` on a hello-world; confirm
  `idf.py build` produces a `.bin` file.
- [ ] Install Python 3.9+ and the dependencies in
  `tools/requirements.txt` (numpy, scipy, pyyaml, matplotlib).
- [ ] Run `make tools`; confirm the Hann coefficients and default
  gain tables generate without errors.
- [ ] Run `make fpga`; confirm a bitstream is produced under
  `fpga/vivado_workspace/auris_cmod.runs/impl_1/top.bit`.
- [ ] Run `make esp`; confirm the ESP32 firmware builds.
- [ ] Program the FPGA with the bitstream; verify the LED blinks
  at 1 Hz (heartbeat in `status_mon.sv`).
- [ ] Flash the ESP32; verify the serial monitor prints "Auris
  alive" at 115200 baud.
- [ ] Commit the working directory tree to GitHub.

**Exit criteria:**

- `make all` runs both Vivado and ESP-IDF end-to-end without
  errors.
- The FPGA LED blinks at exactly 1 Hz (verified with a phone
  stopwatch).
- The ESP32 serial monitor prints "Auris alive" within 5 seconds
  of reset.
- The Git repository has at least 5 commits showing progressive
  work.

**Estimated duration:** 1 week (40 hours of focused work).

**Go / no-go checkpoint:** if Vivado install fails or license
issues arise, consider the open-source Symbiflow toolchain as a
fallback (limited support for Spartan-7; this is a real risk, do
not skip the checkpoint).

---

### 2.2 Phase 1 — I2S Audio Loopback

**Entry criteria:** all of Phase 0's exit criteria are met.

**Tasks:**

- [ ] Order and receive: INMP441, PCM5102A, breadboard, jumper
  wires (per [`docs/hardware/BOM.md`](hardware/BOM.md)).
- [ ] Wire the INMP441 and PCM5102A to the Cmod S7-25 Pmod JB
  and Pmod JC (per [`docs/hardware/WIRING.md`](hardware/WIRING.md)).
- [ ] Implement `i2s_rx.sv` and `i2s_tx.sv` in SystemVerilog.
- [ ] Implement `cdc_i2s_to_dsp.sv` and `cdc_dsp_to_i2s.sv`
  with the Gray-coded async FIFO pattern from
  [`docs/architecture/clock_domains.md`](architecture/clock_domains.md) §2.
- [ ] Implement `audio_driver.c` on the ESP32: I2S master,
  BCLK = 3.072 MHz, LRCLK = 48 kHz.
- [ ] Write `tb_i2s_rx.sv` testbench; verify with
  `vivado -mode batch -source fpga/scripts/sim_i2s_rx.tcl`.
- [ ] Run `top.sv` with the DSP pipeline bypassed (write
  `MODE_BYPASS` to `REG_MODE`, or set `REG_CONTROL.bypass` to 1).
  Speak into the mic; hear audio in the headphones.
- [ ] Verify `REG_I2S_LOCKED` (status bit in `REG_STATUS`) reads
  as 1.

**Exit criteria:**

- Round-trip audio (mic → headphones) is audible and clear in
  Bypass mode.
- Latency in Bypass mode is < 1 ms (one CDC FIFO + I2S
  pipeline delay; no DSP latency yet).
- `REG_I2S_LOCKED` reads as 1; `REG_MODE = MODE_BYPASS`
  (or `REG_CONTROL.bypass = 1`) produces audible audio;
  `REG_MODE = MODE_GENERAL` (or `REG_CONTROL.bypass = 0`) produces
  silence.
- I2S signals verified on oscilloscope: BCLK = 3.072 MHz
  ±0.1 %, LRCLK = 48 kHz ±0.1 %.

**Estimated duration:** 2–3 weeks.

**Go / no-go checkpoint:** if round-trip audio is distorted or
missing, suspect: LRCLK polarity (INMP441 vs PCM5102A
conventions differ), BCLK not exactly 3.072 MHz, or I2S RX/TX
swap (left vs right alignment). See
[`docs/DEMO_PLAN.md`](DEMO_PLAN.md) §4.3 for the diagnostic
flowchart.

**Risk:** the INMP441 has been discontinued; the project's
preferred substitute is the SPH0645 (Knowles), which is
pin-compatible.

---

### 2.3 Phase 2 — FFT Pipeline

**Entry criteria:** all of Phase 1's exit criteria are met.

**Tasks:**

- [ ] Generate the FFT IP (`fft_256.xci`) using the Vivado IP
  catalog. Settings: pipelined streaming I/O, 256-pt, 16-bit
  data, block-floating-point (BFP) scaling, radix-2/burst I/O.
- [ ] Generate the IFFT IP with the same configuration
  (`ifft_256.xci`).
- [ ] Run `gen_hann_coeffs.py` to produce
  `fpga/generated/hann_256.hex`, `hann_256.coe`, `hann_256.txt`.
- [ ] Implement `window_apply.sv` and `window_rom.sv`. Wire to
  the FFT input.
- [ ] Implement `input_buffer.sv` and `output_buffer.sv` as
  ping-pong BRAM.
- [ ] Implement `overlap_add.sv` (50 % OLA, COLA-validated by
  `tools/validation/check_cola.py`).
- [ ] Wire `dsp_pipeline.sv` to `top.sv`.
- [ ] Update `mode_ctrl.sv` so `MODE_GENERAL` loads a flat
  gain table.
- [ ] Pass all testbenches in `fpga/sim/testbenches/`.

**Exit criteria:**

- Bitstream + firmware processes audio through the FFT pipeline
  with flat gain (1.0 across all 128 bins).
- Resource utilisation: ≤ 9,000 LUTs, ≤ 50 DSP48E1s, ≤ 30 BRAMs.
- Speaking into the mic produces audibly transparent output
  in General mode (no coloration compared to Bypass).
- ILA waveform of the FFT input and output shows a clean
  time-frequency decomposition.

**Estimated duration:** 3–4 weeks.

**Go / no-go checkpoint:** if the LUT budget is exceeded
(> 95 % post-route), switch to 12-bit FFT data (halves the LUTs,
loses ~6 dB of SNR), or share the FFT and IFFT (saves ~1,500
LUTs, adds a multiplexer). If timing fails at 96 MHz, drop the
DSP clock to 64 MHz (latency increases by 50 % but is still
acceptable).

**MVP checkpoint:** the moment General mode is audibly
transparent, the project is **MVP-complete**. This is the
headline college-application artifact; the demo video should
be recorded at this point.

---

### 2.4 Phase 3 — Spectral Processing

**Entry criteria:** all of Phase 2's exit criteria are met.

**Tasks:**

- [ ] Run `tools/profile_gen/gen_default_tables.py` to generate
  the three default gain tables (General, Hearing, Speech).
- [ ] Implement `spectral_proc.sv` with per-bin gain and noise
  gate (Q2.14 arithmetic; 128 bins).
- [ ] Implement `mode_ctrl.sv` so each mode loads the correct
  default gain table into the inactive spectral-proc bank,
  then commits the bank.
- [ ] Update the ESP32 firmware to expose the indirect gain-table
  access (`REG_GAIN_ADDR`, `REG_GAIN_DATA`, `REG_GAIN_BANK`,
  `REG_GAIN_COMMIT`) to the application layer.
- [ ] Add the `noise_gate` module to `spectral_proc.sv` (zero
  bins below `REG_NOISE_FLOOR`; the soft-knee ratio is
  `REG_NOISE_GATE_RATIO`).
- [ ] Add a per-bin "smoothed gain" path that cross-fades between
  the two gain-table banks during a commit, to suppress the
  remaining click on a hard bank swap.
- [ ] Add the Hearing mode's "blend" between the user's
  audiogram and the default table (configurable in NVS).
- [ ] Run the frequency-response measurement per
  [`docs/MEASUREMENT_METHODOLOGY.md`](MEASUREMENT_METHODOLOGY.md) §4
  in all four modes (Bypass, General, Hearing, Speech).

**Exit criteria:**

- All three listening modes (General, Hearing, Speech) are
  audibly distinct on a normal-hearing listener.
- The Hearing mode's frequency response matches the
  audiogram-derived gain table to within ±2 dB at every bin
  centre.
- The Speech mode's noise gate zeroes bins below
  `REG_NOISE_FLOOR = 0x0100` (≈ –48 dBFS).
- The mode can be switched at runtime via SPI write to
  `REG_MODE`; the spectral-proc bank-swap is glitch-free
  (no audible click on transition).
- Phase 2's resource utilisation is still within budget
  (≤ 9,000 LUTs, ≤ 50 DSP48E1s, ≤ 30 BRAMs).

**Estimated duration:** 2–3 weeks.

**Go / no-go checkpoint:** if the Hearing mode's effect is not
audible, the gain table is probably under-scaled; check the
output of `gen_default_tables.py` and verify the indirect SPI
writes to `REG_GAIN_ADDR` / `REG_GAIN_DATA` and the
`REG_GAIN_COMMIT` that activates the new bank. If the Speech
mode's noise gate is chattering on and off, raise `REG_NOISE_FLOOR`
or add a longer hold-time in `spectral_proc`.

---

### 2.5 Phase 4 — ESP32 Control + BLE

**Entry criteria:** all of Phase 3's exit criteria are met.

**Tasks:**

- [ ] Implement `button_handler.c` with 3-button debounce
  (short-press cycles modes, long-press enters Bypass, volume
  up/down).
- [ ] Implement `volume_ctrl.c` with 0..31 steps, 2 dB per
  step, persisting to NVS via `profile_store.c`.
- [ ] Implement `profile_store.c` (NVS persistence; 3 default
  tables + 1 user-customisable table; 500 ms write-coalesce).
- [ ] Implement `telemetry.c` (1 Hz polling of `REG_STATUS`,
  `REG_PEAK_LEVEL`, `REG_OUT_PEAK`, `REG_FRAME_COUNT_L`,
  `REG_FRAME_COUNT_H`, `REG_ERROR_FLAGS`).
- [ ] Implement `battery_mon.c` (ADC sampling, low/critical
  thresholds, event-group signalling).
- [ ] Implement `bt_audio.c` (BLE GATT server with
  `auris_mode`, `auris_volume`, `auris_gain_table`,
  `auris_battery`, `auris_status` characteristics; see
  [`docs/architecture/firmware_arch.md`](architecture/firmware_arch.md) §6
  for the GATT service definition).
- [ ] Implement the device state machine in `main.c`
  (BOOT, GENERAL, HEARING, SPEECH, BYPASS, ERROR, SHUTDOWN)
  with the LED pattern from
  [`docs/architecture/firmware_arch.md`](architecture/firmware_arch.md) §3.2.
- [ ] Run the latency, SNR, and THD measurements from
  [`docs/MEASUREMENT_METHODOLOGY.md`](MEASUREMENT_METHODOLOGY.md)
  in all four modes.

**Exit criteria:**

- Mode change works by short button press; cycles
  GENERAL → HEARING → SPEECH → GENERAL.
- Long button press enters Bypass; short press from Bypass
  returns to GENERAL.
- Volume up / volume down buttons change the master volume
  in 2 dB steps; the change persists across a power cycle.
- A phone running nRF Connect or LightBlue can connect to
  "ProjectAuris" and change mode / volume / individual
  frequency bins over BLE.
- Telemetry: serial monitor shows live `peak_in`, `peak_out`,
  `frame_count` updating at 1 Hz.
- Battery monitor: low-battery LED pattern engages when the
  ADC reading falls below 3.3 V.

**Estimated duration:** 4–5 weeks.

**Go / no-go checkpoint:** if BLE pairing fails repeatedly,
fall back to button-only control (the audio path still works
without BLE). If NVS persistence is unreliable, increase the
`profile_task` debounce from 500 ms to 2 s (trades write
amplification for reliability).

---

### 2.6 Phase 5 — Enclosure + Demo

**Entry criteria:** all of Phase 4's exit criteria are met.

**Tasks:**

- [ ] Design a custom PCB (KiCad, 2-layer, 50 mm × 70 mm) that
  integrates the Cmod S7-25 (as a daughter board), the ESP32
  (as a daughter board), the INMP441, the PCM5102A, the
  buttons, the LEDs, the battery, and the 3.5 mm jacks.
- [ ] Order the PCBs from JLCPCB or PCBWay (5 units, ~$20
  plus shipping).
- [ ] Design and 3D-print a two-piece enclosure (top + bottom)
  that holds the PCB, exposes the 3.5 mm jacks, the buttons,
  the LEDs, and a USB-C charging port.
- [ ] Solder and test the first assembled unit end-to-end.
- [ ] Write the IEEE-format technical report (see
  [`docs/college_app/README.md`](college_app/README.md) §4
  for the outline).
- [ ] Record the 3-minute demo video per
  [`docs/DEMO_PLAN.md`](DEMO_PLAN.md) §3.
- [ ] Update the GitHub repository with the polished
  documentation, the BOM, the photos, the measurement logs.
- [ ] Run the full measurement suite from
  [`docs/MEASUREMENT_METHODOLOGY.md`](MEASUREMENT_METHODOLOGY.md)
  on the final assembled unit; commit the results as a
  release.

**Exit criteria:**

- A fully-assembled, 3D-enclosed, battery-powered prototype
  is functional.
- The full measurement suite (latency, frequency response,
  SNR, power, THD) passes the "good" criteria in all four
  modes.
- The demo video is 2–3 minutes long, follows the §3 script,
  and is uploaded to YouTube (unlisted) and embedded in the
  GitHub README.
- The technical report is in IEEE format, 6 pages, and
  includes a measurement-results table.
- The college-application artifact checklist in
  [`docs/college_app/README.md`](college_app/README.md) §2
  is complete.

**Estimated duration:** 3–4 weeks.

**Go / no-go checkpoint:** this phase has no internal
checkpoints; the deliverable is binary. If the deadline is
tight, prioritise: PCB + enclosure first, technical report
second, demo video third.

---

## 3. Cumulative Timeline

A rough Gantt chart of the six phases, assuming a single
contributor working part-time (~10 hours/week, typical of a
high-school student with school, AP exams, and activities):

| Phase | Months 1–2 | Month 3 | Months 4–5 | Month 6 | Months 7–9 | Months 10–12 |
|-------|------------|---------|------------|---------|------------|--------------|
| 0     | ████       |         |            |         |            |              |
| 1     |            | ███     |            |         |            |              |
| 2     |            | ██      | ████       |         |            |              |
| 3     |            |         | ██         | ██      |            |              |
| 4     |            |         |            | ██      | ███        |              |
| 5     |            |         |            |         | ██         | ███          |

This is an **aggressive** schedule. The MVP (Phase 2 exit)
should land in the first half of the timeline; the rest of the
project is polish. The MVP is the college-application
deliverable; the rest is "nice to have" and should be cut if
the deadline is tight. See
[`docs/IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) §6 for
the corresponding go/no-go checkpoints.

### 3.1 Critical path

The critical path (the chain of dependencies that determines the
end date) runs through:

**Phase 0 toolchain → Phase 2 FFT pipeline (MVP) → Phase 5
demo material → college application deadline.**

The non-critical paths (Phase 1 I2S loopback, Phase 3 spectral
processing, Phase 4 BLE) can be done in parallel or
re-ordered if necessary. The MVP (Phase 2) is the absolute
hard deadline; everything else is bonus.

---

## 4. Risk Register

The following risks have been identified, with their probability,
impact, mitigation, and current status. New risks should be
appended to the bottom of the table as they are identified. The
risk register is reviewed at the end of every phase; see
[`docs/phase_reports/`](phase_reports/).

| # | Risk | Probability | Impact | Mitigation | Status |
|---|------|-------------|--------|------------|--------|
| R-01 | INMP441 discontinued; price spikes or stock-out | Medium | High | Identify drop-in alternatives (SPH0645, ICS-43434); order a lifetime supply of the INMP441 as soon as Phase 1 is approved | Open |
| R-02 | FFT IP resource usage exceeds the XC7S25 LUT budget | Medium | High | Drop to 12-bit FFT data (halves the LUTs, loses ~6 dB SNR), or share the FFT and IFFT (saves ~1,500 LUTs, adds a multiplexer); optimise the spectral processor for one-bin-at-a-time | Open |
| R-03 | SPI timing violations at 10 MHz (ESP32 → FPGA) | Low | Medium | Add 2-FF synchronizers on the data path (already in `cdc_spi_to_dsp.sv`); reduce the SPI clock to 5 MHz if violations persist | Mitigated (CDC in place) |
| R-04 | BLE pairing issues with iOS / Android devices | Low | Low | Fallback to button-only control; BLE is a user-experience enhancement, not part of the audio path | Open |
| R-05 | Power budget exceeded (USB 2.0's 500 mA / port) | Low | Medium | Measure early in Phase 0 (per [`docs/MEASUREMENT_METHODOLOGY.md`](MEASUREMENT_METHODOLOGY.md) §6); optimise the FPGA's clock gating; consider clock-gating the IFFT in Bypass mode | Open |
| R-06 | End-to-end latency exceeds 10 ms (above the 20 ms threshold) | Low | High | Profile the pipeline (per [`docs/MEASUREMENT_METHODOLOGY.md`](MEASUREMENT_METHODOLOGY.md) §3); reduce the FFT length to 128 if the budget is breached; reduce the OLA overlap from 50 % to 25 % (halves the latency, costs spectral resolution) | Open |
| R-07 | Toolchain install issues (Vivado WebPack licence failures, ESP-IDF version mismatches) | Medium | Medium | Use a documented Docker image with both toolchains pre-installed; archive the working toolchain versions in a `tools/toolchain_versions.txt` file | Open |
| R-08 | Hearing mode's effect is not audible to normal-hearing listeners | Medium | Medium | The default Hearing table is designed to compensate for a 40 dB high-frequency loss; a normal-hearing listener should still hear a slight high-frequency boost. If not, scale the gain table up by 6 dB and re-test. | Open |
| R-09 | Custom PCB (Phase 5) has a wiring error | Medium | Medium | Order 5 PCBs (volume pricing); use the first unit as a "smoke test" (power it up without the FPGA, verify rails); bench-test each subsystem before the full integration test | Open |
| R-10 | Schedule slip (school, AP exams, extracurriculars) | High | Medium | Aim for the MVP (Phase 2 exit) by the college-application deadline; treat Phases 3–5 as "post-application" work | Acknowledged |
| R-11 | I2S codec pipeline delay exceeds the 1 ms assumption | Low | Low | Both INMP441 and PCM5102A datasheets specify < 1 ms each; if observed otherwise, switch to PCM5101 (lower pipeline delay) | Open |
| R-12 | Ground loops in the breadboard prototype cause hum | Medium | Low | Power the breadboard from a single USB port; use a USB isolator if necessary; the final PCB will share a single ground plane | Open |

### 4.1 Risk review cadence

The risk register is reviewed:

- At the end of every phase (formally, in the phase report)
- After every measurement session that produces a red flag
  (e.g., latency above 10 ms, SNR below 55 dB)
- At every go / no-go checkpoint (see
  [`docs/IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) §6)

A risk is closed when its mitigation is implemented and
verified. A risk is escalated when its probability or impact
increases. The status column reflects the *current* state, not
the original assessment.

---

## 5. Where to Read Next

- The full source-of-truth plan (per-phase file map, build
  commands, validation steps, go/no-go checkpoints) is in
  [`docs/IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md).
- The architecture documents that describe what each phase
  builds are in [`docs/architecture/`](architecture/).
- The phase reports (filled in at the end of each phase) are
  in [`docs/phase_reports/`](phase_reports/).
- The measurement methodology that defines "done" for each
  phase's exit criteria is in
  [`docs/MEASUREMENT_METHODOLOGY.md`](MEASUREMENT_METHODOLOGY.md).
- The demo plan that defines "done" for Phase 5 is in
  [`docs/DEMO_PLAN.md`](DEMO_PLAN.md).
- The college-application framing (essay topics, artifact
  checklist, technical report outline) is in
  [`docs/college_app/README.md`](college_app/README.md).
- The design decision log that justifies the technology
  choices is in [`docs/DESIGN_DECISIONS.md`](DESIGN_DECISIONS.md).
