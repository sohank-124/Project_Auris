// Verilator lint-only interfaces; never use for synthesis or simulation.
`timescale 1ns/1ps

module fft_256_core (
input  wire        aclk,
    input  wire        aresetn,

    
    input  wire [31:0] s_axis_data_tdata,
    input  wire        s_axis_data_tvalid,
    output wire        s_axis_data_tready,
    input  wire        s_axis_data_tlast,

    
    input  wire [7:0]  s_axis_config_tdata,
    input  wire        s_axis_config_tvalid,
    output wire        s_axis_config_tready,

    
    output wire [31:0] m_axis_data_tdata,
    output wire [7:0]  m_axis_data_tuser,
    output wire        m_axis_data_tvalid,
    output wire        m_axis_data_tlast,

    
    output wire [7:0]  m_axis_status_tdata,
    output wire        m_axis_status_tvalid,

    
    output wire        event_frame_started,
    output wire        event_tlast_unexpected,
    output wire        event_data_in_channel_halt,
 output wire event_tlast_missing
);
endmodule

module ifft_256_core (
input  wire        aclk,
    input  wire        aresetn,

    
    input  wire [31:0] s_axis_data_tdata,
    input  wire        s_axis_data_tvalid,
    output wire        s_axis_data_tready,
    input  wire        s_axis_data_tlast,

    
    input  wire [7:0]  s_axis_config_tdata,
    input  wire        s_axis_config_tvalid,
    output wire        s_axis_config_tready,

    
    output wire [31:0] m_axis_data_tdata,
    output wire [7:0]  m_axis_data_tuser,
    output wire        m_axis_data_tvalid,
    output wire        m_axis_data_tlast,

    
    output wire [7:0]  m_axis_status_tdata,
    output wire        m_axis_status_tvalid,

    
    output wire        event_frame_started,
    output wire        event_tlast_unexpected,
    output wire        event_data_in_channel_halt,
 output wire event_tlast_missing
);
endmodule

module BUFG(input wire I, output wire O);
endmodule

module MMCME2_BASE #(
 parameter BANDWIDTH = "OPTIMIZED",
 parameter CLKFBOUT_MULT_F = 50.0,
 parameter CLKFBOUT_PHASE = 0.0,
 parameter CLKIN1_PERIOD = 83.333,
 parameter CLKOUT0_DIVIDE_F = 6.25,
 parameter CLKOUT0_DUTY_CYCLE = 0.5,
 parameter CLKOUT0_PHASE = 0.0,
 parameter CLKOUT1_DIVIDE = 1,
 parameter CLKOUT1_DUTY_CYCLE = 0.5,
 parameter CLKOUT1_PHASE = 0.0,
 parameter CLKOUT2_DIVIDE = 1,
 parameter CLKOUT2_DUTY_CYCLE = 0.5,
 parameter CLKOUT2_PHASE = 0.0,
 parameter CLKOUT3_DIVIDE = 1,
 parameter CLKOUT3_DUTY_CYCLE = 0.5,
 parameter CLKOUT3_PHASE = 0.0,
 parameter CLKOUT4_DIVIDE = 1,
 parameter CLKOUT4_DUTY_CYCLE = 0.5,
 parameter CLKOUT4_PHASE = 0.0,
 parameter CLKOUT5_DIVIDE = 1,
 parameter CLKOUT5_DUTY_CYCLE = 0.5,
 parameter CLKOUT5_PHASE = 0.0,
 parameter CLKOUT6_DIVIDE = 1,
 parameter CLKOUT6_DUTY_CYCLE = 0.5,
 parameter CLKOUT6_PHASE = 0.0,
 parameter DIVCLK_DIVIDE = 1,
 parameter REF_JITTER1 = 0.010,
 parameter STARTUP_WAIT = "FALSE"
)(
 input wire CLKIN1, CLKFBIN, RST, PWRDWN,
 output wire CLKFBOUT, CLKOUT0, CLKOUT0B, CLKOUT1, CLKOUT1B,
 output wire CLKOUT2, CLKOUT2B, CLKOUT3, CLKOUT3B,
 output wire CLKOUT4, CLKOUT5, CLKOUT6, LOCKED
);
endmodule
