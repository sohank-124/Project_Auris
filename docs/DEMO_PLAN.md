# Demo Plan

> **Project Auris** — Demonstrating the FPGA-accelerated hearing-
> assistive device to college interviewers, science-fair judges,
> and peers.
> **Last updated:** 2026-08-12 (FPGA-only migration)
> **Status:** Authoritative for the canonical Project Auris
> demonstration (FPGA-only). For the broader college-application
> framing (essay topics, technical report outline, artifact
> checklist) see [`docs/college_app/README.md`](college_app/README.md).
> For the quantitative evidence underpinning the demo's claims,
> see [`docs/MEASUREMENT_METHODOLOGY.md`](MEASUREMENT_METHODOLOGY.md).
> For the architecture (which the demo demonstrates), see
> [`docs/fpga_only_architecture.md`](fpga_only_architecture.md).

---

## 1. Overview

The purpose of this document is to make the live demonstration of
Project Auris *foolproof*. The audience ranges from a college-
admissions interviewer with no signal-processing background to a
hardware interviewer who will want to see RTL, resource utilisation,
and waveforms. The demo has to engage both, run on a 1 m × 1 m
table, finish in **5–6 minutes**, and recover gracefully from a
half-dozen predictable failure modes (FPGA won't program, audio
is noisy, headphones are missing, audience wants a deeper dive
on a single mode).

This file collects the equipment, the physical layout, the
**second-by-second script**, the talking points, the fallback
scenarios, and the timing budget. Print it before every demo.

### 1.1 What the audience should walk away remembering

1. *Project Auris is real hardware that does real-time audio
   processing on an FPGA — not a simulation.*
2. *The 256-point FFT pipeline is the workhorse, and it runs at
   96 MHz with under 6 ms of latency — fast enough that a user
   cannot detect the delay.*
3. *The four listening modes (General, Speech, Music, Hearing)
   are meaningful, audible, and pre-computed as per-bin gain
   tables inside the FPGA.*
4. *The whole system is open source and reproducible from a
   sub-$110 bill of materials with a single FPGA and no
   microcontroller.*

Every section of this document is designed to deliver one of
those four takeaways.

> **Architecture context.** The FPGA is the sole signal-
> processing and control entity in this build. There is no
> ESP32, no SPI control plane, and no firmware to flash.
> Onboard push buttons drive the mode and volume; the RGB LED
> indicates the active mode; STATUS0 is a 1 Hz heartbeat;
> STATUS2 is a sticky clip indicator.

---

## 2. Demo Setup

### 2.1 Equipment checklist

| Item | Required? | Purpose |
|------|-----------|---------|
| Assembled Project Auris breadboard (Arty S7-25 + INMP441 + PCM5102A on a single 830-point breadboard) | Yes | The system under test. |
| Laptop with Vivado 2024.x installed | Yes | Reprograms the FPGA if needed. |
| Vivado Hardware Manager license active | Yes | FPGA programming. |
| USB-A to Micro-USB cable (Arty S7-25 programming / power) | Yes | Programs the FPGA, also powers it. |
| 3.5 mm over-ear headphones (closed-back, e.g., Sony MDR-7506) | Yes | Reference playback; must be available in two pairs if audience is large. |
| Audio source: phone playing a known track + speaker, or a pre-recorded WAV file from the laptop | Yes | Lets the audience *hear* the modes. |
| Pre-recorded audio with simulated hearing loss (see §2.4) | Recommended | Demonstrates the Hearing mode. |
| Speaker (small, powered) | Recommended | Plays audio into the mic for a "live" demo. |
| Printouts: block diagram, BOM table, oscilloscope screenshot of I2S | Optional | Visual aids for the audience to read at their own pace. |
| Spare Arty S7-25, INMP441, PCM5102A, jumper wires | Recommended | In case the primary breadboard dies mid-demo. |

> **No ESP32, no second USB cable, no BLE.** The FPGA-only
> build is a single-board design.

### 2.2 Software preflight (run 30 minutes before the demo)

1. Open the project in Vivado (`vivado fpga/vivado_proj/auris.xpr`).
2. Build the bitstream (`make fpga`); confirm a fresh `.bit` file.
3. Program the FPGA; verify the heartbeat LED (STATUS0) is
   toggling at 1 Hz and the RGB LED is green (Mode = General).
4. Run the latency test
   (`python tools/latency_analysis/measure_roundtrip.py`) to
   confirm the device is functional; note the result for §4.4.
5. Connect the headphones, play the pre-recorded audio, and
   walk through the four modes once to confirm the audio
   quality is good.
6. Position the laptop so the audience can read it. Open an ILA
   waveform capture of BCLK/LRCLK if you plan to use one.

### 2.3 Physical layout (1 m × 1 m table)

```
             +---------------------------------------------------+
             |  PRINTED BLOCK DIAGRAM (A4)        | PRINTED BOM  |
             |  PRINTED LATENCY / SNR CHART       | PHOTOS       |
             +-------------------+---------------+---------------+
             |                   |                              |
             |  LAPTOP           |  SPEAKER (audio source)      |
             |  (Vivado + ILA)   |  (playing pre-recorded       |
             |                   |   music/speech)              |
             +-------------------+---------------+--------------+
             |                                   |              |
             |  BREADBOARD  +  HEADPHONES        |              |
             |  (Arty, mic,   (3.5 mm jack)     |              |
             |   DAC)                           |              |
             |                                   |              |
             +-------------------+---------------+--------------+
             |  SPARE PARTS     |  LOGIC ANALYZER (optional)   |
             |  (in bag)        |  (probing I2S BCLK)           |
             +-------------------+------------------------------+
```

The presenter stands behind the table facing the audience. The
laptop screen is angled 30° toward the audience. Headphones are
passed around during §4.4 only; the rest of the demo is the
presenter's narration plus the speaker.

### 2.4 Pre-recorded audio with simulated hearing loss

To make the Hearing mode's effect *audible* to a normal-hearing
audience, the audio source should include a track that mimics
the effect of presbycusis (age-related high-frequency hearing
loss):

- **Reference track:** a music clip with strong high-frequency
  content (cymbals, sibilance, piccolo).
- **Hearing-loss version:** the same clip low-pass-filtered at
  4 kHz with 12 dB of additional roll-off above 2 kHz, mixed
  with broadband noise at 6 dB SNR. Generated by
  `tools/test_vector_gen/gen_audiogram_tests.py` with
  `--audiogram 0,0,0,5,15,25,40,55`.
- **Speech-in-noise track:** a podcast clip mixed with cafeteria
  noise at 0 dB SNR. Used to demonstrate the Speech mode's
  noise gate and mid-band boost.

All three clips are 30 seconds long. The presenter plays the
hearing-loss version first (audience can barely understand it),
then switches to Hearing mode (audience can suddenly follow the
words).

---

## 3. Demo Script

The full script runs in **5–6 minutes** plus Q&A. Each step has
a hard time budget; if the audience is engaged and the timing
allows, the presenter may extend a step by up to 50 %, but the
script always ends at the same place.

### 3.1 Step 1 — Introduction (30 s)

> "Project Auris is a hearing-assistive device I built over
> the past year. It pairs an FPGA — a single Xilinx Spartan-7 —
> with a MEMS microphone and a DAC. The FPGA does everything:
> it generates the I²S clocks, runs a 256-point FFT pipeline,
> and applies per-frequency-bin gain. The whole system runs
> from a sub-$110 bill of materials, no microcontroller, no
> firmware to flash."

**What to do:** stand next to the breadboard, point to the FPGA
briefly, then move on.

### 3.2 Step 2 — Architecture walkthrough (1 min)

> "There are two signal paths on the breadboard. The pink wire
> carries I²S audio from the MEMS microphone on the left, into
> the FPGA, through the FFT pipeline, and out the right side
> to the DAC and the headphones. The white and gray wires are
> the I²S bit clock and word clock — the FPGA generates both,
> so the microphones and DAC are slaves. And the four push
> buttons on the FPGA board are the user interface — mode and
> volume, no Bluetooth, no phone app required."

**What to do:** point to each wire, then to the printed block
diagram on the table. Pause briefly to let the audience follow.

### 3.3 Step 3 — Heartbeat + Passthrough baseline (30 s)

> "Before we talk about modes, let me show you the device is
> alive. The first LED — STATUS0 — toggles at 1 Hz whenever the
> FPGA is healthy and out of reset. The second LED is a sticky
> clip indicator; it stays off as long as the input isn't
> clipping. The RGB LED is green — that means we're in General
> mode, which is a transparent pass-through. Audio flows
> straight through with no colouring."

**What to do:** point to STATUS0 (heartbeat), STATUS2 (clip),
and the green RGB LED. Play the reference track through the
speaker; the audience hears it unprocessed.

### 3.4 Step 4 — General mode confirmed (30 s)

> "We're already in General mode. It's a flat unity gain across
> all 128 frequency bins. This is the equivalent of a basic
> amplifier — or more precisely, of no amplifier at all. The
> DSP is engaged, but it's not colouring the signal."

**What to do:** press BTN0 (the mode increments). The LED cycles
green → blue → magenta → red → green (General → Speech → Music
→ Hearing → General). The presenter may skip directly to the
mode of interest by holding BTN0 / BTN1 to reach it. Audio in
General mode is indistinguishable from passthrough.

### 3.5 Step 5 — Hearing profile (30 s)

> "Now the interesting one. Hearing mode loads a pre-computed
> gain table that compensates for a specific audiogram — the
> kind you'd get from an audiologist. This particular table
> boosts the 2 kHz–6 kHz region by up to 12 dB, which is the
> band where presbycusis hits hardest. Listen to the hearing-
> loss audio clip first, then watch what happens when I
> switch to Hearing mode."

**What to do:** play the hearing-loss audio clip (audience
struggles to follow). Press BTN0 to cycle to Hearing mode (LED
turns red). Replay the clip; the audience can now follow. If
time allows, describe the gain table — point to the printed
gain curve.

### 3.6 Step 6 — Speech profile (30 s)

> "Speech mode is different. It applies a noise gate — any
> spectral bin whose magnitude is below a threshold is zeroed,
> which suppresses the constant background hum. It then
> boosts the speech band, roughly 500 Hz to 4 kHz, by 6 dB.
> The result is that speech pops out of noise. Listen to the
> cafeteria-noise clip."

**What to do:** play the speech-in-noise clip (audience can
barely follow). Press BTN0 to cycle to Speech mode (LED turns
blue). Replay the clip; the speech is now intelligible. Note
that the noise-gate threshold is set inside `mode_ctrl.sv` (one
of the per-mode pre-computed parameters).

### 3.7 Step 7 — Music profile (30 s)

> "Music mode is the last of the four. It has a flat mid-band
> with a sub-bass lift and an air/sparkle shelf at the top.
> This is the mode you'd use for general music listening —
> the bass and the treble come through a bit more, the
> mids stay flat."

**What to do:** press BTN0 to cycle to Music mode (LED turns
magenta). Play the reference music clip; the audience hears
the slightly lifted bass and treble.

### 3.8 Step 8 — Volume control (30 s)

> "All four modes also have a volume control. The third button
> raises the volume — 31 levels, with the maximum being unity
> gain. The fourth button lowers it. Let me show you — at the
> top, the music should be loud; at the bottom, it should be
> muted."

**What to do:** press BTN2 repeatedly to raise the volume; press
BTN3 repeatedly to lower it. Note that level 0 is mute and
level 31 is unity gain. The volume is mapped linearly in Q2.14
(0x4000 = unity at level 31).

### 3.9 Step 9 — Q&A (flexible)

> "Happy to take questions."

**What to do:** if the audience is hardware-fluent, offer to
show Vivado — open the block design, point at the FFT IP, show
the resource utilisation report. If the audience is a
science-fair judge, walk them through the printed block
diagram. Common questions and the prepared answers are in §5.

---

## 4. Fallback Scenarios

A demo fails when an unpredicted variable beats the prepared
script. The list below covers the *known unknowns*; each one
has a rehearsed recovery. The general rule: **never let a
5-second failure cascade into a 5-minute recovery in front of
the audience.** If a fix takes more than 60 seconds, switch
to the most-readable sub-demo (General mode + a single mode)
and use the time for talking points.

### 4.1 FPGA won't program

- **Symptom:** Vivado Hardware Manager shows "no devices
  found", or `openFPGALoader` errors with "IDCODE mismatch".
- **First check:** USB cable. Try a different cable; Arty
  S7-25's Micro-USB connector is standard on most Digilent
  boards.
- **Second check:** power LED on the Arty S7-25. If off, the
  board is unpowered. Try a different USB port on the laptop.
- **Third check:** Vivado cable drivers (`libusb`). Reinstall.
- **Fallback demo:** if the FPGA is dead, demonstrate the
  waveform capture from §3.2 — show the audience the BCLK
  and LRCLK from the bitstream you generated earlier. Walk
  through the printed block diagram.
- **Honest framing:** "The FPGA has decided it needs a coffee
  break; let me show you the bitstream we built."

### 4.2 Audio is noisy or distorted

- **Symptom:** audible hiss, hum, crackle, or obvious
  distortion in the headphones.
- **First check:** the BCLK frequency. The FPGA's `clk_gen.sv`
  should be generating exactly 3.072 MHz. If it's off, the
  CDC FIFOs will underrun. Probe with a logic analyzer or
  scope.
- **Second check:** the LRCLK polarity. INMP441 and PCM5102A
  have inverted conventions; flipping the LRCLK pin in the
  FPGA constraints can fix the channel order.
- **Third check:** the gain table. The four pre-computed
  tables are conservative; if the user accidentally loaded
  a 6 dB boost across the board (not possible in this build
  but easy to imagine in a future revision), output clipping
  will sound like harshness.
- **Fallback demo:** if the audio is bad enough that no mode
  sounds right, switch to General mode and explain that
  General mode is the most diagnostic mode for analog path
  issues.

### 4.3 No headphones available

- **Symptom:** the audience brought no headphones, or the
  venue has only single-earbuds.
- **Fallback:** use a small powered speaker connected to the
  DAC output. The audio quality is lower (speaker adds
  distortion) but the demo still works.
- **Honest framing:** "We're skipping the headphones today,
  but the signal chain is identical — the speaker is just a
  different transducer at the end."

### 4.4 Audience wants a deeper technical dive

- **Symptom:** a hardware interviewer asks "show me the FFT
  IP configuration" or "what's the post-route utilisation?".
- **First response:** open the Vivado block design. Walk
  through the FFT IP settings: pipelined streaming I/O,
  256-pt, 16-bit data, BFP output, radix-2. Mention the
  cost: ~3,000 LUTs and 2 BRAMs per FFT.
- **Second response:** show the resource utilisation report
  (`top_utilization_placed.rpt`). Quote the headline numbers
  (LUT, BRAM, DSP48 percentages from
  [`docs/architecture/resource_budget.md`](architecture/resource_budget.md)).
- **Third response (optional):** open an ILA waveform of the
  FFT input and output, show the bin-by-bin behaviour.
  Time-permitting only; this is the part of the demo most
  likely to derail timing.

### 4.5 Audience is disengaged / not technical

- **Symptom:** glazed expressions, the interviewer is a
  humanities professor, or a science-fair judge who is
  timing each station.
- **First response:** skip §3.2 (architecture walkthrough)
  and spend the time on §3.5–§3.7 (Hearing, Speech, and
  Music mode demos). These are the *visceral* parts of the
  demo — the audience can *hear* the difference.
- **Second response:** tell the personal motivation story
  (see [`docs/college_app/README.md`](college_app/README.md)
  §3 for essay angles that work as 60-second anecdotes).
- **Third response:** offer to let them try the device
  themselves. Hand them the breadboard and the headphones;
  they will engage the moment they feel the audio change.

### 4.6 Latency measurement unexpectedly high (> 10 ms)

- **Symptom:** §3.8 telemetry shows the frame count is
  incrementing slowly, or §4.5's ILA shows visible lag.
- **Mitigation:** if the algorithmic latency has grown,
  check whether the DSP clock is locked to 96 MHz (STATUS0
  heartbeat indicates MMCM lock). If the lock has been lost,
  the I²S sample rate is correct but the DSP has fallen
  back to the 12 MHz reference; reset the FPGA.
- **Honest framing:** acknowledge the issue openly. Latency
  is one of the most-measured performance characteristics;
  being transparent is more credible than fudging the
  number.

---

## 5. Talking Points

A grab-bag of quotable facts and figures. These are the numbers
a college interviewer is most likely to ask about, and the ones
that make Project Auris a *standout* portfolio piece. All numbers
come from
[`docs/MEASUREMENT_METHODOLOGY.md`](MEASUREMENT_METHODOLOGY.md) and
[`docs/IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md); the live
demo validates them in real time.

### 5.1 Headline numbers

- **256-point FFT** at **96 MHz** on a **$59 FPGA** (Arty S7-25).
- **End-to-end latency: ~5.33 ms algorithmic** (one 256-sample
  frame at 48 kHz); total perceived latency **7–8 ms**
  including analog stages.
- **Frequency resolution: 187.5 Hz per bin** at 48 kHz. Each
  of the 128 stored bins is independently gain-controllable
  (Q2.14).
- **Cost: $106.60** for one complete breadboard prototype, see
  [`docs/hardware/BOM.md`](hardware/BOM.md).
- **Resource utilisation: ~58 % LUTs, ~19 % BRAMs, ~17 % DSP48s**
  on the XC7S25.
- **SNR: > 60 dB**, limited by the INMP441's datasheet SNR.
- **Power: ~0.85 W** at 5 V (Arty S7-25 only, ~172 mA combined).
- **Modes:** 4 listening modes (General, Speech, Music,
  Hearing) with pre-computed per-mode gain tables.

### 5.2 Why it's hard

- **Real-time DSP at 96 MHz on a sub-$60 FPGA.** The 256-pt
  FFT is just at the limit of the Spartan-7's LUT budget;
  the IFFT and the spectral processor share the rest.
  Optimisation matters.
- **Two clock domains** (12 MHz crystal, 96 MHz MMCM, 96 MHz
  DSP pipelining, plus the 3.072 MHz I2S BCLK and 48 kHz
  LRCLK that the FPGA itself generates). Two crossing
  points (I2S↔DSP), each with a Gray-coded async FIFO. See
  [`docs/architecture/clock_domains.md`](architecture/clock_domains.md).
- **Sub-10 ms latency constraint.** Anything above 20 ms is
  perceptible to a hearing-aid user. The architecture is
  tuned to deliver ~5.3 ms, which is at the lower end of the
  published state-of-the-art for FPGA-based hearing aids.
- **Hann + 50 % overlap-add (COLA).** The window function is
  chosen to satisfy the constant overlap-add condition, so
  the pipeline is exactly reconstructable in General mode — no
  comb filtering, no spectral leakage beyond what the window
  itself imposes.

### 5.3 Why it matters

- **Hearing aids are expensive.** A pair of prescription
  hearing aids costs $4,000–$8,000. A 30 % hearing loss
  affects 1 in 5 people over 65; untreated hearing loss
  correlates with accelerated cognitive decline. A $110
  device that delivers audiogram-based gain could change the
  equation.
- **Open source means reproducible.** Every design decision
  is documented, every part is off-the-shelf, every
  toolchain is free. A high-school student in any country
  can build one.
- **It's a real product, not a tutorial.** The device has
  pre-computed per-mode gain tables, atomic bank swaps, a
  full testbench suite, and a working bitstream. It ships
  as a working breadboard prototype.

### 5.4 What you might be asked, and how to answer

- **"Why an FPGA, not a Raspberry Pi?"** — A Raspberry Pi runs
  Linux, which adds 10–50 ms of scheduling latency. An FPGA
  gives you *deterministic* sub-millisecond latency, which is
  what a hearing aid needs. The Pi also has 50× the power
  draw.
- **"Why the Arty S7-25, not a bigger FPGA?"** — The Arty is
  small enough for a wearable form factor, cheap enough for
  a student project, and the XC7S25 has just enough DSP48
  slices and BRAMs to fit the 256-pt FFT and IFFT. Bigger
  FPGAs would burn power we don't have.
- **"Why Q2.14, not floating point?"** — Floating-point IP
  costs dozens of DSP48 slices per bin. Q2.14 unsigned is
  16 bits, fits in a single DSP48 multiplier, and the gain
  range (0.0 to ≈ 2.0) covers everything a hearing aid
  needs. The format is a deliberate trade documented in
  [`docs/DESIGN_DECISIONS.md`](DESIGN_DECISIONS.md) ADR-008.
- **"Where did the ESP32 go?"** — The pre-migration design
  had an ESP32 co-processor that owned the user interface
  (buttons, BLE, NVS). The FPGA-only build (2026-08-12)
  removed it: the FPGA now owns the buttons directly through
  inline FSMs. See
  [`docs/fpga_only_architecture.md`](fpga_only_architecture.md)
  and the migration narrative at
  [`docs/migration_summary.md`](migration_summary.md).
- **"What's next?"** — DRC LUT, a custom PCB, a 3D-printed
  enclosure, and a smartphone app for audiogram upload (the
  app would talk to the FPGA over BLE through a separate
  bridge — out of scope for the current build).

---

## 6. Visual Aids

| Aid | Format | When to use |
|-----|--------|-------------|
| Block diagram (one-page) | A4 printout or poster | On the table throughout the demo. The Mermaid version in [`docs/architecture/block_diagram.md`](architecture/block_diagram.md) is the source. |
| BOM table (one-page) | A4 printout | Beside the block diagram; the audience can read it while you talk. |
| Photos of the breadboard | 4×6 prints or a tablet slideshow | Optional, useful if the venue lighting is bad. |
| Oscilloscope screenshot of I2S BCLK + LRCLK + SD | PNG | §3.8 only, if the audience is hardware-fluent. |
| Latency measurement screenshot | PNG | §3.8, alongside the telemetry output. |
| Gain-curve plots for General / Hearing / Speech / Music | PNG | §3.5 and §3.6; helps the audience visualise the per-bin gain. |
| Resource-utilisation report (post-route) | PNG | §4.5 only. |

The block diagram, BOM, and gain-curve plots are the *minimum*
set for a successful demo. The rest are deep-dive material.

---

## 7. Timing

| Section                    | Time budget | Cumulative |
|----------------------------|-------------|------------|
| §3.1 Introduction          | 30 s        | 0:30       |
| §3.2 Architecture walkthrough | 60 s      | 1:30       |
| §3.3 Heartbeat + Passthrough | 30 s       | 2:00       |
| §3.4 General mode confirmed | 30 s        | 2:30       |
| §3.5 Hearing profile       | 30 s        | 3:00       |
| §3.6 Speech profile        | 30 s        | 3:30       |
| §3.7 Music profile         | 30 s        | 4:00       |
| §3.8 Volume control        | 30 s        | 4:30       |
| Transition to Q&A          | 30 s        | 5:00       |
| Q&A buffer                 | 60 s        | 6:00       |
| **Total**                  | **6:00**    |            |

If a step is skipped (e.g., Music mode is not working), the
time budget becomes buffer for Q&A; never stretch a step beyond
1.5× the budget or the demo will overrun. The single hardest
timing constraint is §3.2 (the architecture walkthrough) — it
is the only step the presenter can lose the audience on, so it
is also the only one that can be lengthened slightly when the
audience is engaged.

---

## 8. Where to Read Next

- The broader college-application framing — essay topics,
  technical report outline, artifact checklist — is in
  [`docs/college_app/README.md`](college_app/README.md).
- The quantitative evidence (latency, frequency response,
  SNR, THD, power) that backs up the headline numbers in
  §5.1 is in
  [`docs/MEASUREMENT_METHODOLOGY.md`](MEASUREMENT_METHODOLOGY.md).
- The 6-phase development plan and the go/no-go checkpoints
  that define "demo-ready" are in
  [`docs/ROADMAP.md`](ROADMAP.md).
- The architectural context (block diagram, clock domains,
  DSP pipeline) is in
  [`docs/architecture/`](architecture/) and
  [`docs/fpga_only_architecture.md`](fpga_only_architecture.md).
- The build and flash commands for the day-of the demo are
  in [`docs/IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md)
  §3 (pre-migration plan, banner-added 2026-08-12).
- The per-phase reflections (what we actually learned, what
  we would do differently) are in
  [`docs/phase_reports/`](phase_reports/).