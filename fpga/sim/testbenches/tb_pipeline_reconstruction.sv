`timescale 1ns/1ps
module tb_pipeline_reconstruction;
 logic clk=0,rst=0,iv=0;logic [23:0] sample=0;
 wire [23:0] ol,orr;wire ov;wire [31:0] frames;wire [7:0] errors;
 logic test_done=0;
 localparam int INPUT_COUNT=2048;
 // 8192 raw 24-bit counts = 0.098% of positive full scale. This
 // acceptance bound covers quantization; it is not an audio-quality claim.
 localparam int ERROR_BOUND=8192;
 int source[0:INPUT_COUNT-1];
 int fft_exponents[0:31];
 int accepted_fft=0,accepted_ifft=0,fft_out=0,ifft_out=0,ola_count=0,output_count=0;
 int maximum_ola_error=0,maximum_output_error=0,distinct_exponents=0;
 always #5.208333 clk=~clk;
 dsp_pipeline dut(.clk_i(clk),.rst_n_i(rst),.sample_l_i(sample),.sample_r_i(sample),.sample_valid_i(iv),
 .out_l_o(ol),.out_r_o(orr),.out_valid_o(ov),.mode_i(2'd0),.master_gain_i(24'd16384),
 .noise_floor_i(24'd0),.gate_ratio_i(24'd16384),.dsp_enable_i(1'b1),.volume_i(5'd31),
 .gain_addr_i(7'd0),.gain_wdata_i(16'd0),.gain_we_i(1'b0),.gain_bank_i(2'd0),.bank_commit_i(1'b0),
 .gain_bank_active_o(),.peak_in_o(),.peak_out_o(),.frame_count_o(frames),.error_flags_o(errors),.clip_event_o());
 task automatic compare_sample(input int ordinal,input logic [23:0] actual,input bit final_output);
   int expected,err;
   expected=(ordinal<128)?0:source[ordinal-128];
   if($isunknown(actual))$fatal(1,"Unknown reconstructed sample %0d",ordinal);
   err=$signed(actual)-expected;if(err<0)err=-err;
   if(err>ERROR_BOUND)$fatal(1,"Reconstruction index=%0d final=%b got=%0d expected=%0d error=%0d",ordinal,final_output,$signed(actual),expected,err);
   if(final_output) begin if(err>maximum_output_error)maximum_output_error=err;end
   else if(err>maximum_ola_error)maximum_ola_error=err;
 endtask
 always @(posedge clk) if(rst) begin
   if(dut.fft_fifo_valid&&dut.fft_data_ready) begin
     if(dut.fft_fifo_data[32] !== (accepted_fft%256==255))$fatal(1,"FFT input marker");accepted_fft++;
   end
   if(dut.ifft_fifo_valid&&dut.ifft_data_ready) begin
     if(dut.ifft_fifo_data[32] !== (accepted_ifft%256==255))$fatal(1,"IFFT input marker");accepted_ifft++;
   end
   if(dut.fft_v) begin
     if(fft_out%256==0) begin
       fft_exponents[fft_out/256]=dut.fft_blk_exp;
       if(fft_out>0 && dut.fft_blk_exp!=fft_exponents[fft_out/256-1])distinct_exponents++;
     end
     fft_out++;
   end
   if(dut.ifft_v) begin
     if(dut.fft_exp_aligned!==8'(fft_exponents[ifft_out/256]))$fatal(1,"Exponent association failure");
     ifft_out++;
   end
 end
 always @(negedge clk) if(rst) begin
   if(dut.ola_v) begin
     compare_sample(ola_count,dut.ola_l,0);
     if(dut.ola_r!==dut.ola_l)$fatal(1,"OLA stereo mismatch");ola_count++;
   end
   if(ov) begin
     compare_sample(output_count,ol,1);
     if(orr!==ol)$fatal(1,"Output stereo mismatch");output_count++;
   end
 end
 initial begin
   for(int n=0;n<INPUT_COUNT;n++) begin
     case(n/256)
       0:source[n]=0;
       1:source[n]=262144;
       2:source[n]=((n%256)-128)*8192;
       3:source[n]=(n%256==0)?4194304:0;
       4:source[n]=$rtoi(1048576.0*$sin(2.0*3.141592653589793*8*n/256.0));
       5:source[n]=$rtoi(2097152.0*$sin(2.0*3.141592653589793*8.5*n/256.0));
       6:source[n]=$rtoi(32768.0*$sin(2.0*3.141592653589793*3*n/256.0));
       7:source[n]=0;
     endcase
   end
   repeat(20)@(negedge clk);#1;rst=1;
   for(int hop=0;hop<16;hop++) begin
     for(int k=0;k<128;k++) begin
       @(negedge clk);#1;iv=1;sample=source[hop*128+k];
     end
     @(negedge clk);#1;iv=0;
     // Let the BRAM frame and realtime transforms drain before the next hop.
     repeat(4096)@(negedge clk);
   end
   repeat(4000)@(negedge clk);
   if(accepted_fft!=4096||accepted_ifft!=4096||fft_out!=4096||ifft_out!=4096||ola_count!=2048||output_count!=1920||frames!=16)
     $fatal(1,"Counts fft=%0d ifft=%0d fo=%0d io=%0d ola=%0d out=%0d frames=%0d",accepted_fft,accepted_ifft,fft_out,ifft_out,ola_count,output_count,frames);
   // Startup output underflow is expected before the first frame is ready.
   if($isunknown({errors,frames}) || (errors & 8'hfd)!=0 || distinct_exponents<2)$fatal(1,"Unexpected errors or insufficient exponent variation %h changes=%0d",errors,distinct_exponents);
   $display("VENDOR_RECONSTRUCTION_PASS transaction_level_frames=%0d OLA=%0d output=%0d max_ola_error=%0d max_output_error=%0d bound=%0d exponent_changes=%0d",frames,ola_count,output_count,maximum_ola_error,maximum_output_error,ERROR_BOUND,distinct_exponents);
   test_done=1;$finish;
 end
 initial begin #50000000;$fatal(1,"Reconstruction timeout");end
endmodule
