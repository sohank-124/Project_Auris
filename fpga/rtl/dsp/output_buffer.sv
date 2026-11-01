// Two owned blocks in one synchronous-read RAM. Preserve unread blocks;
// reject a whole incoming block when no free half exists at its first sample.
`default_nettype none
`timescale 1ns/1ps
module output_buffer import auris_pkg::*; #(
    parameter int unsigned HALF = GAIN_TABLE_DEPTH,
    parameter int unsigned DATA_W = I2S_DATA_W
)(
    input wire clk_i, rst_n_i,
    input wire [DATA_W-1:0] in_l_i, in_r_i,
    input wire in_v_i, sample_clk_en_i,
    output logic [DATA_W-1:0] out_l_o, out_r_o,
    output logic out_v_o, underflow_o, overflow_o
);
    localparam int AW = $clog2(HALF);
    (* ram_style = "block" *) logic [2*DATA_W-1:0] mem [0:2*HALF-1];
    logic [1:0] ready;
    logic wr_buf, rd_buf, dropping;
    logic [AW-1:0] wr_ptr, rd_ptr;
    logic rd_en_q, rd_valid_q;
    logic [2*DATA_W-1:0] rd_data;
    // A rejected block stays rejected even if a half becomes free midway.
    wire reject = (wr_ptr == 0) ? ready[wr_buf] : dropping;
    wire write_accept = rst_n_i && in_v_i && !reject;
    wire read_accept = rst_n_i && sample_clk_en_i && ready[rd_buf];

    always_ff @(posedge clk_i) begin
        if (write_accept) mem[{wr_buf,wr_ptr}] <= {in_r_i,in_l_i};
        if (read_accept) rd_data <= mem[{rd_buf,rd_ptr}];
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ready <= '0;
            wr_buf <= 0; rd_buf <= 0;
            wr_ptr <= '0; rd_ptr <= '0;
            dropping <= 0; overflow_o <= 0;
        end else begin
            if (read_accept) begin
                if (rd_ptr == HALF-1) begin
                    ready[rd_buf] <= 0;
                    rd_ptr <= '0;
                    rd_buf <= ~rd_buf;
                end else rd_ptr <= rd_ptr + 1'b1;
            end
            if (in_v_i) begin
                if (wr_ptr == 0) begin
                    dropping <= reject;
                    if (reject) overflow_o <= 1;
                end
                if (wr_ptr == HALF-1) begin
                    wr_ptr <= '0;
                    dropping <= 0;
                    if (!reject) begin
                        ready[wr_buf] <= 1;
                        wr_buf <= ~wr_buf;
                    end
                end else wr_ptr <= wr_ptr + 1'b1;
            end
        end
    end

    // RAM capture followed by output capture: preserve existing read latency.
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            out_l_o <= '0; out_r_o <= '0; out_v_o <= 0;
            underflow_o <= 0; rd_en_q <= 0; rd_valid_q <= 0;
        end else begin
            rd_en_q <= sample_clk_en_i;
            rd_valid_q <= read_accept;
            out_v_o <= rd_valid_q;
            if (rd_en_q) begin
                if (rd_valid_q) {out_r_o,out_l_o} <= rd_data;
                else begin
                    out_l_o <= '0; out_r_o <= '0;
                    underflow_o <= 1;
                end
            end
        end
    end
    initial begin
        if (HALF < 2 || (1 << AW) != HALF || DATA_W < 1)
            $fatal(1, "output_buffer requires power-of-two HALF >= 2 and positive DATA_W");
    end
endmodule
`default_nettype wire
