# Schematics

> **Project Auris** — Planned KiCad schematic capture for the
> FPGA-only build.
> **Last updated:** 2026-08-12 (FPGA-only migration)
> **Status:** Authoritative. The breadboard prototype is the
> current reference; a proper KiCad schematic is planned for
> **Phase 2** of the FPGA-only build (see
> [`docs/IMPLEMENTATION_PLAN.md`](../IMPLEMENTATION_PLAN.md) —
> pre-migration plan, banner-added).

This directory will hold the formal schematic capture of the
Project Auris hardware. The breadboard prototype is the
**authoritative** reference for the current build; the wiring
guide at [`../hardware/WIRING.md`](../hardware/WIRING.md) and
the pin map at [`../hardware/README.md`](../hardware/README.md)
together define every connection on the breadboard.

Before a custom PCB is laid out, the wiring must be captured in
a proper schematic editor (KiCad 8.x) so that:

- Net connections are machine-verifiable
- ERC (Electrical Rule Check) catches shorts, unconnected pins,
  and output-to-output conflicts
- The schematic is the single source of truth for the BOM and
  the PCB layout
- Future revisions are tracked in version control

## Planned Schematics

The schematic will be split into logical sheets for readability
and maintenance.

| Sheet file             | Contents                                                                |
|------------------------|-------------------------------------------------------------------------|
| `auris_main.sch`       | Top-level sheet: Arty S7-25 + INMP441 + PCM5102A interconnects, all signal nets |
| `auris_power.sch`      | Power distribution: USB input, Arty regulators, decoupling, 3.3 V and GND rails |
| `auris_audio_in.sch`   | INMP441 microphone interface: clock routing from FPGA, decoupling, channel select |
| `auris_audio_out.sch`  | PCM5102A DAC interface: FMT/SCK/XSMT configuration, headphone output jack, decoupling |
| `auris_io.sch`         | Onboard button / LED interconnects to the FPGA (no external host bus) |

Each sheet is a separate `.kicad_sch` file. The top-level sheet
is `auris_main.sch`; the others are sub-sheets referenced via
hierarchical labels.

## What the Schematic Must Capture

The schematic must capture, at minimum, every net in the current
breadboard prototype. The list below is the completeness
checklist.

### Signal nets (4 nets from the I²S bus)

- [ ] `I2S_BCLK` — FPGA `i2s_bclk_o` (M16) → INMP441 SCK + PCM5102A BCK
      (FPGA is the master and drives both codecs on the same BCLK line)
- [ ] `I2S_LRCLK` — FPGA `i2s_lrclk_o` (M17) → INMP441 WS + PCM5102A LRCK
      (FPGA is the master)
- [ ] `I2S_MIC_DATA` — INMP441 SD → FPGA `i2s_adc_data_i` (M18)
- [ ] `I2S_DAC_DATA` — FPGA `i2s_dac_data_o` (N18) → PCM5102A DIN

### Onboard push buttons (4 nets)

- [ ] `BTN0` — Arty onboard BTN0 → FPGA `btn_i[0]` (C12)
- [ ] `BTN1` — Arty onboard BTN1 → FPGA `btn_i[1]` (C11)
- [ ] `BTN2` — Arty onboard BTN2 → FPGA `btn_i[2]` (F13)
- [ ] `BTN3` — Arty onboard BTN3 → FPGA `btn_i[3]` (E13)

### Onboard LEDs (6 nets)

- [ ] `STATUS0` — FPGA `status_led_o` (E18) → Arty LED[0]
- [ ] `STATUS2` — FPGA `status_clip_o` (G15) → Arty LED[2] (clip indicator)
- [ ] `RGB_R` — FPGA `led_rgb_r` (J15) → Arty RGB0-R
- [ ] `RGB_G` — FPGA `led_rgb_g` (G17) → Arty RGB0-G
- [ ] `RGB_B` — FPGA `led_rgb_b` (F15) → Arty RGB0-B

### Power nets

- [ ] `+5V_USB` — Micro-USB input to Arty S7-25
- [ ] `+3V3` — net: Arty 3.3 V rail, INMP441 VDD, PCM5102A AVCC/DVDD/CPVDD
- [ ] `GND` — net: every ground pin must be on the same net
- [ ] Decoupling caps on every IC supply pin

### Clock reference

- [ ] `CLK_12MHZ` — Arty onboard 12 MHz oscillator (F14) → FPGA
      `clk_12mhz` (feeds the MMCM in `clk_gen.sv`)

### Configuration pins

- [ ] `INMP441_LR` — tied to GND (left channel)
- [ ] `PCM5102A_SCK` — tied to GND (internal clock mode)
- [ ] `PCM5102A_FMT` — tied to GND (standard I2S)
- [ ] `PCM5102A_DEMP` — tied to GND (no de-emphasis)
- [ ] `PCM5102A_FLT` — tied to GND (normal-latency filter)
- [ ] `PCM5102A_XSMT` — tied to +3V3 (unmuted)

### Connectors

- [ ] Micro-USB jack for Arty (5 V input)
- [ ] 3.5 mm headphone jack (PCM5102A output)
- [ ] All Pmod headers (JA) shown as labeled headers (JC and JD are
      not used in the FPGA-only build)

### What is NOT in the schematic (explicitly excluded)

The following were present in the pre-migration schematic but
have been removed from the FPGA-only build:

- ❌ ESP32-DevKitC-32E — no external microcontroller in this build
- ❌ SPI bus nets (`SPI_SCLK`, `SPI_MOSI`, `SPI_MISO`, `SPI_CS_N`)
  — no host interface
- ❌ ESP32 GPIO nets (`GPIO14` I2S BCLK, `GPIO27` I2S LRCLK,
  `GPIO18` SPI SCLK, etc.) — FPGA owns all clock and control
  signals
- ❌ ESP32 JTAG / USB-serial bridge — no firmware to flash
- ❌ Battery monitor (`battery_mon`) — no battery in this build

## Current State

The current state is **breadboard prototype only**. There is
no KiCad project yet. The wiring guide and pin map are the
source of truth.

When the schematic is created, it should:

1. Use **KiCad 8.x** symbol libraries (the project standard).
2. Place each functional block (FPGA, mic, DAC) on its own
   sheet for readability.
3. Use **hierarchical labels** for inter-sheet signals (e.g.,
   `I2S_BCLK` exported from `auris_audio_in.sch` and imported
   on `auris_main.sch`).
4. Use **net labels** (not wire crossings) for clarity.
5. Run **ERC** before committing; resolve all warnings.
6. Update the BOM (`hardware/bom/bom.csv`) from the schematic's
   `bom_csv_grouped_by_value` plugin output.

## Tools

- **KiCad 8.x** — recommended schematic and PCB editor
  ([kicad.org](https://www.kicad.org/)).
- **KiCad symbol libraries** — official `library.kicad` repo.
- **KiCad 3D models** — official `kicad-packages3D` repo for
  STEP exports (consumed by the mechanical design phase).
- **KiCad ERC** — built-in electrical rule checker.
- **KiCad `bom_csv_grouped_by_value`** — built-in BOM plugin
  (used to regenerate `hardware/bom/bom.csv`).

## File Layout (planned)

```
hardware/schematics/
|-- README.md                  <- this file
|-- auris.kicad_pro            <- KiCad project file
|-- auris_main.sch             <- top-level sheet
|-- auris_power.sch            <- power distribution
|-- auris_audio_in.sch         <- microphone interface
|-- auris_audio_out.sch        <- DAC interface
|-- auris_io.sch               <- onboard button + LED interconnect
|-- auris.kicad_pcb            <- PCB layout (Phase 2)
|-- fpga.lib                   <- custom Arty S7-25 symbol (if needed)
|-- fpga.pretty/               <- custom footprints (if needed)
```

The KiCad project will be added in a single commit during
Phase 2 kickoff, with the schematics derived directly from
the wiring guide and pin map in this repository.

## Where to Read Next

- [`../hardware/WIRING.md`](../hardware/WIRING.md) — the wiring
  guide that this schematic must capture.
- [`../hardware/README.md`](../hardware/README.md) — the pin
  map that this schematic must capture.
- [`../fpga_only_architecture.md`](../fpga_only_architecture.md) —
  the current FPGA-only architecture (single source of truth).
- [`../../fpga/constraints/arty_s7_25.xdc`](../../fpga/constraints/arty_s7_25.xdc)
  — the canonical pin constraints.