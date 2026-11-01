`timescale 1ns/1ps
module tb_clk_gen;
 logic board_clk=0;wire dsp,bclk,lrclk,locked;
 bit measuring=0;logic test_done=0;
 int dc=0,bc=0,lc=0,half_cycles=0;
 realtime last_edge=0;
 always #41.666667 board_clk=~board_clk;
 clk_gen dut(.clk_in1(board_clk),.clk_dsp_o(dsp),.i2s_bclk_o(bclk),.i2s_lrclk_o(lrclk),.locked(locked));
 always @(posedge dsp)if(measuring)dc++;
 always @(posedge bclk)if(measuring)bc++;
 always @(posedge lrclk)if(measuring)lc++;
 always @(bclk) if(measuring) begin
   if(last_edge!=0 && (($realtime-last_edge)<155 || ($realtime-last_edge)>168))
     $fatal(1,"BCLK half period outside 15..16 DSP cycles: %0f",$realtime-last_edge);
   last_edge=$realtime;half_cycles++;
 end
 initial begin
   wait(locked===1);#100000;measuring=1;
   #1000000;measuring=0;
   if(dc<95998||dc>96002||bc!=3072||lc!=48)$fatal(1,"Clock counts DSP=%0d BCLK=%0d LRCLK=%0d",dc,bc,lc);
   $display("CLOCK_RATE_PASS DSP=%0d BCLK=%0d LRCLK=%0d per millisecond, %0d half periods checked",dc,bc,lc,half_cycles);
   test_done=1;$finish;
 end
 initial begin #2000000;$fatal(1,"Clock timeout");end
endmodule
