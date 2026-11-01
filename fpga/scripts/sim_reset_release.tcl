# Focused regression, registered with sim_all; strict shared completion contract.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ../..]]
set name reset_release
create_project -force sim_$name [file join $root fpga/vivado_proj sim_$name] -part xc7s25csga324-1
add_files [file join $root fpga/rtl]
add_files -fileset sim_1 [file join $root fpga/sim/testbenches tb_${name}.sv]
set_property top tb_$name [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
update_compile_order -fileset sim_1
source [file join $script_dir simulation_common.tcl]
auris_run_simulation /tb_$name/test_done {2 ms}
close_project
return 0
