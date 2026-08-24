// =============================================================================
// File:        auris_pkg.sv
// Project:     Project Auris — FPGA-Accelerated Assistive Audio
// Module:      auris_pkg (SystemVerilog package)
// Description: Global types, parameters, constants and utility functions
//              shared by every RTL module in Project Auris.
//
//              Centralising these in a single package guarantees that the
//              DSP data widths, the I2S sample width, the FFT length, the
//              register map and the clock-domain identifiers are all
//              consistent across the design.  All register definitions are
//              internal to the FPGA; there is no external host interface.
//
// Author:      [generated]
// Created:     2026-07
// Toolchain:   Xilinx Vivado 2024.x, SystemVerilog-2009
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

package auris_pkg;

    // -------------------------------------------------------------------------
    // Compile-time feature switches
    // -------------------------------------------------------------------------
    parameter bit AURIS_ENABLE_DRC       = 1;   // 0 in Phase 0, 1 in Phase 4
    parameter bit AURIS_ENABLE_TELEMETRY = 0;   // 1 in Phase 5
    parameter bit AURIS_SIM_MODE         = 0;   // 1 in testbench elaboration

    // -------------------------------------------------------------------------
    // DSP parameters (locked by the architecture decision)
    // -------------------------------------------------------------------------
    parameter int unsigned FFT_LEN         = 256;        // 256-point FFT
    parameter int unsigned FFT_ADDR_W      = $clog2(FFT_LEN);
    parameter int unsigned FFT_DATA_W      = 16;         // Q2.14 fixed-point
    parameter int unsigned I2S_DATA_W      = 24;         // INMP441 / PCM5102A
    parameter int unsigned WINDOW_DATA_W   = 16;         // Hann coefficient width
    parameter int unsigned GAIN_TABLE_DEPTH = FFT_LEN / 2;   // per-bin gain table (real-input FFT: N/2 unique bins)
    parameter int unsigned VOLUME_STEPS    = 32;         // host-facing volume
    // Volume: 31 levels. Level 31 = unity (0x4000 Q2.14), level 0 = mute.
    // Linear mapping: vol_q14 = level * (16384 / 31) ≈ level * 529
    parameter int unsigned VOLUME_LEVELS   = 31;         // 0=mute, 31=unity
    parameter int unsigned NUM_BUTTONS     = 4;          // BTN0-3
    parameter int unsigned DEBOUNCE_MS     = 20;         // debounce time
    parameter int unsigned CDC_FIFO_DEPTH  = 4;          // I2S <-> DSP FIFO depth
    parameter int unsigned RESET_STRETCH_CYCLES = 16;    // reset-stretcher length
    // BFP exponent alignment delay (cycles).
    // Shifts fft_blk_exp through an SRL pipeline so it arrives at
    // overlap_add synchronised with the corresponding IFFT output frame.
    //   spectral_proc  :   4 cycles (4-stage pipeline)
    //   IFFT (xfft v9.1, pipelined streaming, N=256) : ~414 cycles
    //   Total          : 4 + 414 = 418 cycles
    parameter int unsigned BFP_PIPE_DELAY  = 418;

    // -------------------------------------------------------------------------
    // Fixed-point helpers (Q2.14 scaling)
    // -------------------------------------------------------------------------
    // 16384 = 1.0 in unsigned Q2.14.  In signed SystemVerilog this is
    // 16'sd16384 which is the unity-gain multiplier used by mode_ctrl and
    // the default initial value of every entry in the per-bin gain tables.
    localparam logic signed [15:0] UNITY_GAIN_Q14 = 16'sd16384;

    // -------------------------------------------------------------------------
    // Hardware revision register (read-only, exposed at REG_HW_VERSION)
    // -------------------------------------------------------------------------
    // Bumped when a wire-level incompatible change is made to the bitstream.
    // 0x0A = revision A (initial prototype bring-up).
    localparam logic [6:0] REG_HW_VERSION = 7'h0A;

    // -------------------------------------------------------------------------
    // Clock-domain identifiers
    // -------------------------------------------------------------------------
    // Used by CDC modules and by documentation/logging.  Each value is
    // assigned to a unique 2-bit code so a single 2-bit field can describe
    // the domain in any status register or log line.
    typedef enum logic [1:0] {
        CD_I2S = 2'd0,
        CD_DSP = 2'd1
    } clock_domain_t;

    // -------------------------------------------------------------------------
    // Operating mode (drives the mode_ctrl / spectral_proc behaviour)
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        MODE_GENERAL = 2'd0,
        MODE_SPEECH  = 2'd1,
        MODE_MUSIC   = 2'd2,
        MODE_HEARING = 2'd3
    } auris_mode_t;

    // -------------------------------------------------------------------------
    // Register-file address map (must match firmware/.../fpga_config.h)
    // -------------------------------------------------------------------------
    localparam logic [6:0] REG_VERSION         = 7'h00;
    localparam logic [6:0] REG_STATUS          = 7'h01;
    localparam logic [6:0] REG_CONTROL         = 7'h02;
    localparam logic [6:0] REG_MODE            = 7'h03;
    localparam logic [6:0] REG_VOLUME          = 7'h04;
    localparam logic [6:0] REG_NOISE_FLOOR     = 7'h05;
    localparam logic [6:0] REG_NOISE_GATE_RATIO = 7'h06;
    localparam logic [6:0] REG_DRC_THRESHOLD   = 7'h07;
    localparam logic [6:0] REG_DRC_RATIO       = 7'h08;
    localparam logic [6:0] REG_MASTER_GAIN     = 7'h09;
    // 0x0A is reserved for the hardware-revision register (REG_HW_VERSION).
    localparam logic [6:0] REG_GAIN_ADDR       = 7'h10;
    localparam logic [6:0] REG_GAIN_DATA       = 7'h11;
    localparam logic [6:0] REG_GAIN_BANK       = 7'h12;
    localparam logic [6:0] REG_GAIN_COMMIT     = 7'h13;
    localparam logic [6:0] REG_PEAK_LEVEL      = 7'h20;
    localparam logic [6:0] REG_OUT_PEAK        = 7'h21;
    localparam logic [6:0] REG_FRAME_COUNT_L   = 7'h22;
    localparam logic [6:0] REG_FRAME_COUNT_H   = 7'h23;
    localparam logic [6:0] REG_ERROR_FLAGS     = 7'h24;
    localparam logic [6:0] REG_SCRATCH         = 7'h7E;
    localparam logic [6:0] REG_LOOPBACK        = 7'h7F;

    // -------------------------------------------------------------------------
    // REG_STATUS bit positions (8-bit read-only field)
    // -------------------------------------------------------------------------
    localparam int unsigned STATUS_READY       = 0;   // MMCM locked, DSP out of reset
    localparam int unsigned STATUS_LOCKED      = 1;   // CDC synchronizers stable
    localparam int unsigned STATUS_CLIP        = 2;   // sticky clip-event indicator
    localparam int unsigned STATUS_DSP_EN      = 3;   // DSP pipeline running
    localparam int unsigned STATUS_MODE_SHIFT  = 4;   // current mode lives in [5:4]

    // -------------------------------------------------------------------------
    // REG_ERROR_FLAGS bit positions (8-bit W1C field)
    // -------------------------------------------------------------------------
    localparam int unsigned ERR_I2S_OVERFLOW   = 0;    // i2s_rx dropped a sample
    localparam int unsigned ERR_I2S_UNDERFLOW  = 1;    // i2s_tx ran out of data
    localparam int unsigned ERR_FFT_OVERFLOW   = 2;    // FFT BFP exponent saturated
    localparam int unsigned ERR_FRAME_DROP     = 3;    // dsp_pipeline missed a frame
    localparam int unsigned ERR_GAIN_RANGE     = 4;    // host wrote an out-of-range gain

    // -------------------------------------------------------------------------
    // Utility functions
    // -------------------------------------------------------------------------
    // Return 24-bit zero in a typed wrapper.
    function automatic logic [23:0] s24_zero();
        return 24'sd0;
    endfunction

    // Sign-extend a 16-bit signed value to 24 bits.  Used when an FFT
    // output (16-bit Q2.14) is widened before being multiplied by a
    // 24-bit master gain.
    function automatic logic [23:0] sxt24(input logic [15:0] in);
        return {{8{in[15]}}, in};
    endfunction

    // Take the upper 16 bits of a 24-bit value, dropping the LSBs.
    // Used to truncate 24-bit I2S samples down to the FFT data width
    // before windowing.
    function automatic logic [15:0] hi16(input logic [23:0] in);
        return in[23:8];
    endfunction

endpackage : auris_pkg

`default_nettype wire
