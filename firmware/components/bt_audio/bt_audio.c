// =============================================================================
// File:        bt_audio.c
// Project:     Project Auris
// Description: Phase-3 stub. The real A2DP source/sink will be added in a
//              later milestone along with the corresponding sdkconfig
//              (CONFIG_BT_ENABLED=y) and a separate OTA app partition.
// =============================================================================
#include "bt_audio.h"
#include "esp_log.h"

static const char *TAG = "bt_audio";
static bool s_initialized = false;

esp_err_t auris_bt_audio_init(void)
{
    if (s_initialized) return ESP_OK;
    ESP_LOGI(TAG, "Bluetooth A2DP stub: init (Phase 3 not implemented)");
    s_initialized = true;
    return ESP_OK;
}

esp_err_t auris_bt_audio_start(void)
{
    ESP_LOGI(TAG, "Bluetooth A2DP stub: start (no-op)");
    return ESP_OK;
}

esp_err_t auris_bt_audio_stop(void)
{
    ESP_LOGI(TAG, "Bluetooth A2DP stub: stop (no-op)");
    return ESP_OK;
}
