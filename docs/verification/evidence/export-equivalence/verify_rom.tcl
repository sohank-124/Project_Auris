set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here ../../..]]
cd $here
create_project -force f30_rom [file join $here vivado] -part xc7s25csga324-1
add_files [file join $root fpga/rtl/pkg/auris_pkg.sv]
add_files [file join $root fpga/rtl/dsp/window_rom.sv]
add_files -fileset sim_1 [file join $here tb_f30_rom.sv]
set_property top tb_f30_rom [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
update_compile_order -fileset sim_1
source [file join $root fpga/scripts/simulation_common.tcl]
if {[catch {auris_run_simulation /tb_f30_rom/test_done {10 us}} message options]} {
    puts stderr "F30_SIM_FAIL: $message"
    exit 1
}
close_project
puts "F30_SIM_CONTRACT_PASS"
exit 0
