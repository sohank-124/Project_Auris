`timescale 1ns/1ps
module tb_volume_ctrl;
 logic clk=0,rst=0,iv=0; logic [23:0] l=0,r=0;logic [4:0] level=0;
 wire [23:0] ol,orr;wire ov;logic test_done=0;int checks=0;
 always #5 clk=~clk;
 volume_ctrl dut(.clk_i(clk),.rst_n_i(rst),.in_l_i(l),.in_r_i(r),.in_valid_i(iv),.volume_i(level),.out_l_o(ol),.out_r_o(orr),.out_valid_o(ov));
 initial begin
   int a,b,g;longint signed el,er;
   repeat(4) @(negedge clk);#1;rst=1;
   for(int v=0;v<32;v++) for(int n=0;n<64;n++) begin
     case(n)
       0:a=-8388608;1:a=8388607;2:a=0;3:a=1;4:a=-1;5:a=1024;6:a=-1024;
       default:a=((n*654321)%16777216)-8388608;
     endcase
     b= -a-1;g=(v*16384+15)/31;
     el=(longint'(a)*g)>>>14;er=(longint'(b)*g)>>>14;
     @(negedge clk);#1;l=a;r=b;iv=1;level=v;
     @(posedge clk);#1;
     if(ov!==1 || $signed(ol)!==el || $signed(orr)!==er) $fatal(1,"Volume v=%0d n=%0d got=%0d/%0d expected=%0d/%0d",v,n,$signed(ol),$signed(orr),el,er);
     checks++;
     if(n%7==0) begin @(negedge clk);#1;iv=0;@(posedge clk);#1;if(ov!==0)$fatal(1,"Volume bubble");end
   end
   $display("VOLUME_PASS %0d stereo comparisons, all 32 levels",checks);test_done=1;$finish;
 end
 initial begin #100000;$fatal(1,"Volume timeout");end
endmodule
