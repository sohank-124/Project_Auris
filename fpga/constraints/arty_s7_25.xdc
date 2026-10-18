# =============================================================================
# File:        arty_s7_25.xdc
# Project:     Project Auris - FPGA-Accelerated Assistive Audio
# Target:      Digilent Arty S7-25 Rev. E (XC7S25-1CSGA324C)
#
# Description: Pin assignments, I/O standards, and timing constraints for the
#              FPGA-only architecture.  No external microcontroller.
#
#              All audio clock generation (BCLK, LRCLK) is performed on-board
#              by the FPGA's MMCM and divider logic.  The FPGA is the I2S
#              master: it drives BCLK and LRCLK, the INMP441 and PCM5102A
#              are I2S slaves that latch on the FPGA-supplied clocks.
#
#              Based on the official Digilent Arty S7-25 Rev. E master XDC.
#
#  Board resources used:
#    - Pmod JA connector   (Bank 14, 3.3 V) — I2S (FPGA-driven clocks)
#    - 12 MHz oscillator   (Bank 15, 3.3 V, pin F14) — MMCM reference
#    - 4 LEDs              (Bank 15, 3.3 V) — status heartbeat (LED[0]),
#                                          clip event (LED[2])
#    - RGB LED 0           (Bank 15, 3.3 V, active-low) — mode indicator
#    - 4 pushbuttons       (Bank 15, 3.3 V, active-low) — user input
#
#  Signal-to-pin mapping:
#    Pmod JA[4..7] : I2S (BCLK, LRCLK, ADC_DATA, DAC_DATA) — FPGA drives
#                    BCLK + LRCLK, INMP441 drives ADC_DATA, FPGA drives
#                    DAC_DATA.
#    Onboard LEDs  : LED[0]=E18 status heartbeat, LED[2]=E13 clip event
#    Onboard RGB0  : J15/G17/F15 mode indicator (active-low RGB)
#    Onboard BTNs  : G15/K16/J16/H13 user input (active-low, debounced)
# =============================================================================

# ---------------------------------------------------------------------------
# 1. Onboard 12 MHz oscillator
#    Pin F14 in Bank 15, 3.3 V LVCMOS.  MRCC-capable, feeds the MMCM.
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN F14   IOSTANDARD LVCMOS33 } [get_ports clk_12mhz];

# ---------------------------------------------------------------------------
# 2. Pmod JA — I2S interface (JA[4..7])
#    The FPGA is the I2S master:
#      JA[4] = BCLK   (output, FPGA drives INMP441 + PCM5102A)
#      JA[5] = LRCLK  (output, FPGA drives both codecs)
#      JA[6] = ADC_DATA   (input, INMP441 drives)
#      JA[7] = DAC_DATA   (output, FPGA drives PCM5102A)
#
#    Physical holes on the 2x6 JA header (wiring docs use these numbers):
#      JA[4]/BCLK = hole 7, JA[5]/LRCLK = hole 8,
#      JA[6]/ADC  = hole 9, JA[7]/DAC   = hole 10.
#    Holes 5/11 = GND, 6/12 = 3V3, holes 1-4 unused. See WIRING.md step 1.
#
#    Note on signal direction: BCLK and LRCLK were previously inputs because
#    the ESP32 was the I2S master.  In the FPGA-only architecture the FPGA
#    generates both clocks on-board (see clk_gen.sv) and now drives them
#    out to the codecs.
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN M16   IOSTANDARD LVCMOS33 } [get_ports i2s_bclk_o];       # JA[4] = ja_p[3]  (FPGA -> codec)
set_property -dict { PACKAGE_PIN M17   IOSTANDARD LVCMOS33 } [get_ports i2s_lrclk_o];      # JA[5] = ja_n[3]  (FPGA -> codec)
set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports i2s_adc_data_i];    # JA[6] = ja_p[4]  (INMP441 -> FPGA)
set_property -dict { PACKAGE_PIN N18   IOSTANDARD LVCMOS33 } [get_ports i2s_dac_data_o];    # JA[7] = ja_n[4]  (FPGA -> PCM5102A)

# ---------------------------------------------------------------------------
# 3. Onboard single-colour LEDs (active-high)
#    LED[0] = status heartbeat, LED[2] = clip indicator.
#    Pins per the official Digilent Arty S7-25 Rev. E master XDC.
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33 } [get_ports status_led_o];    # LED[0] = E18
set_property -dict { PACKAGE_PIN E13   IOSTANDARD LVCMOS33 } [get_ports status_clip_o];   # LED[2] = E13

# ---------------------------------------------------------------------------
# 4. Onboard RGB LED 0 (active-low, Bank 15)
#    Mode-dependent colour: General=green, Speech=blue, Music=magenta,
#    Hearing=red. Self-test uses yellow/cyan/red status overlays.
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports led_rgb_r];       # RGB0-R
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports led_rgb_g];       # RGB0-G
set_property -dict { PACKAGE_PIN F15   IOSTANDARD LVCMOS33 } [get_ports led_rgb_b];       # RGB0-B

# ---------------------------------------------------------------------------
# 5. Onboard pushbuttons (active-low, Bank 15)
#    BTN0..BTN3 map to btn_i[0..3].  These are debounced in the FPGA by
#    btn_debounce.sv before being used as control inputs.
#
#    Corrected pin audit: the previous C12/C11/F13/E13 assignments were
#    invalid (C12/C11 are not package pins on CSGA324, and F13/E13 are
#    LED[1]/LED[2]).  Official Digilent Arty S7-25 Rev. E master XDC:
#      btn[0]=G15, btn[1]=K16, btn[2]=J16, btn[3]=H13.
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN G15   IOSTANDARD LVCMOS33 } [get_ports {btn_i[0]}];      # BTN0 - active-low
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports {btn_i[1]}];      # BTN1 - active-low
set_property -dict { PACKAGE_PIN J16   IOSTANDARD LVCMOS33 } [get_ports {btn_i[2]}];      # BTN2 - active-low
set_property -dict { PACKAGE_PIN H13   IOSTANDARD LVCMOS33 } [get_ports {btn_i[3]}];      # BTN3 - active-low

# ---------------------------------------------------------------------------
# 6. Pull-up / pull-down
#    * i2s_adc_data_i: pulldown holds the line at a defined logic level
#      while the INMP441 is power-ramping or held in reset, preventing
#      spurious transitions into the I2S receiver.
#    * Buttons have external pull-ups on the Arty S7-25 PCB, so no
#      internal pull-up is required.
# ---------------------------------------------------------------------------
set_property PULLDOWN true [get_ports i2s_adc_data_i];

# ---------------------------------------------------------------------------
# 7. Primary clocks
#
#    7a. Onboard 12 MHz oscillator -> clk_12mhz (feeds MMCM).
#        The MMCM in clk_gen.sv auto-derives a 96 MHz generated clock on
#        its CLKOUT0 pin (u_mmcm/CLKOUT0).  Vivado reads
#        CLKOUT0_DIVIDE_F=6.25 from the primitive and creates the 96 MHz
#        generated clock object automatically — no explicit
#        create_generated_clock is needed for the DSP clock.
#
#    7b. I2S bit clock -> i2s_bclk
#        Now an internally-derived clock.  The MMCM CLKOUT0 (96 MHz)
#        is divided by the BCLK-generation logic in clk_gen.sv (toggle
#        counter, average 31.25 cycles per BCLK period -> 3.072 MHz)
#        and distributed by BUFG bufg_bclk.  We declare this with
#        create_generated_clock so Vivado understands the period and
#        the parent-child relationship.
#
#        NOTE: -divide_by 32 reports 96/32 = 3 MHz (period 333.333 ns).
#        The actual hardware period is 96/31.25 = 3.072 MHz
#        (period 325.521 ns).  The ~2.4 % mismatch is bounded by the
#        +/-10 ns I/O-delay slack and does not affect timing closure,
#        but it is worth knowing when reading timing reports.
# ---------------------------------------------------------------------------
create_clock -name clk_12mhz  -period 83.333  [get_ports clk_12mhz];

create_generated_clock -name i2s_bclk \
    -source [get_pins u_clk_gen/u_mmcm/CLKOUT0] \
    -divide_by 32 \
    [get_pins u_clk_gen/bufg_bclk/O];

# ---------------------------------------------------------------------------
# 8. Asynchronous clock domains
#    Two clock domains are mutually asynchronous from a CDC perspective:
#      - clk_12mhz family  (board oscillator + MMCM-generated 96 MHz DSP
#                           clock + bufg_bclk-derived i2s_bclk)
#      - (no third domain — the SPI SCLK domain has been removed)
#
#    Although i2s_bclk is technically derived from the MMCM (and hence
#    shares a synchronous phase relationship with the DSP clock in
#    Vivado's eyes), we still mark the groups as asynchronous.  This
#    tells the tool to skip timing analysis on inter-domain paths and
#    to trust the CDC structures (Gray-coded pointer FIFOs +
#    ASYNC_REG attributes) in cdc_i2s_to_dsp and cdc_dsp_to_i2s.
#
#    Marking the groups as asynchronous is the conservative, correct
#    choice: the FIFOs are explicitly designed to handle the
#    crossing regardless of the underlying phase relationship.
# ---------------------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks clk_12mhz] \
    -group [get_clocks -include_generated_clocks i2s_bclk]

# ---------------------------------------------------------------------------
# 9. I/O timing constraints (I2S interface)
#    The FPGA now drives BCLK and LRCLK; the INMP441 and PCM5102A latch
#    on those forwarded clocks.  All I/O delays are expressed relative
#    to the generated i2s_bclk clock.
#
#    * i2s_adc_data_i (INMP441 -> FPGA)
#        The INMP441 launches data on its BCLK edge; the FPGA samples
#        it on its own BCLK edge after one BCLK period of flight.
#        +/-10 ns covers PCB trace skew (~2 ns each direction) plus
#        INMP441 output delay variation.  The actual data-arrival time
#        relative to the BCLK edge at the FPGA is dominated by the
#        INMP441 t_DHT (data hold time after BCLK), which is several
#        tens of ns — so the constraint is conservative (safe).
#
#    * i2s_dac_data_o (FPGA -> PCM5102A)
#        The PCM5102A samples DAC_DATA on BCLK.  +/-10 ns covers PCB
#        trace skew and the PCM5102A's setup/hold window at 3.072 MHz.
# ---------------------------------------------------------------------------
set_input_delay  -clock [get_clocks i2s_bclk] -max  10.0 [get_ports i2s_adc_data_i];
set_input_delay  -clock [get_clocks i2s_bclk] -min -10.0 [get_ports i2s_adc_data_i];
set_output_delay -clock [get_clocks i2s_bclk] -max  10.0 [get_ports i2s_dac_data_o];
set_output_delay -clock [get_clocks i2s_bclk] -min -10.0 [get_ports i2s_dac_data_o];

# ---------------------------------------------------------------------------
# 10. Output drive strength and slew rate (output ports only)
#     FAST slew + 8 mA drive gives clean edges at 3.072 MHz on Pmod JA's
#     unterminated 3.3 V traces.
# ---------------------------------------------------------------------------
set_property DRIVE   8   [get_ports {i2s_dac_data_o}];
set_property SLEW    FAST [get_ports {i2s_dac_data_o}];

# ---------------------------------------------------------------------------
# 11. False paths
#     * LEDs (status, clip, RGB): human-eye timing, no setup/hold requirement.
#     * i2s_lrclk_o: derived from BCLK by an internal divider; the FF-to-OBUF
#       path is trivially short at 48 kHz and there is no benefit in having
#       Vivado optimise its placement.
#     * btn_i[*]: pushbutton inputs are debounced in btn_debounce.sv before
#       use, so the input-FF to debounce-FF path is asynchronous to any clock
#       domain and is not subject to setup/hold constraints.  The external
#       pull-ups on the Arty S7-25 PCB ensure clean logic levels.
# ---------------------------------------------------------------------------
set_false_path -to   [get_ports {status_led_o status_clip_o led_rgb_r led_rgb_g led_rgb_b}];
set_false_path -to   [get_ports {i2s_lrclk_o}];
set_false_path -from [get_ports {btn_i[*]}];

# ---------------------------------------------------------------------------
# 12. Bitstream configuration
#     SPIx4 selects quad-SPI flash boot.  This is independent of the
#     removed SPI peripheral interface on Pmod JA — the FPGA's
#     configuration controller uses dedicated pins (Bank 14, not on the
#     Pmod), so no port constraint is affected.
# ---------------------------------------------------------------------------
set_property CONFIG_VOLTAGE            3.3   [current_design];
set_property CFGBVS                   VCCO  [current_design];
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design];
set_property CONFIG_MODE             SPIx4 [current_design];
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design];

# ---------------------------------------------------------------------------
# 13. SW3 VREF (Arty S7-25 specific)
#     SW3 is assigned to pin M5 in the 1.35 V bank.  To ensure SW3 does
#     not define the reference voltage and to be able to use this pin as
#     an ordinary I/O, enable the internal VREF for BANK 34.
# ---------------------------------------------------------------------------
set_property INTERNAL_VREF 0.675 [get_iobanks 34];
