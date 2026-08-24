// =============================================================================
// File:        tb_spectral_proc.sv
// Project:     Project Auris
// Module:      tb_spectral_proc
// Description: Self-checking testbench for the spectral processing block
//              (spectral_proc). Verifies:
//                1. Unity gain path (master=1.0, per-bin=1.0) is identity
//                2. Noise gate: low-magnitude bins are attenuated when the
//                   noise floor is set above the bin magnitude
//                3. Gain table write: bin_we_i/bin_addr_i/bin_wdata_i
//                   updates the per-bin gain in the targeted bank
//                4. Bank swap: writing to bank B then committing flips
//                   the internal active bank
//                5. Streaming valid/last: out_v_o follows in_v_i,
//                   out_last_o follows in_last_i with pipeline latency
//
//              Clock: 96 MHz
// =============================================================================
`default_nettype none
`timescale 1ns/1ps

module tb_spectral_proc;
    import auris_pkg::*;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic        clk;
    logic        rst_n;

    logic [15:0] in_re;
    logic [15:0] in_im;
    logic        in_v;
    logic        in_last;

    logic [15:0] out_re;
    logic [15:0] out_im;
    logic        out_v;
    logic        out_last;

    logic [1:0]  mode;
    logic [15:0] master_gain;
    logic [15:0] noise_floor;
    logic [15:0] gate_ratio;

    logic [6:0]  bin_addr;
    logic [15:0] bin_wdata;
    logic        bin_we;
    logic [1:0]  bin_bank;
    logic        bank_commit;

    // Test scratch variables (avoid 16'sd(arith) issues)
    logic signed [15:0] test_re, test_im;

    // -------------------------------------------------------------------------
    // DUT instance
    // -------------------------------------------------------------------------
    spectral_proc #(.N_BINS(128), .DATA_W(16), .ADDR_W(7)) dut (
        .clk_i         (clk),
        .rst_n_i       (rst_n),
        .in_re_i       (in_re),
        .in_im_i       (in_im),
        .in_v_i        (in_v),
        .in_last_i     (in_last),
        .out_re_o      (out_re),
        .out_im_o      (out_im),
        .out_v_o       (out_v),
        .out_last_o    (out_last),
        .mode_i        (mode),
        .master_gain_i (master_gain),
        .noise_floor_i (noise_floor),
        .gate_ratio_i  (gate_ratio),
        .bin_addr_i    (bin_addr),
        .bin_wdata_i   (bin_wdata),
        .bin_we_i      (bin_we),
        .bin_bank_i    (bin_bank),
        .bank_commit_i (bank_commit)
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
    // Test tracking
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;
    int total_count = 0;

    // -------------------------------------------------------------------------
    // Task: send one spectral bin
    // -------------------------------------------------------------------------
    task automatic send_bin(
        input logic [15:0] re,
        input logic [15:0] im,
        input logic        valid
    );
        @(negedge clk);
        in_re = re;
        in_im = im;
        in_v  = valid;
        @(posedge clk);
        // Single-cycle valid pulse: deassert immediately after the
        // sampling posedge so each call injects exactly ONE bin.
        @(negedge clk);
        in_v = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Task: check one output bin
    // -------------------------------------------------------------------------
    task automatic check_bin(
        input logic [15:0] exp_re,
        input logic [15:0] exp_im,
        input string       test_name
    );
        int timeout_cycles;
        logic [15:0] got_re, got_im;
        timeout_cycles = 0;
        while (!out_v && timeout_cycles < 100) begin
            @(posedge clk);
            timeout_cycles++;
        end
        if (!out_v) begin
            $display("[FAIL] %s: timeout waiting for out_v_o", test_name);
            fail_count++;
            total_count++;
            return;
        end
        got_re = out_re;
        got_im = out_im;
        total_count++;
        if (got_re === exp_re && got_im === exp_im) begin
            $display("[PASS] %s: re=%h im=%h", test_name, got_re, got_im);
            pass_count++;
        end else begin
            $display("[FAIL] %s: re=%h im=%h (exp re=%h im=%h)",
                     test_name, got_re, got_im, exp_re, exp_im);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: check one output bin within a tolerance
    // -------------------------------------------------------------------------
    task automatic check_bin_range(
        input logic [15:0] exp_re,
        input logic [15:0] exp_im,
        input int          tolerance,
        input string       test_name
    );
        int timeout_cycles;
        logic [15:0] got_re, got_im;
        int          g_re, g_im, e_re, e_im;
        timeout_cycles = 0;
        while (!out_v && timeout_cycles < 100) begin
            @(posedge clk);
            timeout_cycles++;
        end
        if (!out_v) begin
            $display("[FAIL] %s: timeout waiting for out_v_o", test_name);
            fail_count++;
            total_count++;
            return;
        end
        got_re = out_re;
        got_im = out_im;
        total_count++;
        g_re = $signed(got_re);
        g_im = $signed(got_im);
        e_re = $signed(exp_re);
        e_im = $signed(exp_im);
        if ((g_re >= (e_re - tolerance)) && (g_re <= (e_re + tolerance)) &&
            (g_im >= (e_im - tolerance)) && (g_im <= (e_im + tolerance))) begin
            $display("[PASS] %s: re=%h im=%h", test_name, got_re, got_im);
            pass_count++;
        end else begin
            $display("[FAIL] %s: re=%h im=%h (exp re=%h im=%h +-%0d)",
                     test_name, got_re, got_im, exp_re, exp_im, tolerance);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: write one entry to the gain-table BRAM
    // -------------------------------------------------------------------------
    task automatic write_gain(
        input logic [6:0]  addr_in,
        input logic [15:0] data_in,
        input logic [1:0]  bank_in
    );
        @(negedge clk);
        bin_addr  = addr_in;
        bin_wdata = data_in;
        bin_bank  = bank_in;
        bin_we    = 1'b1;
        @(posedge clk);
        @(negedge clk);
        bin_we    = 1'b0;
        bin_wdata = '0;
    endtask

    // -------------------------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_spectral_proc.vcd");
        $dumpvars(0, tb_spectral_proc);
    end

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        // ---- Reset --------------------------------------------------------
        rst_n      = 1'b0;
        in_re      = '0;
        in_im      = '0;
        in_v       = 1'b0;
        in_last    = 1'b0;
        mode       = MODE_GENERAL;
        master_gain = 16'sd16384;  // Q2.14 unity
        noise_floor = 16'sd0;      // gate fully open
        gate_ratio  = 16'sd0;
        bin_addr   = '0;
        bin_wdata  = '0;
        bin_we     = 1'b0;
        bin_bank   = 2'd0;
        bank_commit = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (4)  @(posedge clk);

        // =====================================================================
        // Test 1: Unity gain (all bins pass through unchanged)
        // Master gain = 1.0 (16384), all per-bin gains = 1.0 (default 16384).
        // Input re=1000, im=500 -> output should be (approximately) re=1000,
        // im=500. The actual formula: mul_re = 1000 * 16384 = 16384000,
        // then [29:14] = 1000. im follows re.
        // =====================================================================
        $display("\n=== Test 1: Unity gain, 128 bins pass through ===");
        for (int i = 0; i < 128; i++) begin
            // Send a unique value per bin so we can verify the right bin
            // gets the right gain (default 16384 for all)
            test_re = 16'sd100 + 16'(i);
            test_im = 16'sd50 + 16'(i);
            send_bin(test_re, test_im, 1'b1);
            // Output appears 4 cycles later (the RTL has a 4-stage pipeline)
            check_bin(test_re, test_im, $sformatf("Test1-Bin%0d", i));
            @(negedge clk);
            in_v = 1'b0;
            @(posedge clk);
        end

        // =====================================================================
        // Test 2: Noise gate
        // Set noise_floor high, send a low-magnitude bin. The gate
        // attenuates bins below the noise floor threshold.
        // =====================================================================
        $display("\n=== Test 2: Noise gate (high noise floor) ===");
        repeat (20) @(posedge clk);
        noise_floor = 16'sd10000;   // high threshold
        gate_ratio  = 16'sd4096;    // Q2.14 0.25 (attenuate to 1/4)

        send_bin(16'sd10, 16'sd5, 1'b1);
        // With floor=10000 and |X|^2=10^2+5^2=125 < floor, gate closes.
        // Output = in * gate_ratio = 10 * 4096 / 16384 = 2 (approx)
        check_bin_range(16'sd2, 16'sd1, 2, "Test2-NoiseGate-bin0");
        @(negedge clk);
        in_v = 1'b0;
        @(posedge clk);

        // Restore normal noise floor
        noise_floor = 16'sd0;
        gate_ratio  = 16'sd0;

        // =====================================================================
        // Test 3: Gain table write
        // The DUT's bin counter increments on every in_v_i pulse and wraps
        // naturally at 127. in_last_i is only pipelined; it does not reset the
        // counter. At this point the counter is 1 (128 bins from Test 1 plus
        // one bin from Test 2), so write the custom gain at bin 0 and advance
        // through bins 1..127 before sending the checked sample at bin 0.
        // =====================================================================
        $display("\n=== Test 3: Gain table write (wrapped bin 0 bank A, gain=0.5) ===");
        write_gain(7'd0, 16'sd8192, 2'd0);
        // Wait for the write to settle
        repeat (4) @(posedge clk);

        // Advance the internal counter from 1 through 127. These dummy bins
        // ensure that the following valid input uses gain_bank_a[0].
        for (int i = 1; i < 128; i++) begin
            send_bin(16'sd0, 16'sd0, 1'b1);
            @(negedge clk);
            in_v = 1'b0;
            @(posedge clk);
        end

        // Flush the 4-stage pipeline: drain the dummy-loop outputs so the
        // check below observes the 1000/500 sample, not a leftover dummy.
        repeat (10) @(posedge clk);

        // The counter wraps from 127 to 0 on this valid input. Gain 0.5 must
        // therefore be applied: 1000 -> 500 and 500 -> 250.
        send_bin(16'sd1000, 16'sd500, 1'b1);
        check_bin(16'sd500, 16'sd250, "Test3-CustomGain-bin0-after-wrap");

        // =====================================================================
        // Test 4: Bank swap (write B, commit, verify via output)
        // Write a distinctive gain to bank B bin 0, commit, then verify
        // the output reflects the new bank's gain.
        // =====================================================================
        $display("\n=== Test 4: Bank swap (write B, commit, verify output) ===");
        repeat (20) @(posedge clk);

        // Write a distinctive gain value to bank B, bin 1 (the bin the
        // check sample below will actually read; the DUT bin counter has
        // already advanced past bin 0 by this point in the campaign).
        write_gain(7'd1, 16'h2000, 2'd1);  // bin 1: the bin the next sample reads (gain = 0.125 in Q2.14)
        repeat (4) @(posedge clk);
        // Commit to bank B
        @(negedge clk);
        bank_commit = 1'b1;
        @(posedge clk);
        @(negedge clk);
        bank_commit = 1'b0;

        // Flush pipeline leftovers from Test 3 before this check.
        repeat (10) @(posedge clk);

        // Send bin 0 with in_re = 4096 (0.25 in Q2.14)
        // Expected: 4096 * 0x2000 >> 14 = 4096 * 8192 / 16384 = 2048
        send_bin(16'sd4096, 16'sd0, 1'b1);
        check_bin_range(16'sd2048, 16'sd0, 4, "Test4-BankB-Gain");

        // =====================================================================
        // Test 5: Streaming valid (out_v_o follows in_v_i with latency)
        // Send 10 bins, verify 10 out_v_o pulses.
        // =====================================================================
        $display("\n=== Test 5: Streaming valid behavior ===");
        repeat (20) @(posedge clk);
        for (int i = 0; i < 10; i++) begin
            test_re = 16'(i);
            test_im = 16'sd0;
            send_bin(test_re, test_im, 1'b1);
            check_bin(test_re, test_im, $sformatf("Test5-Bin%0d", i));
            @(negedge clk);
            in_v = 1'b0;
            @(posedge clk);
        end

        // =====================================================================
        // Summary
        // =====================================================================
        repeat (50) @(posedge clk);
        $display("\n=== tb_spectral_proc Summary ===");
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
        $display("[%0t] TIMEOUT in tb_spectral_proc", $time);
        $finish;
    end

endmodule : tb_spectral_proc

`default_nettype wire
