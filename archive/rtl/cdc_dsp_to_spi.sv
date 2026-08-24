// =============================================================================
// File:        cdc_dsp_to_spi.sv
// Project:     Project Auris
// Module:      cdc_dsp_to_spi
// Description: CDC for the read-data return path from the DSP domain
//              (96 MHz) back to the SPI SCLK domain (10 MHz).  This is
//              the counterpart to `cdc_spi_to_dsp`.
//
//              Implementation: 4-phase request-acknowledge handshake with
//              stable-data-before-valid semantics.  This avoids the
//              bit-wise 2-FF synchronisation anti-pattern (which can
//              produce transient garbage on a multi-bit bus while the
//              control strobe is being synchronised).
//
//              Sequence:
//                1. DSP domain: on src_valid_i pulse, latch src_rdata_i
//                   into a hold register and assert src_req.
//                2. src_req is 2-FF synchronised into the SPI domain
//                   (dst_req_sync[1]).
//                3. SPI domain: when dst_req is high, the hold register
//                   is SAFE to read (it has been stable for at least
//                   2 dst_clk cycles, the synchroniser latency).  Pulse
//                   dst_valid_o for one SPI clock and assert dst_ack.
//                4. dst_ack is 2-FF synchronised back to the DSP domain
//                   (src_ack_sync[1]) and clears src_req.
//
//              The data is held stable in src_rdata_hold from the time
//              src_req is asserted until src_ack_sync[1] is observed
//              high, ensuring the destination always sees a clean
//              multi-bit value alongside its valid strobe.
//
// Author:      [generated]
// Created:     2026-07
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module cdc_dsp_to_spi import auris_pkg::*; #(
    parameter int unsigned DATA_W = 24
) (
    // Source side (DSP domain, 96 MHz)
    input  wire                src_clk_i,
    input  wire                src_rst_n_i,
    input  wire [DATA_W-1:0]   src_rdata_i,
    input  wire                src_valid_i,

    // Destination side (SPI SCLK domain, 10 MHz)
    input  wire                dst_clk_i,
    input  wire                dst_rst_n_i,
    output wire [DATA_W-1:0]   dst_rdata_o,
    output wire                dst_valid_o
);

    // -------------------------------------------------------------------------
    // Source (DSP) domain state
    // -------------------------------------------------------------------------
    // src_rdata_hold: stable copy of src_rdata_i, latched when src_valid_i
    //                 pulses, held until the destination has acknowledged
    //                 the transfer.
    // src_req:        request to the destination.  Asserted on src_valid_i,
    //                 cleared when the synchronised ack returns.
    logic [DATA_W-1:0] src_rdata_hold;
    logic              src_req;
    logic              src_ack_sync_1;     // 2-FF synced ack from dst

    initial begin
        src_rdata_hold  = '0;
        src_req         = 1'b0;
        src_ack_sync_1  = 1'b0;
    end

    always_ff @(posedge src_clk_i or negedge src_rst_n_i) begin
        if (!src_rst_n_i) begin
            src_rdata_hold <= '0;
            src_req        <= 1'b0;
        end else begin
            if (src_valid_i) begin
                // Latch data and raise request.
                src_rdata_hold <= src_rdata_i;
                src_req        <= 1'b1;
            end else if (src_ack_sync_1) begin
                // Destination has consumed the data: lower request.
                src_req        <= 1'b0;
            end
            // else: hold src_req high until the ack comes back.
        end
    end

    // -------------------------------------------------------------------------
    // Ack 2-FF synchroniser (dst -> src)
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) logic [1:0] src_ack_sync;

    always_ff @(posedge src_clk_i or negedge src_rst_n_i) begin
        if (!src_rst_n_i) src_ack_sync <= 2'b00;
        else              src_ack_sync <= {src_ack_sync[0], dst_ack};
    end
    assign src_ack_sync_1 = src_ack_sync[1];

    // -------------------------------------------------------------------------
    // Destination (SPI) domain state — declared early because dst_ack is
    // referenced by the ack synchroniser above.
    // -------------------------------------------------------------------------
    logic [DATA_W-1:0] dst_rdata_r;
    logic              dst_valid_r;
    logic              dst_ack;

    // -------------------------------------------------------------------------
    // Request 2-FF synchroniser (src -> dst)
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) logic [1:0] dst_req_sync;

    always_ff @(posedge dst_clk_i or negedge dst_rst_n_i) begin
        if (!dst_rst_n_i) dst_req_sync <= 2'b00;
        else              dst_req_sync <= {dst_req_sync[0], src_req};
    end

    // -------------------------------------------------------------------------
    // Destination (SPI) domain state
    // -------------------------------------------------------------------------
    initial begin
        dst_rdata_r = '0;
        dst_valid_r = 1'b0;
        dst_ack     = 1'b0;
    end

    always_ff @(posedge dst_clk_i or negedge dst_rst_n_i) begin
        if (!dst_rst_n_i) begin
            dst_rdata_r <= '0;
            dst_valid_r <= 1'b0;
            dst_ack     <= 1'b0;
        end else begin
            dst_valid_r <= 1'b0;     // default: single-cycle pulse

            if (dst_req_sync[1] && !dst_ack) begin
                // New request from the source.  The data on
                // src_rdata_hold has been stable for at least 2 dst
                // clocks (synchroniser latency), so it is safe to
                // sample it here on the dst clock.
                dst_rdata_r <= src_rdata_hold;
                dst_valid_r <= 1'b1;
                dst_ack     <= 1'b1;
            end else if (dst_ack && !dst_req_sync[1]) begin
                // Source has seen our ack (request dropped); clear ack
                // so the next request can be serviced.
                dst_ack     <= 1'b0;
            end
        end
    end

    assign dst_rdata_o = dst_rdata_r;
    assign dst_valid_o = dst_valid_r;

    // -------------------------------------------------------------------------
    // Sanity check
    // -------------------------------------------------------------------------
    initial begin
        if (DATA_W < 1) begin
            $display("ERROR: cdc_dsp_to_spi DATA_W=%0d out of range", DATA_W);
        end
    end

endmodule : cdc_dsp_to_spi

`default_nettype wire
