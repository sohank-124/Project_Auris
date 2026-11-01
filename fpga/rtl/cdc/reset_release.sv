// Asynchronous assertion, clock-edge-synchronized release. Only the final
// flip-flop drives reset consumers: no combinational reset reduction tree.
`default_nettype none
`timescale 1ns/1ps
module reset_release #(
    parameter int unsigned STAGES = 2,
    parameter bit FALLING_EDGE = 1'b0
) (
    input  wire clk_i,
    input  wire async_rst_n_i,
    output wire rst_n_o
);
    // Only the metastability-catching pair requires tight placement. Tagging
    // a long delay pipe ASYNC_REG would create an impossible single-slice group.
    (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
    logic [1:0] sync_pipe;
    generate
        if (FALLING_EDGE) begin : g_sync_falling
            always_ff @(negedge clk_i or negedge async_rst_n_i) begin
                if (!async_rst_n_i) sync_pipe <= '0;
                else sync_pipe <= {sync_pipe[0], 1'b1};
            end
        end else begin : g_sync_rising
            always_ff @(posedge clk_i or negedge async_rst_n_i) begin
                if (!async_rst_n_i) sync_pipe <= '0;
                else sync_pipe <= {sync_pipe[0], 1'b1};
            end
        end
        if (STAGES > 2) begin : g_stretch
            localparam int unsigned TAIL = STAGES - 2;
            (* SHREG_EXTRACT = "NO" *) logic [TAIL-1:0] stretch_pipe;
            if (FALLING_EDGE) begin : g_falling
                always_ff @(negedge clk_i or negedge async_rst_n_i) begin
                    if (!async_rst_n_i) stretch_pipe <= '0;
                    else stretch_pipe <= (stretch_pipe << 1) | TAIL'(sync_pipe[1]);
                end
            end else begin : g_rising
                always_ff @(posedge clk_i or negedge async_rst_n_i) begin
                    if (!async_rst_n_i) stretch_pipe <= '0;
                    else stretch_pipe <= (stretch_pipe << 1) | TAIL'(sync_pipe[1]);
                end
            end
            assign rst_n_o = stretch_pipe[TAIL-1];
        end else begin : g_unstretched
            assign rst_n_o = sync_pipe[1];
        end
    endgenerate
    initial if (STAGES < 2) $fatal(1, "reset_release requires STAGES >= 2");
endmodule
`default_nettype wire
