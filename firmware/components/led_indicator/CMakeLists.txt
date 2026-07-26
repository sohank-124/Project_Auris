# Component: led_indicator
# Purpose:    Two-LED pattern engine (green heartbeat, red clip/error).
idf_component_register(
    SRCS          "led_indicator.c"
    INCLUDE_DIRS  "."
    PRIV_REQUIRES driver
    REQUIRES      freertos esp_log
)
