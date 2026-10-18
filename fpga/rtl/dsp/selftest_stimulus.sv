// =============================================================================
// File:        selftest_stimulus.sv
// Project:     Project Auris
// Module:      selftest_stimulus
// Description: Deterministic internal sample source for FPGA-only bring-up
//              when external codecs are not attached.
//
//              Outputs one sample pair at SAMPLE_HZ in the DSP clock domain.
//              Waveform is selected by mode_i:
//                0: impulse train
//                1: square wave
//                2: sawtooth ramp
//                3: PRBS-shaped noise
//
//              This module is intended for lab validation and should be gated
//              by a top-level compile-time switch.
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module selftest_stimulus #(
    parameter int unsigned CLK_HZ    = 96_000_000,
    parameter int unsigned SAMPLE_HZ = 48_000,
    parameter int unsigned SAMPLE_W  = 24
) (
    input  wire                      clk_i,
    input  wire                      rst_n_i,
    input  wire                      enable_i,
    input  wire [1:0]                mode_i,
    output logic [SAMPLE_W-1:0]      sample_l_o,
    output logic [SAMPLE_W-1:0]      sample_r_o,
    output logic                     sample_v_o
);

    localparam int unsigned DIVISOR = (CLK_HZ / SAMPLE_HZ);
    localparam int unsigned DIV_W   = $clog2(DIVISOR);

    logic [DIV_W-1:0] div_ctr;
    logic [23:0] phase_acc;
    logic [10:0] impulse_ctr;
    logic [22:0] lfsr;

    logic signed [SAMPLE_W-1:0] sample_s;
    logic signed [SAMPLE_W-1:0] amp_impulse;
    logic signed [SAMPLE_W-1:0] amp_square;
    logic signed [SAMPLE_W-1:0] amp_saw;

    assign amp_impulse = 24'sd2097152;  // 0.25 FS
    assign amp_square  = phase_acc[23] ? -24'sd1048576 : 24'sd1048576;
    assign amp_saw     = {phase_acc[23], phase_acc[22:0]};

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            div_ctr      <= '0;
            phase_acc    <= 24'd0;
            impulse_ctr  <= 11'd0;
            lfsr         <= 23'h5A5A5A;
            sample_l_o   <= '0;
            sample_r_o   <= '0;
            sample_v_o   <= 1'b0;
        end else begin
            sample_v_o <= 1'b0;

            if (!enable_i) begin
                sample_l_o <= '0;
                sample_r_o <= '0;
            end else begin
                if (div_ctr == DIVISOR - 1) begin
                    div_ctr   <= '0;
                    sample_v_o <= 1'b1;

                    phase_acc <= phase_acc + 24'd196608; // ~375 Hz tone base
                    lfsr      <= {lfsr[21:0], lfsr[22] ^ lfsr[17]};

                    if (impulse_ctr == 11'd1023) impulse_ctr <= 11'd0;
                    else                         impulse_ctr <= impulse_ctr + 11'd1;

                    case (mode_i)
                        2'd0: sample_s = (impulse_ctr == 11'd0) ? amp_impulse : 24'sd0;
                        2'd1: sample_s = amp_square;
                        2'd2: sample_s = amp_saw;
                        2'd3: sample_s = {lfsr[22], lfsr};
                        default: sample_s = 24'sd0;
                    endcase

                    sample_l_o <= sample_s;
                    sample_r_o <= sample_s;
                end else begin
                    div_ctr <= div_ctr + 1'b1;
                end
            end
        end
    end

    initial begin
        if ((CLK_HZ % SAMPLE_HZ) != 0) begin
            $display("ERROR: selftest_stimulus requires integer CLK_HZ/SAMPLE_HZ ratio");
        end
    end

endmodule

`default_nettype wire
