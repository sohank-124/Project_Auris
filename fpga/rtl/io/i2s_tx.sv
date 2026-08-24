// =============================================================================
// File:        i2s_tx.sv
// Project:     Project Auris
// Module:      i2s_tx
// Description: I2S slave transmitter targeting the PCM5102A DAC in
//              **standard I2S** (Philips) format.  In standard I2S:
//
//                - LRCLK transitions one BCLK period *before* the MSB
//                - the data line is held low for the first BCLK period
//                  after the LRCLK transition (this is the "1-BCLK delay")
//                - the MSB is then clocked out on the second BCLK
//                  rising edge after LRCLK changes
//                - the slave drives sdata_o on the BCLK **falling** edge
//                  so the master (PCM5102A) sees a stable value on its
//                  subsequent BCLK **rising** edge
//
//              Shadow registers capture left_i/right_i on the LRCLK
//              falling edge when valid_i is high; on underflow the
//              transmitter emits silence (24'b0) for the entire frame
//              and asserts the sticky `underflow_o` flag.
//
//              Implementation: the shift register and FSM run on the
//              BCLK rising edge; sdata_o is a separate flip-flop clocked
//              on the BCLK **falling** edge, capturing sdata_q.  This
//              gives a clean half-period of setup + hold margin to the
//              PCM5102A's rising-edge latch.
//
// FSM (3 states, binary encoded):
//                 IDLE --> SHIFT_LEFT --> SHIFT_RIGHT --> IDLE
//
// Author:      [generated]
// Created:     2026-07
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module i2s_tx import auris_pkg::*; #(
    parameter int unsigned DATA_W = I2S_DATA_W   // 24 for PCM5102A
) (
    input  wire                bclk_i,
    input  wire                lrclk_i,
    output logic               sdata_o,
    input  wire                rst_n_i,
    input  wire [DATA_W-1:0]   left_i,
    input  wire [DATA_W-1:0]   right_i,
    input  wire                valid_i,
    output logic               underflow_o   // sticky
);

    // -------------------------------------------------------------------------
    // FSM encoding
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        ST_IDLE       = 2'd0,
        ST_SHIFT_LEFT = 2'd1,
        ST_SHIFT_RIGHT= 2'd2
    } state_t;

    // -------------------------------------------------------------------------
    // 2-FF synchroniser for lrclk_i into the bclk_i domain
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) logic [1:0] lrclk_sync;
    logic lrclk_s;
    logic lrclk_s_d;
    wire  lrclk_fall =  lrclk_s_d & ~lrclk_s;
    wire  lrclk_rise = ~lrclk_s_d &  lrclk_s;

    always_ff @(posedge bclk_i or negedge rst_n_i) begin
        if (!rst_n_i) lrclk_sync <= 2'b00;
        else          lrclk_sync <= {lrclk_sync[0], lrclk_i};
    end
    assign lrclk_s = lrclk_sync[1];

    always_ff @(posedge bclk_i or negedge rst_n_i) begin
        if (!rst_n_i) lrclk_s_d <= 1'b0;
        else          lrclk_s_d <= lrclk_s;
    end

    // -------------------------------------------------------------------------
    // Shadow registers + shift register
    // -------------------------------------------------------------------------
    // `tx_shadow_l` / `tx_shadow_r` are loaded from the host at the LRCLK
    // falling edge.  They are then clocked into `shift_reg` at the
    // start of each channel slot.  When valid_i is low we still load
    // silence so the output is well-defined and the consumer can detect
    // the underflow via `underflow_o`.
    logic [DATA_W-1:0] tx_shadow_l;
    logic [DATA_W-1:0] tx_shadow_r;
    logic [DATA_W-1:0] shift_reg;
    logic [4:0]        bit_cnt;     // counts 0..DATA_W-1, 5 bits
    state_t            state;

    // `sdata_q` is the "next bit to drive" register, updated on the
    // BCLK rising edge.  The actual output `sdata_o` is captured from
    // `sdata_q` on the BCLK falling edge (separate always_ff below).
    logic               sdata_q;

    // -------------------------------------------------------------------------
    // Main FSM (clocked on the BCLK rising edge)
    // -------------------------------------------------------------------------
    always_ff @(posedge bclk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state       <= ST_IDLE;
            bit_cnt     <= 5'd0;
            shift_reg   <= '0;
            tx_shadow_l <= '0;
            tx_shadow_r <= '0;
            sdata_q     <= 1'b0;
            underflow_o <= 1'b0;
        end else begin
            case (state)
                // -----------------------------------------------------------------
                ST_IDLE: begin
                    // Hold sdata low during the "1-BCLK delay" period
                    // (standard I2S) and during the inter-frame gap.
                    sdata_q <= 1'b0;

                    if (lrclk_fall) begin
                        // Start of LEFT-channel frame.  Capture host
                        // data into the shadow register.
                        if (valid_i) begin
                            tx_shadow_l <= left_i;
                            tx_shadow_r <= right_i;
                        end else begin
                            // No fresh sample available — emit silence and
                            // raise the sticky underflow flag.
                            tx_shadow_l <= {DATA_W{1'b0}};
                            tx_shadow_r <= {DATA_W{1'b0}};
                            underflow_o <= 1'b1;
                        end
                        bit_cnt <= 5'd0;
                        state   <= ST_SHIFT_LEFT;
                    end
                end

                // -----------------------------------------------------------------
                ST_SHIFT_LEFT: begin
                    // Drive MSB-first.  On the first cycle of this state
                    // we expose bit[DATA_W-1] of tx_shadow_l; on
                    // subsequent cycles we shift left and expose the
                    // next bit.  The "1-BCLK delay" is provided by the
                    // ST_IDLE state: we transition to ST_SHIFT_LEFT on
                    // the LRCLK falling edge and start clocking out the
                    // MSB one BCLK later, so the first bit appears 1
                    // BCLK after LRCLK falls.
                    if (bit_cnt == 5'd0) begin
                        shift_reg <= {tx_shadow_l[DATA_W-2:0], 1'b0};
                        sdata_q   <= tx_shadow_l[DATA_W-1];
                    end else begin
                        shift_reg <= {shift_reg[DATA_W-2:0], 1'b0};
                        sdata_q   <= shift_reg[DATA_W-1];
                    end

                    if (bit_cnt == 5'(DATA_W - 1)) begin
                        bit_cnt <= 5'd0;
                        state   <= ST_SHIFT_RIGHT;
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end

                // -----------------------------------------------------------------
                ST_SHIFT_RIGHT: begin
                    if (bit_cnt == 5'd0) begin
                        shift_reg <= {tx_shadow_r[DATA_W-2:0], 1'b0};
                        sdata_q   <= tx_shadow_r[DATA_W-1];
                    end else begin
                        shift_reg <= {shift_reg[DATA_W-2:0], 1'b0};
                        sdata_q   <= shift_reg[DATA_W-1];
                    end

                    if (bit_cnt == 5'(DATA_W - 1)) begin
                        bit_cnt <= 5'd0;
                        state   <= ST_IDLE;
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end

                // -----------------------------------------------------------------
                default: state <= ST_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // sdata_o output flop (clocked on the BCLK falling edge)
    // -------------------------------------------------------------------------
    // This ensures sdata_o changes on the BCLK falling edge, so the
    // PCM5102A sees a stable value when it latches on the subsequent
    // BCLK rising edge.  Half a BCLK period of setup + hold margin.
    always_ff @(negedge bclk_i or negedge rst_n_i) begin
        if (!rst_n_i) sdata_o <= 1'b0;
        else          sdata_o <= sdata_q;
    end

    // -------------------------------------------------------------------------
    // Synthesis-time sanity
    // -------------------------------------------------------------------------
    initial begin
        if (DATA_W < 8 || DATA_W > 24) begin
            $display("ERROR: i2s_tx DATA_W=%0d is out of supported range [8..24]", DATA_W);
        end
    end

endmodule : i2s_tx

`default_nettype wire
