// =============================================================================
// File:        mode_ctrl.sv
// Project:     Project Auris — FPGA-Accelerated Assistive Audio
// Module:      mode_ctrl
// Description: Mode controller with pre-computed per-mode gain tables for
//              FPGA-only operation.  Translates the 2-bit mode register into
//              a full set of default per-bin gain values and pushes them into
//              the inactive bank of the spectral_proc's dual-port gain-table
//              BRAM.  When the load is complete, asserts a 1-cycle commit
//              pulse to atomically swap banks (no glitch in the audio path).
//
//              Each operating mode ships with a hand-curated 128-bin gain
//              curve that shapes the audio spectrum appropriately for the
//              intended listening scenario.  All coefficients are expressed
//              in Q2.14 fixed-point (UNITY_GAIN_Q14 = 16384 = 1.0×).
//
//              At reset the GENERAL (flat-unity) curve is loaded into the
//              inactive bank via the `initial_load` flag so the gain BRAM
//              holds a valid, mode-traceable pattern immediately after
//              configuration.  A subsequent `mode_we_i` reloads the table
//              for the newly-selected mode using the same load/commit FSM.
//
//              FSM: ST_IDLE -> ST_LOAD -> ST_COMMIT -> ST_IDLE
//
// Author:      [generated]
// Created:     2026-07
// Modified:    2026-08 (FPGA-only migration: added per-mode gain tables,
//                          removed ESP32 dependency)
// Clock Domain: CD_DSP (96 MHz)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module mode_ctrl import auris_pkg::*; #(
    parameter int unsigned N_BINS = GAIN_TABLE_DEPTH
) (
    input  wire                clk_i,
    input  wire                rst_n_i,

    input  wire [1:0]          mode_i,          // from top-level button FSM
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
    // Per-mode gain tables (Q2.14 fixed-point, 16384 = unity)
    //
    // With Fs = 48 kHz and FFT_LEN = 256 (real input), the FFT produces
    // GAIN_TABLE_DEPTH = FFT_LEN / 2 = 128 unique bins at 187.5 Hz spacing.
    // Each table below is the audio engineering "first cut" for that
    // scenario and ships in silicon so the device produces predictable
    // audio before any host-side tuning is applied.  All tables are
    // intentionally simple piecewise-constant curves; finer-grained shaping
    // (e.g. per-mode interpolation of audiogram data) is a later phase.
    //
    // The annotations after each coefficient give the corresponding linear
    // multiplier (e.g. "28672 (1.75×)") so the file is self-documenting.
    //
    // Resource: each table is 128 x 16 = 2048 bits of constant data.
    // Vivado typically packs such lookup constants into distributed LUT-ROM
    // (no BRAM) and the synthesizer strips them entirely if the table is
    // unreachable — net cost is negligible on a 7S25.
    // -------------------------------------------------------------------------

    // -- MODE_GENERAL: transparent passthrough (1.00× everywhere) ------------
    localparam logic [15:0] GAIN_GENERAL [0:127] = '{
        // bins   0- 15: flat unity passthrough (1.00×)
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        // bins  16- 31: flat unity passthrough (1.00×)
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        // bins  32- 47: flat unity passthrough (1.00×)
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        // bins  48- 63: flat unity passthrough (1.00×)
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        // bins  64- 79: flat unity passthrough (1.00×)
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        // bins  80- 95: flat unity passthrough (1.00×)
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        // bins  96-111: flat unity passthrough (1.00×)
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        // bins 112-127: flat unity passthrough (1.00×)
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384
    };

    // -- MODE_SPEECH: vocal presence boost with high-shelf roll-off ----------
    //   Bins   0-  1: 0.50×  -- suppress sub-bass / handling noise
    //   Bins   2-  3: 0.75×  -- gentle low-cut above 375 Hz
    //   Bins   4- 20: 1.75×  -- presence boost on vocal fundamentals
    //   Bins  21- 31: 1.30×  -- taper above 4 kHz
    //   Bins  32-127: 0.90×  -- gentle high-shelf roll-off (sibilance taming)
    localparam logic [15:0] GAIN_SPEECH [0:127] = '{
        // bins  0-  1: 8192  (0.50×) suppress sub-bass / handling noise
        // bins  2-  3: 12288 (0.75×) gentle low-cut above 375 Hz
        // bins  4-  7: 28672 (1.75×) presence boost on vocal fundamentals
         8192,  8192, 12288, 12288, 28672, 28672, 28672, 28672,
        // bins  8- 15: 28672 (1.75×)
        28672, 28672, 28672, 28672, 28672, 28672, 28672, 28672,
        // bins 16- 20: 28672 (1.75×)
        // bins 21- 23: 21299 (1.30×) taper above 4 kHz
        28672, 28672, 28672, 28672, 28672, 21299, 21299, 21299,
        // bins 24- 31: 21299 (1.30×)
        21299, 21299, 21299, 21299, 21299, 21299, 21299, 21299,
        // bins 32- 39: 14746 (0.90×) gentle high-shelf roll-off
        14746, 14746, 14746, 14746, 14746, 14746, 14746, 14746,
        // bins 40- 47: 14746 (0.90×)
        14746, 14746, 14746, 14746, 14746, 14746, 14746, 14746,
        // bins 48- 55: 14746 (0.90×)
        14746, 14746, 14746, 14746, 14746, 14746, 14746, 14746,
        // bins 56- 63: 14746 (0.90×)
        14746, 14746, 14746, 14746, 14746, 14746, 14746, 14746,
        // bins 64- 71: 14746 (0.90×)
        14746, 14746, 14746, 14746, 14746, 14746, 14746, 14746,
        // bins 72- 79: 14746 (0.90×)
        14746, 14746, 14746, 14746, 14746, 14746, 14746, 14746,
        // bins 80- 87: 14746 (0.90×)
        14746, 14746, 14746, 14746, 14746, 14746, 14746, 14746,
        // bins 88- 95: 14746 (0.90×)
        14746, 14746, 14746, 14746, 14746, 14746, 14746, 14746,
        // bins 96-103: 14746 (0.90×)
        14746, 14746, 14746, 14746, 14746, 14746, 14746, 14746,
        // bins 104-111: 14746 (0.90×)
        14746, 14746, 14746, 14746, 14746, 14746, 14746, 14746,
        // bins 112-119: 14746 (0.90×)
        14746, 14746, 14746, 14746, 14746, 14746, 14746, 14746,
        // bins 120-127: 14746 (0.90×)
        14746, 14746, 14746, 14746, 14746, 14746, 14746, 14746
    };

    // -- MODE_MUSIC: flat mids with sub-bass lift and air shelf ---------------
    //   Bin    0   : 1.20×  -- gentle DC / sub-bass lift
    //   Bins   1- 31: 1.00×  -- flat through vocal & instrument range
    //   Bins  32-127: 1.15×  -- air / sparkle shelf above 6 kHz
    localparam logic [15:0] GAIN_MUSIC [0:127] = '{
        // bin   0    : 19661 (1.20×) gentle DC / sub-bass lift
        // bins  1-  7: 16384 (1.00×) flat through vocal & instrument range
        19661, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        // bins  8- 15: 16384 (1.00×)
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        // bins 16- 23: 16384 (1.00×)
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        // bins 24- 31: 16384 (1.00×)
        16384, 16384, 16384, 16384, 16384, 16384, 16384, 16384,
        // bins 32- 39: 18841 (1.15×) air / sparkle shelf above 6 kHz
        18841, 18841, 18841, 18841, 18841, 18841, 18841, 18841,
        // bins 40- 47: 18841 (1.15×)
        18841, 18841, 18841, 18841, 18841, 18841, 18841, 18841,
        // bins 48- 55: 18841 (1.15×)
        18841, 18841, 18841, 18841, 18841, 18841, 18841, 18841,
        // bins 56- 63: 18841 (1.15×)
        18841, 18841, 18841, 18841, 18841, 18841, 18841, 18841,
        // bins 64- 71: 18841 (1.15×)
        18841, 18841, 18841, 18841, 18841, 18841, 18841, 18841,
        // bins 72- 79: 18841 (1.15×)
        18841, 18841, 18841, 18841, 18841, 18841, 18841, 18841,
        // bins 80- 87: 18841 (1.15×)
        18841, 18841, 18841, 18841, 18841, 18841, 18841, 18841,
        // bins 88- 95: 18841 (1.15×)
        18841, 18841, 18841, 18841, 18841, 18841, 18841, 18841,
        // bins 96-103: 18841 (1.15×)
        18841, 18841, 18841, 18841, 18841, 18841, 18841, 18841,
        // bins 104-111: 18841 (1.15×)
        18841, 18841, 18841, 18841, 18841, 18841, 18841, 18841,
        // bins 112-119: 18841 (1.15×)
        18841, 18841, 18841, 18841, 18841, 18841, 18841, 18841,
        // bins 120-127: 18841 (1.15×)
        18841, 18841, 18841, 18841, 18841, 18841, 18841, 18841
    };

    // -- MODE_HEARING: ski-slope HF emphasis for high-frequency loss ----------
    //   Bins   0-  2: 0.90×  -- mild low-cut to avoid masking
    //   Bins   3- 10: 1.20×  -- upward slope (mild ski-slope loss)
    //   Bins  11- 20: 1.60×  -- consonant / speech-intelligibility boost
    //   Bins  21- 42: 2.00×  -- peak: high-frequency hearing-loss compensation
    //   Bins  43-127: 1.60×  -- gradual descent above 8 kHz
    localparam logic [15:0] GAIN_HEARING [0:127] = '{
        // bins  0-  2: 14746 (0.90×) mild low-cut to avoid masking
        // bins  3-  7: 19661 (1.20×) upward slope (mild ski-slope loss)
        14746, 14746, 14746, 19661, 19661, 19661, 19661, 19661,
        // bins  8- 10: 19661 (1.20×)
        // bins 11- 15: 26214 (1.60×) consonant / speech-intelligibility boost
        19661, 19661, 19661, 26214, 26214, 26214, 26214, 26214,
        // bins 16- 20: 26214 (1.60×)
        // bins 21- 23: 32768 (2.00×) peak: high-frequency hearing-loss comp
        26214, 26214, 26214, 26214, 26214, 32768, 32768, 32768,
        // bins 24- 31: 32768 (2.00×)
        32768, 32768, 32768, 32768, 32768, 32768, 32768, 32768,
        // bins 32- 39: 32768 (2.00×)
        32768, 32768, 32768, 32768, 32768, 32768, 32768, 32768,
        // bins 40- 42: 32768 (2.00×)
        // bins 43- 47: 26214 (1.60×) gradual descent above 8 kHz
        32768, 32768, 32768, 26214, 26214, 26214, 26214, 26214,
        // bins 48- 55: 26214 (1.60×)
        26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214,
        // bins 56- 63: 26214 (1.60×)
        26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214,
        // bins 64- 71: 26214 (1.60×)
        26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214,
        // bins 72- 79: 26214 (1.60×)
        26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214,
        // bins 80- 87: 26214 (1.60×)
        26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214,
        // bins 88- 95: 26214 (1.60×)
        26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214,
        // bins 96-103: 26214 (1.60×)
        26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214,
        // bins 104-111: 26214 (1.60×)
        26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214,
        // bins 112-119: 26214 (1.60×)
        26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214,
        // bins 120-127: 26214 (1.60×)
        26214, 26214, 26214, 26214, 26214, 26214, 26214, 26214
    };

    // -------------------------------------------------------------------------
    // Gain-table lookup
    // -------------------------------------------------------------------------
    // Pure combinational dispatcher: `mode` selects which pre-loaded table to
    // read; `idx` is the bin address.  Synthesis infers a 4:1 mux fronted by
    // four 128-entry LUT-ROMs.  Indices outside [0,127] are not reachable
    // from this design (load_idx is 7 bits) so no bounds check is required.
    function automatic logic [15:0] lookup_gain(
        input logic [1:0] mode,
        input int         idx
    );
        int symmetric_idx;
        // The real-input FFT requires conjugate bins to receive the same
        // real gain. Mirror the upper half of the compact table in hardware
        // so hand-edited tables cannot break Hermitian symmetry.
        symmetric_idx = (idx > 64) ? (128 - idx) : idx;
        case (mode)
            MODE_GENERAL: lookup_gain = GAIN_GENERAL[symmetric_idx];
            MODE_SPEECH:  lookup_gain = GAIN_SPEECH [symmetric_idx];
            MODE_MUSIC:   lookup_gain = GAIN_MUSIC  [symmetric_idx];
            MODE_HEARING: lookup_gain = GAIN_HEARING[symmetric_idx];
            default:      lookup_gain = GAIN_GENERAL[symmetric_idx];
        endcase
    endfunction

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
    logic          initial_load;   // 1-cycle trigger: populate BRAM at boot
    logic [1:0]    load_mode;      // mode associated with the pending table
    logic [1:0]    committed_mode; // mode associated with active_bank

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state              <= ST_IDLE;
            load_idx           <= 7'd0;
            pending_bank       <= 2'd1;   // write to bank B at boot
            active_bank        <= 1'b0;   // bank A live at reset
            bank_we_o          <= 1'b0;
            bank_addr_o        <= 7'd0;
            bank_wdata_o       <= 16'd0;
            bank_sel_o         <= 2'd0;
            bank_commit_o      <= 1'b0;
            initial_load       <= 1'b1;   // schedule first-time GENERAL load
            load_mode          <= MODE_GENERAL;
            committed_mode     <= MODE_GENERAL;
            default_master_gain_o <= 24'd16384;
            default_noise_floor_o <= 24'd4096;
            default_gate_ratio_o  <= 24'd12288;
        end else begin
            // Pulse defaults: keep bank_we_o and bank_commit_o single-cycle.
            bank_we_o     <= 1'b0;
            bank_commit_o <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (initial_load) begin
                        // First-time population: load the GENERAL curve into
                        // the inactive bank so the gain BRAM holds a known,
                        // mode-traceable pattern after FPGA configuration.
                        // `mode_i` is irrelevant here — the GENERAL table is
                        // identical to a flat-unity image, so committing it
                        // produces no audible change vs. the spectral_proc
                        // init defaults while still exercising the FSM.
                        initial_load <= 1'b0;
                        pending_bank <= active_bank ? 2'd0 : 2'd1;  // toggle from A
                        load_mode    <= MODE_GENERAL;
                        load_idx     <= 7'd0;
                        state        <= ST_LOAD;
                    end else if (mode_we_i) begin
                        // Target the inactive bank (toggle LSB).
                        pending_bank <= active_bank ? 2'd0 : 2'd1;
                        load_mode    <= mode_i;
                        load_idx     <= 7'd0;
                        state        <= ST_LOAD;
                    end
                end

                ST_LOAD: begin
                    bank_we_o     <= 1'b1;
                    bank_addr_o   <= load_idx;
                    bank_wdata_o  <= lookup_gain(load_mode, int'(load_idx));
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
                    committed_mode<= load_mode;
                    case (load_mode)
                        MODE_SPEECH: begin
                            default_master_gain_o <= 24'd17203;
                            default_noise_floor_o <= 24'd16384;
                            default_gate_ratio_o  <= 24'd9830;
                        end
                        MODE_MUSIC: begin
                            default_master_gain_o <= 24'd16384;
                            default_noise_floor_o <= 24'd2048;
                            default_gate_ratio_o  <= 24'd13926;
                        end
                        MODE_HEARING: begin
                            default_master_gain_o <= 24'd18022;
                            default_noise_floor_o <= 24'd32768;
                            default_gate_ratio_o  <= 24'd9011;
                        end
                        default: begin
                            default_master_gain_o <= 24'd16384;
                            default_noise_floor_o <= 24'd4096;
                            default_gate_ratio_o  <= 24'd12288;
                        end
                    endcase
                    state         <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Synthesis-time sanity
    // -------------------------------------------------------------------------
    // All four per-mode tables are sized [0:127]; the lookup_gain function
    // relies on that exact width (7-bit index).  Anything else indicates a
    // misconfiguration between this module and auris_pkg.GAIN_TABLE_DEPTH.
    initial begin
        if (N_BINS != 128) $display("WARNING: mode_ctrl N_BINS=%0d, expected 128", N_BINS);
    end

endmodule : mode_ctrl

`default_nettype wire
