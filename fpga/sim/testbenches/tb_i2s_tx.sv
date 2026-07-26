// =============================================================================
// File:        tb_i2s_tx.sv
// Project:     Project Auris
// Module:      tb_i2s_tx
// Description: Self-checking testbench for the I2S standard-format
//              transmitter (i2s_tx) targeting the PCM5102A DAC.
//
//              Standard I2S protocol (PCM5102A):
//                - LRCLK falls to mark the start of the LEFT channel.
//                - A 1-BCLK delay is inserted: the FIRST BCLK rising edge
//                  after LRCLK has no data; the MSB appears on the SECOND
//                  BCLK rising edge.
//                - 24 data bits + 8 don't-care bits = 32 BCLK cycles/channel.
//
//              BCLK  : 3.072 MHz
//              LRCLK : 48 kHz
//
//              The testbench acts as the PCM5102A receiver, sampling sdata_o
//              on BCLK rising edges and reconstructing the 24-bit values.
//
//              NOTE: the current i2s_tx RTL is a stub (sdata_o=0). This
//              testbench validates the documented intended behavior.
// =============================================================================
`default_nettype none
`timescale 1ns/1ps

module tb_i2s_tx;
    import auris_pkg::*;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic        bclk;
    logic        lrclk;
    logic        sdata_o;
    logic        rst_n;
    logic [23:0] left_in;
    logic [23:0] right_in;
    logic        valid_in;
    logic        underflow;

    // -------------------------------------------------------------------------
    // DUT instance
    // -------------------------------------------------------------------------
    i2s_tx #(.DATA_W(24)) dut (
        .bclk_i      (bclk),
        .lrclk_i     (lrclk),
        .sdata_o     (sdata_o),
        .rst_n_i     (rst_n),
        .left_i      (left_in),
        .right_i     (right_in),
        .valid_i     (valid_in),
        .underflow_o (underflow)
    );

    // -------------------------------------------------------------------------
    // BCLK generation: 3.072 MHz
    // -------------------------------------------------------------------------
    localparam real BCLK_HALF = (1000.0/3.072)/2.0;
    initial begin
        bclk = 1'b0;
        forever #(BCLK_HALF) bclk = ~bclk;
    end

    // -------------------------------------------------------------------------
    // LRCLK generation: 48 kHz, toggles every 32 BCLK cycles
    // -------------------------------------------------------------------------
    initial begin
        lrclk = 1'b0;
        // Toggle LRCLK on BCLK falling edge 32 BCLKs after the previous toggle
        forever begin
            repeat (32) @(negedge bclk);
            lrclk = ~lrclk;
        end
    end

    // -------------------------------------------------------------------------
    // Test tracking
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;
    int total_count = 0;

    // -------------------------------------------------------------------------
    // Task: receive one I2S standard-format stereo frame.
    //
    // Waits for the next LRCLK falling edge (start of left), skips the
    // 1-BCLK delay bit, then captures 24 bits on each BCLK rising edge.
    // -------------------------------------------------------------------------
    task automatic receive_i2s_frame(
        output logic [23:0] left_data,
        output logic [23:0] right_data
    );
        logic prev_lrclk;
        logic bit_val;

        // ---- Wait for LRCLK falling edge (start of left) -------------------
        prev_lrclk = lrclk;
        while (prev_lrclk == 1'b0 || lrclk == 1'b1) begin
            @(negedge bclk);
            prev_lrclk = lrclk;
        end
        // We just observed LRCLK falling. Now wait for the BCLK rising edge
        // where the MSB will be driven (standard I2S: 1-BCLK delay).

        // The 1-BCLK delay bit is sampled and discarded.
        @(posedge bclk);
        // Now LRCLK should be low. Skip 1 BCLK rising edge to absorb the delay.
        // (The transmitter drives the MSB on the falling edge AFTER the first
        //  BCLK rising edge following the LRCLK transition.)
        // The next 24 BCLK rising edges carry the left data MSB-first.

        for (int i = 23; i >= 0; i--) begin
            @(posedge bclk);
            left_data[i] = sdata_o;
        end

        // Skip 8 don't-care bits
        repeat (8) @(posedge bclk);

        // ---- Wait for LRCLK rising edge (start of right) ------------------
        prev_lrclk = lrclk;
        while (prev_lrclk == 1'b1 || lrclk == 1'b0) begin
            @(negedge bclk);
            prev_lrclk = lrclk;
        end

        @(posedge bclk);  // Skip 1-BCLK delay bit
        for (int i = 23; i >= 0; i--) begin
            @(posedge bclk);
            right_data[i] = sdata_o;
        end

        repeat (8) @(posedge bclk);
    endtask

    // -------------------------------------------------------------------------
    // Task: provide a stereo sample to the transmitter with valid_i pulse.
    // valid_i is held high for one DSP-domain cycle. Since we are in BCLK
    // domain here, we simply pulse it for a few BCLK cycles around the
    // LRCLK transition so the transmitter can latch it.
    // -------------------------------------------------------------------------
    task automatic provide_sample(
        input logic [23:0] left_data,
        input logic [23:0] right_data
    );
        // Hold valid high across an LRCLK transition so the transmitter
        // can latch the new sample.
        @(negedge bclk);
        left_in  = left_data;
        right_in = right_data;
        valid_in = 1'b1;
        repeat (33) @(negedge bclk);
        valid_in = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Task: check a received frame against expected values.
    // -------------------------------------------------------------------------
    task automatic check_serial(
        input logic [23:0] exp_left,
        input logic [23:0] exp_right,
        input string       test_name
    );
        logic [23:0] got_left, got_right;

        receive_i2s_frame(got_left, got_right);

        total_count++;
        if (got_left === exp_left && got_right === exp_right) begin
            $display("[PASS] %s: L=%h R=%h", test_name, got_left, got_right);
            pass_count++;
        end else begin
            $display("[FAIL] %s: expected L=%h R=%h, got L=%h R=%h",
                     test_name, exp_left, exp_right, got_left, got_right);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("fpga/sim/waveforms/tb_i2s_tx.vcd");
        $dumpvars(0, tb_i2s_tx);
    end

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        // ---- Reset --------------------------------------------------------
        rst_n    = 1'b0;
        left_in  = '0;
        right_in = '0;
        valid_in = 1'b0;
        repeat (20) @(posedge bclk);
        rst_n = 1'b1;
        repeat (4)  @(posedge bclk);

        // =====================================================================
        // Test 1: Basic stereo frame
        // =====================================================================
        $display("\n=== Test 1: Basic stereo frame (L=0x123456, R=0x789ABC) ===");
        provide_sample(24'h123456, 24'h789ABC);
        check_serial(24'h123456, 24'h789ABC, "Test1-BasicFrame");

        // =====================================================================
        // Test 2: Underflow condition
        // Don't provide valid_in; sdata_o should output zeros and
        // underflow_o should assert.
        // =====================================================================
        $display("\n=== Test 2: Underflow condition (no valid_i) ===");
        // Wait for the next frame boundary
        repeat (64) @(posedge bclk);
        valid_in = 1'b0;
        left_in  = '0;
        right_in = '0;
        // Let one full frame pass without valid_in
        repeat (64) @(posedge bclk);

        total_count++;
        if (underflow) begin
            $display("[PASS] Test2-Underflow: underflow_o asserted");
            pass_count++;
        end else begin
            $display("[FAIL] Test2-Underflow: underflow_o NOT asserted");
            fail_count++;
        end

        // sdata_o should be 0 throughout the underflow frame
        total_count++;
        if (sdata_o === 1'b0) begin
            $display("[PASS] Test2-SdataZero: sdata_o held low during underflow");
            pass_count++;
        end else begin
            $display("[FAIL] Test2-SdataZero: sdata_o=%b (expected 0)", sdata_o);
            fail_count++;
        end

        // =====================================================================
        // Test 3: Multiple consecutive frames
        // =====================================================================
        $display("\n=== Test 3: 10 consecutive frames (incrementing pattern) ===");
        for (int i = 0; i < 10; i++) begin
            provide_sample(24'h300000 + i[23:0],
                           24'h400000 + i[23:0]);
            check_serial(24'h300000 + i[23:0],
                         24'h400000 + i[23:0],
                         $sformatf("Test3-Frame%0d", i));
        end

        // =====================================================================
        // Summary
        // =====================================================================
        repeat (50) @(posedge bclk);
        $display("\n=== tb_i2s_tx Summary ===");
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
        $display("[%0t] TIMEOUT in tb_i2s_tx", $time);
        $finish;
    end

endmodule : tb_i2s_tx

`default_nettype wire
