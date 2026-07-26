# =============================================================================
# File:        cmod_s7_25.xdc
# Project:     Project Auris - FPGA-Accelerated Assistive Audio
# Target:      Digilent Cmod S7-25 Rev B (XC7S25-1CSGA225C)
#
# Description: Pin assignments, I/O standards, and configuration.
#
#  Board resources (verified against the official Digilent XDC):
#    - Pmod JA connector   (Bank 34, 3.3 V)
#    - 12 MHz oscillator   (Bank 14, 3.3 V, pin M9)
#    - 4 LEDs              (Bank 34, 3.3 V)
#    - RGB LED             (Bank 34, 3.3 V, active-low)
#
#  Signal-to-pin mapping:
#    Pmod JA1-JA4 : SPI (SCLK, MOSI, MISO, CS_N)
#    Pmod JA7-JA10: I2S (BCLK, LRCLK, ADC_DATA, DAC_DATA)
#    Onboard LEDs : status LEDs
# =============================================================================

# ---------------------------------------------------------------------------
# 1. Onboard 12 MHz oscillator
#    Pin M9 in Bank 14, 3.3 V LVCMOS.  MRCC-capable (feeds MMCME2_BASE).
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN M9    IOSTANDARD LVCMOS33 } [get_ports clk_12mhz];

# ---------------------------------------------------------------------------
# 2. Pmod JA - SPI interface (JA1-JA4)
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN J2    IOSTANDARD LVCMOS33 } [get_ports spi_sclk_i];
set_property -dict { PACKAGE_PIN H2    IOSTANDARD LVCMOS33 } [get_ports spi_mosi_i];
set_property -dict { PACKAGE_PIN H4    IOSTANDARD LVCMOS33 } [get_ports spi_miso_o];
set_property -dict { PACKAGE_PIN F3    IOSTANDARD LVCMOS33 } [get_ports spi_cs_n_i];

# ---------------------------------------------------------------------------
# 3. Pmod JA - I2S interface (JA7-JA10)
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN H3    IOSTANDARD LVCMOS33 } [get_ports i2s_bclk_i];
set_property -dict { PACKAGE_PIN H1    IOSTANDARD LVCMOS33 } [get_ports i2s_lrclk_i];
set_property -dict { PACKAGE_PIN G1    IOSTANDARD LVCMOS33 } [get_ports i2s_adc_data_i];
set_property -dict { PACKAGE_PIN F4    IOSTANDARD LVCMOS33 } [get_ports i2s_dac_data_o];

# ---------------------------------------------------------------------------
# 4. Onboard single-colour LEDs (active-high)
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN E2    IOSTANDARD LVCMOS33 } [get_ports status_led_o];
set_property -dict { PACKAGE_PIN K1    IOSTANDARD LVCMOS33 } [get_ports status_clip_o];

# ---------------------------------------------------------------------------
# 5. Onboard RGB LED (active-low, Bank 34)
# ---------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN F2    IOSTANDARD LVCMOS33 } [get_ports led_rgb_r];
set_property -dict { PACKAGE_PIN D3    IOSTANDARD LVCMOS33 } [get_ports led_rgb_g];
set_property -dict { PACKAGE_PIN F1    IOSTANDARD LVCMOS33 } [get_ports led_rgb_b];

# ---------------------------------------------------------------------------
# 6. Externally-clocked domains: non-dedicated clock routing
#    spi_sclk_i and i2s_bclk_i are driven by the ESP32's SPI and I2S
#    peripherals on non-P-side clock-capable IO pins (CCIO N-type).
#
#    CLOCK_BUFFER_TYPE NONE prevents BUFG insertion during synthesis,
#    but Vivado's implementation link_design phase re-reads create_clock
#    and inserts a BUFG anyway.  CLOCK_DEDICATED_ROUTE FALSE waives
#    the PLIO-9 DRC (demotes ERROR to WARNING) by allowing the IBUF-to-BUFG
#    connection to use general routing instead of the dedicated clock
#    backbone that N-side CCIO pins lack.
#
#    Both domains are slow (<=10 MHz) and asynchronous to the DSP domain,
#    so non-dedicated routing introduces negligible skew relative to the
#    multi-hundred-nanosecond clock periods.
# ---------------------------------------------------------------------------
set_property CLOCK_BUFFER_TYPE NONE [get_ports spi_sclk_i];
set_property CLOCK_BUFFER_TYPE NONE [get_ports i2s_bclk_i];
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets spi_sclk_i_IBUF];
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets i2s_bclk_i_IBUF];

# ---------------------------------------------------------------------------
# 7. Pull-up / pull-down
# ---------------------------------------------------------------------------
set_property PULLUP   true [get_ports spi_cs_n_i];
set_property PULLDOWN true [get_ports i2s_adc_data_i];

# ---------------------------------------------------------------------------
# 8. Primary clocks
#    8a. Onboard 12 MHz oscillator -> clk_12mhz (feeds MMCM)
#    8b. I2S bit clock from ESP32  -> i2s_bclk_i (3.072 MHz)
#    8c. SPI clock from ESP32      -> spi_sclk_i (up to 10 MHz)
#
#    The MMCM in clk_gen.sv auto-derives a 96 MHz generated clock on its
#    CLKOUT0 pin.  Vivado reads CLKOUT0_DIVIDE_F=6.25 from the primitive
#    and creates the clock object automatically (confirmed by Timing 38-2
#    in the synthesis log).  No explicit create_generated_clock is needed;
#    the Tcl command rejects -divide_by 6.25 (non-integer) even though the
#    MMCM hardware parameter is legal.
# ---------------------------------------------------------------------------
create_clock -name clk_12mhz  -period 83.333  [get_ports clk_12mhz];
create_clock -name i2s_bclk_i -period 325.521 [get_ports i2s_bclk_i];
create_clock -name spi_sclk_i -period 100     [get_ports spi_sclk_i];

# ---------------------------------------------------------------------------
# 9. Asynchronous clock domains
#    Three clock domains are mutually asynchronous:
#      - clk_12mhz family  (board oscillator + MMCM-generated clk_fb +
#                           clk_out1_bufr / 96 MHz DSP clock)
#      - i2s_bclk_i        (ESP32 I2S master, independent PLL)
#      - spi_sclk_i        (ESP32 SPI master, independent PLL)
#
#    The -include_generated_clocks flag expands get_clocks to return not
#    only clk_12mhz but also every clock generated from it (clk_fb,
#    clk_out1_bufr).  Without this flag, get_clocks returns only the
#    named clock and the MMCM-generated 96 MHz clock is left ungrouped —
#    Vivado then times its paths to i2s_bclk_i and spi_sclk_i as if they
#    were synchronous, producing "Timed (unsafe)" in report_clock_interaction
#    and critical violations in report_cdc.
#
#    All inter-domain paths go through CDC modules:
#      I2S <-> DSP: async FIFOs with Gray-coded pointers + ASYNC_REG
#      SPI <-> DSP: 4-phase req/ack handshake + ASYNC_REG
#    No synchronous paths exist between domains.
# ---------------------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks clk_12mhz] \
    -group [get_clocks i2s_bclk_i] \
    -group [get_clocks spi_sclk_i]

# ---------------------------------------------------------------------------
# 10. I/O timing constraints (I2S interface)
#     BCLK = 3.072 MHz (64 * 48 kHz).  ESP32 drives BCLK, LRCLK, ADC_DATA.
#     +-10 ns covers PCB skew and INMP441 output delay.
#     The FPGA drives DAC_DATA on BCLK falling edge.
# ---------------------------------------------------------------------------
set_input_delay  -clock [get_clocks i2s_bclk_i] -max  10.0 [get_ports i2s_lrclk_i];
set_input_delay  -clock [get_clocks i2s_bclk_i] -min -10.0 [get_ports i2s_lrclk_i];
set_input_delay  -clock [get_clocks i2s_bclk_i] -max  10.0 [get_ports i2s_adc_data_i];
set_input_delay  -clock [get_clocks i2s_bclk_i] -min -10.0 [get_ports i2s_adc_data_i];
set_output_delay -clock [get_clocks i2s_bclk_i] -max  10.0 [get_ports i2s_dac_data_o];
set_output_delay -clock [get_clocks i2s_bclk_i] -min -10.0 [get_ports i2s_dac_data_o];
# SPI MISO: ESP32 samples MISO on SCLK rising edge (CPOL=0, CPHA=0).
# +-5 ns covers PCB trace skew and the ESP32's input setup/hold window
# at SCLK <= 10 MHz (period 100 ns).  The FPGA drives MISO from the
# spi_sclk_i domain, so these constraints let Vivado verify setup/hold
# on the MISO output path.
set_output_delay -clock [get_clocks spi_sclk_i] -max  5.0  [get_ports spi_miso_o];
set_output_delay -clock [get_clocks spi_sclk_i] -min -5.0  [get_ports spi_miso_o];

# ---------------------------------------------------------------------------
# 11. Output drive strength and slew rate (output ports only)
# ---------------------------------------------------------------------------
set_property DRIVE   8  [get_ports {spi_miso_o}];
set_property SLEW    FAST [get_ports {spi_miso_o}];
set_property DRIVE   8  [get_ports {i2s_dac_data_o}];
set_property SLEW    FAST [get_ports {i2s_dac_data_o}];

# ---------------------------------------------------------------------------
# 12. Async output paths (LEDs - human-eye timing)
# ---------------------------------------------------------------------------
set_false_path -to [get_ports {status_led_o status_clip_o led_rgb_r led_rgb_g led_rgb_b}];

# ---------------------------------------------------------------------------
# 13. Bitstream configuration
# ---------------------------------------------------------------------------
set_property CONFIG_VOLTAGE            3.3   [current_design];
set_property CFGBVS                   VCCO  [current_design];
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design];
set_property CONFIG_MODE             SPIx4 [current_design];
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design];