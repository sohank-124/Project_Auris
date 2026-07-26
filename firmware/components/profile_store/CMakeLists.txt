# Component: profile_store
# Purpose:    NVS-backed persistent profile (mode, volume, gain, counters).
idf_component_register(
    SRCS          "profile_store.c"
    INCLUDE_DIRS  "."
    REQUIRES      nvs_flash
                   freertos
                   esp_log
                   mode_manager
)
