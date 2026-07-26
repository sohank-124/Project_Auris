// =============================================================================
// File:        top.sv
// Project:     Project Auris
// Module:      top
// Description: Top-level wrapper for the Cmod S7-25 FPGA (XC7S25-1CSGA225C).
//              Integrates every sub-module of the design:
//
//                * clk_gen            — 12 MHz → 96 MHz via MMCME2_BASE
//                * reset generators   — 2-FF sync + 16-cycle SRL stretcher
//                                       in each of 3 clock domains
//                * i2s_rx / i2s_tx    — INMP441 / PCM5102A bridges
//                * spi_slave          — ESP32 register-access interface
//                * cdc_i2s_to_dsp x2  — left + right audio path (RX)
//                * cdc_dsp_to_i2s x2  — left + right audio path (TX)
//                * cdc_spi_to_dsp     — control-path handshake
//                * cdc_dsp_to_spi     — read-data 2-FF sync
//                * reg_file           — SPI-facing register storage
//                * mode_ctrl          — mode → default gain tables
//                * dsp_pipeline       — full spectral processing chain
//                * status_mon         — heartbeat + clip-event latch
//
//              The RGB LED colour is mode-dependent (active-low drive)
//              and provides at-a-glance status feedback without the
//              need for a console.
//
// Author:      [generated]
// Created:     2026-07
// Target:      Digilent Cmod S7-25 (XC7S25-1CSGA225C)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module top import auris_pkg::*; #(
    parameter int unsigned FFT_LEN = auris_pkg::FFT_LEN
) (
    // -----------------------------------------------------------------------
    // Power / programming
    // -----------------------------------------------------------------------
    input  wire        clk_12mhz,         // onboard 12 MHz oscillator

    // -----------------------------------------------------------------------
    // Pmod JA: SPI to ESP32 + 2 status pins
    //   Pin assignments: see cmod_s7_25.xdc
    //   JA1=SCLK, JA2=MOSI, JA3=MISO, JA4=CS, JA7=STATUS0, JA8=STATUS1
    // -----------------------------------------------------------------------
    (* clock_buffer_type = "none" *)
    input  wire        spi_sclk_i,
    input  wire        spi_mosi_i,
    output wire        spi_miso_o,
    input  wire        spi_cs_n_i,
    output wire        status_led_o,       // STATUS0: heartbeat / ready
    output wire        status_clip_o,      // STATUS1: clipping indicator

    // -----------------------------------------------------------------------
    // Pmod JA (pins 7-10): I2S to/from ESP32 I2S peripheral
    //   Note: ESP32 is the I2S master, FPGA is the slave
    //   JA7=BCLK_IN,  JA8=LRCLK_IN, JA9=ADC_DATA, JA10=DAC_DATA
    // -----------------------------------------------------------------------
    (* clock_buffer_type = "none" *)
    input  wire        i2s_bclk_i,
    input  wire        i2s_lrclk_i,        // 0 = left, 1 = right
    input  wire        i2s_adc_data_i,     // from INMP441
    output wire        i2s_dac_data_o,     // to PCM5102A

    // -----------------------------------------------------------------------
    // Onboard RGB LED (active low on Cmod S7-25)
    // -----------------------------------------------------------------------
    output logic       led_rgb_r,
    output logic       led_rgb_g,
    output logic       led_rgb_b
);

    // -------------------------------------------------------------------------
    // Local nets — clock and reset
    // -------------------------------------------------------------------------
    logic clk_96mhz;          // DSP clock from MMCM
    logic clk_dsp_locked;     // MMCM lock signal -> system reset source
    logic rst_dsp_n;          // active-low reset in DSP domain
    logic rst_i2s_n;          // active-low reset in I2S BCLK domain
    logic rst_spi_n;          // active-low reset in SPI SCLK domain

    // -------------------------------------------------------------------------
    // Local nets — I2S RX path (BCLK domain)
    // -------------------------------------------------------------------------
    logic [I2S_DATA_W-1:0] i2s_rx_l_data;
    logic [I2S_DATA_W-1:0] i2s_rx_r_data;
    logic                  i2s_rx_valid;
    logic                  i2s_rx_overflow;

    // -------------------------------------------------------------------------
    // Local nets — I2S TX path (BCLK domain)
    // -------------------------------------------------------------------------
    logic [I2S_DATA_W-1:0] i2s_tx_l_data;
    logic [I2S_DATA_W-1:0] i2s_tx_r_data;
    logic                  i2s_tx_valid;
    logic                  i2s_tx_underflow;

    // -------------------------------------------------------------------------
    // Local nets — SPI path (SCLK domain, 10 MHz)
    // -------------------------------------------------------------------------
    logic [6:0]            spi_addr;
    logic [23:0]           spi_wdata;
    logic                  spi_we;
    logic                  spi_re;
    logic [23:0]           spi_rdata;
    logic                  spi_rdata_valid;

    // -------------------------------------------------------------------------
    // Local nets — DSP-facing control / status
    // -------------------------------------------------------------------------
    logic [1:0]            reg_dsp_mode;
    logic [23:0]           reg_dsp_master_gain;
    logic [23:0]           reg_dsp_noise_floor;
    logic [23:0]           reg_dsp_gate_ratio;
    logic [6:0]            reg_dsp_gain_addr;
    logic [15:0]           reg_dsp_gain_wdata;
    logic                  reg_dsp_gain_we;
    logic [1:0]            reg_dsp_gain_bank_id;
    logic                  reg_dsp_bank_commit;

    logic                  mode_bank_we;
    logic [6:0]            mode_bank_addr;
    logic [15:0]           mode_bank_wdata;
    logic [1:0]            mode_bank_sel;
    logic                  mode_bank_commit;

    logic [23:0]           mode_default_master_gain;
    logic [23:0]           mode_default_noise_floor;
    logic [23:0]           mode_default_gate_ratio;

    logic [23:0]           dsp_peak_in;
    logic [23:0]           dsp_peak_out;
    logic [31:0]           dsp_frame_count;
    logic [7:0]            dsp_error_flags;
    logic                  dsp_clip_event;

    // -------------------------------------------------------------------------
    // CDC nets — I2S → DSP (post-CDC signals, in DSP domain)
    // -------------------------------------------------------------------------
    logic [I2S_DATA_W-1:0] dsp_sample_l;
    logic [I2S_DATA_W-1:0] dsp_sample_r;
    logic                  dsp_sample_valid;

    // -------------------------------------------------------------------------
    // CDC nets — DSP → I2S (post-CDC signals, in BCLK domain)
    // -------------------------------------------------------------------------
    logic                  i2s_tx_l_empty;
    logic                  i2s_tx_r_empty;

    // -------------------------------------------------------------------------
    // CDC nets — SPI ↔ DSP
    // -------------------------------------------------------------------------
    logic [6:0]            cdc_dst_addr;
    logic [23:0]           cdc_dst_wdata;
    logic                  cdc_dst_we;
    logic                  cdc_dst_re;

    // -------------------------------------------------------------------------
    // Mode-change pulse for mode_ctrl
    // -------------------------------------------------------------------------
    // reg_file doesn't expose a "mode was written" strobe, so we
    // synthesise one in top by edge-detecting the mode register.
    logic [1:0]            reg_dsp_mode_d;
    logic                  mode_we_pulse;

    // -------------------------------------------------------------------------
    // DSP pipeline outputs (declared here because dsp_pipeline is instantiated
    // later in the file but its outputs are needed by the DSP->I2S CDC FIFOs
    // and by the valid-pulse generator below)
    // -------------------------------------------------------------------------
    logic [23:0]           dsp_out_l;
    logic [23:0]           dsp_out_r;
    logic                  dsp_out_valid;

    // -------------------------------------------------------------------------
    // DSP-domain output strobe (1-cycle pulse per new output sample)
    // -------------------------------------------------------------------------
    // SINGLE driver: the wire declaration with the continuous assignment
    // below is the only driver of dsp_out_valid_pulse.  The previous
    // duplicate `assign dsp_out_valid_pulse = ...` block (further down
    // the file) has been removed to eliminate the multi-driver error.
    logic                  dsp_out_valid_d;
    wire                   dsp_out_valid_pulse = dsp_out_valid & ~dsp_out_valid_d;

    // -------------------------------------------------------------------------
    // Local nets — control/status propagation
    // -------------------------------------------------------------------------
    // dsp_enable:        reg_file's combinational mirror of REG_CONTROL[0],
    //                    routed to dsp_pipeline.dsp_enable_i to gate the
    //                    pipeline (1 = run, 0 = bypass).
    // clip_clear_pulse:  reg_file's 1-cycle pulse on REG_STATUS read,
    //                    routed to status_mon.clip_clear_i to clear the
    //                    sticky clip-event latch.
    logic                  dsp_enable;
    logic                  clip_clear_pulse;

    // -------------------------------------------------------------------------
    // I2S-domain LRCLK falling-edge detector (BCLK-synchronous)
    // -------------------------------------------------------------------------
    logic                  i2s_lrclk_s;
    logic                  i2s_lrclk_s_d;
    wire                   i2s_lrclk_fall = i2s_lrclk_s_d & ~i2s_lrclk_s;

    // -------------------------------------------------------------------------
    // CDC FIFO empty flags (I2S → DSP, DSP domain)
    // -------------------------------------------------------------------------
    logic                  cdc_l_empty;
    logic                  cdc_r_empty;
    logic                  cdc_l_empty_d;
    logic                  cdc_r_empty_d;

    // -------------------------------------------------------------------------
    // Constants — version register values
    // -------------------------------------------------------------------------
    // FW_VERSION: bitstream semantic-version register. Encoding is
    // semver-packed into 24 bits: [23:16]=major, [15:8]=minor, [7:0]=patch.
    // 0x000100 = v0.1.0 (initial FPGA bring-up).
    localparam logic [23:0] FW_VERSION = 24'h00_01_00;
    localparam logic [23:0] HW_VERSION = {17'd0, REG_HW_VERSION};

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    clk_gen u_clk_gen (
        .clk_in1   (clk_12mhz),
        .clk_out1  (clk_96mhz),
        .locked    (clk_dsp_locked)
    );

    // -------------------------------------------------------------------------
    // Reset generators (one per clock domain)
    // -------------------------------------------------------------------------
    // Each generator:
    //   * 2-FF synchronises the source reset into the destination clock
    //   * 16-bit shift register provides the 16-cycle stretch
    //   * Async assert (via async clear of the FFs)
    //   * Sync deassert (via the shift register filling with 1s)
    // -------------------------------------------------------------------------

    reset_sync_stretch #(
        .STRETCH_CYCLES (RESET_STRETCH_CYCLES)
    ) u_rst_dsp (
        .src_rst_n_i (clk_dsp_locked),
        .dst_clk_i   (clk_96mhz),
        .dst_rst_n_o (rst_dsp_n)
    );

    reset_sync_stretch #(
        .STRETCH_CYCLES (RESET_STRETCH_CYCLES)
    ) u_rst_i2s (
        .src_rst_n_i (clk_dsp_locked),
        .dst_clk_i   (i2s_bclk_i),
        .dst_rst_n_o (rst_i2s_n)
    );

    reset_sync_stretch #(
        .STRETCH_CYCLES (RESET_STRETCH_CYCLES)
    ) u_rst_spi (
        .src_rst_n_i (clk_dsp_locked),
        .dst_clk_i   (spi_sclk_i),
        .dst_rst_n_o (rst_spi_n)
    );

    // -------------------------------------------------------------------------
    // I2S LRCLK 2-FF synchroniser (for the DSP → I2S CDC consume pulse)
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) logic [1:0] i2s_lrclk_sync;
    always_ff @(posedge i2s_bclk_i or negedge rst_i2s_n) begin
        if (!rst_i2s_n) i2s_lrclk_sync <= 2'b00;
        else            i2s_lrclk_sync <= {i2s_lrclk_sync[0], i2s_lrclk_i};
    end
    assign i2s_lrclk_s   = i2s_lrclk_sync[1];
    always_ff @(posedge i2s_bclk_i or negedge rst_i2s_n) begin
        if (!rst_i2s_n) i2s_lrclk_s_d <= 1'b0;
        else            i2s_lrclk_s_d <= i2s_lrclk_s;
    end

    // -------------------------------------------------------------------------
    // I2S slave receiver
    // -------------------------------------------------------------------------
    i2s_rx #(
        .DATA_W (I2S_DATA_W)
    ) u_i2s_rx (
        .bclk_i      (i2s_bclk_i),
        .lrclk_i     (i2s_lrclk_i),
        .sdata_i     (i2s_adc_data_i),
        .rst_n_i     (rst_i2s_n),
        .left_o      (i2s_rx_l_data),
        .right_o     (i2s_rx_r_data),
        .valid_o     (i2s_rx_valid),
        .overflow_o  (i2s_rx_overflow)
    );

    // -------------------------------------------------------------------------
    // I2S slave transmitter
    // -------------------------------------------------------------------------
    // The TX consumes a sample from the CDC every LRCLK falling edge
    // when the CDC is non-empty.  valid_i is the level "data available"
    // signal; the i2s_tx module samples it combinationally at the
    // LRCLK falling edge.
    assign i2s_tx_valid = !i2s_tx_l_empty & !i2s_tx_r_empty;

    i2s_tx #(
        .DATA_W (I2S_DATA_W)
    ) u_i2s_tx (
        .bclk_i      (i2s_bclk_i),
        .lrclk_i     (i2s_lrclk_i),
        .sdata_o     (i2s_dac_data_o),
        .rst_n_i     (rst_i2s_n),
        .left_i      (i2s_tx_l_data),
        .right_i     (i2s_tx_r_data),
        .valid_i     (i2s_tx_valid),
        .underflow_o (i2s_tx_underflow)
    );

    // -------------------------------------------------------------------------
    // I2S → DSP CDC (left and right channels)
    // -------------------------------------------------------------------------
    cdc_i2s_to_dsp #(
        .WIDTH (I2S_DATA_W),
        .DEPTH (CDC_FIFO_DEPTH)
    ) u_cdc_i2s_l (
        .wr_clk_i  (i2s_bclk_i),
        .wr_rst_n_i(rst_i2s_n),
        .wr_en_i   (i2s_rx_valid),
        .wr_data_i (i2s_rx_l_data),
        .rd_clk_i  (clk_96mhz),
        .rd_rst_n_i(rst_dsp_n),
        .rd_en_i   (dsp_sample_valid),
        .rd_data_o (dsp_sample_l),
        .rd_valid_o(),
        .rd_empty_o(cdc_l_empty),
        .wr_full_o ()
    );

    cdc_i2s_to_dsp #(
        .WIDTH (I2S_DATA_W),
        .DEPTH (CDC_FIFO_DEPTH)
    ) u_cdc_i2s_r (
        .wr_clk_i  (i2s_bclk_i),
        .wr_rst_n_i(rst_i2s_n),
        .wr_en_i   (i2s_rx_valid),
        .wr_data_i (i2s_rx_r_data),
        .rd_clk_i  (clk_96mhz),
        .rd_rst_n_i(rst_dsp_n),
        .rd_en_i   (dsp_sample_valid),
        .rd_data_o (dsp_sample_r),
        .rd_valid_o(),
        .rd_empty_o(cdc_r_empty),
        .wr_full_o ()
    );

    // Pulse generator: 1-cycle dsp_sample_valid per "empty -> non-empty"
    // transition.  Because the I2S rate (48 kHz) is far slower than the
    // DSP clock (96 MHz) the FIFOs stay at 0–1 entries, so the rising
    // edge fires exactly once per new I2S frame.
    always_ff @(posedge clk_96mhz or negedge rst_dsp_n) begin
        if (!rst_dsp_n) begin
            cdc_l_empty_d <= 1'b1;
            cdc_r_empty_d <= 1'b1;
        end else begin
            cdc_l_empty_d <= cdc_l_empty;
            cdc_r_empty_d <= cdc_r_empty;
        end
    end
    assign dsp_sample_valid = !cdc_l_empty && cdc_l_empty_d;

    // -------------------------------------------------------------------------
    // DSP → I2S CDC (left and right channels)
    // -------------------------------------------------------------------------
    // The DSP pushes one L/R pair per dsp_out_valid_pulse; the I2S TX
    // pulls one L/R pair per LRCLK falling edge.  The CDC depth (4)
    // absorbs any short-term rate mismatch.
    cdc_dsp_to_i2s #(
        .WIDTH (I2S_DATA_W),
        .DEPTH (CDC_FIFO_DEPTH)
    ) u_cdc_o2i_l (
        .wr_clk_i  (clk_96mhz),
        .wr_rst_n_i(rst_dsp_n),
        .wr_en_i   (dsp_out_valid_pulse),
        .wr_data_i (dsp_out_l),
        .rd_clk_i  (i2s_bclk_i),
        .rd_rst_n_i(rst_i2s_n),
        .rd_en_i   (i2s_lrclk_fall & !i2s_tx_l_empty),
        .rd_data_o (i2s_tx_l_data),
        .rd_valid_o(),
        .rd_empty_o(i2s_tx_l_empty),
        .wr_full_o ()
    );

    cdc_dsp_to_i2s #(
        .WIDTH (I2S_DATA_W),
        .DEPTH (CDC_FIFO_DEPTH)
    ) u_cdc_o2i_r (
        .wr_clk_i  (clk_96mhz),
        .wr_rst_n_i(rst_dsp_n),
        .wr_en_i   (dsp_out_valid_pulse),
        .wr_data_i (dsp_out_r),
        .rd_clk_i  (i2s_bclk_i),
        .rd_rst_n_i(rst_i2s_n),
        .rd_en_i   (i2s_lrclk_fall & !i2s_tx_r_empty),
        .rd_data_o (i2s_tx_r_data),
        .rd_valid_o(),
        .rd_empty_o(i2s_tx_r_empty),
        .wr_full_o ()
    );

    // Edge-detect dsp_out_valid to produce a single-cycle write strobe
    // for the CDC.  dsp_out_valid is the DSP pipeline's per-sample
    // valid; the rising edge corresponds to a new output sample.
    // The dsp_out_valid_d register below drives the single-source
    // continuous assignment above (line ~177).  No additional `assign`
    // is permitted here — that would create a multi-driver.
    always_ff @(posedge clk_96mhz or negedge rst_dsp_n) begin
        if (!rst_dsp_n) dsp_out_valid_d <= 1'b0;
        else            dsp_out_valid_d <= dsp_out_valid;
    end

    // -------------------------------------------------------------------------
    // SPI slave
    // -------------------------------------------------------------------------
    spi_slave #(
        .ADDR_W (7),
        .DATA_W (24)
    ) u_spi_slave (
        .sclk_i        (spi_sclk_i),
        .cs_n_i        (spi_cs_n_i),
        .mosi_i        (spi_mosi_i),
        .miso_o        (spi_miso_o),
        .rst_n_i       (rst_spi_n),
        .addr_o        (spi_addr),
        .wdata_o       (spi_wdata),
        .we_o          (spi_we),
        .re_o          (spi_re),
        .rdata_i       (spi_rdata),
        .rdata_valid_i (spi_rdata_valid)
    );

    // -------------------------------------------------------------------------
    // SPI → DSP CDC (handshake)
    // -------------------------------------------------------------------------
    cdc_spi_to_dsp #(
        .ADDR_W (7),
        .DATA_W (24)
    ) u_cdc_spi_dsp (
        .src_clk_i   (spi_sclk_i),
        .src_rst_n_i (rst_spi_n),
        .src_addr_i  (spi_addr),
        .src_wdata_i (spi_wdata),
        .src_we_i    (spi_we),
        .src_re_i    (spi_re),
        .src_ack_o   (),
        .dst_clk_i   (clk_96mhz),
        .dst_rst_n_i (rst_dsp_n),
        .dst_addr_o  (cdc_dst_addr),
        .dst_wdata_o (cdc_dst_wdata),
        .dst_we_o    (cdc_dst_we),
        .dst_re_o    (cdc_dst_re)
    );

    // -------------------------------------------------------------------------
    // DSP → SPI CDC (read-data return)
    // -------------------------------------------------------------------------
    // Note: this CDC's outputs drive the spi_slave's rdata_i and
    // rdata_valid_i.  The reg_file's rdata/rdata_valid outputs are
    // wired into this CDC's source side.
    cdc_dsp_to_spi #(
        .DATA_W (24)
    ) u_cdc_dsp_spi (
        .src_clk_i   (clk_96mhz),
        .src_rst_n_i (rst_dsp_n),
        .src_rdata_i (spi_rdata_regfile),  // tied to reg_file below
        .src_valid_i (spi_rdata_valid_regfile),
        .dst_clk_i   (spi_sclk_i),
        .dst_rst_n_i (rst_spi_n),
        .dst_rdata_o (spi_rdata),
        .dst_valid_o (spi_rdata_valid)
    );

    // -------------------------------------------------------------------------
    // Register file
    // -------------------------------------------------------------------------
    // The reg_file's rdata and rdata_valid outputs feed the DSP→SPI CDC.
    logic [23:0] spi_rdata_regfile;
    logic        spi_rdata_valid_regfile;

    reg_file #(
        .ADDR_W (7),
        .DATA_W (24)
    ) u_reg_file (
        .clk_i        (clk_96mhz),
        .rst_n_i      (rst_dsp_n),
        .addr_i       (cdc_dst_addr),
        .wdata_i      (cdc_dst_wdata),
        .we_i         (cdc_dst_we),
        .re_i         (cdc_dst_re),
        .rdata_o      (spi_rdata_regfile),
        .rdata_valid_o(spi_rdata_valid_regfile),
        // DSP-facing outputs:
        .dsp_mode_o   (reg_dsp_mode),
        .master_gain_o(reg_dsp_master_gain),
        .noise_floor_o(reg_dsp_noise_floor),
        .gate_ratio_o (reg_dsp_gate_ratio),
        .gain_addr_o  (reg_dsp_gain_addr),
        .gain_wdata_o (reg_dsp_gain_wdata),
        .gain_we_o    (reg_dsp_gain_we),
        .gain_bank_o  (reg_dsp_gain_bank_id),
        .bank_commit_o(reg_dsp_bank_commit),
        .dsp_enable_o (dsp_enable),           // -> dsp_pipeline.dsp_enable_i
        // Read-only status inputs:
        .peak_in_i    (dsp_peak_in),
        .peak_out_i   (dsp_peak_out),
        .frame_count_i(dsp_frame_count),
        .error_flags_i(dsp_error_flags),
        // Sticky clip-event indicator (REG_STATUS bit 2, STATUS_CLIP).
        // Driven by status_mon's clip_latch so a slow-polling host can
        // still see the latched event.
        .clip_flag_i  (status_clip_latch),
        .fw_version_i (FW_VERSION),
        .hw_version_i (HW_VERSION),
        // Live health signals for REG_STATUS bits 1:0.
        .dsp_ready_i  (clk_dsp_locked & rst_dsp_n),
        .cdc_locked_i (rst_dsp_n & rst_i2s_n & rst_spi_n),
        // Read-side-effect: 1-cycle pulse on REG_STATUS read, clears the
        // sticky clip latch via status_mon.clip_clear_i.
        .clip_clear_o (clip_clear_pulse)
    );

    // -------------------------------------------------------------------------
    // Mode controller (loads default gain tables on a mode change)
    // -------------------------------------------------------------------------
    // Edge-detect the mode register to generate a 1-cycle mode_we_pulse.
    always_ff @(posedge clk_96mhz or negedge rst_dsp_n) begin
        if (!rst_dsp_n) begin
            reg_dsp_mode_d <= MODE_GENERAL;
            mode_we_pulse  <= 1'b0;
        end else begin
            reg_dsp_mode_d <= reg_dsp_mode;
            mode_we_pulse  <= (reg_dsp_mode != reg_dsp_mode_d);
        end
    end

    mode_ctrl #(
        .N_BINS (GAIN_TABLE_DEPTH)
    ) u_mode_ctrl (
        .clk_i               (clk_96mhz),
        .rst_n_i             (rst_dsp_n),
        .mode_i              (reg_dsp_mode),
        .mode_we_i           (mode_we_pulse),
        .bank_we_o           (mode_bank_we),
        .bank_addr_o         (mode_bank_addr),
        .bank_wdata_o        (mode_bank_wdata),
        .bank_sel_o          (mode_bank_sel),
        .bank_commit_o       (mode_bank_commit),
        .default_master_gain_o (mode_default_master_gain),
        .default_noise_floor_o (mode_default_noise_floor),
        .default_gate_ratio_o  (mode_default_gate_ratio)
    );

    // -------------------------------------------------------------------------
    // Mux between mode_ctrl's table-load and reg_file's per-bin write
    // -------------------------------------------------------------------------
    // mode_ctrl takes priority (it owns the inactive bank during a
    // table load).  reg_file's per-bin write is used the rest of the
    // time so the host can fine-tune individual bins.
    wire        dsp_gain_we     = mode_bank_we     | reg_dsp_gain_we;
    wire [6:0]  dsp_gain_addr   = mode_bank_we     ? mode_bank_addr      : reg_dsp_gain_addr;
    wire [15:0] dsp_gain_wdata  = mode_bank_we     ? mode_bank_wdata     : reg_dsp_gain_wdata;
    wire [1:0]  dsp_gain_bank   = mode_bank_we     ? mode_bank_sel       : reg_dsp_gain_bank_id;
    wire        dsp_bank_commit = mode_bank_commit | reg_dsp_bank_commit;

    // -------------------------------------------------------------------------
    // DSP pipeline
    // -------------------------------------------------------------------------
    dsp_pipeline #(
        .FFT_LEN (FFT_LEN)
    ) u_dsp_pipeline (
        .clk_i           (clk_96mhz),
        .rst_n_i         (rst_dsp_n),
        // From I2S RX (post-CDC, 48 kHz strobe)
        .sample_l_i      (dsp_sample_l),
        .sample_r_i      (dsp_sample_r),
        .sample_valid_i  (dsp_sample_valid),
        // To I2S TX
        .out_l_o         (dsp_out_l),
        .out_r_o         (dsp_out_r),
        .out_valid_o     (dsp_out_valid),
        // Control
        .mode_i          (reg_dsp_mode),
        .master_gain_i   (reg_dsp_master_gain),
        .noise_floor_i   (reg_dsp_noise_floor),
        .gate_ratio_i    (reg_dsp_gate_ratio),
        .dsp_enable_i    (dsp_enable),         // <-- from reg_file (REG_CONTROL[0])
        .gain_addr_i     (dsp_gain_addr),
        .gain_wdata_i    (dsp_gain_wdata),
        .gain_we_i       (dsp_gain_we),
        .gain_bank_i     (dsp_gain_bank),
        .bank_commit_i   (dsp_bank_commit),
        // Telemetry
        .peak_in_o       (dsp_peak_in),
        .peak_out_o      (dsp_peak_out),
        .frame_count_o   (dsp_frame_count),
        .error_flags_o   (dsp_error_flags),
        .clip_event_o    (dsp_clip_event)
    );

    // -------------------------------------------------------------------------
    // Status / heartbeat
    // -------------------------------------------------------------------------
    logic status_heartbeat;
    logic status_clip_latch;

    status_mon #(
        .CLK_FREQ_HZ  (96_000_000),
        .HEARTBEAT_HZ (1)
    ) u_status_mon (
        .clk_i        (clk_96mhz),
        .rst_n_i      (rst_dsp_n),
        .dsp_ready_i  (clk_dsp_locked & rst_dsp_n),
        .clip_event_i (dsp_clip_event),
        // Cleared by a 1-cycle pulse from reg_file when the host reads
        // REG_STATUS (the host polls then clears idiom for sticky flags).
        .clip_clear_i (clip_clear_pulse),
        .heartbeat_o  (status_heartbeat),
        .clip_latch_o (status_clip_latch)
    );

    assign status_led_o  = status_heartbeat;
    assign status_clip_o = status_clip_latch;

    // -------------------------------------------------------------------------
    // RGB LED (mode-dependent, active-low drive)
    // -------------------------------------------------------------------------
    // General -> green     (R=1, G=0, B=1)
    // Hearing -> blue      (R=1, G=1, B=0)
    // Speech  -> cyan      (R=1, G=0, B=0)
    // Bypass  -> red       (R=0, G=1, B=1)
    always_comb begin
        led_rgb_r = 1'b1;
        led_rgb_g = 1'b1;
        led_rgb_b = 1'b1;
        case (reg_dsp_mode)
            MODE_GENERAL: begin
                led_rgb_r = 1'b1;
                led_rgb_g = 1'b0;
                led_rgb_b = 1'b1;
            end
            MODE_HEARING: begin
                led_rgb_r = 1'b1;
                led_rgb_g = 1'b1;
                led_rgb_b = 1'b0;
            end
            MODE_SPEECH: begin
                led_rgb_r = 1'b1;
                led_rgb_g = 1'b0;
                led_rgb_b = 1'b0;
            end
            MODE_BYPASS: begin
                led_rgb_r = 1'b0;
                led_rgb_g = 1'b1;
                led_rgb_b = 1'b1;
            end
            default: begin
                led_rgb_r = 1'b1;
                led_rgb_g = 1'b1;
                led_rgb_b = 1'b1;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Synthesis-time configuration checks
    // -------------------------------------------------------------------------
    initial begin
        if (FFT_LEN != 256) begin
            $display("ERROR: top FFT_LEN=%0d, expected 256", FFT_LEN);
        end
    end

endmodule : top

// =============================================================================
// Helper module: reset_sync_stretch
// =============================================================================
// 2-FF synchroniser + (STRETCH_CYCLES)-bit shift register providing
// async-assert / sync-deassert reset behaviour to a destination clock
// domain.  The shift register is inferred as an SRL16E on Spartan-7.
//
// The first two stages form the 2-FF synchroniser required for safe
// CDC.  The remaining STRETCH_CYCLES stages form the reset stretcher.
// The output is the AND-reduce of the entire pipe — it goes high only
// when every bit is 1, which is STRETCH_CYCLES+2 cycles after
// src_rst_n_i goes high.
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module reset_sync_stretch #(
    parameter int unsigned STRETCH_CYCLES = 16
) (
    input  wire src_rst_n_i,    // async, asserted low, source domain
    input  wire dst_clk_i,      // destination clock
    output wire dst_rst_n_o     // stretched, sync deassert
);
    (* ASYNC_REG = "TRUE" *) logic [1:0] sync_ff;
    logic [STRETCH_CYCLES-1:0] stretch_pipe;

    always_ff @(posedge dst_clk_i or negedge src_rst_n_i) begin
        if (!src_rst_n_i) begin
            sync_ff      <= 2'b00;
            stretch_pipe <= {STRETCH_CYCLES{1'b0}};
        end else begin
            sync_ff      <= {sync_ff[0], 1'b1};
            stretch_pipe <= {stretch_pipe[STRETCH_CYCLES-2:0], 1'b1};
        end
    end

    assign dst_rst_n_o = &{sync_ff, stretch_pipe};

endmodule : reset_sync_stretch

`default_nettype wire
