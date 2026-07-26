// =============================================================================
// File:        spi_master.h
// Project:     Project Auris
// Description: Low-level SPI master driver for the FPGA link. 32-bit MSB-first
//              framed transactions, 10 MHz, Mode 0, polling. All access is
//              serialized by spi_task; this layer does no locking.
//
// Frame layout (32 bits, MSB first on the wire):
//   bit 31     = 0           (start marker)
//   bit 30-24  = addr[6:0]   (7-bit register address)
//   bit 23     = R/W         (0 = write, 1 = read)
//   bit 22-0   = data[22:0]  (23-bit payload)
//
// On a read the host drives data=0x7FFFFF; the FPGA echoes its response
// into the low 23 bits of the same 32-bit shift.
// =============================================================================
#ifndef AURIS_SPI_MASTER_H
#define AURIS_SPI_MASTER_H

#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// Pin assignments
#define AURIS_SPI_PIN_SCLK    18
#define AURIS_SPI_PIN_MOSI    23
#define AURIS_SPI_PIN_MISO    19
#define AURIS_SPI_PIN_CS      5
#define AURIS_SPI_CLK_HZ      (10 * 1000 * 1000)   // 10 MHz
#define AURIS_SPI_HOST        SPI2_HOST

// Maximum number of registers that fit in a single bulk-write request.
#define AURIS_SPI_BULK_MAX    16

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------
esp_err_t auris_spi_init(void);
esp_err_t auris_spi_deinit(void);

// Single-register write. `data` is masked to 24 bits.
esp_err_t auris_spi_write(uint8_t addr, uint32_t data);

// Single-register read. The 24-bit result is placed in *out.
esp_err_t auris_spi_read(uint8_t addr, uint32_t *out);

// Bulk write of up to AURIS_SPI_BULK_MAX (addr,value) pairs in one queue item.
esp_err_t auris_spi_bulk_write(const uint8_t *addrs,
                               const uint32_t *values,
                               size_t count);

// ---------------------------------------------------------------------------
// SPI request envelope — produced by mode_task, monitor_task, etc. and
// consumed by spi_task via the g_spi_q queue. The caller blocks on a task
// notification until spi_task completes the transaction.
// ---------------------------------------------------------------------------
typedef enum {
    AURIS_SPI_REQ_WRITE = 0,
    AURIS_SPI_REQ_READ  = 1,
    AURIS_SPI_REQ_BULK  = 2,
} auris_spi_req_kind_t;

typedef struct {
    auris_spi_req_kind_t kind;
    uint8_t              addr;          // single-register addr (WRITE/READ)
    uint32_t             data;          // WRITE data (low 24 bits used)
    uint32_t            *result_ptr;    // READ: filled with response data
    void                *caller;        // TaskHandle_t; notified on completion
    uint8_t              bulk_addrs[AURIS_SPI_BULK_MAX];
    uint32_t             bulk_vals [AURIS_SPI_BULK_MAX];
    size_t               bulk_count;
} auris_spi_request_t;

#ifdef __cplusplus
}
#endif

#endif // AURIS_SPI_MASTER_H
