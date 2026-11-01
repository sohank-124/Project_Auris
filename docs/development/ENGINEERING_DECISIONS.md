# Engineering decisions and debugging lessons

This is a retrospective synthesis of source and retained repair records, not a fabricated contemporaneous diary. The
[original decision log](../../archive/documentation/pre-cleanup-2026-10-30/docs/DESIGN_DECISIONS.md.txt) remains
unchanged as a historical snapshot; some of its hardware comparisons and estimates were inaccurate. Do not use it as a
current specification.

## Keep one runtime FPGA control plane

The current build removes the former ESP32/SPI host and uses onboard buttons. This reduces interfaces and firmware
dependencies while retaining mode loading and volume control. It trades runtime host programmability for fixed embedded
profile tables. Archived source preserves the earlier architecture; no performance benefit from this migration is
asserted without measurement.

## Associate metadata by transactions

Problem: forward FFT exponents describe frames, while transform latency and stream stalls can change when those frames
emerge. A fixed 418-cycle delay cannot encode ownership reliably across arbitrary later changes.

Decision: queue forward exponents and consume them in inverse-frame order. Restore previous and current overlap
contributions using their own exponents. Pros: explicit ownership, readable checks, and independence from an estimated
transform latency. Cons: queue state, finite capacity, and reset/overflow obligations. The current FIFO depth is eight;
it is not an unlimited backpressure solution.

Plain language: attach scaling information to the block it belongs to instead of guessing when it arrives. See the
[numerical investigation](../research/NUMERICAL_RECONSTRUCTION.md) and its historical-result limits.

## Wait for ownership acknowledgement

Problem: completing a coefficient write does not mean the consumer has switched banks. Reusing the previous bank too
early could corrupt an in-flight frame.

Decision: write inactive storage, request commit, latch controls at a first-bin boundary, and wait for active-bank
acknowledgement. Pros: coherent coefficients, sustained one-bin-per-cycle throughput, and a focused boundary test. Cons:
a state-machine wait, finite update responsiveness, and no guaranteed click-free transition. The all-position test is
strong protocol evidence, not an audio-quality measurement.

Similarly, output_buffer owns both 128-sample halves explicitly. When neither is free, it rejects a whole incoming block
and preserves unread samples. This costs ownership/drop state and can lose audio under overload, but makes loss bounded
and observable rather than silently replacing unread data. See [system contracts](../architecture/block_diagram.md).

## Separate arithmetic from physical timing and reset concerns

A previous spectral final stage combined power restoration, threshold selection, multiplication and saturation. Recorded
setup failures led to seven registered stages, three more DSP clocks (31.25 ns at 96 MHz), with one-bin-per-cycle
throughput retained. Pros: shorter combinational paths and aligned data/valid registers; cons: added registers, routing,
latency and numerical-regression obligations. The historical full reconstruction result predates current edits, so it
remains historical.

A later reset review found raw LOCKED release and a multi-input reset reduction tree. The chosen registered-release
helper removes the tree and synchronizes each operating edge. Pros: explicit release sequencing and reusable
verification; cons: startup wait, reset-distribution timing obligations and a common-reset contract. Final saved
implementation reports 6165 LUTs, 9851 FFs, 6.5 BRAM tiles, 28 DSPs, 3 BUFGs and 1 MMCM.

Plain language: arithmetic speed, clock modeling, reset safety, and simulator correctness are different problems.
Suppressing a warning or changing correct arithmetic would not solve the others. [Reset/CDC
research](../research/RESET_AND_CDC.md) preserves the failed approaches and acceptance limits.

## Make test completion explicit

A simulator may return after a timeout, early finish, or assertion. The maintained runner requires a completion signal
and scans its transcript. Deliberately corrupted data and malformed completion scenarios test the checkers. This adds
test infrastructure and maintenance work but prevents a successful process exit from masquerading as successful
verification.

[Reproduction guidance](../verification/REPRODUCING.md) distinguishes runner tests from actual RTL simulation. The
[verification matrix](../verification/VERIFICATION_STATUS.md) remains the authority for which results are current.
