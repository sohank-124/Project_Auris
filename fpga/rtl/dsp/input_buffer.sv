// =============================================================================
// File:        input_buffer.sv
// Project:     Project Auris — FPGA-Accelerated Assistive Audio
// Module:      input_buffer
// Description: 256-sample BRAM-based input buffer with 50% overlap-add
//              support.
//
//              The buffer is a single true-dual-port 256 x 48-bit BRAM
//              (packed as {sample_r, sample_l}).  Writes happen at the
//              48 kHz sample rate on one port; reads happen at 96 MHz in
//              256-sample bursts on the other port.
//
//              Every 128 writes, a 256-sample burst read is triggered.
//              The read starts at the OLDEST sample in the buffer
//              (wr_ptr + 1) and reads 256 consecutive samples wrapping
//              at 256.  This naturally produces 128 "old" + 128 "new"
//              samples in chronological order — the exact input
//              required for 50% overlap-add.
//
//              For the very first frame (buffer not yet fully populated)
//              the "old" half contains zeroes; this is a cold-start
//              artefact and is acceptable.
//
// Author:      [generated]
// Created:     2026-07
// Clock Domain: CD_DSP (96 MHz)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module input_buffer import auris_pkg::*; #(
    parameter int unsigned DEPTH  = FFT_LEN,
    parameter int unsigned DATA_W = I2S_DATA_W
) (
    input  wire                    clk_i,
    input  wire                    rst_n_i,

    input  wire [DATA_W-1:0]       sample_l_i,
    input  wire [DATA_W-1:0]       sample_r_i,
    input  wire                    sample_v_i,

    output logic [DATA_W-1:0]      frame_l_o,
    output logic [DATA_W-1:0]      frame_r_o,
    output logic                   frame_v_o,

    output logic                   frame_ready_o, // 1-cycle pulse at hop boundary
    output logic                   busy_o,        // high while reading out a frame
    output logic                   overflow_o     // sticky: write happened while busy
);

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------
    (* ram_style = "block" *) logic [2*DATA_W-1:0] mem [0:DEPTH-1];

    // -------------------------------------------------------------------------
    // Write side
    // -------------------------------------------------------------------------
    logic [7:0] wr_ptr;      // 0..255, next write position
    logic [6:0] hop_cnt;     // 0..127, samples within current hop

    // -------------------------------------------------------------------------
    // Read side
    // -------------------------------------------------------------------------
    logic [7:0] rd_ptr;      // 0..255, next read position
    logic [7:0] read_cnt;    // 0..255, samples read in current burst
    logic       reading;     // high while reading out a burst
    logic       rd_en;       // gated read enable (stops 1 cycle early)

    // -------------------------------------------------------------------------
    // Combinational read address and enable
    // -------------------------------------------------------------------------
    // The BRAM read is registered (1-cycle latency).  We present the
    // address and enable combinationally; the output appears 1 cycle
    // later.  rd_en is gated by (reading && read_cnt < 255) so the
    // final read_cnt=255 cycle does NOT trigger a spurious extra read.
    always_comb begin
        rd_en = 1'b0;
        if (reading && (read_cnt < DEPTH - 1)) begin
            rd_en = 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Storage write port (non-reset — required for BRAM inference)
    // -------------------------------------------------------------------------
    // Spartan-7 BRAM cells have no async-reset on the storage matrix.
    // If this write lived inside a `negedge rst_n_i` block, Vivado would
    // dissolve the entire 256x48 array into 12,288 flip-flops (Synth
    // 8-4767 / 8-13159).  By isolating the mem[] write in a plain
    // `posedge clk_i` block, the synthesizer infers a true dual-port
    // BRAM tile.
    always_ff @(posedge clk_i) begin
        if (sample_v_i)
            mem[wr_ptr] <= {sample_r_i, sample_l_i};
    end

    // -------------------------------------------------------------------------
    // Main sequential block: write pointer, read pointer, control signals
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            wr_ptr        <= 8'd0;
            hop_cnt       <= 7'd0;
            rd_ptr        <= 8'd0;
            read_cnt      <= 8'd0;
            reading       <= 1'b0;
            frame_ready_o <= 1'b0;
            busy_o        <= 1'b0;
            overflow_o    <= 1'b0;
        end else begin
            frame_ready_o <= 1'b0;

            // -----------------------------------------------------------------
            // Write side
            // -----------------------------------------------------------------
            if (sample_v_i) begin
                // If we're currently reading out a burst, the write
                // is a real-time sample that arrived during the read.
                // It goes into the buffer; the dual-port BRAM handles
                // simultaneous R/W.  We flag it as an overflow.
                if (reading) overflow_o <= 1'b1;

                wr_ptr      <= wr_ptr + 1'b1;
                hop_cnt     <= hop_cnt + 1'b1;

                // End-of-hop: trigger a read burst
                if (hop_cnt == DEPTH / 2 - 1) begin
                    frame_ready_o <= 1'b1;
                    reading       <= 1'b1;
                    // The oldest sample is at (wr_ptr + 1) — the next
                    // position to be written, which was filled 256
                    // samples ago (or contains the pre-fill default).
                    rd_ptr        <= wr_ptr + 1'b1;
                    read_cnt      <= 8'd0;
                    hop_cnt       <= 7'd0;
                end
            end

            // -----------------------------------------------------------------
            // Read side
            // -----------------------------------------------------------------
            if (reading) begin
                busy_o   <= 1'b1;
                rd_ptr   <= rd_ptr + 1'b1;
                read_cnt <= read_cnt + 1'b1;
                if (read_cnt == DEPTH - 1) begin
                    reading <= 1'b0;
                    busy_o  <= 1'b0;
                end
            end else begin
                busy_o <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // BRAM read data port (1-cycle registered, non-reset for inference)
    // -------------------------------------------------------------------------
    // The data output register lives outside the resettable block so the
    // synthesizer maps it to the BRAM output latch.  At power-on the
    // BRAM contents and this register are both zero (Spartan-7 FF/BRAM
    // init), so the first valid read still produces correct data.
    always_ff @(posedge clk_i) begin
        if (rd_en)
            {frame_r_o, frame_l_o} <= mem[rd_ptr];
    end

    // -------------------------------------------------------------------------
    // Read valid flag (resettable control — not storage)
    // -------------------------------------------------------------------------
    // frame_v_o asserts one cycle after rd_en, matching the BRAM
    // output latency exactly.
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) frame_v_o <= 1'b0;
        else          frame_v_o <= rd_en;
    end

    // -------------------------------------------------------------------------
    // Synthesis-time sanity
    // -------------------------------------------------------------------------
    initial begin
        if (DEPTH != 256)
            $display("WARNING: input_buffer DEPTH=%0d, expected 256", DEPTH);
    end

endmodule : input_buffer

`default_nettype wire
