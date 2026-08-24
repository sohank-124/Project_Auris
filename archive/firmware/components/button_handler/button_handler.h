// =============================================================================
// File:        button_handler.h
// Project:     Project Auris
// Description: GPIO button debounce + event dispatch. Three buttons wired
//              with internal pull-ups to GND on press:
//
//                GPIO32 = Volume+
//                GPIO25 = Volume-
//                GPIO33 = Mode
//
//              Debounce: 5 consecutive stable samples at 10 ms period
//              (= 50 ms total). Long-press detection: a button held for
//              >= 1 s emits BTN_EVT_*__LONG, then re-fires every 150 ms
//              while held. MODE long-press >= 5 s emits BTN_EVT_MODE_LONG
//              (Phase-3 sleep trigger).
// =============================================================================
#ifndef AURIS_BUTTON_HANDLER_H
#define AURIS_BUTTON_HANDLER_H

#include <stdint.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Public event enum (consumed by mode_task via g_button_q)
// ---------------------------------------------------------------------------
typedef enum {
    BTN_EVT_NONE          = 0,
    BTN_EVT_VOL_UP        = 1,
    BTN_EVT_VOL_DOWN      = 2,
    BTN_EVT_MODE          = 3,
    BTN_EVT_VOL_UP_LONG   = 4,   // repeat at 150 ms while held
    BTN_EVT_VOL_DOWN_LONG = 5,
    BTN_EVT_MODE_LONG     = 6,   // >= 5 s, Phase 3 sleep
} button_event_t;

// Pin assignments (must match hardware schematic)
#define AURIS_BTN_PIN_VOL_UP   32
#define AURIS_BTN_PIN_VOL_DN   25
#define AURIS_BTN_PIN_MODE     33

// Timing (all in 10 ms ticks, per the spec's sample period)
#define AURIS_BTN_SAMPLE_MS        10
#define AURIS_BTN_DEBOUNCE_TICKS   5       // 50 ms
#define AURIS_BTN_LONG_PRESS_MS    1000    // 1 s
#define AURIS_BTN_LONG_REPEAT_MS   150
#define AURIS_BTN_MODE_LONG_MS     5000    // 5 s

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------
esp_err_t      auris_btn_init(void);
button_event_t auris_btn_tick(void);

#ifdef __cplusplus
}
#endif

#endif // AURIS_BUTTON_HANDLER_H
