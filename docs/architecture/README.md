# Architecture Documentation

> **Project Auris** — FPGA-accelerated hearing-assistive device
> **Last updated:** 2026-07
> **Status:** Authoritative. The seven documents in this directory
> describe the system in enough detail to rebuild it from scratch.

This directory is the architectural reference for Project Auris.
Every hardware and firmware decision is documented here, with
diagrams, tables, and — where useful — actual RTL and C code
snippets. The docs are written to be read by an engineer (or
college-admissions reviewer) joining the project mid-stream; if
something is unclear, the assumption is that the doc needs more
detail, not that the reader needs more context.

The architecture is split into two physical subsystems
(Cmod S7-25 FPGA + ESP32-DevKitC-32E) joined by a single SPI link,
plus the analog audio chain (INMP441 mic → PCM5102A DAC →
headphones). Each document in this directory covers one slice of
the design.

---

## 1. Document Index

| Document                              | Audience             | What it covers                                                                                                  |
|---------------------------------------|----------------------|-----------------------------------------------------------------------------------------------------------------|
| [`block_diagram.md`](block_diagram.md)            | Everyone — start here | Mermaid + ASCII system block diagram. Three signal-flow narratives (audio, control, telemetry).                 |
| [`dsp_pipeline.md`](dsp_pipeline.md)              | Hardware / DSP       | 256-pt FFT-based spectral processor. Math, data formats, latency budget, per-stage resource estimates.          |
| [`clock_domains.md`](clock_domains.md)            | Hardware / timing    | Four clock domains, three CDC boundaries, metastability mitigation, timing-constraint summary.                  |
| [`register_map.md`](register_map.md)              | Hardware + firmware  | 128 × 24-bit SPI register file. Frame format, address map, gain table format, typical access patterns.         |
| [`firmware_arch.md`](firmware_arch.md)            | Firmware             | 11 components, 8 FreeRTOS tasks, mode state machine, SPI protocol, NVS layout, BLE GATT interface (planned).  |
| [`resource_budget.md`](resource_budget.md)        | Hardware             | XC7S25 LUT / FF / BRAM / DSP48 budget. Per-module estimates, BRAM and DSP48 allocation, risk areas.             |

---

## 2. Reading Order for Newcomers

If you are reading the docs for the first time, follow this order:

1. **[`block_diagram.md`](block_diagram.md)** — get the high-level
   picture. After this doc you should be able to draw the system
   from memory: a microphone, an FPGA doing spectral processing,
   a DAC, headphones, an ESP32 doing the user interface, and an
   SPI link tying it together.
2. **[`dsp_pipeline.md`](dsp_pipeline.md)** — understand the
   *what* of the audio processing. Hann window, FFT, per-bin
   gain, noise gate, IFFT, overlap-add. You should be able to
   explain the transfer function `Y[ω] ≈ G[ω] * X[ω]` and the
   end-to-end latency (≈ 5.33 ms).
3. **[`clock_domains.md`](clock_domains.md)** — understand the
   *how* of the timing. Four clock domains, three CDC boundaries,
   metastability mitigation. You should be able to explain why
   the CDC paths are false-pathed in the XDC and what the
   expected MTBF is.
4. **[`register_map.md`](register_map.md)** — learn the host ↔
   FPGA contract. 32-bit SPI frames, command byte, address, data,
   the 128-entry register file, the gain table format. You should
   be able to write a register read/write transaction from scratch.
5. **[`firmware_arch.md`](firmware_arch.md)** — understand the
   *software*. 11 components, 8 FreeRTOS tasks, the mode state
   machine, the IPC primitives, the NVS storage layout, the BLE
   GATT service. You should be able to explain how a button press
   flows from GPIO to FPGA register write.
6. **[`resource_budget.md`](resource_budget.md)** — understand
   the *cost*. Per-module LUT / FF / BRAM / DSP48 estimates, the
   risk areas, the headroom for Phase 6 features.

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
(see `docs/IMPLEMENTATION_PLAN.md` for the phase plan). A phase
review is a good time to catch stale diagrams, missing cross-
references, and references to as-yet-unimplemented features.

---

## 4. Related Documentation

This directory is one of four documentation directories in
`docs/`:

- **`docs/IMPLEMENTATION_PLAN.md`** — the master plan: repo
  layout, phases, build instructions, code-skeleton index, risk
  mitigation. **Read this first** if you are new to the project.
- **`docs/architecture/`** — this directory. The seven
  architecture documents.
- **`docs/hardware/`** — schematics, pin maps, BOM, mechanical
  design notes.
- **`docs/phase_reports/`** — end-of-phase reflections: what
  worked, what didn't, what changed, what's next.
- **`docs/college_app/`** — college-application material: essay
  topics, demo script, portfolio tips.
