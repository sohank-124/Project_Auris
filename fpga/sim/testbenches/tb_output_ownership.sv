`timescale 1ns/1ps
module tb_output_ownership;
logic test_done=0;
logic clk=0,rst=0,iv=0,read_en=0;
logic [23:0] l=0,r=0;
wire [23:0] ol,orr;
wire ov,underflow,overflow;
int received=0;
always #5 clk=~clk;
output_buffer dut(.clk_i(clk),.rst_n_i(rst),.in_l_i(l),.in_r_i(r),.in_v_i(iv),.sample_clk_en_i(read_en),.out_l_o(ol),.out_r_o(orr),.out_v_o(ov),.underflow_o(underflow),.overflow_o(overflow));
always @(negedge clk) if(rst && ov) begin
 int expected;
 expected=(received<256)?received:received+128;
 if(ol!==24'(expected) || orr!==24'(10000+expected)) $fatal(1,"Order failure at %0d: %0d %0d",received,ol,orr);
 received++;
end
task automatic block_write(input int base);
 for(int k=0;k<128;k++) begin @(negedge clk);#1;iv=1;l=base+k;r=10000+base+k;end
 @(negedge clk);#1;iv=0;
endtask
initial begin
 repeat(4) @(negedge clk);#1;rst=1;
 block_write(0);block_write(128);
 if(overflow !== 1'b0) $fatal(1,"Two blocks should fit");
 block_write(256);
 if(overflow !== 1'b1) $fatal(1,"Overrun not reported");
 @(negedge clk);#1;read_en=1;
 repeat(256) @(negedge clk);#1;read_en=0;
 repeat(3) @(negedge clk);
 if(received!=256) $fatal(1,"Unread blocks lost");
 block_write(384);
 @(negedge clk);#1;read_en=1;
 repeat(128) @(negedge clk);#1;read_en=0;
 repeat(3) @(negedge clk);
 if(received!=384 || underflow !== 1'b0) $fatal(1,"Recovery/count failure");
 @(negedge clk);#1;read_en=1;
 repeat(3) @(negedge clk);#1;read_en=0;
 if(underflow !== 1'b1) $fatal(1,"Missing underflow");
 rst=0;repeat(3) @(negedge clk);
 if({ov,overflow,underflow} !== 3'b000) $fatal(1,"Reset failed");
 $display("OUTPUT_OWNERSHIP_PASS preserved=256 dropped_block=128 recovered=128");test_done=1;$finish;
end
initial begin #100000;$fatal(1,"Timeout");end
endmodule
