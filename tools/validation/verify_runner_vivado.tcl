# Exercise the real aggregate runner with actual XSim fatal/timeout/early-finish
# children followed by a successful child. No mocking of Vivado commands.
set root [file normalize [file join [file dirname [info script]] ../..]]
set fixture [file join $root .audit_verification runner_vivado_faults]
file mkdir [file join $fixture scripts]
file mkdir [file join $fixture sim testbenches]
file copy -force [file join $root fpga scripts sim_all.tcl] [file join $fixture scripts sim_all.tcl]
foreach spec {
    {a_fatal {$fatal(1,"Injected mismatch");}}
    {b_timeout {#100; $fatal(1,"Injected timeout");}}
    {c_early {$finish;}}
    {z_pass {test_done=1; $finish;}}
} {
    lassign $spec name action
    set bench [file join $fixture sim testbenches tb_${name}.sv]
    set channel [open $bench w]
    puts $channel "module tb_${name}; reg test_done=0; initial begin #10; $action end endmodule"
    close $channel
    set channel [open [file join $fixture scripts sim_${name}.tcl] w]
    puts $channel [list source [file join $root fpga scripts simulation_common.tcl]]
    puts $channel [list create_project -force $name [file join $fixture $name] -part xc7s25csga324-1]
    puts $channel [list add_files -fileset sim_1 $bench]
    puts $channel "set_property top tb_${name} \[get_filesets sim_1\]"
    puts $channel "auris_run_simulation /tb_${name}/test_done {1 us}"
    puts $channel {close_project}
    puts $channel {return 0}
    close $channel
}
set code [catch {source [file join $fixture scripts sim_all.tcl]} reason]
if {$code != 1 || $n_fail != 3 || $n_pass != 1} {
    error "Unexpected aggregate result: caught=$code fail=$n_fail pass=$n_pass reason=$reason"
}
puts "VIVADO_RUNNER_FAILURE_PROPAGATION_PASS: three real simulator failures retained; subsequent child passed"
exit 0
