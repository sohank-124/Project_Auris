`timescale 1ns/1ps
module fifo_stress_case #(parameter bit OUTPUT_FIFO=0, REVERSE=0)(
 input wire fast_clk,slow_clk,source_n,run_traffic,drain,
 output integer writes=0,reads=0,full_hits=0,empty_hits=0,
 output logic [23:0] ones_seen=0,zeros_seen=0,
 output wire empty,balanced
);
 wire wc=REVERSE?slow_clk:fast_clk;
 wire rc=REVERSE?fast_clk:slow_clk;
 wire wr_n,rd_n;
 reset_release wr_reset(.clk_i(wc),.async_rst_n_i(source_n),.rst_n_o(wr_n));
 reset_release rd_reset(.clk_i(rc),.async_rst_n_i(source_n),.rst_n_o(rd_n));
 logic we=0,re=0;
 logic [23:0] data=0;
 wire [23:0] head; wire valid,full;
 generate if(OUTPUT_FIFO) begin
 cdc_dsp_to_i2s dut(.wr_clk_i(wc),.wr_rst_n_i(wr_n),.wr_en_i(we),.wr_data_i(data),.rd_clk_i(rc),.rd_rst_n_i(rd_n),.rd_en_i(re),.rd_data_o(head),.rd_valid_o(valid),.rd_empty_o(empty),.wr_full_o(full));
 end else begin
 cdc_i2s_to_dsp dut(.wr_clk_i(wc),.wr_rst_n_i(wr_n),.wr_en_i(we),.wr_data_i(data),.rd_clk_i(rc),.rd_rst_n_i(rd_n),.rd_en_i(re),.rd_data_o(head),.rd_valid_o(valid),.rd_empty_o(empty),.wr_full_o(full));
 end endgenerate
 logic [23:0] expected[0:65535];
 integer put=0,take=0,sequence_number=0;
 assign balanced=(put==take);
 integer unsigned wlfsr=32'h56a12f97,rlfsr=32'h75313248;
 always @(negedge wc) begin
   wlfsr={wlfsr[30:0],wlfsr[31]^wlfsr[21]^wlfsr[1]^wlfsr[0]};
   we=run_traffic && wr_n && (wlfsr[3:0]!=0);
   data=wlfsr[23:0] ^ sequence_number;
 end
 always @(negedge rc) begin
   rlfsr={rlfsr[30:0],rlfsr[31]^rlfsr[21]^rlfsr[1]^rlfsr[0]};
   re=rd_n && (drain || (run_traffic && rlfsr[2:0]!=0));
 end
 always @(posedge wc or negedge source_n) begin
   if(!source_n) begin put=0; sequence_number=0; end
   else if(wr_n) begin
     if($isunknown(full)) $fatal(1,"Unknown full");
     if(we && !full) begin
       if(put-take>=4) $fatal(1,"FIFO accepted over capacity");
       expected[put]=data; put++; writes++; sequence_number++;
       ones_seen=ones_seen | data; zeros_seen=zeros_seen | ~data;
     end else if(we && full) full_hits++;
   end
 end
 always @(posedge rc or negedge source_n) begin
   if(!source_n) take=0;
   else if(rd_n) begin
     if($isunknown({empty,valid}) || valid!==!empty) $fatal(1,"Bad valid/empty");
     // Check the head whenever valid, including when consumption is stalled.
     if(valid) begin
       if(take>=put || head!==expected[take])
         $fatal(1,"FIFO head mismatch type=%0d reverse=%0d put=%0d take=%0d got=%h expected=%h",OUTPUT_FIFO,REVERSE,put,take,head,expected[take]);
       if(re) begin take++; reads++; end
     end else if(re) empty_hits++;
   end
 end
endmodule

module tb_cdc_stress;
 logic fast_clk=0,slow_clk=0,source_n=0,traffic=0,drain=0;
 logic test_done=0;
 integer w[4],r[4],f[4],e[4]; wire [3:0] empty,balanced;
 wire [23:0] ones_seen[4],zeros_seen[4];
 always #5 fast_clk=~fast_clk;
 // Fractional-clock-like 15/16 fast-cycle halves; offset avoids testbench races.
 initial begin #0.37; forever begin #150 slow_clk=~slow_clk; #160 slow_clk=~slow_clk; #160 slow_clk=~slow_clk; #155 slow_clk=~slow_clk; end end
 for(genvar i=0;i<4;i++) begin : cases
   fifo_stress_case #(.OUTPUT_FIFO(i>=2),.REVERSE(i%2)) checks(
     .fast_clk(fast_clk),.slow_clk(slow_clk),.source_n(source_n),.run_traffic(traffic),.drain(drain),
     .writes(w[i]),.reads(r[i]),.full_hits(f[i]),.empty_hits(e[i]),.empty(empty[i]),.balanced(balanced[i]),.ones_seen(ones_seen[i]),.zeros_seen(zeros_seen[i]));
 end
 initial begin
   #1; source_n=0;
   for(int epoch=0;epoch<12;epoch++) begin
     #73.19; source_n=1; traffic=1;
     #25000;
     // Reset occupied FIFOs in alternating epochs; drain others completely.
     if(epoch%2==0) begin
       traffic=0; drain=1; #3000;
       if(empty!==4'b1111) $fatal(1,"FIFO failed to drain");
       if(balanced!==4'b1111) $fatal(1,"Lost sample at drain");
     end
     #0.13; source_n=0; traffic=0; drain=0; #1;
     if(empty!==4'b1111) $fatal(1,"FIFO reset did not flush");
   end
   for(int i=0;i<4;i++) begin
     if(ones_seen[i]!==24'hffffff || zeros_seen[i]!==24'hffffff) $fatal(1,"Incomplete data-bit coverage case%0d",i);
     if(w[i]<500 || r[i]<500 || f[i]+e[i]<100) $fatal(1,"Insufficient stress coverage case%0d",i);
     $display("CDC_STRESS_CASE %0d writes=%0d reads=%0d rejected_full=%0d empty_reads=%0d",i,w[i],r[i],f[i],e[i]);
   end
   $display("CDC_STRESS_PASS cases=4 epochs=12 resets_occupied=6 drains=6 full_24bit_coverage=1");test_done=1;$finish;
 end
 initial begin #1000000; $fatal(1,"CDC stress watchdog"); end
endmodule
