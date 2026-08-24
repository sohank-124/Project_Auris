// =============================================================================
// File:        led_indicator.h
// Project:     Project Auris
// Description: Two discrete LEDs (green=heartbeat, red=clip/error) driven
//              directly by GPIO (no PWM). auris_led_tick() runs at 50 Hz
//              from led_task and walks the pattern state machine.
//
// Patterns:
//   BOOT         1 Hz green blink
//   INIT         4 Hz green blink
//   RUNNING      solid green
//   ERROR        2 Hz red blink
//   LOW_BATTERY  alternating green/red, 1 s each
//
// Transient overlays:
//   BLINK_N      N green blinks (volume feedback); returns to last pattern
//   PEAK         red flash for 100 ms when peak > 0x700000
// =============================================================================
#ifndef AURIS_LED_INDICATOR_H
#define AURIS_LED_INDICATOR_H

#include <stdint.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define AURIS_LED_PIN_GREEN    27
#define AURIS_LED_PIN_RED      26

// 50 Hz tick → 20 ms per tick
#define AURIS_LED_TICK_MS      20

// Pattern identifiers (consumed by mode_task and monitor_task)
typedef enum {
    LED_PATTERN_BOOT         = 0,   // 1 Hz green blink
    LED_PATTERN_INIT         = 1,   // 4 Hz green blink
    LED_PATTERN_RUNNING      = 2,   // solid green
    LED_PATTERN_ERROR        = 3,   // 2 Hz red blink
    LED_PATTERN_LOW_BATTERY  = 4,   // alternating green/red
} led_pattern_t;

esp_err_t      auris_led_init      (void);
void           auris_led_set_state (led_pattern_t pat);
void           auris_led_tick      (void);

// User-feedback overlays
void           auris_led_blink_n   (uint8_t n);
void           auris_led_update_peak(uint32_t peak);
void           auris_led_off       (void);

// ---------------------------------------------------------------------------
// LED command envelope — produced by mode_task, monitor_task, etc. and
// consumed by led_task via the g_led_q queue.
// ---------------------------------------------------------------------------
typedef enum {
    AURIS_LED_CMD_SET_PATTERN = 0,
    AURIS_LED_CMD_BLINK_N     = 1,
    AURIS_LED_CMD_PEAK        = 2,
    AURIS_LED_CMD_OFF         = 3,
} auris_led_cmd_kind_t;

typedef struct {
    auris_led_cmd_kind_t kind;
    led_pattern_t        pattern;     // for SET_PATTERN
    uint8_t              count;       // for BLINK_N
    uint32_t             peak;        // for PEAK
} auris_led_command_t;

#ifdef __cplusplus
}
#endif

#endif // AURIS_LED_INDICATOR_H
