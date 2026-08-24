// =============================================================================
// File:        audio_driver.h
// Project:     Project Auris
// Description: I2S driver for the ESP32<->FPGA audio link. Uses the new
//              ESP-IDF v5.x "standard" mode (driver/i2s_std.h) with the
//              APLL as clock source and 24-bit data packed into 32-bit
//              slots (Philips standard). MCLK is not driven (the FPGA
//              synthesizes its own internal clocks from BCLK/LRCLK).
//
// DMA layout: 4 descriptors * 48 frames = 4 ms total end-to-end latency.
//
// Error counters (overflow/underflow) are maintained as atomic 32-bit
// values, incremented from the I2S event callback. monitor_task reads and
// resets them once per 200 ms tick to implement the 1000-in-10s threshold.
// =============================================================================
#ifndef AURIS_AUDIO_DRIVER_H
#define AURIS_AUDIO_DRIVER_H

#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// Pin assignments
#define AURIS_I2S_PIN_BCLK   14
#define AURIS_I2S_PIN_LRCK   15
#define AURIS_I2S_PIN_ADC    2     // FPGA -> ESP32 (data in)
#define AURIS_I2S_PIN_DAC    4     // ESP32 -> FPGA (data out)

// Audio format
#define AURIS_AUDIO_SAMPLE_RATE_HZ  48000
#define AURIS_AUDIO_BCLK_HZ         (64 * AURIS_AUDIO_SAMPLE_RATE_HZ)
#define AURIS_AUDIO_DMA_DESC_NUM    4
#define AURIS_AUDIO_DMA_FRAME_NUM   48

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------
esp_err_t auris_audio_init   (void);
esp_err_t auris_audio_start  (void);
esp_err_t auris_audio_stop   (void);

// Blocking read/write. `timeout_ms` may be 0 to wait forever.
esp_err_t auris_audio_read  (void *buf, size_t bytes, size_t *bytes_read,    uint32_t timeout_ms);
esp_err_t auris_audio_write (const void *buf, size_t bytes, size_t *bytes_written, uint32_t timeout_ms);

// Returns and atomically resets the running overflow/underflow error total.
uint32_t auris_audio_error_count_and_reset(void);

// Stop, re-init, and start again. Used when the error rate is too high.
esp_err_t auris_audio_restart(void);

#ifdef __cplusplus
}
#endif

#endif // AURIS_AUDIO_DRIVER_H
