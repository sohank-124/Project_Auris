`default_nettype none
`timescale 1ns / 1ps

module tb_xfft_handshake;
    logic test_done = 1'b0;
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

    int input_samples=0, fft_in=0, ifft_in=0, fft_out=0, ifft_out=0;
    // Count transfers, not asserted valid cycles: a stopped producer/consumer
    // must not satisfy a test merely by keeping overflow low.
    always @(posedge dut.clk_96mhz) if (dut.rst_dsp_n === 1'b1) begin
        if ($isunknown({dut.u_dsp_pipeline.sample_valid_i,
            dut.u_dsp_pipeline.fft_fifo_valid, dut.u_dsp_pipeline.fft_data_ready,
            dut.u_dsp_pipeline.ifft_fifo_valid, dut.u_dsp_pipeline.ifft_data_ready,
            dut.u_dsp_pipeline.fft_v, dut.u_dsp_pipeline.ifft_v}))
            $fatal(1, "XFFT_HANDSHAKE_FAIL: unknown transfer control");
        if ({dut.u_dsp_pipeline.fft_fifo_overflow,
             dut.u_dsp_pipeline.ifft_fifo_overflow} !== 2'b00)
            $fatal(1, "XFFT_HANDSHAKE_FAIL: overflow or unknown overflow status");
        if (dut.u_dsp_pipeline.sample_valid_i) input_samples++;
        if (dut.u_dsp_pipeline.fft_fifo_valid && dut.u_dsp_pipeline.fft_data_ready) begin
            if ($isunknown(dut.u_dsp_pipeline.fft_fifo_data) ||
                dut.u_dsp_pipeline.fft_fifo_data[32] !== (fft_in%256==255))
                $fatal(1, "XFFT_HANDSHAKE_FAIL: FFT input data/marker");
            fft_in++;
        end
        if (dut.u_dsp_pipeline.ifft_fifo_valid && dut.u_dsp_pipeline.ifft_data_ready) begin
            if ($isunknown(dut.u_dsp_pipeline.ifft_fifo_data) ||
                dut.u_dsp_pipeline.ifft_fifo_data[32] !== (ifft_in%256==255))
                $fatal(1, "XFFT_HANDSHAKE_FAIL: IFFT input data/marker");
            ifft_in++;
        end
        if (dut.u_dsp_pipeline.fft_v) begin
            if (dut.u_dsp_pipeline.fft_last !== (fft_out%256==255))
                $fatal(1, "XFFT_HANDSHAKE_FAIL: FFT output marker");
            fft_out++;
        end
        if (dut.u_dsp_pipeline.ifft_v) begin
            if (dut.u_dsp_pipeline.ifft_last !== (ifft_out%256==255))
                $fatal(1, "XFFT_HANDSHAKE_FAIL: IFFT output marker");
            ifft_out++;
        end
    end

    initial begin
        clk_12mhz = 1'b0;
        btn_i     = 4'b0000;

        // The prior raw-TREADY failure occurred near 2.7 ms. This run ends
        // shortly after that point and checks only elastic-buffer overflow.
        #4ms;

        if (dut.u_dsp_pipeline.fft_fifo_overflow !== 1'b0)
            $fatal(1, "XFFT_HANDSHAKE_FAIL: FFT input buffer overflowed");
        if (dut.u_dsp_pipeline.ifft_fifo_overflow !== 1'b0)
            $fatal(1, "XFFT_HANDSHAKE_FAIL: IFFT input buffer overflowed");

        // At 48 kHz, 4 ms lies between the first and second 128-sample hop.
        // Derive frame counts from observed input rather than assuming startup.
        if (input_samples/128 < 1 || fft_in != (input_samples/128)*256 ||
            ifft_in != fft_in || fft_out != fft_in || ifft_out != fft_in)
            $fatal(1, "XFFT_HANDSHAKE_FAIL: missing/extra transfers input=%0d fft=%0d/%0d ifft=%0d/%0d",
                input_samples,fft_in,fft_out,ifft_in,ifft_out);
        $display("XFFT_HANDSHAKE_PASS: inputs=%0d FFT=%0d IFFT=%0d, complete frames through 4 ms",
            input_samples,fft_out,ifft_out);
        test_done = 1'b1;
        $finish;
    end
    initial begin #5ms; $fatal(1, "XFFT handshake timeout"); end
endmodule

`default_nettype wire
