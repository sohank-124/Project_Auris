# Bill of Materials

This directory contains the machine-readable bill of materials (BOM) for
the Project Auris hardware, in CSV format, plus the documentation for
interpreting and regenerating the file.

## Overview

- [`bom.csv`](./bom.csv) — the authoritative BOM, one row per line item.
  Open in Excel, Google Sheets, LibreOffice Calc, or import into KiCad.
- [`bom.html`](./bom.html) — (future) interactive HTML BOM generated
  from the CSV via the InteractiveHtmlBom tool, with part photographs and
  placement indicators.
- This `README.md` — explains the CSV schema and how to regenerate the
  file once the KiCad schematic exists.

The high-level, cost-summary view of the BOM is in
[`../../docs/hardware/BOM.md`](../../docs/hardware/BOM.md).

## File Format

The CSV uses the following columns. All fields are required; leave the
field empty (no quotes) if the value is unknown for a given part.

| Column            | Type        | Description                                                              |
|-------------------|-------------|--------------------------------------------------------------------------|
| `Item`            | integer     | Sequential line item number starting at 1                                |
| `Reference`       | string      | Schematic reference designators separated by spaces (e.g., `U1` or `C1 C2 C3`) |
| `Designator`      | string      | Functional block label: `FPGA` `ESP32` `MIC` `DAC` `BREADBOARD` etc.    |
| `Qty`             | integer     | Total quantity of this part required for one build                       |
| `Description`     | string      | Human-readable description of the part                                   |
| `Manufacturer`    | string      | Component manufacturer (e.g., `Texas Instruments` or `Generic`)         |
| `MPN`             | string      | Manufacturer Part Number                                                |
| `DigiKey_PN`      | string      | DigiKey part number (if stocked)                                         |
| `Mouser_PN`       | string      | Mouser part number (if stocked)                                          |
| `LCSC_PN`         | string      | LCSC part number (if stocked; popular for JLCPCB assembly)               |
| `Footprint`       | string      | PCB footprint name (KiCad library); blank for off-board items            |
| `Value`           | string      | Component value (e.g., `10k` for a resistor, `0.1uF` for a cap)          |
| `Datasheet_URL`   | URL         | Datasheet or product page URL                                            |
| `Notes`           | string      | Free-form notes: warnings, substitutes, configuration hints              |

### Quoting rules

The CSV is RFC 4180-compliant. Fields that contain commas, double quotes,
or newlines **must** be quoted with double quotes. Embedded double quotes
are escaped by doubling them. The CSV was hand-checked for:

- No trailing whitespace
- No BOM (byte-order mark)
- Consistent LF line endings
- Header row matches data column order

## How to Regenerate

This BOM is currently maintained by hand. Once the KiCad schematic exists
(Phase 2 — see [`../schematics/README.md`](../schematics/README.md)), the
CSV will be regenerated from the schematic using KiCad's
**`bom_csv_grouped_by_value`** plugin:

1. Open the schematic in Eeschema.
2. Run **Tools -> Generate Bill of Materials**.
3. Select the **`bom_csv_grouped_by_value`** plugin (ships with KiCad 8).
4. Set the output path to `hardware/bom/bom.csv`.
5. Click **Generate**. The plugin will overwrite the existing CSV.
6. Manually fill in the `DigiKey_PN`, `Mouser_PN`, `LCSC_PN`, and
   `Datasheet_URL` columns from the project vendor-preference spreadsheet
   (these are not derivable from the schematic).

### Alternative: InteractiveHtmlBom

For a more visual, placement-aware BOM suitable for assembly, generate an
HTML BOM using the [InteractiveHtmlBom](https://github.com/openscopeproject/InteractiveHtmlBom)
KiCad plugin:

```bash
# From the project root, with KiCad 8 and InteractiveHtmlBom installed
kicad-cli sch export python-bom \
    --output hardware/bom/bom.html \
    hardware/schematics/auris_main.kicad_sch
```

This is recommended for the assembly phase (Phase 3) but is not required
for the breadboard prototype.

## Procurement Guide

### Recommended vendors

| Vendor  | Best for                                     | Notes                                                  |
|---------|----------------------------------------------|--------------------------------------------------------|
| DigiKey | All major parts; fast USA shipping           | Primary vendor for this project; excellent search     |
| Mouser  | ESP32, PCM5102A; strong European presence    | Often cheaper than DigiKey on TI parts; good for EMEA  |
| LCSC    | Passives, breakout boards                    | Cheapest for passives; 2-3 week shipping to USA       |
| Amazon  | Breadboard, jumper wires, USB cables         | Fast Prime delivery; watch for counterfeits on cables  |
| JLCPCB  | PCB fabrication + SMT assembly               | Use together with LCSC for cheapest PCB build          |

### Lead time expectations

- **In-stock US vendors (DigiKey, Mouser):** 2-5 business days
- **LCSC to USA:** 2-3 weeks
- **LCSC to Europe:** 3-4 weeks
- **JLCPCB PCB fab:** 1-2 weeks depending on tier
- **Digilent direct:** 1-2 weeks international

### Order checklist

When placing an order, verify:

- [ ] The `Qty` in the BOM is the per-build quantity (not per-1000 reel)
- [ ] The `Footprint` matches a KiCad library part for any PCB-bound items
- [ ] The `MPN` matches the manufacturer brand (some clones exist for
      ESP32 modules; buy from authorized distributors)
- [ ] The `Datasheet_URL` is current and points to a manufacturer-controlled
      domain (not a third-party PDF host)

### Discontinued parts

The INMP441 microphone is **discontinued** at DigiKey and Mouser. See
[`../../docs/hardware/BOM.md`](../../docs/hardware/BOM.md#alternatives-for-the-inmp441)
for the list of drop-in substitutes (SPH0645 from Knowles is recommended).

## Interactive HTML BOM

A future enhancement (Phase 3) will be an interactive HTML BOM generated
via the
[InteractiveHtmlBom](https://github.com/openscopeproject/InteractiveHtmlBom)
tool. The HTML BOM shows:

- A panned/zoomable rendering of the PCB with each component clickable
- A side panel listing all components grouped by value
- Search by reference designator
- "Check on board" buttons for assembly tracking

This file is **not** committed to the repository because it includes
fabrication data (Gerber-derived board renders) that we do not want to
expose publicly. It is generated on demand by the build system.
