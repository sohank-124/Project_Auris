`timescale 1ns/1ps
module tb_spectral_frames;
    logic clk=0,rst=0,iv=0,last=0,we=0,commit=0;
    logic [6:0] addr=0;
    logic [15:0] wd=0, master=16384;
    logic [1:0] bank=1;
    wire active,ov,ol;
    wire [15:0] ox,oy;
    int expected[0:131071];
    int sent=0,received=0;
    int current_style=0;
    logic test_done=0;
    always #5 clk=~clk;
    spectral_proc dut(.clk_i(clk),.rst_n_i(rst),.in_re_i(16'd16384),.in_im_i(16'd0),
      .in_v_i(iv),.in_last_i(last),.fft_exponent_i(8'd8),.out_re_o(ox),.out_im_o(oy),.out_v_o(ov),.out_last_o(ol),
      .mode_i(2'd0),.master_gain_i(master),.noise_floor_i(16'd0),.gate_ratio_i(16'd8192),
      .bin_addr_i(addr),.bin_wdata_i(wd),.bin_we_i(we),.bin_bank_i(bank),.bank_commit_i(commit),.bank_active_o(active));
    function automatic int gain(input int style,k);
      int j;
      j=(k>128)?256-k:k;
      if(j==128) j=127;
      if(style==0) return 16384;
      return 4000+style*1000+j*37;
    endfunction
    always @(negedge clk) if(rst && ov) begin
      if(received>=sent || ox !== 16'(expected[received]) || oy !== 0 || ol !== (received%256==255))
        $fatal(1,"Frame mismatch sample=%0d value=%0d expected=%0d",received,ox,expected[received]);
      received++;
    end
    initial begin
      int next_style,old_bank,old_master,new_master;
      repeat(4) @(negedge clk); #1;rst=1;
      // Every possible commit position, including first and final bin.
      for(int position=0;position<256;position++) begin
        next_style=1+position%2;
        old_bank=active;
        bank=!active;
        for(int j=0;j<128;j++) begin
          @(negedge clk); #1;we=1;addr=j;wd=gain(next_style,j);iv=0;
        end
        @(negedge clk); #1;we=0;
        old_master=16384;new_master=8192;
        for(int frame=0;frame<2;frame++) begin
          for(int k=0;k<256;k++) begin
            @(negedge clk); #1;
            iv=1;last=(k==255);commit=(frame==0 && k==position);
            master=(frame==0 && k<position)?old_master:new_master;
            if(frame==0 && position!=0) expected[sent]=gain(current_style,k);
            else expected[sent]=gain(next_style,k)/2;
            sent++;
            @(posedge clk); #1;
            if(frame==0 && position!=0 && active!==old_bank)
              $fatal(1,"Bank changed inside frame at %0d",k);
          end
        end
        @(negedge clk); #1;iv=0;last=0;commit=0;
        repeat(10) @(negedge clk);
        if(active!==bank[0]) $fatal(1,"Missing bank acknowledgement");
        current_style=next_style;
      end
      if(received!=sent) $fatal(1,"Lost samples");
      $display("FRAME_MODE_PASS %0d bins, all 256 commit positions",received);
      test_done=1;$finish;
    end
    initial begin #3000000;$fatal(1,"Frame test timeout");end
endmodule
