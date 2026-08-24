# Component: mode_manager
# Purpose:    Operating-mode state machine + FPGA reg-write orchestration.
idf_component_register(
    SRCS          "mode_manager.c"
    INCLUDE_DIRS  "."
    REQUIRES      fpga_config
                   volume_ctrl
                   profile_store
                   spi_master
                   led_indicator
                   freertos
                   esp_log
)
