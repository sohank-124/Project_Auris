// =============================================================================
// File:        profile_store.h
// Project:     Project Auris
// Description: NVS-backed persistent storage. A single auris_profile_t
//              struct is the RAM mirror of the persisted values; getters
//              read from the mirror (zero-cost) and setters update both
//              the mirror and queue an NVS write request.
//
// Schema migration runs on init: if the stored schema_ver is missing or
// older than AURIS_PROFILE_SCHEMA_VER, the namespace is wiped and defaults
// are written. If the persisted err_cnt is >= 3, the namespace is wiped
// and a one-time log message is emitted.
// =============================================================================
#ifndef AURIS_PROFILE_STORE_H
#define AURIS_PROFILE_STORE_H

#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define AURIS_PROFILE_SCHEMA_VER    1
#define AURIS_PROFILE_GAIN_BINS     128
#define AURIS_PROFILE_NS            "auris"
#define AURIS_PROFILE_ERR_THRESHOLD 3

typedef struct {
    uint8_t  schema_ver;
    uint8_t  mode;
    uint8_t  volume;
    int16_t  gain_tbl[AURIS_PROFILE_GAIN_BINS];
    uint32_t boot_cnt;
    uint32_t err_cnt;
} auris_profile_t;

const auris_profile_t *auris_profile_get_mirror(void);

esp_err_t auris_profile_init          (void);
esp_err_t auris_profile_factory_reset (void);

// Mode / volume (mode is passed as uint8_t to avoid a header dep on
// mode_manager.h; callers cast to/from auris_mode_t as needed)
esp_err_t auris_profile_get_mode      (uint8_t *m);
esp_err_t auris_profile_set_mode      (uint8_t m);
esp_err_t auris_profile_get_volume    (uint8_t *v);
esp_err_t auris_profile_set_volume    (uint8_t v);

// Gain table (blob of AURIS_PROFILE_GAIN_BINS int16)
esp_err_t auris_profile_get_gain_table(int16_t *out_q14, size_t len);
esp_err_t auris_profile_set_gain_table(const int16_t *in_q14, size_t len);

// Error counter
esp_err_t auris_profile_inc_err_cnt   (void);
uint32_t  auris_profile_get_err_cnt   (void);

// ---------------------------------------------------------------------------
// Profile-save request envelope — produced by mode_task and consumed by
// profile_task via the g_profile_q queue.
// ---------------------------------------------------------------------------
typedef enum {
    AURIS_PROF_SAVE_MODE   = 0,
    AURIS_PROF_SAVE_VOLUME = 1,
    AURIS_PROF_SAVE_GAIN   = 2,
    AURIS_PROF_SAVE_ERROR  = 3,
} auris_prof_save_kind_t;

typedef struct {
    auris_prof_save_kind_t kind;
    uint8_t                u8;            // mode or volume
    int16_t                table_q14[AURIS_PROFILE_GAIN_BINS]; // GAIN only
    uint32_t               err_cnt;       // ERROR only
} auris_profile_save_request_t;

#ifdef __cplusplus
}
#endif

#endif // AURIS_PROFILE_STORE_H
