// =============================================================================
// File:        mode_manager.h
// Project:     Project Auris
// Description: Tracks the current operating mode (General, Hearing, Speech,
//              Bypass) and orchestrates the FPGA reg writes that bring the
//              FPGA into the matching configuration. auris_mode_apply_*
//              must be called from mode_task (the only context that may
//              post to g_spi_q / g_led_q / g_profile_q).
//
// Mode register table (per architecture spec):
//   Mode 0 General: DRC_THRESHOLD=0x400, DRC_RATIO=4, NOISE_FLOOR=0x20
//   Mode 1 Hearing: DRC_THRESHOLD=0x200, DRC_RATIO=8, NOISE_FLOOR=0x40
//   Mode 2 Speech:  DRC_THRESHOLD=0x300, DRC_RATIO=6, NOISE_FLOOR=0x30
//   Mode 3 Bypass:  DRC_THRESHOLD=0xFFF, DRC_RATIO=1, NOISE_FLOOR=0x00
// =============================================================================
#ifndef AURIS_MODE_MANAGER_H
#define AURIS_MODE_MANAGER_H

#include <stdint.h>
#include "esp_err.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "spi_master.h"          // auris_spi_request_t
#include "led_indicator.h"       // auris_led_command_t, led_pattern_t
#include "profile_store.h"       // auris_profile_save_request_t

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    AURIS_MODE_GENERAL = 0,
    AURIS_MODE_HEARING = 1,
    AURIS_MODE_SPEECH  = 2,
    AURIS_MODE_BYPASS  = 3,
    AURIS_MODE_COUNT   = 4,
} auris_mode_t;

esp_err_t     auris_mode_init(QueueHandle_t spi_q,
                              QueueHandle_t led_q,
                              QueueHandle_t profile_q);
void          auris_mode_set(auris_mode_t m);
auris_mode_t  auris_mode_get_current(void);
void          auris_mode_cycle(void);

// Push the current mode's full register set to the FPGA, send LED feedback,
// and request an NVS save. Blocks on SPI task notifications. Must run from
// mode_task context.
esp_err_t     auris_mode_apply_current(void);

// Pre-task variant: writes the same register set using direct SPI calls.
// MUST only be called from app_main before spi_task exists; once the
// RTOS scheduler is running, use auris_mode_apply_current() instead.
esp_err_t     auris_mode_apply_current_direct(void);

const char   *auris_mode_name(auris_mode_t m);

#ifdef __cplusplus
}
#endif

#endif // AURIS_MODE_MANAGER_H
