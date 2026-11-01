# Current architecture

This directory describes the current local FPGA-only implementation. RTL and constraints are the implementation
authority; saved evidence applies only to its recorded source identity.

- [System and module ownership](block_diagram.md)
- [DSP mathematics and numerical formats](dsp_pipeline.md)
- [Clocks, reset, and CDC](clock_domains.md)
- [Profiles, volume, and indicators](modes_and_gains.md)
- [Actual resource and timing results](resource_budget.md)
- [Verification status](../verification/VERIFICATION_STATUS.md)

Some source comments and unused package constants retain historical descriptions, including BFP_PIPE_DELAY=418 and
register addresses. The active pipeline uses an exponent FIFO, not that delay constant. Those comments are not evidence
of an active SPI interface, compressor, or arbitrary FFT-size support.
