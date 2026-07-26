// =============================================================================
// File:        audio_driver.c
// Project:     Project Auris
// Description: I2S standard-mode driver. ESP32 is master; FPGA is slave.
//
//              Clock tree:
//                APLL @ 12.288 MHz (256 * 48 kHz)
//                BCLK = 64 * LRCLK = 3.072 MHz
//                LRCLK = 48 kHz
//                MCLK: not driven (mclk = I2S_GPIO_UNUSED)
//
//              Slot format: Philips standard, 24-bit data in 32-bit slot,
//              stereo. The FPGA sees MSB-justified 24-bit samples.
//
//              DMA buffer: 4 descriptors * 48 frames = 4 ms end-to-end.
//              audio_task reads a chunk and writes it back, which is the
//              "zero-copy" loopback the spec requires. In Phase 5 the
//              loopback will be replaced with the FPGA-processed stream
//              (the FPGA itself already does most of the work).
// =============================================================================
#include "audio_driver.h"
#include "driver/i2s_std.h"
#include "esp_log.h"
#include <string.h>
#include <stdatomic.h>

static const char *TAG = "audio_driver";

static i2s_chan_handle_t s_tx_handle = NULL;
static i2s_chan_handle_t s_rx_handle = NULL;
static bool s_running = false;

// Atomic error counters (incremented from I2S event callback context)
static atomic_uint s_err_overflow = 0;
static atomic_uint s_err_underflow = 0;
static atomic_uint s_err_total = 0;

// ---------------------------------------------------------------------------
// I2S event callback
//
// Runs in ISR context; keep it short, only update atomics.
// ---------------------------------------------------------------------------
static bool auris_audio_on_event(i2s_chan_handle_t handle,
                                 i2s_event_data_t *event,
                                 void *user_ctx)
{
    (void)handle; (void)event; (void)user_ctx;
    if (event == NULL) return false;

    i2s_event_type_t type = event->type;
    if (type == I2S_EVENT_TX_Q_OVF || type == I2S_EVENT_RX_Q_OVF) {
        atomic_fetch_add(&s_err_overflow, 1);
        atomic_fetch_add(&s_err_total, 1);
    } else if (type == I2S_EVENT_TX_DONE || type == I2S_EVENT_RX_DONE) {
        // Normal completion — nothing to do
    } else {
        // Anything else counts as a soft error
        atomic_fetch_add(&s_err_total, 1);
    }
    return false;  // do not yield from higher-priority task
}

// ---------------------------------------------------------------------------
// auris_audio_init
// ---------------------------------------------------------------------------
esp_err_t auris_audio_init(void)
{
    if (s_tx_handle || s_rx_handle) return ESP_OK;

    // Channel configuration
    i2s_chan_config_t chan_cfg = {
        .id            = I2S_NUM_0,
        .role          = I2S_ROLE_MASTER,
        .dma_desc_num  = AURIS_AUDIO_DMA_DESC_NUM,
        .dma_frame_num = AURIS_AUDIO_DMA_FRAME_NUM,
        .auto_clear    = true,           // silence TX underrun
    };
    esp_err_t r = i2s_new_channel(&chan_cfg, &s_tx_handle, &s_rx_handle);
    if (r != ESP_OK) {
        ESP_LOGE(TAG, "i2s_new_channel: %s", esp_err_to_name(r));
        return r;
    }

    // Standard mode configuration
    i2s_std_config_t std_cfg = {
        .clk_cfg = {
            .sample_rate_hz = AURIS_AUDIO_SAMPLE_RATE_HZ,
            .clk_src        = I2S_CLK_SRC_APLL,
            .mclk_multiple  = I2S_MCLK_MULTIPLE_256,
        },
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(
                        I2S_DATA_BIT_WIDTH_24BIT,
                        I2S_SLOT_MODE_STEREO),
        .gpio_cfg = {
            .mclk = I2S_GPIO_UNUSED,
            .bclk = AURIS_I2S_PIN_BCLK,
            .ws   = AURIS_I2S_PIN_LRCK,
            .dout = AURIS_I2S_PIN_DAC,
            .din  = AURIS_I2S_PIN_ADC,
            .invert_flags = {
                .mclk_inv = false,
                .bclk_inv = false,
                .ws_inv   = false,
            },
        },
    };

    r = i2s_channel_init_std_mode(s_tx_handle, &std_cfg);
    if (r != ESP_OK) {
        ESP_LOGE(TAG, "i2s_channel_init_std_mode (TX): %s", esp_err_to_name(r));
        return r;
    }
    r = i2s_channel_init_std_mode(s_rx_handle, &std_cfg);
    if (r != ESP_OK) {
        ESP_LOGE(TAG, "i2s_channel_init_std_mode (RX): %s", esp_err_to_name(r));
        return r;
    }

    // Register overflow/underflow callback on both directions
    i2s_event_callbacks_t cbs = {
        .on_recv = auris_audio_on_event,
        .on_send = auris_audio_on_event,
        .on_recv_q_ovf = NULL,
        .on_send_q_ovf = NULL,
    };
    (void)i2s_channel_register_event_callback(s_rx_handle, &cbs, NULL);
    (void)i2s_channel_register_event_callback(s_tx_handle, &cbs, NULL);

    ESP_LOGI(TAG, "I2S master initialized: BCLK=%d Hz LRCLK=%d Hz (APLL)",
             AURIS_AUDIO_BCLK_HZ, AURIS_AUDIO_SAMPLE_RATE_HZ);
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// auris_audio_start
// ---------------------------------------------------------------------------
esp_err_t auris_audio_start(void)
{
    if (!s_tx_handle || !s_rx_handle) return ESP_ERR_INVALID_STATE;
    if (s_running) return ESP_OK;

    esp_err_t r = i2s_channel_enable(s_tx_handle);
    if (r != ESP_OK) {
        ESP_LOGE(TAG, "i2s TX enable: %s", esp_err_to_name(r));
        return r;
    }
    r = i2s_channel_enable(s_rx_handle);
    if (r != ESP_OK) {
        ESP_LOGE(TAG, "i2s RX enable: %s", esp_err_to_name(r));
        i2s_channel_disable(s_tx_handle);
        return r;
    }
    s_running = true;
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// auris_audio_stop
// ---------------------------------------------------------------------------
esp_err_t auris_audio_stop(void)
{
    if (!s_running) return ESP_OK;
    esp_err_t r1 = i2s_channel_disable(s_tx_handle);
    esp_err_t r2 = i2s_channel_disable(s_rx_handle);
    s_running = false;
    return (r1 == ESP_OK) ? r2 : r1;
}

// ---------------------------------------------------------------------------
// auris_audio_read / auris_audio_write
// ---------------------------------------------------------------------------
esp_err_t auris_audio_read(void *buf, size_t bytes, size_t *bytes_read, uint32_t timeout_ms)
{
    if (!s_rx_handle) return ESP_ERR_INVALID_STATE;
    if (!buf)         return ESP_ERR_INVALID_ARG;
    if (bytes == 0) {
        if (bytes_read) *bytes_read = 0;
        return ESP_OK;
    }
    return i2s_channel_read(s_rx_handle, buf, bytes, bytes_read,
                            pdMS_TO_TICKS(timeout_ms));
}

esp_err_t auris_audio_write(const void *buf, size_t bytes, size_t *bytes_written, uint32_t timeout_ms)
{
    if (!s_tx_handle) return ESP_ERR_INVALID_STATE;
    if (!buf)         return ESP_ERR_INVALID_ARG;
    if (bytes == 0) {
        if (bytes_written) *bytes_written = 0;
        return ESP_OK;
    }
    return i2s_channel_write(s_tx_handle, buf, bytes, bytes_written,
                             pdMS_TO_TICKS(timeout_ms));
}

// ---------------------------------------------------------------------------
// auris_audio_error_count_and_reset
// ---------------------------------------------------------------------------
uint32_t auris_audio_error_count_and_reset(void)
{
    uint32_t v = atomic_load(&s_err_total);
    atomic_store(&s_err_total, 0);
    return v;
}

// ---------------------------------------------------------------------------
// auris_audio_restart
// ---------------------------------------------------------------------------
esp_err_t auris_audio_restart(void)
{
    ESP_LOGW(TAG, "Restarting I2S (high error rate)");
    esp_err_t r = auris_audio_stop();
    if (r != ESP_OK && r != ESP_ERR_INVALID_STATE) {
        ESP_LOGW(TAG, "audio_stop during restart: %s", esp_err_to_name(r));
    }
    vTaskDelay(pdMS_TO_TICKS(20));
    // Reset the in-band counters
    atomic_store(&s_err_overflow, 0);
    atomic_store(&s_err_underflow, 0);
    atomic_store(&s_err_total, 0);
    return auris_audio_start();
}
