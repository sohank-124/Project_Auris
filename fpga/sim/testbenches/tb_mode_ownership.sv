`timescale 1ns/1ps
module tb_mode_ownership;
 logic clk=0,rst=0,mwe=0,iv=0,last=0;
 logic [1:0] mode=0;
 wire we,commit,active;
 wire [6:0] addr;
 wire [15:0] wd;
 wire [1:0] bank;
 wire [23:0] master,noise,ratio;
 int commits=0,writes=0;
 logic test_done=0;
 always #5 clk=~clk;
 mode_ctrl loader(.clk_i(clk),.rst_n_i(rst),.mode_i(mode),.mode_we_i(mwe),.bank_active_i(active),
 .bank_we_o(we),.bank_addr_o(addr),.bank_wdata_o(wd),.bank_sel_o(bank),.bank_commit_o(commit),
 .default_master_gain_o(master),.default_noise_floor_o(noise),.default_gate_ratio_o(ratio));
 spectral_proc spectral(.clk_i(clk),.rst_n_i(rst),.in_re_i(16'd100),.in_im_i(16'd0),.in_v_i(iv),.in_last_i(last),.fft_exponent_i(8'd8),
 .out_re_o(),.out_im_o(),.out_v_o(),.out_last_o(),.mode_i(mode),.master_gain_i(master[15:0]),
 .noise_floor_i(noise[15:0]),.gate_ratio_i(ratio[15:0]),.bin_addr_i(addr),.bin_wdata_i(wd),
 .bin_we_i(we),.bin_bank_i(bank),.bank_commit_i(commit),.bank_active_o(active));
 always @(posedge clk) if(rst) begin
   if(commit) commits++;
   if(we) begin
     writes++;
     if(bank[0]===active) $fatal(1,"Active bank overwrite");
   end
 end
 initial begin
   repeat(4) @(negedge clk); #1;rst=1;
   // Three requests during boot load; latest wins while acknowledgement waits.
   for(int k=1;k<4;k++) begin
     repeat(10) @(negedge clk); #1;mode=k;mwe=1;
     @(negedge clk); #1;mwe=0;
   end
   repeat(400) @(negedge clk);
   if(commits!=1 || writes!=128 || active!==0) $fatal(1,"Loader reused bank before acknowledgement");
   for(int f=0;f<4;f++) for(int k=0;k<256;k++) begin
     @(negedge clk); #1;iv=1;last=(k==255);
   end
   @(negedge clk); #1;iv=0;last=0;
   repeat(10) @(negedge clk);
   if(commits!=2 || writes!=256 || master!==18022 || noise!==32768 || ratio!==9011)
     $fatal(1,"Latest requested mode not applied: commits=%0d writes=%0d master=%0d",commits,writes,master);
   $display("MODE_OWNERSHIP_PASS delayed acknowledgement and latest-request retention");
   test_done=1;$finish;
 end
 initial begin #100000;$fatal(1,"Ownership timeout");end
endmodule
