# =============================================================================
# File:        sim_overlap_add.tcl
# Project:     Project Auris
# Description: xsim simulation of the overlap-add testbench (tb_overlap_add).
#
#              Drives the BFP-scaled IFFT output into the overlap-add
#              history buffer and verifies the sat24((cur + hist) <<< scale)
#              reconstruction for continuous time-domain output.
#
# Usage:
#   vivado -mode batch -source fpga/scripts/sim_overlap_add.tcl
# =============================================================================

# ---------------------------------------------------------------------------
# 0. Path setup — anchor to the script's own directory so the script
#    works regardless of the caller's cwd.
# ---------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]
set rtl_dir    [file normalize "${script_dir}/../rtl"]
set sim_dir    [file normalize "${script_dir}/../sim"]
set sim_tb_dir [file join $sim_dir testbenches]
set work_dir   [file normalize "${script_dir}/../vivado_proj/sim_overlap_add"]

set proj_name  "sim_overlap_add"
set part       "xc7s25csga324-1"

puts "============================================================"
puts "  Sim: $proj_name"
puts "  rtl_dir    = $rtl_dir"
puts "  sim_tb_dir = $sim_tb_dir"
puts "  work_dir   = $work_dir"
puts "  part       = $part"
puts "============================================================"

# ---------------------------------------------------------------------------
# 1. Project
# ---------------------------------------------------------------------------
file mkdir $work_dir
create_project -force $proj_name $work_dir -part $part

set_property target_language   Verilog [current_project]
set_property simulator_language Mixed   [current_project]

# ---------------------------------------------------------------------------
# 2. Add sources
#    2a. Full RTL tree — Vivado's add_files recurses natively
#        when given a directory path.
#    2b. Testbench.
# ---------------------------------------------------------------------------
add_files -fileset sources_1 $rtl_dir
add_files -fileset sim_1     [glob -directory $sim_tb_dir tb_overlap_add.sv]

# ---------------------------------------------------------------------------
# 3. Top modules
#    The RTL top is dummy (won't be elaborated); the sim top is tb_overlap_add.
# ---------------------------------------------------------------------------
set_property top tb_overlap_add [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# ---------------------------------------------------------------------------
# 4. Launch and run
# ---------------------------------------------------------------------------
puts "Launching xsim ..."
launch_simulation

# 1 ms at 96 MHz = 96000 cycles; overlap-add emits a new sample every
# few cycles once primed, so 1 ms covers a healthy stretch of the
# history buffer and saturation corner cases.
puts "Running 1 ms ..."
run 1 ms

# ---------------------------------------------------------------------------
# 5. Tear down
# ---------------------------------------------------------------------------
close_sim -force
close_project

puts "============================================================"
puts "  Sim complete: $proj_name"
puts "  Waveform    : ${work_dir}/${proj_name}.sim/sim_1/behav/xsim/xsimulator.wdb"
puts "============================================================"
return 0
