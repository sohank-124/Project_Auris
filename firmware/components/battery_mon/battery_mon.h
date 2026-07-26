// =============================================================================
// File:        battery_mon.h
// Project:     Project Auris
// Description: Li-Ion battery monitor. Uses ADC1_CH0 (GPIO36) with 11 dB
//              attenuation and the new ESP-IDF v5.x oneshot ADC API. A 2:1
//              resistor divider brings the 3.0-4.2 V battery into the
//              1.5-2.1 V ADC input range.
//
// Sampling: 1 Hz, 5-sample moving average.
// Thresholds (after divider compensation):
//   LOW       < 3.3 V  (warning)
//   CRITICAL  < 3.1 V  (LED indicator switches to LOW_BATTERY pattern)
// =============================================================================
#ifndef AURIS_BATTERY_MON_H
#define AURIS_BATTERY_MON_H

#include <stdint.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define AURIS_BATT_ADC_GPIO          36
#define AURIS_BATT_ADC_CHANNEL       ADC_CHANNEL_0
#define AURIS_BATT_ADC_ATTEN         ADC_ATTEN_DB_11
#define AURIS_BATT_ADC_BITWIDTH      ADC_BITWIDTH_12
#define AURIS_BATT_DIVIDER_RATIO     2       // V_batt = V_adc * 2
#define AURIS_BATT_V_MIN_MV          3000
#define AURIS_BATT_V_MAX_MV          4200
#define AURIS_BATT_V_LOW_MV          3300
#define AURIS_BATT_V_CRITICAL_MV     3100
#define AURIS_BATT_AVG_LEN           5
#define AURIS_BATT_SAMPLE_PERIOD_MS  1000

esp_err_t auris_batt_init        (void);
int      auris_batt_get_percent  (void);     // 0..100
uint32_t auris_batt_get_mv      (void);     // millivolts
bool     auris_batt_is_low      (void);
bool     auris_batt_is_critical (void);

// Force a fresh sample + average; called from monitor_task at 1 Hz.
esp_err_t auris_batt_sample     (void);

#ifdef __cplusplus
}
#endif

#endif // AURIS_BATTERY_MON_H
