// =============================================================================
// File:        tb_spi_slave.sv
// Project:     Project Auris
// Module:      tb_spi_slave
// Description: Self-checking testbench for the SPI Mode-0 slave.
//
//              Frame format (33 bits on the wire, MSB-first):
//                { 1'b0, addr[6:0], rw, data[23:0] }
//                 ^start  ^7-bit    ^1   ^24-bit payload
//                 marker  address  R/W
//
//              SCLK   : 10 MHz (period 100 ns)
//              Mode 0 : SCLK idle-low, MOSI sampled on rising edge,
//                       data changes on falling edge.
//              CS_N   : active-low, asserted for the full transaction.
//
//              The testbench acts as the SPI master:
//                - drives MOSI on the SCLK falling edge
//                - samples MISO on (or just after) the SCLK rising edge
//
//              NOTE: the current spi_slave RTL is a stub (outputs tied to 0).
//              This testbench validates the documented intended behavior.
// =============================================================================
`default_nettype none
`timescale 1ns/1ps

module tb_spi_slave;
    import auris_pkg::*;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic        sclk;
    logic        cs_n;
    logic        mosi;
    logic        miso;
    logic        rst_n;
    logic [6:0]  addr;
    logic [23:0] wdata;
    logic [23:0] rdata;
    logic        we;
    logic        re;
    logic        rdata_valid;

    // -------------------------------------------------------------------------
    // DUT instance
    // -------------------------------------------------------------------------
    spi_slave #(.ADDR_W(7), .DATA_W(24)) dut (
        .sclk_i        (sclk),
        .cs_n_i        (cs_n),
        .mosi_i        (mosi),
        .miso_o        (miso),
        .rst_n_i       (rst_n),
        .addr_o        (addr),
        .wdata_o       (wdata),
        .we_o          (we),
        .re_o          (re),
        .rdata_i       (rdata),
        .rdata_valid_i (rdata_valid)
    );

    // -------------------------------------------------------------------------
    // SCLK generation: 10 MHz
    // -------------------------------------------------------------------------
    localparam real SCLK_HALF = 50.0;  // ns
    initial begin
        sclk = 1'b0;
        forever #(SCLK_HALF) sclk = ~sclk;
    end

    // -------------------------------------------------------------------------
    // Test tracking
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;
    int total_count = 0;

    // -------------------------------------------------------------------------
    // Frame packers
    // -------------------------------------------------------------------------
    // Frame is 33 bits = 1 (start) + 7 (addr) + 1 (rw) + 24 (data)
    function automatic logic [32:0] pack_write(
        input logic [6:0]  a,
        input logic [23:0] d
    );
        return {1'b0, a, 1'b0, d};
    endfunction

    function automatic logic [32:0] pack_read(
        input logic [6:0] a
    );
        return {1'b0, a, 1'b1, 24'h000000};
    endfunction

    // -------------------------------------------------------------------------
    // Task: full-duplex 33-bit SPI transfer.
    // Drives MOSI MSB-first on each SCLK falling edge, samples MISO MSB-first
    // on each SCLK rising edge.
    // -------------------------------------------------------------------------
    task automatic spi_transfer(
        input  logic [32:0] mosi_data,
        output logic [32:0] miso_data
    );
        // CS_N goes low to start the transaction
        @(negedge sclk);
        cs_n = 1'b0;

        for (int i = 32; i >= 0; i--) begin
            mosi = mosi_data[i];     // drive on falling edge (stable before rising)
            @(posedge sclk);
            #1;                     // small hold
            miso_data[i] = miso;    // sample MISO shortly after rising edge
            @(negedge sclk);
        end

        cs_n = 1'b1;
        mosi = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // High-level tasks
    // -------------------------------------------------------------------------
    task automatic spi_write(
        input logic [6:0]  addr_in,
        input logic [23:0] data_in
    );
        logic [32:0] miso_dummy;
        spi_transfer(pack_write(addr_in, data_in), miso_dummy);
    endtask

    task automatic spi_read(
        input  logic [6:0]  addr_in,
        output logic [23:0] data_out
    );
        logic [32:0] miso_data;
        // The 33-bit MISO frame has rdata[23:0] in the low 24 bits
        // (assuming the slave shifts it out MSB-first starting at the
        //  10th bit; we capture the whole 33 bits and extract).
        spi_transfer(pack_read(addr_in), miso_data);
        // The read data appears in bits [23:0] of the received frame
        data_out = miso_data[23:0];
    endtask

    // -------------------------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("fpga/sim/waveforms/tb_spi_slave.vcd");
        $dumpvars(0, tb_spi_slave);
    end

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        // ---- Reset --------------------------------------------------------
        rst_n       = 1'b0;
        cs_n        = 1'b1;
        mosi        = 1'b0;
        rdata       = '0;
        rdata_valid = 1'b0;
        repeat (20) @(posedge sclk);
        rst_n = 1'b1;
        repeat (4)  @(posedge sclk);

        // =====================================================================
        // Test 1: Write transaction
        // =====================================================================
        $display("\n=== Test 1: Write transaction (REG_SCRATCH=0x7E <- 0xDEADBEEF) ===");
        spi_write(REG_SCRATCH, 24'hDEAD_BEEF);
        // After CS_N rises, the slave should present addr_o/wdata_o/we_o
        // for one SCLK cycle. Wait one SCLK then sample.
        @(posedge sclk);
        total_count++;
        if (addr === REG_SCRATCH && wdata === 24'hDEAD_BEEF && we === 1'b1 && re === 1'b0) begin
            $display("[PASS] Test1-Write: addr=%h wdata=%h we=%b re=%b", addr, wdata, we, re);
            pass_count++;
        end else begin
            $display("[FAIL] Test1-Write: addr=%h wdata=%h we=%b re=%b (exp addr=%h wdata=%h we=1 re=0)",
                     addr, wdata, we, re, REG_SCRATCH, 24'hDEAD_BEEF);
            fail_count++;
        end

        repeat (10) @(posedge sclk);

        // =====================================================================
        // Test 2: Read transaction
        // =====================================================================
        $display("\n=== Test 2: Read transaction (REG_STATUS=0x01 -> expect 0xCAFEBABE) ===");
        rdata       = 24'hCAFE_BABE;
        rdata_valid = 1'b1;
        spi_read(REG_STATUS, wdata);
        // After CS_N rises, slave should present addr_o and re_o
        @(posedge sclk);
        total_count++;
        if (addr === REG_STATUS && re === 1'b1 && we === 1'b0) begin
            $display("[PASS] Test2-Read:  addr=%h re=%b we=%b (MISO got wdata=%h)",
                     addr, re, we, wdata);
            pass_count++;
        end else begin
            $display("[FAIL] Test2-Read:  addr=%h re=%b we=%b (exp addr=%h re=1 we=0)",
                     addr, re, we, REG_STATUS);
            fail_count++;
        end
        // Check that MISO carried the read data
        total_count++;
        if (wdata === 24'hCAFE_BABE) begin
            $display("[PASS] Test2-MISO:  received rdata=%h matches expected", wdata);
            pass_count++;
        end else begin
            $display("[FAIL] Test2-MISO:  received rdata=%h (expected 0xCAFEBABE)", wdata);
            fail_count++;
        end
        rdata_valid = 1'b0;
        repeat (10) @(posedge sclk);

        // =====================================================================
        // Test 3: Multiple transactions (5 writes + 5 reads)
        // =====================================================================
        $display("\n=== Test 3: 5 writes + 5 reads ===");
        // 5 writes to different scratch addresses
        for (int i = 0; i < 5; i++) begin
            spi_write(REG_SCRATCH, 24'hAA0000 + i[23:0]);
            @(posedge sclk);
        end
        $display("       5 writes issued");

        // 5 reads with incrementing rdata
        rdata_valid = 1'b1;
        for (int i = 0; i < 5; i++) begin
            rdata = 24'hBB0000 + i[23:0];
            spi_read(REG_SCRATCH, wdata);
            total_count++;
            if (wdata === 24'hBB0000 + i[23:0]) begin
                $display("[PASS] Test3-Read%0d: got %h", i, wdata);
                pass_count++;
            end else begin
                $display("[FAIL] Test3-Read%0d: got %h (expected %h)",
                         i, wdata, 24'hBB0000 + i[23:0]);
                fail_count++;
            end
        end
        rdata_valid = 1'b0;
        repeat (10) @(posedge sclk);

        // =====================================================================
        // Test 4: Invalid frame (start bit = 1)
        // =====================================================================
        $display("\n=== Test 4: Invalid frame (start bit=1 should be ignored) ===");
        // Build an invalid frame with start=1
        spi_transfer({1'b1, REG_LOOPBACK, 1'b0, 24'h123456}, /*unused*/wdata);
        // Slave should NOT pulse we_o or re_o
        repeat (5) @(posedge sclk);
        total_count++;
        if (we === 1'b0 && re === 1'b0) begin
            $display("[PASS] Test4-Invalid: we=%b re=%b (both 0 as expected)", we, re);
            pass_count++;
        end else begin
            $display("[FAIL] Test4-Invalid: we=%b re=%b (both should be 0)", we, re);
            fail_count++;
        end

        // =====================================================================
        // Test 5: Loopback test
        // Write 0x55AA12 to REG_LOOPBACK (0x7F), then read it back.
        // =====================================================================
        $display("\n=== Test 5: Loopback test (write 0x55AA12 to 0x7F, read back) ===");
        spi_write(REG_LOOPBACK, 24'h55AA12);
        @(posedge sclk);
        // Now read back. For a true loopback the slave would need to echo
        // the just-written value; in the production design the loopback reg
        // is a plain RW register and rdata_i is fed by the reg_file.
        rdata       = 24'h55AA12;  // model the loopback
        rdata_valid = 1'b1;
        spi_read(REG_LOOPBACK, wdata);
        total_count++;
        if (wdata === 24'h55AA12) begin
            $display("[PASS] Test5-Loopback: write/read match (%h)", wdata);
            pass_count++;
        end else begin
            $display("[FAIL] Test5-Loopback: readback %h (expected 0x55AA12)", wdata);
            fail_count++;
        end
        rdata_valid = 1'b0;

        // =====================================================================
        // Summary
        // =====================================================================
        repeat (50) @(posedge sclk);
        $display("\n=== tb_spi_slave Summary ===");
        $display("Total: %0d  Pass: %0d  Fail: %0d", total_count, pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog (100 us)
    // -------------------------------------------------------------------------
    initial begin
        #100_000;
        $display("[%0t] TIMEOUT in tb_spi_slave", $time);
        $finish;
    end

endmodule : tb_spi_slave

`default_nettype wire
