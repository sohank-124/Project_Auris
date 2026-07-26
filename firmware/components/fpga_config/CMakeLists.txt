# Component: fpga_config
# Purpose:    High-level typed wrappers around the SPI master for FPGA regs.
idf_component_register(
    SRCS          "fpga_config.c"
    INCLUDE_DIRS  "."
    REQUIRES      spi_master
)
