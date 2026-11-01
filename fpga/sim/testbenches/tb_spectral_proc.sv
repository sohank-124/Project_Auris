`timescale 1ns/1ps
module tb_spectral_proc;
    logic clk=0, rst=0, iv=0, last=0, we=0, commit=0;
    logic test_done=0;
    logic [15:0] x=0,y=0,master=16384,noise=0,ratio=8192,wd=0;
    logic [6:0] addr=0;
    logic [1:0] bank=1;
    wire [15:0] ox,oy;
    wire ov,ol;
    int expected_re[0:8191],expected_im[0:8191];
    bit expected_last[0:8191];
    int sent=0,received=0;
    always #5 clk=~clk;
    spectral_proc dut(.clk_i(clk),.rst_n_i(rst),.in_re_i(x),.in_im_i(y),
        .in_v_i(iv),.in_last_i(last),.fft_exponent_i(8'd8),.out_re_o(ox),.out_im_o(oy),
        .out_v_o(ov),.out_last_o(ol),.mode_i(2'd0),.master_gain_i(master),
        .noise_floor_i(noise),.gate_ratio_i(ratio),.bin_addr_i(addr),
        .bin_wdata_i(wd),.bin_we_i(we),.bin_bank_i(bank),.bank_commit_i(commit),.bank_active_o());
    function automatic int reference_value(input int value,input longint unsigned gain);
        longint signed product,scaled;
        product=longint'(value)*longint'(gain);
        scaled=product >>> 14;
        if(scaled>32767) return 32767;
        if(scaled< -32768) return -32768;
        return int'(scaled);
    endfunction
    task automatic send(input int re_value,im_value,mg,nf,gr,bg,input bit end_frame);
        longint unsigned gain,power_value,threshold;
        @(negedge clk); #1;
        x=re_value; y=im_value; master=mg; noise=nf; ratio=gr;
        iv=1; last=end_frame;
        gain=(longint'(mg)*bg)/16384;
        power_value=longint'(re_value)*re_value+longint'(im_value)*im_value;
        threshold=longint'(nf)*16384;
        if(power_value<threshold) gain=(gain*gr)/16384;
        expected_re[sent]=reference_value(re_value,gain);
        expected_im[sent]=reference_value(im_value,gain);
        expected_last[sent]=end_frame;
        sent++;
    endtask
    always @(negedge clk) if(rst && ov) begin
        if(received>=sent) $fatal(1,"Unexpected spectral output");
        if($signed(ox)!==expected_re[received] || $signed(oy)!==expected_im[received] || ol!==expected_last[received])
            $fatal(1,"Spectral sample %0d got (%0d,%0d,%b), expected (%0d,%0d,%b)",received,$signed(ox),$signed(oy),ol,expected_re[received],expected_im[received],expected_last[received]);
        received++;
    end
    initial begin
        int bg;
        repeat(4) @(negedge clk); #1; rst=1;
        // Populate only the inactive bank, then commit at a frame boundary.
        for(int phase=0;phase<3;phase++) begin
            bg=(phase==0)?16384:((phase==1)?26214:65535);
            for(int k=0;k<128;k++) begin
                @(negedge clk); #1; iv=0; we=1;addr=k;wd=bg;
            end
            @(negedge clk); #1; we=0;commit=1;
            @(negedge clk); #1;commit=0;
            for(int k=0;k<2048;k++) begin
                case(k/256)
                    0: send(30000,-30000,16384,0,8192,bg,k%256==255);
                    1: send(2048,0,16384,4096,8192,bg,k%256==255);
                    2: send(100,-100,0,65535,8192,bg,k%256==255);
                    3: send(-32768,-32768,65535,65535,16384,bg,k%256==255);
                    4: send(8192,0,16384,4096,0,bg,k%256==255);
                    5: send(8191,0,16384,4096,0,bg,k%256==255);
                    6: send(1,-1,65535,65535,65535,bg,k%256==255);
                    7: send((k*997)%65536-32768,(k*313)%65536-32768,32767,16384,12288,bg,k%256==255);
                endcase
                if(k%11==0) begin @(negedge clk); #1; iv=0;last=0; end
            end
            @(negedge clk); #1;iv=0;last=0;
            repeat(10) @(negedge clk);
            bank=bank^1;
        end
        if(received!=sent) $fatal(1,"Missing spectral outputs %0d/%0d",received,sent);
        $display("SPECTRAL_PASS %0d exact complex comparisons",received);
        test_done=1;
        $finish;
    end
    initial begin #200000; $fatal(1,"Spectral timeout"); end
endmodule
