# Focused validation followed by an isolated demonstration build.
set demo_repo_root [file normalize [file join [file dirname [info script]] ../..]]
cd $demo_repo_root
set argv {}
source fpga/scripts/sim_mode_ctrl.tcl
set argv {}
source fpga/scripts/sim_mode_ownership.tcl
set argv {}
source fpga/scripts/sim_volume_ctrl.tcl
set argv [list --proj-dir [file join $demo_repo_root fpga vivado_demo]]
source fpga/scripts/build_project.tcl
puts AURIS_DEMO_BUILD_COMPLETE
