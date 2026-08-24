// =============================================================================
// File:        mode_manager.c
// Project:     Project Auris
// Description: Mode state machine. Maintains the current mode (mutex
//              protected), exposes a getter, and orchestrates the FPGA
//              reg writes + LED feedback + NVS save when a mode change
//              is applied.
//
//              auris_mode_apply_current() must be called from mode_task.
//              It posts one spi_request_t per register write to g_spi_q
//              and blocks on task notifications. This is the canonical
//              request-response pattern; the SPI bus is owned by spi_task.
//
//              auris_mode_apply_current_direct() is the pre-task variant
//              used by app_main during boot, before spi_task exists.
//              It uses the raw auris_spi_read / auris_spi_write API
//              directly and is NOT safe to call once FreeRTOS tasks are
//              running.
// =============================================================================
#include "mode_manager.h"
#include "fpga_config.h"
#include "volume_ctrl.h"
#include "profile_store.h"
#include "app_state.h"
#include "spi_master.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/event_groups.h"
#include <string.h>

static const char *TAG = "mode_manager";

static volatile auris_mode_t s_current = AURIS_MODE_GENERAL;
static SemaphoreHandle_t     s_mutex   = NULL;

// IPC handles (set by auris_mode_init)
static QueueHandle_t s_spi_q      = NULL;
static QueueHandle_t s_led_q      = NULL;
static QueueHandle_t s_profile_q  = NULL;

// Per-mode register table. Index = mode id.
typedef struct {
    uint16_t drc_threshold;
    uint8_t  drc_ratio;
    uint8_t  noise_floor;
} mode_regs_t;

static const mode_regs_t k_mode_table[AURIS_MODE_COUNT] = {
    [AURIS_MODE_GENERAL] = { .drc_threshold = 0x400, .drc_ratio = 4, .noise_floor = 0x20 },
    [AURIS_MODE_HEARING] = { .drc_threshold = 0x200, .drc_ratio = 8, .noise_floor = 0x40 },
    [AURIS_MODE_SPEECH]  = { .drc_threshold = 0x300, .drc_ratio = 6, .noise_floor = 0x30 },
    [AURIS_MODE_BYPASS]  = { .drc_threshold = 0xFFF, .drc_ratio = 1, .noise_floor = 0x00 },
};

// Default gain table for the General mode (flat 0 dB, i.e. unity gain).
// Q2.14 with 16384 = 1.0×. Matches the FPGA's default gain-table initial
// value (UNITY_GAIN_Q14 in fpga/rtl/pkg/auris_pkg.sv) so a fresh unit
// never boots into silence.
static const int16_t s_table_default_q14[128] = {
    [0 ... 127] = 16384
};

// ---------------------------------------------------------------------------
// Queue-based SPI helpers (used from mode_task only).
//
// C3: all SPI traffic from mode_task must go through the g_spi_q queue so
// that spi_task is the sole owner of the bus. Direct auris_spi_read /
// auris_spi_write calls from mode_task would race with spi_task and any
// other producer (telemetry, etc.).
//
// C5: the result pointer for READ transactions must point at module-level
// storage (s_mode_read_result) so that if the caller times out on
// ulTaskNotifyTake, the spi_task cannot later write to a dangling stack
// pointer.
// ---------------------------------------------------------------------------
static uint32_t s_mode_read_result;
static esp_err_t auris_mode_spi_read_via_queue(uint8_t addr, uint32_t *out)
{
    if (!s_spi_q || !out) return ESP_ERR_INVALID_STATE;
    s_mode_read_result = 0;
    auris_spi_request_t req = {
        .kind       = AURIS_SPI_REQ_READ,
        .addr       = addr,
        .data       = 0x7FFFFFu,
        .result_ptr = &s_mode_read_result,
        .caller     = xTaskGetCurrentTaskHandle(),
    };
    if (xQueueSend(s_spi_q, &req, pdMS_TO_TICKS(200)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    if (ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(200)) == 0) {
        return ESP_ERR_TIMEOUT;
    }
    *out = s_mode_read_result;
    return ESP_OK;
}

static esp_err_t auris_mode_spi_write_blocking(uint8_t addr, uint32_t data)
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
// Queue-based gain-table upload. Mirrors auris_fpga_write_gain_table() but
// uses the SPI queue, so it is safe to call from mode_task context.
// M8: uses FPGA auto-increment — sets REG_GAIN_ADDR=0 once, then
// streams `len` REG_GAIN_DATA writes.  Sends 1 + 1 + 1 + 128 + 1 + 1
// = 133 individual requests at ~3.2 us each ≈ 0.43 ms total.
// ---------------------------------------------------------------------------
static esp_err_t auris_mode_upload_gain_table_via_queue(const int16_t *table_q14, size_t len)
{
    if (!table_q14)                              return ESP_ERR_INVALID_ARG;
    if (len == 0 || len > AURIS_NUM_GAIN_BINS)   return ESP_ERR_INVALID_ARG;
    if (!s_spi_q)                                return ESP_ERR_INVALID_STATE;

    uint32_t active = 0;
    esp_err_t r = auris_mode_spi_read_via_queue(REG_GAIN_BANK, &active);
    if (r != ESP_OK) return r;
    uint8_t inactive = (active == 0) ? 1 : 0;

    r = auris_mode_spi_write_blocking(REG_GAIN_BANK, inactive);
    if (r != ESP_OK) return r;

    // M8: set the auto-increment counter to 0; the FPGA bumps it on
    // every REG_GAIN_DATA write.
    r = auris_mode_spi_write_blocking(REG_GAIN_ADDR, 0);
    if (r != ESP_OK) return r;

    for (size_t i = 0; i < len; i++) {
        uint16_t bin = (uint16_t)table_q14[i];
        r = auris_mode_spi_write_blocking(REG_GAIN_DATA, bin);
        if (r != ESP_OK) return r;
    }

    r = auris_mode_spi_write_blocking(REG_GAIN_COMMIT, inactive);
    if (r != ESP_OK) return r;

    return auris_mode_spi_write_blocking(REG_GAIN_BANK, active & 1u);
}

// ---------------------------------------------------------------------------
// auris_mode_name
// ---------------------------------------------------------------------------
const char *auris_mode_name(auris_mode_t m)
{
    switch (m) {
        case AURIS_MODE_GENERAL: return "General";
        case AURIS_MODE_HEARING: return "Hearing";
        case AURIS_MODE_SPEECH:  return "Speech";
        case AURIS_MODE_BYPASS:  return "Bypass";
        default:                 return "?";
    }
}

// ---------------------------------------------------------------------------
// auris_mode_init
// ---------------------------------------------------------------------------
esp_err_t auris_mode_init(QueueHandle_t spi_q,
                          QueueHandle_t led_q,
                          QueueHandle_t profile_q)
{
    s_spi_q     = spi_q;
    s_led_q     = led_q;
    s_profile_q = profile_q;

    s_mutex = xSemaphoreCreateMutex();
    if (!s_mutex) return ESP_ERR_NO_MEM;

    // Restore the last mode from NVS (profile store is initialized earlier).
    uint8_t saved_u8 = (uint8_t)AURIS_MODE_GENERAL;
    (void)auris_profile_get_mode(&saved_u8);
    if (saved_u8 >= AURIS_MODE_COUNT) saved_u8 = 0;
    s_current = (auris_mode_t)saved_u8;
    ESP_LOGI(TAG, "Mode manager initialized, current=%s (%d)",
             auris_mode_name(s_current), (int)s_current);
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// auris_mode_set
// ---------------------------------------------------------------------------
void auris_mode_set(auris_mode_t m)
{
    if ((unsigned)m >= AURIS_MODE_COUNT) return;
    if (xSemaphoreTake(s_mutex, pdMS_TO_TICKS(50)) != pdTRUE) return;
    if (m != s_current) {
        auris_mode_t prev = s_current;
        s_current = m;
        xSemaphoreGive(s_mutex);

        ESP_LOGI(TAG, "Mode change: %s -> %s",
                 auris_mode_name(prev), auris_mode_name(m));

        // Notify state machine and consumers
        if (g_event_group) {
            xEventGroupSetBits(g_event_group, AURIS_EVT_MODE_CHANGED);
        }

        // Push to FPGA + LED + NVS
        if (auris_mode_apply_current() != ESP_OK) {
            ESP_LOGW(TAG, "Apply current mode failed");
        }
    } else {
        xSemaphoreGive(s_mutex);
    }
}

// ---------------------------------------------------------------------------
// auris_mode_get_current
// ---------------------------------------------------------------------------
auris_mode_t auris_mode_get_current(void)
{
    auris_mode_t m = AURIS_MODE_GENERAL;
    if (xSemaphoreTake(s_mutex, pdMS_TO_TICKS(50)) == pdTRUE) {
        m = s_current;
        xSemaphoreGive(s_mutex);
    }
    return m;
}

// ---------------------------------------------------------------------------
// auris_mode_cycle
// ---------------------------------------------------------------------------
void auris_mode_cycle(void)
{
    auris_mode_t cur = auris_mode_get_current();
    auris_mode_t next = (auris_mode_t)(((int)cur + 1) % AURIS_MODE_COUNT);
    auris_mode_set(next);
}

// ---------------------------------------------------------------------------
// auris_mode_apply_current — push current mode to FPGA + LED + NVS
//
// All FPGA register writes go through g_spi_q (C3). The gain table is
// uploaded via the queue as a sequence of 256 bin writes plus bank
// select/commit/restore, with each request blocking on a task
// notification. This is safe because spi_task serializes the bus.
// ---------------------------------------------------------------------------
esp_err_t auris_mode_apply_current(void)
{
    auris_mode_t m = auris_mode_get_current();
    const mode_regs_t *regs = &k_mode_table[m];

    ESP_LOGI(TAG, "Applying mode %s: DRC_THR=0x%X DRC_RATIO=%d NF=0x%X",
             auris_mode_name(m), regs->drc_threshold,
             regs->drc_ratio, regs->noise_floor);

    // 1. DSP enable
    esp_err_t r = auris_mode_spi_write_blocking(REG_CONTROL, 0x1);
    if (r != ESP_OK) return r;
    // 2. Mode register
    r = auris_mode_spi_write_blocking(REG_MODE, (uint32_t)m);
    if (r != ESP_OK) return r;
    // 3. DRC threshold + ratio
    r = auris_mode_spi_write_blocking(REG_DRC_THRESHOLD, regs->drc_threshold);
    if (r != ESP_OK) return r;
    r = auris_mode_spi_write_blocking(REG_DRC_RATIO, regs->drc_ratio);
    if (r != ESP_OK) return r;
    // 4. Noise floor
    r = auris_mode_spi_write_blocking(REG_NOISE_FLOOR, regs->noise_floor);
    if (r != ESP_OK) return r;
    // 5. Volume
    r = auris_mode_spi_write_blocking(REG_VOLUME, auris_vol_get());
    if (r != ESP_OK) return r;

    // 6. Gain table: user-tuned for Hearing, flat default for the rest.
    //    C3: route through the queue; do NOT call auris_fpga_write_gain_table,
    //    which would touch the SPI bus directly from mode_task context.
    int16_t tmp[128];
    if (m == AURIS_MODE_HEARING) {
        (void)auris_profile_get_gain_table(tmp, 128);
        r = auris_mode_upload_gain_table_via_queue(tmp, 128);
    } else {
        r = auris_mode_upload_gain_table_via_queue(s_table_default_q14, 128);
    }
    if (r != ESP_OK) {
        ESP_LOGW(TAG, "Gain table write failed: %s", esp_err_to_name(r));
    }

    // 7. LED feedback — request the led_task pick the running pattern
    auris_led_command_t lc = {
        .kind    = AURIS_LED_CMD_SET_PATTERN,
        .pattern = LED_PATTERN_RUNNING,
    };
    if (s_led_q) (void)xQueueOverwrite(s_led_q, &lc);

    // 8. Persist the new mode
    auris_profile_save_request_t save = {
        .kind = AURIS_PROF_SAVE_MODE,
        .u8   = (uint8_t)m,
    };
    if (s_profile_q) (void)xQueueSend(s_profile_q, &save, 0);

    return ESP_OK;
}

// ---------------------------------------------------------------------------
// auris_mode_apply_current_direct
//
// Boot-time variant of auris_mode_apply_current() that issues the same
// register sequence but uses the raw auris_spi_read / auris_spi_write API
// directly. MUST only be called from app_main BEFORE spi_task exists:
// once tasks are running, only auris_mode_apply_current() is safe.
// ---------------------------------------------------------------------------
esp_err_t auris_mode_apply_current_direct(void)
{
    auris_mode_t m = auris_mode_get_current();
    const mode_regs_t *regs = &k_mode_table[m];

    ESP_LOGI(TAG, "Direct-apply mode %s: DRC_THR=0x%X DRC_RATIO=%d NF=0x%X",
             auris_mode_name(m), regs->drc_threshold,
             regs->drc_ratio, regs->noise_floor);

    // REG_CONTROL wake is performed by the caller (main.c) so it stays
    // visible in the boot sequence, but re-assert it here to keep this
    // function self-contained for future use.
    esp_err_t r = auris_spi_write(REG_CONTROL, 0x1);
    if (r != ESP_OK) return r;

    r = auris_spi_write(REG_MODE, (uint32_t)m);
    if (r != ESP_OK) return r;
    r = auris_spi_write(REG_DRC_THRESHOLD, regs->drc_threshold);
    if (r != ESP_OK) return r;
    r = auris_spi_write(REG_DRC_RATIO, regs->drc_ratio);
    if (r != ESP_OK) return r;
    r = auris_spi_write(REG_NOISE_FLOOR, regs->noise_floor);
    if (r != ESP_OK) return r;
    r = auris_spi_write(REG_VOLUME, auris_vol_get());
    if (r != ESP_OK) return r;

    // Gain table: direct-SPI variant is fine here because spi_task doesn't
    // exist yet. auris_fpga_write_gain_table() does a read-modify-write
    // on the bank pointer and then 256 individual bin writes.
    int16_t tmp[128];
    const int16_t *src = s_table_default_q14;
    if (m == AURIS_MODE_HEARING) {
        (void)auris_profile_get_gain_table(tmp, 128);
        src = tmp;
    }
    r = auris_fpga_write_gain_table(src, 128);
    if (r != ESP_OK) {
        ESP_LOGW(TAG, "Direct gain table write failed: %s", esp_err_to_name(r));
    }
    return ESP_OK;
}
