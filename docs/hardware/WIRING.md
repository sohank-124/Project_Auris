# Wiring Guide

This document is the step-by-step procedure for assembling the Project Auris
breadboard prototype. Follow the steps in order. Each step produces a
verifiable sub-system (SPI link works, I2S clocks appear on the scope, mic
captures audio, DAC plays audio) before moving on.

## Required Components

| Item | Qty | Notes |
|------|-----|-------|
| Cmod S7-25 (FPGA module) | 1 | Digilent 410-331 |
| ESP32-DevKitC-32E | 1 | Espressif |
| INMP441 I2S MEMS microphone (breakout board) | 1 | TDK / InvenSense |
| PCM5102A I2S DAC (breakout board) | 1 | Texas Instruments |
| 830-point solderless breadboard | 1 | |
| Male-male jumper wires | ~40 | Various lengths |
| Male-female jumper wires | ~20 | For Pmod-to-peripheral |
| Female-female jumper wires | ~10 | For DAC/mic to breadboard |
| USB-A to USB-C cable | 1 | For Cmod S7-25 (programming + power) |
| Micro-USB cable | 1 | For ESP32 (programming + power) |
| 3.5 mm headphones or earbuds | 1 | For DAC output verification |
| Oscilloscope or logic analyzer (recommended) | 1 | For debug |

See [`BOM.md`](./BOM.md) and [`../../hardware/bom/bom.csv`](../../hardware/bom/bom.csv)
for full part numbers and vendor links.

## Before You Begin

**Safety**

1. **Power off before wiring.** Always disconnect both USB cables before
   inserting or removing jumper wires. A loose wire bridging 3.3 V to a
   signal pin can latch-up or destroy the FPGA or ESP32.
2. **Verify voltage levels.** All signals are 3.3 V. Do not connect a 5 V
   source to any signal pin. The ESP32 GPIO is **not** 5 V tolerant.
3. **Common ground is mandatory.** The ESP32 and the Cmod must share a
   ground reference. Tie their GND pins together on the breadboard before
   powering up.
4. **Anti-static precautions.** The Cmod S7-25 and the PCM5102A are
   ESD-sensitive. Work on an anti-static mat if available.

**Breadboard orientation**

- Place the breadboard with the **red rail (+) on the right** and the
  **blue rail (-) on the left**. Most breadboards are labelled.
- Power rails run vertically along both edges. Use the right-hand red rail
  for 3.3 V and the left-hand blue rail for GND, or use a single rail pair
  for both. Be consistent.
- The Cmod S7-25 and the ESP32 should be seated at opposite ends of the
  breadboard with the INMP441 and PCM5102A between them, leaving room for
  jumpers.

**Suggested wire-color convention**

This guide uses a consistent color code so that wiring mistakes are easier
to spot. Substitute freely if you do not have the exact colors.

| Color      | Function                    |
|------------|-----------------------------|
| Orange     | SPI SCLK                    |
| Yellow     | SPI MISO                    |
| Green      | SPI MOSI                    |
| Blue       | SPI CS_N                    |
| White      | I2S BCLK                    |
| Gray       | I2S LRCLK                   |
| Purple     | INMP441 SCK (BCLK)          |
| Brown      | INMP441 WS (LRCLK)          |
| Pink       | INMP441 SD (DATA)           |
| Cyan       | PCM5102A BCK                |
| Magenta    | PCM5102A LRCK               |
| Lime       | PCM5102A DIN                |
| Red        | 3.3 V power                 |
| Black      | Ground                      |

---

## Step 1: SPI Link (ESP32 <-> FPGA)

The SPI link carries control commands, parameter updates, and status
telemetry between the ESP32 (host) and the FPGA (slave). Wire these four
signals first — they are the slowest to debug if wired wrong because a
single swapped MOSI/MISO will look like a "no communication" failure.

| ESP32 Pin | Cmod Pmod Pin | Wire Color | Signal     | Notes                                  |
|-----------|---------------|------------|------------|----------------------------------------|
| GPIO 18   | JA1           | Orange     | SPI SCLK   | 10 MHz max in this design              |
| GPIO 23   | JA2           | Green      | SPI MOSI   | ESP32 -> FPGA (host TX)                |
| GPIO 19   | JA3           | Yellow     | SPI MISO   | FPGA -> ESP32 (peripheral TX)          |
| GPIO 5    | JA4           | Blue       | SPI CS_N   | Active-low; idle high                  |

**Caveats**

- The Cmod S7-25's Pmod JA header is on the **top** edge of the board, with
  pin 1 (JA1) on the left when the USB-C jack is facing you.
- The ESP32-DevKitC-32E silkscreen numbers the GPIO pins on the **bottom**
  edge of the board — orient the board with the USB jack on the left and
  the GPIO labels are on the row nearest you.
- The Pmod JA header on the Cmod also exposes +3.3 V (pin 6) and GND
  (pin 5). **Do not** connect those yet; do that in Step 5.

**Verification**

With both boards powered (USB connected) and the FPGA bitstream loaded:

1. Use a logic analyzer or scope on JA1 — you should see idle-high on
   CS_N (JA4) and SCLK (JA1) when no transaction is in progress.
2. From the ESP32, run the SPI loopback test (a firmware test that reads
   the FPGA's known version register). The ESP32 should report a
   successful read.
3. If communication fails, **double-check MOSI/MISO** — they are the most
   commonly swapped pair.

---

## Step 2: I2S Clocks (ESP32 -> FPGA)

The ESP32 is the I2S clock master. It generates BCLK (3.072 MHz = 64 x
48 kHz) and LRCLK (48 kHz) and sends them to the FPGA, which routes them
to the I2S peripherals (mic and DAC) and uses them to clock its own I2S
RX and TX logic.

| ESP32 Pin | Cmod Pmod Pin | Wire Color | Signal    | Notes                              |
|-----------|---------------|------------|-----------|------------------------------------|
| GPIO 14   | JB1           | White      | I2S BCLK  | 3.072 MHz, 50% duty cycle          |
| GPIO 15   | JB2           | Gray       | I2S LRCLK | 48 kHz, 50% duty cycle             |
| (n.c.)    | JB3           | Pink       | I2S ADC_DATA | INMP441 -> FPGA (mono, left chan) |
| (n.c.)    | JB4           | Lime       | I2S DAC_DATA | FPGA -> PCM5102A                  |

**Caveats**

- The Cmod S7-25's Pmod JB header is on the **top** edge of the board, just
  east of JA. Pin 1 (JB1) is the leftmost.
- Both clocks must be running before the FPGA's I2S RX block can capture
  data from the microphone. The ESP32 firmware should enable the I2S
  peripheral during `app_main()`.
- JB3 and JB4 are the I2S data lines (FPGA-owned; the ESP32's I2S
  data pins GPIO2/GPIO4 are *not* connected to the FPGA's I2S bus).

**Verification**

With both boards powered and the ESP32 I2S peripheral enabled:

1. Probe JB1 with a scope — you should see a 3.072 MHz square wave.
2. Probe JB2 with a scope — you should see a 48 kHz square wave.
3. The two should be phase-locked: every 64 BCLK periods, LRCLK toggles.
4. If either clock is missing, re-check the ESP32 firmware's I2S driver
   configuration and the GPIO mux settings.

---

## Step 3: I2S Microphone (FPGA -> INMP441)

The INMP441 is a bottom-port MEMS microphone with a digital I2S output.
It is powered from the Cmod's Pmod 3.3 V rail and clocked from the FPGA's
I2S clock signals (which originate from the ESP32).

| Cmod Pmod Pin | INMP441 Pin  | Wire Color | Signal       | Notes                              |
|---------------|--------------|------------|--------------|------------------------------------|
| JB1           | SCK          | Purple     | I2S BCLK     | 3.072 MHz from FPGA (JB1, BCLK)    |
| JB2           | WS           | Brown      | I2S LRCLK    | 48 kHz from FPGA (JB2, LRCLK)      |
| JB3           | SD           | Pink       | I2S DATA     | INMP441 -> FPGA, 24-bit left-just  |
| (unused)      | n/a          | (unused)   | -            | Reserved (FPGA owns I2S data)      |
| Pmod JA pin 6 | VDD          | Red        | 3.3 V power  | From Cmod 3.3 V rail               |
| Pmod JA pin 5 | GND          | Black      | Ground       | Common ground with Cmod            |
| Breadboard GND| L/R          | Black      | Channel sel  | Tie to GND = left channel          |

**INMP441 pin reference (typical breakout board)**

```
     +-------+
 VDD | 1   6 | L/R     (left/right channel select)
 GND | 2   5 | SCK
  SD | 3   4 | WS
     +-------+
```

**Caveats**

- Tie **L/R to GND** so that the INMP441 transmits on the left channel of
  the I2S frame. If tied to VDD it transmits on the right channel; if
  floating, the channel is undefined.
- The INMP441's **bottom acoustic port** must be unobstructed. Most
  breakout boards expose this through a hole on the underside of the PCB.
  Do not place the breakout face-down on the breadboard — leave a gap or
  stand it off.
- Place a **0.1 uF decoupling capacitor** between VDD and GND, as close to
  the INMP441 breakout as practical. The Cmod's Pmod 3.3 V rail can be
  noisy during FPGA configuration.

**Verification**

With the FPGA bitstream loaded and the ESP32 streaming I2S clocks:

1. Probe JB3 (SD) with a scope. You should see data transitions once per
   audio sample (~48 kHz frame rate). The data line is idle-low when no
   sample is being transmitted.
2. The FPGA firmware should report a non-zero sample stream on the I2S
   RX. If you have a spare DAC or headphone amp, you can route the
   mic data directly to it (bypassing the DSP) as a sanity check.
3. Blow gently on the mic and watch the I2S DATA line activity change.

---

## Step 4: I2S DAC (FPGA -> PCM5102A)

The PCM5102A is a 32-bit I2S audio DAC with a built-in headphone driver
and charge-pump line driver. It is configured for **I2S format** (FMT tied
low), **internal system clock** (SCK tied low — the DAC derives its
internal clock from BCLK), and **unmuted** (XSMT tied high).

| Cmod Pmod Pin | PCM5102A Pin | Wire Color | Signal       | Notes                              |
|---------------|--------------|------------|--------------|------------------------------------|
| JB1           | BCK          | Cyan       | I2S BCLK     | 3.072 MHz from FPGA (shared with mic) |
| JB2           | LRCK         | Magenta    | I2S LRCLK    | 48 kHz from FPGA (shared with mic)   |
| JB4           | DIN          | Lime       | I2S DATA     | FPGA -> PCM5102A, 32-bit I2S         |
| (unused)      | n/a          | (unused)   | -            | Reserved (FPGA owns I2S data)        |
| Pmod JA pin 6 | VCC (AVCC + DVDD) | Red  | 3.3 V power  | Tie AVCC, DVDD, CPVDD all to 3.3 V |
| Pmod JA pin 5 | GND (AGND + DGND) | Black | Ground     | Common ground with Cmod            |
| Breadboard GND| SCK          | Black      | Sys clock    | Tie to GND = use BCLK as clock ref |
| Breadboard GND| FMT          | Black      | Format sel   | Tie to GND = standard I2S          |
| Breadboard GND| DEMP         | Black      | De-emphasis  | Tie to GND = no de-emphasis        |
| Breadboard GND| FLT          | Black      | Filter sel   | Tie to GND = normal-latency filter |
| Breadboard 3V3| XSMT         | Red        | Soft mute    | Tie HIGH = unmuted (LOW = muted)   |

**PCM5102A pin reference (TSSOP-20)**

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

**Caveats**

- **FMT to GND** selects standard I2S (Philips) format. If you want
  left-justified format, tie FMT to VCC instead.
- **XSMT to 3.3 V** is mandatory for any audio output. If you leave XSMT
  floating or tied low, the DAC is in software mute and you will hear
  silence. The datasheet recommends a pull-up; we use a direct connection
  to 3.3 V for simplicity.
- **Decoupling is essential.** Place the following capacitors as close to
  the PCM5102A as possible:
  - 0.1 uF ceramic between AVCC and AGND
  - 0.1 uF ceramic between DVDD and DGND
  - 10 uF electrolytic (or tantalum) between VCC and GND (bulk)
  - The charge-pump flying capacitor (220 nF typical) between CPVDD and
    CPN is **internal** to the PCM5102A on the TSSOP-20 package; no
    external flying cap is needed.
- The headphone output is the line-driver output (VOUTL+, VOUTL-) wired
  through a 3.5 mm jack. Most PCM5102A breakouts have this jack already
  onboard.

**Verification**

With the FPGA bitstream loaded and a test tone playing:

1. Probe JB4 (DIN) with a scope — you should see I2S data toggling at the
   sample rate.
2. Plug headphones into the DAC's 3.5 mm jack. You should hear the test
   tone. If you hear nothing, check XSMT (must be high) and verify the
   FMT pin matches the FPGA's I2S_TX format.
3. If you hear distorted audio, check that BCLK is exactly 64 x LRCLK
   (i.e., 3.072 MHz and 48 kHz) and that the data is MSB-first.

---

## ESP32 Pin Assignment Reference (M34, M35)

For convenience, the complete ESP32 GPIO map used by the firmware
(`firmware/components/spi_master/spi_master.h`,
`firmware/components/audio_driver/audio_driver.h`,
`firmware/components/button_handler/button_handler.h`,
`firmware/components/led_indicator/led_indicator.h`,
`firmware/components/battery_mon/battery_mon.h`) is reproduced here.

| ESP32 GPIO | Function             | Wired to           | Direction   |
|------------|----------------------|--------------------|-------------|
| GPIO 2     | I2S ADC data (unused)| (FPGA owns I2S)    | not used    |
| GPIO 4     | I2S DAC data (unused)| (FPGA owns I2S)    | not used    |
| GPIO 5     | SPI CS_N             | Cmod JA4           | output      |
| GPIO 14    | I2S BCLK             | Cmod JB1           | output      |
| GPIO 15    | I2S LRCLK            | Cmod JB2           | output      |
| GPIO 18    | SPI SCLK             | Cmod JA1           | output      |
| GPIO 19    | SPI MISO             | Cmod JA3           | input       |
| GPIO 21    | I2S MCLK (unused)    | not connected      | n/a         |
| GPIO 22    | I2S BCLK to FPGA     | Cmod JB1           | output      |
| GPIO 23    | SPI MOSI             | Cmod JA2           | output      |
| GPIO 25    | RGB LED red (PWM)    | onboard LED        | output      |
| GPIO 26    | RGB LED green (PWM)  | onboard LED        | output      |
| GPIO 27    | RGB LED blue (PWM)   | onboard LED        | output      |
| GPIO 32    | Mode button          | tactile switch     | input, PULLUP |
| GPIO 33    | Volume up button     | tactile switch     | input, PULLUP |
| GPIO 34    | Volume down button   | tactile switch     | input, PULLUP |
| GPIO 35    | Battery voltage ADC  | divider to BAT+    | input, ADC  |
| GPIO 36    | (reserved)           | n/a                | n/a         |

Note: GPIO 2, 4, 21 are reserved by the firmware for I2S data lines
but are **not connected** to the FPGA's I2S data lines (which are
driven by the Cmod S7-25's Pmod JB3/JB4).  The ESP32's I2S
peripheral runs only to generate BCLK and LRCLK for the FPGA; no
audio data passes through the ESP32.

---

## Step 5: Power Distribution

Power is delivered entirely over USB. Each board has its own onboard
regulators. The only manual wiring is the ground bus on the breadboard.

```
                    +-------------+        +-------------+
   Micro-USB  ----> | ESP32 3V3   |        | Cmod S7-25  | <---- USB-C
                    |             |        |             |
                    |        3V3 o|------> |o 3V3  (Pmod)|
                    |        GND o|---GND--+o GND  (Pmod)|
                    +-------------+        +-------------+
                            |                    |
                            +-- breadboard GND --+
                            |                    |
                       +----+----+          +----+----+
                       | INMP441 |          |PCM5102A|
                       | VDD=GND |          | VCC=GND|
                       +---------+          +---------+
```

**Step 5a: Wire the breadboard power rails**

1. Connect the ESP32's **GND** pin to the breadboard's blue ground rail.
2. Connect the Cmod S7-25's **GND** (Pmod pin 5, any header) to the
   **same** blue ground rail. The two grounds must be common.
3. (Optional) Run a red wire from the ESP32's **3V3** pin to the
   breadboard's red power rail. This is not required if every peripheral
   draws power from the Cmod's Pmod rails, but it provides a spare 3.3 V
   tap for scope probes and pull-ups.

**Step 5b: Power the INMP441**

- Connect INMP441 **VDD** to Pmod JA pin 6 (3.3 V) or to the
  breadboard red power rail.
- Connect INMP441 **GND** to Pmod JA pin 5 (GND) AND to the breadboard
  ground rail.
- Place a 0.1 uF decoupling cap across VDD and GND, close to the
  breakout.

**Step 5c: Power the PCM5102A**

- Connect PCM5102A **AVCC**, **DVDD**, and **CPVDD** all to Pmod JA pin 6
  (3.3 V).
- Connect PCM5102A **AGND** and **DGND** all to Pmod JA pin 5 (GND) AND
  to the breadboard ground rail.
- Place 0.1 uF decoupling caps on each supply pin and a 10 uF bulk cap
  on VCC.

**Step 5d: Sanity check**

Before connecting USB:

1. Use a multimeter in continuity mode to verify that all GND points are
   tied together (ESP32 GND, Cmod GND, breadboard ground rail, INMP441
   GND, PCM5102A GND).
2. Verify that no 3.3 V rail is shorted to ground (multimeter in
   resistance mode, expect > 1 kohm).
3. Verify that the INMP441 and PCM5102A signal pins are **not** shorted
   to 3.3 V or GND (would indicate a wiring mistake).

---

## Step 6: USB Connections

After all signal and power wiring is complete and visually inspected:

1. **Connect the Cmod S7-25** to the host computer with a USB-A to
   USB-C cable. This provides power and the programming/JTAG link to
   the FPGA.
2. **Connect the ESP32** to the host computer with a Micro-USB cable.
   This provides power and the serial/JTAG link to the ESP32.
3. The host should enumerate two USB serial ports (one per board). The
   Cmod appears as a Digilent programmer; the ESP32 appears as a CP210x
   or CH340 USB-to-UART bridge.
4. **Do not** power either board from a charger-style USB supply during
   development — you need the data lines connected for programming and
   serial console output.

---

## Verification

After assembly, perform these checks in order.

### Pre-power checks (no USB connected)

- [ ] Visual inspection: every wire goes from the documented source pin
      to the documented destination pin.
- [ ] Continuity test: all GND points are common.
- [ ] Continuity test: no 3.3 V rail is shorted to GND.
- [ ] Continuity test: no signal pin is shorted to 3.3 V or GND
      (this would indicate a wire in the wrong hole).

### Power-on checks

- [ ] ESP32 power LED is on (typically red).
- [ ] Cmod S7-25 power LED is on (typically green or blue).
- [ ] 3.3 V rail measures 3.30 +/- 0.10 V with a multimeter.

### SPI link

- [ ] Run the ESP32 firmware's SPI self-test. It should report a
      successful read of the FPGA version register.
- [ ] On a logic analyzer, capture a single SPI transaction and verify
      the four signal edges (CS_N falling, SCLK toggling, MOSI/MISO
      transitions).

### I2S clocks

- [ ] Probe JB1 (BCLK) — 3.072 MHz square wave, 50% duty cycle.
- [ ] Probe JB2 (LRCLK) — 48 kHz square wave, 50% duty cycle.
- [ ] Verify phase lock: BCLK period x 64 = LRCLK period.

### I2S microphone

- [ ] Probe JB3 (SD) — 24-bit data frames once per LRCLK period.
- [ ] Speak or tap near the mic; the FPGA's sample stream should show
      non-trivial variation.
- [ ] If you have a spare DAC, route the mic stream to it directly to
      confirm end-to-end audio capture.

### I2S DAC

- [ ] Probe JB4 (DIN) — 32-bit data frames once per LRCLK period.
- [ ] Plug in headphones; you should hear the test tone that the FPGA is
      generating.
- [ ] Verify the headphone output level with a multimeter on AC volts —
      a full-scale sine should produce ~0.5-1.0 V RMS at the jack.

### End-to-end

- [ ] Speak into the microphone; hear your voice in the headphones with
      a short, fixed latency (typically < 10 ms in this design).
- [ ] Toggle the gain and noise-reduction parameters from the ESP32
      (via SPI); verify the audio changes accordingly.

---

## Troubleshooting

### No audio output

1. **XSMT is floating or low.** The PCM5102A is in soft mute. Check that
   XSMT is tied to 3.3 V.
2. **Wrong I2S format.** FMT is high (left-justified) but the FPGA is
   sending standard I2S (or vice versa). Verify FMT is low and that the
   FPGA's I2S_TX block is configured for standard I2S.
3. **BCLK is not running.** The DAC needs a continuous bit clock. Probe
   JB1 and confirm 3.072 MHz.
4. **Wrong clock ratio.** The DAC expects 64 x BCLK per LRCLK period.
   Confirm 3.072 MHz and 48 kHz.
5. **Headphones plugged into the wrong jack.** Make sure they are in the
   DAC's 3.5 mm output, not the ESP32 or the Cmod.

### SPI timeout / no communication

1. **MOSI and MISO are swapped.** This is the most common mistake. Swap
   the green and yellow wires.
2. **CS_N is not reaching the FPGA.** Probe JA4 with a scope; the line
   should idle high and go low at the start of each transaction.
3. **SCLK too fast for the FPGA fabric.** Reduce the SPI clock divider
   in the ESP32 firmware and try again.
4. **FPGA bitstream is not loaded.** The FPGA will not respond on SPI
   until a valid bitstream is programmed into flash. Check the Cmod's
   done LED.

### I2S clocks missing

1. **ESP32 firmware has not started the I2S peripheral.** Check the
   serial console for I2S init errors.
2. **Wrong GPIO mux settings.** The ESP32's I2S driver may be configured
   for different pins. Verify the I2S pin configuration in firmware
   matches GPIO 14 (BCLK) and GPIO 15 (LRCLK).
3. **FPGA is driving the I2S lines low.** If the FPGA's Pmod JB pins
   are not configured as inputs in the bitstream, they may be driving
   the bus and conflicting with the ESP32.

### Noisy / distorted audio

1. **Ground loop.** Make sure all grounds are common and that no audio
   ground path runs near a switching regulator.
2. **Missing decoupling.** Place 0.1 uF caps on the PCM5102A supply
   pins as close to the chip as possible.
3. **Clock jitter.** If the BCLK has significant jitter, the DAC's
   internal PLL may miscompute. Probe the clock with a scope and look
   for noise.
4. **Mic acoustic coupling.** If the microphone is too close to the
   headphones, you will get feedback. Move them apart.

### ESP32 brownout / random resets

1. **USB supply is insufficient.** The ESP32 peaks at ~500 mA during
   Wi-Fi transmit. Use a powered hub or a high-current USB port.
2. **Loose USB cable.** Replace the Micro-USB cable; many are
   power-only or have thin gauge wires.

---

## Photo Reference

> *Placeholder — photos of the assembled breadboard will be added during
> Phase 1 (Prototype Bring-up).*
