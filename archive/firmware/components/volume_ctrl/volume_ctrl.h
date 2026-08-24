// =============================================================================
// File:        volume_ctrl.h
// Project:     Project Auris
// Description: Volume control state. 0..31 steps, 2 dB per step. Volume=0
//              is mute (REG_VOLUME=0 sets FPGA digital mute). Default
//              startup value is 16 (mid scale).
//
//              This component runs in mode_task context and is the
//              single owner of REG_VOLUME writes.
// =============================================================================
#ifndef AURIS_VOLUME_CTRL_H
#define AURIS_VOLUME_CTRL_H

#include <stdint.h>
#include "esp_err.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "spi_master.h"          // auris_spi_request_t
#include "led_indicator.h"       // auris_led_command_t
#include "profile_store.h"       // auris_profile_save_request_t

#ifdef __cplusplus
extern "C" {
#endif

#define AURIS_VOLUME_MIN       0
#define AURIS_VOLUME_MAX       31
#define AURIS_VOLUME_DEFAULT   16
#define AURIS_VOLUME_STEP_DB   2

esp_err_t auris_vol_init(QueueHandle_t spi_q,
                         QueueHandle_t led_q,
                         QueueHandle_t profile_q);

// Clamp and apply. `delta` is +1 or -1 typically. Returns the new value.
uint8_t   auris_vol_step(int delta);

uint8_t   auris_vol_get(void);
void      auris_vol_set(uint8_t v);

#ifdef __cplusplus
}
#endif

#endif // AURIS_VOLUME_CTRL_H
