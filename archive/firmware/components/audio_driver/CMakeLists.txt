# Component: audio_driver
# Purpose:    I2S master driver for the ESP32<->FPGA audio link.
idf_component_register(
    SRCS          "audio_driver.c"
    INCLUDE_DIRS  "."
    PRIV_REQUIRES driver esp_hw_support
    REQUIRES      freertos
)
