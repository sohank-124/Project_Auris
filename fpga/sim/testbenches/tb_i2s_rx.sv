`timescale 1ns/1ps
module tb_i2s_rx;
    tb_i2s_standard #(.CHECK_RX(1'b1), .CHECK_TX(1'b0)) checks();
    // Completion is owned by checks; Tcl reads checks/test_done directly.
endmodule
