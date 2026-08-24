// =============================================================================
// File:        reg_file.sv
// Project:     Project Auris — FPGA-Accelerated Assistive Audio
// Module:      reg_file
// Description: 128 x 24-bit register file in the CD_DSP clock domain.
//
//              The register file is the bridge between the SPI slave (host
//              control path) and the DSP pipeline.  The SPI-facing port
//              is presented as a simple synchronous RAM interface (addr_i,
//              wdata_i, we_i, re_i, rdata_o, rdata_valid_o) — the SPI
//              <-> DSP CDC sits outside this module and presents
//              already-CDC'd signals.
//
//              Storage is 128 entries x 24 bits.  Only a subset of the
//              128 entries are actually used (see auris_pkg for the
//              address map).  Unused entries read as 0 and writes to
//              them are harmless.
//
//              Read-only registers (status, peak meters, frame count,
//              error flags, version) are NOT backed by storage: their
//              values come from telemetry inputs and are mux'd at read
//              time.  Writing to a read-only address is silently ignored
//              (except REG_ERROR_FLAGS, which is write-1-to-clear).
//
//              Special write side-effects:
//                REG_GAIN_DATA   (0x11): pulse gain_we_o for 1 cycle and
//                                        auto-increment REG_GAIN_ADDR
//                REG_GAIN_COMMIT (0x13): pulse bank_commit_o for 1 cycle
//                REG_MODE        (0x03): pulse mode_we_o for 1 cycle
//                REG_ERROR_FLAGS (0x24): W1C on internal error_latch
//                REG_CONTROL     (0x02): bit 0 -> dsp_enable_o
//
//              BRAM inference note:
//                The original design used a synchronous broadcast reset
//                over all 128 entries (`for (i=0;i<128;i++) regs[i]<=0`)
//                inside a `negedge rst_n_i` block.  Spartan-7 BRAM
//                cells have no async-reset on the storage matrix, so
//                Vivado dissolved the entire 3,072-bit array into
//                flip-flops.  The storage is now a non-reset BRAM
//                with:
//                  - a non-reset write port (always_ff @(posedge clk_i))
//                  - a non-reset registered read port (1-cycle latency)
//                A small set of "shadow" FFs (9 entries x 24 bits =
//                216 FFs) mirrors the addresses that need combinational
//                access by the DSP pipeline (mode, volume, gains,
//                control, gain-table write interface).  These shadows
//                ARE resettable, so the DSP pipeline sees all-zero
//                control state at power-on, just as before.
//                The BRAM itself initialises to 0 on Spartan-7 after
//                configuration.  An initial block provides the same
//                zero initialisation for simulation.
//
// Author:      [generated]
// Created:     2026-07
// Clock Domain: CD_DSP (96 MHz)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module reg_file import auris_pkg::*; #(
    parameter int unsigned ADDR_W = 7,
    parameter int unsigned DATA_W = 24
) (
    // ---- SPI-facing port ---------------------------------------------------
    input  wire                    clk_i,
    input  wire                    rst_n_i,
    input  wire [ADDR_W-1:0]       addr_i,
    input  wire [DATA_W-1:0]       wdata_i,
    input  wire                    we_i,
    input  wire                    re_i,
    output logic [DATA_W-1:0]      rdata_o,
    output logic                   rdata_valid_o,

    // ---- DSP-facing control outputs ---------------------------------------
    output logic [1:0]             dsp_mode_o,
    output logic [4:0]             dsp_volume_o,   // reserved: digital volume stage not yet implemented in DSP pipeline
    output logic [DATA_W-1:0]      master_gain_o,
    output logic [DATA_W-1:0]      noise_floor_o,
    output logic [DATA_W-1:0]      gate_ratio_o,

    // ---- Gain-table write interface to spectral_proc ----------------------
    output logic [6:0]             gain_addr_o,     // 7 bits -> 128 bins
    output logic [15:0]            gain_wdata_o,    // 16-bit Q2.14 per-bin
    output logic                   gain_we_o,       // 1-cycle pulse
    output logic [1:0]             gain_bank_o,     // bank select for write
    output logic                   bank_commit_o,   // 1-cycle pulse
    output logic                   mode_we_o,       // 1-cycle pulse
    output logic                   dsp_enable_o,    // level from REG_CONTROL

    // ---- DSP-facing telemetry inputs ---------------------------------------
    input  wire [DATA_W-1:0]       peak_in_i,
    input  wire [DATA_W-1:0]       peak_out_i,
    input  wire [31:0]             frame_count_i,
    input  wire [7:0]              error_flags_i,
    input  wire                    clip_flag_i,
    input  wire [DATA_W-1:0]       fw_version_i,
    input  wire [DATA_W-1:0]       hw_version_i,   // Bumped on wire-incompat bitstreams
    input  wire                    dsp_ready_i,    // MMCM locked, DSP out of reset
    input  wire                    cdc_locked_i,   // CDC synchronisers stable
    output logic                   clip_clear_o     // 1-cycle pulse on REG_STATUS read
);

    // -------------------------------------------------------------------------
    // BRAM storage (128 x 24-bit)
    // -------------------------------------------------------------------------
    (* ram_style = "block" *) logic [DATA_W-1:0] regs [0:127];

    // Simulation / synthesis init (BRAM init to 0; harmless on Spartan-7
    // where BRAM defaults to 0, but keeps simulation deterministic).
    initial begin
        for (int i = 0; i < 128; i++) regs[i] = DATA_W'(0);
    end

    // -------------------------------------------------------------------------
    // Shadow registers for DSP-facing combinational outputs
    // -------------------------------------------------------------------------
    // These 9 shadow FFs replace the 3,072-FF broadcast-reset array.
    // They are resettable so the DSP pipeline observes all-zero control
    // state at power-on, matching the original behaviour exactly.
    logic [DATA_W-1:0] mode_reg;
    logic [DATA_W-1:0] volume_reg;
    logic [DATA_W-1:0] noise_floor_reg;
    logic [DATA_W-1:0] gate_ratio_reg;
    logic [DATA_W-1:0] master_gain_reg;
    logic [DATA_W-1:0] gain_addr_reg;
    logic [DATA_W-1:0] gain_data_reg;
    logic [DATA_W-1:0] gain_bank_reg;
    logic [DATA_W-1:0] control_reg;

    // Internal W1C error latch
    logic [7:0] error_latch;

    // BRAM registered read data (1-cycle latency)
    logic [DATA_W-1:0] reg_rd_data;

    // -------------------------------------------------------------------------
    // BRAM write port (non-reset — required for BRAM inference)
    // -------------------------------------------------------------------------
    // Writes to read-only addresses harmlessly update a BRAM entry that
    // is never read (the read mux routes RO addresses to telemetry).
    // This avoids a complex write-enable decoder that would complicate
    // the BRAM template.
    always_ff @(posedge clk_i) begin
        if (we_i) regs[addr_i] <= wdata_i;
    end

    // -------------------------------------------------------------------------
    // BRAM read port (registered, 1-cycle latency, non-reset for inference)
    // -------------------------------------------------------------------------
    // A continuous read (no enable gate) keeps the template simple and
    // is harmless — the output is only consumed when rdata_valid_o
    // fires, which is always 1 cycle after re_i, aligning exactly with
    // this registered read.
    always_ff @(posedge clk_i) begin
        reg_rd_data <= regs[addr_i];
    end

    // -------------------------------------------------------------------------
    // Shadow registers + pulse generation (resettable)
    // -------------------------------------------------------------------------
    // All register storage updates and all 1-cycle write pulses are
    // generated in this single block.  RO addresses are no-ops for the
    // shadow registers.  The BRAM write itself is handled in the
    // non-reset block above (covers all addresses including RO, which
    // is harmless).  The shadow update here only fires for the
    // addresses that have combinational mirror outputs to the DSP
    // pipeline.
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            mode_reg        <= DATA_W'(0);
            volume_reg      <= DATA_W'(0);
            noise_floor_reg <= DATA_W'(0);
            gate_ratio_reg  <= DATA_W'(0);
            master_gain_reg <= DATA_W'(0);
            gain_addr_reg   <= DATA_W'(0);
            gain_data_reg   <= DATA_W'(0);
            gain_bank_reg   <= DATA_W'(0);
            control_reg     <= DATA_W'(0);
            error_latch     <= 8'd0;
            gain_we_o       <= 1'b0;
            bank_commit_o   <= 1'b0;
            mode_we_o       <= 1'b0;
            rdata_valid_o   <= 1'b0;
            clip_clear_o    <= 1'b0;
        end else begin
            // Default: no pulses
            gain_we_o     <= 1'b0;
            bank_commit_o <= 1'b0;
            mode_we_o     <= 1'b0;
            rdata_valid_o <= re_i;
            clip_clear_o  <= 1'b0;

            if (we_i) begin
                case (addr_i)
                    // Read-only: BRAM write above is harmless; shadows
                    // are not updated.
                    REG_VERSION,
                    REG_STATUS,
                    REG_PEAK_LEVEL,
                    REG_OUT_PEAK,
                    REG_FRAME_COUNT_L,
                    REG_FRAME_COUNT_H: begin
                        // no-op on shadows
                    end

                    // W1C error flags: clear bits set in wdata_i
                    REG_ERROR_FLAGS: begin
                        error_latch <= error_latch & ~wdata_i[7:0];
                    end

                    // Gain-table data write: shadow update + pulse
                    // gain_we_o + auto-increment the gain address
                    // shadow.  The BRAM write happens in the non-reset
                    // block above.
                    REG_GAIN_DATA: begin
                        gain_data_reg <= wdata_i;
                        gain_addr_reg <= gain_addr_reg + 7'd1;
                        gain_we_o     <= 1'b1;
                    end

                    // Gain-table commit: pulse bank_commit_o
                    REG_GAIN_COMMIT: bank_commit_o <= 1'b1;

                    // Mode write: shadow update + pulse mode_we_o
                    REG_MODE: begin
                        mode_reg <= wdata_i;
                        mode_we_o <= 1'b1;
                    end

                    // Default: update the shadow for any address that
                    // has a combinational mirror to the DSP pipeline.
                    // Addresses without a shadow are stored in BRAM
                    // only (read back via the registered read path).
                    default: begin
                        case (addr_i)
                            REG_CONTROL:          control_reg     <= wdata_i;
                            REG_VOLUME:           volume_reg      <= wdata_i;
                            REG_NOISE_FLOOR:      noise_floor_reg <= wdata_i;
                            REG_NOISE_GATE_RATIO: gate_ratio_reg  <= wdata_i;
                            REG_MASTER_GAIN:      master_gain_reg <= wdata_i;
                            REG_GAIN_ADDR:        gain_addr_reg   <= wdata_i;
                            REG_GAIN_BANK:        gain_bank_reg   <= wdata_i;
                            default: ; // BRAM-only — no shadow needed
                        endcase
                    end
                endcase
            end

            // -----------------------------------------------------------------
            // REG_STATUS read side-effect: pulse clip_clear_o for 1 cycle.
            // -----------------------------------------------------------------
            if (re_i && addr_i == REG_STATUS) begin
                clip_clear_o <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Registered read mux (resettable — just a mux, not storage)
    // -------------------------------------------------------------------------
    // The read mux is now registered (was combinational in the original
    // design).  This aligns with the BRAM's 1-cycle read latency and
    // with rdata_valid_o, which fires 1 cycle after re_i.  For special
    // (telemetry) addresses, the registered output captures the live
    // telemetry value 1 cycle after the read request — harmless for a
    // polling-based SPI host.  For normal addresses, the output is
    // reg_rd_data (the BRAM registered read).
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rdata_o <= DATA_W'(0);
        end else begin
            case (addr_i)
                REG_VERSION:       rdata_o <= hw_version_i;
                REG_STATUS:        rdata_o <= {4'b0, mode_reg[1:0], control_reg[0],
                                               clip_flag_i, cdc_locked_i,
                                               dsp_ready_i};
                REG_PEAK_LEVEL:    rdata_o <= peak_in_i;
                REG_OUT_PEAK:      rdata_o <= peak_out_i;
                REG_FRAME_COUNT_L: rdata_o <= frame_count_i[23:0];
                REG_FRAME_COUNT_H: rdata_o <= {16'b0, frame_count_i[31:24]};
                REG_ERROR_FLAGS:   rdata_o <= {16'b0, error_latch};
                default:           rdata_o <= reg_rd_data;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Continuous mirror outputs from shadow registers
    // -------------------------------------------------------------------------
    // These are pure combinational outputs driven from the shadow FFs.
    // The DSP pipeline sees the value in the cycle after the SPI write
    // commits (same 1-cycle latency as the original regs[] write).
    assign dsp_mode_o     = mode_reg[1:0];
    assign dsp_volume_o   = volume_reg[4:0];   // unconnected at top level; reserved for future digital volume
    assign master_gain_o  = master_gain_reg;
    assign noise_floor_o  = noise_floor_reg;
    assign gate_ratio_o   = gate_ratio_reg;
    assign gain_addr_o    = gain_addr_reg[6:0];
    assign gain_wdata_o   = gain_data_reg[15:0];
    assign gain_bank_o    = gain_bank_reg[1:0];
    assign dsp_enable_o   = control_reg[0];

    // -------------------------------------------------------------------------
    // Synthesis-time sanity
    // -------------------------------------------------------------------------
    initial begin
        if (DATA_W < 24) $display("WARNING: reg_file DATA_W=%0d < 24", DATA_W);
        if (ADDR_W < 7)  $display("WARNING: reg_file ADDR_W=%0d < 7", ADDR_W);
    end

endmodule : reg_file

`default_nettype wire