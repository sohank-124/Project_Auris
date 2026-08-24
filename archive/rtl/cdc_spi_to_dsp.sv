// =============================================================================
// File:        cdc_spi_to_dsp.sv
// Project:     Project Auris
// Module:      cdc_spi_to_dsp
// Description: Handshake-based CDC for the multi-bit SPI control payload
//              (7-bit address + 24-bit write data + 1-bit we + 1-bit re)
//              crossing from the SPI SCLK domain (10 MHz) to the DSP
//              domain (96 MHz).
//
//              Why a handshake?  A 32-bit (or wider) bus cannot safely
//              be transported by a plain 2-FF synchroniser because bits
//              can arrive skewed and the destination can sample a
//              transient intermediate value.  A 4-phase req/ack handshake
//              guarantees that the entire payload is stable in the
//              destination domain before the consumer sees the
//              associated we_o / re_o pulse.
//
//              Handshake protocol (4-phase, return-to-zero):
//                 1. SPI side:  src_we_i || src_re_i pulse →
//                                 latch addr+wdata into hold regs,
//                                 assert `req` (source-domain FF).
//                 2.            `req` is 2-FF synchronised into DSP
//                                 domain → `dst_req_sync[1]`.
//                 3. DSP side:  rising edge of `dst_req_sync[1]`
//                                 (with a 1-cycle delayed copy for
//                                 edge detection) → assert dst_we_o
//                                 or dst_re_o for one DSP cycle, then
//                                 assert `ack` (DSP-domain FF).
//                 4.            `ack` is 2-FF synchronised back into SPI
//                                 domain → `src_ack`.
//                 5. SPI side:  `src_ack` rising edge → clear `req`.
//                 6.            `req` clearing propagates back, ack
//                                 clears, both sides return to idle.
//
//              This module only synchronises the control signals.  The
//              address / data payload is held in source-side hold
//              registers and is assumed to be stable while `req` is
//              high (the destination samples the hold registers via the
//              ack-based protocol).
//
//              `ASYNC_REG = "TRUE"` is applied to every synchroniser
//              flip-flop pair.
//
// Author:      [generated]
// Created:     2026-07
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module cdc_spi_to_dsp import auris_pkg::*; #(
    parameter int unsigned ADDR_W = 7,
    parameter int unsigned DATA_W = 24
) (
    // Source side (SPI SCLK domain, 10 MHz)
    input  wire                    src_clk_i,
    input  wire                    src_rst_n_i,
    input  wire [ADDR_W-1:0]       src_addr_i,
    input  wire [DATA_W-1:0]       src_wdata_i,
    input  wire                    src_we_i,
    input  wire                    src_re_i,
    output wire                    src_ack_o,

    // Destination side (DSP domain, 96 MHz)
    input  wire                    dst_clk_i,
    input  wire                    dst_rst_n_i,
    output wire [ADDR_W-1:0]       dst_addr_o,
    output wire [DATA_W-1:0]       dst_wdata_o,
    output wire                    dst_we_o,
    output wire                    dst_re_o
);

    // -------------------------------------------------------------------------
    // Source-side state
    // -------------------------------------------------------------------------
    logic [ADDR_W-1:0] src_addr_hold;
    logic [DATA_W-1:0] src_wdata_hold;
    logic             src_we_hold;
    logic             src_re_hold;
    logic             src_req;

    // -------------------------------------------------------------------------
    // 2-FF synchroniser: src_req → dst domain
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) logic [1:0] dst_req_sync;
    // Delayed copy of dst_req_sync[1] for rising-edge detection.
    logic dst_req_r;

    // -------------------------------------------------------------------------
    // Destination-side state
    // -------------------------------------------------------------------------
    logic [ADDR_W-1:0] dst_addr_r;
    logic [DATA_W-1:0] dst_wdata_r;
    logic             dst_we_pulse;
    logic             dst_re_pulse;
    logic             dst_ack;          // DSP-domain ack FF
    logic             fired;            // "this request has been fired" latch

    // -------------------------------------------------------------------------
    // 2-FF synchroniser: dst_ack → src domain
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) logic [1:0] src_ack_sync;

    // -------------------------------------------------------------------------
    // Continuous outputs
    // -------------------------------------------------------------------------
    assign src_ack_o  = src_ack_sync[1];
    assign dst_addr_o  = dst_addr_r;
    assign dst_wdata_o = dst_wdata_r;
    assign dst_we_o    = dst_we_pulse;
    assign dst_re_o    = dst_re_pulse;

    // -------------------------------------------------------------------------
    // Default initial values (sim determinism only).
    // -------------------------------------------------------------------------
    initial begin
        src_addr_hold  = '0;
        src_wdata_hold = '0;
        src_we_hold    = 1'b0;
        src_re_hold    = 1'b0;
        src_req        = 1'b0;
        dst_req_sync   = 2'b00;
        dst_req_r      = 1'b0;
        dst_addr_r     = '0;
        dst_wdata_r    = '0;
        dst_we_pulse   = 1'b0;
        dst_re_pulse   = 1'b0;
        dst_ack        = 1'b0;
        fired          = 1'b0;
        src_ack_sync   = 2'b00;
    end

    // -------------------------------------------------------------------------
    // Source-side sequential logic
    // -------------------------------------------------------------------------
    always_ff @(posedge src_clk_i or negedge src_rst_n_i) begin
        if (!src_rst_n_i) begin
            src_addr_hold  <= '0;
            src_wdata_hold <= '0;
            src_we_hold    <= 1'b0;
            src_re_hold    <= 1'b0;
            src_req        <= 1'b0;
        end else begin
            // Latch a new transaction.
            if (src_we_i || src_re_i) begin
                src_addr_hold  <= src_addr_i;
                src_wdata_hold <= src_wdata_i;
                src_we_hold    <= src_we_i;
                src_re_hold    <= src_re_i;
                src_req        <= 1'b1;
            end else if (src_ack_sync[1]) begin
                // Acknowledge from the destination has been seen;
                // clear the request and the hold flags.
                src_req     <= 1'b0;
                src_we_hold <= 1'b0;
                src_re_hold <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 2-FF synchroniser: src_req -> dst domain + delayed copy for edge detect
    // -------------------------------------------------------------------------
    always_ff @(posedge dst_clk_i or negedge dst_rst_n_i) begin
        if (!dst_rst_n_i) begin
            dst_req_sync <= 2'b00;
            dst_req_r    <= 1'b0;
        end else begin
            dst_req_sync <= {dst_req_sync[0], src_req};
            dst_req_r    <= dst_req_sync[1];
        end
    end

    wire dst_req_rising = dst_req_sync[1] & ~dst_req_r;

    // -------------------------------------------------------------------------
    // Destination-side FSM
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        DST_IDLE = 2'd0,
        DST_FIRE = 2'd1,
        DST_WAIT = 2'd2
    } dst_state_t;

    dst_state_t dst_state;

    initial dst_state = DST_IDLE;

    always_ff @(posedge dst_clk_i or negedge dst_rst_n_i) begin
        if (!dst_rst_n_i) begin
            dst_state   <= DST_IDLE;
            dst_addr_r  <= '0;
            dst_wdata_r <= '0;
            dst_we_pulse<= 1'b0;
            dst_re_pulse<= 1'b0;
            dst_ack     <= 1'b0;
            fired       <= 1'b0;
        end else begin
            // Default: no strobe.
            dst_we_pulse <= 1'b0;
            dst_re_pulse <= 1'b0;

            case (dst_state)
                DST_IDLE: begin
                    // Wait for a rising edge of the synchronised
                    // request.  The `fired` flag ensures we only
                    // process each request once, even if the source
                    // holds `req` high for an extended period.
                    if (dst_req_rising && !fired) begin
                        dst_addr_r   <= src_addr_hold;
                        dst_wdata_r  <= src_wdata_hold;
                        dst_we_pulse <= src_we_hold;
                        dst_re_pulse <= src_re_hold;
                        fired        <= 1'b1;
                        dst_state    <= DST_FIRE;
                    end
                end

                DST_FIRE: begin
                    // Ack is registered combinationally; here we just
                    // transition to WAIT to assert it.
                    dst_ack   <= 1'b1;
                    dst_state <= DST_WAIT;
                end

                DST_WAIT: begin
                    // Hold ack high until the request goes away.
                    // Once it does, the source-side 2-FF sync
                    // propagates the falling edge back as src_ack
                    // going low, and we return to IDLE.
                    if (!dst_req_sync[1]) begin
                        dst_ack   <= 1'b0;
                        fired     <= 1'b0;
                        dst_state <= DST_IDLE;
                    end
                end

                default: dst_state <= DST_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 2-FF synchroniser: dst_ack -> src domain
    // -------------------------------------------------------------------------
    always_ff @(posedge src_clk_i or negedge src_rst_n_i) begin
        if (!src_rst_n_i) src_ack_sync <= 2'b00;
        else              src_ack_sync <= {src_ack_sync[0], dst_ack};
    end

    // -------------------------------------------------------------------------
    // Sanity check
    // -------------------------------------------------------------------------
    initial begin
        if (ADDR_W < 1 || DATA_W < 8) begin
            $display("ERROR: cdc_spi_to_dsp ADDR_W=%0d or DATA_W=%0d out of range", ADDR_W, DATA_W);
        end
    end

endmodule : cdc_spi_to_dsp

`default_nettype wire
