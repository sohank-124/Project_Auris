# Mechanical Design

> **Project Auris** — Mechanical design notes for the FPGA-only build. **Last updated:** 2026-08-12 (FPGA-only
> migration: ESP32 cutouts and ventilation removed; buttons-on-Arty noted) **Status:** Authoritative. The breadboard
> prototype has **no mechanical design** — it sits loose on a lab bench. A proper enclosure may be considered in a
> future hardware revision.

This directory will hold the mechanical design files for the Project Auris enclosure, mounting hardware, and assembly
drawings. The breadboard prototype is loose on a lab bench. A proper enclosure is planned for a later phase.

The mechanical design must:

- Protect the breadboard (or, in later revisions, the custom PCB) from physical damage
- Provide acoustic access for the INMP441 microphone (the bottom port must be unobstructed)
- Provide a mounting point for a 3.5 mm headphone jack
- Provide access to the Micro-USB port on the Arty S7-25 for programming
- Be manufacturable on a hobby 3D printer (FDM, ~0.2 mm layer height)
- Be aesthetically acceptable for a college-application portfolio piece

## Requirements

### Form factor

- **Footprint:** Approximately 150 mm × 100 mm (fits a standard 830-point breadboard with a small margin)
- **Height:** Approximately 30 mm above the bench (room for components and 3D-printer-friendly wall thickness)
- **Weight target:** < 200 g (so it can be worn on a lanyard or clipped to a belt loop in future iterations)

### I/O access (cutouts / openings in the enclosure)

| Opening                       | Purpose                                |
| ----------------------------- | -------------------------------------- |
| Micro-USB cutout              | Arty S7-25 programming and power       |
| 3.5 mm headphone jack cutout  | Audio output                           |
| Microphone acoustic port      | Sound entry to INMP441 bottom port     |
| Status LED windows (optional) | STATUS0 heartbeat, STATUS2 clip        |
| RGB LED window                | Mode indicator                         |
| Push-button cutouts (future)  | Mode up/down, volume up/down (on Arty) |
| Ventilation slots (optional)  | Heat dissipation for the FPGA          |

> **Buttons on the Arty.** The Arty S7-25 PCB has four onboard push buttons (BTN0–BTN3). They do **not** need mechanical
> cutouts — they are accessible through the enclosure's top surface (a rectangular slot that aligns with the button row,
> or a fully-open top with the buttons protruding through).

### Mounting

- **Internal:** M2.5 or M3 standoffs for the Arty S7-25 (4 holes on the Arty PCB)
- **External:** Belt clip or lanyard loop on the rear of the enclosure (future)
- **Anti-slip:** Rubber feet on the bottom

### Acoustic considerations

- The **INMP441 bottom port** must have a clear acoustic path to the outside. The preferred implementation is a through-
  hole in the enclosure wall with a small cavity behind it (so the mic is suspended in free air, not pressed against the
  enclosure wall).
- Avoid placing the mic port directly against a flat surface (the bench, a table, the user's clothing) — this blocks the
  bottom port.
- The headphone jack should be on a different face from the mic port to minimize acoustic feedback.

### Thermal considerations

- The **Arty S7-25** can dissipate ~0.5 W with the audio DSP running at full utilization.
- A small vented region near the FPGA is recommended; active cooling is not required.
- Avoid fully enclosing the FPGA in an airtight cavity.

## Planned Deliverables

| File                          | Format       | Purpose                                          |
| ----------------------------- | ------------ | ------------------------------------------------ |
| `auris_enclosure.step`        | STEP (AP214) | Master 3D model; exchange format for CAD tools   |
| `auris_enclosure_top.stl`     | STL          | 3D-printable top shell (FDM, 0.2 mm layer)       |
| `auris_enclosure_bottom.stl`  | STL          | 3D-printable bottom shell                        |
| `auris_enclosure_lid.stl`     | STL          | 3D-printable service lid (for breadboard access) |
| `auris_assembly.pdf`          | PDF          | 2D assembly drawing with callouts                |
| `auris_assembly_exploded.pdf` | PDF          | Exploded view drawing for assembly instructions  |
| `auris_dimensional.pdf`       | PDF          | Dimensioned drawing for manufacturing reference  |
| `auris_enclosure.f3d`         | Fusion 360   | Source-of-truth CAD file (if using Fusion 360)   |
| `README.md`                   | Markdown     | This file                                        |

All deliverables are generated from a single source CAD model to avoid version drift.

## Current State

The current state is **no mechanical design exists**. The breadboard prototype sits loose on a lab bench with cables
hanging out in every direction. This is intentional for Phase 1 (Prototype Bring-up) to maximize access to test points
and to make it easy to swap parts.

The mechanical design is intentionally deferred to Phase 5 because:

1. The PCB is not yet finalized — designing an enclosure around a breadboard is wasted effort when the PCB dimensions
   will differ.
2. The component selection may change (substitute INMP441, alternative DAC, etc.) which would invalidate enclosure
   cutouts.
3. Phase 5 is the production-readiness phase, where mechanical design has the most value.

## Tools

- **Fusion 360** (free for personal/hobby use) — recommended for parametric CAD and STEP export
  ([autodesk.com/products/fusion-360](https://www.autodesk.com/products/fusion-360))
- **FreeCAD** (open source) — alternative for users without Fusion 360
- **KiCad 3D viewer** — for verifying PCB fit in the enclosure cavity
- **PrusaSlicer** or **Cura** — for slicing STLs for 3D printing
- **FDM 3D printer** — Prusa MK4, Bambu X1, or equivalent
- **M2.5 / M3 hardware kit** — standoffs, screws, nuts

## Material recommendations

For the first 3D-printed prototype:

- **Shell material:** PLA or PETG, 0.2 mm layer height, 3 perimeters, 20 % infill. PETG is preferred for its heat
  resistance and toughness.
- **Color:** Black or dark gray to hide the breadboard wiring inside.
- **Acoustic mesh:** None for v1 (the through-hole alone is sufficient). A future v2 may add a fine stainless-steel mesh
  over the mic port for ingress protection.
- **Hardware:** M2.5 × 6 mm pan-head screws, M2.5 × 8 mm brass standoffs (4–6 pieces).

## File Layout (planned)

```text
hardware/mechanical/
|-- README.md                       <- this file
|-- source/
|   |-- auris_enclosure.f3z         <- Fusion 360 archive (source of truth)
|   |-- auris_enclosure.step        <- STEP export for CAD exchange
|-- stl/
|   |-- auris_top.stl
|   |-- auris_bottom.stl
|   |-- auris_lid.stl
|-- drawings/
|   |-- auris_assembly.pdf
|   |-- auris_assembly_exploded.pdf
|   |-- auris_dimensional.pdf
|-- photos/                         <- build photos of the assembled unit
    |-- v1_assembled.jpg
    |-- v1_with_headphones.jpg
```

The mechanical design files will be added in a single commit during the Phase 5 kickoff, after the PCB is finalized.
