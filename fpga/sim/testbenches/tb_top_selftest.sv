// =============================================================================
// File:        tb_top_selftest.sv
// Project:     Project Auris
// Description: Top-level boardless bring-up test for self-test mode.
//              Emulates JA7->JA6 jumper by wiring DAC SDATA back to ADC SDATA.
//              Pass criterion:
//                - loopback checker reaches PASS state (RGB cyan)
//                - no loopback fail indication (status_clip_o stays low)
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module tb_top_selftest;

    logic clk_12mhz;
    logic [3:0] btn_i;
    logic i2s_bclk_o;
    logic i2s_lrclk_o;
    logic i2s_adc_data_i;
    logic i2s_dac_data_o;
    logic status_led_o;
    logic status_clip_o;
    logic led_rgb_r;
    logic led_rgb_g;
    logic led_rgb_b;

    // 12 MHz board clock
    localparam time CLK12_HALF = 41.666ns;
    always #(CLK12_HALF) clk_12mhz = ~clk_12mhz;

    // JA7 -> JA6 digital jumper emulation
    assign i2s_adc_data_i = i2s_dac_data_o;

    top #(
        .SELF_TEST_ENABLE(1'b1),
        .SELF_TEST_LOOPBACK_ENABLE(1'b1),
        // Reduce pass threshold in simulation to keep runtime practical.
        .SELF_TEST_PASS_BITS(24'd8192)
    ) dut (
        .clk_12mhz      (clk_12mhz),
        .btn_i          (btn_i),
        .i2s_bclk_o     (i2s_bclk_o),
        .i2s_lrclk_o    (i2s_lrclk_o),
        .i2s_adc_data_i (i2s_adc_data_i),
        .i2s_dac_data_o (i2s_dac_data_o),
        .status_led_o   (status_led_o),
        .status_clip_o  (status_clip_o),
        .led_rgb_r      (led_rgb_r),
        .led_rgb_g      (led_rgb_g),
        .led_rgb_b      (led_rgb_b)
    );

    initial begin
        clk_12mhz = 1'b0;
        btn_i     = 4'b1111; // all buttons unpressed

        // With reduced SELF_TEST_PASS_BITS, 10 ms is enough for PASS.
        #10ms;

        // self-test PASS is RGB cyan in active-low drive: R=1,G=0,B=0.
        if ({led_rgb_r, led_rgb_g, led_rgb_b} != 3'b100) begin
            $error("SELFTEST FAIL: expected RGB cyan PASS state, got %b", {led_rgb_r, led_rgb_g, led_rgb_b});
            $fatal;
        end

        // status_clip_o also reports sticky loopback fail when enabled.
        if (status_clip_o !== 1'b0) begin
            $error("SELFTEST FAIL: status_clip_o asserted, indicates clip/loopback error");
            $fatal;
        end

        $display("tb_top_selftest PASS");
        $finish;
    end

endmodule

`default_nettype wire
