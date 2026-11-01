# Connection reference

This is the intended interface map from the current [board constraints](../../fpga/constraints/arty_s7_25.xdc), not a
record of completed assembly. Confirm header orientation and actual breakout documentation. Use [the validation
record](HARDWARE_VALIDATION.md) to capture what was connected and observed.

| FPGA signal | Package pin | JA signal index | Physical JA hole | External destination/source |
| --- | --- | --- | --- | --- |
| i2s_bclk_o | M16 | JA[4] | 7 | Microphone SCK and DAC BCK |
| i2s_lrclk_o | M17 | JA[5] | 8 | Microphone WS and DAC LRCK |
| i2s_adc_data_i | M18 | JA[6] | 9 | Microphone SD to FPGA |
| i2s_dac_data_o | N18 | JA[7] | 10 | FPGA to DAC DIN |
| Ground | Board GND | GND | 5 or 11 | Shared signal reference |
| 3.3 V rail | Board supply | 3V3 | 6 or 12 | Only devices/inputs specified for this supply |

JA[4] means a logical signal index, not physical hole 4. Do not confuse these numbering systems. The microphone must
select the left slot because the DSP processes left input only. Identify and record its L/R strap.

I²S uses 3.3 V FPGA signaling, 24-bit payloads, and 32-bit left/right slots. The FPGA is the master. The PCM5102A setup
must match standard I²S and its breakout's clock configuration; FMT, SCK and XSMT strap labels must be checked against
the actual module rather than assumed from photographs of another board.

Breakout supply inputs differ: some expose regulated supply pins, others expect VIN feeding an onboard regulator. The
actual microphone/DAC module and supply requirements remain to be recorded. Do not apply a generic 5 V or 3.3 V
instruction to an unidentified breakout.

The DAC outputs are separate single-ended line outputs referenced to ground. Use a supported line input/measurement
load. Headphones require an identified compatible amplifier; see [OUTPUT_LOAD](OUTPUT_LOAD.md). No amplifier is selected
by this documentation change.

Onboard buttons BTN0..3 use G15/K16/J16/H13; RGB uses J15/G17/F15. Current RTL uses active-high drive. STATUS0 is E18
and STATUS2 E13. Runtime controls are described once in [profiles and indicators](../architecture/modes_and_gains.md).

Receiver timing, flight/skew/load assumptions and fractional-clock acceptance are covered by
[TIMING_CONTRACT](TIMING_CONTRACT.md). Physical measurements remain separate from the saved FPGA timing report.
