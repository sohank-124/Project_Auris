`default_nettype none
`timescale 1ns / 1ps

module tb_xfft_handshake;
    logic clk_12mhz;
    logic [3:0] btn_i;
    logic i2s_bclk_o, i2s_lrclk_o;
    logic i2s_adc_data_i, i2s_dac_data_o;
    logic status_led_o, status_clip_o;
    logic led_rgb_r, led_rgb_g, led_rgb_b;

    localparam time CLK12_HALF = 41.666ns;
    always #(CLK12_HALF) clk_12mhz = ~clk_12mhz;

    assign i2s_adc_data_i = i2s_dac_data_o;

    top #(
        .SELF_TEST_ENABLE(1'b1),
        .SELF_TEST_LOOPBACK_ENABLE(1'b1),
        .SELF_TEST_PASS_BITS(24'd1024)
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
        btn_i     = 4'b1111;

        // The prior raw-TREADY failure occurred near 2.7 ms. This run ends
        // shortly after that point and checks only elastic-buffer overflow.
        #4ms;

        if (dut.u_dsp_pipeline.fft_fifo_overflow)
            $fatal(1, "XFFT_HANDSHAKE_FAIL: FFT input buffer overflowed");
        if (dut.u_dsp_pipeline.ifft_fifo_overflow)
            $fatal(1, "XFFT_HANDSHAKE_FAIL: IFFT input buffer overflowed");

        $display("XFFT_HANDSHAKE_PASS: no elastic-buffer overflow through 4 ms");
        $finish;
    end
endmodule

`default_nettype wire