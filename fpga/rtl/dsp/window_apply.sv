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

    // -------------------------------------------------------------------------
    // Sample counter (0..LEN-1): resets on frame_start_i, advances on in_v_i
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)            rom_addr <= '0;
        else if (frame_start_i)  rom_addr <= '0;
        else if (in_v_i)         rom_addr <= rom_addr + 1'b1;
    end

    // -------------------------------------------------------------------------
    // Pipeline stage 1: register ROM output and valid
    // -------------------------------------------------------------------------
    logic [WIN_W-1:0] win_reg;
    logic             in_v_reg;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            win_reg  <= '0;
            in_v_reg <= 1'b0;
        end else begin
            win_reg  <= rom_q;
            in_v_reg <= in_v_i;
        end
    end

    // -------------------------------------------------------------------------
    // Pipeline stage 2: signed multiply + truncate
    // -------------------------------------------------------------------------
    // Q2.14 * Q2.14 = Q4.28.  Take bits [27:12] to get back to Q2.14.
    // The 16-bit input is taken from the upper 16 bits of the 24-bit
    // sample (in_l_i[23:8]) — simple truncation.
    logic signed [15:0] samp_q14;
    logic signed [15:0] win_q14_s;
    logic signed [31:0] product;

    assign samp_q14 = in_l_i[23:8];
    assign win_q14_s = $signed(win_reg);
    assign product  = samp_q14 * win_q14_s;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            out_re_o <= '0;
            out_im_o <= '0;
            out_v_o  <= 1'b0;
        end else begin
            out_re_o <= product[27:12];
            out_im_o <= 16'sd0;   // real-input FFT
            out_v_o  <= in_v_reg;
        end
    end

endmodule : window_apply

`default_nettype wire
