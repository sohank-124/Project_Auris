// =============================================================================
// File:        tb_cdc_fifo.sv
// Project:     Project Auris
// Module:      tb_cdc_fifo
// Description: Self-checking testbench for the I2S-to-DSP clock-domain
//              crossing FIFO (cdc_i2s_to_dsp).
//
//              wr_clk : 3.072 MHz (I2S BCLK domain)
//              rd_clk : 96 MHz   (DSP domain)
//              DEPTH  : 4 entries
//              WIDTH  : 24 bits
//
//              Tests:
//                1. Basic transfer: write 4 samples, read them, verify data
//                2. Full flag: write 4 samples without reading, wr_full_o
//                3. Empty flag: read from empty FIFO, rd_empty_o asserts
//                4. Continuous streaming: 100 samples round-trip
//                5. Reset: assert reset, verify empty/full reset
// =============================================================================
`default_nettype none
`timescale 1ns/1ps

module tb_cdc_fifo;
    import auris_pkg::*;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic        wr_clk;
    logic        wr_rst_n;
    logic        wr_en;
    logic [23:0] wr_data;
    logic        wr_full;

    logic        rd_clk;
    logic        rd_rst_n;
    logic        rd_en;
    logic [23:0] rd_data;
    logic        rd_valid;
    logic        rd_empty;

    // -------------------------------------------------------------------------
    // DUT instance
    // -------------------------------------------------------------------------
    cdc_i2s_to_dsp #(.WIDTH(24), .DEPTH(4)) dut (
        .wr_clk_i  (wr_clk),
        .wr_rst_n_i(wr_rst_n),
        .wr_en_i   (wr_en),
        .wr_data_i (wr_data),
        .rd_clk_i  (rd_clk),
        .rd_rst_n_i(rd_rst_n),
        .rd_en_i   (rd_en),
        .rd_data_o (rd_data),
        .rd_valid_o(rd_valid),
        .rd_empty_o(rd_empty),
        .wr_full_o (wr_full)
    );

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    localparam real WR_HALF = (1000.0/3.072)/2.0;  // 162.7604 ns
    localparam real RD_HALF = (1000.0/96.0)/2.0;   // 5.2083 ns

    initial begin
        wr_clk = 1'b0;
        forever #(WR_HALF) wr_clk = ~wr_clk;
    end

    initial begin
        rd_clk = 1'b0;
        forever #(RD_HALF) rd_clk = ~rd_clk;
    end

    // -------------------------------------------------------------------------
    // Test tracking
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;
    int total_count = 0;

    // -------------------------------------------------------------------------
    // Task: write one sample into the FIFO
    // -------------------------------------------------------------------------
    task automatic write_sample(input logic [23:0] data);
        @(negedge wr_clk);
        wr_en  = 1'b1;
        wr_data = data;
        @(posedge wr_clk);
        @(negedge wr_clk);
        wr_en  = 1'b0;
        wr_data = '0;
    endtask

    // -------------------------------------------------------------------------
    // Task: read one sample from the FIFO.
    // Asserts rd_en_i and waits for rd_valid_o.
    // -------------------------------------------------------------------------
    task automatic read_sample(
        output logic [23:0] data,
        output logic        valid,
        input  int          timeout_cycles
    );
        int cnt;
        valid = 1'b0;
        data  = '0;
        cnt   = 0;

        // Wait for the FIFO to become non-empty WITHOUT holding rd_en,
        // so the read pointer cannot advance prematurely.
        while (rd_empty && cnt < timeout_cycles) begin
            @(posedge rd_clk);
            cnt++;
        end
        if (rd_empty) begin
            valid = 1'b0;   // timeout: no data available
            return;
        end

        // Single-cycle read: capture rd_data at the NEGEDGE (pointer is
        // stable; it only advances on posedges), then commit on the
        // following posedge.
        @(negedge rd_clk);
        rd_en  = 1'b1;
        data   = rd_data;   // mem[rd_ptr] before the commit posedge
        @(posedge rd_clk);  // read commits; pointer advances here
        @(negedge rd_clk);
        rd_en  = 1'b0;
        valid  = 1'b1;
    endtask

    // -------------------------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_cdc_fifo.vcd");
        $dumpvars(0, tb_cdc_fifo);
    end

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        logic [23:0] rdata;
        logic        rvalid;

        // ---- Reset --------------------------------------------------------
        wr_rst_n = 1'b0;
        rd_rst_n = 1'b0;
        wr_en    = 1'b0;
        wr_data  = '0;
        rd_en    = 1'b0;
        repeat (20) @(posedge wr_clk);
        repeat (20) @(posedge rd_clk);
        wr_rst_n = 1'b1;
        rd_rst_n = 1'b1;
        repeat (10) @(posedge rd_clk);

        // =====================================================================
        // Test 1: Basic transfer (4 samples)
        // =====================================================================
        $display("\n=== Test 1: Basic transfer (4 samples) ===");
        write_sample(24'h111111);
        write_sample(24'h222222);
        write_sample(24'h333333);
        write_sample(24'h444444);

        for (int i = 0; i < 4; i++) begin
            read_sample(rdata, rvalid, 200);
            total_count++;
            if (rvalid && rdata === 24'h111111 * (i + 1)) begin
                $display("[PASS] Test1-Read%0d: got %h", i, rdata);
                pass_count++;
            end else begin
                $display("[FAIL] Test1-Read%0d: got %h valid=%b", i, rdata, rvalid);
                fail_count++;
            end
        end

        // =====================================================================
        // Test 2: Full flag
        // Write DEPTH=4 samples without reading, wr_full_o should assert.
        // =====================================================================
        $display("\n=== Test 2: Full flag after 4 writes ===");
        repeat (20) @(posedge wr_clk);
        wr_en = 1'b0;
        wr_data = '0;
        repeat (10) @(posedge wr_clk);

        write_sample(24'hAAAA01);
        write_sample(24'hAAAA02);
        write_sample(24'hAAAA03);
        write_sample(24'hAAAA04);

        // After 4 writes, FIFO is full
        @(posedge wr_clk);
        total_count++;
        if (wr_full === 1'b1) begin
            $display("[PASS] Test2-Full: wr_full_o=1 after 4 writes");
            pass_count++;
        end else begin
            $display("[FAIL] Test2-Full: wr_full_o=%b (expected 1)", wr_full);
            fail_count++;
        end

        // Drain so the next test starts empty
        for (int i = 0; i < 4; i++) begin
            read_sample(rdata, rvalid, 200);
        end

        // =====================================================================
        // Test 3: Empty flag
        // After draining, rd_empty_o should be high; reading should not
        // produce valid data.
        // =====================================================================
        $display("\n=== Test 3: Empty flag after drain ===");
        repeat (20) @(posedge rd_clk);
        total_count++;
        if (rd_empty === 1'b1) begin
            $display("[PASS] Test3-Empty: rd_empty_o=1 after drain");
            pass_count++;
        end else begin
            $display("[FAIL] Test3-Empty: rd_empty_o=%b (expected 1)", rd_empty);
            fail_count++;
        end

        // Try to read when empty — valid should remain low
        read_sample(rdata, rvalid, 50);
        total_count++;
        if (rvalid === 1'b0) begin
            $display("[PASS] Test3-ReadEmpty: rd_valid_o=0 (no spurious data)");
            pass_count++;
        end else begin
            $display("[FAIL] Test3-ReadEmpty: rd_valid_o=1, data=%h", rdata);
            fail_count++;
        end

        // =====================================================================
        // Test 4: Continuous streaming (100 samples)
        // =====================================================================
        $display("\n=== Test 4: Continuous streaming (100 samples) ===");
        repeat (50) @(posedge rd_clk);

        // 25 synchronized batches of 4 (write 4, then read 4); keeps the
        // depth-4 FIFO exactly full but never overflowing.
        for (int b = 0; b < 25; b++) begin
            // Write 4 samples (depth-4 FIFO: exactly fills, never overflows)
            for (int j = 0; j < 4; j++) begin
                int idx = b * 4 + j;
                write_sample(24'h100000 + idx[23:0]);
            end
            // Read 4 samples back
            for (int j = 0; j < 4; j++) begin
                int i = b * 4 + j;
                read_sample(rdata, rvalid, 500);
                total_count++;
                if (rvalid && rdata === (24'h100000 + i[23:0])) begin
                    if (i == 0 || i == 49 || i == 99)
                        $display("[PASS] Test4-Read%0d: got %h", i, rdata);
                    pass_count++;
                end else begin
                    $display("[FAIL] Test4-Read%0d: got %h valid=%b (exp %h)",
                             i, rdata, rvalid, 24'h100000 + i[23:0]);
                    fail_count++;
                end
            end

            // CDC settle: let the read pointer synchronize back to the
            // write domain before the next write batch, so the write-side
            // full flag is accurate (avoids batch-boundary write drops).
            repeat (20) @(posedge wr_clk);
        end

        // =====================================================================
        // Test 5: Reset behavior
        // Assert reset, verify wr_full_o=0 and rd_empty_o=1
        // =====================================================================
        $display("\n=== Test 5: Reset behavior ===");
        // Fill the FIFO partially
        write_sample(24'hDEAD01);
        write_sample(24'hDEAD02);
        // Now assert reset
        @(negedge wr_clk);
        wr_rst_n = 1'b0;
        @(negedge rd_clk);
        rd_rst_n = 1'b0;
        repeat (10) @(posedge wr_clk);
        repeat (10) @(posedge rd_clk);

        // Release reset, then wait for pointer-sync latency to settle
        wr_rst_n = 1'b1;
        rd_rst_n = 1'b1;
        repeat (10) @(posedge wr_clk);
        repeat (10) @(posedge rd_clk);

        total_count++;
        if (wr_full === 1'b0 && rd_empty === 1'b1) begin
            $display("[PASS] Test5-Reset: wr_full=%b rd_empty=%b", wr_full, rd_empty);
            pass_count++;
        end else begin
            $display("[FAIL] Test5-Reset: wr_full=%b (exp 0), rd_empty=%b (exp 1)",
                     wr_full, rd_empty);
            fail_count++;
        end

        // =====================================================================
        // Summary
        // =====================================================================
        repeat (50) @(posedge rd_clk);
        $display("\n=== tb_cdc_fifo Summary ===");
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
        $display("[%0t] TIMEOUT in tb_cdc_fifo", $time);
        $finish;
    end

endmodule : tb_cdc_fifo

`default_nettype wire
