# Bill of Materials

> **Project Auris** — FPGA-only build bill of materials.
> **Last updated:** 2026-08-12 (FPGA-only migration: ESP32 removed)
> **Status:** Authoritative. The complete part-by-part list
> with vendor part numbers, footprints, and datasheet links is in
> [`../../hardware/bom/bom.csv`](../../hardware/bom/bom.csv). The
> summary below groups parts by category and gives an estimated
> total cost for a single prototype.

All costs are USD estimates as of early 2026 and are intended
for budgeting only. Verify pricing with the vendor before
ordering. Most parts are available from DigiKey and Mouser;
some passives can be sourced more cheaply from LCSC.

## Summary

| Category       | Item                                | Qty | Unit Cost (est.) | Total  | Source                |
|----------------|-------------------------------------|-----|------------------|--------|-----------------------|
| FPGA module    | Arty S7-25 (Digilent 410-346)       | 1   | $59.00           | $59.00 | DigiKey / Digilent    |
| Microphone     | INMP441 I2S MEMS mic (breakout)     | 1   | $8.00            | $8.00  | DigiKey / LCSC        |
| DAC            | PCM5102A breakout (GY-PCM5102, 3.3 V or 5 V VIN — see note) | 1 | $6.50 | $6.50 | Amazon (e.g. DORHEA 5 V VIN) / DigiKey / Mouser / LCSC |
| Breadboard     | 830-point solderless breadboard     | 1   | $5.00            | $5.00  | Amazon / generic      |
| Jumper wires   | M-M assortment (65 pcs)             | 1   | $6.00            | $6.00  | Amazon / generic      |
| Jumper wires   | M-F assortment (40 pcs)             | 1   | $5.00            | $5.00  | Amazon / generic      |
| Jumper wires   | F-F assortment (40 pcs)             | 1   | $5.00            | $5.00  | Amazon / generic      |
| Capacitor      | 0.1 uF ceramic (decoupling)         | 5   | $0.10            | $0.50  | DigiKey / LCSC        |
| Capacitor      | 10 uF electrolytic (bulk)           | 2   | $0.20            | $0.40  | DigiKey / LCSC        |
| Resistor       | 10 kohm 1% (pull-ups)               | 4   | $0.05            | $0.20  | DigiKey / LCSC        |
| USB cable      | USB-A to Micro-USB (Arty power/program) | 1   | $3.00            | $3.00  | Amazon / generic      |
| Audio          | 3.5 mm headphones (test load)       | 1   | $8.00            | $8.00  | Any                   |
| **Total (estimated)** |                                 |     |                  | **$106.60** |                  |

> **Note:** Costs assume breakout boards for the INMP441 and
> PCM5102A. If you buy bare ICs and build breakouts yourself,
> you can save ~$5 on the mic and ~$3 on the DAC, but the
> assembly time and risk are not worth it for a single
> prototype.
>
> **DAC voltage variants:** Amazon GY-PCM5102 listings come in two
> flavors that look identical. 3.3 V-direct modules take `VCC` from
> Pmod JA hole 6. 5 V-VIN modules with an onboard LDO (e.g. DORHEA
> B0DCFN2JGF, `Supply: 5V`) need `VIN` from Arduino-header 5V0 or an
> external 5 V supply — never from Pmod 3.3 V (LDO dropout starves
> the chip) and never 5 V into FPGA I/O. Signals stay 3.3 V logic;
> grounds must be common. See `WIRING.md` §5–§6 for both wirings.
>
> **No ESP32.** The pre-migration BOM listed an
> ESP32-DevKitC-32E module (~$12) and a second USB cable
> (~$3). The ESP32 co-processor was removed from the build on
> 2026-08-12; the FPGA is the sole signal-processing and
> control entity in the FPGA-only build.

## Detailed BOM

The complete, machine-readable BOM with all vendor part numbers
is in
[`../../hardware/bom/bom.csv`](../../hardware/bom/bom.csv). Open it
in Excel, Google Sheets, or any spreadsheet program. Columns are
documented in
[`../../hardware/bom/README.md`](../../hardware/bom/README.md).

## Procurement Notes

### Lead times

- **Arty S7-25** — Stock at DigiKey (USA warehouse). Typically
  1–2 weeks international.
- **INMP441** — **Discontinued at DigiKey and Mouser.** See
  alternatives below.
- **PCM5102A** — Stock at DigiKey, Mouser, and LCSC. The
  TSSOP-20 package (`PCM5102APWR`) is in stock; the bare die
  version is also available on a Texas Instruments
  evaluation module.

### Alternatives for the INMP441

The INMP441 has been discontinued by TDK/InvenSense. Several
drop-in alternatives exist:

| Part     | Manufacturer | Interface  | Notes                                       |
|----------|--------------|------------|---------------------------------------------|
| INMP441  | TDK          | I2S        | Original, discontinued; some LCSC stock     |
| SPH0645  | Knowles      | I2S        | Pin-compatible, 24-bit, similar performance |
| ICS-43434 | TDK         | I2S        | Bottom-port, 24-bit, I2S-native             |
| MP34DT05 | STMicro      | PDM/SPI    | Requires decimation; not a drop-in         |

**Recommended substitute:** SPH0645 (Knowles) — same I2S
interface, same 24-bit data, same 3.3 V supply, similar pinout.
The only meaningful difference is the acoustic port location
(top-port vs bottom-port), which affects mechanical integration
but not electrical behavior.

### Recommended vendors

| Vendor  | Best for                                     | Notes                             |
|---------|----------------------------------------------|-----------------------------------|
| DigiKey | All major parts; fast USA shipping           | Primary vendor for this project   |
| Mouser  | PCM5102A; strong European presence           | Often cheaper than DigiKey on TI   |
| LCSC    | Passives, breakout boards                    | Cheapest for passives; slow ship  |
| Amazon  | Breadboard, jumper wires, USB cables         | Fast, but watch for counterfeits  |

## Total Estimated Cost

- **Single prototype:** ~$106.60 (see summary table)
- **Two prototypes (recommended for parallel bring-up):** ~$195
- **Five units (class-set):** ~$450 (volume discounts on
  Arty S7-25 and passives)

## Notes

### Reusable parts

These parts are likely to be reusable across multiple
iterations or projects:

- **Arty S7-25** — reusable for any Spartan-7 hobby project
- **Breadboard** — reusable until the wires wear out the
  contacts
- **Jumper wires** — reusable indefinitely
- **USB cables** — generic, reusable

### Single-use / consumable

- **0.1 uF and 10 uF capacitors** — these are dirt-cheap; do
  not bother salvaging.
- **10 kohm resistors** — same as above.

### Optional parts

- **Oscilloscope or logic analyzer** — not in the BOM but
  **strongly recommended** for debug. A $20 USB logic
  analyzer (e.g., Saleae clone) is sufficient for I²S work.
- **Anti-static mat and wrist strap** — recommended for the
  FPGA and DAC handling.
- **Breadboard power supply module** — not required since the
  board is USB-powered, but useful if you need to disconnect
  the host.

### Not in this BOM

The following are **deliberately** excluded from the BOM:

- Host computer (laptop or desktop for programming)
- Oscilloscope / logic analyzer (see "Optional parts" above)
- Soldering iron (not needed for breadboard prototype)
- Anti-static equipment (see "Optional parts" above)
- Battery, charging circuit, battery monitor (no battery in
  the FPGA-only build)

### Future versions

This BOM is for the **breadboard prototype only** (Phase 1).
The production-version BOM (a later phase) will add:

- Custom PCB (1–2 layer, JLCPCB or PCBWay)
- 3D-printed enclosure
- Optional LiPo battery and charging circuit (TP4056) for
  wearable operation
- Power switch, additional buttons or LEDs

See [`../../hardware/mechanical/README.md`](../../hardware/mechanical/README.md)
and [`../../hardware/schematics/README.md`](../../hardware/schematics/README.md)
for the planned Phase 2 and Phase 5 deliverables.