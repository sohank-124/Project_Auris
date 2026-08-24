# =============================================================================
# File:        sim_mode_ctrl.tcl
# Project:     Project Auris
# Description: xsim simulation of the mode controller testbench (tb_mode_ctrl).
#
#              Drives mode transitions and per-mode gain tables to verify
#              the mode->gain-bank routing and the gain table shadow/active
#              swap semantics.
#
# Usage:
#   vivado -mode batch -source fpga/scripts/sim_mode_ctrl.tcl
# =============================================================================

# ---------------------------------------------------------------------------
# 0. Path setup — anchor to the script's own directory so the script
#    works regardless of the caller's cwd.
# ---------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]
set rtl_dir    [file normalize "${script_dir}/../rtl"]
set sim_dir    [file normalize "${script_dir}/../sim"]
set sim_tb_dir [file join $sim_dir testbenches]
set work_dir   [file normalize "${script_dir}/../vivado_proj/sim_mode_ctrl"]

set proj_name  "sim_mode_ctrl"
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
add_files -fileset sim_1     [glob -directory $sim_tb_dir tb_mode_ctrl.sv]

# ---------------------------------------------------------------------------
# 3. Top modules
#    The RTL top is dummy (won't be elaborated); the sim top is tb_mode_ctrl.
# ---------------------------------------------------------------------------
set_property top tb_mode_ctrl [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# ---------------------------------------------------------------------------
# 4. Launch and run
# ---------------------------------------------------------------------------
puts "Launching xsim ..."
launch_simulation

# 100 us at 96 MHz = 9600 cycles, plenty for multiple mode changes and
# to clock 128 gain-table entries through the SPI loader.
puts "Running 500 us ..."
run 500 us

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
