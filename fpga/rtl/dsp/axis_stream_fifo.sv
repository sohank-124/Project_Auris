`default_nettype none
`timescale 1ns / 1ps

// Small elastic buffer for AXI-stream data entering a realtime XFFT core.
// The producer may continue for a few cycles while the core deasserts TREADY.
module axis_stream_fifo #(
    parameter int unsigned WIDTH = 33,
    parameter int unsigned DEPTH = 4
) (
    input  wire             clk_i,
    input  wire             rst_n_i,
    input  wire             in_valid_i,
    output wire             in_ready_o,
    input  wire [WIDTH-1:0] in_data_i,
    input  wire             out_ready_i,
    output wire             out_valid_o,
    output wire [WIDTH-1:0] out_data_o,
    output wire             overflow_o
);
    localparam int unsigned PTR_W = $clog2(DEPTH);
    localparam int unsigned CNT_W = $clog2(DEPTH + 1);

    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [PTR_W-1:0] wr_ptr;
    logic [PTR_W-1:0] rd_ptr;
    logic [CNT_W-1:0] count;
    logic             overflow;

    wire push = in_valid_i && in_ready_o;
    wire pop  = out_valid_o && out_ready_i;

    assign in_ready_o  = (count < DEPTH) || pop;
    assign out_valid_o = (count != 0);
    assign out_data_o  = mem[rd_ptr];
    assign overflow_o  = overflow;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            wr_ptr   <= '0;
            rd_ptr   <= '0;
            count    <= '0;
            overflow <= 1'b0;
        end else begin
            if (in_valid_i && !in_ready_o)
                overflow <= 1'b1;

            if (push) begin
                mem[wr_ptr] <= in_data_i;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            if (pop)
                rd_ptr <= rd_ptr + 1'b1;

            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ;
            endcase
        end
    end

    initial begin
        if (DEPTH < 2 || (1 << PTR_W) != DEPTH)
            $display("ERROR: axis_stream_fifo DEPTH must be a power of two >= 2");
    end
endmodule

`default_nettype wire