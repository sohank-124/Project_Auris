// =============================================================================
// File:        spi_master.c
// Project:     Project Auris
// Description: Polling-mode SPI master driver for the FPGA register bus.
//
//              All public functions are non-blocking-ish: a single 32-bit
//              frame at 10 MHz takes ~3.2 us, well under any FreeRTOS
//              tick. spi_task is the only legitimate caller; calling these
//              from another task will still work (the bus is a single
//              hardware peripheral) but creates contention that the
//              request-response queue is designed to avoid.
//
//              Note: DMA is intentionally disabled. 10 MHz * 32 bits is
//              faster than the DMA setup overhead, and the transaction is
//              small enough that interrupt latency is not a concern.
// =============================================================================
#include "spi_master.h"
#include "driver/spi_master.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include <string.h>

static const char *TAG = "spi_master";

static spi_device_handle_t s_dev = NULL;
static bool s_initialized = false;

// ---------------------------------------------------------------------------
// Frame packing (per architecture spec)
//
//   Byte 0: addr & 0x7F           (bit 7=0 start marker, bits 6:0 = addr[6:0])
//   Byte 1: (is_read ? 0x80 : 0x00) | ((data >> 16) & 0x7F)
//                                  (bit 7 = R/W, bits 6:0 = data[22:16])
//   Byte 2: (data >> 8) & 0xFF    (data[15:8])
//   Byte 3: data & 0xFF           (data[7:0])
//
// 32-bit frame on the wire (MSB first):
//   bit 31     = 0           (start marker)
//   bit 30-24  = addr[6:0]   (7-bit register address)
//   bit 23     = R/W         (0 = write, 1 = read)
//   bit 22-0   = data[22:0]  (23-bit payload)
// ---------------------------------------------------------------------------
static inline void auris_spi_pack(uint8_t *tx, uint8_t addr, bool is_read, uint32_t data)
{
    tx[0] = (uint8_t)(addr & 0x7F);
    tx[1] = (uint8_t)((is_read ? 0x80u : 0x00u) | ((data >> 16) & 0x7Fu));
    tx[2] = (uint8_t)((data >> 8) & 0xFFu);
    tx[3] = (uint8_t)( data        & 0xFFu);
}

// ---------------------------------------------------------------------------
// auris_spi_init
// ---------------------------------------------------------------------------
esp_err_t auris_spi_init(void)
{
    if (s_initialized) return ESP_OK;

    spi_bus_config_t bus_cfg = {
        .miso_io_num     = AURIS_SPI_PIN_MISO,
        .mosi_io_num     = AURIS_SPI_PIN_MOSI,
        .sclk_io_num     = AURIS_SPI_PIN_SCLK,
        .quadwp_io_num   = -1,
        .quadhd_io_num   = -1,
        .max_transfer_sz = 4,
    };
    esp_err_t ret = spi_bus_initialize(AURIS_SPI_HOST, &bus_cfg, SPI_DMA_DISABLED);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "spi_bus_initialize failed: %s", esp_err_to_name(ret));
        return ret;
    }

    spi_device_interface_config_t dev_cfg = {
        .clock_speed_hz = AURIS_SPI_CLK_HZ,
        .mode           = 0,                      // CPOL=0, CPHA=0
        .spics_io_num   = AURIS_SPI_PIN_CS,
        .queue_size     = 1,
        .flags          = 0,
    };
    ret = spi_bus_add_device(AURIS_SPI_HOST, &dev_cfg, &s_dev);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "spi_bus_add_device failed: %s", esp_err_to_name(ret));
        spi_bus_free(AURIS_SPI_HOST);
        return ret;
    }

    s_initialized = true;
    ESP_LOGI(TAG, "SPI master initialized: SCLK=%d Hz, CS=GPIO%d",
             AURIS_SPI_CLK_HZ, AURIS_SPI_PIN_CS);
    return ESP_OK;
}

esp_err_t auris_spi_deinit(void)
{
    if (!s_initialized) return ESP_OK;
    if (s_dev) {
        spi_bus_remove_device(s_dev);
        s_dev = NULL;
    }
    spi_bus_free(AURIS_SPI_HOST);
    s_initialized = false;
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// auris_spi_write
// ---------------------------------------------------------------------------
esp_err_t auris_spi_write(uint8_t addr, uint32_t data)
{
    if (!s_initialized) return ESP_ERR_INVALID_STATE;
    if (addr > 0x7F)    return ESP_ERR_INVALID_ARG;

    uint8_t tx[4];
    auris_spi_pack(tx, addr, /*is_read=*/false, data & 0xFFFFFFu);

    spi_transaction_t t = {
        .length    = 32,
        .tx_buffer = tx,
        .rx_buffer = NULL,
    };
    esp_err_t ret = spi_device_polling_transmit(s_dev, &t);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "SPI write 0x%02X failed: %s", addr, esp_err_to_name(ret));
    }
    return ret;
}

// ---------------------------------------------------------------------------
// auris_spi_read
// ---------------------------------------------------------------------------
esp_err_t auris_spi_read(uint8_t addr, uint32_t *out)
{
    if (!s_initialized) return ESP_ERR_INVALID_STATE;
    if (addr > 0x7F)    return ESP_ERR_INVALID_ARG;
    if (!out)           return ESP_ERR_INVALID_ARG;

    uint8_t tx[4];
    uint8_t rx[4] = {0};
    auris_spi_pack(tx, addr, /*is_read=*/true, 0xFFFFFFu);

    spi_transaction_t t = {
        .length    = 32,
        .tx_buffer = tx,
        .rx_buffer = rx,
    };
    esp_err_t ret = spi_device_polling_transmit(s_dev, &t);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "SPI read 0x%02X failed: %s", addr, esp_err_to_name(ret));
        return ret;
    }

    // Response: bits 22:0 of the 32-bit received word carry the register
    // value. Bits 31:23 are don't-care (start + R/W echo + addr echo).
    uint32_t word = ((uint32_t)rx[0] << 24) | ((uint32_t)rx[1] << 16)
                  | ((uint32_t)rx[2] <<  8) |  (uint32_t)rx[3];
    *out = word & 0x7FFFFFu;
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// auris_spi_bulk_write
// ---------------------------------------------------------------------------
esp_err_t auris_spi_bulk_write(const uint8_t *addrs,
                               const uint32_t *values,
                               size_t count)
{
    if (!addrs || !values) return ESP_ERR_INVALID_ARG;
    if (count == 0)         return ESP_OK;
    if (count > AURIS_SPI_BULK_MAX) return ESP_ERR_INVALID_ARG;
    if (!s_initialized)     return ESP_ERR_INVALID_STATE;

    for (size_t i = 0; i < count; i++) {
        esp_err_t r = auris_spi_write(addrs[i], values[i]);
        if (r != ESP_OK) return r;
    }
    return ESP_OK;
}
