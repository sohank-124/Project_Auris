// =============================================================================
// File:        spectral_proc.sv
// Project:     Project Auris — FPGA-Accelerated Assistive Audio
// Module:      spectral_proc
// Description: Per-bin frequency-domain processing.  Receives FFT output one
//              bin at a time (in complex {re, im} format) and applies:
//
//                1. Per-bin gain (read from active bank of dual-port BRAM)
//                2. Master gain (combinational multiply with bin gain)
//                3. Spectral noise gate (compare |X|^2 with noise_floor;
//                   if below threshold, scale by gate_ratio)
//
//              The gain table is 2 banks x 128 bins x 16 bits.  The SPI
//              host writes the inactive bank; on bank_commit_i the
//              active_bank register toggles atomically — no glitch in
//              the audio path.
//
//              Pipeline (4 cycles):
//                Stage 1: read gain from active bank
//                Stage 2: effective_gain = bin_gain * master_gain (Q2.14)
//                Stage 3: compute |X|^2
//                Stage 4: apply gate, multiply, output
//
//              All multiplies are signed Q2.14 with bits [29:14] taken
//              for the result (truncation, no rounding — acceptable for
//              MVP).
//
// Author:      [generated]
// Created:     2026-07
// Clock Domain: CD_DSP (96 MHz)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module spectral_proc import auris_pkg::*; #(
    parameter int unsigned N_BINS = GAIN_TABLE_DEPTH,
    parameter int unsigned DATA_W = FFT_DATA_W,
    parameter int unsigned ADDR_W = $clog2(GAIN_TABLE_DEPTH)
) (
    input  wire                    clk_i,
    input  wire                    rst_n_i,

    // Streaming complex data from FFT
    input  wire [DATA_W-1:0]       in_re_i,
    input  wire [DATA_W-1:0]       in_im_i,
    input  wire                    in_v_i,
    input  wire                    in_last_i,

    // Streaming complex data to IFFT
    output logic [DATA_W-1:0]      out_re_o,
    output logic [DATA_W-1:0]      out_im_o,
    output logic                   out_v_o,
    output logic                   out_last_o,

    // Control inputs (Q2.14, 16-bit)
    input  wire [1:0]              mode_i,
    input  wire [DATA_W-1:0]       master_gain_i,
    input  wire [DATA_W-1:0]       noise_floor_i,
    input  wire [DATA_W-1:0]       gate_ratio_i,

    // Gain-table write interface
    input  wire [ADDR_W-1:0]       bin_addr_i,
    input  wire [DATA_W-1:0]       bin_wdata_i,
    input  wire                    bin_we_i,
    input  wire [1:0]              bin_bank_i,
    input  wire                    bank_commit_i
);

    // -------------------------------------------------------------------------
    // Dual-bank gain table
    // -------------------------------------------------------------------------
    (* ram_style = "block" *) logic [DATA_W-1:0] gain_bank_a [0:N_BINS-1];
    (* ram_style = "block" *) logic [DATA_W-1:0] gain_bank_b [0:N_BINS-1];

    initial begin
        for (int i = 0; i < N_BINS; i++) begin
            gain_bank_a[i] = UNITY_GAIN_Q14;
            gain_bank_b[i] = UNITY_GAIN_Q14;
        end
    end

    // -------------------------------------------------------------------------
    // Active bank register
    // -------------------------------------------------------------------------
    logic active_bank;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)            active_bank <= 1'b0;
        else if (bank_commit_i)  active_bank <= bin_bank_i[0];
    end

    // -------------------------------------------------------------------------
    // Gain-table write port (SPI -> inactive bank)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (bin_we_i) begin
            if (bin_bank_i[0] == 1'b0) gain_bank_a[bin_addr_i] <= bin_wdata_i;
            else                        gain_bank_b[bin_addr_i] <= bin_wdata_i;
        end
    end

    // -------------------------------------------------------------------------
    // Bin counter (tracks FFT bin index, 0..127)
    // -------------------------------------------------------------------------
    // Hermitian bin wrapping: The 256-point FFT (natural-order output)
    // produces bins sequentially:
    //   bin 0:            DC component (real)
    //   bins 1..127:      positive frequencies
    //   bin 128:          Nyquist frequency (real, self-conjugate)
    //   bins 129..255:    negative frequencies
    //
    // For a real input, the FFT obeys X[256-k] = conj(X[k]) for k=1..127.
    // This module processes all 256 bins with a 7-bit counter (0..127):
    //
    //   FFT bin k          Counter    Gain applied
    //   ------------------------------------------
    //   0..127              k          gain[k]
    //   128                 0          gain[0]         (wraps to 0)
    //   129..255            k-128      gain[k-128]     (wraps into 0..127)
    //
    // Equivalently, bin (256-k) for k=1..127 maps to gain[128-k]:
    //   Y[256-k] = gain[128-k] * X[256-k]
    //            = gain[128-k] * conj(X[k])      [FFT symmetry]
    //
    // For the IFFT to produce real output, Y must also be Hermitian:
    //   Y[256-k] = conj(Y[k])
    //            = conj(gain[k] * X[k])
    //            = gain[k] * conj(X[k])           [gains are real Q2.14]
    //
    // Equating the two expressions:
    //   gain[128-k] = gain[k]    for k = 1..127
    //
    // This is a palindromic constraint on gain[1..127]; gain[0] is
    // unconstrained but applies to both DC (bin 0) and Nyquist (bin 128).
    //
    // MVP uses unity gain (trivially satisfies this). Phase 4 per-mode
    // tables must enforce this symmetry or add a hardware mirror stage
    // for bins 129..255.
    logic [ADDR_W-1:0] bin_idx;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)        bin_idx <= '0;
        else if (in_v_i)     bin_idx <= bin_idx + 1'b1;
    end

    // -------------------------------------------------------------------------
    // Pipeline stage 1: read gain from active bank
    // -------------------------------------------------------------------------
    logic [DATA_W-1:0] gain_s1;
    logic [DATA_W-1:0] in_re_s1, in_im_s1;
    logic              in_v_s1,  in_last_s1;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            gain_s1    <= '0;
            in_re_s1   <= '0;
            in_im_s1   <= '0;
            in_v_s1    <= 1'b0;
            in_last_s1 <= 1'b0;
        end else begin
            if (active_bank == 1'b0) gain_s1 <= gain_bank_a[bin_idx];
            else                     gain_s1 <= gain_bank_b[bin_idx];
            in_re_s1   <= in_re_i;
            in_im_s1   <= in_im_i;
            in_v_s1    <= in_v_i;
            in_last_s1 <= in_last_i;
        end
    end

    // -------------------------------------------------------------------------
    // Pipeline stage 2: effective_gain = gain_s1 * master_gain_i (Q2.14)
    // -------------------------------------------------------------------------
    logic signed [DATA_W-1:0] eff_gain_s2;
    logic [DATA_W-1:0]        in_re_s2, in_im_s2;
    logic                     in_v_s2,  in_last_s2;
    logic signed [31:0]       eff_mul;

    assign eff_mul = $signed(gain_s1) * $signed(master_gain_i);

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            eff_gain_s2 <= '0;
            in_re_s2    <= '0;
            in_im_s2    <= '0;
            in_v_s2     <= 1'b0;
            in_last_s2  <= 1'b0;
        end else begin
            eff_gain_s2 <= eff_mul[29:14];
            in_re_s2    <= in_re_s1;
            in_im_s2    <= in_im_s1;
            in_v_s2     <= in_v_s1;
            in_last_s2  <= in_last_s1;
        end
    end

    // -------------------------------------------------------------------------
    // Pipeline stage 3: compute |X|^2 = re^2 + im^2
    // -------------------------------------------------------------------------
    logic signed [31:0] mag_sq_s3;
    logic signed [DATA_W-1:0] eff_gain_s3;
    logic [DATA_W-1:0]        in_re_s3, in_im_s3;
    logic                     in_v_s3,  in_last_s3;
    logic signed [31:0]       re_sq, im_sq;

    assign re_sq = $signed(in_re_s2) * $signed(in_re_s2);
    assign im_sq = $signed(in_im_s2) * $signed(in_im_s2);

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mag_sq_s3   <= '0;
            eff_gain_s3 <= '0;
            in_re_s3    <= '0;
            in_im_s3    <= '0;
            in_v_s3     <= 1'b0;
            in_last_s3  <= 1'b0;
        end else begin
            mag_sq_s3   <= re_sq + im_sq;
            eff_gain_s3 <= eff_gain_s2;
            in_re_s3    <= in_re_s2;
            in_im_s3    <= in_im_s2;
            in_v_s3     <= in_v_s2;
            in_last_s3  <= in_last_s2;
        end
    end

    // -------------------------------------------------------------------------
    // Pipeline stage 4: noise gate decision + final multiply
    // -------------------------------------------------------------------------
    // If |X|^2 < noise_floor: gated_gain = gate_ratio (attenuated)
    // Else:                   gated_gain = eff_gain_s3
    logic signed [DATA_W-1:0] gated_gain;
    logic                     gate_open;
    logic signed [31:0]       mul_re, mul_im;
    logic                     gate_mag_is_pos; // mag_sq is unsigned; treat as >=0

    // The noise_floor_i is a 16-bit Q2.14 magnitude-squared threshold.
    // |X|^2 is a 32-bit signed value, but since it's a sum of squares
    // it is always >= 0.  We compare it as unsigned.
    assign gate_mag_is_pos = ~mag_sq_s3[31];

    always_comb begin
        if (gate_mag_is_pos &&
            ($unsigned(mag_sq_s3) < $unsigned(noise_floor_i)))
            gate_open = 1'b0;
        else
            gate_open = 1'b1;
    end

    always_comb begin
        if (gate_open) gated_gain = eff_gain_s3;
        else           gated_gain = $signed(gate_ratio_i);
    end

    assign mul_re = $signed(in_re_s3) * gated_gain;
    assign mul_im = $signed(in_im_s3) * gated_gain;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            out_re_o  <= '0;
            out_im_o  <= '0;
            out_v_o   <= 1'b0;
            out_last_o<= 1'b0;
        end else begin
            out_re_o  <= mul_re[29:14];
            out_im_o  <= mul_im[29:14];
            out_v_o   <= in_v_s3;
            out_last_o<= in_last_s3;
        end
    end

    // -------------------------------------------------------------------------
    // Synthesis-time sanity
    // -------------------------------------------------------------------------
    initial begin
        if (N_BINS != 128)
            $display("WARNING: spectral_proc N_BINS=%0d, expected 128", N_BINS);
    end

endmodule : spectral_proc

`default_nettype wire
