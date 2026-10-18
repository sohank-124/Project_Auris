# Hardware Documentation

> **Project Auris** — FPGA-only hardware overview.
> **Last updated:** 2026-08-12 (FPGA-only migration)
> **Status:** Authoritative. The pin map below matches the
> canonical XDC at `fpga/constraints/arty_s7_25.xdc`. There is
> no ESP32, no SPI bus, and no external microcontroller in this
> build.

## Overview

Project Auris is a breadboard-prototype hearing-assistive
device that combines a **Digilent Arty S7-25** FPGA module
(Xilinx Spartan-7 XC7S25-1CSGA324C) with an **InvenSense
INMP441** I2S MEMS microphone and a **Texas Instruments
PCM5102A** I2S audio DAC. The FPGA implements the entire
signal-processing chain (256-point FFT pipeline with per-bin
gain and noise gating) **and** the entire control plane (mode
selection, volume, status indication). The user input surface
is the four onboard push buttons; the feedback surface is the
onboard RGB LED and two status LEDs.

There is no external microcontroller in this build. The FPGA
generates BCLK and LRCLK on-board via the MMCM in `clk_gen.sv`
and drives both the INMP441 (I²S slave) and the PCM5102A (I²S
slave). Audio flows into the FPGA from the INMP441, is
processed in real time, and is routed back out to the PCM5102A
which drives a 3.5 mm headphone output.

All interconnects are point-to-point jumper wires on a single
830-point solderless breadboard. No custom PCB exists yet —
see `hardware/schematics/` for the planned KiCad capture and
`hardware/mechanical/` for the planned enclosure.

## Pin Map

The complete pin map for the breadboard prototype. All signals
operate at **3.3 V LVCMOS** and share a common ground. The
FPGA is the **I2S master** (drives BCLK and LRCLK to both
codecs) and the **sole control plane**.

### Pmod JA — I²S interface (FPGA-driven clocks)

> Physical-hole convention: all Pmod references below are **physical
> hole numbers** on the 2×6 JA header (see `WIRING.md` §3 for the
> change notice and row-orientation check). Old signal names mapped:
> `JA4`→hole 7, `JA5`→hole 8, `JA6`→hole 9, `JA7`→hole 10.

| Signal | Direction | Physical hole | FPGA package pin | Voltage | Notes |
|--------|-----------|---------------|------------------|---------|-------|
| I²S BCLK   | FPGA → Codecs | Hole 7 | M16 | 3.3 V | 3.072 MHz, 50% duty cycle (FPGA-generated) |
| I²S LRCLK  | FPGA → Codecs | Hole 8 | M17 | 3.3 V | 48 kHz, 50% duty cycle (FPGA-generated) |
| I²S ADC data | INMP441 → FPGA | Hole 9 | M18 | 3.3 V | 24-bit, left-justified, MSB first, mono (L-chan) |
| I²S DAC data | FPGA → PCM5102A | Hole 10 | N18 | 3.3 V | 24-bit, MSB first, stereo |

### Pmod JA — power rails

| Physical hole | Net | Source |
|-----|-----|--------|
| Hole 5 (both rows: 5 and 11) | GND | Arty ground |
| Hole 6 (both rows: 6 and 12) | +3V3 | Arty 3.3 V rail (from onboard regulator) |

The pre-migration Pmod JA0–JA3 pins (SPI SCLK / MOSI / MISO /
CS_N) are **not** used in this build. They are exposed on the
Arty S7-25 PCB but the FPGA does not constrain them in the
canonical XDC.

### Onboard LEDs

| LED | FPGA package pin | Function | Drive |
|-----|------------------|----------|-------|
| STATUS0 (LED[0]) | E18 | 1 Hz heartbeat — toggles when the FPGA is healthy and out of reset | Active-high |
| STATUS2 (LED[2]) | G15 | Sticky clip-event indicator — set when the DSP pipeline detects a clipping sample | Active-high |
| RGB LED 0 — R | J15 | Mode indicator (red channel) | Active-low |
| RGB LED 0 — G | G17 | Mode indicator (green channel) | Active-low |
| RGB LED 0 — B | F15 | Mode indicator (blue channel) | Active-low |

> **LED[1] conflict.** The Digilent master XDC assigns LED[1]
> to F13; the FPGA-only build instead assigns F13 to BTN2.
> The clip indicator is moved to LED[2] (G15). This is
> documented in `fpga/constraints/arty_s7_25.xdc` §3 and §5.

### Onboard push buttons (active-low)

| Button | FPGA package pin | Function |
|--------|------------------|----------|
| BTN0 | C12 | Mode increment (cycles General → Speech → Music → Hearing → wrap) |
| BTN1 | C11 | Mode decrement |
| BTN2 | F13 | Volume up (saturates at 31 = unity) |
| BTN3 | E13 | Volume down (saturates at 0 = mute) |

All four buttons are debounced in the FPGA by `btn_debounce.sv`
(20 ms debounce; press and release edge pulses). The mode and
volume FSMs are inline `always_ff` blocks in `top.sv`; they
operate in `CD_DSP` (96 MHz) and do not cross any clock domain.

### Onboard 12 MHz oscillator

The Arty S7-25's onboard 12 MHz oscillator feeds the MMCM in
`clk_gen.sv`. The MMCM multiplies to 600 MHz VCO and divides
to produce the 96 MHz `CD_DSP` clock. The 12 MHz oscillator is
on package pin **F14** (Bank 15, 3.3 V LVCMOS).

## Power

The FPGA-only build runs from a single USB cable to the Arty
S7-25. The Arty's onboard regulators produce the 3.3 V, 1.8 V,
and 1.0 V rails. The INMP441 always runs from the Arty's Pmod
JA 3.3 V rail (pin 6). The PCM5102A power depends on the module
variant (see `WIRING.md` §5):

- **Variant A (3.3 V direct):** DAC from Pmod JA 3.3 V rail (pin 6).
- **Variant B (5 V VIN with onboard LDO, e.g. DORHEA B0DCFN2JGF):**
  DAC `VIN` from 5 V — Arty Arduino-header 5V0 pin or an external
  USB 5 V breakout. Onboard LDO makes 3.3 V for the chip. All
  I2S signals stay 3.3 V logic; all grounds (Arty, mic, DAC, 5 V
  supply) must be common. Never put 5 V on any FPGA I/O pin.

| Rail | Source | Consumers | Estimated Current |
|------|--------|-----------|--------------------|
| 5 V  | USB (Arty) / Arduino 5V0 / external 5 V | Arty onboard regulators + Variant B DAC VIN | ~500 mA (USB limit) |
| 3.3 V| Arty 3V3 rail | INMP441, DAC logic refs (XSMT/SCK/FMT), Variant A DAC, FPGA I/O | ~50 mA combined |

### Power distribution rules

- **Arty S7-25** is powered from its Micro-USB jack (5 V input).
  The module has onboard switching regulators that produce
  3.3 V, 1.8 V, and 1.0 V rails. The 3.3 V rail is exposed on
  the Pmod headers (pin 6 is +3V3, pin 5 is GND). A 5 V rail is
  available on the Arduino-shield header (5V0) for Variant B DACs.
- **INMP441** is powered from the 3.3 V rail of the Arty Pmod
  JA header (pin 6). Maximum supply current is ~1.4 mA.
- **PCM5102A Variant A** is powered from the 3.3 V rail of the
  Arty Pmod JA header (pin 6). Maximum supply current is ~30 mA.
  Typical supply current is ~20 mA at full-scale output into
  32 Ω headphones. The DAC's charge pump requires the full
  3.3 V supply; do not power it from 1.8 V.
- **PCM5102A Variant B (5 V VIN)** is powered from 5 V into `VIN`
  (Arduino 5V0 or external 5 V, ~20–30 mA). The module's onboard
  LDO produces the chip 3.3 V. `XSMT` still goes to 3.3 V (never
  5 V — abs-max DVDD+0.3 V); `BCK`/`DIN`/`LRCK` stay 3.3 V FPGA
  logic; GNDs must be common.
- **Headphones** are driven directly from the PCM5102A's
  line-driver outputs (no external amplifier needed for
  typical 16–32 Ω headphones at moderate listening levels).
- **No ESP32.** The pre-migration build had a second USB cable
  and a LiPo battery; the FPGA-only build has neither.

## Current Budget Estimate

| Block | Current @ 3.3 V |
|-------|-----------------|
| Arty S7-25 (incl. FPGA) | ~150 mA |
| INMP441 | ~1.4 mA |
| PCM5102A | ~20 mA |
| **Total** | **~172 mA** |

The shared 3.3 V rail on the Arty is rated for ~500 mA; this
leaves plenty of headroom.

## Related Documents

- [`WIRING.md`](./WIRING.md) — Step-by-step breadboard wiring
  guide for the FPGA-only build.
- [`BOM.md`](./BOM.md) — Top-level bill of materials with cost
  summary.
- [`../../hardware/bom/bom.csv`](../../hardware/bom/bom.csv) —
  Detailed CSV bill of materials (vendor part numbers,
  footprints, datasheets).
- [`../../hardware/bom/README.md`](../../hardware/bom/README.md) —
  BOM directory documentation.
- [`../../hardware/schematics/README.md`](../../hardware/schematics/README.md) —
  Planned KiCad schematic capture.
- [`../../hardware/mechanical/README.md`](../../hardware/mechanical/README.md) —
  Planned enclosure and mechanical design.
- [`../architecture/block_diagram.md`](../architecture/block_diagram.md) —
  System block diagram.
- [`../architecture/clock_domains.md`](../architecture/clock_domains.md) —
  Clocking architecture (two-domain model).
- [`../architecture/modes_and_gains.md`](../architecture/modes_and_gains.md) —
  Per-mode gain tables and LED colour mapping.
- [`../fpga_only_architecture.md`](../fpga_only_architecture.md) —
  Single-pane-of-glass architecture overview.
- [`../IMPLEMENTATION_PLAN.md`](../IMPLEMENTATION_PLAN.md) —
  HISTORICAL — pre-migration implementation plan (banner added
  2026-08-12).