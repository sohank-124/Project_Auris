// =============================================================================
// File:        tb_dsp_pipeline.sv
// Project:     Project Auris
// Module:      tb_dsp_pipeline
// Description: Self-checking testbench for the top-level DSP pipeline
//              (dsp_pipeline). Drives a 48 kHz sample stream and verifies:
// =============================================================================
`default_nettype none
`timescale 1ns/1ps

module tb_dsp_pipeline;
    import auris_pkg::*;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic        clk;
    logic        rst_n;

    logic [23:0] sample_l;
    logic [23:0] sample_r;
    logic        sample_valid;

    logic [23:0] out_l;
    logic [23:0] out_r;
    logic        out_valid;

    logic [1:0]  mode;
    logic [23:0] master_gain;
    logic [23:0] noise_floor;
    logic [23:0] gate_ratio;
    logic [6:0]  gain_addr;
    logic [15:0] gain_wdata;
    logic        gain_we;
    logic [1:0]  gain_bank;
    logic        bank_commit;

    logic [23:0] peak_in;
    logic [23:0] peak_out;
    logic [31:0] frame_count;
    logic [7:0]  error_flags;
    logic        clip_event;

    logic        dsp_enable;
    logic [4:0]  volume_level;

    // -------------------------------------------------------------------------
    // DUT instance
    // -------------------------------------------------------------------------
    dsp_pipeline #(.FFT_LEN(256)) dut (
        .clk_i          (clk),
        .rst_n_i        (rst_n),
        .sample_l_i     (sample_l),
        .sample_r_i     (sample_r),
        .sample_valid_i (sample_clk_en),
        .out_l_o        (out_l),
        .out_r_o        (out_r),
        .out_valid_o    (out_valid),
        .mode_i         (mode),
        .master_gain_i  (master_gain),
        .noise_floor_i  (noise_floor),
        .gate_ratio_i   (gate_ratio),
        .dsp_enable_i   (dsp_enable),
        .volume_i       (volume_level),
        .gain_addr_i    (gain_addr),
        .gain_wdata_i   (gain_wdata),
        .gain_we_i      (gain_we),
        .gain_bank_i    (gain_bank),
        .bank_commit_i  (bank_commit),
        .peak_in_o      (peak_in),
        .peak_out_o     (peak_out),
        .frame_count_o  (frame_count),
        .error_flags_o  (error_flags),
        .clip_event_o   (clip_event)
    );

    // -------------------------------------------------------------------------
    // Clock generation: 96 MHz
    // -------------------------------------------------------------------------
    localparam real CLK_HALF = (1000.0/96.0)/2.0;
    initial begin
        clk = 1'b0;
        forever #(CLK_HALF) clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // 48 kHz sample strobe: fires every 2000 DSP cycles, continuously.
    // In real hardware this comes from the I2S LRCLK edge detector and
    // runs forever.  Decoupled from send_sample so the output buffer
    // keeps draining after input injection ends.
    // -------------------------------------------------------------------------
    logic [10:0] sample_div;
    logic        sample_clk_en;

    assign sample_clk_en = rst_n && (sample_div == 11'd1999);

    always_ff @(posedge clk) begin
        if (!rst_n)
            sample_div <= 11'd0;
        else if (sample_div == 11'd1999)
            sample_div <= 11'd0;
        else
            sample_div <= sample_div + 1'b1;
    end

    // -------------------------------------------------------------------------
    // Test tracking
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;
    int total_count = 0;

    // -------------------------------------------------------------------------
    // Task: inject a sample aligned to the continuous sample_clk_en strobe.
    // Places data on sample_l/r one cycle before the strobe fires, so the
    // DUT captures it on the sample_clk_en edge.
    // -------------------------------------------------------------------------
    task automatic send_sample(
        input logic [23:0] left,
        input logic [23:0] right
    );
        // Wait until 1 cycle before the strobe
        while (sample_div != 11'd1998) @(posedge clk);
        @(negedge clk);
        sample_l = left;
        sample_r = right;
        // sample_clk_en fires on the next posedge, capturing the data
        @(posedge clk);   // sample_clk_en = 1 here
        @(negedge clk);
        sample_l = '0;
        sample_r = '0;
    endtask

    // -------------------------------------------------------------------------
    // Task: wait for an output valid pulse, capture the value
    // -------------------------------------------------------------------------
    task automatic wait_output(
        output logic [23:0] out_left,
        output logic [23:0] out_right,
        input  int          timeout_cycles
    );
        int cnt;
        out_left  = '0;
        out_right = '0;
        cnt = 0;
        while (!out_valid && cnt < timeout_cycles) begin
            @(posedge clk);
            cnt++;
        end
        if (out_valid) begin
            out_left  = out_l;
            out_right = out_r;
        end
    endtask

    // -------------------------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_dsp_pipeline.vcd");
        $dumpvars(0, tb_dsp_pipeline);
    end

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [23:0] got_l, got_r;
        int          got_valid;

        // ---- Reset --------------------------------------------------------
        rst_n       = 1'b0;
        sample_l    = '0;
        sample_r    = '0;
        mode        = MODE_HEARING;  // valid mode constant (mode_ctrl is bypassed in this TB)
        master_gain = 24'sd16384;
        noise_floor = 24'sd0;
        gate_ratio  = 24'sd0;
        gain_addr   = '0;
        gain_wdata  = '0;
        gain_we     = 1'b0;
        gain_bank   = 2'd0;
        bank_commit = 1'b0;
        dsp_enable  = 1'b0;
        volume_level = 5'd31;   // unity volume
        repeat (50) @(posedge clk);
        rst_n = 1'b1;
        dsp_enable = 1'b1;           // enable pipeline after reset
        repeat (10) @(posedge clk);

        // =====================================================================
        // Test 1: Active mode — send 200 samples, verify output is produced
        // =====================================================================
        $display("\n=== Test 1: Active mode (200 samples, expect output) ===");
        for (int i = 0; i < 200; i++) begin
            send_sample(24'(1000 + i), 24'(2000 + i));
        end
        // Wait for the pipeline + output buffer to drain
        repeat (150000) @(posedge clk);

        got_valid = 0;
        // Try to capture a few output values
        for (int i = 0; i < 10; i++) begin
            wait_output(got_l, got_r, 5000);
            if (out_valid) got_valid++;
        end

        total_count++;
        if (got_valid > 0) begin
            $display("[PASS] Test1-Active: out_valid_o pulsed %0d times", got_valid);
            pass_count++;
        end else begin
            $display("[FAIL] Test1-Active: out_valid_o never asserted");
            fail_count++;
        end

        // Verify output is not X
        total_count++;
        if (^got_l !== 1'bx && ^got_r !== 1'bx) begin
            $display("[PASS] Test1-NoX: out_l=%h out_r=%h (not X)", got_l, got_r);
            pass_count++;
        end else begin
            $display("[FAIL] Test1-NoX: output is X (got_l=%h got_r=%h)", got_l, got_r);
            fail_count++;
        end

        // =====================================================================
        // Test 2: Frame counter
        // After processing 256+ samples, frame_count_o should be > 0.
        // 200 samples at 50% OLA should produce a few frames.
        // =====================================================================
        $display("\n=== Test 2: Frame counter ===");
        total_count++;
        if (frame_count > 32'd0) begin
            $display("[PASS] Test2-FrameCount: frame_count_o=%0d (> 0)", frame_count);
            pass_count++;
        end else begin
            $display("[FAIL] Test2-FrameCount: frame_count_o=%0d (expected > 0)", frame_count);
            fail_count++;
        end

        // =====================================================================
        // Test 3: Peak meter
        // Send a max-amplitude sample and verify peak_in_o updates.
        // =====================================================================
        $display("\n=== Test 3: Peak meter ===");
        // Send a few max-amplitude samples
        for (int i = 0; i < 10; i++) begin
            send_sample(24'h7FFFFF, 24'h7FFFFF);
        end
        repeat (100) @(posedge clk);

        total_count++;
        if (peak_in >= 24'sd1000000) begin
            $display("[PASS] Test3-PeakIn: peak_in_o=%h (>= 0xF4240)", peak_in);
            pass_count++;
        end else begin
            $display("[FAIL] Test3-PeakIn: peak_in_o=%h (expected large value)", peak_in);
            fail_count++;
        end

        // =====================================================================
        // Summary
        // =====================================================================
        repeat (100) @(posedge clk);
        $display("\n=== tb_dsp_pipeline Summary ===");
        $display("Total: %0d  Pass: %0d  Fail: %0d", total_count, pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog (10 ms — long enough for pipeline + output drain)
    // -------------------------------------------------------------------------
    initial begin
        #10_000_000;
        $display("[%0t] TIMEOUT in tb_dsp_pipeline", $time);
        $finish;
    end

endmodule : tb_dsp_pipeline

`default_nettype wire
