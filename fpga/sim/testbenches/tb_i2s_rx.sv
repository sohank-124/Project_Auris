// =============================================================================
// File:        tb_i2s_rx.sv
// Project:     Project Auris
// Module:      tb_i2s_rx
// Description: Self-checking testbench for the I2S left-justified receiver
//              (i2s_rx). Drives deterministic INMP441-style frames (MSB on
//              the first BCLK rising edge after the LRCLK transition, no
//              1-BCLK delay) and verifies that the captured left/right
//              samples match the transmitted values.
//
//              BCLK  : 3.072 MHz (period 325.5208 ns)
//              LRCLK : 48 kHz   (toggles every 32 BCLK cycles)
//              Data  : 24-bit, left-justified, 8 don't-care bits/channel
//
//              Run from Vivado:
//                  launch_simulation -simulator xsim
//              or from xsim directly:
//                  xsim tb_i2s_rx
//
//              NOTE: the current i2s_rx RTL is a stub (outputs tied to 0).
//              This testbench validates the documented intended behavior;
//              it will FAIL on the current stub and PASS once the RTL is
//              implemented per the TODO comments in i2s_rx.sv.
// =============================================================================
`default_nettype none
`timescale 1ns/1ps

module tb_i2s_rx;
    import auris_pkg::*;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic        bclk;
    logic        lrclk;
    logic        sdata;
    logic        rst_n;
    logic [23:0] left_out;
    logic [23:0] right_out;
    logic        valid;
    logic        overflow;

    // -------------------------------------------------------------------------
    // DUT instance
    // -------------------------------------------------------------------------
    i2s_rx #(.DATA_W(24)) dut (
        .bclk_i     (bclk),
        .lrclk_i    (lrclk),
        .sdata_i    (sdata),
        .rst_n_i    (rst_n),
        .left_o     (left_out),
        .right_o    (right_out),
        .valid_o    (valid),
        .overflow_o (overflow)
    );

    // -------------------------------------------------------------------------
    // BCLK generation: 3.072 MHz
    // -------------------------------------------------------------------------
    localparam real BCLK_HALF = (1000.0/3.072)/2.0;  // 162.7604 ns
    initial begin
        bclk = 1'b0;
        forever #(BCLK_HALF) bclk = ~bclk;
    end

    // -------------------------------------------------------------------------
    // Test tracking
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;
    int total_count = 0;

    // -------------------------------------------------------------------------
    // Task: send one complete I2S left-justified stereo frame.
    //
    // Left-justified protocol (INMP441):
    //   - LRCLK falls to mark the start of the LEFT channel.
    //   - The MSB of the left sample is valid on the FIRST BCLK rising edge
    //     after the LRCLK transition (no 1-BCLK delay).
    //   - Subsequent bits are clocked on each subsequent BCLK rising edge.
    //   - 24 data bits + 8 don't-care bits = 32 BCLK cycles per channel.
    //   - LRCLK rises to mark the start of the RIGHT channel (same protocol).
    //
    // The transmitter (INMP441) drives SDATA on the BCLK falling edge, so the
    // testbench updates sdata on every negedge so the value is stable by the
    // next posedge when the receiver samples it.
    // -------------------------------------------------------------------------
    task automatic send_i2s_frame(
        input logic [23:0] left_data,
        input logic [23:0] right_data
    );
        // ---- Start of LEFT channel ----------------------------------------
        @(negedge bclk);
        lrclk = 1'b0;          // LRCLK falls -> left channel
        sdata = left_data[23]; // MSB stable for upcoming rising edge

        // Drive remaining 23 bits MSB-first
        for (int i = 22; i >= 0; i--) begin
            @(negedge bclk);
            sdata = left_data[i];
        end

        // 8 don't-care bits
        for (int i = 0; i < 8; i++) begin
            @(negedge bclk);
            sdata = 1'b0;
        end

        // ---- Start of RIGHT channel ---------------------------------------
        @(negedge bclk);
        lrclk = 1'b1;           // LRCLK rises -> right channel
        sdata = right_data[23];

        for (int i = 22; i >= 0; i--) begin
            @(negedge bclk);
            sdata = right_data[i];
        end

        for (int i = 0; i < 8; i++) begin
            @(negedge bclk);
            sdata = 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: wait for valid_o pulse and compare captured values to expected.
    // Returns 1 on match, 0 on mismatch.
    // -------------------------------------------------------------------------
    task automatic check_output(
        input logic [23:0] exp_left,
        input logic [23:0] exp_right,
        input string       test_name,
        output logic       matched
    );
        logic [23:0] got_left, got_right;
        int timeout_cycles;

        matched = 1'b0;
        timeout_cycles = 0;

        // Wait up to 200 BCLK cycles for valid_o to assert.
        while (!valid && timeout_cycles < 200) begin
            @(posedge bclk);
            timeout_cycles++;
        end

        if (!valid) begin
            $display("[FAIL] %s: timeout waiting for valid_o (exp L=%h R=%h)",
                     test_name, exp_left, exp_right);
            fail_count++;
            total_count++;
            return;
        end

        // Capture values on the cycle valid_o is high.
        got_left  = left_out;
        got_right = right_out;

        total_count++;
        if (got_left === exp_left && got_right === exp_right) begin
            $display("[PASS] %s: L=%h R=%h", test_name, got_left, got_right);
            pass_count++;
            matched = 1'b1;
        end else begin
            $display("[FAIL] %s: expected L=%h R=%h, got L=%h R=%h",
                     test_name, exp_left, exp_right, got_left, got_right);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // VCD waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("fpga/sim/waveforms/tb_i2s_rx.vcd");
        $dumpvars(0, tb_i2s_rx);
    end

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic matched;

        // ---- Reset --------------------------------------------------------
        rst_n = 1'b0;
        lrclk = 1'b0;
        sdata = 1'b0;
        repeat (20) @(posedge bclk);
        rst_n = 1'b1;
        repeat (4)  @(posedge bclk);

        // =====================================================================
        // Test 1: Basic stereo frame with known data
        // =====================================================================
        $display("\n=== Test 1: Basic stereo frame (L=0x123456, R=0x789ABC) ===");
        send_i2s_frame(24'h123456, 24'h789ABC);
        check_output(24'h123456, 24'h789ABC, "Test1-BasicFrame", matched);

        // =====================================================================
        // Test 2: Multiple consecutive frames
        // =====================================================================
        $display("\n=== Test 2: 10 consecutive frames (incrementing pattern) ===");
        for (int i = 0; i < 10; i++) begin
            send_i2s_frame(24'h100000 + i[23:0],
                           24'h200000 + i[23:0]);
        end
        for (int i = 0; i < 10; i++) begin
            check_output(24'h100000 + i[23:0],
                         24'h200000 + i[23:0],
                         $sformatf("Test2-Frame%0d", i),
                         matched);
        end

        // =====================================================================
        // Test 3: Overflow condition
        // Send 4 frames back-to-back without reading valid_o, then check
        // that overflow_o asserts.
        // =====================================================================
        $display("\n=== Test 3: Overflow condition (no reads for 4 frames) ===");
        // Allow the previous test's last valid_o to drain.
        repeat (100) @(posedge bclk);

        for (int i = 0; i < 4; i++) begin
            send_i2s_frame(24'hAA0000 + i[23:0],
                           24'hBB0000 + i[23:0]);
        end

        // Wait for the RTL to react
        repeat (200) @(posedge bclk);

        total_count++;
        if (overflow) begin
            $display("[PASS] Test3-Overflow: overflow_o asserted after 4 un-consumed frames");
            pass_count++;
        end else begin
            $display("[FAIL] Test3-Overflow: overflow_o NOT asserted (expected=1, got=0)");
            fail_count++;
        end

        // Drain the overflowed state
        for (int i = 0; i < 4; i++) begin
            check_output('x, 'x, $sformatf("Test3-Drain%0d", i), matched);
        end

        // =====================================================================
        // Summary
        // =====================================================================
        repeat (50) @(posedge bclk);
        $display("\n=== tb_i2s_rx Summary ===");
        $display("Total: %0d  Pass: %0d  Fail: %0d", total_count, pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog (5 ms)
    // -------------------------------------------------------------------------
    initial begin
        #5_000_000;
        $display("[%0t] TIMEOUT in tb_i2s_rx", $time);
        $finish;
    end

endmodule : tb_i2s_rx

`default_nettype wire
