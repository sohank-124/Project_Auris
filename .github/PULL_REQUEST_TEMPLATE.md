<!--
Thanks for contributing to Project Auris! Please fill out this template
in full. A focused PR with a clear description and passing CI is far
easier to review than a sprawling one.

If your PR closes an existing issue, link it with "Closes #N". If it
fixes a security issue, see SECURITY.md (if present) and do NOT file a
public issue first.

Note: Project Auris is an FPGA-only build. There is no ESP32, no
firmware at runtime, no SPI host interface. "Build" in this template
means Vivado synthesis + implementation + xsim simulation.
-->

## Description

<!--
What does this PR do, and why? Reference the relevant design notes,
discussions, or issues. Include before/after reasoning where it is not
obvious from the diff alone.
-->

Closes #

## Area

<!-- Tick all that apply. -->

- [ ] FPGA (`fpga/`)
- [ ] Tools (`tools/`)
- [ ] Hardware (`hardware/`)
- [ ] Documentation (`docs/`)
- [ ] CI / CD (`.github/`)

## Type of Change

<!-- Tick exactly one. -->

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing behaviour to change)
- [ ] Documentation update (no code change)
- [ ] Refactor / cleanup (no behaviour change)
- [ ] Build / CI / tooling (no production code change)

## Testing Checklist

<!--
Tick the boxes that apply. CI runs the lint and sim gates; the
hardware-test row is for changes that need bench validation. Add a
new test whenever you add a feature or fix a bug.
-->

- [ ] `verible-verilog-lint` passes on `fpga/rtl/**/*.sv`
- [ ] `make fpga-sim` passes (or the relevant `fpga/scripts/sim_*.tcl` for the affected TB)
- [ ] Affected Python tools (`tools/`) run cleanly and produce expected outputs
- [ ] `markdownlint` passes on touched `.md` files
- [ ] Manual hardware test on Arty S7-25 (programming the bitstream and verifying STATUS0 heartbeat, mode cycling, audio playback)
- [ ] New test added (and linked below)

**Test details:** _e.g. "Added `tb_btn_debounce_edge_test`; runs in 1.2 ms."_

## Timing Closure

<!--
For changes to any DSP / CDC / I2S / reset path on the FPGA, fill in
the post-route timing summary. Skip for non-timing-critical changes.
-->

- [ ] Post-route WNS (worst negative slack) ≥ 0.0 ns at the 96 MHz target
- [ ] Post-route WHNS (worst hold slack) ≥ 0.0 ns
- [ ] No new CDC paths introduced (or: new CDC paths documented and reviewed)

## Screenshots / Waveforms

<!--
For RTL changes, attach a GTKWave / Vivado waveform capture of the
relevant signals (BCLK, LRCLK, FFT output, gain-table load, etc.).
For UI / docs changes, attach a screenshot.
For everything else, write "N/A".
-->

## Final Checklist

- [ ] I have read [CONTRIBUTING.md](../CONTRIBUTING.md)
- [ ] My code follows the project's style (Verible, ruff, markdownlint all clean)
- [ ] I have updated the relevant documentation
- [ ] I have added an entry to [CHANGELOG.md](../CHANGELOG.md) under "Unreleased"
- [ ] My PR is focused on a single concern (no unrelated drive-by edits)
- [ ] I have signed off my commits (`git commit -s`)

<!--
After opening the PR, verify the CI dashboard (the Actions tab) shows
green for all required jobs. If `ci-pass` is red, fix the underlying
job — don't silence it with continue-on-error unless you have a tracked
follow-up issue.
-->