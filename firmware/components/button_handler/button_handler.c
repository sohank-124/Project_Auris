// =============================================================================
// File:        button_handler.c
// Project:     Project Auris
// Description: Debounce + long-press detector. Called from button_task at
//              exactly 10 ms intervals. Each call:
//                1. Reads all three GPIOs.
//                2. Runs a 5-tap debounce filter.
//                3. On a stable rising edge (press), records the timestamp.
//                4. On the falling edge (release), if the press was
//                   shorter than 1 s, emits a short event.
//                5. While held, emits a long-press event every 150 ms
//                   (or a single BTN_EVT_MODE_LONG after 5 s).
// =============================================================================
#include "button_handler.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include <stdint.h>
#include <stdbool.h>

static const char *TAG = "button";

typedef struct {
    gpio_num_t      pin;
    int             stable;          // 1 = released, 0 = pressed
    int             cnt;             // debounce counter
    int             pressed;         // 1 = currently held (post-debounce)
    TickType_t      press_tick;      // tick at which press started
    TickType_t      last_repeat;     // last long-repeat emit
    int             long_emitted;    // for MODE long-press (one-shot)
} btn_state_t;

static btn_state_t s_btns[3];

// ---------------------------------------------------------------------------
// auris_btn_init
// ---------------------------------------------------------------------------
esp_err_t auris_btn_init(void)
{
    s_btns[0] = (btn_state_t){ .pin = AURIS_BTN_PIN_VOL_UP };
    s_btns[1] = (btn_state_t){ .pin = AURIS_BTN_PIN_VOL_DN };
    s_btns[2] = (btn_state_t){ .pin = AURIS_BTN_PIN_MODE   };

    uint64_t mask = 0;
    for (int i = 0; i < 3; i++) mask |= (1ULL << s_btns[i].pin);

    gpio_config_t cfg = {
        .pin_bit_mask = mask,
        .mode         = GPIO_MODE_INPUT,
        .pull_up_en   = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE,
    };
    esp_err_t r = gpio_config(&cfg);
    if (r != ESP_OK) {
        ESP_LOGE(TAG, "gpio_config: %s", esp_err_to_name(r));
        return r;
    }
    ESP_LOGI(TAG, "Buttons initialized: UP=%d DN=%d MODE=%d",
             AURIS_BTN_PIN_VOL_UP, AURIS_BTN_PIN_VOL_DN, AURIS_BTN_PIN_MODE);
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// Process one button; emit short/long events as appropriate.
// Returns the most recent event for this button (or BTN_EVT_NONE).
// ---------------------------------------------------------------------------
static button_event_t auris_btn_poll_one(btn_state_t *b, button_event_t short_evt, button_event_t long_evt, int is_mode)
{
    button_event_t out = BTN_EVT_NONE;
    bool raw_pressed = (gpio_get_level(b->pin) == 0);  // active low

    if (raw_pressed) {
        if (b->cnt < 255) b->cnt++;
    } else {
        b->cnt = 0;
    }

    // Stable transition: released -> pressed
    if (raw_pressed && b->cnt >= AURIS_BTN_DEBOUNCE_TICKS && b->stable == 1) {
        b->stable       = 0;
        b->pressed      = 1;
        b->press_tick   = xTaskGetTickCount();
        b->last_repeat  = b->press_tick;
        b->long_emitted = 0;
        b->cnt          = 0;
        out = short_evt;
    }
    // Stable transition: pressed -> released
    else if (!raw_pressed && b->stable == 0) {
        b->stable = 1;
        b->pressed = 0;
        b->long_emitted = 0;
        // (short_evt was already emitted on the rising edge)
    }

    // Long-press handling
    if (b->pressed) {
        TickType_t now = xTaskGetTickCount();
        TickType_t held_ms = (now - b->press_tick) * portTICK_PERIOD_MS;
        if (is_mode) {
            if (!b->long_emitted && held_ms >= AURIS_BTN_MODE_LONG_MS) {
                b->long_emitted = 1;
                out = BTN_EVT_MODE_LONG;
            }
        } else {
            if (held_ms >= AURIS_BTN_LONG_PRESS_MS) {
                TickType_t since = (now - b->last_repeat) * portTICK_PERIOD_MS;
                if (since >= AURIS_BTN_LONG_REPEAT_MS) {
                    b->last_repeat = now;
                    out = long_evt;
                }
            }
        }
    }
    return out;
}

// ---------------------------------------------------------------------------
// auris_btn_tick
// ---------------------------------------------------------------------------
button_event_t auris_btn_tick(void)
{
    button_event_t e1 = auris_btn_poll_one(&s_btns[0], BTN_EVT_VOL_UP,   BTN_EVT_VOL_UP_LONG,   0);
    button_event_t e2 = auris_btn_poll_one(&s_btns[1], BTN_EVT_VOL_DOWN, BTN_EVT_VOL_DOWN_LONG, 0);
    button_event_t e3 = auris_btn_poll_one(&s_btns[2], BTN_EVT_MODE,     BTN_EVT_MODE_LONG,     1);

    // Priority: MODE_LONG > anything else, then MODE > VOL.
    if (e3 == BTN_EVT_MODE_LONG) return BTN_EVT_MODE_LONG;
    if (e3 != BTN_EVT_NONE)      return e3;
    if (e1 != BTN_EVT_NONE)      return e1;
    return e2;
}
