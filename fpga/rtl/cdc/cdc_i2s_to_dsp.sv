// =============================================================================
// File:        cdc_i2s_to_dsp.sv
// Project:     Project Auris
// Module:      cdc_i2s_to_dsp
// Description: Asynchronous FIFO crossing audio samples from the
//              3.072 MHz I2S BCLK domain to the 96 MHz DSP domain.
//
//              Design points:
//                * Small (4-entry) distributed-RAM FIFO.  4 entries give
//                  the DSP enough headroom to absorb scheduler jitter
//                  without resorting to BRAM (which costs a full BRAM
//                  tile on S7 for 96 bits total).
//                * Standard 3-bit Gray-coded pointers (the address space
//                  is 2 bits; the extra MSB is the wrap bit used to
//                  distinguish full from empty).
//                * `ram_style = "distributed"` so Vivado packs the
//                  storage into LUTRAM instead of BRAM.
//                * `ASYNC_REG = "TRUE"` on every synchroniser flip-flop
//                  so the placer keeps them tightly packed and reduces
//                  mean-time-between-failure (MTBF) for the metastable
//                  stages.
//
//              Full vs. empty convention:
//                * empty when wr_gray_sync == rd_gray
//                * full  when wr_gray == { ~rd_gray_sync[PW-1:PW-2],
//                                           rd_gray_sync[PW-3:0] }
//              (PW = AW+1, so for DEPTH=4, AW=2, PW=3.)
//
//              On reset, the full flag is forced high (Xilinx convention)
//              so the producer cannot start writing until the first read
//              pointer has crossed the CDC and the empty flag has
//              deasserted.
//
// Author:      [generated]
// Created:     2026-07
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module cdc_i2s_to_dsp import auris_pkg::*; #(
    parameter int unsigned WIDTH = I2S_DATA_W,     // 24-bit audio samples
    parameter int unsigned DEPTH = CDC_FIFO_DEPTH, // 4 entries
    parameter int unsigned AW    = $clog2(DEPTH)   // address width = 2
) (
    // Write side (I2S BCLK domain, 3.072 MHz)
    input  wire                wr_clk_i,
    input  wire                wr_rst_n_i,
    input  wire                wr_en_i,
    input  wire [WIDTH-1:0]    wr_data_i,

    // Read side (DSP domain, 96 MHz)
    input  wire                rd_clk_i,
    input  wire                rd_rst_n_i,
    input  wire                rd_en_i,
    output wire [WIDTH-1:0]    rd_data_o,
    output wire                rd_valid_o,
    output wire                rd_empty_o,
    output wire                wr_full_o
);

    // -------------------------------------------------------------------------
    // Sanity: DEPTH must be a power of two and AW must match.
    // -------------------------------------------------------------------------
    initial begin
        if ((1 << AW) != DEPTH) begin
            $display("ERROR: cdc_i2s_to_dsp AW=%0d does not match DEPTH=%0d", AW, DEPTH);
        end
    end

    // -------------------------------------------------------------------------
    // Local constants
    // -------------------------------------------------------------------------
    // Pointers are AW+1 bits wide (one extra MSB = wrap bit).
    localparam int unsigned PW = AW + 1;

    // -------------------------------------------------------------------------
    // Storage (distributed RAM)
    // -------------------------------------------------------------------------
    (* ram_style = "distributed" *)
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // -------------------------------------------------------------------------
    // Pointer state (visible to both clock domains)
    // -------------------------------------------------------------------------
    // Write-domain state
    logic [PW-1:0] wr_ptr_bin;          // binary write pointer
    logic [PW-1:0] wr_ptr_gray;         // Gray-coded write pointer
    (* ASYNC_REG = "TRUE" *) logic [PW-1:0] rd_ptr_gray_a;       // rd gray, 1st-stage sync into wr clk
    (* ASYNC_REG = "TRUE" *) logic [PW-1:0] rd_ptr_gray_b;       // rd gray, 2nd-stage sync into wr clk

    // Read-domain state
    logic [PW-1:0] rd_ptr_bin;          // binary read pointer
    logic [PW-1:0] rd_ptr_gray;         // Gray-coded read pointer
    (* ASYNC_REG = "TRUE" *) logic [PW-1:0] wr_ptr_gray_a;       // wr gray, 1st-stage sync into rd clk
    (* ASYNC_REG = "TRUE" *) logic [PW-1:0] wr_ptr_gray_b;       // wr gray, 2nd-stage sync into rd clk

    // -------------------------------------------------------------------------
    // Empty / full comparators
    // -------------------------------------------------------------------------
    // Empty when the read pointer equals the synchronised write pointer.
    wire rd_empty = (rd_ptr_gray == wr_ptr_gray_b);

    // Full when the write pointer's Gray code matches the inverted
    // top bits + lower bits of the synchronised read pointer.  For
    // PW=3: {~rd_ptr_gray_b[2:1], rd_ptr_gray_b[0]}.
    wire wr_full_raw = (wr_ptr_gray == { ~rd_ptr_gray_b[PW-1:PW-2],
                                           rd_ptr_gray_b[PW-3:0] });

    // Force wr_full_o high while the FIFO is in reset (Xilinx convention
    // — producer must wait for the first read-pointer synchronisation
    // before the first write is allowed).
    assign wr_full_o = !wr_rst_n_i | wr_full_raw;
    assign rd_empty_o = rd_empty;

    // -------------------------------------------------------------------------
    // Write-side sequential logic
    // -------------------------------------------------------------------------
    always_ff @(posedge wr_clk_i or negedge wr_rst_n_i) begin
        if (!wr_rst_n_i) begin
            wr_ptr_bin    <= '0;
            wr_ptr_gray   <= '0;
            rd_ptr_gray_a <= '0;
            rd_ptr_gray_b <= '0;
        end else begin
            // Binary pointer increments only on a successful write.
            if (wr_en_i && !wr_full_raw) begin
                wr_ptr_bin <= wr_ptr_bin + 1'b1;
            end

            // Gray-coded write pointer.
            wr_ptr_gray <= wr_ptr_bin ^ (wr_ptr_bin >> 1);

            // 2-FF synchroniser of the read pointer into the write domain.
            // ASYNC_REG attribute applied via the array declaration above.
            rd_ptr_gray_a <= rd_ptr_gray;
            rd_ptr_gray_b <= rd_ptr_gray_a;
        end
    end

    // -------------------------------------------------------------------------
    // Write port: synchronous RAM write
    // -------------------------------------------------------------------------
    always_ff @(posedge wr_clk_i) begin
        if (wr_en_i && !wr_full_raw) begin
            mem[wr_ptr_bin[AW-1:0]] <= wr_data_i;
        end
    end

    // -------------------------------------------------------------------------
    // Read-side sequential logic
    // -------------------------------------------------------------------------
    always_ff @(posedge rd_clk_i or negedge rd_rst_n_i) begin
        if (!rd_rst_n_i) begin
            rd_ptr_bin    <= '0;
            rd_ptr_gray   <= '0;
            wr_ptr_gray_a <= '0;
            wr_ptr_gray_b <= '0;
        end else begin
            // Binary pointer increments only on a successful read.
            if (rd_en_i && !rd_empty) begin
                rd_ptr_bin <= rd_ptr_bin + 1'b1;
            end

            // Gray-coded read pointer.
            rd_ptr_gray <= rd_ptr_bin ^ (rd_ptr_bin >> 1);

            // 2-FF synchroniser of the write pointer into the read domain.
            wr_ptr_gray_a <= wr_ptr_gray;
            wr_ptr_gray_b <= wr_ptr_gray_a;
        end
    end

    // -------------------------------------------------------------------------
    // Read data port
    // -------------------------------------------------------------------------
    // The output is a direct look-up into the storage at the current
    // read pointer.  It is valid combinationally as long as !rd_empty.
    assign rd_data_o = mem[rd_ptr_bin[AW-1:0]];

    // -------------------------------------------------------------------------
    // Read valid: 1-cycle pulse when rd_en_i and !rd_empty
    // -------------------------------------------------------------------------
    logic rd_valid_r;
    always_ff @(posedge rd_clk_i or negedge rd_rst_n_i) begin
        if (!rd_rst_n_i) rd_valid_r <= 1'b0;
        else             rd_valid_r <= rd_en_i & ~rd_empty;
    end
    assign rd_valid_o = rd_valid_r;

endmodule : cdc_i2s_to_dsp

`default_nettype wire
