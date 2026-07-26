# Component: volume_ctrl
# Purpose:    Volume state + REG_VOLUME orchestrator (runs in mode_task).
idf_component_register(
    SRCS          "volume_ctrl.c"
    INCLUDE_DIRS  "."
    REQUIRES      profile_store
                   fpga_config
                   spi_master
                   led_indicator
                   freertos
                   esp_log
)
