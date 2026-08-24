# Component: battery_mon
# Purpose:    ADC1 oneshot driver for the Li-Ion battery sense divider.
idf_component_register(
    SRCS          "battery_mon.c"
    INCLUDE_DIRS  "."
    PRIV_REQUIRES driver esp_adc
    REQUIRES      freertos esp_log
)
