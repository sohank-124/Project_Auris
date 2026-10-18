# Wiring Guide

> **Project Auris** — Step-by-step breadboard wiring for the
> FPGA-only build.
> **Last updated:** 2026-08-12 (FPGA-only migration)
> **Status:** Authoritative for the current FPGA-only architecture.
> This document supersedes the pre-migration ESP32 + FPGA wiring
> guide. There is no ESP32, no SPI bus, and no external
> microcontroller in this build.

This document is the step-by-step procedure for assembling the
Project Auris breadboard prototype. Follow the steps in order.
Each step produces a verifiable sub-system (FPGA bitstream
loads, I2S clocks appear on the scope, mic captures audio, DAC
plays audio) before moving on.

The canonical board is a **Digilent Arty S7-25 (Rev. E)** —
Spartan-7 XC7S25-1CSGA324C — with two audio codecs wired
point-to-point on a single 830-point solderless breadboard. The
FPGA is the **I2S master**: it generates BCLK and LRCLK
on-board via the MMCM in `clk_gen.sv` and drives the codecs. The
codecs (INMP441 MEMS mic and PCM5102A DAC) are I2S slaves.

The FPGA is also the **sole control plane**: there is no
ESP32, no SPI slave, no register file, and no firmware at
runtime. The four onboard push buttons (BTN0–BTN3) drive the
mode and volume FSMs in `top.sv`; the RGB LED indicates the
active mode; the STATUS LEDs report pipeline health.

---

## 1. Required Components

| Item | Qty | Notes |
|------|-----|-------|
| Arty S7-25 (FPGA module) | 1 | Digilent 410-346 |
| INMP441 I2S MEMS microphone (breakout board) | 1 | TDK / InvenSense |
| PCM5102A I2S DAC (breakout board) | 1 | Texas Instruments — see DAC voltage variants below |
| 830-point solderless breadboard | 1 | |
| Male-male jumper wires | ~20 | Various lengths |
| Male-female jumper wires | ~10 | For Pmod-to-peripheral (Arty Pmod JA to codec headers) |
| 5 V source for DAC VIN (Variant B only) | 1 | Arty Arduino-header 5V0 pin OR external USB 5 V breakout / breadboard supply — see §5–§6 |

> **DAC voltage variants — read this before wiring power.**
> There are two GY-PCM5102 module types that look identical:
> - **Variant A (3.3 V direct):** `VCC` takes 3.3 V from Pmod JA hole 6.
>   Bare TSSOP-20 / some RPi breakouts. Follows the original §5/§6 as written.
> - **Variant B (5 V VIN with onboard LDO, e.g. DORHEA B0DCFN2JGF):**
>   listing says `Supply Voltage: 5V`, 7 pins. The module has an onboard
>   3.3 V regulator: 5 V into `VIN` → 3.3 V to the PCM5102A chip.
>   Power `VIN` from **5 V only** (Arduino-header 5V0 or external 5 V),
>   **never** from Pmod 3.3 V (LDO dropout would starve the chip to ~2.2 V).
>   I2S signals stay 3.3 V from Pmod JA in both variants, and all grounds
>   must be common. §5 and §6 below give both wirings.
| USB-A to Micro-USB cable | 1 | For Arty S7-25 (programming + power) |
| 3.5 mm headphones or earbuds | 1 | For DAC output verification |
| Oscilloscope or logic analyzer (recommended) | 1 | For debug |

See [`BOM.md`](./BOM.md) and
[`../../hardware/bom/bom.csv`](../../hardware/bom/bom.csv) for full
part numbers and vendor links.

> **No ESP32.** The pre-migration build had an ESP32-DevKitC-32E
> co-processor; the FPGA-only build does not. There is no second
> USB cable, no ESP-IDF toolchain, and no firmware to flash.

---

## 2. Before You Begin

### 2.1 Safety

1. **Power off before wiring.** Always disconnect the USB cable
   before inserting or removing jumper wires. A loose wire
   bridging 3.3 V to a signal pin can latch-up or destroy the
   FPGA.
2. **Verify voltage levels.** All signals are 3.3 V LVCMOS. Do
   not connect a 5 V source to any signal pin.
3. **Common ground is mandatory.** The Arty's GND and the codec
   GNDs must share a ground reference. Tie their GND pins
   together on the breadboard before powering up.
4. **Anti-static precautions.** The Arty S7-25 and the PCM5102A
   are ESD-sensitive. Work on an anti-static mat if available.

### 2.2 Breadboard orientation

- Place the breadboard with the **red rail (+) on the right**
  and the **blue rail (-) on the left**. Most breadboards are
  labelled.
- Power rails run vertically along both edges. Use the right-hand
  red rail for 3.3 V and the left-hand blue rail for GND.
- The Arty S7-25 should be seated at one end of the breadboard
  with the INMP441 and PCM5102A in the middle, leaving room
  for jumpers.

### 2.3 Suggested wire-colour convention

| Color      | Function                       |
|------------|--------------------------------|
| White      | I2S BCLK                       |
| Gray       | I2S LRCLK                      |
| Pink       | INMP441 SD (DATA, to FPGA)     |
| Lime       | PCM5102A DIN (DATA, from FPGA) |
| Red        | 3.3 V power                    |
| Black      | Ground                         |

The pre-migration SPI bus (orange / yellow / green / blue
wires) is **not** needed in this build. The ESP32 is gone.

---

## 3. Step 1 — Pmod JA I²S Wiring (FPGA → Codecs)

> **CHANGE NOTICE (physical-hole convention).** This guide used to
> name these pins `JA4–JA7` (Digilent *signal* names). Those names
> collide with the connector's *physical hole numbers* — physical
> hole 5 is GND, not a signal — and caused a real miswire scare.
> From here on, **every Pmod reference in this guide is the physical
> hole number** on the 2×6 JA header (1–6 one row, 7–12 the other).
> Old → new mapping (identical copper, new words only):
> `JA4` → **hole 7** (BCLK), `JA5` → **hole 8** (LRCLK),
> `JA6` → **hole 9** (mic data), `JA7` → **hole 10** (DAC data).
> Pmod power holes 5/11 = GND, 6/12 = 3V3 (unchanged, already physical).
> The historical docs (`migration_summary.md`, forensic audit) keep the
> old names — they are dated records, not wiring instructions.

The FPGA drives BCLK and LRCLK to both codecs. Both the INMP441
and the PCM5102A latch on the FPGA-supplied clocks. The
INMP441 drives SD back to the FPGA; the PCM5102A receives DIN
from the FPGA. The four I²S signals live on **physical holes 7–10**
of the Pmod JA header on the **top** edge of the Arty S7-25 PCB.
Hole numbering runs **left to right starting at hole 1 (far left)
when the Micro-USB jack faces you**: holes 1–6 in one row, holes
7–12 in the other, with GND at the 5th position and 3V3 at the 6th
position of *each* row.

| Physical hole | FPGA package pin | FPGA signal | Codec pin (INMP441 / PCM5102A) |
|---------------|------------------|-------------|-------------------------------|
| Hole 7 | M16 | `i2s_bclk_o` (FPGA drives) | INMP441 SCK + PCM5102A BCK |
| Hole 8 | M17 | `i2s_lrclk_o` (FPGA drives) | INMP441 WS + PCM5102A LRCK |
| Hole 9 | M18 | `i2s_adc_data_i` (FPGA receives) | INMP441 SD only |
| Hole 10 | N18 | `i2s_dac_data_o` (FPGA drives) | PCM5102A DIN only |
| Holes 5 and 11 | — | GND | Common ground (both rows) |
| Holes 6 and 12 | — | 3V3 | 3.3 V rail (both rows) |
| Holes 1–4 | — | (old SPI, unused) | **Leave empty** |

> **Which row is 1–6? Read this before plugging anything.**
> Digilent's docs fix left-to-right order (hole 1 at the far left)
> but do not state in text which of the two physical rows holds
> holes 1–6 on the S7's top edge — so identify, don't assume:
> 1. Find the **pin-1 marker** on the silkscreen (square pad or small
>    arrow at one end of the JA header). The row containing hole 1
>    is the 1–6 row; the other row is 7–12.
> 2. Meter check (USB unplugged): the 5th hole of *each* row beeps
>    continuity to Arduino-header GND — those are holes 5 and 11.
>    This fixes your counting direction along both rows.
> 3. Definitive check (bitstream programmed, scope): the hole with a
>    3.072 MHz square wave is **hole 7 (BCLK)**; 48 kHz beside it is
>    **hole 8 (LRCLK)**. If your assumed hole 7 is silent, you are
>    looking at the wrong row — no damage done (all logic pins are
>    3.3 V), just switch rows.
> Holes 1–4 connect to undriven FPGA inputs in this build: wiring a
> codec there gives silence, not damage — but the scope check above
> catches it in seconds.

> **Direction reminder.** BCLK and LRCLK were previously *inputs*
> to the FPGA when the ESP32 was the I2S master. In the FPGA-only
> build the FPGA generates both clocks on-board (see `clk_gen.sv`)
> and now *drives* them out to the codecs.

**Verification**

With the Arty powered (USB connected) and the FPGA bitstream
loaded:

1. Use a logic analyzer or scope on hole 7 (BCLK) — you should see
   a 3.072 MHz square wave, 50% duty cycle.
2. Use a logic analyzer or scope on hole 8 (LRCLK) — you should see
   a 48 kHz square wave, 50% duty cycle.
3. The two should be phase-locked: every 64 BCLK periods, LRCLK
   toggles.
4. If either clock is missing, check that the bitstream has been
   successfully programmed into flash (the green "DONE" LED on
   the Arty is on) and that the MMCM achieved lock (the STATUS0
   heartbeat LED is toggling at 1 Hz).

---

## 4. Step 2 — INMP441 MEMS Microphone

The INMP441 is a bottom-port MEMS microphone with a digital I²S
output. It is powered from the Arty's Pmod 3.3 V rail and clocked
by the FPGA's I²S clocks (which the FPGA generates on-board).

| Arty Pmod hole | INMP441 Pin  | Wire Color | Signal       | Notes                                       |
|---------------|--------------|------------|--------------|---------------------------------------------|
| Hole 7        | SCK          | White      | I2S BCLK     | 3.072 MHz from FPGA (shared with DAC)       |
| Hole 8        | WS           | Gray       | I2S LRCLK    | 48 kHz from FPGA (shared with DAC)          |
| Hole 9        | SD           | Pink       | I2S DATA     | INMP441 → FPGA, 24-bit, MSB first, L-chan   |
| (unused)      | L/R          | Black      | Channel sel  | Tie to GND = left channel                   |
| Pmod JA hole 6 | VDD         | Red        | 3.3 V power  | From Arty 3.3 V rail                        |
| Pmod JA hole 5 | GND         | Black      | Ground       | Common ground with Arty                     |

### 4.1 INMP441 pin reference (typical breakout board)

```
     +-------+
 VDD | 1   6 | L/R     (left/right channel select)
 GND | 2   5 | SCK
  SD | 3   4 | WS
     +-------+
```

### 4.2 Caveats

- Tie **L/R to GND** so that the INMP441 transmits on the left
  channel of the I²S frame. If tied to VDD it transmits on the
  right channel; if floating, the channel is undefined.
- The INMP441's **bottom acoustic port** must be unobstructed.
  Most breakout boards expose this through a hole on the
  underside of the PCB. Do not place the breakout face-down on
  the breadboard — leave a gap or stand it off.
- Place a **0.1 µF decoupling capacitor** between VDD and GND,
  as close to the INMP441 breakout as practical. The Arty's
  Pmod 3.3 V rail can be noisy during FPGA configuration.

### 4.3 Verification

With the FPGA bitstream loaded and the BCLK/LRCLK running:

1. Probe hole 9 (SD) with a scope. You should see data transitions
   once per audio sample (~48 kHz frame rate). The data line is
   idle-low when no sample is being transmitted.
2. The FPGA's `STATUS0` heartbeat LED continues to toggle at
   1 Hz, confirming the pipeline is alive.
3. Speak or tap near the mic and watch the I2S DATA line
   activity change.

---

## 5. Step 3 — PCM5102A DAC

The PCM5102A is a 32-bit I²S audio DAC with a built-in headphone
driver and charge-pump line driver. It is configured for
**I²S format** (FMT tied low), **internal system clock** (SCK
tied low — the DAC derives its internal clock from BCLK), and
**unmuted** (XSMT tied high).

| Arty Pmod hole | PCM5102A Pin | Wire Color | Signal       | Notes                                       |
|---------------|--------------|------------|--------------|---------------------------------------------|
| Hole 7        | BCK          | White      | I2S BCLK     | 3.072 MHz from FPGA (shared with mic) — 3.3 V logic in BOTH variants |
| Hole 8        | LRCK         | Gray       | I2S LRCLK    | 48 kHz from FPGA (shared with mic) — 3.3 V logic in BOTH variants |
| Hole 10       | DIN          | Lime       | I2S DATA     | FPGA → PCM5102A, 24-bit, MSB first — 3.3 V logic in BOTH variants |
| (unused)      | SCK          | Black      | Sys clock    | Tie to GND = use BCLK as clock ref          |
| (unused)      | FMT          | Black      | Format sel   | Tie to GND = standard I2S                   |
| (unused)      | DEMP         | Black      | De-emphasis  | Tie to GND = no de-emphasis                 |
| (unused)      | FLT          | Black      | Filter sel   | Tie to GND = normal-latency filter          |
| Breadboard 3V3| XSMT         | Red        | Soft mute    | Tie HIGH to 3.3 V = unmuted (LOW = muted). NEVER tie to 5 V — XSMT abs-max is DVDD+0.3 V |
| **Variant A:** Pmod JA hole 6 | VCC (AVCC + DVDD) | Red | 3.3 V power | 3.3 V-direct modules only: tie AVCC, DVDD, CPVDD all to 3.3 V |
| **Variant B:** 5 V source | VIN (5 V) | Orange/red | 5 V power | 5 V-VIN modules only (e.g. DORHEA B0DCFN2JGF): VIN → Arduino-header 5V0 OR external 5 V. Onboard LDO makes 3.3 V for the chip |
| Pmod JA hole 5 | GND (AGND + DGND) | Black | Ground     | Common ground with Arty — MANDATORY in both variants; tie 5 V-supply GND here too |

### 5.1 PCM5102A pin reference (TSSOP-20)

```
                +--------+
        CPVDD  | 1  20  | XSMT
         CPN   | 2  19  | FLT
        VINL   | 3  18  | DEMP
        VINR   | 4  17  | FMT
      VOUTL+   | 5  16  | SCK
      VOUTL-   | 6  15  | DIN
      VOUTR+   | 7  14  | BCK
      VOUTR-   | 8  13  | LRCK
         AGND  | 9  12  | DGND
         AVCC  |10  11  | DVDD
                +--------+
```

### 5.2 Caveats

- **Identify your variant first.** If the listing says `Supply: 5V`
  (e.g. DORHEA B0DCFN2JGF, 7-pin GY-PCM5102) you have Variant B:
  `VIN` needs 5 V. If it says 3.3 V / shows `VCC` with no regulator
  (bare TSSOP-20), you have Variant A. When in doubt, look at the
  module back for `AMS1117-3.3` (LDO = Variant B) or a `VIN` vs
  `VCC` label.
- **Variant B power rule.** `VIN` → 5 V (Arduino-header 5V0 or
  external 5 V breakout). Powering `VIN` from Pmod 3.3 V starves
  the chip through LDO dropout (~3.3 V in → ~2.2 V out) → mute,
  distortion, or charge-pump failure. Powering any FPGA I/O pin
  (holes 7/8/10) from 5 V destroys the FPGA — Arty I/O is 3.3 V
  LVCMOS only, NOT 5 V-tolerant.
- **Common ground is non-negotiable for Variant B.** The 5 V
  supply GND, Arty GND (Pmod pin 5), mic GND, and DAC GND must all
  tie to the breadboard blue rail. Without this, I2S has no voltage
  reference and reads as noise.
- **FMT to GND** selects standard I²S (Philips) format. If you
  want left-justified format, tie FMT to VCC instead.
- **XSMT to 3.3 V** is mandatory for any audio output. If you
  leave XSMT floating or tied low, the DAC is in software mute
  and you will hear silence. Never tie XSMT to 5 V (abs-max
  DVDD+0.3 V).
- **Decoupling is essential.** Place the following capacitors as
  close to the PCM5102A as possible:
  - 0.1 µF ceramic between AVCC and AGND
  - 0.1 µF ceramic between DVDD and DGND
  - 10 µF electrolytic (or tantalum) between VCC and GND (bulk)
  - The charge-pump flying capacitor (220 nF typical) between
    CPVDD and CPN is **internal** to the PCM5102A on the
    TSSOP-20 package; no external flying cap is needed.
- The headphone output is the line-driver output (VOUTL+,
  VOUTL-) wired through a 3.5 mm jack. Most PCM5102A breakouts
  have this jack already onboard.

### 5.3 Verification

With the FPGA bitstream loaded, the I2S clocks running, and a
test tone playing (the FPGA's General mode produces unity-gain
audio — the mic input should pass through cleanly):

1. Probe hole 10 (DIN) with a scope — you should see I2S data
   toggling at the sample rate.
2. Plug headphones into the DAC's 3.5 mm jack. You should hear
   the mic input at unity gain. If you hear nothing, check XSMT
   (must be high) and verify the FMT pin matches the FPGA's
   I2S_TX format.
3. If you hear distorted audio, check that BCLK is exactly
   64 × LRCLK (i.e., 3.072 MHz and 48 kHz) and that the data
   is MSB-first.

---

## 6. Step 4 — Power Distribution

Power starts as 5 V over USB to the Arty S7-25. The Arty's
onboard regulators make 3.3 V / 1.8 V / 1.0 V. The mic always
runs from 3.3 V. The DAC depends on its variant (§5):

- **Variant A (3.3 V direct):** DAC also from Pmod 3.3 V.
- **Variant B (5 V VIN, e.g. DORHEA B0DCFN2JGF):** DAC `VIN` from
  5 V (Arty Arduino-header 5V0 pin OR external USB 5 V breakout).
  DAC `GND` still ties to the common ground rail. Signals stay 3.3 V.

```
                +-------------+
   Micro-USB -->| Arty S7-25  |
                |             |
                |        3V3 o|------> Pmod JA hole 6  (3.3 V rail) --> INMP441 VDD + DAC XSMT + DAC SCK/FMT GND refs
                |        5V0 o|------> [Variant B only] Arduino-header 5V0 --> DAC VIN (5 V)
                |        GND o|--+---> Pmod JA hole 5  (ground)
                +-------------+  |
                                 |
                       +---------+---------+
                       |    breadboard GND  |<--- external 5 V supply GND (Variant B, if used)
                       +---------+---------+
                                 |
                       +---------+---------+----------+
                       |         |                    |
                  +----+----+ +--+----+         +-----+-----+
                  | INMP441 | |PCM5102A|         | (no ESP32)|
                  |  VDD    | | VIN/VCC|         +-----------+
                  |  GND    | | GND    |
                  +---------+ +--------+
```

### 6.1 Wire the breadboard power rails

1. Connect the Arty's **GND** (Pmod pin 5) to the breadboard's
   blue ground rail. **All** device grounds connect here — including
   the external 5 V supply GND if you use one for Variant B.
2. Connect the Arty's **3V3** (Pmod pin 6) to the breadboard's
   red power rail. The INMP441, DAC logic refs (XSMT high), and
   Variant A DAC power come from this rail.
3. **[Variant B only]** Run a separate orange/red wire for 5 V:
   Arduino-header 5V0 → breadboard terminal strip → DAC `VIN`.
   Keep it off the 3.3 V red rail. Label it.

### 6.2 Power the INMP441 (both variants, unchanged)

- Connect INMP441 **VDD** to Pmod JA hole 6 (3.3 V) or to the
  breadboard red power rail.
- Connect INMP441 **GND** to Pmod JA hole 5 (GND) AND to the
  breadboard ground rail.
- Place a 0.1 µF decoupling cap across VDD and GND, close to
  the breakout.

### 6.3 Power the PCM5102A

- **Variant A (3.3 V direct):**
  Connect PCM5102A **AVCC**, **DVDD**, and **CPVDD** all to
  Pmod JA hole 6 (3.3 V).
  Connect **AGND** and **DGND** all to Pmod JA hole 5
  (GND) AND to the breadboard ground rail.
- **Variant B (5 V VIN, e.g. DORHEA B0DCFN2JGF):**
  Connect module **VIN** to 5 V (Arduino 5V0 or external 5 V).
  Connect module **GND** to Pmod JA hole 5 AND the ground rail.
  `XSMT` still goes to **3.3 V** (never 5 V). `SCK`/`FMT`/`DEMP`/`FLT`
  still go to **GND**. I2S `BCK`/`DIN`/`LRCK` still come from holes 7/10/8
  at 3.3 V logic.
- Place 0.1 µF decoupling caps on each supply pin and a 10 µF
  bulk cap on VCC (Variant A). Variant B modules already include
  bulk/LDO caps onboard; an extra 10 µF near VIN is still good practice.

### 6.4 Sanity check

Before connecting USB:

1. Use a multimeter in continuity mode to verify that all GND
   points are tied together (Arty GND, breadboard ground rail,
   INMP441 GND, PCM5102A GND).
2. Verify that no 3.3 V rail is shorted to ground (multimeter
   in resistance mode, expect > 1 kΩ).
3. Verify that the INMP441 and PCM5102A signal pins are **not**
   shorted to 3.3 V or GND (would indicate a wiring mistake).

---

## 7. Step 5 — USB Connection

After all signal and power wiring is complete and visually
inspected:

1. **Connect the Arty S7-25** to the host computer with a USB-A
   to Micro-USB cable. This provides power and the
   programming/JTAG link to the FPGA.
2. The host should enumerate one USB serial port (the Arty
   appears as a Digilent programmer).
3. **Do not** power the board from a charger-style USB supply
   during development — you need the data lines connected for
   programming.
4. There is no second USB cable. The ESP32 is gone; there is
   no firmware to flash.

---

## 8. Buttons and Indicators

The user input and feedback surfaces are all **onboard** the
Arty S7-25. No additional wiring is required. The pin
assignments are documented in
[`fpga/constraints/arty_s7_25.xdc`](../../fpga/constraints/arty_s7_25.xdc)
and the FPGA package pins are C12, C11, F13, E13 for BTN0–BTN3
and J15, G17, F15 for RGB LED 0.

| Button / LED | Function | Notes |
|--------------|----------|-------|
| BTN0 | Mode increment (General → Speech → Music → Hearing → wrap) | Active-low; debounced in `btn_debounce.sv` |
| BTN1 | Mode decrement | Active-low |
| BTN2 | Volume up (saturates at 31 = unity) | Active-low; shares F13 with the pre-migration clip LED — clip LED has moved to LED[2] (G15) to yield the pin to BTN2 |
| BTN3 | Volume down (saturates at 0 = mute) | Active-low |
| STATUS0 (LED[0]) | 1 Hz heartbeat — toggles when the FPGA is healthy and out of reset | Active-high |
| STATUS2 (LED[2]) | Sticky clip-event indicator — set by the DSP pipeline when the input sample saturates; cleared only by FPGA reset | Active-high; moved from LED[1] (see BTN2 note above) |
| RGB LED 0 | Mode indicator — green=General, blue=Speech, magenta=Music, red=Hearing | Active-low |

---

## 9. Verification

After assembly, perform these checks in order.

### 9.1 Pre-power checks (no USB connected)

- [ ] Visual inspection: every wire goes from the documented
      source pin to the documented destination pin.
- [ ] Continuity test: all GND points are common (Arty GND, mic
      GND, DAC GND, external 5 V GND if Variant B).
- [ ] Continuity test: no 3.3 V rail is shorted to GND.
- [ ] Continuity test (Variant B): no 5 V VIN rail is shorted to
      GND, and 5 V is NOT connected to any JA signal pin
      (holes 7/8/9/10), XSMT, SCK, or FMT.
- [ ] Continuity test: no signal pin is shorted to 3.3 V or GND
      (this would indicate a wire in the wrong hole).

### 9.2 Power-on checks

- [ ] Arty S7-25 power LED is on (typically green or blue).
- [ ] 3.3 V rail measures 3.30 ± 0.10 V with a multimeter.
- [ ] Variant B only: DAC VIN measures 5.0 ± 0.25 V, and the
      module's onboard 3.3 V point (if exposed) measures
      3.30 ± 0.15 V.

### 9.3 FPGA bring-up

- [ ] Program the FPGA bitstream (see
      [`docs/fpga_only_architecture.md`](../fpga_only_architecture.md)
      for the canonical workflow). The Arty's "DONE" LED lights
      when programming succeeds.
- [ ] STATUS0 (heartbeat) is toggling at 1 Hz (verify with a
      phone stopwatch or by counting flashes over 10 seconds).
- [ ] RGB LED shows the General-mode colour (green on active-low
      Arty S7-25).
- [ ] Probe hole 7 — 3.072 MHz square wave, 50% duty cycle.
- [ ] Probe hole 8 — 48 kHz square wave, 50% duty cycle.
- [ ] Verify phase lock: BCLK period × 64 = LRCLK period.

### 9.4 I²S microphone

- [ ] Probe hole 9 (SD) — 24-bit data frames once per LRCLK period.
- [ ] Speak or tap near the mic; the FPGA's input sample stream
      should show non-trivial variation (you can verify this via
      the post-CDC observation points in `top.sv` with an ILA).
- [ ] If you have a spare DAC or headphone amp, you can route
      the mic stream directly to it (bypassing the DSP) as a
      sanity check.

### 9.5 I²S DAC

- [ ] Probe hole 10 (DIN) — 24-bit data frames once per LRCLK period.
- [ ] Plug in headphones; you should hear the mic input at
      unity gain (General mode is the default after FPGA reset).
- [ ] Verify the headphone output level with a multimeter on AC
      volts — a full-scale sine should produce ~0.5–1.0 V RMS
      at the jack.

### 9.6 End-to-end

- [ ] Speak into the microphone; hear your voice in the
      headphones with a short, fixed latency (typically < 10 ms
      in this design — 5.33 ms algorithmic + ~1 ms I2S codec
      pipeline).
- [ ] Press BTN0 several times; observe the RGB LED cycle
      green → blue → magenta → red → green.
- [ ] Press BTN2 several times; observe a louder output
      (volume level increases until it saturates at 31).
- [ ] Press BTN3 several times; observe a quieter output
      (volume level decreases until it mutes at 0).

### 9.7 Mode-specific verification (deeper)

- [ ] In Speech mode (blue LED), the speech band should be
      boosted relative to General mode.
- [ ] In Music mode (magenta LED), low and high frequencies
      should be slightly lifted relative to General mode.
- [ ] In Hearing mode (red LED), high frequencies should be
      boosted relative to General mode.

---

## 10. Troubleshooting

### 10.1 No audio output

1. **XSMT is floating or low.** The PCM5102A is in soft mute.
   Check that XSMT is tied to 3.3 V (never 5 V).
2. **Variant B powered from 3.3 V by mistake.** If DAC VIN reads
   ~3.3 V instead of ~5 V, the onboard LDO starves the chip
   (~2.2 V) → silence or distortion. Move VIN to Arduino 5V0 or
   external 5 V.
3. **5 V on a signal pin.** If holes 7/8/10 ever saw 5 V, stop —
   inspect for FPGA damage, rewire to 3.3 V logic only.
4. **Wrong I2S format.** FMT is high (left-justified) but the
   FPGA is sending standard I2S (or vice versa). Verify FMT is
   low and that the FPGA's `i2s_tx` block is configured for
   standard I2S.
3. **BCLK is not running.** The DAC needs a continuous bit
   clock. Probe hole 7 and confirm 3.072 MHz.
4. **Wrong clock ratio.** The DAC expects 64 × BCLK per LRCLK
   period. Confirm 3.072 MHz and 48 kHz.
5. **Headphones plugged into the wrong jack.** Make sure they
   are in the DAC's 3.5 mm output.
6. **Volume is at 0.** Press BTN2 to raise the volume level.

### 10.2 STATUS0 heartbeat is not toggling

1. **FPGA bitstream is not loaded.** The STATUS0 heartbeat is
   generated by `status_mon.sv`; it requires a valid bitstream.
   The Arty's "DONE" LED will be off if configuration has not
   completed successfully.
2. **MMCM has not locked.** The heartbeat is gated on
   `dsp_ready_i`, which is the AND of MMCM lock and DSP out
   of reset. If the MMCM lost lock (rare on the Arty S7-25's
   onboard oscillator), the heartbeat will be held low. Reset
   the FPGA.
3. **dsp_pipeline is bypassed.** The heartbeat is independent
   of `dsp_enable_i`; bypass mode does not silence it. If
   the heartbeat is silent, the bitstream or lock is the
   issue, not the bypass.

### 10.3 Mode change has no audible effect

1. **Wrong button mapping.** BTN0 cycles the mode; BTN1 cycles
   it in reverse. Press BTN0 and watch the RGB LED change
   colour — this confirms the FSM is alive.
2. **Volume is at 0.** Press BTN2 to raise the volume; the
   mode-specific gain shaping only affects audible frequencies
   when the output level is non-zero.
3. **Headphones in the wrong socket.** Confirm the headphones
   are in the DAC's 3.5 mm output.

### 10.4 Noisy / distorted audio

1. **Ground loop.** Make sure all grounds are common and that
   no audio ground path runs near a switching regulator.
2. **Missing decoupling.** Place 0.1 µF caps on the PCM5102A
   supply pins as close to the chip as possible.
3. **Clock jitter.** If the BCLK has significant jitter, the
   DAC's internal PLL may miscompute. Probe the clock with a
   scope and look for noise.
4. **Mic acoustic coupling.** If the microphone is too close
   to the headphones, you will get feedback. Move them apart.

---

## 11. Photo Reference

> *Placeholder — photos of the assembled breadboard will be added
> during Phase 1 (Prototype Bring-up) of the FPGA-only build.*

---

## 12. Where to Read Next

- [`fpga/constraints/arty_s7_25.xdc`](../../fpga/constraints/arty_s7_25.xdc)
  — pin map and timing constraints (authoritative).
- [`docs/fpga_only_architecture.md`](../fpga_only_architecture.md)
  — single-pane-of-glass overview of the current architecture.
- [`docs/hardware/README.md`](./README.md) — pin map summary.
- [`docs/hardware/BOM.md`](./BOM.md) — top-level bill of
  materials.
- [`../../hardware/bom/bom.csv`](../../hardware/bom/bom.csv) —
  detailed CSV BOM.
- [`docs/architecture/clock_domains.md`](../architecture/clock_domains.md)
  — clock domain analysis.
- [`docs/MEASUREMENT_METHODOLOGY.md`](../MEASUREMENT_METHODOLOGY.md)
  — measurement methodology for the FPGA-only build.