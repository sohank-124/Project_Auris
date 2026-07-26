// =============================================================================
// File:        bt_audio.h
// Project:     Project Auris
// Description: Bluetooth A2DP audio source (Phase 3). The MVP build stubs
//              these functions out — they return ESP_OK after a single log
//              message so the firmware boots cleanly on hardware that has
//              Bluetooth disabled in sdkconfig.
// =============================================================================
#ifndef AURIS_BT_AUDIO_H
#define AURIS_BT_AUDIO_H

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t auris_bt_audio_init (void);
esp_err_t auris_bt_audio_start(void);
esp_err_t auris_bt_audio_stop (void);

#ifdef __cplusplus
}
#endif

#endif // AURIS_BT_AUDIO_H
