# Design Decision Log

> **Project Auris** — Architecture Decision Records (ADR-style) for
> the key technical choices.
> **Last updated:** 2026-07
> **Status:** Authoritative. New ADRs are appended to the bottom of
> the log; old ADRs are not edited (they are immutable historical
> records). The full implementation plan, including per-module
> design notes, is in [`docs/IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md).

This document is the project's memory. Every significant
"we chose X over Y" decision is recorded here, with the context
that led to the decision, the decision itself, the consequences
(positive and negative), and the alternatives that were
considered. The format is borrowed from the
[Architecture Decision Records (ADR) process](https://adr.github.io/)
popularised by Michael Nygard.

The purpose is *not* to justify decisions that have already been
made. The purpose is to let a future reader (the author in 12
months, a college interviewer, a new contributor) understand
*why* the project looks the way it does, and to make the next
decision easier by exposing the trade-offs that were considered.

---

## 1. ADR Format

Each ADR is a short, self-contained document with the following
sections:

| Section | Purpose |
|---------|---------|
| **ID** | A unique identifier (`ADR-NNN`). Numbers are assigned in the order the ADR is written; do not re-use. |
| **Title** | A noun-phrase summary of the decision. |
| **Status** | One of: `Accepted` (the decision is in effect), `Superseded` (a later ADR replaces it; link to the new one), `Deprecated` (no longer relevant; do not use), `Proposed` (under discussion). |
| **Date** | The date the ADR was accepted. |
| **Context** | The forces at play: the technical, economic, and human constraints that made this decision necessary. What problem are we solving? |
| **Decision** | The choice that was made, stated in the active voice ("Use X", "Adopt Y", "Standardise on Z"). |
| **Consequences** | The positive *and* negative effects of the decision. "Positive" is what we get; "negative" is what we give up. |
| **Alternatives Considered** | The other choices that were on the table, and a one-sentence reason for rejecting each. |

ADRs are *immutable* once accepted. If a decision is reversed, the
original ADR is marked `Superseded` and a new ADR is written. The
history of a decision is the full chain of ADRs that reference it.

---

## ADR-001: Use Cmod S7-25 as FPGA Platform

**Status:** Accepted
**Date:** 2026-04

### Context

Project Auris needs an FPGA that:

- Has enough logic cells, BRAM, and DSP slices for a 256-pt FFT +
  IFFT + spectral processor (target: 9,000 LUTs, 30 BRAMs, 14
  DSP48E1s).
- Supports I2S (3.072 MHz BCLK at 24-bit data), SPI slave (10 MHz
  Mode 0), and a handful of GPIO for buttons and LEDs.
- Is available as a *module* (i.e., a ready-to-use PCB with
  voltage regulators, clock source, and pin headers) for under
  $100.
- Has a free or low-cost toolchain that runs on a high-school
  student's laptop.
- Is breadboard-friendly (2.54 mm pin headers, not BGA-only).

### Decision

Use the **Digilent Cmod S7-25** (Xilinx Spartan-7 XC7S25-1CSGA225C,
~14,620 LUTs, 42 BRAMs, 48 DSP48E1s, $59 module).

### Consequences

**Positive:**

- 14,620 LUTs is sufficient for the FFT + IFFT + spectral
  processor, with 42 % headroom for Phase 6 features (DRC,
  WDRC, adaptive filters).
- Two Pmod connectors (2×6 0.1" headers) make breadboard wiring
  trivial. No need for a custom PCB until Phase 5.
- 12 MHz onboard crystal feeds the MMCM; 96 MHz DSP clock
  synthesised cleanly with jitter within the FPGA's data-sheet
  spec.
- USB-C programming via Vivado Hardware Manager; no separate
  JTAG probe needed.
- Module cost (~$59) is within the project's BOM budget of
  ~$120 total.
- The XC7S25 is supported by Vivado WebPack (free edition), so
  the toolchain cost is zero.

**Negative:**

- Only 14,620 LUTs; aggressive optimisation is required to fit
  the 256-pt FFT (the FFT IP alone uses ~3,000 LUTs × 2 = 6,000
  LUTs for FFT and IFFT).
- Only 48 DSP48E1s; the spectral processor and the window
  multiplier compete for slices. Future WDRC extensions will
  need LUT-based compressors.
- Speed grade is –1 (the only Spartan-7 grade available for the
  XC7S25); 96 MHz timing closure is non-trivial.

### Alternatives Considered

- **Arty A7 (Xilinx Artix-7 XC7A35T).** More LUTs and DSP
  slices, but $130 module cost and a larger form factor.
  Rejected: out of budget and over-spec for the project.
- **Terasic DE10-Lite (Intel MAX 10).** Cheap, but MAX 10 has
  no DSP slices, so the FFT would have to be implemented in
  fabric LUTs (very expensive). Rejected: wrong architecture.
- **Lattice ECP5 (e.g., ULX3S board).** Cheap, open-source
  toolchain (Yosys + nextpnr), but smaller community and
  less familiar to college-admissions readers. Rejected:
  ecosystem risk.
- **Raspberry Pi Pico (RP2040 + programmable fabric).** No
  traditional FPGA fabric; the RP2040's PIO is not
  appropriate for FFT-class DSP. Rejected: not an FPGA in
  the relevant sense.
- **Zynq-7000 (e.g., Arty Z7).** Combines an FPGA with a
  hard ARM core; the ESP32 would be redundant. Rejected:
  doubles the cost and complicates the system.

---

## ADR-002: Use ESP32 as Controller

**Status:** Accepted
**Date:** 2026-04

### Context

Project Auris needs a microcontroller that:

- Generates the I2S master clock (BCLK = 3.072 MHz, LRCLK = 48 kHz).
- Is a SPI master to the FPGA (Mode 0, up to 10 MHz).
- Has BLE for wireless configuration from a phone.
- Handles 3 physical buttons (mode, volume up, volume down)
  with hardware debounce.
- Persists configuration to non-volatile storage (NVS).
- Is inexpensive (< $15) and breadboard-friendly.
- Has a free or low-cost toolchain (ESP-IDF).

### Decision

Use the **ESP32-DevKitC-32E** (Espressif ESP32-WROOM-32E module
on a development board, dual-core Tensilica LX6 @ 240 MHz, BLE
4.2, 4 MB flash, ~$12).

### Consequences

**Positive:**

- Dual-core 240 MHz processor with 4 MB flash; plenty of headroom
  for the 8 FreeRTOS tasks (see
  [`docs/architecture/firmware_arch.md`](architecture/firmware_arch.md) §2).
- Hardware I2S peripheral generates BCLK and LRCLK with zero
  CPU overhead; the audio DMA engine runs independently of the
  application.
- Hardware SPI master peripheral supports DMA; the SPI bus is
  not a CPU bottleneck.
- Built-in BLE 4.2 (and BLE 5.x via the IDF) with the NimBLE
  stack; A2DP source + GATT server fit in flash.
- Free ESP-IDF toolchain (Xtensa GCC) and a rich ecosystem of
  components.
- ESP32 is widely recognised by college-admissions readers; the
  module is a familiar reference point.

**Negative:**

- ESP-IDF has a learning curve for a high-school student who
  has not used FreeRTOS before. The project mitigates this
  with detailed component headers and a single-state-machine
  in `main.c`.
- BLE pairing can be flaky on some Android devices; the project
  has a button-only fallback.
- The ESP32's Wi-Fi radio adds BOM cost; this project does
  not use Wi-Fi but cannot disable the radio in firmware
  without a `sdkconfig` change.

### Alternatives Considered

- **ESP32-S3 (e.g., DevKitC-1).** Newer, with USB-OTG and
  vector instructions, but more expensive (~$15) and slightly
  harder to find. Rejected: over-spec; the project does not
  need USB-OTG or vector instructions.
- **STM32 (e.g., Nucleo-F446ZE).** Mature toolchain and good
  DSP performance, but no built-in BLE. Adding an external
  BLE module would double the BOM cost. Rejected: BLE is
  core to the user experience.
- **RP2040 (Raspberry Pi Pico).** Cheap and dual-core, but no
  built-in BLE. Rejected: BLE is core to the user experience.
- **nRF52 (e.g., nRF52840 DK).** Excellent BLE and DSP, but
  the toolchain is less familiar and the module is more
  expensive (~$30). Rejected: ecosystem and cost.
- **Bare ESP32 module (no DevKit).** Cheaper (~$3), but no
  USB-serial bridge, no voltage regulator, no boot button.
  Rejected: too much board bring-up for a one-off prototype.

---

## ADR-003: Use INMP441 as Microphone

**Status:** Accepted (with risk: see §R-01 in ROADMAP.md)
**Date:** 2026-04

### Context

Project Auris needs a microphone that:

- Outputs I2S directly (no analog mic + ADC pipeline).
- Is 24-bit, 48 kHz-capable, with a low noise floor (SNR > 60 dB
  to keep the system SNR above 55 dB).
- Is small (≤ 5 mm × 5 mm) and breadboard-friendly (preferably
  with a breakout board).
- Is inexpensive (< $10).
- Is available from a major distributor.

### Decision

Use the **TDK/InvenSense INMP441** (I2S MEMS microphone, 24-bit,
61 dB SNR, ~$8 on a breakout).

### Consequences

**Positive:**

- 24-bit I2S output matches the FPGA's I2S RX interface
  (no format conversion required).
- 61 dB SNR is sufficient for the project's SNR target of
  > 55 dB.
- Bottom-port acoustic inlet; small (4 mm × 3 mm × 1 mm)
  LGA package; widely available on a $5–$8 breakout board.
- Single 3.3 V supply; no bias voltage required.

**Negative:**

- **The INMP441 has been discontinued at DigiKey and Mouser**
  (as of 2026-04). Remaining stock is at LCSC and on
  eBay. This is a real availability risk; the project
  carries this as a top-level risk in
  [`docs/ROADMAP.md`](ROADMAP.md) §4 (R-01).
- The MEMS element is sensitive to mechanical vibration
  ("structure-borne noise"); a rubber isolation mount is
  recommended for wearable applications.
- The INMP441's I2S output is 24-bit, two's complement,
  MSB-first; this is the *de facto* standard but is worth
  confirming against the FPGA's I2S RX expectations.

### Alternatives Considered

- **SPH0645LM4H-B (Knowles).** Pin-compatible with the
  INMP441, 24-bit I2S, similar SNR. **This is the
  recommended drop-in replacement** if the INMP441 stock
  runs out.
- **ICS-43434 (TDK).** Bottom-port, 24-bit I2S, lower
  noise (65 dB SNR), but slightly more expensive (~$12).
  Considered as a substitute.
- **MP34DT05 (STMicro).** PDM output, not I2S; requires
  decimation filtering on the FPGA. Rejected: more
  complexity.
- **Analog MEMS mic (e.g., SPH0641LM4H-1) + external ADC
  (e.g., PCM1808).** Higher noise floor, more components,
  larger PCB. Rejected: more complexity, no upside.
- **Boom microphone (electret).** Cheap, but the analog
  path adds noise and is sensitive to the breadboard's
  ground loops. Rejected: project goal is I2S digital
  mic.

---

## ADR-004: Use PCM5102A as DAC

**Status:** Accepted
**Date:** 2026-04

### Context

Project Auris needs a digital-to-analog converter that:

- Accepts I2S input at 24-bit, 48 kHz.
- Drives 32 Ω headphones directly (or via a buffer) at
  ≥ 30 mW per channel.
- Has a low noise floor (SNR > 100 dB, to be well above the
  INMP441's 61 dB and not become the noise bottleneck).
- Is inexpensive (< $10).
- Is breadboard-friendly (preferably on a breakout board, or
  available in a hand-solderable package).

### Decision

Use the **Texas Instruments PCM5102A** (32-bit I2S DAC, 112 dB
SNR, TSSOP-20 package, ~$3 on a TSSOP-to-DIP breakout).

### Consequences

**Positive:**

- 32-bit I2S input is over-spec for the project (the FPGA
  outputs 24-bit), but the format is compatible.
- 112 dB SNR is *much* better than the INMP441's 61 dB; the
  DAC will not become the noise bottleneck.
- 2.1 V_RMS line-level output drives 32 Ω headphones at
  ~30 mW per channel (sufficient for normal listening).
- 3.3 V single supply; no expensive analog rails.
- ~$3 on a TSSOP-20 breakout; within the BOM budget.

**Negative:**

- TSSOP-20 is hand-solderable but requires care. A breakout
  board (~$3) is strongly recommended; the bare IC is
  not breadboard-friendly.
- The PCM5102A's mute / format pins need correct
  configuration at boot (XYLR/MUTE/SCLK routing); the
  PCB must include pull-ups/pull-downs on these pins.
- No hardware volume control; volume is software (via the
  ESP32's `REG_VOLUME` SPI write to the FPGA's spectral
  processor).

### Alternatives Considered

- **MAX98357A (Maxim Integrated).** I2S DAC with a built-in
  Class D amplifier (output drives a speaker directly).
  Considered for a future battery-powered wearable
  version; rejected for the breadboard prototype
  because the speaker adds distortion to the measurement
  setup.
- **PCM5100 (TI).** Older, 24-bit only. Rejected: the
  PCM5102A is pin-compatible and cheaper.
- **PT8211 (Princeton Technology).** Cheaper (~$1), but
  16-bit and lower SNR (90 dB). Rejected: insufficient
  headroom.
- **UDA1334A (NXP).** 24-bit, 95 dB SNR, but harder to
  source. Rejected: PCM5102A is more available and has
  a better SNR.
- **CS4344 (Cirrus Logic).** 24-bit, 101 dB SNR, TSSOP-10.
  Considered as a smaller-footprint alternative; rejected
  because the PCM5102A has more community support.

---

## ADR-005: 256-point FFT

**Status:** Accepted
**Date:** 2026-04

### Context

The DSP pipeline's FFT length is a central design parameter that
affects:

- **Frequency resolution.** At 48 kHz, the bin width is
  `f_s / N`. A 256-pt FFT gives 187.5 Hz per bin; a 128-pt
  FFT gives 375 Hz; a 512-pt FFT gives 93.75 Hz.
- **Algorithmic latency.** The pipeline waits one frame
  period of `N` samples. At 48 kHz: 256-pt = 5.33 ms;
  128-pt = 2.67 ms; 512-pt = 10.67 ms.
- **Resource cost.** The Xilinx xfft IP for 256-pt,
  16-bit data, pipelined streaming I/O uses ~3,000 LUTs
  and 2 BRAMs. The 512-pt IP is ~1.4× the LUTs and
  ~1.5× the BRAMs.
- **Spectral resolution per mode.** Hearing profiles typically
  need ~125 Hz resolution to capture the audiometric bins
  (250 Hz, 500 Hz, 1 kHz, 2 kHz, 4 kHz, 8 kHz). 256-pt
  gives 5.3 Hz per bin, which is more than enough;
  128-pt gives 10.7 Hz, which is also enough.

The perceptual threshold for headphone delay is 20 ms. The
project targets a total latency of < 8 ms, leaving ~2 ms of
budget for the analog and I2S codec pipeline.

### Decision

Use a **256-point FFT**, 50 % overlap-add, Hann window.

### Consequences

**Positive:**

- 128 unique frequency bins (the upper 128 are conjugates of
  the lower 128); the gain table is 128 entries × 16 bits =
  256 bytes per mode, easily stored in NVS.
- 5.3 Hz frequency resolution per bin; the Hearing mode can
  shape the response at every audiometric frequency with
  one or two bins of precision.
- 5.33 ms algorithmic latency; well under the 8 ms target
  (after adding ~2 ms of analog and I2S overhead).
- Fits in the XC7S25's resource budget: ~3,000 LUTs per
  FFT × 2 (FFT + IFFT) = 6,000 LUTs, plus ~4,000 LUTs for
  the rest of the pipeline = 10,000 LUTs, leaving 4,620
  LUTs of headroom (32 %).
- Standard size; well-supported by the Xilinx xfft IP, the
  `numpy.fft` Python tools, and any reference textbook.

**Negative:**

- The latency is *fixed* by the FFT length: 5.33 ms is the
  minimum, regardless of how the pipeline is optimised. A
  hearing-aid-class device with stricter latency
  requirements would need a 128-pt FFT.
- 5.3 Hz per bin is finer than the typical audiogram
  resolution; the per-bin gain table is over-sampled
  (a 6-band audiogram effectively controls 60+ bins).

### Alternatives Considered

- **128-point FFT.** Halves the latency to 2.67 ms and
  halves the resource cost, but halves the frequency
  resolution (10.7 Hz per bin). Still sufficient for
  audiogram-based gain; the smaller window has wider
  main lobe (8 bins vs 4 bins), which slightly blurs
  the spectral shaping. Rejected: the latency
  budget has headroom; 256-pt is more standard.
- **512-point FFT.** Doubles the frequency resolution
  (2.7 Hz per bin) but doubles the latency to 10.67 ms
  (exceeding the 8 ms total target) and pushes the
  resource cost past the budget. Rejected: exceeds
  the latency budget.
- **1024-point FFT.** Way too much latency (21.3 ms,
  above the perceptual threshold) and 3× the resource
  cost. Rejected: not viable.
- **Custom FFT (e.g., dblclockfft).** Smaller resource
  cost but more engineering effort. Considered as a
  fallback if the Xilinx IP does not fit; the Xilinx
  IP fits, so the custom path is not taken.

---

## ADR-006: Hann Window with 50 % Overlap

**Status:** Accepted
**Date:** 2026-04

### Context

The window function in an overlap-add pipeline determines the
spectral leakage of the analysis and the COLA (Constant
Overlap-Add) property of the synthesis. The choices are:

- **Rectangular window.** No leakage reduction, but the
  worst spectral leakage. No COLA property at 50 % overlap.
- **Hann window.** Moderate main-lobe width (4 bins), low
  side-lobe level (-31 dB). Satisfies COLA at 50 % overlap.
- **Hamming window.** Slightly lower side-lobe level (-43 dB)
  but **does not** satisfy COLA at 50 % overlap (only at
  75 % overlap or with a custom overlap factor).
- **Blackman window.** Very low side-lobe level (-58 dB) but
  very wide main lobe (8 bins). Does not satisfy COLA at
  50 % overlap.
- **Custom windows (e.g., Nuttall, Blackman-Harris).**
  Tighter side lobes at the cost of wider main lobes.
  Considered for specialised use cases; not needed here.

For a hearing-aid application, the spectral shaping needs to
be smooth (no comb filtering, no audible artefacts in the
overlap-add reconstruction). The Hann window is the standard
choice for 50 % overlap-add pipelines.

### Decision

Use the **Hann window** with **50 % overlap**, applied on both
analysis (before the FFT) and synthesis (after the IFFT).

### Consequences

**Positive:**

- COLA-satisfied: `w[n] + w[n + N/2] = 1.0` for all `n` in
  `[0, N/2 - 1]`. This means the overlap-add reconstruction
  is *exact* (no comb filtering, no amplitude ripple) when
  the gain table is flat. The Bypass mode is therefore
  audibly transparent by construction.
- Moderate main-lobe width (4 bins at –3 dB, 8 bins at
  –20 dB); the per-bin gain shaping is local in frequency
  and does not bleed into adjacent bins.
- Low side-lobe level (–31 dB); the gain shaping in one
  frequency band does not leak energy into distant bands.
- Symmetric; the synthesis window equals the analysis
  window, so the OLA reconstructor is just an add and a
  shift register (no extra multiplies).
- Coefficients are pre-computed by
  `tools/win_gen/gen_hann_coeffs.py` and stored in a 256 ×
  16-bit ROM; zero DSP48E1 cost on the synthesis side.

**Negative:**

- The Hann window's main-lobe width (4 bins) means a
  single-bin gain change affects the 4 bins around it. For
  sharp notches in the gain table (e.g., feedback-canceller
  notch filters), this is too wide; a narrower window (e.g.,
  Hamming at 25 % overlap) would be needed. Not relevant
  for the current project.
- The window attenuates the input by 6 dB at the frame
  centre; the OLA restores this, but the per-bin SNR is
  6 dB lower than the time-domain SNR. Acceptable for the
  current design.

### Alternatives Considered

- **Hamming window.** Lower side-lobe level (-43 dB) but
  does not satisfy COLA at 50 % overlap. Rejected:
  reconstruction is not exact.
- **Blackman window.** Lowest side-lobe level (-58 dB) but
  widest main lobe (8 bins). Rejected: over-smooths the
  spectral shaping.
- **Rectangular window.** No side-lobe suppression; severe
  spectral leakage. Rejected: would colour the output
  unacceptably.
- **Custom COLA-satisfying window (e.g., Hamming at 75 %
  overlap).** Possible, but the 50 % overlap of the Hann
  window is the lowest-overhead option and is universally
  understood.
- **WOLA (Weighted Overlap-Add) with a non-symmetric
  window.** More flexibility, more complexity. Rejected:
  not needed for the current project.

---

## ADR-007: SPI Register File for ESP32 → FPGA Configuration

**Status:** Accepted
**Date:** 2026-04

### Context

The ESP32 needs to configure the FPGA at runtime (mode, volume,
per-bin gain table). The interface choices are:

- **Parallel bus (8, 16, or 32 GPIO + chip-select).** Fast,
  but uses many pins (8–32) on both sides.
- **I2C (2-wire, addressable, multi-master capable).** Only
  2 pins, but limited to ~400 kHz in fast mode and ~1 MHz in
  fast-mode plus; too slow for bulk gain-table updates.
- **UART (asynchronous serial).** Simple, but flow control
  and framing are awkward at 10 MHz equivalent.
- **SPI (4-wire: SCLK, MOSI, MISO, CS_N).** 4 pins, well-
  understood, easy to DMA on the ESP32, supports the full
  10 MHz target.
- **QSPI / OSPI.** Higher bandwidth, but the FPGA side
  requires more I/O pins for the data lines. Rejected:
  not needed.

The configuration data is small (a mode change is 4 bytes;
a full gain-table update is 256 bytes). The data is
unidirectional from the ESP32 to the FPGA, except for
telemetry reads (a few bytes per second).

### Decision

Use a **4-wire SPI bus** (Mode 0, MSB first, up to 10 MHz)
with a **128 × 24-bit register file** on the FPGA.

### Consequences

**Positive:**

- 4 pins total on each side: SCLK, MOSI, MISO, CS_N. Both
  the Cmod S7-25 and the ESP32 have plenty of free GPIO.
- 10 MHz clock; one 32-bit transaction is 3.2 µs. A full
  gain-table update (128 bins × 4 bytes = 512 bytes) is
  ~52 µs, well under the 1 ms budget.
- Well-supported by the ESP32's hardware SPI peripheral
  (with DMA).
- 24-bit data width matches the FPGA's audio sample width
  and the project's Q2.14 gain table (16 bits, sign-extended
  to 24 bits in the register file).
- The register file (128 × 24 bits = 384 bytes) fits
  comfortably in ~3,072 flip-flops on the FPGA; no BRAM
  cost.

**Negative:**

- SPI requires a chip-select pin, which the ESP32 must
  manage explicitly.
- The 4-wire SPI does not scale well to multi-FPGA systems
  (each FPGA needs its own CS_N). Not relevant for the
  current single-FPGA project.
- The 10 MHz maximum is conservative; the ESP32 can do
  40 MHz. The 10 MHz limit is the FPGA's timing-closure
  constraint on the SPI input pad.

### Alternatives Considered

- **I2C.** 2 pins, but ~400 kHz max. A full gain-table
  update is ~5 ms at 400 kHz. Rejected: too slow for
  glitch-free mode changes.
- **UART.** Asynchronous, no clock pin, but the framing
  overhead and the absence of a hardware peripheral
  for the FPGA side make it awkward. Rejected:
  not the right tool.
- **8-bit parallel bus.** 10 pins total. The 256-bin
  gain table would need 4 separate writes per bin
  (low byte + high byte + address + control). Fast
  but pin-hungry. Rejected: SPI is sufficient.
- **16-bit parallel bus.** 18 pins. Even faster. Rejected:
  not enough free pins on the Cmod S7-25's Pmod
  connectors (8 pins per Pmod, including power and
  ground).

---

## ADR-008: Q2.14 Fixed-Point Arithmetic

**Status:** Accepted
**Date:** 2026-04

### Context

The DSP pipeline multiplies audio samples by gain coefficients
in the spectral processor. The arithmetic choices are:

- **Floating-point (IEEE 754 single precision).** 32 bits per
  operand, but the Xilinx floating-point IP is expensive
  (each multiply uses 2–4 DSP48E1 slices; 128 bins × 2
  multiplies per bin = 256–512 DSP48E1s, exceeding the
  XC7S25's 48 slices).
- **Q1.15 (16-bit signed, range [–1, +1)).** 16 bits per
  operand, but the range cannot represent a gain > 1.0
  (e.g., +6 dB ≈ 2.0×). Unsuitable.
- **Q2.14 (16-bit unsigned, range [0, 2.0)).** 16 bits per
  operand, range covers [0, 1.9999], which is sufficient
  for any hearing-aid gain (max +6 dB ≈ 2.0×). One
  DSP48E1 per multiply. Recommended.
- **Q4.12 (16-bit unsigned, range [0, 16)).** 16 bits per
  operand, wider range, but coarser fractional precision
  (1/4096 vs 1/16384). Not needed; +6 dB is the practical
  maximum.
- **Q0.16 (16-bit unsigned, range [0, 1)).** Cannot
  represent gain > 1.0. Unsuitable.

For the spectral processor's per-bin gain and the master
volume, the required range is [0, 2.0] (mute to +6 dB).
The required precision is ~0.01 dB (one 256th of a step),
which corresponds to a fractional step of
`2.0 / 2^16 ≈ 0.00003` — much finer than the 0.01 dB
target.

### Decision

Use **Q2.14 unsigned fixed-point** for all per-bin gains,
master volume, and noise-gate threshold.

### Consequences

**Positive:**

- 16 bits per value; fits in a single DSP48E1 multiplier
  operand.
- Range [0, 2.0) covers the full hearing-aid gain range
  (mute to +6 dB).
- Precision: 2.0 / 2^14 = 0.000122 per LSB, corresponding
  to ~0.001 dB. Finer than the human-perceptible threshold
  for gain changes.
- `0x4000 = 1.0×` (unity gain), `0x0000 = 0.0` (mute),
  `0x7FFF ≈ 1.9999` (max gain). Easy to reason about.
- No floating-point IP needed; the design uses only
  integer multiplies.
- Easy to generate in Python with
  `tools/common/fixed_point.py` (`q214_encode(value)`).

**Negative:**

- Q2.14 is unsigned; the *audio* it multiplies is a signed
  two's-complement integer. The spectral-proc RTL must
  use the appropriate multiplier mode.
- Values above 2.0 (e.g., +12 dB) cannot be represented;
  the gain table is limited to +6 dB. For a hearing aid
  this is sufficient (most prescriptive gains are < +6 dB),
  but a future revision that needs higher gains (e.g., a
  power hearing aid) would need a wider format.
- The fixed-point tools (`q214_encode`, `q214_decode`)
  are in `tools/common/fixed_point.py`; the
  gain-table generator must use them consistently.

### Alternatives Considered

- **Q1.15 (signed).** Range [–1, +1). Unsuitable: cannot
  represent gain > 1.0.
- **Q4.12.** Range [0, 16), but coarser precision
  (1/4096). Rejected: not needed; Q2.14 is sufficient.
- **IEEE 754 single precision.** Too expensive on the
  XC7S25 (each floating-point multiply uses 2–4
  DSP48E1s; 128 bins × 2 multiplies = 256–512 DSP48E1s,
  exceeding the 48 available). Rejected: resource
  budget.
- **Block floating-point (BFP).** Used internally by the
  Xilinx xfft IP for the FFT/IFFT data path; not
  appropriate for the gain coefficients (which are
  static). Rejected: wrong tool for the job.
- **18-bit fixed-point (Q4.14 or Q2.16).** The DSP48E1's
  native width is 18 × 25; using 18 bits gives one extra
  bit of precision or headroom. Considered; rejected
  because the gain range is well within 16 bits and the
  extra precision is not needed.

---

## 2. ADR Index

The 8 ADRs above are summarised here for quick reference:

| ID | Title | Status | Date |
|----|-------|--------|------|
| ADR-001 | Use Cmod S7-25 as FPGA Platform | Accepted | 2026-04 |
| ADR-002 | Use ESP32 as Controller | Accepted | 2026-04 |
| ADR-003 | Use INMP441 as Microphone | Accepted (R-01 in [`ROADMAP.md`](ROADMAP.md)) | 2026-04 |
| ADR-004 | Use PCM5102A as DAC | Accepted | 2026-04 |
| ADR-005 | 256-point FFT | Accepted | 2026-04 |
| ADR-006 | Hann Window with 50 % Overlap | Accepted | 2026-04 |
| ADR-007 | SPI Register File for ESP32 → FPGA Configuration | Accepted | 2026-04 |
| ADR-008 | Q2.14 Fixed-Point Arithmetic | Accepted | 2026-04 |

### 2.1 Future ADRs (to be written)

The following decisions are anticipated but not yet formalised:

- **ADR-009: Custom PCB vs breadboard for Phase 5.** The PCB
  decision is a 4-layer board, 50 mm × 70 mm, with the Cmod
  S7-25 and ESP32 as daughter boards. To be written when the
  schematic is finalised.
- **ADR-010: Bluetooth audio path (A2DP sink) for Phase 4.**
  The decision to use the ESP32's A2DP API vs an external
  BT module. To be written when the BLE architecture is
  implemented.
- **ADR-011: Battery management for Phase 5.** The decision
  to use a LiPo + TP4056 vs a USB power bank. To be written
  when the enclosure design is finalised.
- **ADR-012: WDRC vs linear amplification for Speech mode.**
  The decision to use a fixed gain table vs a WDRC LUT.
  To be written when the WDRC table generator is implemented.

### 2.2 Superseded ADRs

None. All current ADRs are still in effect.

---

## 3. Where to Read Next

- The implementation plan that uses these decisions is in
  [`docs/IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md).
- The architecture documents that show how these decisions
  fit together are in
  [`docs/architecture/`](architecture/).
- The risk register that tracks the consequences of these
  decisions is in
  [`docs/ROADMAP.md`](ROADMAP.md) §4.
- The measurement methodology that validates the
  performance claims made in these decisions is in
  [`docs/MEASUREMENT_METHODOLOGY.md`](MEASUREMENT_METHODOLOGY.md).
