// =============================================================================
// File:        output_buffer.sv
// Project:     Project Auris — FPGA-Accelerated Assistive Audio
// Module:      output_buffer
// Description: 128-sample ping-pong output buffer.
//
//              A single 256 x 48-bit BRAM stores both ping-pong halves.
//              The MSB of the address selects the half (0 = A, 1 = B);
//              the lower 7 bits select the sample within the half.
//
//              While the DSP writes one half (via in_v_i, a 128-cycle
//              burst from overlap_add), the I2S TX reads the other half
//              (via sample_clk_en_i, a 48 kHz strobe).  Every 128 writes
//              the buffers swap; every 128 reads the read pointer wraps.
//
//              The read is now REGISTERED (1-cycle BRAM latency) rather
//              than combinational.  A delayed copy of sample_clk_en_i
//              and buf_valid aligns the output capture with the BRAM
//              data.  This adds exactly 1 cycle of latency relative to
//              the previous async-read design — absorbed by the
//              downstream CDC FIFO with no functional impact.
//
//              Underflow detection: if sample_clk_en_i fires while the
//              read buffer does not yet contain a complete frame
//              (buf_valid=0), the outputs are forced to zero and
//              underflow_o is set sticky.
//
//              The commit logic (on 128th write) and the read-finish
//              logic (on 128th read) are in the SAME always_ff block
//              with the commit taking priority, to avoid a race
//              condition when both events coincide.
//
//              BRAM inference note:
//                The storage array and the registered read path live
//                in non-reset always_ff blocks.  Spartan-7 BRAM cells
//                have no async-reset on the storage matrix; placing
//                the array inside a `negedge rst_n_i` block would
//                force Vivado to dissolve 256x48 = 12,288 bits into
//                individual flip-flops (Synth 8-4767).  Only the
//                ping-pong control FFs and the output stage retain
//                the async reset.
//
// Author:      [generated]
// Created:     2026-07
// Clock Domain: CD_DSP (96 MHz)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module output_buffer import auris_pkg::*; #(
    parameter int unsigned HALF  = GAIN_TABLE_DEPTH,
    parameter int unsigned DATA_W = I2S_DATA_W
) (
    input  wire                    clk_i,
    input  wire                    rst_n_i,

    input  wire [DATA_W-1:0]       in_l_i,
    input  wire [DATA_W-1:0]       in_r_i,
    input  wire                    in_v_i,

    input  wire                    sample_clk_en_i,   // 48 kHz enable

    output logic [DATA_W-1:0]      out_l_o,
    output logic [DATA_W-1:0]      out_r_o,
    output logic                   out_v_o,
    output logic                   underflow_o         // sticky
);

    // -------------------------------------------------------------------------
    // Storage: single 256 x 48-bit BRAM, packed as {right, left}
    // -------------------------------------------------------------------------
    // Address layout: {buf_sel[0], ptr[6:0]}
    //   buf_sel=0 -> half A (entries 0..127)
    //   buf_sel=1 -> half B (entries 128..255)
    (* ram_style = "block" *) logic [2*DATA_W-1:0] mem [0:2*HALF-1];

    // -------------------------------------------------------------------------
    // Ping-pong control (resettable FFs — not storage)
    // -------------------------------------------------------------------------
    logic        wr_buf;       // 0 = writing half A, 1 = writing half B
    logic        rd_buf;       // 0 = reading half A, 1 = reading half B
    logic [6:0]  wr_ptr;       // 0..127, write position in wr_buf
    logic [6:0]  rd_ptr;       // 0..127, read position in rd_buf
    logic        buf_valid;    // rd_buf has 128 valid samples ready

    // -------------------------------------------------------------------------
    // Delayed read control (aligns registered BRAM output with capture)
    // -------------------------------------------------------------------------
    logic        rd_en_q;      // sample_clk_en_i delayed by 1 cycle
    logic        buf_valid_q;  // buf_valid delayed by 1 cycle

    // -------------------------------------------------------------------------
    // BRAM write port (non-reset — required for BRAM inference)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (in_v_i)
            mem[{wr_buf, wr_ptr}] <= {in_r_i, in_l_i};
    end

    // -------------------------------------------------------------------------
    // BRAM read port (registered, 1-cycle latency, non-reset for inference)
    // -------------------------------------------------------------------------
    // The address {rd_buf, rd_ptr} is presented when sample_clk_en_i
    // fires; data appears in rd_data one cycle later.  The output stage
    // below captures rd_data using the delayed rd_en_q / buf_valid_q.
    logic [2*DATA_W-1:0] rd_data;
    always_ff @(posedge clk_i) begin
        if (sample_clk_en_i)
            rd_data <= mem[{rd_buf, rd_ptr}];
    end

    // -------------------------------------------------------------------------
    // Write pointer management (resettable)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            wr_buf <= 1'b0;
            wr_ptr <= 7'd0;
        end else if (in_v_i) begin
            wr_ptr <= wr_ptr + 1'b1;
            if (wr_ptr == HALF - 1) begin
                wr_ptr <= 7'd0;
                wr_buf <= ~wr_buf;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Commit + read-pointer management (resettable, commit has priority)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rd_buf    <= 1'b1;   // start by reading half B (half A written first)
            rd_ptr    <= 7'd0;
            buf_valid <= 1'b0;
        end else if (in_v_i && (wr_ptr == HALF - 1)) begin
            // COMMIT: the half that was just filled becomes the new read half
            rd_buf    <= wr_buf;
            rd_ptr    <= 7'd0;
            buf_valid <= 1'b1;
        end else if (sample_clk_en_i && buf_valid) begin
            // NORMAL READ: advance read pointer
            rd_ptr <= rd_ptr + 1'b1;
            if (rd_ptr == HALF - 1) begin
                rd_ptr    <= 7'd0;
                buf_valid <= 1'b0;  // consumed the half
            end
        end
    end

    // -------------------------------------------------------------------------
    // Output stage with 1-cycle read-latency alignment (resettable)
    // -------------------------------------------------------------------------
    // rd_en_q / buf_valid_q are 1-cycle delayed copies of the read
    // condition.  They fire exactly when rd_data (the registered BRAM
    // output) holds the data for the address that was presented one
    // cycle earlier.  This preserves the original ping-pong and
    // underflow semantics with exactly one extra cycle of latency.
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            out_l_o     <= '0;
            out_r_o     <= '0;
            out_v_o     <= 1'b0;
            underflow_o <= 1'b0;
            rd_en_q     <= 1'b0;
            buf_valid_q <= 1'b0;
        end else begin
            // Delay read condition by 1 cycle to align with rd_data
            rd_en_q     <= sample_clk_en_i;
            buf_valid_q <= buf_valid;

            if (rd_en_q) begin
                if (buf_valid_q) begin
                    {out_r_o, out_l_o} <= rd_data;
                    out_v_o            <= 1'b1;
                end else begin
                    // Underflow: no data available
                    out_l_o     <= '0;
                    out_r_o     <= '0;
                    out_v_o     <= 1'b0;
                    underflow_o <= 1'b1;
                end
            end else begin
                out_v_o <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Synthesis-time sanity
    // -------------------------------------------------------------------------
    initial begin
        if (HALF != 128)
            $display("WARNING: output_buffer HALF=%0d, expected 128", HALF);
    end

endmodule : output_buffer

`default_nettype wire