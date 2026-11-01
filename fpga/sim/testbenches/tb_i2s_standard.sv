`timescale 1ns/1ps
module tb_i2s_standard #(parameter bit CHECK_RX=1, CHECK_TX=1);
 logic clk=0,rst=0,lr=1,sd=0,valid=1;
 logic [23:0] left_word=0,right_word=0;
 wire tx,rv,overflow,underflow;wire [23:0] rl,rr;
 int rx_count=0;logic test_done=0;
 always #10 clk=~clk;
 generate if(CHECK_RX) begin: rx_test
 i2s_rx rx(.bclk_i(clk),.lrclk_i(lr),.sdata_i(sd),.rst_n_i(rst),.left_o(rl),.right_o(rr),.valid_o(rv),.overflow_o(overflow));
 end else begin assign {rv,overflow,rl,rr}='0; end
 if(CHECK_TX) begin: tx_test
 i2s_tx transmitter(.bclk_i(clk),.lrclk_i(lr),.sdata_o(tx),.rst_n_i(rst),.left_i(left_word),.right_i(right_word),.valid_i(valid),.underflow_o(underflow));
 end else begin assign {tx,underflow}='0; end endgenerate
 initial begin
   logic [23:0] decoded_l,decoded_r;
   repeat(4)@(negedge clk);#1;rst=1;
   repeat(32)@(negedge clk);
   for(int f=0;f<33;f++) begin
     left_word=24'h812345^(f*123456);right_word=24'h456789^(f*98765);valid=(f!=32);
     decoded_l=0;decoded_r=0;
     for(int slot=0;slot<64;slot++) begin
       @(negedge clk);#1;lr=(slot>=32);
       if(slot>=1&&slot<=24)sd=left_word[24-slot];
       else if(slot>=33&&slot<=56)sd=right_word[56-slot];else sd=0;
       @(posedge clk);#1;
       if(slot>=1&&slot<=24)decoded_l={decoded_l[22:0],tx};
       if(slot>=33&&slot<=56)decoded_r={decoded_r[22:0],tx};
       if(CHECK_RX && $isunknown(rv)) $fatal(1,"Unknown RX valid");
       if(CHECK_RX && rv) begin
         if(rl!==left_word||rr!==right_word)$fatal(1,"I2S RX word mismatch");rx_count++;
       end
     end
     if(CHECK_TX && (decoded_l!==(valid?left_word:24'd0)||decoded_r!==(valid?right_word:24'd0)))$fatal(1,"I2S TX frame %0d got=%h/%h",f,decoded_l,decoded_r);
   end
   if((CHECK_RX && (rx_count!=33 || overflow !== 1'b0)) || (CHECK_TX && underflow !== 1'b1))$fatal(1,"I2S count/status mismatch");
   // An early slot transition must be reported; reset clears sticky status.
   @(negedge clk);#1;lr=0;
   repeat(4)@(negedge clk);#1;lr=1;
   @(posedge clk);#1;if(CHECK_RX && overflow !== 1'b1)$fatal(1,"Malformed RX slot not reported");
   @(negedge clk);#1;rst=0;
   @(posedge clk);#1;if({rv,overflow,underflow} !== 3'b000)$fatal(1,"I2S reset failed");
   $display("I2S_STANDARD_PASS 33 stereo frames, independent source/decoder underrun silence, malformed slot and reset");$display("I2S_DIRECTION_COVERAGE RX=%0d TX=%0d",CHECK_RX,CHECK_TX);test_done=1;$finish;
 end
 initial begin #100000;$fatal(1,"I2S timeout");end
endmodule
