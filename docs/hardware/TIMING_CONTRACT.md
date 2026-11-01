# Audio clock and I/O timing contract (F25)

Current acceptance status (2026-10-30): reset-release code and manual CDC review
are accepted for the default configuration/common-reset contract. Fresh full-top
routing passes at **+0.696 ns setup / +0.019 ns hold**. Overall **F25 remains open**
for external timing budgets and physical receiver/PLL validation below.

[Current reset/CDC implementation and acceptance](../verification/evidence/2026-10-30/original_reset_cdc_review.txt)
records tests, timing, reset topology, source hashes and scope limits. The earlier
pre-repair audit (retained locally under `.audit_verification/repair_runs/f25_current/`)
remains historical evidence and source material for the external-budget review.
No autonomous physical MMCM relock or arbitrary one-sided FIFO reset is claimed.

The XDC implements the following conditional timing contract. Passing static
timing analysis (STA) proves FPGA paths against these budgets; it does not
measure the external microphone, wiring, or DAC PLL performance.

## Fractional BCLK

FACT: `clk_gen.sv` toggles BCLK at DSP counter values
`0,16,31,47,62,78,94,109`, repeating after 125 clocks. At nominal 96 MHz:

- Four BCLK periods take 125 DSP clocks: average 3.072 MHz.
- Half-periods are 15 or 16 DSP clocks: 156.250 or 166.667 ns.
- Rising-edge periods are 31,31,32,31 clocks: minimum 322.917 ns.
- LRCLK divides BCLK by 64: average 48 kHz.

The generated-clock ratio is multiply-by-4 / divide-by-125. A single periodic
STA waveform cannot express the eight unequal edge intervals. Relative to
ideal edges every 15.625 DSP clocks, actual edge errors (DSP clocks) are
`0,+0.375,-0.25,+0.125,-0.5,-0.125,+0.25,-0.375`. Their range is 0.875 clocks
(9.115 ns). The XDC reserves **10.417 ns** for this deterministic variation.
This exceeds the maximum difference between any two edge errors, including
across a pattern boundary. MMCM/tool-derived jitter remains separate.

Setup checks ensure data arrives before capture; they receive this margin.
Same-edge internal hold checks ensure data does not change too soon after
capture; their common fractional edge displacement cancels. Opposite-edge
internal hold and external I/O hold checks receive the margin explicitly.
For example the nominal half-cycle setup window, 162.760 ns, becomes at most
152.343 ns before other timing deductions, less than the real 156.250 ns
minimum. Same-edge hold must not receive a spurious full DSP cycle of jitter.

The forwarded `i2s_bclk_forwarded` clock is defined at `i2s_bclk_o`, sourced
from the internal BCLK BUFG. FPGA clock insertion and output routing are
therefore included by STA. The rational waveform is not a claim of a fixed
phase after reset between DSP and BCLK. FIFO CDC datapaths retain their
explicit max-delay/bus-skew constraints; CDC/reset review is still required.

## External budgets

FACT: TI's PCM510xA datasheet SLAS859A, Table 7, specifies DIN setup/hold
8/8 ns and LRCK setup/hold 8/8 ns relative to rising BCK. It also specifies
40 ns minimum BCK period and 16 ns high/low pulses.
[Manufacturer-authored datasheet, archived copy](https://www.kyohritsu.com/eclib/OTHER/DATASHEET/TI/pcm5102a.pdf).
The current SLAS859C document does not reproduce that serial timing table;
the older revision is identified deliberately rather than attributed to C.

FACT: InvenSense DS-INMP441-00 revision 1.1, Table 3/Figure 1, specifies
WS setup/hold 0/20 ns, minimum SCK period 312 ns and high/low pulses 50 ns.
Its table provides no SD clock-to-output maximum.
[Manufacturer-authored datasheet, archived
copy](https://device.report/m/71d42f02ff324329ef86ea160d21bb412a813c2d3014f5a836a2d1305bfde1f5).

ASSUMPTIONS: each external clock/data connection has 0..2 ns flight time;
microphone SD becomes valid 0..100 ns after falling BCLK. **100 ns is an
allocated acceptance budget, not a manufacturer guarantee or a measurement.**
It includes microphone output settling under the actual load. Verify it at
the operating voltage, temperature and wiring before hardware sign-off.

| FPGA port | Reference edge at FPGA BCLK pin | Min delay | Max delay | Derivation |
| --- | --- | ---: | ---: | --- |
| ADC data input | Falling | 0 ns | 104 ns | Clock flight + mic delay + return flight |
| DAC data output | Rising | -10 ns | 10 ns | Hold 8 + worst skew 2; setup 8 + skew 2 |
| LRCLK output | Rising | -22 ns | 10 ns | Stricter of both receivers: hold 20, setup 8, plus skew 2 |

For outputs, skew is data-flight minus clock-flight, in [-2,+2] ns.
`-max = setup + maximum skew`; `-min = -hold + minimum skew`.
LRCLK is timed as receiver data, not false-pathed merely because it is slow.
The receiver samples ADC data on rising BCLK; the input constraint explicitly
uses the microphone's falling launch edge.

## Acceptance and limits

The original constraint-only repair left RTL unchanged. The subsequent reset
repair changes startup release sequencing, preserves steady-state data latency,
and removes three LUTs with unchanged FF/BRAM/DSP/clocking totals. New constraints can change placement/routing on a
future build.
No pipeline stage is needed: logic depth or fanout is not the source of the
incorrect model. Critical paths (least slack), combinational delay and routing
delay must be reviewed under the repaired constraints, for both setup and hold.

Before board acceptance, measure clock pulses and periods at the receivers,
confirm the flight/skew and microphone SD budget above, and check codec lock
and audio performance with the fractional clock. Digital pulse-width compliance
does not prove DAC PLL jitter tolerance or audio quality. Repeat STA/CDC on the
current implemented source revision. Saved-checkpoint reanalysis is evidence
only for that checkpoint, not an implementation of subsequent RTL edits.
