`timescale 1ns/1ps
module tb_overlap_add;
 logic clk=0,rst_n=0,iv=0,last=0;
 logic [23:0] value=0;
 logic [7:0] scale=0;
 wire [23:0] result,rresult;
 wire ov,done;
 logic test_done=0;
 int expected[0:4095];
 int sent=0,received=0;
 int previous[0:127];
 int previous_scale=0;
 always #5 clk=~clk;
 overlap_add dut(.clk_i(clk),.rst_n_i(rst_n),.in_l_i(value),.in_r_i(value),.in_v_i(iv),.in_last_i(last),
 .out_l_o(result),.out_r_o(rresult),.out_v_o(ov),.frame_done_o(done),.scale_factor_i(scale));
 function automatic int clamp(input longint signed x);
   if(x>8388607) return 8388607;
   if(x< -8388608) return -8388608;
   return int'(x);
 endfunction
 always @(negedge clk) if(rst_n && ov) begin
   if(received>=sent || $signed(result)!==expected[received] || rresult!==result)
     $fatal(1,"OLA sample %0d got=%0d expected=%0d",received,$signed(result),expected[received]);
   received++;
 end
 initial begin
   int sample_value,frame_scale;
   longint signed sum;
   for(int session=0;session<2;session++) begin
     @(negedge clk); #1;rst_n=0;iv=0;last=0;
     for(int j=0;j<128;j++) previous[j]=0;
     previous_scale=0;
     repeat(4) @(negedge clk); #1;rst_n=1;
     for(int f=0;f<8;f++) begin
       frame_scale=(f*3)%17;
       for(int k=0;k<256;k++) begin
         @(negedge clk); #1;
         if(f%2 && k%3==0) begin iv=0;last=0; @(negedge clk); #1; end
         sample_value=((k*997+f*1237)%60000)-30000;
         value=sample_value;scale=frame_scale;iv=1;last=(k==255);
         if(k<128) begin
           sum=(longint'(sample_value)<<<frame_scale)+(longint'(previous[k])<<<previous_scale);
           expected[sent]=clamp(sum);sent++;
         end else previous[k-128]=sample_value;
       end
       previous_scale=frame_scale;
     end
     @(negedge clk); #1;iv=0;last=0;
     repeat(6) @(negedge clk);
     if(received!=sent) $fatal(1,"Missing OLA outputs");
   end
   $display("OLA_NUMERICAL_PASS %0d samples, changing exponents, bubbles, saturation and soft reset",received);
   test_done=1;$finish;
 end
 initial begin #200000;$fatal(1,"OLA timeout");end
endmodule
