# Run with Vivado -mode batch -source tools/validation/verify_suite_faults.tcl.
# Compile the actual acceptance benches against controlled broken/valid fixtures.
set root [file normalize [file join [file dirname [info script]] ../..]]
set audit [file join $root .audit_verification suite_fault_regression]
file mkdir $audit
source [file join $root fpga scripts simulation_common.tcl]
set stub {
`timescale 1ns/1ps
module pipeline_stub(input clk);
 integer cycle=0;
 always @(posedge clk) cycle<=cycle+1;
 wire sample_valid_i=(cycle>=10 && cycle<138);
 wire fft_fifo_valid=VALID;
 wire ifft_fifo_valid=fft_fifo_valid;
 wire fft_data_ready=1, ifft_data_ready=1;
 wire [32:0] fft_fifo_data={MARKER,32'd0};
 wire [32:0] ifft_fifo_data=fft_fifo_data;
 wire fft_v=fft_fifo_valid, ifft_v=fft_fifo_valid;
 wire fft_last=fft_fifo_data[32], ifft_last=fft_fifo_data[32];
 wire fft_fifo_overflow=FLAG, ifft_fifo_overflow=FLAG;
endmodule
module top #(parameter SELF_TEST_ENABLE=1,SELF_TEST_LOOPBACK_ENABLE=1,SELF_TEST_PASS_BITS=8192)
 (input clk_12mhz,input [3:0] btn_i,input i2s_adc_data_i,
 output i2s_bclk_o,i2s_lrclk_o,i2s_dac_data_o,status_led_o,status_clip_o,led_rgb_r,led_rgb_g,led_rgb_b);
 reg clk_96mhz=0; always #5.208333 clk_96mhz=~clk_96mhz;
 wire rst_dsp_n=1;
 assign {i2s_bclk_o,i2s_lrclk_o,i2s_dac_data_o,status_led_o}=0;
 assign status_clip_o=0;
 assign {led_rgb_r,led_rgb_g,led_rgb_b}=RGB;
 pipeline_stub u_dsp_pipeline(clk_96mhz);
endmodule
}
set failures {}
foreach spec {
    {handshake_valid tb_xfft_handshake 0}
    {handshake_unknown tb_xfft_handshake 1}
    {handshake_stalled tb_xfft_handshake 1}
    {handshake_bad_marker tb_xfft_handshake 1}
    {handshake_missing tb_xfft_handshake 1}
    {handshake_extra tb_xfft_handshake 1}
    {selftest_valid tb_top_selftest 0}
    {selftest_unknown tb_top_selftest 1}
    {fatal tb_contract 1}
    {nonfatal_error tb_contract 1}
    {timeout tb_contract 1}
    {early_finish tb_contract 1}
} {
    lassign $spec name bench expect_failure
    set dir [file join $audit $name]
    file mkdir $dir
    set valid {(cycle>=200 && cycle<456)}
    set marker {(cycle==455)}
    set flag {1'b0}
    set rgb {3'b011}
    switch $name {
        handshake_unknown {set flag {1'bx}}
        handshake_stalled {set valid {1'b0}}
        handshake_bad_marker {set marker {1'b0}}
        handshake_missing {set valid {(cycle>=200 && cycle<455)}}
        handshake_extra {set valid {(cycle>=200 && cycle<457)}}
        selftest_unknown {set rgb {3'bxxx}}
    }
    set f [open [file join $dir fixture.sv] w]
    if {$bench eq "tb_contract"} {
        switch $name {
            fatal {set action {$fatal(1,"Injected numerical failure");}}
            nonfatal_error {set action {$error("Injected nonfatal error"); test_done=1; $finish;}}
            timeout {set action {#100; $fatal(1,"Injected watchdog timeout");}}
            early_finish {set action {$finish;}}
        }
        puts $f "module tb_contract; reg test_done=0; initial begin #10; $action end endmodule"
    } else {
        puts $f [string map [list VALID $valid MARKER $marker FLAG $flag RGB $rgb] $stub]
    }
    close $f
    create_project -force $name [file join $dir project] -part xc7s25csga324-1
    add_files [file join $dir fixture.sv]
    if {$bench ne "tb_contract"} {
        add_files -fileset sim_1 [file join $root fpga sim testbenches ${bench}.sv]
    }
    set_property top $bench [get_filesets sim_1]
    set failed [catch {auris_run_simulation /$bench/test_done {15 ms}} reason]
    # Setup/compile errors are not evidence that a fault was detected.
    if {$failed && $expect_failure &&
        ![string match "Simulator reported an error:*" $reason] &&
        $reason ne "Simulation did not reach successful completion"} {
        lappend failures ${name}_infrastructure
    }
    puts "FAULT_CASE $name rejected=$failed expected=$expect_failure reason=<$reason>"
    if {$failed != $expect_failure} { lappend failures $name }
    catch {close_sim -force}
    close_project
}
if {[llength $failures]} {error "Fault regression failed: $failures"}
puts "SUITE_FAULT_REGRESSION_PASS"
exit 0
