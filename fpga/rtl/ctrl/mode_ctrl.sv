// =============================================================================
// File:        mode_ctrl.sv
// Project:     Project Auris — FPGA-Accelerated Assistive Audio
// Module:      mode_ctrl
// Description: Mode controller.  Translates the 2-bit mode register into a
//              full set of default per-bin gain values and pushes them into
//              the inactive bank of the spectral_proc's dual-port gain-table
//              BRAM.  When the load is complete, asserts a 1-cycle commit
//              pulse to atomically swap banks (no glitch in the audio path).
//
//              For the MVP, ALL modes load a flat unity-gain table.  Mode-
//              specific shaping (audiogram compensation, high-shelf for
//              speech, etc.) is a Phase 4 enhancement and will be sourced
//              from the gen_default_tables.py tool.
//
//              FSM: ST_IDLE -> ST_LOAD -> ST_COMMIT -> ST_IDLE
//
// Author:      [generated]
// Created:     2026-07
// Clock Domain: CD_DSP (96 MHz)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module mode_ctrl import auris_pkg::*; #(
    parameter int unsigned N_BINS = GAIN_TABLE_DEPTH
) (
    input  wire                clk_i,
    input  wire                rst_n_i,

    input  wire [1:0]          mode_i,          // from reg_file
    input  wire                mode_we_i,       // pulse when mode reg is written

    // Streaming write port to gain-table bank BRAM
    output logic               bank_we_o,
    output logic [6:0]         bank_addr_o,
    output logic [15:0]        bank_wdata_o,
    output logic [1:0]         bank_sel_o,      // which bank to write
    output logic               bank_commit_o,   // pulse when load complete

    // Default parameter outputs (drive the relevant reg_file mirrors)
    output logic [23:0]        default_master_gain_o,
    output logic [23:0]        default_noise_floor_o,
    output logic [23:0]        default_gate_ratio_o
);

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        ST_IDLE,
        ST_LOAD,
        ST_COMMIT
    } state_t;

    state_t        state;
    logic [6:0]    load_idx;
    logic [1:0]    pending_bank;   // bank being written this transaction
    logic          active_bank;    // currently-live bank (0 or 1)

    // -------------------------------------------------------------------------
    // Gain-table lookup
    // -------------------------------------------------------------------------
    // For MVP, all modes return unity gain.  This is a single combinational
    // function that will be expanded in Phase 4 to read from
    // pre-computed per-mode tables.  MODE_BYPASS also uses unity gain;
    // the actual signal-bypass behaviour is implemented in
    // dsp_pipeline.sv via the dsp_enable_i input (REG_CONTROL bit 0).
    function automatic logic [15:0] lookup_gain(
        input logic [1:0] mode,
        input int         idx
    );
        // `mode` and `idx` are intentionally unused in the MVP; the
        // function returns UNITY_GAIN_Q14 for every mode including
        // MODE_BYPASS (3).  When Phase 4 per-mode tables land, the
        // case statement below will dispatch on `mode`.
        begin
            lookup_gain = UNITY_GAIN_Q14;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state              <= ST_IDLE;
            load_idx           <= 7'd0;
            pending_bank       <= 2'd1;   // write to bank B by default
            active_bank        <= 1'b0;   // bank A is live at reset
            bank_we_o          <= 1'b0;
            bank_addr_o        <= 7'd0;
            bank_wdata_o       <= 16'd0;
            bank_sel_o         <= 2'd0;
            bank_commit_o      <= 1'b0;
        end else begin
            // Defaults
            bank_we_o     <= 1'b0;
            bank_commit_o <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (mode_we_i) begin
                        // Target the inactive bank (toggle LSB)
                        pending_bank <= 2'(~active_bank);
                        load_idx     <= 7'd0;
                        state        <= ST_LOAD;
                    end
                end

                ST_LOAD: begin
                    bank_we_o     <= 1'b1;
                    bank_addr_o   <= load_idx;
                    bank_wdata_o  <= lookup_gain(mode_i, int'(load_idx));
                    bank_sel_o    <= pending_bank;
                    if (load_idx == N_BINS[$bits(load_idx)-1:0] - 7'd1) begin
                        state    <= ST_COMMIT;
                        load_idx <= 7'd0;
                    end else begin
                        load_idx <= load_idx + 7'd1;
                    end
                end

                ST_COMMIT: begin
                    bank_commit_o <= 1'b1;
                    active_bank   <= pending_bank[0];
                    state         <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Mode-specific defaults for the simple scalar registers
    // -------------------------------------------------------------------------
    // For MVP, all modes use the same defaults: master=unity, noise
    // floor=100, gate ratio=unity.  Phase 4 will tune these per mode.
    assign default_master_gain_o = {8'sd0, UNITY_GAIN_Q14};
    assign default_noise_floor_o = 24'sd100;
    assign default_gate_ratio_o  = {8'sd0, UNITY_GAIN_Q14};

    // -------------------------------------------------------------------------
    // Synthesis-time sanity
    // -------------------------------------------------------------------------
    initial begin
        if (N_BINS != 128) $display("WARNING: mode_ctrl N_BINS=%0d, expected 128", N_BINS);
    end

endmodule : mode_ctrl

`default_nettype wire
