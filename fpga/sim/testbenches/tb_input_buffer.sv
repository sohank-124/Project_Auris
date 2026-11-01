`timescale 1ns/1ps
module tb_input_buffer;
 logic clk=0,rst=0,iv=0;logic [23:0] l=0,r=0;
 wire [23:0] ol,orr;wire ov,ready,busy,overflow;
 logic test_done=0;int received=0,base=0;
 always #5 clk=~clk;
 input_buffer dut(.clk_i(clk),.rst_n_i(rst),.sample_l_i(l),.sample_r_i(r),.sample_v_i(iv),
 .frame_l_o(ol),.frame_r_o(orr),.frame_v_o(ov),.frame_ready_o(ready),.busy_o(busy),.overflow_o(overflow));
 always @(negedge clk) if(rst && ov) begin
   int hop,k,index,expected;
   hop=received/256;k=received%256;index=hop*128+k-127;
   expected=(index<=0)?0:base+index;
   if($signed(ol)!==expected || $signed(orr)!==-expected) $fatal(1,"Input frame %0d sample %0d got %0d/%0d expected %0d",hop,k,$signed(ol),$signed(orr),expected);
   received++;
 end
 initial begin
   for(int session=0;session<2;session++) begin
     @(negedge clk);#1;rst=0;iv=0;received=0;base=session*10000;
     repeat(4)@(negedge clk);#1;rst=1;
     for(int hop=0;hop<6;hop++) begin
       for(int n=1;n<=128;n++) begin @(negedge clk);#1;iv=1;l=base+hop*128+n;r=-int'(l);end
       @(negedge clk);#1;iv=0;
       repeat(260)@(negedge clk);
       if(received!=(hop+1)*256 || overflow !== 1'b0) $fatal(1,"Frame length/overflow failure");
     end
   end
   $display("INPUT_BUFFER_PASS 3072 stereo samples including soft-reset zero history");test_done=1;$finish;
 end
 initial begin #100000;$fatal(1,"Input buffer timeout");end
endmodule
