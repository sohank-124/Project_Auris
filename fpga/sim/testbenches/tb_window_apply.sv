`timescale 1ns/1ps
module tb_window_apply;
    logic clk=0, rst_n=0, in_v=0, frame_start=0;
    logic [23:0] in_l=0;
    wire [15:0] out_re,out_im;
    wire out_v;
    logic test_done=0;
    int expected[0:2047];
    int sent=0, received=0;
    always #5 clk=~clk;
    window_apply dut(.clk_i(clk),.rst_n_i(rst_n),.in_l_i(in_l),.in_r_i(24'd0),
        .in_v_i(in_v),.frame_start_i(frame_start),.out_re_o(out_re),.out_im_o(out_im),.out_v_o(out_v));
    always @(negedge clk) if (rst_n && out_v) begin
        if (received >= sent) $fatal(1,"Unexpected output");
        if ($signed(out_re) !== expected[received] || out_im !== 0)
            $fatal(1,"Window sample %0d got %0d expected %0d", received,$signed(out_re),expected[received]);
        received++;
    end
    initial begin
        int sample_value, coeff;
        repeat(4) @(negedge clk);
        #1 rst_n=1;
        for (int frame=0; frame<6; frame++) begin
            for (int n=0;n<256;n++) begin
                @(negedge clk); #1;
                if (frame%2 && n%3==0) begin
                    in_v=0; frame_start=0;
                    @(negedge clk); #1;
                end
                case(frame)
                    0: sample_value=16384;
                    1: sample_value=-32768;
                    2: sample_value=32767;
                    default: sample_value=((n*997+frame*12345)%65536)-32768;
                endcase
                coeff=$rtoi((0.5-0.5*$cos(2.0*3.141592653589793*n/256.0))*16384.0+0.5);
                expected[sent]=(sample_value*coeff) >>> 14;
                sent++;
                in_l=sample_value <<< 8;
                in_v=1; frame_start=(n==0);
            end
        end
        @(negedge clk); #1; in_v=0; frame_start=0;
        repeat(5) @(negedge clk);
        if(received != sent) $fatal(1,"Missing window outputs: %0d/%0d",received,sent);
        $display("WINDOW_PASS %0d exact signed comparisons",received);
        test_done=1;
        $finish;
    end
    initial begin #100000; $fatal(1,"Window timeout"); end
endmodule
