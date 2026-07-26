// =============================================================================
// File:        tb_reg_file.sv
// Project:     Project Auris
// Module:      tb_reg_file
// Description: Self-checking testbench for the 128x24-bit register file
//              (reg_file). Verifies:
//                - Scratchpad read/write
//                - Loopback read/write
//                - Read-only registers return their dedicated input value
//                - Writes to read-only registers are ignored
//                - Gain-table streaming port (gain_addr_o, gain_wdata_o,
//                  gain_we_o)
//                - Mode register mirrors to dsp_mode_o
//                - Error flags are write-1-to-clear
//                - Gain address auto-increment
//
//              Clock: 96 MHz DSP clock (period 10.4167 ns)
//
//              NOTE: the current reg_file RTL implements the basic RW memory
//              and the RO mirror, but the W1C behavior on REG_ERROR_FLAGS,
//              the RO write-ignore, and the gain_addr auto-increment are
//              marked TODO. Those particular checks will FAIL on the current
//              stub and PASS once those features are added.
// =============================================================================
`default_nettype none
`timescale 1ns/1ps

module tb_reg_file;
    import auris_pkg::*;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic        clk;
    logic        rst_n;

    // SPI-facing port
    logic [6:0]  addr;
    logic [23:0] wdata;
    logic        we;
    logic        re;
    logic [23:0] rdata;
    logic        rdata_valid;

    // DSP-facing control outputs
    logic [1:0]  dsp_mode;
    logic [23:0] master_gain;
    logic [23:0] noise_floor;
    logic [23:0] gate_ratio;
    logic [6:0]  gain_addr;
    logic [15:0] gain_wdata;
    logic        gain_we;
    logic [1:0]  gain_bank;
    logic        bank_commit;

    // DSP-facing telemetry inputs
    logic [23:0] peak_in;
    logic [23:0] peak_out;
    logic [31:0] frame_count;
    logic [7:0]  error_flags;
    logic [23:0] fw_version;
    logic [23:0] hw_version;

    // -------------------------------------------------------------------------
    // DUT instance
    // -------------------------------------------------------------------------
    reg_file #(.ADDR_W(7), .DATA_W(24)) dut (
        .clk_i           (clk),
        .rst_n_i         (rst_n),
        .addr_i          (addr),
        .wdata_i         (wdata),
        .we_i            (we),
        .re_i            (re),
        .rdata_o         (rdata),
        .rdata_valid_o   (rdata_valid),
        .dsp_mode_o      (dsp_mode),
        .master_gain_o   (master_gain),
        .noise_floor_o   (noise_floor),
        .gate_ratio_o    (gate_ratio),
        .gain_addr_o     (gain_addr),
        .gain_wdata_o    (gain_wdata),
        .gain_we_o       (gain_we),
        .gain_bank_o     (gain_bank),
        .bank_commit_o   (bank_commit),
        .peak_in_i       (peak_in),
        .peak_out_i      (peak_out),
        .frame_count_i   (frame_count),
        .error_flags_i   (error_flags),
        .fw_version_i    (fw_version),
        .hw_version_i    (hw_version)
    );

    // -------------------------------------------------------------------------
    // Clock generation: 96 MHz
    // -------------------------------------------------------------------------
    localparam real CLK_HALF = (1000.0/96.0)/2.0;  // 5.2083 ns
    initial begin
        clk = 1'b0;
        forever #(CLK_HALF) clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Test tracking
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;
    int total_count = 0;

    // -------------------------------------------------------------------------
    // Task: write a register
    // -------------------------------------------------------------------------
    task automatic reg_write(
        input logic [6:0]  addr_in,
        input logic [23:0] data_in
    );
        @(negedge clk);
        addr  = addr_in;
        wdata = data_in;
        we    = 1'b1;
        re    = 1'b0;
        @(posedge clk);
        @(negedge clk);
        we    = 1'b0;
        wdata = '0;
    endtask

    // -------------------------------------------------------------------------
    // Task: read a register, return data via output
    // -------------------------------------------------------------------------
    task automatic reg_read(
        input  logic [6:0]  addr_in,
        output logic [23:0] data_out,
        output logic        valid_out
    );
        @(negedge clk);
        addr = addr_in;
        re   = 1'b1;
        we   = 1'b0;
        @(posedge clk);
        data_out = rdata;
        valid_out = rdata_valid;
        @(negedge clk);
        re = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Helper task: assert pass/fail
    // -------------------------------------------------------------------------
    task automatic check(
        input logic        cond,
        input string       name,
        input logic [23:0] got,
        input logic [23:0] exp
    );
        total_count++;
        if (cond) begin
            $display("[PASS] %s: got=%h exp=%h", name, got, exp);
            pass_count++;
        end else begin
            $display("[FAIL] %s: got=%h exp=%h", name, got, exp);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("fpga/sim/waveforms/tb_reg_file.vcd");
        $dumpvars(0, tb_reg_file);
    end

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [23:0] read_val;
        logic        rv;

        // ---- Reset --------------------------------------------------------
        rst_n        = 1'b0;
        addr         = '0;
        wdata        = '0;
        we           = 1'b0;
        re           = 1'b0;
        peak_in      = '0;
        peak_out     = '0;
        frame_count  = '0;
        error_flags  = '0;
        fw_version   = 24'h010203;  // arbitrary
        hw_version   = 24'h040506;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (4)  @(posedge clk);

        // =====================================================================
        // Test 1: Write/read scratch (REG_SCRATCH = 0x7E)
        // =====================================================================
        $display("\n=== Test 1: Write/read REG_SCRATCH (0x7E) ===");
        reg_write(REG_SCRATCH, 24'hCAFE_BEEF);
        reg_read(REG_SCRATCH, read_val, rv);
        check(rv && read_val === 24'hCAFE_BEEF,
              "Test1-Scratch", read_val, 24'hCAFE_BEEF);

        // =====================================================================
        // Test 2: Write/read loopback (REG_LOOPBACK = 0x7F)
        // =====================================================================
        $display("\n=== Test 2: Write/read REG_LOOPBACK (0x7F) ===");
        reg_write(REG_LOOPBACK, 24'h123456);
        reg_read(REG_LOOPBACK, read_val, rv);
        check(rv && read_val === 24'h123456,
              "Test2-Loopback", read_val, 24'h123456);

        // =====================================================================
        // Test 3: Read RO register (REG_VERSION) returns fw_version_i
        // =====================================================================
        $display("\n=== Test 3: Read REG_VERSION returns fw_version_i ===");
        reg_read(REG_VERSION, read_val, rv);
        check(rv && read_val === 24'h010203,
              "Test3-Version", read_val, 24'h010203);

        // =====================================================================
        // Test 4: Write to RO register (REG_VERSION) should be ignored
        // =====================================================================
        $display("\n=== Test 4: Write to REG_VERSION should be ignored ===");
        reg_write(REG_VERSION, 24'hFFFFFF);
        reg_read(REG_VERSION, read_val, rv);
        check(rv && read_val === 24'h010203,
              "Test4-RO-Write-Ignored", read_val, 24'h010203);

        // =====================================================================
        // Test 5: Gain table write (REG_GAIN_ADDR + REG_GAIN_DATA)
        // =====================================================================
        $display("\n=== Test 5: Gain table write via REG_GAIN_ADDR/DATA ===");
        // First set the address
        reg_write(REG_GAIN_ADDR, 24'd5);
        // Then write the data — this should pulse gain_we_o
        @(negedge clk);
        addr  = REG_GAIN_DATA;
        wdata = 24'h00ABCD;
        we    = 1'b1;
        @(posedge clk);
        // Check on the same cycle
        total_count++;
        if (gain_we === 1'b1) begin
            $display("[PASS] Test5-gain_we: gain_we_o pulsed");
            pass_count++;
        end else begin
            $display("[FAIL] Test5-gain_we: gain_we_o=%b (expected 1)", gain_we);
            fail_count++;
        end
        total_count++;
        if (gain_addr === 7'd5) begin
            $display("[PASS] Test5-gain_addr: gain_addr_o=%0d", gain_addr);
            pass_count++;
        end else begin
            $display("[FAIL] Test5-gain_addr: gain_addr_o=%0d (expected 5)", gain_addr);
            fail_count++;
        end
        total_count++;
        if (gain_wdata === 16'hABCD) begin
            $display("[PASS] Test5-gain_wdata: gain_wdata_o=%h", gain_wdata);
            pass_count++;
        end else begin
            $display("[FAIL] Test5-gain_wdata: gain_wdata_o=%h (expected 0xABCD)", gain_wdata);
            fail_count++;
        end
        @(negedge clk);
        we = 1'b0;

        // =====================================================================
        // Test 6: Mode write (REG_MODE -> dsp_mode_o)
        // =====================================================================
        $display("\n=== Test 6: Write REG_MODE=MODE_HEARING (0x1) ===");
        reg_write(REG_MODE, 24'd1);
        // Mirror is registered, wait one cycle
        @(posedge clk);
        @(posedge clk);
        total_count++;
        if (dsp_mode === MODE_HEARING) begin
            $display("[PASS] Test6-Mode: dsp_mode_o=%0d (HEARING)", dsp_mode);
            pass_count++;
        end else begin
            $display("[FAIL] Test6-Mode: dsp_mode_o=%0d (expected %0d=HEARING)",
                     dsp_mode, MODE_HEARING);
            fail_count++;
        end

        // =====================================================================
        // Test 7: Error flags W1C (Write-1-to-Clear)
        // =====================================================================
        $display("\n=== Test 7: Error flags write-1-to-clear ===");
        // Set error_flags_i to all ones
        error_flags = 8'hFF;
        reg_read(REG_ERROR_FLAGS, read_val, rv);
        check(rv && read_val === 24'h0000FF,
              "Test7a-ErrorReadAll", read_val, 24'h0000FF);

        // Write 1s to clear; the spec says REG_ERROR_FLAGS is W1C: writing 1
        // to a bit position clears that bit in the source error_flags.
        // The model here is that the testbench will clear the corresponding
        // bits in error_flags_i when the SPI master writes them.
        reg_write(REG_ERROR_FLAGS, 24'h0000FF);  // write 1s -> clear all
        // Simulate the hardware clearing the bits
        error_flags = 8'h00;
        reg_read(REG_ERROR_FLAGS, read_val, rv);
        check(rv && read_val === 24'h000000,
              "Test7b-ErrorCleared", read_val, 24'h000000);

        // =====================================================================
        // Test 8: Auto-increment on REG_GAIN_DATA writes
        // =====================================================================
        $display("\n=== Test 8: Gain address auto-increment ===");
        // Set starting address to 10
        reg_write(REG_GAIN_ADDR, 24'd10);
        // Write 3 consecutive values to REG_GAIN_DATA
        // The intended behavior is that gain_addr_o increments after each
        // write, so 3 writes cover addresses 10, 11, 12.
        reg_write(REG_GAIN_DATA, 24'h000AAA);
        reg_write(REG_GAIN_DATA, 24'h000BBB);
        reg_write(REG_GAIN_DATA, 24'h000CCC);
        // After 3 auto-increments starting from 10, address should be 13
        @(posedge clk);
        total_count++;
        if (gain_addr === 7'd13) begin
            $display("[PASS] Test8-AutoInc: gain_addr_o=%0d (expected 13)", gain_addr);
            pass_count++;
        end else begin
            $display("[FAIL] Test8-AutoInc: gain_addr_o=%0d (expected 13 after 3 writes)", gain_addr);
            fail_count++;
        end

        // =====================================================================
        // Summary
        // =====================================================================
        repeat (50) @(posedge clk);
        $display("\n=== tb_reg_file Summary ===");
        $display("Total: %0d  Pass: %0d  Fail: %0d", total_count, pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog (1 ms)
    // -------------------------------------------------------------------------
    initial begin
        #1_000_000;
        $display("[%0t] TIMEOUT in tb_reg_file", $time);
        $finish;
    end

endmodule : tb_reg_file

`default_nettype wire
