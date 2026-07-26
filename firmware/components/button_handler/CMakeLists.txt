# Component: button_handler
# Purpose:    GPIO button debounce + long-press event generator.
idf_component_register(
    SRCS          "button_handler.c"
    INCLUDE_DIRS  "."
    PRIV_REQUIRES driver
    REQUIRES      freertos esp_log
)
