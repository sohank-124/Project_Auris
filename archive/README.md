# Archived Components

This directory contains components and subsystems that were removed during the FPGA-only migration (2026-08).

## Contents

- `firmware/` — ESP32 firmware (ESP-IDF). Removed because the FPGA now handles all control, mode switching, and volume management internally via onboard pushbuttons. The ESP32 is no longer part of the hardware.
- `rtl/` — SPI-era RTL retired in the FPGA-only migration: `spi_slave.sv`, `cdc_spi_to_dsp.sv`, `cdc_dsp_to_spi.sv`, and the SPI-mapped `reg_file.sv`.
- `tb/` — testbenches for the retired RTL: `tb_spi_slave.sv`, `tb_reg_file.sv`.
- `scripts/` — xsim driver scripts for the retired testbenches: `sim_spi_slave.tcl`, `sim_reg_file.tcl`.

## Why Archived Instead of Deleted?

These files are preserved for reference and potential future use. They document the original ESP32 co-processor architecture and may be useful for:
- Understanding design decisions that influenced the FPGA-only implementation
- Reverting to a host-controlled architecture if needed
- Educational reference (this is a portfolio project)

## Migration Context

The FPGA-only migration moved all control-plane functionality into the FPGA:
- Mode switching: 4 pushbuttons → FPGA internal FSM
- Volume control: pushbuttons → FPGA internal counter
- Gain tables: SPI upload from ESP32 → pre-computed in FPGA ROM
- I2S master: ESP32 → FPGA (via MMCM + fractional divider)
- LED control: SPI register writes → direct mode decode

The SPI interface, CDC handshakes, and register file that mediated ESP32↔FPGA communication have been removed from the RTL.
