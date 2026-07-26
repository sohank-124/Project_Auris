# Schematics

This directory will hold the formal schematic capture of the Project Auris
hardware. The breadboard prototype is the current reference; a proper
KiCad schematic is planned for **Phase 2** (see
[`../../docs/IMPLEMENTATION_PLAN.md`](../../docs/IMPLEMENTATION_PLAN.md)).

## Overview

The breadboard prototype has no schematic capture. The wiring is
documented in [`../../docs/hardware/WIRING.md`](../../docs/hardware/WIRING.md)
and the pin map is in [`../../docs/hardware/README.md`](../../docs/hardware/README.md).
These documents are the **authoritative** sources for the breadboard
prototype.

Before a custom PCB is laid out, the wiring must be captured in a proper
schematic editor (KiCad 8.x) so that:

- Net connections are machine-verifiable
- ERC (Electrical Rule Check) catches shorts, unconnected pins, and
  output-to-output conflicts
- The schematic is the single source of truth for the BOM and the PCB
  layout
- Future revisions are tracked in version control

## Planned Schematics

The schematic will be split into logical sheets for readability and
maintenance.

| Sheet file             | Contents                                                    |
|------------------------|-------------------------------------------------------------|
| `auris_main.sch`       | Top-level sheet: ESP32, Cmod S7-25, INMP441, PCM5102A interconnects, all signal nets |
| `auris_power.sch`      | Power distribution: USB inputs, onboard regulators, decoupling, 3.3 V and GND rails |
| `auris_audio_in.sch`   | INMP441 microphone interface: clock routing, decoupling, channel select |
| `auris_audio_out.sch`  | PCM5102A DAC interface: format/SCK/XSMT configuration, headphone output jack, decoupling |
| `auris_io.sch`         | ESP32-to-FPGA SPI and I2S clock routing, pin assignments, any pull-ups |

Each sheet is a separate `.kicad_sch` file. The top-level sheet is
`auris_main.sch`; the others are sub-sheets referenced via hierarchical
labels.

## What the Schematic Must Capture

The schematic must capture, at minimum, every net in the current
breadboard prototype. The list below is the completeness checklist.

### Signal nets (12 nets from the pin map)

- [ ] `SPI_SCLK` — ESP32 GPIO18 <-> Cmod JA1
- [ ] `SPI_MOSI` — ESP32 GPIO23 <-> Cmod JA2
- [ ] `SPI_MISO` — ESP32 GPIO19 <-> Cmod JA3
- [ ] `SPI_CS_N` — ESP32 GPIO5 <-> Cmod JA4
- [ ] `I2S_BCLK` — ESP32 GPIO14 -> Cmod JB1 (FPGA forwards to mic + DAC; bus architecture in schematic)
- [ ] `I2S_LRCLK` — ESP32 GPIO15 -> Cmod JB2 (FPGA forwards to mic + DAC)
- [ ] `I2S_MIC_DATA` — INMP441 SD -> Cmod JB3
- [ ] `I2S_DAC_DATA` — Cmod JB4 -> PCM5102A DIN

### Power nets

- [ ] `+5V_USB1` — USB-C input to Cmod S7-25
- [ ] `+5V_USB2` — Micro-USB input to ESP32
- [ ] `+3V3` — net: Cmod 3.3 V rail, ESP32 3V3 pin, INMP441 VDD, PCM5102A AVCC/DVDD/CPVDD
- [ ] `GND` — net: every ground pin must be on the same net
- [ ] Decoupling caps on every IC supply pin

### Configuration pins

- [ ] `INMP441_LR` — tied to GND (left channel)
- [ ] `PCM5102A_SCK` — tied to GND (internal clock mode)
- [ ] `PCM5102A_FMT` — tied to GND (standard I2S)
- [ ] `PCM5102A_DEMP` — tied to GND (no de-emphasis)
- [ ] `PCM5102A_FLT` — tied to GND (normal-latency filter)
- [ ] `PCM5102A_XSMT` — tied to +3V3 (unmuted)

### Connectors

- [ ] USB-C jack for Cmod (5 V input)
- [ ] Micro-USB jack for ESP32 (5 V input)
- [ ] 3.5 mm headphone jack (PCM5102A output)
- [ ] All Pmod headers (JA, JB, JC, JD) shown as labeled headers

## Current State

The current state is **breadboard prototype only**. There is no KiCad
project yet. The wiring guide and pin map are the source of truth.

When the schematic is created, it should:

1. Use **KiCad 8.x** symbol libraries (the project standard)
2. Place each functional block (FPGA, ESP32, mic, DAC) on its own sheet
   for readability
3. Use **hierarchical labels** for inter-sheet signals (e.g.,
   `SPI_SCLK` exported from `auris_io.sch` and imported on
   `auris_main.sch`)
4. Use **net labels** (not wire crossings) for clarity
5. Run **ERC** before committing; resolve all warnings
6. Update the BOM (`hardware/bom/bom.csv`) from the schematic's
   `bom_csv_grouped_by_value` plugin output

## Tools

- **KiCad 8.x** — recommended schematic and PCB editor
  ([kicad.org](https://www.kicad.org/))
- **KiCad symbol libraries** — official `library.kicad` repo
- **KiCad 3D models** — official `kicad-packages3D` repo for STEP
  exports (consumed by the mechanical design phase)
- **KiCad ERC** — built-in electrical rule checker
- **KiCad `bom_csv_grouped_by_value`** — built-in BOM plugin (used to
  regenerate `hardware/bom/bom.csv`)

## File Layout (planned)

```
hardware/schematics/
|-- README.md                  <- this file
|-- auris.kicad_pro            <- KiCad project file
|-- auris_main.sch             <- top-level sheet
|-- auris_power.sch            <- power distribution
|-- auris_audio_in.sch         <- microphone interface
|-- auris_audio_out.sch        <- DAC interface
|-- auris_io.sch               <- ESP32 <-> FPGA interconnect
|-- auris.kicad_pcb            <- PCB layout (Phase 2)
|-- fpga.lib                   <- custom Cmod S7-25 symbol (if needed)
|-- fpga.pretty/               <- custom footprints (if needed)
```

The KiCad project will be added in a single commit during Phase 2
kickoff, with the schematics derived directly from the wiring guide and
pin map in this repository.
