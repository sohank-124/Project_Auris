// =============================================================================
// File:        clk_gen.sv
// Project:     Project Auris
// Module:      clk_gen
// Description: MMCM wrapper that multiplies the 12 MHz onboard oscillator up
//              to a 96 MHz DSP clock.  The `locked` output is asserted once
//              the MMCM has achieved lock and is used by the top-level
//              reset generator to gate the system reset.
//
//              Implemented with the MMCME2_BASE primitive directly so the
//              design is portable across Vivado versions without depending
//              on a generated Clocking Wizard .xci file.
//
//              Target:  Spartan-7 XC7S25-1CSGA225C
//                       (MMCME2_BASE is available; PLL_BASE is not)
//
// Author:      [generated]
// Created:     2026-07
// =============================================================================
`default_nettype none
`timescale 1ns / 1ps

module clk_gen (
    input  wire clk_in1,    // 12 MHz from onboard oscillator
    output wire clk_out1,   // 96 MHz DSP clock
    output wire locked      // MMCM lock indicator (high when locked)
);

    // -------------------------------------------------------------------------
    // Internal nets: feedback clock, MMCM control/status
    // -------------------------------------------------------------------------
    logic clk_fb;           // MMCM feedback (driven onto a global BUFG)
    logic clk_fb_bufg;      // BUFG-buffered copy of clk_fb for the feedback path
    logic clk_out1_bufr;    // raw MMCM output before the output buffer
    logic mmcm_locked;      // MMCME2_BASE LOCKED pin

    // -------------------------------------------------------------------------
    // Global clock buffers
    // -------------------------------------------------------------------------
    // BUFG on the feedback path is mandatory for the MMCME2_BASE to
    // correctly model its internal feedback.
    BUFG bufg_fb (
        .I (clk_fb),
        .O (clk_fb_bufg)
    );

    // BUFG on the primary output — distributes the 96 MHz clock to the
    // DSP-domain logic across the whole device.
    BUFG bufg_out1 (
        .I (clk_out1_bufr),
        .O (clk_out1)
    );

    // -------------------------------------------------------------------------
    // MMCME2_BASE primitive
    // -------------------------------------------------------------------------
    // Configuration (matches the spec — see file header):
    //   CLKIN1_PERIOD   = 83.333 ns      (1 / 12 MHz, in ps: 83333)
    //   CLKFBOUT_MULT_F = 50.0           (VCO target = 12 * 50 / 1 = 600 MHz,
    //                                     at the legal MMCME2_BASE minimum)
    //   DIVCLK_DIVIDE   = 1              (no input division)
    //   CLKOUT0_DIVIDE_F= 6.25           (clk_out1 = 600 / 6.25 = 96 MHz)
    //   BANDWIDTH       = "OPTIMIZED"    (best jitter, OK for 96 MHz)
    //
    // The VCO is held at the Spartan-7 MMCME2_BASE minimum of 600 MHz so
    // the MMCM can lock.  clk_out1 is the final 96 MHz DSP clock.
    MMCME2_BASE #(
        .BANDWIDTH            ("OPTIMIZED"),
        .CLKFBOUT_MULT_F      (50.0),
        .CLKFBOUT_PHASE       (0.0),
        .CLKIN1_PERIOD        (83.333),
        .CLKOUT0_DIVIDE_F     (6.25),
        .CLKOUT0_DUTY_CYCLE   (0.5),
        .CLKOUT0_PHASE        (0.0),
        .CLKOUT1_DIVIDE       (1),
        .CLKOUT1_DUTY_CYCLE   (0.5),
        .CLKOUT1_PHASE        (0.0),
        .CLKOUT2_DIVIDE       (1),
        .CLKOUT2_DUTY_CYCLE   (0.5),
        .CLKOUT2_PHASE        (0.0),
        .CLKOUT3_DIVIDE       (1),
        .CLKOUT3_DUTY_CYCLE   (0.5),
        .CLKOUT3_PHASE        (0.0),
        .CLKOUT4_DIVIDE       (1),
        .CLKOUT4_DUTY_CYCLE   (0.5),
        .CLKOUT4_PHASE        (0.0),
        .CLKOUT5_DIVIDE       (1),
        .CLKOUT5_DUTY_CYCLE   (0.5),
        .CLKOUT5_PHASE        (0.0),
        .CLKOUT6_DIVIDE       (1),
        .CLKOUT6_DUTY_CYCLE   (0.5),
        .CLKOUT6_PHASE        (0.0),
        .DIVCLK_DIVIDE        (1),
        .REF_JITTER1          (0.010),
        .STARTUP_WAIT         ("FALSE")
    ) u_mmcm (
        // Clock inputs
        .CLKIN1    (clk_in1),
        .CLKFBIN   (clk_fb_bufg),
        // Outputs
        .CLKFBOUT  (clk_fb),
        .CLKOUT0   (clk_out1_bufr),
        .CLKOUT0B  (),
        .CLKOUT1   (),
        .CLKOUT1B  (),
        .CLKOUT2   (),
        .CLKOUT2B  (),
        .CLKOUT3   (),
        .CLKOUT3B  (),
        .CLKOUT4   (),
        .CLKOUT5   (),
        .CLKOUT6   (),
        // Status / control
        .LOCKED    (mmcm_locked),
        .RST       (1'b0),
        .PWRDWN    (1'b0)
    );

    // -------------------------------------------------------------------------
    // Output assignment
    // -------------------------------------------------------------------------
    // mmcm_locked is high once the MMCM has achieved lock.  Route it
    // directly to the top-level `locked` port.
    assign locked = mmcm_locked;

endmodule : clk_gen

`default_nettype wire
