# Verification status

Updated 2026-11-01: the project owner has confirmed physical audio operation and recorded a demonstration. The tables
below collect the saved implementation and simulation results.

A source manifest records SHA-256 hashes of exact input files. A Git commit alone cannot identify the many uncommitted
repairs. The latest 82-file implementation manifest matched the local files before this documentation cleanup.
Implementation/tool inputs are preserved during cleanup and checked again at completion.

## Evidence matrix

| Subsystem | Method | Recorded result | Source identity | Remaining limitations |
| --- | --- | --- | --- | --- |
| Production top | Vivado 2026.1 synthesis, route, bitstream generation | Setup +0.696 ns; hold +0.019 ns; no failing setup/hold endpoints; no unconstrained internal endpoints | [82-file manifest](evidence/2026-10-30/implementation_sources.json) | Conditional external budgets; warnings remain; not a board test |
| Resource use | Routed utilization | 6165 LUT, 9851 FF, 6.5 BRAM36-equivalent, 28 DSP | Same implementation manifest | Actual selected configuration only |
| Reset release | Focused phase/stopped-clock/lock-injection simulation | 20 phases, 8 injected restarts, 1200 BCLK edges | Same manifest; [focused transcript](evidence/2026-10-30/focused_final.txt) | Digital behavior, not analog metastability or autonomous physical relock |
| Both FIFO modules | Concurrent independent queues, both rate directions, full-width stimulus | Four cases, 12 epochs, 6 occupied resets, 6 drains; all 24 data bits exercise both values | Same manifest; [full-width transcript](evidence/2026-10-30/cdc_fullwidth.txt) | Common asynchronous reset epoch required; bounded simulation |
| FIFO checker | Deliberate output corruption | Rejected by specific queue diagnostic | [Negative-control transcript](evidence/2026-10-30/faults_fullwidth.txt) | Expected Fatal text is an injected fault, not a production failure |
| Generated clocks | MMCM/BUFG simulation and period checks | 96000 DSP / 3072 BCLK / 48 LRCLK rising edges per ms; 6144 half periods | [Focused transcript](evidence/2026-10-30/focused_final.txt) | Digital clock simulation |
| Full-top reset integration | Actual MMCM/FFT models; test-local IP cold entry | Three restart epochs pass | [Top reset](evidence/2026-10-30/top_reset.txt), [cold entry](evidence/2026-10-30/top_reset_cold.txt); same manifest | Short reset test, not sustained audio reconstruction |
| Hann/default-mode exports | Actual ROM output and embedded-array comparison | 256 Hann words and 512 mode words match exports | [Export evidence](evidence/export-equivalence/README.md) | Fingerprinted historical run; inspection exports do not configure RTL |
| Unity DSP reconstruction | Vendor models; independent sample comparison | 16 frames; 2048 OLA / 1920 final samples; max error 709, bound 8192 | [Historical manifest and transcript](evidence/historical-reconstruction/README.md) | Several current files differ; burst-fed with drain gaps; not all modes or realtime pacing |
| Spectral arithmetic/frame control | Focused self-checking benches | Prior repair record reports 6144 arithmetic, 6144 power and 131072 frame-bin checks | [Tests](../../fpga/sim/testbenches/); raw local repair records retained | No current complete-suite certification; counts are historical recorded checks |
| I²S, input/output buffering, volume | Directed self-checking benches | Prior focused results retained in local repair records; benches remain public | [Reproduction commands](REPRODUCING.md) | Do not infer a fresh pass for all modules from test existence |
| Physical microphone, DAC, controls, audio output | Board demonstration | Owner confirmed working audio and recorded video | [Hardware record](../hardware/HARDWARE_VALIDATION.md) | Acoustic demonstration |

## Public reports

- [Full routed timing](evidence/2026-10-30/timing.rpt), [utilization](evidence/2026-10-30/utilization.rpt), and
  [check_timing](evidence/2026-10-30/check_timing.rpt).
- [CDC classifications](evidence/2026-10-30/cdc_all_checks.rpt), [bus skew](evidence/2026-10-30/bus_skew.rpt),
  [exceptions](evidence/2026-10-30/exceptions.rpt), and [ignored
  exceptions](evidence/2026-10-30/exceptions_ignored.rpt).
- [Original reset/CDC acceptance narrative](evidence/2026-10-30/original_reset_cdc_review.txt) and [reset topology
  transcript](evidence/2026-10-30/reset_topology_final.txt).
- [Evidence index and provenance](evidence/2026-10-30/README.md), including file checksums. Files are copies of saved
  results, not new executions.

## Hardware demonstration

See the [hardware demonstration record](../hardware/HARDWARE_VALIDATION.md) and [video folder](../media/README.md).
