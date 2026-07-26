// =============================================================================
// File:        fpga_config.c
// Project:     Project Auris
// Description: High-level FPGA configuration API. All accessors are thin
//              wrappers around auris_spi_* and assume they run inside
//              spi_task (the only context that may touch the SPI bus).
//
//              Gain-table upload strategy (M8: uses FPGA auto-increment):
//                1. Read the current active bank (REG_GAIN_BANK).
//                2. Compute the inactive bank index.
//                3. Set REG_GAIN_BANK to point at the inactive bank.
//                4. Write REG_GAIN_ADDR=0 once; subsequent writes to
//                   REG_GAIN_DATA auto-increment the FPGA's internal
//                   address pointer (see reg_file.sv: writing
//                   REG_GAIN_DATA also bumps REG_GAIN_ADDR).
//                5. Stream 128 data words via REG_GAIN_DATA.
//                6. Pulse REG_GAIN_COMMIT with the inactive bank id; the
//                   FPGA atomically swaps the active bank to point at it.
//                7. Restore REG_GAIN_BANK to the original active bank so
//                   subsequent writes don't disturb live audio.
//
//              Total transactions: 1 (read bank) + 1 (set inactive bank)
//                + 1 (set addr=0) + 128 (data) + 1 (commit) + 1 (restore)
//                = 133 transactions per table upload (~43 us at 10 MHz).
// =============================================================================
#include "fpga_config.h"
#include "spi_master.h"
#include "esp_log.h"
#include <string.h>

static const char *TAG = "fpga_config";

// ---------------------------------------------------------------------------
// auris_fpga_init
// ---------------------------------------------------------------------------
esp_err_t auris_fpga_init(void)
{
    // No-op: REG_CONTROL wake is performed by auris_push_initial_config_direct()
    // in main.c BEFORE tasks are created. Once tasks run, the queue is the
    // sole SPI path.
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// Generic accessors
// ---------------------------------------------------------------------------
esp_err_t auris_fpga_reg_read(uint8_t addr, uint32_t *out)
{
    if (!out) return ESP_ERR_INVALID_ARG;
    return auris_spi_read(addr, out);
}

esp_err_t auris_fpga_reg_write(uint8_t addr, uint32_t value)
{
    return auris_spi_write(addr, value & 0xFFFFFFu);
}

// ---------------------------------------------------------------------------
// Typed setters
// ---------------------------------------------------------------------------
esp_err_t auris_fpga_set_mode(uint8_t mode)
{
    return auris_fpga_reg_write(REG_MODE, mode & 0x3u);
}

esp_err_t auris_fpga_set_volume(uint8_t vol)
{
    if (vol > 31) vol = 31;
    return auris_fpga_reg_write(REG_VOLUME, vol);
}

esp_err_t auris_fpga_set_noise_floor(uint8_t nf)
{
    // M11: send as 16-bit Q2.14 (left-aligned in 24 bits via << 8).
    // The 8-bit input is treated as the upper byte of a 16-bit Q2.14
    // value, so input 0xFF produces 0xFF00 (~1.0) at the FPGA.
    return auris_fpga_reg_write(REG_NOISE_FLOOR, ((uint32_t)nf) << 8);
}

esp_err_t auris_fpga_set_gate_ratio(uint8_t ratio)
{
    // M12: send as 16-bit Q2.14 (left-aligned in 24 bits via << 8).
    return auris_fpga_reg_write(REG_NOISE_GATE_RATIO, ((uint32_t)ratio) << 8);
}

esp_err_t auris_fpga_set_drc_threshold(uint32_t thr)
{
    // M13: 12-bit Q2.14, left-aligned in 24 bits.
    // The 12-bit input occupies bits 23:12; bits 11:0 are zero.  This
    // matches the FPGA's expected 16-bit Q2.14 layout (high 12 bits
    // of the 16-bit value, then <<8 to fill 24-bit field).
    return auris_fpga_reg_write(REG_DRC_THRESHOLD, (thr & 0xFFFu) << 12);
}

esp_err_t auris_fpga_set_drc_ratio(uint8_t ratio)
{
    if (ratio == 0) ratio = 1;
    if (ratio > 16) ratio = 16;
    // M14: 5-bit ratio, left-aligned in 24 bits (occupies bits 23:19).
    return auris_fpga_reg_write(REG_DRC_RATIO, ((uint32_t)(ratio & 0x1Fu)) << 19);
}

esp_err_t auris_fpga_set_master_gain(uint16_t q14)
{
    // M15: full 16-bit Q2.14, NOT 14-bit.  Previous code masked with
    // 0x3FFF which capped the gain at ~0.5×; the new mask is 0xFFFF
    // (full 16-bit Q2.14 range, max 1.99994×).  Left-aligned in 24
    // bits via << 8 to match the FPGA's expected encoding.
    return auris_fpga_reg_write(REG_MASTER_GAIN, ((uint32_t)q14) << 8);
}

esp_err_t auris_fpga_set_control(uint32_t bits)
{
    return auris_fpga_reg_write(REG_CONTROL, bits & 0xFFu);
}

// ---------------------------------------------------------------------------
// Gain-table upload
// ---------------------------------------------------------------------------
// M8: leverage the FPGA's REG_GAIN_DATA auto-increment.  The reg_file
// auto-increments REG_GAIN_ADDR on every REG_GAIN_DATA write, so the
// ESP32 only needs to set REG_GAIN_ADDR=0 once and then stream 128
// REG_GAIN_DATA writes.  This halves the SPI traffic compared to the
// per-bin (addr, data) sequence.
esp_err_t auris_fpga_write_gain_table(const int16_t *table_q14, size_t len)
{
    if (!table_q14)                  return ESP_ERR_INVALID_ARG;
    if (len == 0 || len > AURIS_NUM_GAIN_BINS) return ESP_ERR_INVALID_ARG;

    // Determine the active bank so we can target the other one.
    uint32_t active = 0;
    esp_err_t r = auris_fpga_reg_read(REG_GAIN_BANK, &active);
    if (r != ESP_OK) return r;
    uint8_t inactive = (active == 0) ? 1 : 0;

    // Point the FPGA's gain-bus at the inactive bank.
    r = auris_fpga_reg_write(REG_GAIN_BANK, inactive);
    if (r != ESP_OK) return r;

    // M8: set the auto-increment counter to 0; the FPGA will bump it on
    // every REG_GAIN_DATA write.
    r = auris_fpga_reg_write(REG_GAIN_ADDR, 0);
    if (r != ESP_OK) return r;

    // Stream `len` data words. The FPGA's REG_GAIN_ADDR counter is
    // post-incremented on every REG_GAIN_DATA write, so we do not need
    // to (and must not) re-write REG_GAIN_ADDR between bins.
    for (size_t i = 0; i < len; i++) {
        // Q2.14 -> 16-bit signed -> mask to 16 bits on the wire.
        uint16_t bin = (uint16_t)table_q14[i];
        r = auris_fpga_reg_write(REG_GAIN_DATA, bin);
        if (r != ESP_OK) return r;
    }

    // Commit triggers the atomic bank swap.
    r = auris_fpga_reg_write(REG_GAIN_COMMIT, inactive);
    if (r != ESP_OK) return r;

    // Restore the GAIN_BANK pointer to the originally active bank.
    return auris_fpga_reg_write(REG_GAIN_BANK, active & 1u);
}

esp_err_t auris_fpga_commit_gain_bank(uint8_t bank)
{
    if (bank >= AURIS_NUM_GAIN_BANKS) return ESP_ERR_INVALID_ARG;
    return auris_fpga_reg_write(REG_GAIN_COMMIT, bank);
}

// ---------------------------------------------------------------------------
// Telemetry readback
// ---------------------------------------------------------------------------
esp_err_t auris_fpga_read_version(uint32_t *out)
{
    return auris_fpga_reg_read(REG_VERSION, out);
}

esp_err_t auris_fpga_read_peak_in(uint32_t *out)
{
    return auris_fpga_reg_read(REG_PEAK_LEVEL, out);
}

esp_err_t auris_fpga_read_peak_out(uint32_t *out)
{
    return auris_fpga_reg_read(REG_OUT_PEAK, out);
}

esp_err_t auris_fpga_read_frame_count(uint32_t *out)
{
    if (!out) return ESP_ERR_INVALID_ARG;
    uint32_t lo = 0, hi = 0;
    esp_err_t r = auris_fpga_reg_read(REG_FRAME_COUNT_L, &lo);
    if (r != ESP_OK) return r;
    r = auris_fpga_reg_read(REG_FRAME_COUNT_H, &hi);
    if (r != ESP_OK) return r;
    // M16: REG_FRAME_COUNT_H is 8 bits wide on the FPGA (returns
    // frame_count[31:24] in the low 8 bits of the read response;
    // bits 23:8 of the response are 0).  Mask to 8 bits to match.
    *out = ((hi & 0xFFu) << 24) | (lo & 0xFFFFFFu);
    return ESP_OK;
}

esp_err_t auris_fpga_read_error_flags(uint32_t *out)
{
    // M9: REG_ERROR_FLAGS is write-1-to-clear on the FPGA side.  The
    // canonical host idiom is "read, then write-back the same value",
    // which clears every bit that was 1 in the read.  Bits that have
    // become 1 between the read and the write are preserved (the FPGA
    // implements a true W1C, not a register-clear on write).
    if (!out) return ESP_ERR_INVALID_ARG;
    esp_err_t r = auris_fpga_reg_read(REG_ERROR_FLAGS, out);
    if (r != ESP_OK) return r;
    if (*out != 0) {
        r = auris_fpga_reg_write(REG_ERROR_FLAGS, *out);
        if (r != ESP_OK) return r;
    }
    return ESP_OK;
}
