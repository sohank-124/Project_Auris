// =============================================================================
// File:        status_mon.sv
// Project:     Project Auris — FPGA-Accelerated Assistive Audio
// Module:      status_mon
// Description: 1 Hz heartbeat generator and sticky clip-event latch.
//
//              The heartbeat is a free-running toggle at HEARTBEAT_HZ,
//              derived from a CLK_FREQ_HZ-cycle half-period counter.
//              When dsp_ready_i is low, the heartbeat is held low and the
//              counter is reset — this gives an external observer a
//              "DSP not running" indication.
//
//              The clip latch is a simple SR flip-flop: set on clip_event_i,
//              cleared on clip_clear_i.  It latches the most recent clip
//              event so a slow-polling host can still see it.
//
// Author:      [generated]
// Created:     2026-07
// Clock Domain: CD_DSP (96 MHz)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module status_mon import auris_pkg::*; #(
    parameter int unsigned CLK_FREQ_HZ  = 96_000_000,
    parameter int unsigned HEARTBEAT_HZ = 1
) (
    input  wire clk_i,
    input  wire rst_n_i,
    input  wire dsp_ready_i,
    input  wire clip_event_i,
    input  wire clip_clear_i,
    output logic heartbeat_o,
    output logic clip_latch_o
);

    // -------------------------------------------------------------------------
    // Heartbeat counter
    // -------------------------------------------------------------------------
    // The counter width must be wide enough to hold HALF_PERIOD.
    // For CLK_FREQ_HZ=96 MHz and HEARTBEAT_HZ=1, HALF_PERIOD=48_000_000
    // which needs 26 bits.  We use 28 bits to give headroom.
    localparam int unsigned HALF_PERIOD = CLK_FREQ_HZ / (2 * HEARTBEAT_HZ);
    localparam int unsigned HB_CNT_W    = $clog2(HALF_PERIOD + 1);

    logic [HB_CNT_W-1:0] hb_cnt;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            hb_cnt      <= '0;
            heartbeat_o <= 1'b0;
        end else if (!dsp_ready_i) begin
            hb_cnt      <= '0;
            heartbeat_o <= 1'b0;
        end else if (hb_cnt >= HALF_PERIOD[HB_CNT_W-1:0]) begin
            hb_cnt      <= '0;
            heartbeat_o <= ~heartbeat_o;
        end else begin
            hb_cnt      <= hb_cnt + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Clip latch (SR flip-flop)
    // -------------------------------------------------------------------------
    // Set dominates: if both clip_event_i and clip_clear_i are high in
    // the same cycle, the latch is set.  This is intentional — a fresh
    // clip event always wins.
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            clip_latch_o <= 1'b0;
        end else if (clip_event_i) begin
            clip_latch_o <= 1'b1;
        end else if (clip_clear_i) begin
            clip_latch_o <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Synthesis-time sanity
    // -------------------------------------------------------------------------
    initial begin
        if (HEARTBEAT_HZ == 0)
            $display("ERROR: status_mon HEARTBEAT_HZ=0 is illegal");
    end

endmodule : status_mon

`default_nettype wire
