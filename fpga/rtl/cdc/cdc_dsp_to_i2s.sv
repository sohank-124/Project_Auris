// =============================================================================
// File:        cdc_dsp_to_i2s.sv
// Project:     Project Auris
// Module:      cdc_dsp_to_i2s
// Description: Asynchronous FIFO crossing processed audio samples from the
//              96 MHz DSP domain to the 3.072 MHz I2S BCLK domain.
//
//              Functionally identical to `cdc_i2s_to_dsp` — the only
//              difference is the direction of the data flow:
//                * write clock is now the DSP clock (fast side)
//                * read  clock is now the I2S BCLK (slow side)
//
//              Storage: 4-entry distributed RAM, 3-bit Gray-coded
//              pointers, 2-FF synchronisers on each side, full flag
//              forced high during reset (Xilinx convention).
//
// Author:      [generated]
// Created:     2026-07
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module cdc_dsp_to_i2s import auris_pkg::*; #(
    parameter int unsigned WIDTH = I2S_DATA_W,     // 24-bit audio samples
    parameter int unsigned DEPTH = CDC_FIFO_DEPTH, // 4 entries
    parameter int unsigned AW    = $clog2(DEPTH)   // address width = 2
) (
    // Write side (DSP domain, 96 MHz)
    input  wire                wr_clk_i,
    input  wire                wr_rst_n_i,
    input  wire                wr_en_i,
    input  wire [WIDTH-1:0]    wr_data_i,

    // Read side (I2S BCLK domain, 3.072 MHz)
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
            $display("ERROR: cdc_dsp_to_i2s AW=%0d does not match DEPTH=%0d", AW, DEPTH);
        end
    end

    // -------------------------------------------------------------------------
    // Local constants
    // -------------------------------------------------------------------------
    localparam int unsigned PW = AW + 1;

    // -------------------------------------------------------------------------
    // Storage (distributed RAM)
    // -------------------------------------------------------------------------
    (* ram_style = "distributed" *)
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // -------------------------------------------------------------------------
    // Pointer state (visible to both clock domains)
    // -------------------------------------------------------------------------
    logic [PW-1:0] wr_ptr_bin;
    logic [PW-1:0] wr_ptr_gray;
    (* ASYNC_REG = "TRUE" *) logic [PW-1:0] rd_ptr_gray_a;
    (* ASYNC_REG = "TRUE" *) logic [PW-1:0] rd_ptr_gray_b;

    logic [PW-1:0] rd_ptr_bin;
    logic [PW-1:0] rd_ptr_gray;
    (* ASYNC_REG = "TRUE" *) logic [PW-1:0] wr_ptr_gray_a;
    (* ASYNC_REG = "TRUE" *) logic [PW-1:0] wr_ptr_gray_b;

    // -------------------------------------------------------------------------
    // Empty / full comparators
    // -------------------------------------------------------------------------
    wire rd_empty     = (rd_ptr_gray == wr_ptr_gray_b);
    wire wr_full_raw  = (wr_ptr_gray == { ~rd_ptr_gray_b[PW-1:PW-2],
                                           rd_ptr_gray_b[PW-3:0] });

    assign wr_full_o  = !wr_rst_n_i | wr_full_raw;
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
            if (wr_en_i && !wr_full_raw) begin
                wr_ptr_bin <= wr_ptr_bin + 1'b1;
            end
            wr_ptr_gray   <= wr_ptr_bin ^ (wr_ptr_bin >> 1);
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
            if (rd_en_i && !rd_empty) begin
                rd_ptr_bin <= rd_ptr_bin + 1'b1;
            end
            rd_ptr_gray   <= rd_ptr_bin ^ (rd_ptr_bin >> 1);
            wr_ptr_gray_a <= wr_ptr_gray;
            wr_ptr_gray_b <= wr_ptr_gray_a;
        end
    end

    // -------------------------------------------------------------------------
    // Read data port
    // -------------------------------------------------------------------------
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

endmodule : cdc_dsp_to_i2s

`default_nettype wire
