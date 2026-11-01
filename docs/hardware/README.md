# Hardware integration

Target hardware is an Arty S7-25 Rev. E with INMP441 microphone and PCM5102A DAC breakouts. The owner has confirmed
audio operation and recorded a hardware demonstration. The FPGA generates I²S clocks and performs all runtime processing
and controls.

- [Connection reference](WIRING.md)
- [Output load and headphone requirements](OUTPUT_LOAD.md)
- [Clock and external timing contract](TIMING_CONTRACT.md)
- [STATUS2 meaning](STATUS2.md)
- [Hardware demonstration record](HARDWARE_VALIDATION.md)
- [Component inventory](../../hardware/bom/README.md)

The actual breakout supplies, pin labels and output stage must be identified before acceptance. A connector does not
establish an amplifier. See the [recorded demonstration](HARDWARE_VALIDATION.md) for the current hardware status.
