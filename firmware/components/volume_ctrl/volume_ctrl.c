// =============================================================================
// File:        volume_ctrl.c
// Project:     Project Auris
// Description: Volume state, clamped to [0, 31]. On change:
//                1. Update internal state.
//                2. Post REG_VOLUME write to g_spi_q (blocking).
//                3. Post LED_CMD_BLINK_N with the new level for user
//                   feedback (N = level/4).
//                4. Post a PROF_SAVE_VOLUME request for debounced NVS write.
// =============================================================================
#include "volume_ctrl.h"
#include "profile_store.h"
#include "fpga_config.h"
#include "app_state.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"

static const char *TAG = "volume_ctrl";

static volatile uint8_t s_volume = AURIS_VOLUME_DEFAULT;

// IPC handles (set by auris_vol_init)
static QueueHandle_t s_spi_q     = NULL;
static QueueHandle_t s_led_q     = NULL;
static QueueHandle_t s_profile_q = NULL;

// ---------------------------------------------------------------------------
// Synchronous SPI write helper
// ---------------------------------------------------------------------------
static esp_err_t auris_vol_spi_write_blocking(uint8_t addr, uint32_t data)
{
    if (!s_spi_q) return ESP_ERR_INVALID_STATE;
    auris_spi_request_t req = {
        .kind   = AURIS_SPI_REQ_WRITE,
        .addr   = addr,
        .data   = data,
        .caller = xTaskGetCurrentTaskHandle(),
    };
    if (xQueueSend(s_spi_q, &req, pdMS_TO_TICKS(200)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    if (ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(200)) == 0) {
        return ESP_ERR_TIMEOUT;
    }
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// auris_vol_init
// ---------------------------------------------------------------------------
esp_err_t auris_vol_init(QueueHandle_t spi_q,
                         QueueHandle_t led_q,
                         QueueHandle_t profile_q)
{
    s_spi_q     = spi_q;
    s_led_q     = led_q;
    s_profile_q = profile_q;

    uint8_t saved = AURIS_VOLUME_DEFAULT;
    (void)auris_profile_get_volume(&saved);
    if (saved > AURIS_VOLUME_MAX) saved = AURIS_VOLUME_MAX;
    s_volume = saved;
    ESP_LOGI(TAG, "Volume initialized: %d", s_volume);
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// auris_vol_get / auris_vol_set
// ---------------------------------------------------------------------------
uint8_t auris_vol_get(void) { return s_volume; }

void auris_vol_set(uint8_t v)
{
    if (v > AURIS_VOLUME_MAX) v = AURIS_VOLUME_MAX;
    if (v == s_volume) return;
    uint8_t prev = s_volume;
    s_volume = v;

    ESP_LOGI(TAG, "Volume: %d -> %d", prev, v);
    if (g_event_group) {
        xEventGroupSetBits(g_event_group, AURIS_EVT_VOLUME_CHANGED);
    }

    (void)auris_vol_spi_write_blocking(REG_VOLUME, v);

    auris_led_command_t lc = {
        .kind  = AURIS_LED_CMD_BLINK_N,
        .count = (uint8_t)(v / 4 > 0 ? v / 4 : 0),
    };
    if (s_led_q) (void)xQueueOverwrite(s_led_q, &lc);

    auris_profile_save_request_t save = {
        .kind = AURIS_PROF_SAVE_VOLUME,
        .u8   = v,
    };
    if (s_profile_q) (void)xQueueSend(s_profile_q, &save, 0);
}

// ---------------------------------------------------------------------------
// auris_vol_step
// ---------------------------------------------------------------------------
uint8_t auris_vol_step(int delta)
{
    int v = (int)s_volume + delta;
    if (v < AURIS_VOLUME_MIN) v = AURIS_VOLUME_MIN;
    if (v > AURIS_VOLUME_MAX) v = AURIS_VOLUME_MAX;
    auris_vol_set((uint8_t)v);
    return (uint8_t)v;
}
