# Component: bt_audio
# Purpose:    Bluetooth A2DP stub for Phase 3.
idf_component_register(
    SRCS          "bt_audio.c"
    INCLUDE_DIRS  "."
    REQUIRES      freertos esp_log
)
