// =============================================================================
// File:        window_rom.sv
// Project:     Project Auris — FPGA-Accelerated Assistive Audio
// Module:      window_rom
// Description: 256 x 16-bit ROM containing pre-computed Hann window
//              coefficients in unsigned Q2.14 fixed-point format.
//
//              The coefficients are computed at elaboration time using
//              $cos() inside an `initial` block.  Vivado evaluates
//              `initial` blocks for ROM inference, so the resulting
//              hardware is a pure LUT-based distributed ROM with no
//              external file dependency.
//
//              Hann formula:
//                w[n] = 0.5 * (1 - cos(2*pi*n/N))
//              In Q2.14:
//                w[n] = round( w[n] * 16384 )
//
// Author:      [generated]
// Created:     2026-07
// Clock Domain: CD_DSP (96 MHz)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module window_rom import auris_pkg::*; #(
    parameter int unsigned LEN   = FFT_LEN,
    parameter int unsigned WIDTH = WINDOW_DATA_W
) (
    input  wire                    clk_i,
    input  wire [$clog2(LEN)-1:0]  addr_i,
    output logic [WIDTH-1:0]       data_o
);

    // -------------------------------------------------------------------------
    // Coefficient calculation function
    // -------------------------------------------------------------------------
    // Uses $cos() which Vivado evaluates at elaboration time inside an
    // initial block.  The result is a 16-bit unsigned Q2.14 value.
    function automatic logic [WIDTH-1:0] hann_calc(input int n);
        real pi;
        real w;
        int  scaled;
        begin
            pi     = 3.14159265358979;
            w      = 0.5 * (1.0 - $cos(2.0 * pi * real'(n) / real'(LEN)));
            scaled = $rtoi(w * real'(int'(1) <<< WIDTH-2) + 0.5);
            if (scaled < 0)            scaled = 0;
            if (scaled > int'(1)<<WIDTH - 1) scaled = (int'(1)<<WIDTH) - 1;
            hann_calc = logic'(scaled[WIDTH-1:0]);
        end
    endfunction

    // -------------------------------------------------------------------------
    // ROM storage — computed at elaboration
    // -------------------------------------------------------------------------
    logic [WIDTH-1:0] mem [0:LEN-1];

    initial begin
        for (int i = 0; i < LEN; i++) begin
            mem[i] = hann_calc(i);
        end
    end

    // -------------------------------------------------------------------------
    // Synchronous read (1-cycle latency)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        data_o <= mem[addr_i];
    end

    // -------------------------------------------------------------------------
    // Synthesis-time sanity
    // -------------------------------------------------------------------------
    initial begin
        if (LEN != 256)
            $display("WARNING: window_rom LEN=%0d, expected 256", LEN);
    end

endmodule : window_rom

`default_nettype wire
