`timescale 1ns/1ps
module tb_spectral_power;
 logic clk=0,rst=0,iv=0,last=0;
 logic [7:0] exponent=0;
 logic [15:0] value=0,threshold=0;
 wire [15:0] result;
 wire ov;
 int expected[0:8191];
 int sent=0,received=0;
 logic test_done=0;
 always #5 clk=~clk;
 spectral_proc dut(.clk_i(clk),.rst_n_i(rst),.in_re_i(value),.in_im_i(16'd0),
 .in_v_i(iv),.in_last_i(last),.fft_exponent_i(exponent),.out_re_o(result),.out_im_o(),.out_v_o(ov),.out_last_o(),
 .mode_i(2'd0),.master_gain_i(16'd16384),.noise_floor_i(threshold),.gate_ratio_i(16'd8192),
 .bin_addr_i(7'd0),.bin_wdata_i(16'd0),.bin_we_i(1'b0),.bin_bank_i(2'd0),.bank_commit_i(1'b0),.bank_active_o());
 always @(negedge clk) if(rst && ov) begin
   if(received>=sent || $signed(result)!==expected[received])
     $fatal(1,"Power decision mismatch %0d: got=%0d exp=%0d",received,$signed(result),expected[received]);
   received++;
 end
 initial begin
   int mantissa;
   repeat(4) @(negedge clk); #1;rst=1;
   // All representations describe normalized amplitude 0.125, power 0.015625.
   // Threshold 255: open; 256: equal/open; 257: attenuated.
   for(int e=5;e<=12;e++) for(int t=255;t<=257;t++) begin
     mantissa=524288/(1<<e);
     for(int k=0;k<256;k++) begin
       @(negedge clk); #1;iv=1;last=(k==255);
       value=(k%2)?-mantissa:mantissa;
       exponent=e;threshold=t;
       expected[sent]=(k%2)?-mantissa:mantissa;
       if(t==257) expected[sent]=expected[sent]/2;
       sent++;
       if(k%17==0) begin @(negedge clk); #1;iv=0;last=0;exponent=0; end
     end
   end
   @(negedge clk); #1;iv=0;last=0;
   repeat(10) @(negedge clk);
   if(received!=sent) $fatal(1,"Missing power outputs");
   $display("POWER_NORMALIZATION_PASS %0d samples, eight exponents, below/equal/above thresholds",received);
   test_done=1;$finish;
 end
 initial begin #200000;$fatal(1,"Power timeout");end
endmodule
