// =============================================================================
// File:        main.c
// Project:     Project Auris — ESP32 firmware
// Description: Top-level entry point. Owns the global state machine, event
//              group, and IPC queues, then creates the 8 FreeRTOS tasks
//              defined in the architecture spec.
//
//              Task layout:
//                # Name             Stack  Prio  Core  Purpose
//                1 audio_task        2048   20    1   I2S clock feeder (no data path; M17)
//                2 button_task       2048    5    0   Debounce + dispatch
//                3 mode_task         3072    4    0   Mode/volume FSM
//                4 spi_task          2048    6    0   Serialized SPI access
//                5 monitor_task      3072    3    0   Telemetry + battery
//                6 led_task          2048    2    0   LED pattern engine
//                7 profile_task      3072    1    0   Debounced NVS write
//                8 idle_feed_task    1024    0    1   Core-1 WDT feeder
//
//              IPC:
//                button_task -> [button_q] -> mode_task
//                mode_task,monitor_task -> [spi_q] -> spi_task
//                                                 (response via task notify)
//                mode_task,monitor_task -> [led_q]  -> led_task
//                mode_task  -> [profile_q] -> profile_task
// =============================================================================
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/event_groups.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_task_wdt.h"
#include "nvs_flash.h"

#include "app_state.h"
#include "ipc.h"
#include "button_handler.h"
#include "mode_manager.h"
#include "volume_ctrl.h"
#include "spi_master.h"
#include "fpga_config.h"
#include "audio_driver.h"
#include "led_indicator.h"
#include "profile_store.h"
#include "battery_mon.h"
#include "telemetry.h"
#include "bt_audio.h"

static const char *TAG = "main";

// ---------------------------------------------------------------------------
// Global IPC handles (declared extern in ipc.h)
// ---------------------------------------------------------------------------
EventGroupHandle_t g_event_group    = NULL;
QueueHandle_t      g_button_q       = NULL;
QueueHandle_t      g_spi_q          = NULL;
QueueHandle_t      g_led_q          = NULL;
QueueHandle_t      g_profile_q      = NULL;

// ---------------------------------------------------------------------------
// State machine state
// ---------------------------------------------------------------------------
static volatile auris_state_t s_state = AURIS_STATE_BOOT;
static volatile uint8_t      s_err_streak = 0;  // consecutive ERROR entries
static volatile uint8_t      s_fpga_probe_retry = 0;

// Mutex protecting s_state and s_err_streak. Created in app_main before
// any task that observes the state machine is spawned (H1).
static SemaphoreHandle_t     s_state_mutex = NULL;

// ---------------------------------------------------------------------------
// State helpers (declared in app_state.h)
// ---------------------------------------------------------------------------
const char *auris_state_name(auris_state_t s)
{
    switch (s) {
        case AURIS_STATE_BOOT:    return "BOOT";
        case AURIS_STATE_INIT:    return "INIT";
        case AURIS_STATE_RUNNING: return "RUNNING";
        case AURIS_STATE_ERROR:   return "ERROR";
        case AURIS_STATE_SLEEP:   return "SLEEP";
        default:                  return "?";
    }
}

auris_state_t auris_app_state_get(void)
{
    auris_state_t s = AURIS_STATE_BOOT;
    if (s_state_mutex && xSemaphoreTake(s_state_mutex, pdMS_TO_TICKS(50)) == pdTRUE) {
        s = s_state;
        xSemaphoreGive(s_state_mutex);
    }
    return s;
}

void auris_app_state_set(auris_state_t s)
{
    if (s_state_mutex && xSemaphoreTake(s_state_mutex, pdMS_TO_TICKS(50)) != pdTRUE) {
        ESP_LOGW(TAG, "auris_app_state_set: state mutex unavailable");
        return;
    }
    if (s == s_state) {
        if (s_state_mutex) xSemaphoreGive(s_state_mutex);
        return;
    }
    ESP_LOGI(TAG, "State: %s -> %s", auris_state_name(s_state), auris_state_name(s));
    s_state = s;
    if (s == AURIS_STATE_ERROR) {
        s_err_streak++;
        xEventGroupSetBits(g_event_group, AURIS_EVT_ERROR);
        if (s_err_streak >= 3) {
            if (s_state_mutex) xSemaphoreGive(s_state_mutex);
            ESP_LOGE(TAG, "3 consecutive ERROR entries, restarting in 1s");
            vTaskDelay(pdMS_TO_TICKS(1000));
            esp_restart();
        }
    } else {
        // Reset the error streak on ANY transition out of ERROR (H2).
        s_err_streak = 0;
        xEventGroupClearBits(g_event_group, AURIS_EVT_ERROR);
    }
    if (s_state_mutex) xSemaphoreGive(s_state_mutex);
}

bool auris_app_state_is(auris_state_t s)
{
    return auris_app_state_get() == s;
}

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------
static void audio_task      (void *arg);
static void button_task     (void *arg);
static void mode_task       (void *arg);
static void spi_task        (void *arg);
static void monitor_task    (void *arg);
static void led_task        (void *arg);
static void profile_task    (void *arg);
static void idle_feed_task  (void *arg);

static esp_err_t auris_init_peripherals(void);
static esp_err_t auris_probe_fpga_direct(void);
static esp_err_t auris_push_initial_config_direct(void);

// ---------------------------------------------------------------------------
// app_main
//
// Boot sequence (C2):
//   1. NVS init, profile init, SPI init
//   2. Allocate the SPI queue (handle only — must not be used yet)
//   3. Probe FPGA via DIRECT auris_spi_read — 3 retries, 1s apart
//   4. If probe fails: factory-reset NVS, set ERROR state
//   5. Init peripherals (I2S, buttons, LEDs, volume, mode)
//   6. Push initial FPGA config via DIRECT auris_spi_write calls
//      (REG_CONTROL, REG_MODE, REG_VOLUME, gain table)
//   7. Start audio DMA
//   8. Set RUNNING state
//   9. Create all 8 tasks (spi_task will own all future SPI access)
//
//   Direct SPI access is safe in steps 3-8 because no FreeRTOS task is
//   running and therefore no other code path can touch the bus. Once
//   spi_task starts, the g_spi_q is the sole SPI entry point.
// ---------------------------------------------------------------------------
void app_main(void)
{
    ESP_LOGI(TAG, "=========================================");
    ESP_LOGI(TAG, " Project Auris firmware v0.1.0 booting...");
    ESP_LOGI(TAG, "=========================================");

    // 1. State mutex (used by auris_app_state_get / _set) and global
    //    event group.
    s_state_mutex = xSemaphoreCreateMutex();
    if (!s_state_mutex) {
        ESP_LOGE(TAG, "xSemaphoreCreateMutex(state) failed; restarting");
        esp_restart();
    }
    g_event_group = xEventGroupCreate();
    if (!g_event_group) {
        ESP_LOGE(TAG, "xEventGroupCreate failed; restarting");
        esp_restart();
    }

    // 2. Allocate IPC queue handles up front so they're available the
    //    moment tasks are created. They MUST NOT be used for SPI traffic
    //    until spi_task exists — see the C2 boot sequence above (H4).
    g_button_q    = xQueueCreate(8, sizeof(button_event_t));
    g_spi_q       = xQueueCreate(8, sizeof(auris_spi_request_t));
    g_led_q       = xQueueCreate(4, sizeof(auris_led_command_t));
    g_profile_q   = xQueueCreate(4, sizeof(auris_profile_save_request_t));
    if (!g_button_q || !g_spi_q || !g_led_q || !g_profile_q) {
        ESP_LOGE(TAG, "xQueueCreate failed (button=%p spi=%p led=%p profile=%p); restarting",
                 (void*)g_button_q, (void*)g_spi_q, (void*)g_led_q, (void*)g_profile_q);
        esp_restart();
    }

    // 3. NVS flash (required by profile_store)
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_LOGW(TAG, "NVS erase required: %s", esp_err_to_name(ret));
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // 4. Profile store: handles boot_cnt and err_cnt; may factory-reset on
    //    err_cnt >= 3.
    ESP_ERROR_CHECK(auris_profile_init());

    // 5. Initialize SPI bus. auris_fpga_init() is a no-op (the CONTROL
    //    wake is now performed by auris_push_initial_config_direct()
    //    further below, where direct SPI access is also still safe).
    ESP_ERROR_CHECK(auris_spi_init());
    ESP_ERROR_CHECK(auris_fpga_init());

    // 6. Probe FPGA version via DIRECT SPI; retry up to 3x with 1s
    //    back-off. No queue is used — spi_task doesn't exist yet.
    auris_app_state_set(AURIS_STATE_BOOT);
    s_fpga_probe_retry = 0;
    bool probe_ok = false;
    while (s_fpga_probe_retry < 3) {
        if (auris_probe_fpga_direct() == ESP_OK) {
            probe_ok = true;
            break;
        }
        s_fpga_probe_retry++;
        ESP_LOGW(TAG, "FPGA probe attempt %u/3 failed", (unsigned)(s_fpga_probe_retry + 1));
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
    if (!probe_ok) {
        ESP_LOGE(TAG, "FPGA probe failed 3x -> factory-reset NVS then ERROR");
        auris_profile_factory_reset();
        auris_app_state_set(AURIS_STATE_ERROR);
        // Stay in ERROR: monitor_task (once created) will keep retrying.
        // We still create the 8 tasks so the LED pattern engine can drive
        // the user-visible error indication.
    }

    // 7. Initialize remaining peripherals (I2S, buttons, LEDs, volume,
    //    mode). auris_mode_init restores the persisted mode from NVS.
    if (!probe_ok || auris_init_peripherals() != ESP_OK) {
        if (probe_ok) {
            auris_app_state_set(AURIS_STATE_ERROR);
        }
    } else {
        auris_app_state_set(AURIS_STATE_INIT);

        // 8. Push initial FPGA configuration using DIRECT SPI writes
        //    (still pre-spi_task). This writes REG_CONTROL, REG_MODE,
        //    REG_DRC_*, REG_NOISE_FLOOR, REG_VOLUME, and the gain table.
        if (auris_push_initial_config_direct() != ESP_OK) {
            ESP_LOGE(TAG, "Failed initial FPGA config");
            auris_app_state_set(AURIS_STATE_ERROR);
        } else {
            // 9. Start audio DMA
            if (auris_audio_start() != ESP_OK) {
                ESP_LOGE(TAG, "Failed to start audio");
                auris_app_state_set(AURIS_STATE_ERROR);
            } else {
                xEventGroupSetBits(g_event_group, AURIS_EVT_AUDIO_RUNNING);
                auris_app_state_set(AURIS_STATE_RUNNING);
            }
        }
    }

    // 10. Subscribe to task watchdog for the long-running tasks
    esp_task_wdt_config_t twdt_cfg = {
        .timeout_ms     = 5000,
        .idle_core_mask = 0,           // we feed the watchdog explicitly
        .trigger_panic  = true,
    };
    ESP_ERROR_CHECK(esp_task_wdt_init(&twdt_cfg));

    // 11. Create the 8 FreeRTOS tasks
    ESP_LOGI(TAG, "Creating FreeRTOS tasks...");
    // H3/M17: audio_task no longer holds a 1024-byte I2S buffer (the
    // loopback was removed); stack can be reduced to 2048.
    xTaskCreatePinnedToCore(audio_task,     "audio",      2048, NULL, 20, NULL, 1);
    xTaskCreatePinnedToCore(button_task,    "button",     2048, NULL,  5, NULL, 0);
    xTaskCreatePinnedToCore(mode_task,      "mode",       3072, NULL,  4, NULL, 0);
    xTaskCreatePinnedToCore(spi_task,       "spi",        2048, NULL,  6, NULL, 0);
    xTaskCreatePinnedToCore(monitor_task,   "monitor",    3072, NULL,  3, NULL, 0);
    xTaskCreatePinnedToCore(led_task,       "led",        2048, NULL,  2, NULL, 0);
    xTaskCreatePinnedToCore(profile_task,   "profile",    3072, NULL,  1, NULL, 0);
    xTaskCreatePinnedToCore(idle_feed_task, "idle_feed",  1024, NULL,  0, NULL, 1);

    // 12. Bluetooth is a Phase-3 stub; initialize but don't start.
    ESP_ERROR_CHECK(auris_bt_audio_init());

    // 13. Battery monitor + telemetry
    ESP_ERROR_CHECK(auris_batt_init());
    ESP_ERROR_CHECK(auris_telem_init(g_spi_q));

    ESP_LOGI(TAG, "Firmware ready. State = %s", auris_state_name(s_state));
}

// ---------------------------------------------------------------------------
// auris_init_peripherals
// ---------------------------------------------------------------------------
static esp_err_t auris_init_peripherals(void)
{
    esp_err_t r = ESP_OK;
    r |= auris_audio_init();
    r |= auris_btn_init();
    r |= auris_led_init();
    r |= auris_vol_init(g_spi_q, g_led_q, g_profile_q);
    r |= auris_mode_init(g_spi_q, g_led_q, g_profile_q);
    return r;
}

// ---------------------------------------------------------------------------
// auris_probe_fpga_direct — read REG_VERSION using a direct SPI call
//
// Safe to call from app_main before spi_task exists. The bus is unused at
// this point, so no locking or queue indirection is needed.
// ---------------------------------------------------------------------------
static esp_err_t auris_probe_fpga_direct(void)
{
    uint32_t version = 0;
    esp_err_t r = auris_spi_read(REG_VERSION, &version);
    if (r != ESP_OK) {
        ESP_LOGE(TAG, "probe: SPI read failed: %s", esp_err_to_name(r));
        return r;
    }
    if (version == 0 || version == 0x7FFFFFu) {
        ESP_LOGE(TAG, "probe: bad version 0x%06lx", (unsigned long)version);
        return ESP_FAIL;
    }
    ESP_LOGI(TAG, "FPGA version: 0x%06lx", (unsigned long)version);
    xEventGroupSetBits(g_event_group, AURIS_EVT_FPGA_CONNECTED);
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// auris_push_initial_config_direct — initial REG_CONTROL, REG_MODE, etc.
//
// Mirrors the register sequence that auris_mode_apply_current() would
// perform, but uses direct SPI calls because spi_task does not exist yet.
// Once tasks are running, auris_mode_apply_current() is the canonical
// path; this function is the boot-only equivalent.
// ---------------------------------------------------------------------------
static esp_err_t auris_push_initial_config_direct(void)
{
    // DSP enable first so the FPGA leaves reset.
    esp_err_t r = auris_spi_write(REG_CONTROL, 0x1);
    if (r != ESP_OK) return r;

    // Delegate the rest to mode_manager, which already owns the per-mode
    // register table and gain-table upload logic. auris_mode_apply_current
    // is queue-based, so it must NOT be called here; instead, we go through
    // a direct-SPI variant in mode_manager (declared in mode_manager.h).
    return auris_mode_apply_current_direct();
}

// ===========================================================================
// TASK 1: audio_task  (core 1, prio 20)
//
// M17: The ESP32 is NOT in the audio data path.  Audio flows
// INMP441 -> FPGA I2S RX -> DSP -> FPGA I2S TX -> PCM5102A.
// The ESP32 only generates the I2S bit/word clocks (BCLK = 3.072 MHz,
// LRCLK = 48 kHz) for the FPGA, which uses them to clock its own I2S
// RX and TX.  This task previously performed a zero-copy I2S RX->TX
// loopback through the ESP32's I2S data pins (GPIO2, GPIO4), but those
// pins are not connected to the audio path on the Cmod S7-25 — the
// FPGA owns the I2S data.  The loopback is therefore disabled; this
// task now only feeds the watchdog and the I2S driver continues to
// run (for clock generation) without any data movement.
// ===========================================================================
static void audio_task(void *arg)
{
    (void)arg;
    ESP_ERROR_CHECK(esp_task_wdt_add(NULL));
    ESP_LOGI(TAG, "audio_task started on core %d (clock-only; no data path)",
             xPortGetCoreID());

    for (;;) {
        // Idle: the I2S driver runs autonomously to maintain BCLK/LRCLK.
        // We only need to feed the watchdog.
        vTaskDelay(pdMS_TO_TICKS(100));
        esp_task_wdt_reset();
    }
}

// ===========================================================================
// TASK 2: button_task  (core 0, prio 5, 10 ms tick)
//
// Reads three GPIOs, debounces (5-sample = 50 ms), and detects long-press.
// Posts events to g_button_q for mode_task.
// ===========================================================================
static void button_task(void *arg)
{
    (void)arg;
    ESP_ERROR_CHECK(esp_task_wdt_add(NULL));
    ESP_LOGI(TAG, "button_task started on core %d", xPortGetCoreID());
    TickType_t last = xTaskGetTickCount();
    for (;;) {
        button_event_t evt = auris_btn_tick();
        if (evt != BTN_EVT_NONE) {
            // Non-blocking enqueue: drop on overflow
            if (xQueueSend(g_button_q, &evt, 0) != pdTRUE) {
                ESP_LOGW(TAG, "button_q full, dropping event");
            }
        }
        vTaskDelayUntil(&last, pdMS_TO_TICKS(10));
        esp_task_wdt_reset();
    }
}

// ===========================================================================
// TASK 3: mode_task  (core 0, prio 4)
//
// Consumes button events; updates mode/volume state, dispatches SPI writes
// to spi_task (blocking on task notification), LED feedback, and NVS save
// requests.
// ===========================================================================
static void mode_task(void *arg)
{
    (void)arg;
    ESP_ERROR_CHECK(esp_task_wdt_add(NULL));
    ESP_LOGI(TAG, "mode_task started on core %d", xPortGetCoreID());

    button_event_t evt;
    for (;;) {
        if (xQueueReceive(g_button_q, &evt, pdMS_TO_TICKS(1000)) == pdTRUE) {
            switch (evt) {
                case BTN_EVT_MODE:
                    auris_mode_cycle();
                    break;
                case BTN_EVT_VOL_UP:
                case BTN_EVT_VOL_UP_LONG:
                    auris_vol_step(+1);
                    break;
                case BTN_EVT_VOL_DOWN:
                case BTN_EVT_VOL_DOWN_LONG:
                    auris_vol_step(-1);
                    break;
                case BTN_EVT_MODE_LONG:
                    ESP_LOGI(TAG, "MODE long-press -> SLEEP (Phase 3 stub)");
                    auris_app_state_set(AURIS_STATE_SLEEP);
                    break;
                default: break;
            }
        } else {
            // 1s idle: check event group for housekeeping
            EventBits_t bits = xEventGroupGetBits(g_event_group);
            if (bits & AURIS_EVT_ERROR) {
                // Handled in monitor_task
            }
        }
        esp_task_wdt_reset();
    }
}

// ===========================================================================
// TASK 4: spi_task  (core 0, prio 6)
//
// Serializes all SPI access via g_spi_q. Each request carries a caller handle;
// on completion, xTaskNotifyGive() wakes the caller (request-response).
// ===========================================================================
static void spi_task(void *arg)
{
    (void)arg;
    ESP_ERROR_CHECK(esp_task_wdt_add(NULL));
    ESP_LOGI(TAG, "spi_task started on core %d", xPortGetCoreID());
    auris_spi_request_t req;
    for (;;) {
        if (xQueueReceive(g_spi_q, &req, portMAX_DELAY) == pdTRUE) {
            switch (req.kind) {
                case AURIS_SPI_REQ_WRITE:
                    auris_spi_write(req.addr, req.data);
                    break;
                case AURIS_SPI_REQ_READ:
                    if (req.result_ptr) {
                        auris_spi_read(req.addr, req.result_ptr);
                    }
                    break;
                case AURIS_SPI_REQ_BULK:
                    auris_spi_bulk_write(req.bulk_addrs, req.bulk_vals, req.bulk_count);
                    break;
            }
            if (req.caller) {
                xTaskNotifyGive(req.caller);
            }
        }
        esp_task_wdt_reset();
    }
}

// ===========================================================================
// TASK 5: monitor_task  (core 0, prio 3, 200 ms tick)
//
// Polls FPGA telemetry, battery ADC, and I2S error counters. Drives LED
// pattern transitions on FPGA stall / low battery / audio error bursts.
// ===========================================================================
static void monitor_task(void *arg)
{
    (void)arg;
    ESP_ERROR_CHECK(esp_task_wdt_add(NULL));
    ESP_LOGI(TAG, "monitor_task started on core %d", xPortGetCoreID());
    TickType_t last = xTaskGetTickCount();

    // Cross-iteration state
    uint32_t   last_frame_count     = 0;
    TickType_t last_frame_advance   = 0;
    uint32_t   err_window           = 0;
    TickType_t err_window_start     = 0;
    uint8_t    batt_tick_counter    = 0;     // 1 Hz sampling (every 5 ticks)

    for (;;) {
        // Snapshot FPGA telemetry
        auris_telem_snapshot_t snap;
        auris_telem_tick(&snap);

        // FPGA stall detection
        TickType_t now = xTaskGetTickCount();
        if (snap.frame_count != last_frame_count) {
            last_frame_count   = snap.frame_count;
            last_frame_advance = now;
        } else if ((now - last_frame_advance) > pdMS_TO_TICKS(2000)) {
            if (auris_app_state_is(AURIS_STATE_RUNNING)) {
                ESP_LOGE(TAG, "FPGA frame count stalled 2s -> ERROR");
                auris_app_state_set(AURIS_STATE_ERROR);
            }
        }

        // I2S error burst detection
        uint32_t errs = auris_audio_error_count_and_reset();
        if (err_window_start == 0) err_window_start = now;
        err_window += errs;
        if ((now - err_window_start) > pdMS_TO_TICKS(10000)) {
            if (err_window > 1000) {
                ESP_LOGE(TAG, "I2S errors %lu in 10s -> restart I2S",
                         (unsigned long)err_window);
                auris_audio_restart();
            }
            err_window      = 0;
            err_window_start = now;
        }

        // Battery: 1 Hz sample (every 5th 200-ms tick)
        if (++batt_tick_counter >= 5) {
            batt_tick_counter = 0;
            (void)auris_batt_sample();
        }

        // Battery low/critical
        if (auris_batt_is_critical()) {
            xEventGroupSetBits(g_event_group, AURIS_EVT_LOW_BATTERY);
            auris_led_command_t lc = { .kind = AURIS_LED_CMD_SET_PATTERN, .pattern = LED_PATTERN_LOW_BATTERY };
            xQueueOverwrite(g_led_q, &lc);
        } else if (auris_batt_is_low()) {
            xEventGroupSetBits(g_event_group, AURIS_EVT_LOW_BATTERY);
        }

        // LED peak update: PEAK is event-like, so use xQueueSend with a
        // 0 timeout. The newest value supersedes any older unprocessed
        // PEAK (one-slot queue acts as a mailbox). We intentionally do
        // NOT use xQueueOverwrite here, because that would let a PEAK
        // overwrite a still-pending SET_PATTERN from mode_task and
        // miss the new pattern notification.
        if (snap.peak_out >= 0x700000) {
            auris_led_command_t lc = { .kind = AURIS_LED_CMD_PEAK, .peak = snap.peak_out };
            xQueueSend(g_led_q, &lc, 0);
        }

        vTaskDelayUntil(&last, pdMS_TO_TICKS(200));
        esp_task_wdt_reset();
    }
}

// ===========================================================================
// TASK 6: led_task  (core 0, prio 2, 20 ms tick)
//
// Pattern engine. Receives LED commands (set pattern, N-blink, peak),
// otherwise ticks the current pattern at 50 Hz (20 ms period).
// ===========================================================================
static void led_task(void *arg)
{
    (void)arg;
    ESP_ERROR_CHECK(esp_task_wdt_add(NULL));
    ESP_LOGI(TAG, "led_task started on core %d", xPortGetCoreID());
    auris_led_command_t cmd;

    // Initial pattern: BOOT
    auris_led_set_state(LED_PATTERN_BOOT);

    for (;;) {
        if (xQueueReceive(g_led_q, &cmd, pdMS_TO_TICKS(20)) == pdTRUE) {
            switch (cmd.kind) {
                case AURIS_LED_CMD_SET_PATTERN:
                    auris_led_set_state(cmd.pattern);
                    break;
                case AURIS_LED_CMD_BLINK_N:
                    auris_led_blink_n(cmd.count);
                    break;
                case AURIS_LED_CMD_PEAK:
                    auris_led_update_peak(cmd.peak);
                    break;
                case AURIS_LED_CMD_OFF:
                    auris_led_off();
                    break;
            }
        }
        auris_led_tick();
        esp_task_wdt_reset();
    }
}

// ===========================================================================
// TASK 7: profile_task  (core 0, prio 1)
//
// Debounces NVS writes: accumulates requests for 500 ms, then writes once.
// ===========================================================================
static void profile_task(void *arg)
{
    (void)arg;
    ESP_ERROR_CHECK(esp_task_wdt_add(NULL));
    ESP_LOGI(TAG, "profile_task started on core %d", xPortGetCoreID());
    auris_profile_save_request_t req;
    TickType_t deadline = 0;
    auris_profile_save_request_t pending = { .kind = (auris_prof_save_kind_t)-1 };
    bool pending_valid = false;

    for (;;) {
        if (xQueueReceive(g_profile_q, &req, pdMS_TO_TICKS(50)) == pdTRUE) {
            // Coalesce: always keep the most recent request. The whole
            // struct is copied verbatim, which is correct for both
            // scalar (mode/volume/error) and blob (gain-table) kinds —
            // the full 128-bin table is small and copying it is cheaper
            // than maintaining a separate "pending kind" tracker.
            pending = req;
            pending_valid = true;
            deadline = xTaskGetTickCount() + pdMS_TO_TICKS(500);
        }
        if (pending_valid && xTaskGetTickCount() >= deadline) {
            esp_err_t r = ESP_OK;
            switch (pending.kind) {
                case AURIS_PROF_SAVE_MODE:
                    r = auris_profile_set_mode(pending.u8);
                    break;
                case AURIS_PROF_SAVE_VOLUME:
                    r = auris_profile_set_volume(pending.u8);
                    break;
                case AURIS_PROF_SAVE_GAIN:
                    r = auris_profile_set_gain_table(pending.table_q14, 128);
                    break;
                case AURIS_PROF_SAVE_ERROR:
                    r = auris_profile_inc_err_cnt();
                    break;
            }
            if (r != ESP_OK) {
                ESP_LOGW(TAG, "NVS write failed: %s", esp_err_to_name(r));
            }
            pending_valid = false;
        }
        esp_task_wdt_reset();
    }
}

// ===========================================================================
// TASK 8: idle_feed_task  (core 1, prio 0)
//
// Resets the task watchdog at 1 Hz to keep the system healthy during idle
// periods on core 1 (audio_task does its own feeding).
// ===========================================================================
static void idle_feed_task(void *arg)
{
    (void)arg;
    ESP_ERROR_CHECK(esp_task_wdt_add(NULL));
    ESP_LOGI(TAG, "idle_feed_task started on core %d", xPortGetCoreID());
    TickType_t last = xTaskGetTickCount();
    for (;;) {
        esp_task_wdt_reset();
        vTaskDelayUntil(&last, pdMS_TO_TICKS(1000));
    }
}
