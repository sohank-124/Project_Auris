// =============================================================================
// File:        profile_store.c
// Project:     Project Auris
// Description: NVS persistence layer. On auris_profile_init():
//                1. Open the "auris" namespace.
//                2. Read schema_ver. If < AURIS_PROFILE_SCHEMA_VER or
//                   missing, factory reset.
//                3. Read err_cnt. If >= AURIS_PROFILE_ERR_THRESHOLD, log
//                   and factory reset (boot-loop recovery).
//                4. Read the rest of the keys into the RAM mirror.
//                5. Increment and persist boot_cnt.
//
// Setters update the RAM mirror immediately and return ESP_OK. The actual
// NVS write is performed later by profile_task from the g_profile_q.
// =============================================================================
#include "profile_store.h"
// C6: AURIS_MODE_GENERAL is defined in mode_manager.h; without this
// include the build would fail on the default-initializer below.
#include "mode_manager.h"
#include "nvs_flash.h"
#include "nvs.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include <string.h>

static const char *TAG = "profile_store";

// NVS keys
static const char *K_SCHEMA = "schema_ver";
static const char *K_MODE   = "mode";
static const char *K_VOL    = "vol";
static const char *K_GAIN   = "gain_tbl";
static const char *K_BOOT   = "boot_cnt";
static const char *K_ERR    = "err_cnt";

// ---------------------------------------------------------------------------
// RAM mirror, NVS handle, and M3: access mutex.
//
// profile_task is the only task that performs NVS writes, but the RAM
// mirror is read and written from many contexts (mode_task, audio_task
// via monitor_task, etc.). A mutex serializes mirror access so that a
// reader cannot observe a partially updated struct.
// ---------------------------------------------------------------------------
static auris_profile_t   s_mirror = {
    .schema_ver = AURIS_PROFILE_SCHEMA_VER,
    .mode       = AURIS_MODE_GENERAL,
    .volume     = 16,
    .gain_tbl   = {[0 ... 127] = 16384},   // M7: unity Q2.14, matches FPGA default
    .boot_cnt   = 0,
    .err_cnt    = 0,
};
static nvs_handle_t      s_nvs    = 0;
static bool              s_open   = false;
static SemaphoreHandle_t s_mutex  = NULL;

// ---------------------------------------------------------------------------
// Default-values writer (used by factory reset and schema migration)
// ---------------------------------------------------------------------------
static void auris_profile_set_defaults(void)
{
    s_mirror.schema_ver = AURIS_PROFILE_SCHEMA_VER;
    s_mirror.mode       = AURIS_MODE_GENERAL;
    s_mirror.volume     = 16;
    // M7: default gain table is unity (16384 in Q2.14 = 1.0x), matching
    // the FPGA's default gain-table initial value. A factory reset must
    // not boot the device into silence.
    for (int i = 0; i < AURIS_PROFILE_GAIN_BINS; i++) {
        s_mirror.gain_tbl[i] = 16384;
    }
    // boot_cnt and err_cnt are reset by the factory_reset path.
}

// ---------------------------------------------------------------------------
// auris_profile_factory_reset
// ---------------------------------------------------------------------------
esp_err_t auris_profile_factory_reset(void)
{
    if (!s_open) {
        // First-time boot path: nvs_flash_init() was already called.
        esp_err_t r = nvs_open(AURIS_PROFILE_NS, NVS_READWRITE, &s_nvs);
        if (r != ESP_OK) {
            ESP_LOGE(TAG, "factory_reset: nvs_open: %s", esp_err_to_name(r));
            return r;
        }
        s_open = true;
    }
    ESP_LOGW(TAG, "Factory reset of NVS namespace '%s'", AURIS_PROFILE_NS);
    esp_err_t r = nvs_erase_all(s_nvs);
    if (r != ESP_OK) {
        ESP_LOGE(TAG, "nvs_erase_all: %s", esp_err_to_name(r));
        return r;
    }
    r = nvs_commit(s_nvs);
    if (r != ESP_OK) {
        ESP_LOGE(TAG, "nvs_commit: %s", esp_err_to_name(r));
        return r;
    }
    auris_profile_set_defaults();
    s_mirror.boot_cnt = 0;
    s_mirror.err_cnt  = 0;
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// auris_profile_init
// ---------------------------------------------------------------------------
esp_err_t auris_profile_init(void)
{
    if (s_open) return ESP_OK;

    // M3: create the mirror-access mutex exactly once, before any reader
    // or writer can run.
    if (!s_mutex) {
        s_mutex = xSemaphoreCreateMutex();
        if (!s_mutex) {
            ESP_LOGE(TAG, "xSemaphoreCreateMutex failed");
            return ESP_ERR_NO_MEM;
        }
    }

    esp_err_t r = nvs_open(AURIS_PROFILE_NS, NVS_READWRITE, &s_nvs);
    if (r != ESP_OK) {
        ESP_LOGE(TAG, "nvs_open: %s", esp_err_to_name(r));
        return r;
    }
    s_open = true;

    // Schema check
    uint8_t ver = 0;
    r = nvs_get_u8(s_nvs, K_SCHEMA, &ver);
    if (r == ESP_ERR_NVS_NOT_FOUND || ver < AURIS_PROFILE_SCHEMA_VER) {
        ESP_LOGW(TAG, "Schema ver %u (expected %u) — factory reset",
                 ver, AURIS_PROFILE_SCHEMA_VER);
        (void)auris_profile_factory_reset();
    } else if (r != ESP_OK) {
        ESP_LOGE(TAG, "schema read: %s", esp_err_to_name(r));
        return r;
    }

    // Read mirror
    auris_profile_set_defaults();
    nvs_get_u8(s_nvs, K_MODE, &s_mirror.mode);
    nvs_get_u8(s_nvs, K_VOL,  &s_mirror.volume);
    size_t blob = sizeof(s_mirror.gain_tbl);
    nvs_get_blob(s_nvs, K_GAIN, s_mirror.gain_tbl, &blob);
    nvs_get_u32(s_nvs, K_BOOT, &s_mirror.boot_cnt);
    nvs_get_u32(s_nvs, K_ERR,  &s_mirror.err_cnt);

    // Boot-loop recovery
    if (s_mirror.err_cnt >= AURIS_PROFILE_ERR_THRESHOLD) {
        ESP_LOGE(TAG, "err_cnt=%lu >= %d — factory reset",
                 (unsigned long)s_mirror.err_cnt, AURIS_PROFILE_ERR_THRESHOLD);
        (void)auris_profile_factory_reset();
    }

    // Sanity-clamp
    if (s_mirror.mode > 3) s_mirror.mode = 0;
    if (s_mirror.volume > 31) s_mirror.volume = 16;

    // Increment boot_cnt
    s_mirror.boot_cnt++;
    nvs_set_u32(s_nvs, K_BOOT, s_mirror.boot_cnt);
    nvs_set_u8 (s_nvs, K_SCHEMA, s_mirror.schema_ver);
    nvs_commit(s_nvs);

    ESP_LOGI(TAG, "Profile loaded: mode=%d vol=%d boot_cnt=%lu err_cnt=%lu",
             s_mirror.mode, s_mirror.volume,
             (unsigned long)s_mirror.boot_cnt,
             (unsigned long)s_mirror.err_cnt);
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// auris_profile_get_mirror
// ---------------------------------------------------------------------------
const auris_profile_t *auris_profile_get_mirror(void)
{
    return &s_mirror;
}

// ---------------------------------------------------------------------------
// Mode / volume (mirror only — NVS writes happen via profile_task)
// ---------------------------------------------------------------------------
esp_err_t auris_profile_get_mode(uint8_t *m)
{
    if (!m) return ESP_ERR_INVALID_ARG;
    if (s_mutex && xSemaphoreTake(s_mutex, pdMS_TO_TICKS(50)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    *m = s_mirror.mode;
    if (s_mutex) xSemaphoreGive(s_mutex);
    return ESP_OK;
}

esp_err_t auris_profile_set_mode(uint8_t m)
{
    if (m >= 4) return ESP_ERR_INVALID_ARG;
    if (s_mutex && xSemaphoreTake(s_mutex, pdMS_TO_TICKS(50)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    s_mirror.mode = m;
    esp_err_t r = ESP_OK;
    if (s_open) {
        r = nvs_set_u8(s_nvs, K_MODE, s_mirror.mode);
        if (r == ESP_OK) r = nvs_commit(s_nvs);
    }
    if (s_mutex) xSemaphoreGive(s_mutex);
    return r;
}

esp_err_t auris_profile_get_volume(uint8_t *v)
{
    if (!v) return ESP_ERR_INVALID_ARG;
    if (s_mutex && xSemaphoreTake(s_mutex, pdMS_TO_TICKS(50)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    *v = s_mirror.volume;
    if (s_mutex) xSemaphoreGive(s_mutex);
    return ESP_OK;
}

esp_err_t auris_profile_set_volume(uint8_t v)
{
    if (v > 31) return ESP_ERR_INVALID_ARG;
    if (s_mutex && xSemaphoreTake(s_mutex, pdMS_TO_TICKS(50)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    s_mirror.volume = v;
    esp_err_t r = ESP_OK;
    if (s_open) {
        r = nvs_set_u8(s_nvs, K_VOL, s_mirror.volume);
        if (r == ESP_OK) r = nvs_commit(s_nvs);
    }
    if (s_mutex) xSemaphoreGive(s_mutex);
    return r;
}

// ---------------------------------------------------------------------------
// Gain table
// ---------------------------------------------------------------------------
esp_err_t auris_profile_get_gain_table(int16_t *out_q14, size_t len)
{
    if (!out_q14) return ESP_ERR_INVALID_ARG;
    if (len > AURIS_PROFILE_GAIN_BINS) len = AURIS_PROFILE_GAIN_BINS;
    if (s_mutex && xSemaphoreTake(s_mutex, pdMS_TO_TICKS(50)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    memcpy(out_q14, s_mirror.gain_tbl, len * sizeof(int16_t));
    if (s_mutex) xSemaphoreGive(s_mutex);
    return ESP_OK;
}

esp_err_t auris_profile_set_gain_table(const int16_t *in_q14, size_t len)
{
    if (!in_q14) return ESP_ERR_INVALID_ARG;
    if (len > AURIS_PROFILE_GAIN_BINS) return ESP_ERR_INVALID_ARG;
    if (s_mutex && xSemaphoreTake(s_mutex, pdMS_TO_TICKS(50)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    memcpy(s_mirror.gain_tbl, in_q14, len * sizeof(int16_t));
    esp_err_t r = ESP_OK;
    if (s_open) {
        r = nvs_set_blob(s_nvs, K_GAIN, s_mirror.gain_tbl,
                         sizeof(s_mirror.gain_tbl));
        if (r == ESP_OK) r = nvs_commit(s_nvs);
    }
    if (s_mutex) xSemaphoreGive(s_mutex);
    return r;
}

// ---------------------------------------------------------------------------
// Error counter
// ---------------------------------------------------------------------------
esp_err_t auris_profile_inc_err_cnt(void)
{
    if (s_mutex && xSemaphoreTake(s_mutex, pdMS_TO_TICKS(50)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    s_mirror.err_cnt++;
    esp_err_t r = ESP_OK;
    if (s_open) {
        r = nvs_set_u32(s_nvs, K_ERR, s_mirror.err_cnt);
        if (r == ESP_OK) r = nvs_commit(s_nvs);
    }
    if (s_mutex) xSemaphoreGive(s_mutex);
    return r;
}

uint32_t auris_profile_get_err_cnt(void)
{
    uint32_t v = 0;
    if (s_mutex && xSemaphoreTake(s_mutex, pdMS_TO_TICKS(50)) != pdTRUE) {
        return 0;
    }
    v = s_mirror.err_cnt;
    if (s_mutex) xSemaphoreGive(s_mutex);
    return v;
}
