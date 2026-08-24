// =============================================================================
// File:        led_indicator.c
// Project:     Project Auris
// Description: LED pattern engine. auris_led_tick() runs at 50 Hz from
//              led_task. Each tick advances the internal phase counter
//              and drives the two GPIO pins directly.
//
//              A small state machine handles pattern overlays:
//                - A "BLINK_N" overlay takes over for N green blinks then
//                  returns to the base pattern.
//                - A "PEAK" overlay flashes red for 100 ms, then resumes
//                  the base pattern. New peak events re-trigger the flash.
// =============================================================================
#include "led_indicator.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include <string.h>
#include <stdbool.h>

static const char *TAG = "led_indicator";

// Pattern descriptors: (period_ms, duty_q15, color, alt_color)
typedef enum { COLOR_GREEN = 0, COLOR_RED = 1, COLOR_ALT = 2 } color_mode_t;

typedef struct {
    uint16_t    period_ms;     // 0 = solid
    uint16_t    duty_q15;      // 0..32768 = fraction of period that is ON
    color_mode_t color;
} pattern_desc_t;

// duty_q15 = 0x8000 = 50%; 0xFFFF = 100% (solid)
static const pattern_desc_t k_patterns[] = {
    [LED_PATTERN_BOOT]        = { .period_ms = 1000, .duty_q15 = 0x8000, .color = COLOR_GREEN },
    [LED_PATTERN_INIT]        = { .period_ms =  250, .duty_q15 = 0x8000, .color = COLOR_GREEN },
    [LED_PATTERN_RUNNING]     = { .period_ms =    0, .duty_q15 = 0xFFFF, .color = COLOR_GREEN },
    [LED_PATTERN_ERROR]       = { .period_ms =  500, .duty_q15 = 0x8000, .color = COLOR_RED   },
    [LED_PATTERN_LOW_BATTERY] = { .period_ms = 1000, .duty_q15 = 0x8000, .color = COLOR_ALT   },
};

// State
static led_pattern_t s_base_pattern = LED_PATTERN_BOOT;
static uint32_t      s_phase_ms     = 0;     // accumulated time in current pattern
static int           s_alt_phase    = 0;     // alternates 0/1 for ALT color

// Blink-N overlay
static uint8_t       s_blink_remaining = 0;
static uint16_t      s_blink_period_ms = 0;
static led_pattern_t s_blink_return    = LED_PATTERN_RUNNING;

// Peak flash overlay
static uint16_t      s_peak_flash_ms_left = 0;

// ---------------------------------------------------------------------------
// auris_led_init
// ---------------------------------------------------------------------------
esp_err_t auris_led_init(void)
{
    uint64_t mask = (1ULL << AURIS_LED_PIN_GREEN) | (1ULL << AURIS_LED_PIN_RED);
    gpio_config_t cfg = {
        .pin_bit_mask = mask,
        .mode         = GPIO_MODE_OUTPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE,
    };
    esp_err_t r = gpio_config(&cfg);
    if (r != ESP_OK) {
        ESP_LOGE(TAG, "gpio_config: %s", esp_err_to_name(r));
        return r;
    }
    gpio_set_level(AURIS_LED_PIN_GREEN, 0);
    gpio_set_level(AURIS_LED_PIN_RED,   0);
    s_base_pattern = LED_PATTERN_BOOT;
    ESP_LOGI(TAG, "LED indicator initialized: GRN=%d RED=%d",
             AURIS_LED_PIN_GREEN, AURIS_LED_PIN_RED);
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// Set the base pattern (called from led_task on LED_CMD_SET_PATTERN)
// ---------------------------------------------------------------------------
void auris_led_set_state(led_pattern_t pat)
{
    if ((unsigned)pat >= (unsigned)(sizeof(k_patterns)/sizeof(k_patterns[0]))) {
        return;
    }
    s_base_pattern = pat;
    s_phase_ms     = 0;
    s_alt_phase    = 0;
    ESP_LOGD(TAG, "LED pattern: %d", (int)pat);
}

// ---------------------------------------------------------------------------
// Volume feedback: N green blinks
// ---------------------------------------------------------------------------
void auris_led_blink_n(uint8_t n)
{
    if (n == 0) n = 1;
    if (n > 8) n = 8;     // clamp
    s_blink_remaining = n;
    s_blink_period_ms = 150;  // 75 ms on, 75 ms off
    s_blink_return    = s_base_pattern;
}

// ---------------------------------------------------------------------------
// Peak / clip indicator
// ---------------------------------------------------------------------------
void auris_led_update_peak(uint32_t peak)
{
    if (peak >= 0x700000u) {
        s_peak_flash_ms_left = 100;   // 100 ms red flash
    }
}

// ---------------------------------------------------------------------------
// Off
// ---------------------------------------------------------------------------
void auris_led_off(void)
{
    gpio_set_level(AURIS_LED_PIN_GREEN, 0);
    gpio_set_level(AURIS_LED_PIN_RED,   0);
}

// ---------------------------------------------------------------------------
// Internal: drive the pins for the current effective pattern
// ---------------------------------------------------------------------------
static void auris_led_apply(const pattern_desc_t *p, bool on, color_mode_t alt_color)
{
    int green = 0, red = 0;
    color_mode_t c = p->color;
    if (c == COLOR_ALT) c = alt_color;

    if (on) {
        if (c == COLOR_GREEN) green = 1;
        else                  red   = 1;
    }
    gpio_set_level(AURIS_LED_PIN_GREEN, green);
    gpio_set_level(AURIS_LED_PIN_RED,   red);
}

// ---------------------------------------------------------------------------
// auris_led_tick — called at 50 Hz
// ---------------------------------------------------------------------------
void auris_led_tick(void)
{
    s_phase_ms += AURIS_LED_TICK_MS;

    // 1. Peak flash overlay (highest priority — visual safety)
    if (s_peak_flash_ms_left > 0) {
        gpio_set_level(AURIS_LED_PIN_GREEN, 0);
        gpio_set_level(AURIS_LED_PIN_RED,   1);
        if (s_peak_flash_ms_left > AURIS_LED_TICK_MS) {
            s_peak_flash_ms_left -= AURIS_LED_TICK_MS;
        } else {
            s_peak_flash_ms_left = 0;
        }
        return;
    }

    // 2. Blink-N overlay
    if (s_blink_remaining > 0) {
        uint16_t half = s_blink_period_ms / 2;
        if (half == 0) half = 50;
        uint16_t pos = s_phase_ms % s_blink_period_ms;
        bool on = (pos < half);
        gpio_set_level(AURIS_LED_PIN_GREEN, on ? 1 : 0);
        gpio_set_level(AURIS_LED_PIN_RED,   0);
        if (s_phase_ms >= s_blink_period_ms) {
            s_phase_ms = 0;
            s_blink_remaining--;
            if (s_blink_remaining == 0) {
                s_base_pattern = s_blink_return;
                s_phase_ms     = 0;
            }
        }
        return;
    }

    // 3. Base pattern
    const pattern_desc_t *p = &k_patterns[s_base_pattern];
    if (p->period_ms == 0) {
        // Solid
        auris_led_apply(p, true, COLOR_GREEN);
        return;
    }

    uint16_t pos = s_phase_ms % p->period_ms;
    uint16_t on_ms = (uint16_t)(((uint32_t)p->duty_q15 * p->period_ms) >> 15);
    bool on = (pos < on_ms);
    if (p->color == COLOR_ALT) {
        s_alt_phase = (s_phase_ms / p->period_ms) & 1;
    }
    auris_led_apply(p, on, (color_mode_t)s_alt_phase);
}
