// =============================================================================
// File:        battery_mon.c
// Project:     Project Auris
// Description: ADC1 oneshot driver for the battery sense divider. Keeps
//              a 5-sample moving average updated at 1 Hz. All public
//              getters read the most recent averaged value.
//
//              Voltage calculation:
//                V_adc  = raw * 3.1 V / 4095     (11 dB attenuation)
//                V_batt = V_adc * 2              (2:1 divider)
// =============================================================================
#include "battery_mon.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_log.h"
#include <string.h>

static const char *TAG = "battery_mon";

static adc_oneshot_unit_handle_t s_adc = NULL;
static bool   s_initialized = false;

// 5-sample moving average buffer
static int    s_avg_buf[AURIS_BATT_AVG_LEN] = {0};
static int    s_avg_idx = 0;
static int    s_avg_count = 0;
static int    s_avg_sum = 0;
static int    s_last_raw = 0;
static uint32_t s_last_mv = 0;

// ---------------------------------------------------------------------------
// auris_batt_init
// ---------------------------------------------------------------------------
esp_err_t auris_batt_init(void)
{
    if (s_initialized) return ESP_OK;

    adc_oneshot_unit_init_cfg_t unit_cfg = {
        .unit_id = ADC_UNIT_1,
        .ulp_mode = ADC_ULP_MODE_DISABLE,
    };
    esp_err_t r = adc_oneshot_new_unit(&unit_cfg, &s_adc);
    if (r != ESP_OK) {
        ESP_LOGE(TAG, "adc_oneshot_new_unit: %s", esp_err_to_name(r));
        return r;
    }

    adc_oneshot_chan_cfg_t chan_cfg = {
        .atten    = AURIS_BATT_ADC_ATTEN,
        .bitwidth = AURIS_BATT_ADC_BITWIDTH,
    };
    r = adc_oneshot_config_channel(s_adc, AURIS_BATT_ADC_CHANNEL, &chan_cfg);
    if (r != ESP_OK) {
        ESP_LOGE(TAG, "adc_oneshot_config_channel: %s", esp_err_to_name(r));
        adc_oneshot_del_unit(s_adc);
        s_adc = NULL;
        return r;
    }

    memset(s_avg_buf, 0, sizeof(s_avg_buf));
    s_avg_idx = s_avg_count = 0;
    s_avg_sum = 0;
    s_last_raw = 0;
    s_last_mv = 0;
    s_initialized = true;

    ESP_LOGI(TAG, "Battery monitor initialized: GPIO%d CH0, atten=11dB, 12-bit",
             AURIS_BATT_ADC_GPIO);
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// auris_batt_sample — take one reading, update moving average
// ---------------------------------------------------------------------------
esp_err_t auris_batt_sample(void)
{
    if (!s_initialized) return ESP_ERR_INVALID_STATE;
    int raw = 0;
    esp_err_t r = adc_oneshot_read(s_adc, AURIS_BATT_ADC_CHANNEL, &raw);
    if (r != ESP_OK) {
        ESP_LOGW(TAG, "adc read: %s", esp_err_to_name(r));
        return r;
    }
    if (raw < 0) raw = 0;
    if (raw > 4095) raw = 4095;

    // Ring buffer update
    s_avg_sum -= s_avg_buf[s_avg_idx];
    s_avg_buf[s_avg_idx] = raw;
    s_avg_sum += raw;
    s_avg_idx = (s_avg_idx + 1) % AURIS_BATT_AVG_LEN;
    if (s_avg_count < AURIS_BATT_AVG_LEN) s_avg_count++;

    int avg = s_avg_sum / s_avg_count;
    s_last_raw = avg;

    // Convert to mV: 11 dB attenuation → 3.1 V full-scale.
    // raw / 4095 * 3100 = V_adc in mV.
    uint32_t v_adc_mv = (uint32_t)((uint64_t)avg * 3100u / 4095u);
    s_last_mv = v_adc_mv * AURIS_BATT_DIVIDER_RATIO;

    // Clamp to expected range
    if (s_last_mv < AURIS_BATT_V_MIN_MV) s_last_mv = AURIS_BATT_V_MIN_MV;
    if (s_last_mv > AURIS_BATT_V_MAX_MV) s_last_mv = AURIS_BATT_V_MAX_MV;

    return ESP_OK;
}

// ---------------------------------------------------------------------------
// auris_batt_get_mv
// ---------------------------------------------------------------------------
uint32_t auris_batt_get_mv(void)
{
    return s_last_mv;
}

// ---------------------------------------------------------------------------
// auris_batt_get_percent
//
// Linear piecewise approximation of the Li-Ion discharge curve:
//   3.0 V  -> 0 %
//   3.7 V  -> 50 %
//   4.2 V  -> 100 %
// ---------------------------------------------------------------------------
int auris_batt_get_percent(void)
{
    if (s_last_mv <= AURIS_BATT_V_MIN_MV) return 0;
    if (s_last_mv >= AURIS_BATT_V_MAX_MV) return 100;
    if (s_last_mv >= 3700) {
        // 3.7..4.2 V -> 50..100
        return 50 + (int)((uint64_t)(s_last_mv - 3700) * 50 / 500);
    }
    // 3.0..3.7 V -> 0..50
    return (int)((uint64_t)(s_last_mv - AURIS_BATT_V_MIN_MV) * 50 / 700);
}

bool auris_batt_is_low(void)
{
    return s_last_mv < AURIS_BATT_V_LOW_MV;
}

bool auris_batt_is_critical(void)
{
    return s_last_mv < AURIS_BATT_V_CRITICAL_MV;
}
