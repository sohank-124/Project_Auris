// =============================================================================
// File:        dsp_pipeline.sv
// Project:     Project Auris — FPGA-Accelerated Assistive Audio
// Module:      dsp_pipeline
// Description: Top-level wrapper for the spectral audio processing chain
//              in the CD_DSP clock domain (96 MHz).
//
//              Data flow:
//                I2S_RX -> input_buffer -> window_apply -> fft_256
//                -> spectral_proc -> ifft_256 -> overlap_add
//                -> output_buffer -> I2S_TX
//
//              Bypass mode (dsp_enable_i=0): the pipeline is bypassed
//              and input samples are passed straight to the output
//              (registered, 1 cycle).  The pipeline continues to run
//              internally but its output is ignored.
//
//              Telemetry:
//                - peak_in_o:   peak absolute value of sample_l_i
//                - peak_out_o:  peak absolute value of out_l_o
//                - frame_count_o: incremented on every frame_done pulse
//                - error_flags_o: 8-bit field collected from sub-modules
//                - clip_event_o: pulse when |sample_l_i| >= 24'sd8388607
//
// Author:      [generated]
// Created:     2026-07
// Clock Domain: CD_DSP (96 MHz)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module dsp_pipeline import auris_pkg::*; #(
    parameter int unsigned FFT_LEN = auris_pkg::FFT_LEN
) (
    input  wire                    clk_i,
    input  wire                    rst_n_i,

    // Sample input (post-CDC, 48 kHz strobe)
    input  wire [23:0]             sample_l_i,
    input  wire [23:0]             sample_r_i,
    input  wire                    sample_valid_i,

    // Sample output (to CDC, 48 kHz strobe)
    output logic [23:0]            out_l_o,
    output logic [23:0]            out_r_o,
    output logic                   out_valid_o,

    // Control
    input  wire [1:0]              mode_i,
    input  wire [23:0]             master_gain_i,
    input  wire [23:0]             noise_floor_i,
    input  wire [23:0]             gate_ratio_i,
    input  wire                    dsp_enable_i,
    input  wire [4:0]              volume_i,      // 0=mute, 31=unity

    // Gain-table write interface (passed through to spectral_proc)
    input  wire [6:0]              gain_addr_i,
    input  wire [15:0]             gain_wdata_i,
    input  wire                    gain_we_i,
    input  wire [1:0]              gain_bank_i,
    input  wire                    bank_commit_i,

    // Telemetry
    output logic [23:0]            peak_in_o,
    output logic [23:0]            peak_out_o,
    output logic [31:0]            frame_count_o,
    output logic [7:0]             error_flags_o,
    output logic                   clip_event_o
);

    // -------------------------------------------------------------------------
    // Internal nets — input_buffer -> window_apply
    // -------------------------------------------------------------------------
    logic [23:0]  ibuf_l, ibuf_r;
    logic         ibuf_v;
    logic         ibuf_frame_ready;
    logic         ibuf_busy;
    logic         ibuf_overflow;

    // -------------------------------------------------------------------------
    // Internal nets — window_apply -> fft_256
    // -------------------------------------------------------------------------
    logic [15:0]  win_re, win_im;
    logic         win_v;

    // -------------------------------------------------------------------------
    // FFT TLAST generation (256-sample frame marker)
    // -------------------------------------------------------------------------
    // The xfft IP uses TLAST to mark the last sample of a 256-sample
    // frame.  A constant-1 TLAST corrupts the FFT's internal frame
    // tracking.  We count 0..255 on win_v and assert fft_tlast for
    // exactly one cycle on the 256th sample (index 255).
    logic [7:0]   fft_sample_cnt;
    logic         fft_tlast;

    // -------------------------------------------------------------------------
    // Internal nets — fft_256 -> spectral_proc
    // -------------------------------------------------------------------------
    logic [15:0]  fft_re, fft_im;
    logic         fft_v;
    logic         fft_last;

    // -------------------------------------------------------------------------
    // Internal nets — spectral_proc -> ifft_256
    // -------------------------------------------------------------------------
    logic [15:0]  sp_re, sp_im;
    logic         sp_v;
    logic         sp_last;

    // -------------------------------------------------------------------------
    // IFFT TLAST generation (256-sample frame marker)
    // -------------------------------------------------------------------------
    // Same pattern as the FFT TLAST generator above, but driven by
    // sp_v (spectral_proc's output valid) so the IFFT receives a
    // proper last-sample marker for its 256-point frame.
    logic [7:0]   ifft_sample_cnt;
    logic         ifft_tlast;

    // -------------------------------------------------------------------------
    // Internal nets — ifft_256 -> overlap_add
    // -------------------------------------------------------------------------
    logic [15:0]  ifft_re, ifft_im;
    logic         ifft_v;
    logic         ifft_last;

    // -------------------------------------------------------------------------
    // BFP exponent pipeline (see auris_pkg::BFP_PIPE_DELAY)
    // -------------------------------------------------------------------------
    logic [7:0]   fft_blk_exp;
    logic [7:0]   ifft_blk_exp;
    logic [7:0]   fft_exp_pipe [0:auris_pkg::BFP_PIPE_DELAY-1];
    logic [7:0]   fft_exp_aligned;
    logic [7:0]   ola_scale_factor;

    // -------------------------------------------------------------------------
    // Internal nets — overlap_add -> output_buffer
    // -------------------------------------------------------------------------
    logic [23:0]  ola_l, ola_r;
    logic         ola_v;
    logic         ola_frame_done;

    // Internal nets — overlap_add -> volume_ctrl
    logic [23:0] vol_l, vol_r;
    logic        vol_v;

    // -------------------------------------------------------------------------
    // Internal nets — output_buffer -> output mux
    // -------------------------------------------------------------------------
    logic [23:0]  obuf_l, obuf_r;
    logic         obuf_v;
    logic         obuf_underflow;

    // -------------------------------------------------------------------------
    // Absolute-value helpers
    // -------------------------------------------------------------------------
    function automatic logic [23:0] abs24(input logic [23:0] x);
        if (x[23]) abs24 = ~x + 24'd1;  // two's complement negate
        else       abs24 = x;
    endfunction

    // -------------------------------------------------------------------------
    // Sub-module: input_buffer
    // -------------------------------------------------------------------------
    input_buffer #(
        .DEPTH  (FFT_LEN),
        .DATA_W (I2S_DATA_W)
    ) u_input_buffer (
        .clk_i       (clk_i),
        .rst_n_i     (rst_n_i),
        .sample_l_i  (sample_l_i),
        .sample_r_i  (sample_r_i),
        .sample_v_i  (sample_valid_i),
        .frame_l_o   (ibuf_l),
        .frame_r_o   (ibuf_r),
        .frame_v_o   (ibuf_v),
        .frame_ready_o(ibuf_frame_ready),
        .busy_o      (ibuf_busy),
        .overflow_o  (ibuf_overflow)
    );

    // -------------------------------------------------------------------------
    // Sub-module: window_apply
    // -------------------------------------------------------------------------
    window_apply #(
        .LEN    (FFT_LEN),
        .DATA_W (I2S_DATA_W),
        .WIN_W  (WINDOW_DATA_W)
    ) u_window_apply (
        .clk_i        (clk_i),
        .rst_n_i      (rst_n_i),
        .in_l_i       (ibuf_l),
        .in_r_i       (ibuf_r),
        .in_v_i       (ibuf_v),
        .frame_start_i(ibuf_frame_ready),
        .out_re_o     (win_re),
        .out_im_o     (win_im),
        .out_v_o      (win_v)
    );

    // -------------------------------------------------------------------------
    // Sub-module: fft_256 (forward FFT)
    // -------------------------------------------------------------------------
    fft_256 u_fft_256 (
        .aclk                      (clk_i),
        .aresetn                   (rst_n_i),
        .s_axis_data_tdata         ({win_im, win_re}),
        .s_axis_data_tvalid        (win_v),
        .s_axis_data_tready        (),
        .s_axis_data_tlast         (fft_tlast),
        .s_axis_config_tdata       (8'd1),   // FWD_INV = 1 (forward)
        .s_axis_config_tvalid      (1'b1),
        .s_axis_config_tready      (),
        .m_axis_data_tdata         ({fft_im, fft_re}),
        .m_axis_data_tuser         (fft_blk_exp),
        .m_axis_data_tvalid        (fft_v),
        .m_axis_data_tlast         (fft_last),
        .m_axis_status_tdata       (),
        .m_axis_status_tvalid      (),
        .event_frame_started       (),
        .event_tlast_unexpected    (),
        .event_data_in_channel_halt()
    );

    // -------------------------------------------------------------------------
    // FFT TLAST counter
    // -------------------------------------------------------------------------
    // Count 0..255 on win_v.  On the 256th valid sample (index 255),
    // pulse fft_tlast for one cycle and wrap the counter to 0.  The
    // xfft IP uses TLAST to delineate 256-sample frames internally;
    // a hard-wired 1'b1 would confuse its bookkeeping.
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            fft_sample_cnt <= 8'd0;
            fft_tlast      <= 1'b0;
        end else begin
            if (win_v) begin
                if (fft_sample_cnt == FFT_LEN - 1) begin
                    fft_sample_cnt <= 8'd0;
                    fft_tlast      <= 1'b1;
                end else begin
                    fft_sample_cnt <= fft_sample_cnt + 1'b1;
                    fft_tlast      <= 1'b0;
                end
            end else begin
                // Hold the TLAST pulse for exactly 1 cycle.
                fft_tlast <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Sub-module: spectral_proc
    // -------------------------------------------------------------------------
    // Truncate 24-bit control inputs to 16-bit Q2.14 for spectral_proc.
    logic [15:0] master_gain_q14;
    logic [15:0] noise_floor_q14;
    logic [15:0] gate_ratio_q14;

    assign master_gain_q14 = master_gain_i[23:8];
    assign noise_floor_q14 = noise_floor_i[23:8];
    assign gate_ratio_q14  = gate_ratio_i[23:8];

    spectral_proc #(
        .N_BINS (GAIN_TABLE_DEPTH),
        .DATA_W (FFT_DATA_W),
        .ADDR_W ($clog2(GAIN_TABLE_DEPTH))
    ) u_spectral_proc (
        .clk_i         (clk_i),
        .rst_n_i       (rst_n_i),
        .in_re_i       (fft_re),
        .in_im_i       (fft_im),
        .in_v_i        (fft_v),
        .in_last_i     (fft_last),
        .out_re_o      (sp_re),
        .out_im_o      (sp_im),
        .out_v_o       (sp_v),
        .out_last_o    (sp_last),
        .mode_i        (mode_i),
        .master_gain_i (master_gain_q14),
        .noise_floor_i (noise_floor_q14),
        .gate_ratio_i  (gate_ratio_q14),
        .bin_addr_i    (gain_addr_i),
        .bin_wdata_i   (gain_wdata_i),
        .bin_we_i      (gain_we_i),
        .bin_bank_i    (gain_bank_i),
        .bank_commit_i (bank_commit_i)
    );

    // -------------------------------------------------------------------------
    // Sub-module: ifft_256 (inverse FFT)
    // -------------------------------------------------------------------------
    ifft_256 u_ifft_256 (
        .aclk                      (clk_i),
        .aresetn                   (rst_n_i),
        .s_axis_data_tdata         ({sp_im, sp_re}),
        .s_axis_data_tvalid        (sp_v),
        .s_axis_data_tready        (),
        .s_axis_data_tlast         (ifft_tlast),
        .s_axis_config_tdata       (8'd0),   // FWD_INV = 0 (inverse)
        .s_axis_config_tvalid      (1'b1),
        .s_axis_config_tready      (),
        .m_axis_data_tdata         ({ifft_im, ifft_re}),
        .m_axis_data_tuser         (ifft_blk_exp),
        .m_axis_data_tvalid        (ifft_v),
        .m_axis_data_tlast         (ifft_last),
        .m_axis_status_tdata       (),
        .m_axis_status_tvalid      (),
        .event_frame_started       (),
        .event_tlast_unexpected    (),
        .event_data_in_channel_halt()
    );

    // -------------------------------------------------------------------------
    // IFFT TLAST counter
    // -------------------------------------------------------------------------
    // Count 0..255 on sp_v (spectral_proc's output valid).  Pulse
    // ifft_tlast for one cycle on the 256th sample (index 255).  The
    // xfft IP (IFFT configuration) uses TLAST to mark the end of a
    // 256-sample spectral frame.
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ifft_sample_cnt <= 8'd0;
            ifft_tlast      <= 1'b0;
        end else begin
            if (sp_v) begin
                if (ifft_sample_cnt == FFT_LEN - 1) begin
                    ifft_sample_cnt <= 8'd0;
                    ifft_tlast      <= 1'b1;
                end else begin
                    ifft_sample_cnt <= ifft_sample_cnt + 1'b1;
                    ifft_tlast      <= 1'b0;
                end
            end else begin
                // Hold the TLAST pulse for exactly 1 cycle.
                ifft_tlast <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // BFP exponent delay pipeline
    // -------------------------------------------------------------------------
    // Shifts fft_blk_exp every cycle to match the IFFT output latency.
    // Depth = spectral_proc(4) + IFFT pipelined streaming latency (~414).
    // No async reset — Vivado infers SRL32E shift-register LUTs.
    always_ff @(posedge clk_i) begin
        fft_exp_pipe[0] <= fft_blk_exp;
        for (int i = 1; i < auris_pkg::BFP_PIPE_DELAY; i++)
            fft_exp_pipe[i] <= fft_exp_pipe[i-1];
    end
    assign fft_exp_aligned = fft_exp_pipe[auris_pkg::BFP_PIPE_DELAY-1];

    assign ola_scale_factor = fft_exp_aligned + ifft_blk_exp;

    // -------------------------------------------------------------------------
    // Sub-module: overlap_add
    // -------------------------------------------------------------------------
    // Sign-extend 16-bit IFFT output to 24-bit for overlap_add.
    logic [23:0] ifft_l_sxt;
    logic [23:0] ifft_r_sxt;

    assign ifft_l_sxt = sxt24(ifft_re);
    assign ifft_r_sxt = sxt24(ifft_im);

    overlap_add #(
        .LEN    (FFT_LEN),
        .DATA_W (I2S_DATA_W)
    ) u_overlap_add (
        .clk_i          (clk_i),
        .rst_n_i        (rst_n_i),
        .in_l_i         (ifft_l_sxt),
        .in_r_i         (ifft_r_sxt),
        .in_v_i         (ifft_v),
        .in_last_i      (ifft_last),
        .out_l_o        (ola_l),
        .out_r_o        (ola_r),
        .out_v_o        (ola_v),
        .frame_done_o   (ola_frame_done),
        .scale_factor_i (ola_scale_factor)
    );

    // -------------------------------------------------------------------------
    // Sub-module: volume_ctrl (after DSP, before output buffer)
    // -------------------------------------------------------------------------
    volume_ctrl #(
        .DATA_W (I2S_DATA_W)
    ) u_volume_ctrl (
        .clk_i      (clk_i),
        .rst_n_i    (rst_n_i),
        .in_l_i     (ola_l),
        .in_r_i     (ola_r),
        .in_valid_i (ola_v),
        .volume_i   (volume_i),
        .out_l_o    (vol_l),
        .out_r_o    (vol_r),
        .out_valid_o(vol_v)
    );

    // -------------------------------------------------------------------------
    // Sub-module: output_buffer
    // -------------------------------------------------------------------------
    output_buffer #(
        .HALF   (GAIN_TABLE_DEPTH),
        .DATA_W (I2S_DATA_W)
    ) u_output_buffer (
        .clk_i          (clk_i),
        .rst_n_i        (rst_n_i),
        .in_l_i         (vol_l),
        .in_r_i         (vol_r),
        .in_v_i         (vol_v),
        .sample_clk_en_i(sample_valid_i),
        .out_l_o        (obuf_l),
        .out_r_o        (obuf_r),
        .out_v_o        (obuf_v),
        .underflow_o    (obuf_underflow)
    );

    // -------------------------------------------------------------------------
    // Output mux: bypass vs pipeline
    // -------------------------------------------------------------------------
    // When dsp_enable_i=0: pass through sample_l_i, sample_r_i, sample_valid_i
    //                      (registered, 1 cycle).
    // When dsp_enable_i=1: use pipeline output (obuf_l, obuf_r, obuf_v).
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            out_l_o     <= '0;
            out_r_o     <= '0;
            out_valid_o <= 1'b0;
        end else begin
            if (dsp_enable_i) begin
                out_l_o     <= obuf_l;
                out_r_o     <= obuf_r;
                out_valid_o <= obuf_v;
            end else begin
                out_l_o     <= sample_l_i;
                out_r_o     <= sample_r_i;
                out_valid_o <= sample_valid_i;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Telemetry: peak meters, frame counter, error flags, clip
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            peak_in_o     <= '0;
            peak_out_o    <= '0;
            frame_count_o <= '0;
            error_flags_o <= '0;
            clip_event_o  <= 1'b0;
        end else begin
            // Peak input: track absolute max of sample_l_i
            if (sample_valid_i) begin
                peak_in_o <= abs24(sample_l_i);
            end

            // Peak output: track absolute max of out_l_o
            if (out_valid_o) begin
                peak_out_o <= abs24(out_l_o);
            end

            // Frame counter
            if (ola_frame_done) begin
                frame_count_o <= frame_count_o + 1'b1;
            end

            // Error flags collection
            //   bit 0: I2S overflow from input_buffer
            //   bit 1: I2S underflow from output_buffer
            //   bit 2: FFT overflow (tied to 0 for MVP)
            //   bit 3: frame drop (tied to 0 for MVP)
            error_flags_o <= {4'b0000,
                              1'b0,    // FFT overflow (reserved)
                              obuf_underflow,
                              1'b0,    // frame drop (reserved)
                              ibuf_overflow};

            // Clip detection: pulse when |sample_l_i| >= max positive
            // (24'sd8388607 = 0x7FFFFF)
            if (sample_valid_i && (sample_l_i == 24'sd8388607)) begin
                clip_event_o <= 1'b1;
            end else begin
                clip_event_o <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Synthesis-time sanity
    // -------------------------------------------------------------------------
    initial begin
        if (FFT_LEN != 256)
            $display("WARNING: dsp_pipeline FFT_LEN=%0d, expected 256", FFT_LEN);
    end

endmodule : dsp_pipeline

`default_nettype wire
