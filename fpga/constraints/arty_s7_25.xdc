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
#    - RGB LED 0           (Bank 15, 3.3 V, active-high) — mode indicator
#    - 4 pushbuttons       (Bank 15, 3.3 V, active-high) — user input
#
#  Signal-to-pin mapping:
#    Pmod JA[4..7] : I2S (BCLK, LRCLK, ADC_DATA, DAC_DATA) — FPGA drives
#                    BCLK + LRCLK, INMP441 drives ADC_DATA, FPGA drives
#                    DAC_DATA.
#    Onboard LEDs  : LED[0]=E18 status heartbeat, LED[2]=E13 clip event
#    Onboard RGB0  : J15/G17/F15 mode indicator (active-high RGB)
#    Onboard BTNs  : G15/K16/J16/H13 user input (active-high, debounced)
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
# 4. Onboard RGB LED 0 (active-high, Bank 15)
#    Mode-dependent colour: General=green, Speech=blue, Music=magenta,
#    Hearing=red. Self-test uses yellow/cyan/red status overlays.
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports led_rgb_r];       # RGB0-R
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports led_rgb_g];       # RGB0-G
set_property -dict { PACKAGE_PIN F15   IOSTANDARD LVCMOS33 } [get_ports led_rgb_b];       # RGB0-B

# ---------------------------------------------------------------------------
# 5. Onboard pushbuttons (active-high, Bank 15)
#    BTN0..BTN3 map to btn_i[0..3].  These are debounced in the FPGA by
#    btn_debounce.sv before being used as control inputs.
#
#    Corrected pin audit: the previous C12/C11/F13/E13 assignments were
#    invalid (C12/C11 are not package pins on CSGA324, and F13/E13 are
#    LED[1]/LED[2]).  Official Digilent Arty S7-25 Rev. E master XDC:
#      btn[0]=G15, btn[1]=K16, btn[2]=J16, btn[3]=H13.
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN G15   IOSTANDARD LVCMOS33 } [get_ports {btn_i[0]}];      # BTN0 - active-high
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports {btn_i[1]}];      # BTN1 - active-high
set_property -dict { PACKAGE_PIN J16   IOSTANDARD LVCMOS33 } [get_ports {btn_i[2]}];      # BTN2 - active-high
set_property -dict { PACKAGE_PIN H13   IOSTANDARD LVCMOS33 } [get_ports {btn_i[3]}];      # BTN3 - active-high

# ---------------------------------------------------------------------------
# 6. Pull-up / pull-down
#    * i2s_adc_data_i: pulldown holds the line at a defined logic level
#      while the INMP441 is power-ramping or held in reset, preventing
#      spurious transitions into the I2S receiver.
#    * Buttons have external pull-downs on the Arty S7-25 PCB, so no
#      internal pull-down is required.
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
#        Four BCLK cycles per 125 DSP cycles. The average waveform below
#        is bounded by explicit uncertainty for the 15/16-cycle halves.
#        Derivation and external assumptions: docs/hardware/TIMING_CONTRACT.md.
# ---------------------------------------------------------------------------
create_clock -name clk_12mhz  -period 83.333  [get_ports clk_12mhz];

create_generated_clock -name i2s_bclk \
    -source [get_pins u_clk_gen/u_mmcm/CLKOUT0] \
    -multiply_by 4 -divide_by 125 \
    [get_pins u_clk_gen/bufg_bclk/O];

# Refer external timing to the FPGA clock output, including its routed delay.
create_generated_clock -name i2s_bclk_forwarded \
    -source [get_pins u_clk_gen/bufg_bclk/O] -divide_by 1 \
    [get_ports i2s_bclk_o];

# Fractional phase error spans 0.875 DSP cycles; one cycle bounds it.
# Setup checks compare different edges. Same-edge internal hold checks do
# not incur fractional jitter: their common edge displacement cancels.
set_clock_uncertainty -setup 10.417 [get_clocks {i2s_bclk i2s_bclk_forwarded}];
set_clock_uncertainty -hold -rise_from [get_clocks i2s_bclk] -fall_to [get_clocks i2s_bclk] 10.417;
set_clock_uncertainty -hold -fall_from [get_clocks i2s_bclk] -rise_to [get_clocks i2s_bclk] 10.417;
set_clock_uncertainty -hold -from [get_clocks i2s_bclk] -to [get_clocks i2s_bclk_forwarded] 10.417;
set_clock_uncertainty -hold -from [get_clocks i2s_bclk_forwarded] -to [get_clocks i2s_bclk] 10.417;

# ---------------------------------------------------------------------------
# 8. FIFO crossing constraints are in cdc_fifo.xdc.
# Keep this file free of Tcl control flow: Vivado's XDC reader supports only
# its constraint command subset. Do not add blanket clock-group exceptions
# that override the FIFO datapath bounds.
# ---------------------------------------------------------------------------
# 9. I/O timing constraints (I2S interface)
#    The FPGA now drives BCLK and LRCLK; the INMP441 and PCM5102A latch
#    on those forwarded clocks.  All I/O delays are expressed relative
#    to the forwarded clock at the FPGA package pin.
#
#    ASSUMPTIONS to verify on hardware: each external wire flight is 0..2 ns;
#    microphone falling-edge-to-valid is 0..100 ns (not a datasheet limit).
#    Input max = 2 clock flight + 100 microphone + 2 return flight = 104 ns.
#    PCM5102A DIN setup/hold = 8/8 ns; +/-2 ns external differential skew.
#    LRCLK drives both devices: max setup 8 ns; max hold 20 ns (INMP441).
#    Output max = setup + skew; output min = -hold - skew.
#    Board acceptance is conditional on TIMING_CONTRACT.md, not implied by STA.
# ---------------------------------------------------------------------------
set_input_delay  -clock [get_clocks i2s_bclk_forwarded] -clock_fall -max 104.0 [get_ports i2s_adc_data_i];
set_input_delay  -clock [get_clocks i2s_bclk_forwarded] -clock_fall -min   0.0 [get_ports i2s_adc_data_i];
set_output_delay -clock [get_clocks i2s_bclk_forwarded] -max  10.0 [get_ports i2s_dac_data_o];
set_output_delay -clock [get_clocks i2s_bclk_forwarded] -min -10.0 [get_ports i2s_dac_data_o];
set_output_delay -clock [get_clocks i2s_bclk_forwarded] -max  10.0 [get_ports i2s_lrclk_o];
set_output_delay -clock [get_clocks i2s_bclk_forwarded] -min -22.0 [get_ports i2s_lrclk_o];

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
#     * btn_i[*]: pushbutton inputs are debounced in btn_debounce.sv before
#       use, so the input-FF to debounce-FF path is asynchronous to any clock
#       domain and is not subject to setup/hold constraints.  The external
#       pull-downs on the Arty S7-25 PCB ensure clean logic levels.
# ---------------------------------------------------------------------------
set_false_path -to   [get_ports {status_led_o status_clip_o led_rgb_r led_rgb_g led_rgb_b}];
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
