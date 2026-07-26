// =============================================================================
// File:        tb_overlap_add.sv
// Project:     Project Auris
// Module:      tb_overlap_add
// Description: Self-checking testbench for the 50% overlap-add
//              reconstructor (overlap_add). Verifies:
//
//                1. Single frame: send 256 samples, expect 128 output samples
//                2. Two consecutive frames: send 2*256, expect 2*128 outputs
//                3. Known values: with frame1=all-1000 and frame2=all-1000,
//                   the overlapping region sums the two contributions and
//                   the non-overlapping region has just one
//
//              Per the RTL TODO comment, the intended overlap-add formula
//              is: y[n] = prev[n] + (cur[n] >> 1) for n in 0..127, with
//              history[n] = (cur[n+128] >> 1) stored for the next frame.
//              The current RTL is a stub (outputs tied to 0).
//
//              Clock: 96 MHz
//
//              NOTE: the current overlap_add RTL is a stub. This testbench
//              validates the documented intended behavior; it will FAIL
//              on the current stub.
// =============================================================================
`default_nettype none
`timescale 1ns/1ps

module tb_overlap_add;
    import auris_pkg::*;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic        clk;
    logic        rst_n;
    logic [15:0] in_l;
    logic [15:0] in_r;
    logic        in_v;
    logic [23:0] out_l;
    logic [23:0] out_r;
    logic        out_v;

    // -------------------------------------------------------------------------
    // DUT instance
    // -------------------------------------------------------------------------
    overlap_add #(.LEN(256)) dut (
        .clk_i   (clk),
        .rst_n_i (rst_n),
        .in_l_i  (in_l),
        .in_r_i  (in_r),
        .in_v_i  (in_v),
        .out_l_o (out_l),
        .out_r_o (out_r),
        .out_v_o (out_v)
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
    // Task: send one complete frame of 256 samples
    // -------------------------------------------------------------------------
    task automatic send_frame(
        input logic [15:0] value
    );
        for (int i = 0; i < 256; i++) begin
            @(negedge clk);
            in_l = value;
            in_r = value;
            in_v = 1'b1;
            @(posedge clk);
        end
        @(negedge clk);
        in_v = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Task: receive 128 output samples
    // -------------------------------------------------------------------------
    task automatic receive_frame(
        output logic [23:0] out_vals [128],
        output int          count
    );
        int timeout_cycles;
        count = 0;
        timeout_cycles = 0;
        while (count < 128 && timeout_cycles < 5000) begin
            @(posedge clk);
            if (out_v) begin
                out_vals[count] = out_l;
                count++;
            end
            timeout_cycles++;
        end
    endtask

    // -------------------------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("fpga/sim/waveforms/tb_overlap_add.vcd");
        $dumpvars(0, tb_overlap_add);
    end

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [23:0] out_vals [128];
        int          rcv_count;

        // ---- Reset --------------------------------------------------------
        rst_n = 1'b0;
        in_l  = '0;
        in_r  = '0;
        in_v  = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (4)  @(posedge clk);

        // =====================================================================
        // Test 1: Single frame (256 samples, expect 128 outputs)
        // =====================================================================
        $display("\n=== Test 1: Single frame, expect 128 outputs ===");
        send_frame(16'sd500);
        receive_frame(out_vals, rcv_count);

        total_count++;
        if (rcv_count == 128) begin
            $display("[PASS] Test1-Count: received %0d output samples (expected 128)", rcv_count);
            pass_count++;
        end else begin
            $display("[FAIL] Test1-Count: received %0d output samples (expected 128)", rcv_count);
            fail_count++;
        end

        repeat (100) @(posedge clk);

        // =====================================================================
        // Test 2: Two consecutive frames (2*256 samples, expect 2*128 outputs)
        // =====================================================================
        $display("\n=== Test 2: Two consecutive frames, expect 256 outputs ===");
        send_frame(16'sd1000);
        send_frame(16'sd1000);
        receive_frame(out_vals, rcv_count);

        total_count++;
        if (rcv_count == 128) begin
            $display("[PASS] Test2-Count: frame-2 output count=%0d (expected 128)", rcv_count);
            pass_count++;
        end else begin
            $display("[FAIL] Test2-Count: frame-2 output count=%0d (expected 128)", rcv_count);
            fail_count++;
        end

        repeat (100) @(posedge clk);

        // =====================================================================
        // Test 3: Known values (frame1=1000, frame2=1000)
        // Per the spec: output = 2000 for overlapping region (1000+1000),
        // output = 1000 for non-overlapping.
        // With the RTL's intended formula y = prev + (cur >> 1):
        //   Frame 1: prev=0, cur=1000 -> y = 0 + 500 = 500
        //   Frame 2: prev=500, cur=1000 -> y = 500 + 500 = 1000
        // The spec's "2000" implies a different formula (y = prev + cur).
        // We test for the spec's expected value (2000 for overlap) and
        // note the discrepancy in the report.
        // =====================================================================
        $display("\n=== Test 3: Known values (frame1=1000, frame2=1000) ===");
        repeat (50) @(posedge clk);

        // Frame 1: all 1000
        send_frame(16'sd1000);
        receive_frame(out_vals, rcv_count);
        total_count++;
        if (rcv_count == 128) begin
            $display("[PASS] Test3-Frame1-Count: received %0d samples", rcv_count);
            pass_count++;
        end else begin
            $display("[FAIL] Test3-Frame1-Count: received %0d samples", rcv_count);
            fail_count++;
        end

        // Check that the first frame output is non-zero and consistent
        total_count++;
        if (out_vals[0] === 24'sd1000) begin
            $display("[PASS] Test3-Frame1-Val: out_vals[0]=%0d (expected 1000)", out_vals[0]);
            pass_count++;
        end else begin
            $display("[FAIL] Test3-Frame1-Val: out_vals[0]=%0d (expected 1000 for non-overlap)", out_vals[0]);
            fail_count++;
        end

        repeat (50) @(posedge clk);

        // Frame 2: all 1000
        send_frame(16'sd1000);
        receive_frame(out_vals, rcv_count);
        total_count++;
        if (rcv_count == 128) begin
            $display("[PASS] Test3-Frame2-Count: received %0d samples", rcv_count);
            pass_count++;
        end else begin
            $display("[FAIL] Test3-Frame2-Count: received %0d samples", rcv_count);
            fail_count++;
        end

        // Check the overlapping region: spec expects 2000 (1000+1000)
        total_count++;
        if (out_vals[0] === 24'sd2000) begin
            $display("[PASS] Test3-Frame2-Val: out_vals[0]=%0d (expected 2000=1000+1000)", out_vals[0]);
            pass_count++;
        end else begin
            $display("[FAIL] Test3-Frame2-Val: out_vals[0]=%0d (expected 2000 for overlap)", out_vals[0]);
            fail_count++;
        end

        // =====================================================================
        // Summary
        // =====================================================================
        repeat (50) @(posedge clk);
        $display("\n=== tb_overlap_add Summary ===");
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
        $display("[%0t] TIMEOUT in tb_overlap_add", $time);
        $finish;
    end

endmodule : tb_overlap_add

`default_nettype wire
