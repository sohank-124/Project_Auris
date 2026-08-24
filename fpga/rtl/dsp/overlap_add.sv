// =============================================================================
// File:        overlap_add.sv
// Project:     Project Auris — FPGA-Accelerated Assistive Audio
// Module:      overlap_add
// Description: 50% overlap-add reconstructor with BFP-aware dynamic scaling
//              and a 2-stage output pipeline for timing closure at 96 MHz.
//
//              The IFFT produces 256 samples per frame.  With a Hann
//              window and 50% overlap, the COLA (Constant OverLap-Add)
//              condition is satisfied: the sum of the overlapped window
//              functions equals a constant, so the overlap-add is
//              gain-stable.
//
//              Algorithm (2-stage pipeline):
//                - Maintain a 128-sample history buffer (previous
//                  frame's second half), stored WITHOUT pre-shifting.
//                - For samples 0..127 of the current frame:
//                    Stage 1 (this cycle):  sum = current[n] + history[n]
//                                           shifted = sum <<< (scale + 6)
//                    Stage 2 (next cycle): output[n] = sat24(shifted)
//                - For samples 128..255 of the current frame:
//                    history[n-128] = current[n]
//
//              The left-shift amount is scale_factor_i + 6, where
//              scale_factor_i = E_fft + E_ifft (the sum of the block
//              exponents from the forward and inverse FFT BFP stages).
//              This implements the proven gain equation:
//                X_out_corrected = (cur + hist) <<< (E_fft + E_ifft + 6)
//              Output is saturated to 24-bit signed range.
//
//              out_v_o is asserted for the first 128 samples of each
//              frame (the output samples).
//
//              frame_done_o pulses for 1 cycle when the last sample of
//              the IFFT frame is received (in_last_i).
//
//              BRAM inference note:
//                The history buffer (128 x 48 bits) was previously
//                written and read inside `negedge rst_n_i` always_ff
//                blocks, which prevented BRAM inference (Synth 8-4767)
//                and dissolved it into ~6,000 FFs.  The storage is now
//                in a single non-reset block using a single-port BRAM
//                template: read during the first half of the frame,
//                write during the second half.  The 1-cycle registered
//                read latency is identical to the previous design
//                (the BRAM output register replaces the old
//                hist_l_pipe / hist_r_pipe registers).  At power-on,
//                the BRAM and pipeline FFs initialise to zero
//                (Spartan-7 default), so cold-start is unchanged.
//
// Author:      [generated]
// Created:     2026-07
// Clock Domain: CD_DSP (96 MHz)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module overlap_add import auris_pkg::*; #(
    parameter int unsigned LEN     = FFT_LEN,
    parameter int unsigned HALF    = LEN / 2,
    parameter int unsigned DATA_W  = I2S_DATA_W
) (
    input  wire                    clk_i,
    input  wire                    rst_n_i,

    input  wire [DATA_W-1:0]       in_l_i,
    input  wire [DATA_W-1:0]       in_r_i,
    input  wire                    in_v_i,
    input  wire                    in_last_i,

    output logic [DATA_W-1:0]      out_l_o,
    output logic [DATA_W-1:0]      out_r_o,
    output logic                   out_v_o,

    output logic                   frame_done_o,

    input  wire [7:0]              scale_factor_i   // BFP exponent: E_fft + E_ifft
);

    // -------------------------------------------------------------------------
    // History buffer (128 x 48-bit BRAM, packed as {right, left})
    // -------------------------------------------------------------------------
    (* ram_style = "block" *) logic [2*DATA_W-1:0] history [0:HALF-1];

    // -------------------------------------------------------------------------
    // Sample counter (0..255 within a frame)
    // -------------------------------------------------------------------------
    logic [7:0] sample_cnt;

    // Pipeline register for history read (1-cycle BRAM latency)
    logic [DATA_W-1:0] hist_l_pipe, hist_r_pipe;
    logic              hist_v_pipe;

    // Input delay registers (1 cycle) — align current input with the
    // 1-cycle-delayed history read so OLA = (current + history) >> 8
    // uses the correct history index instead of the previous one.
    logic signed [DATA_W-1:0] in_l_d1;
    logic signed [DATA_W-1:0] in_r_d1;

    // -------------------------------------------------------------------------
    // BFP-aware dynamic shift (combinational)
    // -------------------------------------------------------------------------
    // scale_factor_i = E_fft + E_ifft (per-frame, summed in dsp_pipeline).
    // K = 6 is the proven fixed constant compensating for the static
    // pipeline attenuation (window truncation, OLA structure, Q2.14
    // format conversions).  Maximum shift: 16 + 6 = 22 bits.
    // Saturation prevents wraparound on the 24-bit I2S output.
    localparam int unsigned K_BFP = 6;

    logic signed [24:0]               sum_l, sum_r;
    logic signed [6:0]                shift_amt;
    logic signed [47:0]               shifted_l, shifted_r;

    assign sum_l     = $signed(in_l_d1) + $signed(hist_l_pipe);
    assign sum_r     = $signed(in_r_d1) + $signed(hist_r_pipe);
    assign shift_amt = $signed({1'b0, scale_factor_i}) + signed'(K_BFP);

    assign shifted_l = $signed(sum_l) <<< shift_amt;
    assign shifted_r = $signed(sum_r) <<< shift_amt;

    // -------------------------------------------------------------------------
    // Pipeline register (1 cycle) — cuts the 18-level critical path from
    // BRAM through adder/shift/saturation to output into two 9-level paths:
    //    Stage 1: BRAM → hist pipe → sum → shift → shifted_l/r_r
    //    Stage 2: shifted_l/r_r → sat24 → ola_l/r_comb → out_l/r_o
    // -------------------------------------------------------------------------
    logic signed [47:0] shifted_l_r, shifted_r_r;
    logic              hist_v_r;
    logic              hist_v_r2;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            shifted_l_r <= '0;
            shifted_r_r <= '0;
            hist_v_r    <= 1'b0;
            hist_v_r2   <= 1'b0;
        end else begin
            shifted_l_r <= shifted_l;
            shifted_r_r <= shifted_r;
            hist_v_r    <= hist_v_pipe;
            hist_v_r2   <= hist_v_r;
        end
    end

    function automatic logic [DATA_W-1:0] sat24(input logic signed [47:0] val);
        if (val > 48'sd8388607)
            return 24'sd8388607;
        else if (val < -48'sd8388608)
            return -24'sd8388608;
        else
            return val[DATA_W-1:0];
    endfunction

    logic [DATA_W-1:0] ola_l_comb, ola_r_comb;

    assign ola_l_comb = sat24(shifted_l_r);
    assign ola_r_comb = sat24(shifted_r_r);

    // -------------------------------------------------------------------------
    // History storage: read + write (non-reset — required for BRAM inference)
    // -------------------------------------------------------------------------
    // Single-port BRAM template: during the first half of the frame
    // (sample_cnt < 128) we READ history for overlap-add; during the
    // second half (sample_cnt >= 128) we WRITE the new history values.
    // Read and write never happen on the same address in the same
    // cycle, so a single-port BRAM suffices.
    //
    // The async reset is removed from this block because Spartan-7
    // BRAM storage cells have no async-reset pin; keeping rst_n_i in
    // the sensitivity list would force ~6,000 FFs (Synth 8-4767).
    // Both the BRAM and the pipeline registers initialise to zero on
    // Spartan-7 after configuration, so cold-start history is zero —
    // identical to the previous reset behaviour.
    always_ff @(posedge clk_i) begin
        if (in_v_i) begin
            if (sample_cnt < HALF) begin
                // First half: read history for overlap-add (1-cycle latency)
                {hist_r_pipe, hist_l_pipe} <= history[sample_cnt[6:0]];
                hist_v_pipe                <= 1'b1;
            end else begin
                // Second half: store current (raw, no pre-shift) to history
                history[sample_cnt[6:0]] <= {in_r_i, in_l_i};
                hist_v_pipe               <= 1'b0;
            end
        end else begin
            hist_v_pipe <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Input delay (1-cycle pipeline — align with BRAM read latency)
    // -------------------------------------------------------------------------
    // The BRAM read returns data 1 cycle after the address is presented,
    // so hist_l_pipe / hist_r_pipe hold history[sample_cnt-1] when the
    // output block computes the OLA sum.  Without delaying the input
    // by the same 1 cycle, every OLA output would combine current[n]
    // with history[n-1] — a 1-sample misalignment that produces a
    // 375 Hz periodic click at the 8 kHz / 256-sample / 50%-overlap
    // frame rate (256 * 48 kHz / 128 = 96 kHz; 96 kHz / 256 = 375 Hz
    // artefact).
    //
    // No async reset — these are pure pipeline registers, identical
    // in spirit to hist_l_pipe / hist_r_pipe above.
    always_ff @(posedge clk_i) begin
        in_l_d1 <= in_l_i;
        in_r_d1 <= in_r_i;
    end

    // -------------------------------------------------------------------------
    // Main control + output (resettable)
    // -------------------------------------------------------------------------
    // This block contains only control registers (sample_cnt, output
    // registers, frame_done) — no storage array — so the async reset
    // is harmless for BRAM inference.
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            sample_cnt  <= 8'd0;
            out_l_o     <= '0;
            out_r_o     <= '0;
            out_v_o     <= 1'b0;
            frame_done_o<= 1'b0;
        end else begin
            frame_done_o <= 1'b0;

            if (in_v_i) begin
                if (sample_cnt <= HALF + 2) begin
                    // First half + 3 trailing samples: OLA with BFP-aware dynamic shift.
                    // out_v_o window = sample_cnt 3..130 (exactly 128 valid outputs),
                    // tracking the 3-cycle pipeline latency (BRAM read -> hist pipe ->
                    // sum/shift -> sat24 -> out).  out_l_o[3] is the first valid OLA
                    // sample in[0] + history[0]; the gate (sample_cnt >= 8'd3) masks
                    // the 2 prior pipeline-fill cycles.
                    out_l_o <= ola_l_comb;
                    out_r_o <= ola_r_comb;
                    out_v_o <= hist_v_r2 && (sample_cnt >= 8'd3);
                end else begin
                    // Second half: no output, history written in the
                    // non-reset block above.
                    out_v_o <= 1'b0;
                end

                sample_cnt <= sample_cnt + 1'b1;
                if (in_last_i) begin
                    sample_cnt  <= 8'd0;
                    frame_done_o<= 1'b1;
                end
            end else begin
                out_v_o <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // BRAM cold-start note: Spartan-7 BRAM initialises to zero after
    // configuration, so the first frame's history is zero — correct for
    // cold OLA startup.
    // -------------------------------------------------------------------------

endmodule : overlap_add

`default_nettype wire