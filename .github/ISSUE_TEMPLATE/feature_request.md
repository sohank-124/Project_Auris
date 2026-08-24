---
name: Feature Request
about: Suggest a new feature, enhancement, or non-trivial change for Project Auris
title: "[FEATURE] "
labels: ["enhancement", "triage"]
---

<!--
Feature requests that don't map to the current development phases take
much longer to triage. Please skim docs/IMPLEMENTATION_PLAN.md first and
reference the phase your idea fits into (or explain why it should
spawn a new phase). Note that the implementation plan was authored
for the pre-migration ESP32+FPGA build; the FPGA-only architecture is
the current one. See docs/fpga_only_architecture.md.
-->

## Summary

<!-- One-paragraph description of the proposed feature. -->

## Motivation

<!--
What problem does this solve? Who benefits? Is there a real use case
on hardware you own, or a hypothetical one? Link to any prior art.
-->

## Area

<!-- Tick all that apply. -->

- [ ] FPGA (`fpga/`)
- [ ] Tools (`tools/`)
- [ ] Hardware / schematics (`hardware/`)
- [ ] Documentation (`docs/`)
- [ ] CI / CD (`.github/`)

## Proposed Approach

<!--
Sketch the design: which files would change, which interfaces are touched,
what the new RTL module or Python script would look like at a high
level. Diagrams welcome (ASCII, Mermaid, or attach an image).
-->

## Alternatives Considered

<!--
What other designs did you weigh, and why is the proposed approach
better? Or: "No alternative considered — happy to discuss."
-->

## Phase Alignment

<!--
Open docs/IMPLEMENTATION_PLAN.md (historical) and identify which phase
this belongs to. Examples for the FPGA-only build:
  * Mode / gain table refinement → adds a new pre-computed gain table
    in `mode_ctrl.sv`
  * DSP pipeline enhancement → adds a new spectral processor block
  * Verification maturity → adds SVA to an existing module
  * Hardware → custom PCB or 3D-printed enclosure
If it does not fit any current phase, suggest which new phase it would
define, and what prerequisite work would be needed.
-->

**Phase:** _e.g. Phase 3 — Polish_
**Prerequisites:** _what needs to exist first, if anything_

## Additional Context

<!-- Links, papers, datasheets, prior-art repos, or related issues. -->