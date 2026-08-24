// =============================================================================
// File:        btn_debounce.sv
// Project:     Project Auris
// Module:      btn_debounce
// Description: Debounced button input for active-low push buttons on the
//              Arty S7-25.  Each button produces a single-cycle pulse on
//              press (leading edge) and a separate single-cycle pulse on
//              release (trailing edge).
//
//              The debouncer uses a simple counter-based approach:
//              the raw input is sampled at the system clock rate, and
//              the output changes state only after the input has been
//              stable for DEBOUNCE_CYCLES consecutive clock cycles.
//
//              Arty S7-25 buttons are active-low (pressed = 0).
//              The module internally inverts so `btn_pressed_o` is
//              active-high (1 = pressed).
//
// Author:      [generated]
// Created:     2026-08
// Clock Domain: CD_DSP (96 MHz)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module btn_debounce #(
    parameter int unsigned CLK_FREQ_HZ    = 96_000_000,
    parameter int unsigned DEBOUNCE_MS    = 20,
    parameter int unsigned NUM_BUTTONS    = 4
) (
    input  wire                          clk_i,
    input  wire                          rst_n_i,

    // Active-low button inputs (directly from FPGA pins)
    input  wire [NUM_BUTTONS-1:0]        btn_i,

    // Debounced button state (active-high: 1 = pressed)
    output logic [NUM_BUTTONS-1:0]       btn_pressed_o,

    // Single-cycle pulse on press (active-high, 1 cycle)
    output logic [NUM_BUTTONS-1:0]       btn_press_pulse_o,

    // Single-cycle pulse on release (active-high, 1 cycle)
    output logic [NUM_BUTTONS-1:0]       btn_release_pulse_o
);

    // -------------------------------------------------------------------------
    // Debounce counter parameters
    // -------------------------------------------------------------------------
    localparam int unsigned DEBOUNCE_CYCLES = CLK_FREQ_HZ / 1000 * DEBOUNCE_MS;
    localparam int unsigned CNT_WIDTH       = $clog2(DEBOUNCE_CYCLES + 1);

    // -------------------------------------------------------------------------
    // Per-button debounce logic
    // -------------------------------------------------------------------------
    logic [NUM_BUTTONS-1:0] btn_sync_0;    // first sync FF
    logic [NUM_BUTTONS-1:0] btn_sync_1;    // second sync FF (meta-stable safe)
    logic [NUM_BUTTONS-1:0] btn_state;     // debounced state (active-high)
    logic [NUM_BUTTONS-1:0] btn_state_d;   // delayed state for edge detect

    (* CNT_WIDTH *) logic [CNT_WIDTH-1:0] cnt [0:NUM_BUTTONS-1];

    // -------------------------------------------------------------------------
    // 2-FF synchroniser + active-low to active-high inversion
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            btn_sync_0 <= {NUM_BUTTONS{1'b0}};
            btn_sync_1 <= {NUM_BUTTONS{1'b0}};
        end else begin
            btn_sync_0 <= ~btn_i;    // invert: active-low → active-high
            btn_sync_1 <= btn_sync_0;
        end
    end

    // -------------------------------------------------------------------------
    // Debounce counters + state update
    // -------------------------------------------------------------------------
    genvar gi;
    generate
        for (gi = 0; gi < NUM_BUTTONS; gi++) begin : gen_btn
            always_ff @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    cnt[gi]   <= '0;
                    btn_state[gi] <= 1'b0;
                end else begin
                    if (btn_sync_1[gi] != btn_state[gi]) begin
                        // Input differs from current state — count
                        if (cnt[gi] >= CNT_WIDTH'(DEBOUNCE_CYCLES - 1)) begin
                            btn_state[gi] <= btn_sync_1[gi];
                            cnt[gi]       <= '0;
                        end else begin
                            cnt[gi] <= cnt[gi] + 1'b1;
                        end
                    end else begin
                        // Input matches state — reset counter
                        cnt[gi] <= '0;
                    end
                end
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Edge detection: press and release pulses
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            btn_state_d <= {NUM_BUTTONS{1'b0}};
        end else begin
            btn_state_d <= btn_state;
        end
    end

    assign btn_pressed_o       = btn_state;
    assign btn_press_pulse_o   = btn_state & ~btn_state_d;   // rising edge
    assign btn_release_pulse_o = ~btn_state & btn_state_d;   // falling edge

    // -------------------------------------------------------------------------
    // Synthesis-time sanity
    // -------------------------------------------------------------------------
    initial begin
        if (DEBOUNCE_CYCLES < 2)
            $display("WARNING: btn_debounce DEBOUNCE_CYCLES=%0d too small", DEBOUNCE_CYCLES);
    end

endmodule : btn_debounce

`default_nettype wire
