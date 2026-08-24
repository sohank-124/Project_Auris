// =============================================================================
// File:        volume_ctrl.sv
// Project:     Project Auris
// Module:      volume_ctrl
// Description: 31-step volume controller for the DSP output path.
//
//              Volume levels 0..31:
//                0  = mute  (output forced to zero)
//                31 = unity gain (1.0×)
//                16 ≈ 0.516× (≈ half volume)
//
//              The gain is linear: vol_q14 = level * (16384 / 31)
//              where 16384 = 1.0 in Q2.14 format.
//
//              The volume multiplier is applied AFTER the DSP pipeline
//              and BEFORE the output buffer, in the time domain.
//              This is a simple registered multiplier with 1-cycle
//              latency.
//
//              Inputs: 24-bit signed audio samples + 5-bit volume level.
//              Output: 24-bit signed scaled samples (saturated).
//
// Author:      [generated]
// Created:     2026-08
// Clock Domain: CD_DSP (96 MHz)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module volume_ctrl import auris_pkg::*; #(
    parameter int unsigned DATA_W = I2S_DATA_W   // 24
) (
    input  wire                clk_i,
    input  wire                rst_n_i,

    // Audio input (from DSP pipeline / overlap-add)
    input  wire [DATA_W-1:0]   in_l_i,
    input  wire [DATA_W-1:0]   in_r_i,
    input  wire                in_valid_i,

    // Volume level (0 = mute, 31 = unity)
    input  wire [4:0]          volume_i,

    // Audio output (to output buffer)
    output logic [DATA_W-1:0]  out_l_o,
    output logic [DATA_W-1:0]  out_r_o,
    output logic               out_valid_o
);

    // -------------------------------------------------------------------------
    // Volume gain table (Q2.14, 0..31)
    // -------------------------------------------------------------------------
    // level * (16384 / 31) = level * 528.516...
    // Rounded to nearest integer:
    //   0 → 0, 1 → 529, 2 → 1057, ..., 31 → 16384
    // Pre-computed for all 32 levels:
    localparam logic [15:0] VOL_TABLE [0:31] = '{
        16'd0,      16'd529,    16'd1057,   16'd1586,   // 0-3
        16'd2114,   16'd2643,   16'd3171,   16'd3700,   // 4-7
        16'd4228,   16'd4757,   16'd5285,   16'd5814,   // 8-11
        16'd6342,   16'd6871,   16'd7399,   16'd7928,   // 12-15
        16'd8456,   16'd8985,   16'd9513,   16'd10042,  // 16-19
        16'd10570,  16'd11099,  16'd11627,  16'd12156,  // 20-23
        16'd12684,  16'd13213,  16'd13741,  16'd14270,  // 24-27
        16'd14798,  16'd15327,  16'd15855,  16'd16384   // 28-31
    };

    // -------------------------------------------------------------------------
    // Gain lookup
    // -------------------------------------------------------------------------
    wire [15:0] vol_gain = VOL_TABLE[volume_i];

    // -------------------------------------------------------------------------
    // Multiplier: out = sat24(in * gain >> 14)
    // -------------------------------------------------------------------------
    // The multiplication is signed(24-bit) × unsigned(16-bit Q2.14).
    // Result is 40 bits.  We take bits [37:14] (equivalent to >> 14)
    // and saturate to 24-bit signed range.
    logic signed [39:0] mul_l, mul_r;
    logic signed [23:0] scaled_l, scaled_r;

    assign mul_l = $signed(in_l_i) * $signed({1'b0, vol_gain});
    assign mul_r = $signed(in_r_i) * $signed({1'b0, vol_gain});

    // Extract bits [37:14] (shift right by 14, keep 24 bits)
    assign scaled_l = mul_l[37:14];
    assign scaled_r = mul_r[37:14];

    // -------------------------------------------------------------------------
    // Saturation to 24-bit signed range
    // -------------------------------------------------------------------------
    function automatic logic [23:0] sat24(input logic signed [23:0] x,
                                           input logic overflow);
        if (overflow) begin
            // Saturate to max positive or max negative
            if (x[23]) sat24 = 24'sd8388607;   // +max (clip positive)
            else       sat24 = -24'sd8388607;  // -max (clip negative)
        end else begin
            sat24 = x;
        end
    endfunction

    // Detect overflow: if the upper bits (above bit 23) are not all
    // the same as bit 23, we have overflow.
    wire ovf_l = (mul_l[39:24] != {16{mul_l[23]}});
    wire ovf_r = (mul_r[39:24] != {16{mul_r[23]}});

    // -------------------------------------------------------------------------
    // Registered output with mute
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            out_l_o     <= '0;
            out_r_o     <= '0;
            out_valid_o <= 1'b0;
        end else begin
            out_valid_o <= in_valid_i;
            if (in_valid_i) begin
                if (volume_i == 5'd0) begin
                    // Mute
                    out_l_o <= '0;
                    out_r_o <= '0;
                end else begin
                    out_l_o <= sat24(scaled_l, ovf_l);
                    out_r_o <= sat24(scaled_r, ovf_r);
                end
            end
        end
    end

endmodule : volume_ctrl

`default_nettype wire
