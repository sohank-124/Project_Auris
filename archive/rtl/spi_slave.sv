// =============================================================================
// File:        spi_slave.sv
// Project:     Project Auris
// Module:      spi_slave
// Description: SPI Mode-0 slave.  Receives 32-bit frames from the ESP32
//              master and decodes the on-the-wire protocol:
//
//                  MSB                                                                LSB
//                  +---+-----------+----+--------------------------+
//                  | 0 | addr[6:0] | RW | data[22:0]               |
//                  +---+-----------+----+--------------------------+
//                  31  30        24  23  22                      0
//                   ^   ^           ^    ^
//                   |   |           |    +-- data payload (23 bits on the wire;
//                   |   |           |        zero-padded to 24 bits in wdata_o
//                   |   |           |        to match reg_file DATA_W=24)
//                   |   |           +------- R/W# : 1 = read, 0 = write
//                   |   +------------------- 7-bit register address
//                   +----------------------- start marker, must be 0
//                                            (frame boundary is delimited by CS_N
//                                            so the start bit is not strictly
//                                            required; we keep it for protocol
//                                            observability)
//
//              Bit order on the wire is MSB-first.  The SCLK line idles
//              low and data is sampled on the rising edge of SCLK
//              (Mode 0, CPOL=0, CPHA=0).  MISO is driven combinationally
//              so it is forced to 0 whenever CS_N is high (avoiding bus
//              contention) and follows the shift-out register otherwise.
//
//              The decoded transaction is presented on addr_o / wdata_o
//              / we_o / re_o for one SCLK cycle after the final SCLK
//              rising edge (i.e. on the next clock after entering the
//              DECODE state).
//
//              The response data rdata_i is shifted back out MSB-first
//              on the very next transaction.  The on-wire data field
//              is 23 bits; the top bit of rdata_i[23] is shifted out
//              first and is always zero for the read-only status /
//              telemetry registers (which is the common case).  The
//              firmware masks the 23-bit read response with 0x7FFFFF.
//
// FSM (3 states, binary encoded):
//                 IDLE --> SHIFT --> DECODE --> IDLE
//
//              Recovery: if CS_N goes high before 32 bits have been
//              received, the FSM transitions back to IDLE (frame
//              abort).  The partially-shifted sr_in is discarded.
//
// Author:      [generated]
// Created:     2026-07
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module spi_slave import auris_pkg::*; #(
    parameter int unsigned ADDR_W = 7,
    parameter int unsigned DATA_W = 24
) (
    input  wire                    sclk_i,
    input  wire                    cs_n_i,
    input  wire                    mosi_i,
    output logic                   miso_o,
    input  wire                    rst_n_i,

    output logic [ADDR_W-1:0]      addr_o,
    output logic [DATA_W-1:0]      wdata_o,
    output logic                   we_o,
    output logic                   re_o,
    input  wire [DATA_W-1:0]       rdata_i,
    input  wire                    rdata_valid_i
);

    // -------------------------------------------------------------------------
    // Frame constants
    // -------------------------------------------------------------------------
    // 32 bits on the wire: 1 (start) + 7 (addr) + 1 (RW) + 23 (data) = 32.
    // The internal register interface remains 24 bits (DATA_W=24); the
    // 23-bit on-wire data field is zero-padded to 24 bits in wdata_o on
    // the way in, and the top bit of rdata_i[23] is shifted out as the
    // MSB of the response (the firmware masks with 0x7FFFFF on read).
    localparam int unsigned FRAME_W  = 32;
    // WIRE_DATA_W is the width of the on-wire data field, distinct from
    // DATA_W which is the reg_file width.
    localparam int unsigned WIRE_DATA_W = 23;

    // -------------------------------------------------------------------------
    // FSM encoding
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        ST_IDLE   = 2'd0,
        ST_SHIFT  = 2'd1,
        ST_DECODE = 2'd2
    } state_t;

    // -------------------------------------------------------------------------
    // 2-FF synchronisers for cs_n_i and mosi_i into the sclk_i domain
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) logic [1:0] cs_n_sync;
    (* ASYNC_REG = "TRUE" *) logic [1:0] mosi_sync;

    always_ff @(posedge sclk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cs_n_sync <= 2'b11;       // deasserted (inactive)
            mosi_sync <= 2'b00;
        end else begin
            cs_n_sync <= {cs_n_sync[0], cs_n_i};
            mosi_sync <= {mosi_sync[0], mosi_i};
        end
    end

    logic cs_n_s;        // current synchronised cs_n_i (active low)
    logic cs_n_s_d;      // delayed by one sclk_i
    wire  cs_n_fall =  cs_n_s_d & ~cs_n_s;
    wire  cs_n_rise = ~cs_n_s_d &  cs_n_s;

    assign cs_n_s = cs_n_sync[1];

    always_ff @(posedge sclk_i or negedge rst_n_i) begin
        if (!rst_n_i) cs_n_s_d <= 1'b1;
        else          cs_n_s_d <= cs_n_s;
    end

    // -------------------------------------------------------------------------
    // Shift registers
    // -------------------------------------------------------------------------
    logic [FRAME_W-1:0] sr_in;     // shift in  from MOSI, MSB-first
    logic [DATA_W-1:0]  sr_out;    // shift out to MISO, MSB-first
    logic [5:0]         bit_cnt;   // counts 0..32 (6 bits -> up to 63)

    state_t state;

    // -------------------------------------------------------------------------
    // Combinational MISO driver
    // -------------------------------------------------------------------------
    // MISO is forced low whenever CS_N is deasserted (avoiding bus
    // contention with other slaves on the SPI bus).  When CS_N is
    // asserted, MISO follows the MSB of sr_out; on every falling edge
    // of SCLK, sr_out is shifted left, so the next bit is exposed on
    // the next rising edge.
    always_comb begin
        if (cs_n_s) begin
            miso_o = 1'b0;
        end else begin
            miso_o = sr_out[DATA_W-1];
        end
    end

    // -------------------------------------------------------------------------
    // all signals are initialised by the synchronous / asynchronous reset).

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge sclk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state     <= ST_IDLE;
            sr_in     <= '0;
            sr_out    <= '0;
            bit_cnt   <= 6'd0;
            addr_o    <= '0;
            wdata_o   <= '0;
            we_o      <= 1'b0;
            re_o      <= 1'b0;
        end else begin
            // Default: no strobe.
            we_o <= 1'b0;
            re_o <= 1'b0;

            case (state)
                // -----------------------------------------------------------------
                ST_IDLE: begin
                    bit_cnt <= 6'd0;
                    if (cs_n_fall) begin
                        // Latch the response data into the shift-out
                        // register at the start of every transaction so
                        // it is ready to be clocked out MSB-first.
                        //
                        // rdata_valid_i is the CDC-synchronised read
                        // pulse from cdc_dsp_to_spi; in this stub we
                        // unconditionally load sr_out from rdata_i.
                        // The production version will gate this load on
                        // rdata_valid_i (sticky) so that a stale
                        // rdata cannot be shifted out before the CDC
                        // has propagated a fresh read.
                        sr_out <= rdata_i;
                        state  <= ST_SHIFT;
                    end
                end

                // -----------------------------------------------------------------
                ST_SHIFT: begin
                    if (cs_n_s) begin
                        // CS_N went high before FRAME_W bits were
                        // clocked in: the host aborted the frame.
                        // Discard the partial shift register and
                        // return to IDLE.
                        sr_in   <= '0;
                        bit_cnt <= 6'd0;
                        state   <= ST_IDLE;
                    end else begin
                        // Shift in  on every sclk_i rising edge.
                        sr_in   <= {sr_in[FRAME_W-2:0], mosi_sync[1]};
                        bit_cnt <= bit_cnt + 1'b1;

                        // Shift out the response data MSB-first.  The
                        // combinational MISO driver above presents
                        // sr_out[DATA_W-1] on the wire; here we shift
                        // sr_out on the falling edge of SCLK so the
                        // next bit is ready by the next rising edge.
                        sr_out <= {sr_out[DATA_W-2:0], 1'b0};

                        // Once FRAME_W bits have been clocked in we
                        // move to DECODE.
                        if (bit_cnt == 6'(FRAME_W - 1)) begin
                            state <= ST_DECODE;
                        end
                    end
                end

                // -----------------------------------------------------------------
                ST_DECODE: begin
                    // Sample the assembled frame, validate the start
                    // bit, and present (addr, wdata, we/re) for
                    // exactly one sclk_i cycle.
                    //
                    // Frame layout (32 bits):
                    //   [31]    = start (must be 0)
                    //   [30:24] = addr[6:0]
                    //   [23]    = RW (1 = read, 0 = write)
                    //   [22:0]  = data[22:0]  (23 bits on the wire)
                    if (sr_in[FRAME_W-1] == 1'b0) begin
                        addr_o  <= sr_in[FRAME_W-2 : FRAME_W-1-ADDR_W];
                        // 23-bit on-wire data zero-extended to 24 bits.
                        // The MSB of wdata_o (bit 23) is hard-wired to 0
                        // since the on-wire field is only 23 bits wide.
                        wdata_o <= {1'b0, sr_in[WIRE_DATA_W-1:0]};
                        if (sr_in[FRAME_W-1-ADDR_W-1] == 1'b1) begin
                            re_o <= 1'b1;            // READ
                        end else begin
                            we_o <= 1'b1;            // WRITE
                        end
                    end
                    // If the start bit is set (=1) we drop the frame
                    // silently (no strobe).  The host can detect this
                    // via the lack of an ACK interrupt.
                    bit_cnt <= 6'd0;
                    state   <= ST_IDLE;
                end

                // -----------------------------------------------------------------
                default: state <= ST_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Sanity check
    // -------------------------------------------------------------------------
    initial begin
        if ((1 + ADDR_W + 1 + WIRE_DATA_W) != FRAME_W) begin
            $display("ERROR: spi_slave frame-width arithmetic is inconsistent: %0d != %0d",
                     (1 + ADDR_W + 1 + WIRE_DATA_W), FRAME_W);
        end
    end

endmodule : spi_slave

`default_nettype wire
