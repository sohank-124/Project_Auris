// =============================================================================
// File:        app_state.h
// Project:     Project Auris
// Description: Device-level state machine and event-group definitions shared
//              across all firmware tasks. The state machine is driven from
//              main.c and observed (read-only) by background tasks via
//              auris_app_state_get() and the global event group.
//
//              States (transitions):
//                  BOOT     -> INIT       (NVS + FPGA probe OK)
//                  INIT     -> RUNNING    (I2S started, all tasks spawned)
//                  INIT     -> ERROR      (FPGA probe failed 3x)
//                  RUNNING  -> ERROR      (audio/SPI/FPGA fault)
//                  ERROR    -> RUNNING    (FPGA re-probe OK)
//                  ERROR    -> RESTART    (3 consecutive ERROR entries)
//                  *        -> SLEEP      (Phase 3, BTN_MODE_LONG >= 5s)
// =============================================================================
#ifndef AURIS_APP_STATE_H
#define AURIS_APP_STATE_H

#include <stdint.h>
#include "esp_err.h"
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// State machine
// ---------------------------------------------------------------------------
typedef enum {
    AURIS_STATE_BOOT     = 0,
    AURIS_STATE_INIT     = 1,
    AURIS_STATE_RUNNING  = 2,
    AURIS_STATE_ERROR    = 3,
    AURIS_STATE_SLEEP    = 4,
} auris_state_t;

// ---------------------------------------------------------------------------
// Event group bits
// ---------------------------------------------------------------------------
#define AURIS_EVT_FPGA_CONNECTED  BIT0
#define AURIS_EVT_AUDIO_RUNNING   BIT1
#define AURIS_EVT_LOW_BATTERY     BIT2
#define AURIS_EVT_ERROR           BIT3
#define AURIS_EVT_MODE_CHANGED    BIT4
#define AURIS_EVT_VOLUME_CHANGED  BIT5

#define AURIS_EVT_ALL_BITS        (AURIS_EVT_FPGA_CONNECTED | \
                                   AURIS_EVT_AUDIO_RUNNING  | \
                                   AURIS_EVT_LOW_BATTERY    | \
                                   AURIS_EVT_ERROR          | \
                                   AURIS_EVT_MODE_CHANGED   | \
                                   AURIS_EVT_VOLUME_CHANGED)

// ---------------------------------------------------------------------------
// Global handles (defined in main.c)
// ---------------------------------------------------------------------------
extern EventGroupHandle_t g_event_group;

// ---------------------------------------------------------------------------
// State helpers
// ---------------------------------------------------------------------------
const char     *auris_state_name(auris_state_t s);
auris_state_t   auris_app_state_get(void);
void            auris_app_state_set(auris_state_t s);
bool            auris_app_state_is(auris_state_t s);

#ifdef __cplusplus
}
#endif

#endif // AURIS_APP_STATE_H
