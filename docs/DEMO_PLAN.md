# Demo Plan

> **Project Auris** — Demonstrating the FPGA-accelerated hearing-assistive
> device to college interviewers, science-fair judges, and peers.
> **Last updated:** 2026-07
> **Status:** Authoritative for the canonical Project Auris demonstration.
> For the broader college-application framing (essay topics, technical
> report outline, artifact checklist) see
> [`docs/college_app/README.md`](college_app/README.md). For the
> quantitative evidence underpinning the demo's claims, see
> [`docs/MEASUREMENT_METHODOLOGY.md`](MEASUREMENT_METHODOLOGY.md).

---

## 1. Overview

The purpose of this document is to make the live demonstration of
Project Auris *foolproof*. The audience ranges from a college-admissions
interviewer with no signal-processing background to a hardware
interviewer who will want to see RTL, resource utilisation, and
waveforms. The demo has to engage both, run on a 1 m × 1 m table, finish
in **5–6 minutes**, and recover gracefully from a half-dozen predictable
failure modes (FPGA won't program, BLE won't pair, audio is noisy,
headphones are missing, audience wants a deeper dive on a single mode).

This file collects the equipment, the physical layout, the
**second-by-second script**, the talking points, the fallback scenarios,
and the timing budget. Print it before every demo.

### 1.1 What the audience should walk away remembering

1. *Project Auris is real hardware that does real-time audio processing
   on an FPGA — not a simulation.*
2. *The 256-point FFT pipeline is the workhorse, and it runs at 96 MHz
   with under 6 ms of latency — fast enough that a user cannot detect
   the delay.*
3. *The three listening modes (General, Hearing, Speech) are
   meaningful, audible, and configurable per-bin from an audiogram.*
4. *The whole system is open source and reproducible from a
   sub-$120 bill of materials.*

Every section of this document is designed to deliver one of those
four takeaways.

---

## 2. Demo Setup

### 2.1 Equipment checklist

| Item | Required? | Purpose |
|------|-----------|---------|
| Assembled Project Auris breadboard (Cmod S7-25 + ESP32-DevKitC-32E + INMP441 + PCM5102A on a single 830-point breadboard) | Yes | The system under test. |
| Laptop with Vivado 2024.x and ESP-IDF v5.x installed | Yes | Reprograms the FPGA and reflash firmware if needed. |
| Vivado Hardware Manager license active | Yes | FPGA programming. |
| USB-A to micro-USB cable (Cmod S7-25 programming / power) | Yes | Programs the FPGA, also powers it. |
| USB-A to micro-USB cable (ESP32 programming / power) | Yes | Programs and powers the ESP32. |
| USB-C to USB-A adapter (for newer laptops) | Recommended | Cmod S7-25 ships with USB-C. |
| 3.5 mm over-ear headphones (closed-back, e.g., Sony MDR-7506) | Yes | Reference playback; must be available in two pairs if audience is large. |
| Audio source: phone playing a known track + speaker, or a pre-recorded WAV file from the laptop | Yes | Lets the audience *hear* the modes. |
| Pre-recorded audio with simulated hearing loss (see §2.4) | Recommended | Demonstrates the Hearing mode. |
| Speaker (small, powered) | Recommended | Plays audio into the mic for a "live" demo. |
| USB current meter (e.g., ~~$10 inline USB ammeter) | Recommended | Shows the ESP32 and FPGA power draw live. |
| Logic analyzer (Saleae or clone) with I2S/SPI protocol decoding | Optional | Visual aid for the deep-dive audience. |
| Printouts: block diagram, BOM table, oscilloscope screenshot of I2S | Optional | Visual aids for the audience to read at their own pace. |
| Spare ESP32, Cmod S7-25, INMP441, PCM5102A, jumper wires | Recommended | In case the primary breadboard dies mid-demo. |
| Spare batteries / power bank | Optional | Allows demo to run unplugged from the laptop. |

### 2.2 Software preflight (run 30 minutes before the demo)

1. Open the project in Vivado (`vivado fpga/vivado_workspace/auris_cmod.xpr`).
2. Open the ESP-IDF terminal with the project (`cd firmware`).
3. Build both targets (`make all`); confirm fresh `.bit` and `.bin` files.
4. Program the FPGA, flash the ESP32, and verify the LED pattern is green
   (Mode = General).
5. Run the latency test (`python tools/latency_analysis/measure_roundtrip.py`)
   to confirm the device is functional; note the result for §4.4.
6. Connect the headphones, play the pre-recorded audio, and walk through
   the four modes once to confirm the audio quality is good.
7. Open the ESP32 serial monitor (`make esp-monitor ESP_PORT=COM3`) and
   the Vivado Hardware Manager's ILA (if any signals are tapped) side
   by side. Position them on the laptop so the audience can read them.

### 2.3 Physical layout (1 m × 1 m table)

```
            +---------------------------------------------------+
            |  PRINTED BLOCK DIAGRAM (A4)        | PRINTED BOM  |
            |  PRINTED LATENCY / SNR CHART       | PHOTOS       |
            +-------------------+---------------+---------------+
            |                   |                              |
            |  LAPTOP           |  SPEAKER (audio source)      |
            |  (Vivado + IDF    |  (playing pre-recorded       |
            |   + serial mon.)  |   music/speech)              |
            |                   |                              |
            +-------------------+---------------+--------------+
            |                                   |              |
            |  BREADBOARD  +  HEADPHONES        |  USB METERS  |
            |  (Cmod, ESP32,                    |  (current    |
            |   mic, DAC)                       |   readout)   |
            |                                   |              |
            +-------------------+---------------+--------------+
            |  LOGIC ANALYZER (optional)        |  SPARE PARTS |
            |  (probing I2S BCLK)               |  (in bag)    |
            +-----------------------------------+--------------+
```

The presenter stands behind the table facing the audience. The laptop
screen is angled 30° toward the audience. Headphones are passed around
during §4.4 only; the rest of the demo is the presenter's narration
plus the speaker.

### 2.4 Pre-recorded audio with simulated hearing loss

To make the Hearing mode's effect *audible* to a normal-hearing
audience, the audio source should include a track that mimics the
effect of presbycusis (age-related high-frequency hearing loss):

- **Reference track:** a music clip with strong high-frequency content
  (cymbals, sibilance, piccolo).
- **Hearing-loss version:** the same clip low-pass-filtered at 4 kHz
  with 12 dB of additional roll-off above 2 kHz, mixed with broadband
  noise at 6 dB SNR. Generated by
  `tools/test_vector_gen/gen_audiogram_tests.py` with
  `--audiogram 0,0,0,5,15,25,40,55`.
- **Speech-in-noise track:** a podcast clip mixed with cafeteria
  noise at 0 dB SNR. Used to demonstrate the Speech mode's noise gate
  and mid-band boost.

All three clips are 30 seconds long. The presenter plays the
hearing-loss version first (audience can barely understand it), then
switches to Hearing mode (audience can suddenly follow the words).

---

## 3. Demo Script

The full script runs in **5–6 minutes** plus Q&A. Each step has a hard
time budget; if the audience is engaged and the timing allows, the
presenter may extend a step by up to 50 %, but the script always
ends at the same place.

### 3.1 Step 1 — Introduction (30 s)

> "Project Auris is a hearing-assistive device I built over the past
> year. It pairs an ESP32 microcontroller with a Xilinx Spartan-7 FPGA
> to perform real-time spectral audio processing — the same kind of
> processing that commercial hearing aids do, but on open-source
> hardware for under $120. The FPGA runs a 256-point FFT pipeline that
> applies per-frequency-bin gain to the incoming audio. The ESP32 owns
> the user interface — buttons, Bluetooth, profile storage — and
> configures the FPGA over a four-wire SPI bus."

**What to do:** stand next to the breadboard, point to the FPGA
briefly, then move on.

### 3.2 Step 2 — Architecture walkthrough (1 min)

> "There are three signal paths on the breadboard. The blue wire
> carries I2S audio from the MEMS microphone on the left, into the
> FPGA, through the FFT pipeline, and out the right side to the DAC
> and the headphones. The green wire is the SPI bus from the ESP32
> to the FPGA's register file — every time you press a button or
> change a profile, a register write goes across this bus. And the
> red wire is the BLE antenna on the ESP32 — that's how a phone can
> configure the device without a button press."

**What to do:** point to each wire, then to the printed block diagram
on the table. Pause briefly to let the audience follow.

### 3.3 Step 3 — Bypass mode baseline (30 s)

> "The device has four modes. Let me start with Bypass, which is the
> FPGA in pass-through — the audio goes mic → DAC with zero
> processing. This is your reference."

**What to do:** press and hold the mode button for 2 seconds (long
press cycles to Bypass). The LED turns red. Play the reference track
through the speaker; the audience hears it unprocessed.

### 3.4 Step 4 — General profile (30 s)

> "Now I'll switch to General mode, which is flat amplification — the
> gain table is a constant 1.0 across all 128 frequency bins. This
> is the equivalent of a basic amplifier. It should sound the same as
> Bypass, and that's the point: the DSP is engaged, but it's not
> colouring the signal."

**What to do:** short-press the mode button (cycles Bypass → General).
The LED turns green. Play the same track; the audio should be
indistinguishable from Bypass. Pause briefly to confirm.

### 3.5 Step 5 — Hearing profile (30 s)

> "Now the interesting one. Hearing mode loads a gain table that
> compensates for a specific audiogram — the kind you'd get from an
> audiologist. This particular table boosts the 2 kHz–6 kHz region by
> up to 12 dB, which is the band where presbycusis hits hardest.
> Listen to the hearing-loss audio clip first, then watch what
> happens when I switch to Hearing mode."

**What to do:** play the hearing-loss audio clip (audience struggles
to follow). Press the mode button to cycle to Hearing (LED turns
blue). Replay the clip; the audience can now follow. If time allows,
describe the gain table — point to the printed gain curve.

### 3.6 Step 6 — Speech profile (30 s)

> "Speech mode is different. It applies a noise gate — any bin whose
> magnitude is below a threshold is zeroed, which suppresses the
> constant background hum. It then boosts the speech band, roughly
> 500 Hz to 4 kHz, by 6 dB. The result is that speech pops out of
> noise. Listen to the cafeteria-noise clip."

**What to do:** play the speech-in-noise clip (audience can barely
follow). Press the mode button to cycle to Speech (LED turns cyan).
Replay the clip; the speech is now intelligible. Mention the noise
gate's threshold register (`REG_NOISE_FLOOR` = 0x0100).

### 3.7 Step 7 — BLE control (30 s)

> "All of that mode-switching is also accessible over Bluetooth. The
> ESP32 runs a GATT server; the phone acts as a client. I can change
> the mode, the volume, even individual frequency bins, from a phone
> app — and the device never needs to leave your ear."

**What to do:** open the nRF Connect or LightBlue app on the
presenter's phone. Connect to "ProjectAuris". Write a value to the
`auris_mode` characteristic and show the LED on the breadboard
changing colour. If the phone app is not installed, skip and rely on
the §4.3 fallback.

### 3.8 Step 8 — Telemetry display (30 s)

> "The FPGA also reports back over the same SPI bus. The ESP32 polls
> the status registers once a second and prints them to the serial
> monitor. You can see the peak input level, the peak output level,
> the frame counter, and the error flags. Right now the frame count
> is incrementing at 47 Hz, which matches our 256-point FFT running
> at 48 kHz — one frame every 5.33 ms."

**What to do:** switch the laptop display to the ESP32 serial
monitor. Show the live `peak_in`, `peak_out`, `frame_count` fields.
Optionally grab the printed waveform screenshot from the
oscilloscope capture (see §6).

### 3.9 Step 9 — Q&A (flexible)

> "Happy to take questions."

**What to do:** if the audience is hardware-fluent, offer to show
Vivado — open the block design, point at the FFT IP, show the
resource utilisation report. If the audience is a science-fair
judge, walk them through the printed block diagram. Common questions
and the prepared answers are in §5.

---

## 4. Fallback Scenarios

A demo fails when an unpredicted variable beats the prepared script.
The list below covers the *known unknowns*; each one has a rehearsed
recovery. The general rule: **never let a 5-second failure cascade
into a 5-minute recovery in front of the audience.** If a fix takes
more than 60 seconds, switch to the most-readable sub-demo (Bypass +
a single mode) and use the time for talking points.

### 4.1 FPGA won't program

- **Symptom:** Vivado Hardware Manager shows "no devices found", or
  `openFPGALoader` errors with "IDCODE mismatch".
- **First check:** USB cable. Try a different cable; Cmod S7-25's
  USB-C connector has a reputation for flaky cables.
- **Second check:** power LED on the Cmod S7-25. If off, the board
  is unpowered. Try a different USB port on the laptop.
- **Third check:** Vivado cable drivers (`libusb`). Reinstall.
- **Fallback demo:** if the FPGA is dead, demonstrate the ESP32
  side: open the serial monitor, walk through the button handler,
  show the mode state machine, explain how it *would* configure the
  FPGA. Pass around the printed block diagram.
- **Honest framing:** "The FPGA has decided it needs a coffee break;
  let me show you the firmware side, which is just as interesting."

### 4.2 BLE pairing fails

- **Symptom:** the phone app cannot find "ProjectAuris", or the
  GATT write returns "insufficient authentication".
- **First check:** the ESP32's BLE stack initialises successfully
  (`bt_audio` task reports "BLE advertising"). The serial monitor
  shows the device's BLE address.
- **Second check:** the phone's Bluetooth is on, location services
  are allowed (Android requirement), and the nRF Connect app is up
  to date.
- **Fallback demo:** use the physical button to cycle modes
  (§3.4–§3.6 still work without BLE). Mention that BLE is a
  user-experience enhancement, not a required part of the audio
  path.

### 4.3 Audio is noisy or distorted

- **Symptom:** audible hiss, hum, crackle, or obvious distortion
  in the headphones.
- **First check:** the BCLK frequency. ESP32 I2S master should be
  generating exactly 3.072 MHz. If it's off, the CDC FIFOs will
  underrun. Probe with a logic analyzer or scope.
- **Second check:** the LRCLK polarity. INMP441 and PCM5102A have
  inverted conventions; flipping the LRCLK pin in the FPGA
  constraints can fix the channel order.
- **Third check:** the gain table. If the user accidentally loaded
  a 6 dB boost across the board, output clipping will sound like
  harshness. Re-flash the default tables.
- **Fallback demo:** if the audio is bad enough that no mode sounds
  right, switch to Bypass and explain that Bypass is the most
  diagnostic mode for analog path issues.

### 4.4 No headphones available

- **Symptom:** the audience brought no headphones, or the venue has
  only single-earbuds.
- **Fallback:** use a small powered speaker connected to the DAC
  output. The audio quality is lower (speaker adds distortion) but
  the demo still works.
- **Honest framing:** "We're skipping the headphones today, but the
  signal chain is identical — the speaker is just a different
  transducer at the end."

### 4.5 Audience wants a deeper technical dive

- **Symptom:** a hardware interviewer asks "show me the FFT IP
  configuration" or "what's the post-route utilisation?".
- **First response:** open the Vivado block design. Walk through
  the FFT IP settings: pipelined streaming I/O, 256-pt, 16-bit
  data, BFP output, radix-2. Mention the cost: ~3,000 LUTs and
  2 BRAMs per FFT.
- **Second response:** show the resource utilisation report
  (`top_utilization_placed.rpt`). Quote the headline numbers
  (LUT, BRAM, DSP48 percentages from
  [`docs/architecture/resource_budget.md`](architecture/resource_budget.md)).
- **Third response (optional):** open an ILA waveform of the FFT
  input and output, show the bin-by-bin behaviour. Time-permitting
  only; this is the part of the demo most likely to derail timing.

### 4.6 Audience is disengaged / not technical

- **Symptom:** glazed expressions, the interviewer is a humanities
  professor, or a science-fair judge who is timing each station.
- **First response:** skip §3.2 (architecture walkthrough) and
  spend the time on §3.5–§3.6 (Hearing and Speech mode demos).
  These are the *visceral* parts of the demo — the audience can
  *hear* the difference.
- **Second response:** tell the personal motivation story
  (see [`docs/college_app/README.md`](college_app/README.md) §3 for
  essay angles that work as 60-second anecdotes).
- **Third response:** offer to let them try the device themselves.
  Hand them the breadboard and the headphones; they will engage
  the moment they feel the audio change.

### 4.7 Latency measurement unexpectedly high (> 10 ms)

- **Symptom:** §3.8 telemetry shows the frame count is
  incrementing slowly, or §4.5's ILA shows visible lag.
- **Mitigation:** if the algorithmic latency has grown, check
  whether the DSP clock is locked to 96 MHz (the green LED on the
  Cmod S7-25 indicates MMCM lock). If the lock has been lost, the
  I2S sample rate is correct but the DSP has fallen back to the
  12 MHz reference; reset the FPGA.
- **Honest framing:** acknowledge the issue openly. Latency is
  one of the most-measured performance characteristics; being
  transparent is more credible than fudging the number.

---

## 5. Talking Points

A grab-bag of quotable facts and figures. These are the numbers a
college interviewer is most likely to ask about, and the ones that
make Project Auris a *standout* portfolio piece. All numbers come from
[`docs/MEASUREMENT_METHODOLOGY.md`](MEASUREMENT_METHODOLOGY.md) and
[`docs/IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md); the live
demo validates them in real time.

### 5.1 Headline numbers

- **256-point FFT** at **96 MHz** on a **$75 FPGA** (Cmod S7-25).
- **End-to-end latency: ~5.33 ms algorithmic** (one 256-sample
  frame at 48 kHz); total perceived latency **7–8 ms** including
  analog stages.
- **Frequency resolution: 5.3 Hz per bin** at 48 kHz. Each of the
  128 stored bins is independently gain-controllable (Q2.14).
- **Cost: $116.60** for one complete breadboard prototype, see
  [`docs/hardware/BOM.md`](hardware/BOM.md).
- **Resource utilisation: ~58 % LUTs, ~19 % BRAMs, ~25 % DSP48s**
  on the XC7S25.
- **SNR: > 60 dB**, limited by the INMP441's datasheet SNR.
- **Power: ~1.15 W** at 5 V (ESP32 ~80 mA, FPGA ~150 mA).

### 5.2 Why it's hard

- **Real-time DSP at 96 MHz on a sub-$100 FPGA.** The 256-pt FFT
  is just at the limit of the Spartan-7's LUT budget; the IFFT
  and the spectral processor share the rest. Optimisation matters.
- **Three clock domains** (12 MHz crystal, 96 MHz MMCM, 96 MHz DSP
  pipelining, plus the 3.072 MHz I2S BCLK and the 10 MHz SPI
  SCLK from the ESP32). Five crossing points, each with a
  hand-rolled CDC strategy. See
  [`docs/architecture/clock_domains.md`](architecture/clock_domains.md).
- **Sub-10 ms latency constraint.** Anything above 20 ms is
  perceptible to a hearing-aid user. The architecture is tuned to
  deliver ~5.3 ms, which is at the lower end of the published
  state-of-the-art for FPGA-based hearing aids.
- **Hann + 50 % overlap-add (COLA).** The window function is
  chosen to satisfy the constant overlap-add condition, so the
  pipeline is exactly reconstructable in Bypass — no comb
  filtering, no spectral leakage beyond what the window itself
  imposes.

### 5.3 Why it matters

- **Hearing aids are expensive.** A pair of prescription hearing
  aids costs $4,000–$8,000. A 30 % hearing loss affects 1 in 5
  people over 65; untreated hearing loss correlates with
  accelerated cognitive decline. A $120 device that delivers
  audiogram-based gain could change the equation.
- **Open source means reproducible.** Every design decision is
  documented, every part is off-the-shelf, every toolchain is
  free. A high-school student in any country can build one.
- **It's a real product, not a tutorial.** The device has
  NVS-persisted profiles, BLE, a real state machine, and a
  full testbench. It ships as a working breadboard prototype.

### 5.4 What you might be asked, and how to answer

- **"Why an FPGA, not a Raspberry Pi?"** — A Raspberry Pi runs
  Linux, which adds 10–50 ms of scheduling latency. An FPGA gives
  you *deterministic* sub-millisecond latency, which is what a
  hearing aid needs. The Pi also has 50× the power draw.
- **"Why the Cmod S7-25, not a bigger FPGA?"** — The Cmod is
  small enough for a wearable form factor, cheap enough for a
  student project, and the XC7S25 has just enough DSP48 slices
  and BRAMs to fit the 256-pt FFT and IFFT. Bigger FPGAs would
  burn power we don't have.
- **"Why Q2.14, not floating point?"** — Floating-point IP costs
  dozens of DSP48 slices per bin. Q2.14 unsigned is 16 bits, fits
  in a single DSP48 multiplier, and the gain range (0.0 to ≈ 2.0)
  covers everything a hearing aid needs. The format is a
  deliberate trade documented in
  [`docs/DESIGN_DECISIONS.md`](DESIGN_DECISIONS.md) ADR-008.
- **"What's next?"** — Phase 6 of the implementation plan
  (Bluetooth audio, DRC LUT, telemetry dashboard) is the
  "production" version. A custom PCB and a 3D-printed enclosure
  round out the project for Phase 5. Long-term: an LMS
  adaptive feedback canceller, a WDRC compressor, and a smartphone
  app for audiogram upload.

---

## 6. Visual Aids

| Aid | Format | When to use |
|-----|--------|-------------|
| Block diagram (one-page) | A4 printout or poster | On the table throughout the demo. The Mermaid version in [`docs/architecture/block_diagram.md`](architecture/block_diagram.md) is the source. |
| BOM table (one-page) | A4 printout | Beside the block diagram; the audience can read it while you talk. |
| Photos of the breadboard | 4×6 prints or a tablet slideshow | Optional, useful if the venue lighting is bad. |
| Oscilloscope screenshot of I2S BCLK + LRCLK + SD | PNG | §3.8 only, if the audience is hardware-fluent. |
| Latency measurement screenshot | PNG | §3.8, alongside the telemetry output. |
| Gain-curve plots for General / Hearing / Speech | PNG | §3.5 and §3.6; helps the audience visualise the per-bin gain. |
| Resource-utilisation report (post-route) | PNG | §4.5 only. |
| Schematic of the SPI link (Pmod JA) | PNG | §4.5 only. |

The block diagram, BOM, and gain-curve plots are the *minimum* set
for a successful demo. The rest are deep-dive material.

---

## 7. Timing

| Section                    | Time budget | Cumulative |
|----------------------------|-------------|------------|
| §3.1 Introduction          | 30 s        | 0:30       |
| §3.2 Architecture walkthrough | 60 s      | 1:30       |
| §3.3 Bypass mode baseline  | 30 s        | 2:00       |
| §3.4 General profile       | 30 s        | 2:30       |
| §3.5 Hearing profile       | 30 s        | 3:00       |
| §3.6 Speech profile        | 30 s        | 3:30       |
| §3.7 BLE control           | 30 s        | 4:00       |
| §3.8 Telemetry display     | 30 s        | 4:30       |
| Transition to Q&A          | 30 s        | 5:00       |
| Q&A buffer                 | 60 s        | 6:00       |
| **Total**                  | **6:00**    |            |

If a step is skipped (e.g., BLE is not working), the time budget
becomes buffer for Q&A; never stretch a step beyond 1.5× the budget
or the demo will overrun. The single hardest timing constraint is
§3.2 (the architecture walkthrough) — it is the only step the
presenter can lose the audience on, so it is also the only one
that can be lengthened slightly when the audience is engaged.

---

## 8. Where to Read Next

- The broader college-application framing — essay topics, technical
  report outline, artifact checklist — is in
  [`docs/college_app/README.md`](college_app/README.md).
- The quantitative evidence (latency, frequency response, SNR, THD,
  power) that backs up the headline numbers in §5.1 is in
  [`docs/MEASUREMENT_METHODOLOGY.md`](MEASUREMENT_METHODOLOGY.md).
- The 6-phase development plan and the go/no-go checkpoints that
  define "demo-ready" are in
  [`docs/ROADMAP.md`](ROADMAP.md).
- The architectural context (block diagram, clock domains, DSP
  pipeline) is in [`docs/architecture/`](architecture/).
- The build and flash commands for the day-of the demo are in
  [`docs/IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) §3.
- The per-phase reflections (what we actually learned, what we
  would do differently) are in
  [`docs/phase_reports/`](phase_reports/).
