`timescale 1ns/1ps
module tb_top_reset;
 logic board_clk=0, inject_lock=0;
 logic test_done=0;
 wire bclk,lrclk;
 integer dsp_edges=0,i2s_edges=0,restarts=0;
 always #41.666667 board_clk=~board_clk;
 top dut(.clk_12mhz(board_clk),.btn_i(4'b0),.i2s_adc_data_i(1'b0),.i2s_bclk_o(bclk),.i2s_lrclk_o(lrclk));
 always @(posedge dut.clk_96mhz or negedge inject_lock) begin
  if(!inject_lock) dsp_edges=0;
  else begin
   dsp_edges++; #0.001;
   if(dut.rst_dsp_n !== (dsp_edges>=16)) $fatal(1,"Top DSP release edge count");
  end
 end
 always @(posedge bclk or negedge inject_lock) begin
  if(!inject_lock) i2s_edges=0;
  else begin
   i2s_edges++; #0.001;
   if(dut.rst_i2s_n !== (i2s_edges>=16)) $fatal(1,"Top I2S release edge count");
  end
 end
 task automatic check_flush;
  #0.02;
  if({dut.rst_dsp_n,dut.rst_i2s_n}!==0) $fatal(1,"Top reset assertion");
  if({dut.u_cdc_i2s_l.wr_ptr_bin,dut.u_cdc_i2s_l.rd_ptr_bin,
      dut.u_cdc_i2s_r.wr_ptr_bin,dut.u_cdc_i2s_r.rd_ptr_bin,
      dut.u_cdc_o2i_l.wr_ptr_bin,dut.u_cdc_o2i_l.rd_ptr_bin,
      dut.u_cdc_o2i_r.wr_ptr_bin,dut.u_cdc_o2i_r.rd_ptr_bin}!==0)
    $fatal(1,"Top FIFO epoch did not flush");
  if(dut.dsp_in_valid!==0 || dut.dsp_out_valid!==0) $fatal(1,"Valid survived reset");
 endtask
 initial begin
  force dut.u_clk_gen.mmcm_locked=inject_lock;
  wait(dut.u_clk_gen.u_mmcm.LOCKED===1);
  for(int epoch=0;epoch<3;epoch++) begin
   @(negedge dut.clk_96mhz); #(0.19+epoch*0.83); inject_lock=1;
   #30000;
   if({dut.rst_dsp_n,dut.rst_i2s_n}!==2'b11 || i2s_edges<80) $fatal(1,"Top failed to restart");
   #0.17; inject_lock=0; check_flush(); restarts++;
   #100;
  end
  $display("TOP_RESET_PASS restarts=%0d four_fifos_flushed=1 actual_vendor_ip=1",restarts);
  test_done=1;$finish;
 end
 initial begin #300000; $fatal(1,"Top reset watchdog"); end
endmodule
