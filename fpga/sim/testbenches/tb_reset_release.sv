`timescale 1ns/1ps
module tb_reset_release;
  logic clk=0, running=1, source_n=0;
  wire r2,r16,rf;
  logic test_done=0;
  integer rises=0, falls=0, sessions=0;
  realtime last_rise=0,last_fall=0;
  always #5 if(running) clk=~clk;
  reset_release a(.clk_i(clk),.async_rst_n_i(source_n),.rst_n_o(r2));
  reset_sync_stretch #(.STRETCH_CYCLES(16)) b(.dst_clk_i(clk),.src_rst_n_i(source_n),.dst_rst_n_o(r16));
  reset_release #(.FALLING_EDGE(1)) c(.clk_i(clk),.async_rst_n_i(source_n),.rst_n_o(rf));
  always @(posedge clk or negedge source_n) begin
    if(!source_n) rises=0;
    else begin
      rises++; last_rise=$realtime; #0.001;
      if(r2 !== (rises>=2) || r16 !== (rises>=16)) $fatal(1,"Release edge count rises=%0d",rises);
    end
  end
  always @(negedge clk or negedge source_n) begin
    if(!source_n) falls=0;
    else begin
      falls++; last_fall=$realtime; #0.001;
      if(rf !== (falls>=2)) $fatal(1,"Falling release count");
    end
  end
  always @(posedge r2 or posedge r16) if(source_n && $realtime!=last_rise) $fatal(1,"Off-edge rising reset release");
  always @(posedge rf) if(source_n && $realtime!=last_fall) $fatal(1,"Off-edge falling reset release");

  logic board_clk=0, inject_lock=0;
  wire dsp,bclk,lrclk,locked;
  integer dsp_since_lock=0, fall_since_lock=0, bclk_edges=0;
  always #41.666667 board_clk=~board_clk;
  clk_gen clocks(.clk_in1(board_clk),.clk_dsp_o(dsp),.i2s_bclk_o(bclk),.i2s_lrclk_o(lrclk),.locked(locked));
  always @(posedge dsp or negedge inject_lock) begin
    if(!inject_lock) dsp_since_lock=0;
    else dsp_since_lock++;
  end
  always @(posedge bclk) if(inject_lock) begin
    if(dsp_since_lock<3) $fatal(1,"BCLK state released before two synchronization edges");
    bclk_edges++;
  end
  always @(negedge bclk or negedge inject_lock) begin
    if(!inject_lock) fall_since_lock=0;
    else begin
      fall_since_lock++; #0.001;
      if(fall_since_lock<=2 && clocks.lrclk_cnt!==0) $fatal(1,"LRCLK state released early");
    end
  end
  task automatic check_asserted;
    #0.002;
    if({r2,r16,rf} !== 3'b000) $fatal(1,"Async reset assertion failed");
  endtask
  initial begin
    force clocks.mmcm_locked=inject_lock;
    #1; source_n=0; check_asserted();
    for(int phase=0;phase<20;phase++) begin
      @(negedge clk); #(0.15+phase*0.23); source_n=1;
      repeat(18) @(negedge clk);
      #0.07; source_n=0; check_asserted(); sessions++;
    end
    @(negedge clk); running=0;
    #2; source_n=1; #53;
    if({r2,r16,rf}!==0) $fatal(1,"Reset released without a clock");
    source_n=0; check_asserted(); source_n=1; running=1;
    repeat(18) @(negedge clk);
    wait(clocks.u_mmcm.LOCKED===1);
    for(int phase=0;phase<8;phase++) begin
      @(negedge dsp); #(0.2+phase*0.31); inject_lock=1;
      repeat(150) @(negedge bclk);
      #1.19; inject_lock=0; #0.01;
      if(clocks.bclk_cnt!==0 || clocks.lrclk_cnt!==0 || bclk!==0 || lrclk!==0)
        $fatal(1,"Lock loss did not clear clock state");
      repeat(4) @(negedge dsp);
    end
    if(bclk_edges<500) $fatal(1,"Insufficient restarted traffic");
    $display("RESET_RELEASE_PASS phases=%0d lock_restarts=8 bclk_edges=%0d stopped_clock=1",sessions,bclk_edges);
    test_done=1; $finish;
  end
  initial begin #1000000; $fatal(1,"Reset test watchdog"); end
endmodule
