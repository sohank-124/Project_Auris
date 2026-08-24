// =============================================================================
// File:        tb_overlap_add.sv
// Project:     Project Auris
// Module:      tb_overlap_add
// Description: Self-checking testbench for the 50% overlap-add
//              reconstructor (overlap_add). Verifies:
//
//                1. Single frame: send 256 samples, expect 128 output samples
//                2. Two consecutive frames: send 2*256, expect 2*128 outputs
//                3. Known values: validates overlap-add arithmetic with
//                   BFP-aware dynamic scaling
//
//              Clock: 96 MHz
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
    logic [23:0] in_l;
    logic [23:0] in_r;
    logic        in_v;
    logic        in_last;
    logic [23:0] out_l;
    logic [23:0] out_r;
    logic        out_v;
    logic        frame_done;
    logic [7:0]  scale_factor;

    // -------------------------------------------------------------------------
    // DUT instance
    // -------------------------------------------------------------------------
    overlap_add #(.LEN(256), .DATA_W(24)) dut (
        .clk_i          (clk),
        .rst_n_i        (rst_n),
        .in_l_i         (in_l),
        .in_r_i         (in_r),
        .in_v_i         (in_v),
        .in_last_i      (in_last),
        .out_l_o        (out_l),
        .out_r_o        (out_r),
        .out_v_o        (out_v),
        .frame_done_o   (frame_done),
        .scale_factor_i (scale_factor)
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
    // Asserts in_last_i on the final sample to mark the frame boundary.
    // -------------------------------------------------------------------------
    task automatic send_frame(
        input logic [23:0] value
    );
        for (int i = 0; i < 256; i++) begin
            @(negedge clk);
            in_l = value;
            in_r = value;
            in_v = 1'b1;
            in_last = (i == 255);
            @(posedge clk);
        end
        @(negedge clk);
        in_v = 1'b0;
        in_last = 1'b0;
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
    // Task: receive N output samples (parameterized)
    // -------------------------------------------------------------------------
    task automatic receive_n(
        input  int          n,
        output logic [23:0] out_vals [],
        output int          count
    );
        int timeout_cycles;
        out_vals = new[n];
        count = 0;
        timeout_cycles = 0;
        while (count < n && timeout_cycles < 10000) begin
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
        $dumpfile("tb_overlap_add.vcd");
        $dumpvars(0, tb_overlap_add);
    end

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [23:0] out_vals [128];
        int          rcv_count;

        // ---- Reset --------------------------------------------------------
        rst_n       = 1'b0;
        in_l        = '0;
        in_r        = '0;
        in_v        = 1'b0;
        in_last     = 1'b0;
        scale_factor = 8'd0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (4)  @(posedge clk);

        // =====================================================================
        // Test 1: Single frame (256 samples, expect 128 outputs)
        // =====================================================================
        $display("\n=== Test 1: Single frame, expect 128 outputs ===");
        fork
            send_frame(24'sd500);
            receive_frame(out_vals, rcv_count);
        join

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
        begin
            logic [23:0] out_vals_2 [];
            int          rcv_count_2;
            fork
                begin
                    send_frame(24'sd1000);
                    send_frame(24'sd1000);
                end
                receive_n(256, out_vals_2, rcv_count_2);
            join

            total_count++;
            if (rcv_count_2 == 256) begin
                $display("[PASS] Test2-Count: received %0d output samples (expected 256)", rcv_count_2);
                pass_count++;
            end else begin
                $display("[FAIL] Test2-Count: received %0d output samples (expected 256)", rcv_count_2);
                fail_count++;
            end

            // Verify first frame's 128 outputs are present and non-zero
            total_count++;
            if (out_vals_2[0] !== 24'sd0) begin
                $display("[PASS] Test2-Frame1: out_vals[0]=%0d (non-zero)", out_vals_2[0]);
                pass_count++;
            end else begin
                $display("[FAIL] Test2-Frame1: out_vals[0]=%0d (expected non-zero)", out_vals_2[0]);
                fail_count++;
            end

            // Verify second frame's 128 outputs are present and non-zero
            total_count++;
            if (rcv_count_2 >= 129 && out_vals_2[128] !== 24'sd0) begin
                $display("[PASS] Test2-Frame2: out_vals[128]=%0d (non-zero)", out_vals_2[128]);
                pass_count++;
            end else begin
                $display("[FAIL] Test2-Frame2: out_vals[128]=%0d (expected non-zero, count=%0d)",
                         rcv_count_2 >= 129 ? out_vals_2[128] : 24'sd0, rcv_count_2);
                fail_count++;
            end
        end

        repeat (100) @(posedge clk);

        // =====================================================================
        // Test 3: Known values with BFP-aware scaling
        // scale_factor = 0, K_BFP = 6: output = sat24(sum <<< 6)
        // Frame 1: sum = cur + hist = val + 0 = val
        //          output = sat24(val <<< 6) = val * 64
        // Frame 2: hist = val (second half of frame 1)
        //          output = sat24((val + val) <<< 6) = val * 128
        // =====================================================================
        $display("\n=== Test 3: Known values (frame1=1000, frame2=1000) ===");
        repeat (50) @(posedge clk);

        // Frame 1: all 1000
        fork
            send_frame(24'sd1000);
            receive_frame(out_vals, rcv_count);
        join
        total_count++;
        if (rcv_count == 128) begin
            $display("[PASS] Test3-Frame1-Count: received %0d samples", rcv_count);
            pass_count++;
        end else begin
            $display("[FAIL] Test3-Frame1-Count: received %0d samples", rcv_count);
            fail_count++;
        end

        // Frame-1 overlap-add: hist=0, cur=1000 → sum=1000, output ≈ sat24(1000 <<< 6) ≈ 64000
        total_count++;
        if (out_vals[0] >= 24'sd60000) begin
            $display("[PASS] Test3-Frame1-Val: out_vals[0]=%0d (>= 60000)", out_vals[0]);
            pass_count++;
        end else begin
            $display("[FAIL] Test3-Frame1-Val: out_vals[0]=%0d (expected >= 60000)", out_vals[0]);
            fail_count++;
        end

        repeat (50) @(posedge clk);

        // Frame 2: all 1000
        fork
            send_frame(24'sd1000);
            receive_frame(out_vals, rcv_count);
        join
        total_count++;
        if (rcv_count == 128) begin
            $display("[PASS] Test3-Frame2-Count: received %0d samples", rcv_count);
            pass_count++;
        end else begin
            $display("[FAIL] Test3-Frame2-Count: received %0d samples", rcv_count);
            fail_count++;
        end

        // Frame-2 overlap-add: hist=1000, cur=1000 → sum=2000, output ≈ sat24(2000 <<< 6) ≈ 128000
        total_count++;
        if (out_vals[0] >= 24'sd120000) begin
            $display("[PASS] Test3-Frame2-Val: out_vals[0]=%0d (>= 120000)", out_vals[0]);
            pass_count++;
        end else begin
            $display("[FAIL] Test3-Frame2-Val: out_vals[0]=%0d (expected >= 120000)", out_vals[0]);
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
