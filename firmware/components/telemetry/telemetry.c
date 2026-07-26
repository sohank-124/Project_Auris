// =============================================================================
// File:        telemetry.c
// Project:     Project Auris
// Description: Reads FPGA telemetry registers via the SPI request-response
//              queue. Designed to be called from monitor_task. Each read
//              blocks up to 50 ms on the task notification (M2). If a read
//              fails, the function short-circuits the remaining reads
//              (circuit breaker) so a single 200-ms budget is never
//              exceeded even in a degraded SPI state.
// =============================================================================
#include "telemetry.h"
#include "fpga_config.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include <string.h>

static const char *TAG = "telemetry";

// IPC handle (set by auris_telem_init)
static QueueHandle_t s_spi_q = NULL;

// C5: result_ptr in the request struct must point at module-level
// storage. If the caller times out on ulTaskNotifyTake, it returns and
// the local `out` pointer (on its stack) becomes dangling; spi_task may
// later complete the read and write to freed memory. Using a static
// result keeps the storage valid for spi_task regardless of caller
// lifetime.
static uint32_t s_telem_result;

// Per-read SPI timeout. 50 ms is enough for the round trip at 10 MHz
// (3.2 us bus time) plus scheduler jitter, while keeping the worst-case
// four-read tick under 200 ms.
#define AURIS_TELEM_READ_TIMEOUT_MS  50

// ---------------------------------------------------------------------------
// auris_telem_init
// ---------------------------------------------------------------------------
esp_err_t auris_telem_init(QueueHandle_t spi_q)
{
    s_spi_q = spi_q;
    ESP_LOGI(TAG, "Telemetry initialized");
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// Internal: blocking read of a single register via the SPI queue.
// Returns the read value via *out only on success.
// ---------------------------------------------------------------------------
static esp_err_t auris_telem_read_blocking(uint8_t addr, uint32_t *out)
{
    if (!out)     return ESP_ERR_INVALID_ARG;
    if (!s_spi_q) return ESP_ERR_INVALID_STATE;
    s_telem_result = 0;
    auris_spi_request_t req = {
        .kind       = AURIS_SPI_REQ_READ,
        .addr       = addr,
        .data       = 0x7FFFFFu,
        .result_ptr = &s_telem_result,
        .caller     = xTaskGetCurrentTaskHandle(),
    };
    if (xQueueSend(s_spi_q, &req, pdMS_TO_TICKS(AURIS_TELEM_READ_TIMEOUT_MS)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    if (ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(AURIS_TELEM_READ_TIMEOUT_MS)) == 0) {
        return ESP_ERR_TIMEOUT;
    }
    *out = s_telem_result;
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// auris_telem_tick
//
// M2: reads are short-circuited on the first failure so that a degraded
// SPI bus cannot blow the monitor_task budget (formerly 4 * 200 ms =
// 800 ms worst case).
// ---------------------------------------------------------------------------
void auris_telem_tick(auris_telem_snapshot_t *snap)
{
    if (!snap) return;
    memset(snap, 0, sizeof(*snap));

    uint32_t fc_l = 0, fc_h = 0;
    if (auris_telem_read_blocking(REG_FRAME_COUNT_L, &fc_l) != ESP_OK) {
        return;  // circuit breaker: skip the rest of the snapshot
    }
    if (auris_telem_read_blocking(REG_FRAME_COUNT_H, &fc_h) != ESP_OK) {
        return;
    }
    snap->frame_count = ((fc_h & 0xFFFFu) << 16) | (fc_l & 0xFFFFu);

    if (auris_telem_read_blocking(REG_PEAK_LEVEL, &snap->peak_in) != ESP_OK) {
        return;
    }
    (void)auris_telem_read_blocking(REG_OUT_PEAK,   &snap->peak_out);
    (void)auris_telem_read_blocking(REG_ERROR_FLAGS,&snap->error_flags);
}
