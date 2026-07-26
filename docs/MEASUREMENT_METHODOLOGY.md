# Measurement Methodology

> **Project Auris** — Quantitative evaluation of the FPGA-accelerated
> hearing-assistive device.
> **Last updated:** 2026-07
> **Status:** Authoritative for the measurement procedures and pass/fail
> criteria. Live measurement logs are committed under
> `docs/MEASUREMENT_METHODOLOGY/measurements/` (one CSV per session) and
> the analysis scripts live under `tools/`.

This document specifies *how* to evaluate a Project Auris prototype.
The goal is to produce measurements that are **reproducible** (anyone
with the equipment can redo them), **documented** (the result has a
date, a setup, and a known source of error), and **comparable**
(the pass/fail criteria in §3–§8 are stable across prototypes).

The five primary measurements are: **latency**, **frequency response**,
**signal-to-noise ratio**, **power consumption**, and **total harmonic
distortion**. Each is described in its own section with a procedure
(steps the experimenter follows), a pass/fail criterion, and the
expected value. A measurement log template is provided in §9.

For an architectural understanding of what is being measured, see
[`docs/architecture/block_diagram.md`](architecture/block_diagram.md)
and [`docs/architecture/dsp_pipeline.md`](architecture/dsp_pipeline.md).

---

## 1. Overview

### 1.1 What we measure and why

| Measurement | Why it matters | Headline target |
|-------------|----------------|-----------------|
| Latency | A hearing aid above 20 ms is perceptibly delayed. The project is designed for 5.3 ms algorithmic. | < 10 ms total, < 8 ms is good |
| Frequency response | The gain table is the user-facing product. It must match the audiogram-derived shape. | ±3 dB passband in Bypass, ±2 dB to gain table |
| SNR | The INMP441 datasheet promises 61 dB; the system should not lose more than 1 dB. | > 55 dB acceptable, > 60 dB good |
| Power consumption | The device is USB-powered; the 5 V rail must stay within USB's 500 mA budget per port. | < 300 mA total |
| THD | Nonlinearity is audible. | < 1 % acceptable, < 0.5 % good |

Each measurement is also a **diagnostic tool**. A frequency response
that is flat below 100 Hz but rolls off above 1 kHz points at a CDC
FIFO timing issue; a latency that doubles points at a stalled DSP
clock; an SNR that is 10 dB below expectation points at a ground
loop in the breadboard wiring.

### 1.2 The measurement philosophy

- **Always measure Bypass first.** Bypass is the simplest signal
  path; if Bypass is broken, everything else is broken. A 2-minute
  Bypass sanity check before every measurement session catches
  wiring problems before they poison the data.
- **Capture the setup photographically.** A picture of the
  breadboard, the wiring, and the equipment layout is the single
  most useful artifact when reviewing the data later. Save the
  photo with the measurement CSV.
- **Log the environmental conditions.** Temperature (CPU temp of
  the Cmod S7-25 matters for ADC drift), humidity (less so), and
  ambient noise (the SNR measurement is sensitive to acoustic
  noise) belong in the log header.
- **Reject the outliers.** If a measurement is more than 3 σ from
  the mean of 10 trials, re-measure; the prototype is probably
  glitching. Note any rejected points in the log.

---

## 2. Test Equipment

The table below lists the recommended equipment, its purpose, and
the minimum acceptable alternative. The "Required?" column flags
items that are non-negotiable for the headline measurements.

| Equipment | Purpose | Required? | Alternative |
|-----------|---------|-----------|-------------|
| Oscilloscope (100 MHz+, 2 channels minimum, 1 GS/s) | I2S signal verification, latency measurement, power-rail ripple check | Yes | Logic analyzer (no analog bandwidth, harder for latency) |
| Logic analyzer (8+ channels, 24 MHz+, Saleae Logic 8 or clone) | SPI + I2S protocol decode, frame-accurate triggering | Recommended | Oscilloscope + manual protocol decode |
| Audio interface / sound card (Focusrite Scarlett 2i2 or similar, 24-bit, 96 kHz-capable) | Frequency response measurement, acoustic reference | Yes | Onboard laptop sound card (lower SNR; use as a last resort) |
| Audio analyser software (Room EQ Wizard (free), ARTA, or REW) | Frequency response, SNR, THD measurement | Recommended | Python script (`tools/validation/check_freq_response.py`) using `scipy.signal` |
| Multimeter (True-RMS, 0.1 mV resolution, 10 A current range) | Power-consumption measurement on the 5 V rail | Yes | USB inline current meter (less precise, no voltage display) |
| USB inline current meter (e.g., ~~$10 inline USB ammeter) | Live current readout for the demo audience | Optional | Multimeter inline |
| Known audio test files (1 kHz sine, pink noise, speech sample, chirp) | Test signals | Yes | Generate with Python (`tools/test_vector_gen/gen_test_signals.py`) |
| Calibrated measurement microphone (Dayton Audio EMM-6 or Behringer ECM8000) | Acoustic-frequency-response reference | Optional | Use the INMP441 as the reference (cheaper, less accurate) |
| Stopwatch / phone timer | Latency sanity check (round-trip echo timing) | Yes | Oscilloscope + impulse (more accurate) |
| Thermometer or thermal camera (0.1 °C resolution) | Optional: tracks the Cmod S7-25 die temperature during long tests | Optional | Skip; assumes room-temperature operation |

### 2.1 Pre-test setup checklist

1. Power the breadboard from a *separate* USB port than the laptop
   audio interface, to avoid ground loops.
2. Run the Bypass sanity check (§3.1) before any other measurement.
3. Verify the audio interface is set to 24-bit, 48 kHz, no +48 V
   phantom power (the test mics are not phantom-powered).
4. Verify the laptop's Wi-Fi and Bluetooth radios are off (or at
   least the ESP32's BLE stack is suspended) to avoid RF noise on
   the audio measurement.
5. Photograph the setup.

---

## 3. Latency Measurement

### 3.1 Definition

The end-to-end latency is the time from the moment an acoustic event
arrives at the INMP441's diaphragm to the moment the same event is
reproduced at the PCM5102A's output. It is dominated by:

- 1 × frame period of the DSP pipeline (256 samples at 48 kHz) =
  5.33 ms
- 1 × I2S codec pipeline delay (INMP441 + PCM5102A datasheet values,
  typically 1 ms each)
- A small fixed overhead from the CDC FIFOs and the OLA history
  buffer (~50 µs)
- Analog path latency (negligible at audio frequencies)

The total perceived latency is therefore **7–8 ms**, dominated by
the frame-period waiting time. The algorithmic latency (excluding
the analog and I2S codec delays) is **5.33 ms**, set by the FFT
length and the sample rate.

### 3.2 Method

Inject a known impulse (a click or a 1-cycle sine burst) into the
microphone, capture the analog input at the mic's input pin and the
analog output at the DAC's output pin on the oscilloscope, and
measure the time delay between the two.

### 3.3 Equipment

- Oscilloscope (2 channels minimum, 100 MHz+)
- 1-cycle sine burst generator (the laptop's audio output, replayed
  through a small speaker pointed at the INMP441)
- 2 oscilloscope probes (×10, short ground leads)

### 3.4 Procedure

1. **Verify Bypass.** Set `REG_MODE = MODE_BYPASS` (long-press
   the mode button) — or, equivalently, set `REG_CONTROL.bypass`
   (bit 1) to 1. Confirm a hand-clap in front of the mic is audible
   in the headphones with no obvious delay.
2. **Connect probes.** Probe the INMP441's SDOUT line (the analog
   equivalent is the audio at the mic's input pin — easier: probe
   the speaker output feeding the mic). Probe the PCM5102A's
   analog output (left channel, tip of the 3.5 mm jack).
3. **Trigger.** Set the scope to trigger on the input channel,
   single-shot, at a level just above the noise floor.
4. **Inject the impulse.** Play a 1-cycle 1 kHz sine burst from
   the laptop's speaker, held ~30 cm from the INMP441.
5. **Measure.** Use the scope's cursor measurement to read the
   time difference between the input trigger and the output
   waveform's leading edge. Take 10 measurements, average, and
   record the standard deviation.
6. **Repeat for General mode.** Set `REG_MODE = GENERAL` (and
   clear `REG_CONTROL.bypass`). Re-measure; the latency should be
   identical to Bypass (the DSP is engaged but the gain table
   is flat).

### 3.5 Pass / fail criteria

| Tier | Criterion | Notes |
|------|-----------|-------|
| Acceptable | < 10 ms total | The perceptual threshold for headphone delay is 20 ms; 10 ms is a comfortable margin. |
| Good | < 8 ms total | Matches commercial hearing aids. |
| Excellent | < 6.5 ms total | The theoretical minimum (5.33 ms algorithmic + ~1 ms analog). |

A measurement above 10 ms indicates either a CDC FIFO underflow
(the DSP clock has slipped relative to the I2S clock) or an OLA
reconstruction bug. See
[`docs/architecture/dsp_pipeline.md`](architecture/dsp_pipeline.md) §5
for the per-stage latency budget and the troubleshooting guidance.

---

## 4. Frequency Response Measurement

### 4.1 Method

Sweep a sine wave from 20 Hz to 20 kHz through the system, capture
the analog output, and compute the magnitude at each frequency. The
result is the **transfer function** of the device from microphone
input to DAC output. In Bypass mode, the response should be flat; in
General / Hearing / Speech modes, the response should follow the
configured gain table.

### 4.2 Equipment

- Audio interface (input: from the PCM5102A's analog output; output:
  to a small speaker pointed at the INMP441)
- Audio analyser software (REW, ARTA, or
  `tools/validation/check_freq_response.py`)
- Loopback cable (3.5 mm male-to-male, for verifying the audio
  interface's own frequency response)
- Pre-generated chirp or log-sine sweep test file (generate with
  `tools/test_vector_gen/gen_test_signals.py --sweep`)

### 4.3 Procedure

1. **Bypass sanity check.** Same as §3.1.
2. **Audio interface loopback.** Connect the audio interface's
   output to its own input, run the sweep, and save the
   response. This is the *reference* against which the device is
   compared. Subtract it from the device response to remove the
   interface's own colouration.
3. **Switch the device to Bypass.** Sweep 20 Hz – 20 kHz.
   Capture the response. It should be flat (±3 dB) from 100 Hz
   to 18 kHz, with the expected low-frequency roll-off below
   100 Hz (the INMP441's AC-coupling capacitor) and the expected
   high-frequency roll-off above 18 kHz (the INMP441's
   anti-alias filter).
4. **Switch to General mode.** Re-sweep. The response should be
   identical to Bypass (the General gain table is flat 1.0).
5. **Switch to Hearing mode.** Re-sweep. The response should
   show the expected audiogram-derived boost (e.g., +12 dB at
   4 kHz for the default Hearing profile).
6. **Switch to Speech mode.** Re-sweep. The response should
   show the expected speech-band boost (e.g., +6 dB from
   500 Hz to 4 kHz).

### 4.4 Expected behaviour

- **Bypass:** flat (±3 dB) from 100 Hz to 18 kHz.
- **General:** flat (±3 dB) from 100 Hz to 18 kHz, identical to
  Bypass.
- **Hearing:** shaped per the configured gain table, within
  ±2 dB at every bin centre.
- **Speech:** shaped per the configured gain table, with the
  noise gate engaged above 4 kHz (i.e., quiet input → near-zero
  output above 4 kHz; loud input → full gain above 4 kHz).

### 4.5 Pass / fail criteria

| Tier | Criterion |
|------|-----------|
| Acceptable | Bypass and General are flat within ±3 dB in the passband (100 Hz – 18 kHz). |
| Good | Same, within ±2 dB. |
| Excellent | Same, within ±1 dB, AND the Hearing / Speech modes match the gain table to within ±1 dB at every bin centre. |

A failure in Bypass is almost always an analog issue (wiring,
grounding, codec pipeline). A failure in Hearing / Speech is
usually a gain-table loading problem (check the indirect SPI
writes to `REG_GAIN_ADDR` / `REG_GAIN_DATA` and the
`REG_GAIN_COMMIT` that activates the new bank; see
[`docs/architecture/register_map.md`](architecture/register_map.md) §3).

---

## 5. Signal-to-Noise Ratio (SNR) Measurement

### 5.1 Method

Measure the device's output when the input is a known signal (a
1 kHz sine at –6 dBFS), then measure the output when the input is
quiet (a quiet room, the speaker muted). Compute the ratio.

### 5.2 Formula

```
SNR_dB = 20 * log10(V_signal / V_noise)
```

Where `V_signal` is the RMS voltage of the output with the 1 kHz
input, and `V_noise` is the RMS voltage of the output with the
input muted (in the same frequency band, ideally 20 Hz – 20 kHz).

### 5.3 Equipment

- Audio interface (24-bit, 48 kHz)
- Audio analyser software (REW, ARTA, or a Python script)
- 1 kHz sine test file (generate with
  `tools/test_vector_gen/gen_test_signals.py --tone 1000`)
- A way to mute the speaker (a physical mute switch, or
  unplugging it)

### 5.4 Procedure

1. **Bypass sanity check.** Same as §3.1.
2. **Play the 1 kHz sine** at –6 dBFS through the speaker, ~30 cm
   from the INMP441. Capture 10 seconds of output.
3. **Measure the signal RMS.** Use the analyser to find the RMS
   amplitude of the captured output. This is `V_signal`.
4. **Mute the speaker** (do NOT stop the playback; the INMP441
   should still be powered, but the acoustic input is now the
   ambient room noise). Capture 10 seconds of output.
5. **Measure the noise RMS.** Use the analyser to find the RMS
   amplitude of the captured output. This is `V_noise`. Apply an
   A-weighting filter to the noise measurement to match
   human-perceived noise.
6. **Compute SNR.** Apply the formula in §5.2.

### 5.5 Pass / fail criteria

| Tier | Criterion | Notes |
|------|-----------|-------|
| Acceptable | > 55 dB | Limited by the INMP441's 61 dB datasheet SNR; the 6 dB margin is for the FPGA + DAC contribution. |
| Good | > 60 dB | Within 1 dB of the INMP441's theoretical limit. |
| Excellent | > 62 dB | If achieved, the FPGA and DAC are adding negligible noise (likely measurement-floor limited). |

A low SNR (e.g., 40 dB) almost always indicates a **ground loop** in
the breadboard (the laptop's USB and the audio interface's USB
sharing a ground), a noisy I2S clock, or a gain-table error pushing
the output into the noise floor.

---

## 6. Power Consumption Measurement

### 6.1 Method

Measure the current draw on each power rail (ESP32 USB, Cmod S7-25
USB) in each operating mode (Bypass, General, Hearing, Speech).
The total power consumption is the sum of the two rails.

### 6.2 Equipment

- USB inline current meter (one per rail; or a multimeter inline
  with one of the USB cables)
- Multimeter (True-RMS, 0.1 mV resolution) for the voltage
  measurement on the 5 V rail (to compute the power)

### 6.3 Procedure

1. **Bypass sanity check.** Same as §3.1.
2. **Measure ESP32 rail.** Insert the inline current meter between
   the laptop and the ESP32's micro-USB cable. Read the current
   in Bypass mode. Record.
3. **Measure FPGA rail.** Insert the inline current meter between
   the laptop and the Cmod S7-25's USB cable. Read the current
   in Bypass mode. Record.
4. **Repeat for each mode.** Switch to General, Hearing, and
   Speech modes; record the current on each rail in each mode.
5. **Compute power.** P = V × I. With a 5 V rail, P_W = 5 ×
   I_A. Total power is the sum of the two rails.

### 6.4 Expected behaviour

| Mode | ESP32 (mA) | FPGA (mA) | Total (mA) | Total (W) |
|------|------------|-----------|------------|-----------|
| Bypass | ~80 | ~120 | ~200 | ~1.00 |
| General | ~80 | ~150 | ~230 | ~1.15 |
| Hearing | ~80 | ~150 | ~230 | ~1.15 |
| Speech | ~80 | ~150 | ~230 | ~1.15 |

The FPGA current is higher in DSP-active modes because the FFT and
IFFT are running. The Bypass current is lower because the DSP
pipeline is in clock-gated reset.

### 6.5 Pass / fail criteria

| Tier | Criterion |
|------|-----------|
| Acceptable | < 300 mA total. USB 2.0 ports are rated for 500 mA; 300 mA is a safe margin. |
| Good | < 250 mA total. Leaves headroom for the BLE radio and the status LEDs. |
| Excellent | < 200 mA total. Implies the FPGA is doing aggressive clock gating in idle modes. |

A power consumption significantly above 300 mA is a red flag for
either a short circuit (check the breadboard wiring) or an
inefficient FPGA implementation (e.g., the MMCM is not in bypass
when idle).

---

## 7. Total Harmonic Distortion (THD) Measurement

### 7.1 Method

Apply a 1 kHz sine wave at –6 dBFS to the system, capture the
output, compute the FFT, and read the magnitudes of the harmonics
(2 kHz, 3 kHz, 4 kHz, ...). THD is the ratio of the harmonic
power to the fundamental power, expressed as a percentage.

### 7.2 Formula

```
THD = (sqrt(V_2² + V_3² + ... + V_n²) / V_1) × 100%
```

Where `V_k` is the RMS voltage of the k-th harmonic of the
fundamental, and `V_1` is the RMS voltage of the fundamental. In
practice, harmonics above the 5th or so are negligible for a
well-designed audio system; the sum is typically truncated at
k = 5 or k = 10.

### 7.3 Equipment

- Audio interface (24-bit, 48 kHz)
- 1 kHz sine test file (the same one used in §5)
- Audio analyser software (REW, ARTA, or a Python FFT script)

### 7.4 Procedure

1. **Bypass sanity check.** Same as §3.1.
2. **Play the 1 kHz sine** at –6 dBFS through the speaker.
   Capture 10 seconds of output.
3. **Compute the FFT** of the captured output (use a window
   function, e.g., Hann, and a length that gives 1 Hz bin
   resolution, e.g., 48000 samples = 1 second).
4. **Read the harmonic magnitudes.** The fundamental is at bin
   1000; the 2nd harmonic is at bin 2000, the 3rd at bin 3000,
   etc.
5. **Apply the THD formula.** Sum the harmonic magnitudes, divide
   by the fundamental, multiply by 100 %.

### 7.5 Pass / fail criteria

| Tier | Criterion |
|------|-----------|
| Acceptable | < 1 % THD at normal listening levels. |
| Good | < 0.5 % THD at normal listening levels. |
| Excellent | < 0.1 % THD at normal listening levels (limited by the INMP441 and PCM5102A datasheet distortion). |

A THD above 1 % is almost always a sign of **output clipping** (the
gain table is too hot, or the input level is too high), or a
**broken I2S link** (dropped samples, mis-clocked).

---

## 8. Other Measurements (Briefer)

### 8.1 Phase response (linearity)

The Hann window + 50 % overlap-add pipeline is designed to be
**linear phase** (the magnitude response is shaped, the phase
response is a constant group delay equal to one frame period).
Measure by sweeping a chirp and measuring the group delay at each
frequency. The result should be flat at 5.33 ms across the
passband. A non-flat group delay indicates an FFT length error
(or a buggy IFFT configuration). See
[`docs/architecture/dsp_pipeline.md`](architecture/dsp_pipeline.md) §3.6.

### 8.2 Noise-gate threshold accuracy

The noise gate (default `REG_NOISE_FLOOR = 0x0100` ≈ –48 dBFS) is
expected to zero any bin whose magnitude is below the threshold.
Test by playing a sine wave at –50 dBFS (below the threshold) and
verifying the output is silent; then play at –40 dBFS and verify
the output is at the expected gain. The threshold is accurate to
within 1 dB.

### 8.3 BLE range and latency

A peripheral measurement, not core to the audio path. With the
ESP32's on-board antenna, the expected line-of-sight range is
~10 m. The GATT write-to-mode-change latency is ~50 ms (one
BLE connection interval). Measure with two phones, one running
nRF Connect, the other acting as a reference.

### 8.4 NVS persistence

Verify that a mode / volume / gain-table change persists across
a power cycle. The acceptance criterion is that after a 5-second
power-off, the device returns to the same mode, volume, and gain
table. The latency for the first write to settle in NVS is
500 ms (the `profile_task` debounce; see
[`docs/architecture/firmware_arch.md`](architecture/firmware_arch.md) §5.1).

---

## 9. Measurement Log Template

Every measurement session produces one CSV file under
`docs/MEASUREMENT_METHODOLOGY/measurements/`. The CSV has the
following columns. Save the photo of the setup alongside the CSV
with the same base name.

```csv
date,time,measurement,mode,value,unit,expected,pass_fail,notes
2026-07-15,14:32,latency,Bypass,7.4,ms,<10 ms,PASS,room temp 22C
2026-07-15,14:35,latency,General,7.4,ms,<10 ms,PASS,identical to Bypass
2026-07-15,14:38,latency,Hearing,7.4,ms,<10 ms,PASS,identical to Bypass
2026-07-15,14:41,snr,Bypass,58.2,dB,>55 dB,PASS,A-weighted
2026-07-15,14:44,thd,Bypass,0.31,%,<1 %,PASS,1 kHz at -6 dBFS
2026-07-15,14:47,power,General,232,mA,<300 mA,PASS,ESP32 81 mA + FPGA 151 mA
2026-07-15,14:52,freq_resp_1k,General,-0.3,dB,0 dB +/- 3 dB,PASS,1 kHz reference
2026-07-15,14:55,freq_resp_4k,Hearing,11.7,dB,+12 dB +/- 2 dB,PASS,4 kHz bin centre
```

The `notes` column captures anything that affects the measurement:
the room temperature, the laptop model, the INMP441 batch number,
a description of any visible glitches, the photo filename, and the
Git commit hash of the firmware and bitstream under test.

### 9.1 Recommended session cadence

| When | What to measure | Time required |
|------|-----------------|---------------|
| After every code change that touches the DSP pipeline | Latency, frequency response (single 1 kHz tone), THD | 15 minutes |
| After every code change that touches the analog path | Frequency response (full sweep), SNR | 30 minutes |
| After every code change that touches the clock or CDC | Latency, I2S lock verification (scope) | 20 minutes |
| Before every demo (24 hours prior) | All five measurements | 90 minutes |
| After every bitstream release | Full sweep, all four modes | 2 hours |
| Weekly (steady-state) | Latency, SNR, power, THD | 30 minutes |

### 9.2 Analysis scripts

The Python scripts under `tools/validation/` automate the analysis
of the captured CSVs:

- `tools/validation/check_freq_response.py` — parses the
  frequency-response sweep CSV and overlays it on the expected
  gain table.
- `tools/validation/check_cola.py` — verifies the Hann window's
  COLA property in the bitstream.
- `tools/validation/check_parseval.py` — verifies that the FFT
  preserves energy (Parseval's theorem), which is a strong
  signal that the FFT/IFFT are configured correctly.

These scripts are run as part of the CI pipeline (see
`.github/workflows/docs.yml`); a CI failure on a measurement CSV
is a red flag for a regression.

---

## 10. Where to Read Next

- The DSP pipeline that is being measured is described in
  [`docs/architecture/dsp_pipeline.md`](architecture/dsp_pipeline.md).
- The block diagram showing the audio and control paths is in
  [`docs/architecture/block_diagram.md`](architecture/block_diagram.md).
- The clock-domain analysis (the most likely source of latency
  issues) is in
  [`docs/architecture/clock_domains.md`](architecture/clock_domains.md).
- The full source-of-truth implementation plan is in
  [`docs/IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md).
- The measurement values that the demo *should* be able to
  reproduce live are quoted in
  [`docs/DEMO_PLAN.md`](DEMO_PLAN.md) §5.1.
