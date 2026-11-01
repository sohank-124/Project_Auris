// 256-point, 50% overlap-add with per-frame BFP exponent restoration.
`default_nettype none
`timescale 1ns / 1ps

module overlap_add import auris_pkg::*; #(
    parameter int unsigned LEN     = FFT_LEN,
    parameter int unsigned HALF    = LEN / 2,
    parameter int unsigned DATA_W  = I2S_DATA_W
) (
    input  wire                    clk_i,
    input  wire                    rst_n_i,

    input  wire [DATA_W-1:0]       in_l_i,
    input  wire [DATA_W-1:0]       in_r_i,
    input  wire                    in_v_i,
    input  wire                    in_last_i,

    output logic [DATA_W-1:0]      out_l_o,
    output logic [DATA_W-1:0]      out_r_o,
    output logic                   out_v_o,

    output logic                   frame_done_o,

    input  wire [7:0]              scale_factor_i   // BFP exponent: E_fft + E_ifft
);

    // History stores raw mantissas; its exponent belongs to the old frame.
    // The transform pair's N=256 gain cancels the input's 24->16 bit shift.
    // Therefore restore only E_fft+E_ifft, with no extra fixed gain.
    localparam int ACC_W = DATA_W + 33;
    (* ram_style = "block" *) logic [2*DATA_W-1:0] history [0:HALF-1];
    logic [7:0] sample_cnt, history_scale;
    logic history_valid;
    logic [2*DATA_W-1:0] history_q;
    logic signed [DATA_W-1:0] current_l, current_r;
    logic [7:0] current_scale_q, history_scale_q;
    logic use_history_q, read_valid, sum_valid;
    logic signed [ACC_W-1:0] sum_l, sum_r;

    function automatic logic signed [ACC_W-1:0] restore(
        input logic signed [DATA_W-1:0] value, input logic [7:0] exponent);
        logic signed [ACC_W-1:0] wide;
        begin
            wide = value;
            restore = wide <<< ((exponent > 32) ? 32 : exponent);
        end
    endfunction
    function automatic logic [DATA_W-1:0] saturate(
        input logic signed [ACC_W-1:0] value);
        if (value > 8388607) return 24'h7fffff;
        else if (value < -8388608) return 24'h800000;
        else return value[DATA_W-1:0];
    endfunction

    // No array reset: invalidate history on reset without destroying BRAM inference.
    always_ff @(posedge clk_i) begin
        if (rst_n_i && in_v_i) begin
            if (sample_cnt < HALF) history_q <= history[sample_cnt[6:0]];
            else history[sample_cnt[6:0]] <= {in_r_i,in_l_i};
        end
    end
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            sample_cnt <= 0;
            history_scale <= 0;
            history_valid <= 0;
            current_l <= 0; current_r <= 0;
            current_scale_q <= 0; history_scale_q <= 0;
            use_history_q <= 0;
            read_valid <= 0; sum_valid <= 0;
            sum_l <= 0; sum_r <= 0;
            out_l_o <= 0; out_r_o <= 0; out_v_o <= 0;
            frame_done_o <= 0;
        end else begin
            read_valid <= in_v_i && (sample_cnt < HALF);
            sum_valid <= read_valid;
            out_v_o <= sum_valid;
            frame_done_o <= in_v_i && in_last_i;
            if (in_v_i) begin
                current_l <= in_l_i; current_r <= in_r_i;
                current_scale_q <= scale_factor_i;
                history_scale_q <= history_scale;
                use_history_q <= history_valid;
                sample_cnt <= sample_cnt + 1'b1;
                if (in_last_i) begin
                    sample_cnt <= 0;
                    history_valid <= (sample_cnt == LEN-1);
                    history_scale <= scale_factor_i;
                end
            end
            if (read_valid) begin
                sum_l <= restore(current_l,current_scale_q) +
                    (use_history_q ? restore($signed(history_q[DATA_W-1:0]),history_scale_q) : 0);
                sum_r <= restore(current_r,current_scale_q) +
                    (use_history_q ? restore($signed(history_q[2*DATA_W-1:DATA_W]),history_scale_q) : 0);
            end
            if (sum_valid) begin
                out_l_o <= saturate(sum_l);
                out_r_o <= saturate(sum_r);
            end
        end
    end
    initial if (LEN != 256 || HALF != 128 || DATA_W != 24)
        $fatal(1, "overlap_add supports 256/128/24 only");
`ifndef SYNTHESIS
    always @(posedge clk_i) if (rst_n_i && in_v_i) begin
        if (in_last_i != (sample_cnt == LEN-1)) $fatal(1, "OLA malformed frame");
        if (scale_factor_i > 32) $fatal(1, "OLA exponent exceeds supported range");
    end
`endif
endmodule : overlap_add
`default_nettype wire
