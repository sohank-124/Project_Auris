// =============================================================================
// File:        fpga_config.h
// Project:     Project Auris
// Description: High-level FPGA configuration API. Wraps spi_master with
//              semantically meaningful calls and defines the register
//              address map shared with the FPGA RTL package
//              (fpga/rtl/pkg/auris_pkg.sv).
//
// All functions in this header assume they are called from spi_task (the
// sole owner of the SPI bus). Direct calls from another context must
// submit a spi_request_t to g_spi_q instead.
// =============================================================================
#ifndef AURIS_FPGA_CONFIG_H
#define AURIS_FPGA_CONFIG_H

#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Register address map (must match fpga/rtl/pkg/auris_pkg.sv)
// ---------------------------------------------------------------------------
#define REG_VERSION           0x00
#define REG_STATUS            0x01
#define REG_CONTROL           0x02
#define REG_MODE              0x03
#define REG_VOLUME            0x04
#define REG_NOISE_FLOOR       0x05
#define REG_NOISE_GATE_RATIO  0x06
#define REG_DRC_THRESHOLD     0x07
#define REG_DRC_RATIO         0x08
#define REG_MASTER_GAIN       0x09
#define REG_GAIN_ADDR         0x10
#define REG_GAIN_DATA         0x11
#define REG_GAIN_BANK         0x12
#define REG_GAIN_COMMIT       0x13
#define REG_PEAK_LEVEL        0x20
#define REG_OUT_PEAK          0x21
#define REG_FRAME_COUNT_L     0x22
#define REG_FRAME_COUNT_H     0x23
#define REG_ERROR_FLAGS       0x24
#define REG_SCRATCH           0x7E
#define REG_LOOPBACK          0x7F

// Gain table: 128 frequency bins (Q2.14 signed)
#define AURIS_NUM_GAIN_BINS   128
#define AURIS_NUM_GAIN_BANKS  2

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------
esp_err_t auris_fpga_init(void);

// Generic register access (callable from spi_task only)
esp_err_t auris_fpga_reg_read (uint8_t addr, uint32_t *out);
esp_err_t auris_fpga_reg_write(uint8_t addr, uint32_t value);

// Typed setters
esp_err_t auris_fpga_set_mode          (uint8_t mode);     // 0..3
esp_err_t auris_fpga_set_volume        (uint8_t vol);      // 0..31
esp_err_t auris_fpga_set_noise_floor   (uint8_t nf);
esp_err_t auris_fpga_set_gate_ratio    (uint8_t ratio);
esp_err_t auris_fpga_set_drc_threshold (uint32_t thr);     // 12-bit
esp_err_t auris_fpga_set_drc_ratio     (uint8_t ratio);    // 1..16
esp_err_t auris_fpga_set_master_gain   (uint16_t q14);     // Q2.14
esp_err_t auris_fpga_set_control       (uint32_t bits);

// Gain table: write `len` bins (16-bit Q2.14 signed) to the inactive
// bank, then commit.  M8: uses the FPGA's REG_GAIN_DATA auto-increment
// to reduce SPI traffic from 2*len to (len + 2) transactions.
esp_err_t auris_fpga_write_gain_table  (const int16_t *table_q14, size_t len);
esp_err_t auris_fpga_commit_gain_bank  (uint8_t bank);

// Telemetry readback
esp_err_t auris_fpga_read_version     (uint32_t *out);
esp_err_t auris_fpga_read_peak_in     (uint32_t *out);
esp_err_t auris_fpga_read_peak_out    (uint32_t *out);
esp_err_t auris_fpga_read_frame_count (uint32_t *out);   // 32-bit
esp_err_t auris_fpga_read_error_flags (uint32_t *out);

#ifdef __cplusplus
}
#endif

#endif // AURIS_FPGA_CONFIG_H
