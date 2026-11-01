`timescale 1ns/1ps
module tb_cdc_fifo;
 logic wc=0,rc=0,rst=0,we=0,re=0;logic [23:0] data=0;
 wire [23:0] a,b;wire va,vb,ea,eb,fa,fb;
 logic test_done=0;int checks=0;
 always #7 wc=~wc;always #11 rc=~rc;
 cdc_i2s_to_dsp x(.wr_clk_i(wc),.wr_rst_n_i(rst),.wr_en_i(we),.wr_data_i(data),.rd_clk_i(rc),.rd_rst_n_i(rst),.rd_en_i(re),.rd_data_o(a),.rd_valid_o(va),.rd_empty_o(ea),.wr_full_o(fa));
 cdc_dsp_to_i2s y(.wr_clk_i(wc),.wr_rst_n_i(rst),.wr_en_i(we),.wr_data_i(data),.rd_clk_i(rc),.rd_rst_n_i(rst),.rd_en_i(re),.rd_data_o(b),.rd_valid_o(vb),.rd_empty_o(eb),.wr_full_o(fb));
 initial begin
   for(int session=0;session<2;session++) begin
     rst=0;we=0;re=0;repeat(4)@(negedge wc);#1;rst=1;
     repeat(4)@(negedge wc);
     for(int round=0;round<32;round++) begin
       for(int k=0;k<4;k++) begin
         @(negedge wc);#1;if({fa,fb} !== 2'b00)$fatal(1,"Premature full");we=1;data=round*4+k+1;
       end
       @(negedge wc);#1;
       if(fa!==1||fb!==1)$fatal(1,"Not full at four entries");
       data=24'hffffff; // fifth write must not replace oldest entry
       @(negedge wc);#1;we=0;
       repeat(4)@(negedge rc);
       if(va!==1||vb!==1)$fatal(1,"Head valid absent without read enable");
       for(int k=0;k<4;k++) begin
         @(negedge rc);#1;
         if(ea !== 1'b0 || eb !== 1'b0 ||a!==(round*4+k+1)||b!==a)$fatal(1,"FIFO order round=%0d k=%0d got=%0d/%0d",round,k,a,b);
         re=1;checks++;
       end
       @(negedge rc);#1;
       if(ea!==1||eb!==1||va!==0||vb!==0)$fatal(1,"Empty boundary incorrect");
       @(negedge rc);#1;re=0;
       repeat(4)@(negedge wc);
     end
   end
   $display("CDC_FIFO_PASS %0d reads in each implementation, overfill, empty and reset",checks);test_done=1;$finish;
 end
 initial begin #200000;$fatal(1,"FIFO timeout");end
endmodule
