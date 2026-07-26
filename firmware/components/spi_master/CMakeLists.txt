# Component: spi_master
# Purpose:    Low-level SPI master driver for the FPGA register bus.
idf_component_register(
    SRCS          "spi_master.c"
    INCLUDE_DIRS  "."
    PRIV_REQUIRES driver esp_hw_support
    REQUIRES      freertos
)
