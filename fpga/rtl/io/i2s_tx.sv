// =============================================================================
// File:        i2s_tx.sv
// Project:     Project Auris
// Module:      i2s_tx
// Description: I2S slave transmitter targeting the PCM5102A DAC in
//              **standard I2S** (Philips) format.  In standard I2S:
//
//                - LRCLK transitions one BCLK period *before* the MSB
//                - the data line is held low for the first BCLK period
//                  after the LRCLK transition (this is the "1-BCLK delay")
//                - the MSB is then clocked out on the second BCLK
//                  rising edge after LRCLK changes
//                - the slave drives sdata_o on the BCLK **falling** edge
//                  so the master (PCM5102A) sees a stable value on its
//                  subsequent BCLK **rising** edge
//
//              Shadow registers capture left_i/right_i on the LRCLK
//              falling edge when valid_i is high; on underflow the
//              transmitter emits silence (24'b0) for the entire frame
//              and asserts the sticky `underflow_o` flag.
//
//              Implementation: the shift register and FSM run on the
//              BCLK rising edge; sdata_o is a separate flip-flop clocked
//              on the BCLK **falling** edge, capturing sdata_q.  This
//              gives a clean half-period of setup + hold margin to the
//              PCM5102A's rising-edge latch.
//
// FSM (3 states, binary encoded):
//                 IDLE --> SHIFT_LEFT --> SHIFT_RIGHT --> IDLE
//
// Author:      [generated]
// Created:     2026-07
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module i2s_tx import auris_pkg::*; #(
    parameter int unsigned DATA_W = I2S_DATA_W   // 24 for PCM5102A
) (
    input  wire                bclk_i,
    input  wire                lrclk_i,
    output logic               sdata_o,
    input  wire                rst_n_i,
    input  wire [DATA_W-1:0]   left_i,
    input  wire [DATA_W-1:0]   right_i,
    input  wire                valid_i,
    output logic               underflow_o   // sticky
);

    logic lrclk_d;
    logic [DATA_W-1:0] right_shadow, shift_reg;
    logic [4:0] bits_remaining;
    logic sdata_q;
    // Detect each slot at its first rising edge. The next falling edge
    // launches its MSB, exactly one bit after LRCLK changes.
    always_ff @(posedge bclk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            lrclk_d <= 0;
            right_shadow <= 0;
            shift_reg <= 0;
            bits_remaining <= 0;
            sdata_q <= 0;
            underflow_o <= 0;
        end else begin
            lrclk_d <= lrclk_i;
            if (lrclk_d != lrclk_i) begin
                bits_remaining <= DATA_W-1;
                if (!lrclk_i) begin
                    right_shadow <= valid_i ? right_i : '0;
                    sdata_q <= valid_i ? left_i[DATA_W-1] : 1'b0;
                    shift_reg <= valid_i ? {left_i[DATA_W-2:0],1'b0} : '0;
                    if (!valid_i) underflow_o <= 1;
                end else begin
                    sdata_q <= right_shadow[DATA_W-1];
                    shift_reg <= {right_shadow[DATA_W-2:0],1'b0};
                end
            end else if (bits_remaining != 0) begin
                sdata_q <= shift_reg[DATA_W-1];
                shift_reg <= {shift_reg[DATA_W-2:0],1'b0};
                bits_remaining <= bits_remaining - 1'b1;
            end else sdata_q <= 0;
        end
    end
    always_ff @(negedge bclk_i or negedge rst_n_i) begin
        if (!rst_n_i) sdata_o <= 0;
        else sdata_o <= sdata_q;
    end
    initial if (DATA_W < 8 || DATA_W > 24)
        $fatal(1, "i2s_tx DATA_W must be 8..24");
endmodule : i2s_tx
`default_nettype wire
