# Component: telemetry
# Purpose:    FPGA telemetry snapshotter (peak/frame/error readback).
idf_component_register(
    SRCS          "telemetry.c"
    INCLUDE_DIRS  "."
    REQUIRES      fpga_config
                   spi_master
                   freertos
                   esp_log
)
