// =============================================================================
// File:        tb_window_apply.sv
// Project:     Project Auris
// Module:      tb_window_apply
// Description: Self-checking testbench for the Hann-window multiplier
//              (window_apply). Multiplies incoming 24-bit samples by Hann
//              window coefficients from a 256-entry ROM.
//
//              The window coefficients are Q2.14 fixed-point:
//                w[n] = round( (0.5 - 0.5*cos(2*pi*n/256)) * 16384 )
//
//              Key values:
//                w[0]   = 0      (window starts at zero)
//                w[64]  = 8192   (window at n=N/4 is exactly 0.5)
//                w[128] = 16384  (window peak is 1.0 at center)
//                w[192] = 8192   (mirror of w[64])
//                w[255] = 0      (window ends at zero)
//
//              Multiplication: Q2.14 sample * Q2.14 coefficient = Q4.28,
//              then take bits[27:12] to scale back to Q2.14.
//
//              The DUT truncates the 24-bit input to its top 16 bits
//              (in_l_i[23:8]) before multiplication, so the effective
//              sample value is in_l_i[23:8].
//
//              Clock: 96 MHz
//
//              The DUT's window_rom computes all 256 Hann coefficients at
//              elaboration time inside an `initial` block using $cos(); it
//              does NOT load from any external hex file. The expected
//              values in this testbench are computed mathematically so
//              they remain correct independent of the ROM contents.
// =============================================================================
`default_nettype none
`timescale 1ns/1ps

module tb_window_apply;
    import auris_pkg::*;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic        clk;
    logic        rst_n;
    logic [23:0] in_l;
    logic [23:0] in_r;
    logic        in_v;
    logic        frame_start;
    logic [15:0] out_re;
    logic [15:0] out_im;
    logic        out_v;

    // -------------------------------------------------------------------------
    // DUT instance
    // -------------------------------------------------------------------------
    window_apply #(.LEN(256), .DATA_W(24), .WIN_W(16)) dut (
        .clk_i          (clk),
        .rst_n_i        (rst_n),
        .in_l_i         (in_l),
        .in_r_i         (in_r),
        .in_v_i         (in_v),
        .frame_start_i  (frame_start),
        .out_re_o       (out_re),
        .out_im_o       (out_im),
        .out_v_o        (out_v)
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
    // Function: compute expected Hann coefficient at index n (Q2.14)
    //   w[n] = round( (0.5 - 0.5*cos(2*pi*n/256)) * 16384 )
    // -------------------------------------------------------------------------
    function automatic int hann_q14(input int n);
        real r;
        r = 0.5 - 0.5 * $cos(2.0 * 3.141592653589793 * n / 256.0);
        return $rtoi(r * 16384.0 + 0.5);  // round to nearest
    endfunction

    // -------------------------------------------------------------------------
    // Task: send one sample to the DUT
    // -------------------------------------------------------------------------
    task automatic send_sample(
        input logic [23:0] data,
        input logic        valid
    );
        @(negedge clk);
        in_l = data;
        in_r = '0;
        in_v = valid;
        @(posedge clk);
        if (!valid) begin
            @(negedge clk);
            in_v = 1'b0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: wait for one output and compare to expected
    // -------------------------------------------------------------------------
    task automatic check_output(
        input logic [15:0] expected,
        input string       test_name
    );
        logic [15:0] got;
        int timeout_cycles;
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
        got = out_re;
        total_count++;
        // Allow +/- 1 LSB tolerance for rounding
        if ((got === expected) || ((got + 1) === expected) || ((got - 1) === expected)) begin
            $display("[PASS] %s: out_re=%h (exp %h)", test_name, got, expected);
            pass_count++;
        end else begin
            $display("[FAIL] %s: out_re=%h (exp %h, diff=%0d)",
                     test_name, got, expected, $signed(got) - $signed(expected));
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_window_apply.vcd");
        $dumpvars(0, tb_window_apply);
    end

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        int w_q14;
        int samp_q14;

        // ---- Reset --------------------------------------------------------
        rst_n       = 1'b0;
        in_l        = '0;
        in_r        = '0;
        in_v        = 1'b0;
        frame_start = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (4)  @(posedge clk);

        // =====================================================================
        // Test 1: Unity input (16384) -> output = Hann coefficient
        // The DUT truncates the 24-bit input to its top 16 bits
        // (in_l_i[23:8]), so passing 24'h004000 = {8'h00, 16'h4000=16384}
        // gives a Q2.14 sample of exactly 1.0.
        // =====================================================================
        $display("\n=== Test 1: Unity input (sample=1.0), check Hann coefficients ===");
        // The DUT output is valid 2 cycles after the input is sampled.
        for (int n = 0; n < 256; n++) begin
            w_q14 = hann_q14(n);
            // Drive 24-bit value whose top 16 bits = 0x4000 (16384 = 1.0 in Q2.14)
            send_sample(24'h00_4000, 1'b1);
            // Wait for the corresponding output
            check_output(logic'(16'(w_q14)), $sformatf("Test1-n%0d", n));
            // De-assert valid between samples to keep the protocol clean
            @(negedge clk);
            in_v = 1'b0;
            @(posedge clk);
        end

        // =====================================================================
        // Test 2: Zero input -> output = 0
        // =====================================================================
        $display("\n=== Test 2: Zero input, output should be 0 ===");
        for (int n = 0; n < 256; n++) begin
            send_sample(24'h000000, 1'b1);
            check_output(16'h0000, $sformatf("Test2-n%0d", n));
            @(negedge clk);
            in_v = 1'b0;
            @(posedge clk);
        end

        // =====================================================================
        // Test 3: Max input (32767 in Q2.14)
        // Output = (32767 * Hann_q14) >> 14, possibly saturated.
        // =====================================================================
        $display("\n=== Test 3: Max input (sample=32767) ===");
        for (int n = 0; n < 256; n++) begin
            w_q14 = hann_q14(n);
            // 32767 = 0x7FFF, but we need 16-bit top half = 0x7FFF.
            // 24-bit: 0x00_7FFF. Truncated to top 16 = 0x7FFF = 32767.
            send_sample(24'h00_7FFF, 1'b1);
            // Compute expected: (32767 * w_q14) >> 14
            samp_q14 = (32767 * w_q14) >> 14;
            if (samp_q14 > 32767) samp_q14 = 32767;
            check_output(logic'(16'(samp_q14)), $sformatf("Test3-n%0d", n));
            @(negedge clk);
            in_v = 1'b0;
            @(posedge clk);
        end

        // =====================================================================
        // Test 4: Frame boundary
        // After 256 samples the internal counter wraps to 0. Send 256 more
        // samples and verify the pattern repeats (i.e. w[0] at n=256).
        // =====================================================================
        $display("\n=== Test 4: Frame boundary (counter wraps at 256) ===");
        for (int n = 0; n < 256; n++) begin
            w_q14 = hann_q14(n);  // wraps to w[0] after 256
            send_sample(24'h00_4000, 1'b1);
            check_output(logic'(16'(w_q14)), $sformatf("Test4-n%0d", n));
            @(negedge clk);
            in_v = 1'b0;
            @(posedge clk);
        end

        // =====================================================================
        // Summary
        // =====================================================================
        repeat (50) @(posedge clk);
        $display("\n=== tb_window_apply Summary ===");
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
        $display("[%0t] TIMEOUT in tb_window_apply", $time);
        $finish;
    end

endmodule : tb_window_apply

`default_nettype wire
