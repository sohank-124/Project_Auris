// =============================================================================
// File:        telemetry.h
// Project:     Project Auris
// Description: FPGA telemetry snapshotter. Each auris_telem_tick() call
//              polls the FPGA's readback registers (PEAK_LEVEL, OUT_PEAK,
//              FRAME_COUNT, ERROR_FLAGS) through the SPI queue and fills
//              the provided snapshot. Frame count is reconstructed from
//              FRAME_COUNT_L and FRAME_COUNT_H into a single 32-bit value.
// =============================================================================
#ifndef AURIS_TELEMETRY_H
#define AURIS_TELEMETRY_H

#include <stdint.h>
#include "esp_err.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "spi_master.h"         // auris_spi_request_t

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t frame_count;
    uint32_t peak_in;
    uint32_t peak_out;
    uint32_t error_flags;
    uint32_t version;
} auris_telem_snapshot_t;

esp_err_t auris_telem_init (QueueHandle_t spi_q);
void      auris_telem_tick (auris_telem_snapshot_t *snap);

#ifdef __cplusplus
}
#endif

#endif // AURIS_TELEMETRY_H
