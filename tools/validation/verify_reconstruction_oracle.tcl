# Run sim_pipeline_reconstruction.tcl first to produce the project-local IP.
# Invoke the actual reconstruction comparison task with controlled samples.
set root [file normalize [file join [file dirname [info script]] ../..]]
set audit [file join $root .audit_verification reconstruction_oracle_faults]
file mkdir $audit
source [file join $root fpga scripts simulation_common.tcl]
set failures {}
foreach spec {{correct 24'd0 0} {wrong 24'h7fffff 1} {unknown 24'hxxxxxx 1}} {
    lassign $spec name sample expected_failure
    set dir [file join $audit $name]
    file mkdir $dir
    set channel [open [file join $dir oracle.sv] w]
    puts $channel {`timescale 1ns/1ps}
    puts $channel {module tb_oracle; logic test_done=0; tb_pipeline_reconstruction checks();}
    # Source[0] is initialized to silence by the real bench at time zero.
    puts $channel "initial begin #1; checks.compare_sample(128,$sample,0); test_done=1; \$finish; end endmodule"
    close $channel
    create_project -force oracle_$name [file join $dir project] -part xc7s25csga324-1
    add_files [file join $root fpga rtl]
    foreach core {fft_256_core ifft_256_core} {
        set xci [file join $root fpga vivado_proj sim_pipeline_reconstruction ip $core $core ${core}.xci]
        if {![file exists $xci]} {error "Run sim_pipeline_reconstruction first: missing $xci"}
        read_ip $xci
    }
    add_files -fileset sim_1 [file join $root fpga sim testbenches tb_pipeline_reconstruction.sv]
    add_files -fileset sim_1 [file join $dir oracle.sv]
    set_property top tb_oracle [get_filesets sim_1]
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1
    set failed [catch {auris_run_simulation /tb_oracle/test_done {1 us}} reason]
    puts "ORACLE_CASE $name rejected=$failed expected=$expected_failure reason=<$reason>"
    if {$failed != $expected_failure || ($failed && ![string match "Simulator reported an error:*" $reason])} {
        lappend failures $name
    }
    catch {close_sim -force}
    close_project
}
if {[llength $failures]} {error "Reconstruction oracle fault regression failed: $failures"}
puts "RECONSTRUCTION_ORACLE_FAULT_PASS"
exit 0
