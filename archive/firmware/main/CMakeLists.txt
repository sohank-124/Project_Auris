# Component: main
# Purpose:    ESP-IDF entry point, FreeRTOS task scheduler, IPC, state machine.
idf_component_register(
    SRCS          "main.c"
    INCLUDE_DIRS  "."
    REQUIRES      freertos
                   nvs_flash
                   esp_system
                   esp_event
                   esp_log
                   esp_task_wdt
                   driver
                   button_handler
                   mode_manager
                   spi_master
                   fpga_config
                   audio_driver
                   led_indicator
                   volume_ctrl
                   profile_store
                   battery_mon
                   telemetry
                   bt_audio
)
