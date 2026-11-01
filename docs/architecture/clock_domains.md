# Clocks, reset, and clock-domain crossing

[clk_gen.sv](../../fpga/rtl/clk_gen.sv) derives a 96 MHz DSP clock from the board's 12 MHz reference using an MMCM. Its
fractional divider produces BCLK at an average 3.072 MHz; LRCLK divides BCLK by 64 for 48 kHz. BCLK half-periods are 15
or 16 DSP cycles. These are related generated clocks, not independent oscillators, but crossings use asynchronous-FIFO
protocols rather than assuming a fixed usable phase.

Four depth-4, 24-bit LUTRAM FIFOs carry paired left/right samples. Each binary pointer has a registered Gray-code
representation and two destination-domain synchronization stages tagged ASYNC_REG. Consumers capture the visible FIFO
head only when synchronized availability qualifies it. Source ownership prevents overwrite before consumption has
crossed back.

In plain language, the pointer is a publication signal: data is written first, then declared available after
synchronization. Simulation checks ordering and reset behavior; physical path bounds remain necessary.

## Constraints and acceptance

[cdc_fifo.xdc](../../fpga/constraints/cdc_fifo.xdc) bounds first-stage Gray-pointer delay and bus skew to 10 ns, and
bounds RAM-to-consumer data propagation. Second synchronizer stages remain ordinarily timed. Blanket asynchronous clock
groups are deliberately absent because they would override these bounds. Audio data buses are not independently
bit-synchronized.

The [timing contract](../hardware/TIMING_CONTRACT.md) explains fractional-edge uncertainty and provisional external
budgets. The published [evidence](../verification/VERIFICATION_STATUS.md) retains CDC warnings and critical
classifications. Acceptance is a manual default-configuration protocol review, not a clean automatic CDC report or
exhaustive formal proof.

## Reset

[reset_release.sv](../../fpga/rtl/cdc/reset_release.sv) asserts asynchronously and releases through clocked registers.
Only the initial synchronization pair carries ASYNC_REG; a final register drives downstream reset. Clock-generator state
releases on its actual operating edge, including falling-edge LRCLK generation. Top-level DSP/I²S reset helpers preserve
the default 16-cycle stretch.

Both FIFO sides must share one asynchronous reset epoch, with independently synchronized release. Arbitrary one-sided
runtime reset is unsupported. Digital lock injection exercises reset response when clocks and lock return.

The [reset and CDC investigation](../research/RESET_AND_CDC.md) records why the earlier reset reduction tree was
replaced and how protocol reasoning was combined with physical timing review.
