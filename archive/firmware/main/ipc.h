// =============================================================================
// File:        ipc.h
// Project:     Project Auris
// Description: Inter-process communication handle declarations. The IPC
//              TYPES live with their producers (button_event_t in
//              button_handler.h, auris_spi_request_t in spi_master.h,
//              auris_led_command_t in led_indicator.h, and
//              auris_profile_save_request_t in profile_store.h). The
//              queue handles themselves are defined in main.c and exposed
//              here as extern so any component can publish to or consume
//              from them.
//
//              Producers and consumers:
//
//                button_task     -> [g_button_q]   -> mode_task
//                mode_task,      -> [g_spi_q]      -> spi_task
//                monitor_task       (response via task notification)
//                mode_task,      -> [g_led_q]      -> led_task
//                monitor_task
//                mode_task       -> [g_profile_q]  -> profile_task
// =============================================================================
#ifndef AURIS_IPC_H
#define AURIS_IPC_H

#include <stdint.h>
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "app_state.h"          // event group + event bits
#include "button_handler.h"     // button_event_t
#include "spi_master.h"         // auris_spi_request_t
#include "led_indicator.h"      // led_pattern_t, auris_led_command_t
#include "profile_store.h"      // auris_profile_save_request_t

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Queue handles (defined in main.c, populated in app_main)
// ---------------------------------------------------------------------------
extern QueueHandle_t g_button_q;
extern QueueHandle_t g_spi_q;
extern QueueHandle_t g_led_q;
extern QueueHandle_t g_profile_q;

#ifdef __cplusplus
}
#endif

#endif // AURIS_IPC_H
