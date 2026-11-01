// =============================================================================
// File:        window_apply.sv
// Project:     Project Auris — FPGA-Accelerated Assistive Audio
// Module:      window_apply
// Description: Hann window multiplier.  Multiplies incoming 24-bit samples
//              by 256-entry Hann window coefficients (Q2.14) and presents
//              the result to the FFT as a 16-bit Q2.14 real value.
//
//              Pipeline (2 cycles total):
//                Cycle 1: window ROM read (1-cycle registered output)
//                Cycle 2: signed multiply + truncate back to Q2.14
//
//              The imaginary channel is tied to zero (real-input FFT).
//              The right channel is dropped for MVP — only the left
//              channel is processed and the output is duplicated to
//              both real and imaginary paths inside dsp_pipeline.
//
// Author:      [generated]
// Created:     2026-07
// Clock Domain: CD_DSP (96 MHz)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module window_apply import auris_pkg::*; #(
    parameter int unsigned LEN    = FFT_LEN,
    parameter int unsigned DATA_W = I2S_DATA_W,
    parameter int unsigned WIN_W  = WINDOW_DATA_W
) (
    input  wire                    clk_i,
    input  wire                    rst_n_i,

    input  wire [DATA_W-1:0]       in_l_i,
    input  wire [DATA_W-1:0]       in_r_i,
    input  wire                    in_v_i,
    input  wire                    frame_start_i,  // pulse at first sample of frame

    output logic [15:0]            out_re_o,
    output logic [15:0]            out_im_o,
    output logic                   out_v_o
);

    // -------------------------------------------------------------------------
    // Window ROM
    // -------------------------------------------------------------------------
    logic [$clog2(LEN)-1:0] rom_addr;
    logic [WIN_W-1:0]       rom_q;

    window_rom #(
        .LEN   (LEN),
        .WIDTH (WIN_W)
    ) u_window_rom (
        .clk_i (clk_i),
        .addr_i(rom_addr),
        .data_o(rom_q)
    );

    // The ROM and sample register capture the same accepted transaction.
    logic [$clog2(LEN)-1:0] sample_index;
    logic signed [15:0] sample_q14;
    logic sample_valid;
    logic signed [32:0] product;
    assign rom_addr = frame_start_i ? '0 : sample_index;
    assign product = sample_q14 * $signed({1'b0, rom_q});

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            sample_index <= '0;
            sample_q14 <= '0;
            sample_valid <= 1'b0;
            out_re_o <= '0;
            out_im_o <= '0;
            out_v_o <= 1'b0;
        end else begin
            if (frame_start_i) sample_index <= '0;
            if (in_v_i) begin
                sample_index <= (rom_addr == LEN-1) ? '0 : rom_addr + 1'b1;
                sample_q14 <= $signed(in_l_i[23:8]);
            end
            sample_valid <= in_v_i;
            out_v_o <= sample_valid;
            out_re_o <= product >>> 14;
            out_im_o <= '0;
        end
    end

    initial begin
        if (LEN != 256 || DATA_W != 24 || WIN_W != 16)
            $fatal(1, "window_apply supports LEN=256 DATA_W=24 WIN_W=16");
    end
endmodule : window_apply
`default_nettype wire
