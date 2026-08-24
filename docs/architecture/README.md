# Architecture Documentation

> **Project Auris** — FPGA-accelerated hearing-assistive device
> **Last updated:** 2026-08-12 (FPGA-only migration: index updated;
> `register_map.md` and `firmware_arch.md` reclassified as historical)
> **Status:** Authoritative. The seven documents in this directory
> describe the system in enough detail to rebuild it from scratch.

This directory is the architectural reference for Project Auris.
Every hardware decision is documented here, with diagrams, tables,
and — where useful — actual RTL code snippets. The docs are written
to be read by an engineer (or college-admissions reviewer) joining
the project mid-stream; if something is unclear, the assumption is
that the doc needs more detail, not that the reader needs more
context.

The architecture is **FPGA-only**: a single Arty S7-25 (XC7S25)
performs all signal processing, all control, and is the I²S clock
master for both the INMP441 microphone and the PCM5102A DAC.
Onboard push buttons drive inline mode and volume FSMs in `top.sv`.
There is no ESP32, no firmware at runtime, no SPI host interface,
no BLE, no NVS.

For the canonical architecture overview, see
[`../fpga_only_architecture.md`](../fpga_only_architecture.md).
For the migration narrative (what changed on 2026-08-12), see
[`../migration_summary.md`](../migration_summary.md).

---

## 1. Document Index

### 1.1 Current (FPGA-only build)

| Document                                                | Audience             | What it covers                                                                                                  |
|---------------------------------------------------------|----------------------|-----------------------------------------------------------------------------------------------------------------|
| [`block_diagram.md`](block_diagram.md)                  | Everyone — start here | Mermaid + ASCII system block diagram. Three signal-flow narratives (audio, control, indicators).                |
| [`dsp_pipeline.md`](dsp_pipeline.md)                    | Hardware / DSP       | 256-pt FFT-based spectral processor. Math, data formats, latency budget, per-stage resource estimates.          |
| [`clock_domains.md`](clock_domains.md)                  | Hardware / timing    | Two clock domains, two CDC FIFO boundaries, metastability mitigation, timing-constraint summary.               |
| [`modes_and_gains.md`](modes_and_gains.md)              | Hardware / UX        | Four listening modes (General/Speech/Music/Hearing), pre-computed gain tables, RGB LED colour map.            |
| [`resource_budget.md`](resource_budget.md)              | Hardware             | XC7S25 LUT / FF / BRAM / DSP48 budget. Per-module estimates, BRAM and DSP48 allocation, risk areas.             |

### 1.2 Historical (pre-migration ESP32 + FPGA build)

| Document                                                | Original audience     | Why it's now historical                                                                                        |
|---------------------------------------------------------|------------------------|-----------------------------------------------------------------------------------------------------------------|
| [`register_map.md`](register_map.md)                    | Hardware + firmware    | SPI register map (128 × 24-bit) accessed by the ESP32. The SPI host interface was removed on 2026-08-12.            |
| [`firmware_arch.md`](firmware_arch.md)                  | Firmware               | ESP32-DevKitC-32E firmware architecture (ESP-IDF + FreeRTOS, BLE GATT, NVS). The ESP32 was removed on 2026-08-12. |

---

## 2. Reading Order for Newcomers

If you are reading the docs for the first time, follow this order:

1. **[`../fpga_only_architecture.md`](../fpga_only_architecture.md)**
   — get the canonical high-level picture. After this doc you
   should be able to draw the system from memory: a microphone,
   an FPGA doing all signal processing and control, a DAC,
   headphones, and the four onboard push buttons as the user
   interface.
2. **[`block_diagram.md`](block_diagram.md)** — the Mermaid +
   ASCII system block diagram with three signal-flow narratives
   (audio, control, indicators).
3. **[`dsp_pipeline.md`](dsp_pipeline.md)** — understand the
   *what* of the audio processing. Hann window, FFT, per-bin
   gain, noise gate, IFFT, overlap-add, volume. You should be
   able to explain the transfer function `Y[ω] ≈ G[ω] * X[ω]`
   and the end-to-end latency (≈ 5.33 ms).
4. **[`clock_domains.md`](clock_domains.md)** — understand the
   *how* of the timing. Two clock domains (DSP + I2S), two CDC
   FIFO boundaries, metastability mitigation. You should be
   able to explain why the CDC paths are false-pathed in the
   XDC and what the expected MTBF is.
5. **[`modes_and_gains.md`](modes_and_gains.md)** — the four
   listening modes (General, Speech, Music, Hearing), the
   pre-computed per-mode gain tables, and the RGB LED colour
   map.
6. **[`resource_budget.md`](resource_budget.md)** — understand
   the *cost*. Per-module LUT / FF / BRAM / DSP48 estimates,
   the risk areas, the headroom for Phase 6 features.

The historical documents (`register_map.md` and `firmware_arch.md`)
are useful for understanding what changed during the 2026-08-12
migration but are **not** part of the current architecture. Read
[`../migration_summary.md`](../migration_summary.md) for the
narrative.

For a deeper understanding of any specific module, follow the
"where to read next" section at the bottom of each document.

---

## 3. Document Maintenance

These documents are **living** — they are updated as the design
evolves. The process for keeping them accurate is:

1. **Update the doc in the same commit as the code change.** A
   doc that disagrees with the code is worse than no doc at all.
2. **Update the "Last updated" date at the top of the doc.**
3. **Update the "Status" field** if the doc moves from
   "Authoritative" to "Draft" or vice versa.
4. **Cross-link liberally.** Every doc ends with a "where to read
   next" section. If you add a new doc, link to it from every
   relevant existing doc.

The doc set is reviewed at the end of every development phase
(see the historical `docs/IMPLEMENTATION_PLAN.md` for the
pre-migration phase plan; banner-added 2026-08-12). A phase
review is a good time to catch stale diagrams, missing cross-
references, and references to as-yet-unimplemented features.

---

## 4. Related Documentation

This directory is one of several documentation directories in
`docs/`:

- **`docs/fpga_only_architecture.md`** — canonical architecture
  overview for the FPGA-only build (read this first).
- **`docs/migration_summary.md`** — narrative of what changed on
  2026-08-12.
- **`docs/architecture/`** — this directory. The seven
  architecture documents (five current, two historical).
- **`docs/hardware/`** — schematics, pin maps, BOM, mechanical
  design notes.
- **`docs/phase_reports/`** — end-of-phase reflections: what
  worked, what didn't, what changed, what's next.
- **`docs/college_app/`** — college-application material: essay
  topics, demo script, portfolio tips.
- **`docs/IMPLEMENTATION_PLAN.md`** — HISTORICAL (pre-migration
  plan, banner-added 2026-08-12).
