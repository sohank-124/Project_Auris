# Hardware Documentation

## Overview

Project Auris is a breadboard-prototype hearing-assistive device that combines a
**Digilent Cmod S7-25** FPGA module (Xilinx Spartan-7 XC7S25) with an
**Espressif ESP32-DevKitC-32E** microcontroller, an **InvenSense INMP441**
I2S MEMS microphone, and a **Texas Instruments PCM5102A** I2S audio DAC. The
FPGA implements the deterministic, low-latency DSP pipeline (noise reduction,
beamforming, gain control), while the ESP32 provides Wi-Fi/Bluetooth control,
parameter management, and the I2S clocks for the audio CODEC pair. Audio
flows into the FPGA from the INMP441, is processed in real time, and is
routed back out to the PCM5102A which drives a 3.5 mm headphone output.

All interconnects are point-to-point jumper wires on a single 830-point
solderless breadboard. No custom PCB exists yet — see `hardware/schematics/`
for the planned KiCad capture and `hardware/mechanical/` for the planned
enclosure.

## Pin Map

The complete pin map for the breadboard prototype. All signals operate at
**3.3 V LVCMOS** and share a common ground. The ESP32 is the SPI master and
the I2S clock master; the FPGA is the SPI slave and the I2S data endpoint
(rx from mic, tx to DAC).

### ESP32 <-> FPGA (SPI)

| Signal     | ESP32 Pin | FPGA Pin (Pmod) | Direction      | Voltage | Notes                                |
|------------|-----------|-----------------|-----------------|---------|--------------------------------------|
| SPI SCLK   | GPIO 18   | JA1             | ESP32 -> FPGA   | 3.3 V   | SPI clock, up to 10 MHz              |
| SPI MOSI   | GPIO 23   | JA2             | ESP32 -> FPGA   | 3.3 V   | Host-to-FPGA data (commands, params) |
| SPI MISO   | GPIO 19   | JA3             | FPGA -> ESP32   | 3.3 V   | FPGA-to-host data                    |
| SPI CS_N   | GPIO 5    | JA4             | ESP32 -> FPGA   | 3.3 V   | Active-low chip select              |

### ESP32 -> FPGA (I2S clocks)

The ESP32 provides BCLK and LRCLK only.  All I2S data passes
between the FPGA and the peripherals directly; the ESP32 is **not**
in the audio data path.

| Signal     | ESP32 Pin | FPGA Pin (Pmod) | Direction      | Voltage | Notes                                |
|------------|-----------|-----------------|-----------------|---------|--------------------------------------|
| I2S BCLK   | GPIO 14   | JB1             | ESP32 -> FPGA   | 3.3 V   | Bit clock, 3.072 MHz (64 x 48 kHz)   |
| I2S LRCLK  | GPIO 15   | JB2             | ESP32 -> FPGA   | 3.3 V   | Word select, 48 kHz                  |

### INMP441 <-> FPGA (I2S microphone)

| Signal     | ESP32 Pin | FPGA Pin (Pmod) | Direction      | Voltage | Notes                                |
|------------|-----------|-----------------|-----------------|---------|--------------------------------------|
| I2S BCLK   | (none)    | JB1             | FPGA -> INMP441 | 3.3 V   | Bit clock, 3.072 MHz (shared)       |
| I2S LRCLK  | (none)    | JB2             | FPGA -> INMP441 | 3.3 V   | Word select, 48 kHz (shared)         |
| I2S DATA   | (none)    | JB3             | INMP441 -> FPGA | 3.3 V   | 24-bit, left-justified, MSB first    |

### FPGA -> PCM5102A (I2S DAC)

| Signal     | ESP32 Pin | FPGA Pin (Pmod) | Direction      | Voltage | Notes                                |
|------------|-----------|-----------------|-----------------|---------|--------------------------------------|
| I2S BCLK   | (none)    | JB1             | FPGA -> PCM5102A | 3.3 V | Bit clock, 3.072 MHz (shared)       |
| I2S LRCLK  | (none)    | JB2             | FPGA -> PCM5102A | 3.3 V | Word select, 48 kHz (shared)         |
| I2S DATA   | (none)    | JB4             | FPGA -> PCM5102A | 3.3 V | 32-bit I2S, MSB first                |

> **Note:** The PCM5102A receives its clocks from the FPGA in this prototype
> so that the FPGA can tightly synchronize its I2S TX to the RX phase
> relationship required for tight DSP latency. In production these clocks
> would likely be re-routed from the ESP32 to the DAC through the FPGA as a
> clock buffer.

### Reserved / unused FPGA Pmod pins

Only the SPI uses a 4th Pmod pin (JA4 = CS_N).  The I2S data
sub-bus (JB3 mic data, JB4 DAC data) consumes the remaining JB
pins.  No other Pmod headers (JC, JD) are used by the FPGA in
this revision; the INMP441 and PCM5102A both connect to the
Cmod S7-25 via Pmod JB (shared BCLK/LRCLK from the FPGA).

## Power

| Rail | Source                       | Consumers                                  | Estimated Current |
|------|------------------------------|--------------------------------------------|-------------------|
| 5 V  | USB (ESP32) and USB (Cmod)   | ESP32 onboard LDO, Cmod onboard regulators | 500 mA (USB limit) |
| 3.3 V| ESP32 LDO and Cmod 3V3 rail  | INMP441, PCM5102A, FPGA I/O                | ~250 mA combined |

### Power distribution rules

- **ESP32** is powered from its micro-USB jack (5 V input). The onboard
  AMS1117-3.3 LDO produces 3.3 V on the `3V3` header pin, which can be used
  to power peripherals if desired.
- **Cmod S7-25** is powered from its USB-C jack (5 V input). The module has
  onboard switching regulators that produce 3.3 V, 1.8 V, and 1.0 V rails.
  The 3.3 V rail is exposed on the Pmod headers (pins labelled `VCC`/`3V3`
  on Pmod pin 6 and ground on pin 5). The Cmod and the ESP32 share a common
  ground on the breadboard.
- **INMP441** is powered from the 3.3 V rail of the Cmod Pmod JA header
  (pin 6).  Maximum supply current is ~1.4 mA.
- **PCM5102A** is powered from the 3.3 V rail of the Cmod Pmod JA header
  (pin 6).  Maximum supply current is ~30 mA.
  Typical supply current is ~20 mA at full-scale output into 32 ohm
  headphones. The DAC's charge pump requires the full 3.3 V supply; do not
  power it from 1.8 V.
- **Headphones** are driven directly from the PCM5102A's line-driver
  outputs (no external amplifier needed for typical 16-32 ohm headphones at
  moderate listening levels).

> **Important:** Do **not** power the ESP32 and the Cmod from two separate
> USB chargers without tying their grounds together on the breadboard.
> Always share the ground rail between the two boards, or use a single
> powered hub.

## Current Budget Estimate

| Block         | Current @ 3.3 V |
|---------------|-----------------|
| Cmod S7-25    | ~150 mA         |
| ESP32 (Wi-Fi) | ~160 mA         |
| INMP441       | ~1.4 mA         |
| PCM5102A      | ~20 mA          |
| **Total**     | **~330 mA**     |

The shared 3.3 V rail on the Cmod is rated for ~500 mA; the ESP32's 3V3 pin
is rated for ~600 mA. Either rail can power the whole system at 3.3 V with
margin to spare.

## Related Documents

- [`WIRING.md`](./WIRING.md) — Step-by-step breadboard wiring guide
- [`BOM.md`](./BOM.md) — Top-level bill of materials with cost summary
- [`../../hardware/bom/bom.csv`](../../hardware/bom/bom.csv) — Detailed CSV
  bill of materials (vendor part numbers, footprints, datasheets)
- [`../../hardware/bom/README.md`](../../hardware/bom/README.md) — BOM
  directory documentation
- [`../../hardware/schematics/README.md`](../../hardware/schematics/README.md) —
  Planned KiCad schematic capture
- [`../../hardware/mechanical/README.md`](../../hardware/mechanical/README.md) —
  Planned enclosure and mechanical design
- [`../architecture/block_diagram.md`](../architecture/block_diagram.md) —
  System block diagram
- [`../architecture/clock_domains.md`](../architecture/clock_domains.md) —
  Clocking architecture (FPGA fabric clocks vs. ESP32 I2S clocks)
- [`../architecture/register_map.md`](../architecture/register_map.md) — SPI
  register map (the protocol carried over the SPI link above)
- [`../IMPLEMENTATION_PLAN.md`](../IMPLEMENTATION_PLAN.md) — Project phasing
