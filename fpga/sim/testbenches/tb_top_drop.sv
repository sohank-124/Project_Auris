`timescale 1ns/1ps
module tb_top_drop;
logic test_done=0;
logic clk=0;
wire status;
always #41.666 clk=~clk;
top dut(.clk_12mhz(clk),.btn_i(4'b0000),.i2s_adc_data_i(1'b0),.status_clip_o(status));
initial begin
 force dut.rst_i2s_n=0;force dut.rst_dsp_n=0;
 force dut.i2s_rx_valid=0;force dut.dsp_out_valid=0;
 force dut.dsp_in_valid=0;
 force dut.i2s_rx_l_full=0;force dut.i2s_rx_r_full=0;
 force dut.i2s_tx_l_full=0;force dut.i2s_tx_r_full=0;
 #20000;
 force dut.rst_i2s_n=1;force dut.rst_dsp_n=1;
 @(negedge dut.i2s_bclk_o);
 force dut.i2s_rx_valid=1;force dut.i2s_rx_r_full=1;
 #1;if(dut.i2s_rx_pair_write!==0) $fatal(1,"RX accepted a partial pair");
 @(negedge dut.i2s_bclk_o);force dut.i2s_rx_valid=0;
 repeat(4) @(negedge dut.clk_96mhz);
 if({dut.rx_drop_dsp,status} !== 2'b11) $fatal(1,"RX drop not observable");
 force dut.i2s_rx_r_full=0;force dut.i2s_rx_l_full=1;force dut.i2s_rx_valid=1;
 #1;if(dut.i2s_rx_pair_write!==0) $fatal(1,"RX left-full acceptance");
 force dut.i2s_rx_l_full=0;
 #1;if(dut.i2s_rx_pair_write!==1) $fatal(1,"RX free pair rejected");
 force dut.i2s_rx_valid=0;
 @(negedge dut.clk_96mhz);force dut.dsp_out_valid=1;force dut.i2s_tx_l_full=1;
 @(negedge dut.clk_96mhz);force dut.dsp_out_valid=0;
 if({dut.tx_drop_sticky,status} !== 2'b11) $fatal(1,"TX drop not observable");
 force dut.rst_i2s_n=0;force dut.rst_dsp_n=0;
 #100;if({dut.rx_drop_dsp,dut.rx_drop_sticky,dut.tx_drop_sticky} !== 3'b000) $fatal(1,"Drop reset failed");
 $display("TOP_DROP_PASS paired admission RX/TX sticky reporting and reset");test_done=1;$finish;
end
initial begin #100000;$fatal(1,"Timeout");end
endmodule
