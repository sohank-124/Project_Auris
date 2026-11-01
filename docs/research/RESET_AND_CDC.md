# Reset, CDC, and physical timing investigation

## Question

Does a positive timing summary establish that the custom FIFOs and reset release are safe? No: source protocols, reset
epochs, physical bounds, and the timing model must be examined together.

FACT from the retained investigation: functional clock-generator registers previously released from raw MMCM LOCKED; top
reset used parallel chains combined by logic. INFERENCE: release safety was insufficiently established. This was not an
observed analog metastability event, nor a reason to alter correct DSP arithmetic.

The [original review](../verification/evidence/2026-10-30/original_reset_cdc_review.txt) preserves the detailed
acceptance matrix, intermediate problems and actual results. Raw failed runs remain local.

## Selected approach and rejected shortcuts

A final registered reset source replaces the multi-input reduction. Release synchronizes to the clock edge that operates
each state group. Two initial stages carry ASYNC_REG; later delay stages provide waiting time.

Tagging every delay register as ASYNC_REG was tried and produced placement warnings. The final implementation confines
that physical placement intent to actual synchronization pairs. An early topology query also failed because synthesized
scope names and hierarchy pins differed from query assumptions. That was a reporting-script defect, corrected without
changing the data path.

Suppressing warnings, false-pathing release concerns, or placing ASYNC_REG on audio data would not establish a valid
protocol. A larger clock redesign would introduce broader architectural change without removing reset obligations.

Plain language: stop immediately, then restart on controlled local clock edges. A warning-free report alone cannot
substitute for knowing which circuit owns each data word.

## Evidence and limits

The saved current focused tests cover release phases, stopped clocks, injected lock restarts, concurrent FIFO traffic
and occupied resets. A deliberately corrupted FIFO output is rejected by an independent queue checker. The [public
transcripts](../verification/VERIFICATION_STATUS.md) preserve actual results and the source identity.

The routed review accounts for 1470 asynchronous reset controls: 1434 locally FF-sourced controls and 36 intentional
raw-reset chain controls. All 24 first-stage Gray paths have physical bounds and eight skew checks pass. All 129 RAM
consumer endpoints were manually associated with synchronized availability and ownership protection. CDC
warning/critical classifications remain published; there is no blanket waiver or formal-proof claim.

Common asynchronous reset epochs are required for both FIFO sides. One-sided runtime reset is unsupported. Digital lock
injection assumes clocks/lock return and does not prove autonomous MMCM recovery. Analog metastability/MTBF is outside
digital simulation.

## Clock model versus board measurements

Fractional BCLK has unequal edges; the [timing contract](../hardware/TIMING_CONTRACT.md) derives the reserved
uncertainty. Provisional external microphone/wiring budgets are explicit assumptions, not measurements. Positive FPGA
setup/hold results are conditional on those assumptions. See the [hardware demonstration record](../hardware/HARDWARE_VALIDATION.md) for board operation and the [implemented resource/timing reference](../architecture/resource_budget.md) for implementation results.
