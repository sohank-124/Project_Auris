# =============================================================================
# File:        sim_i2s_rx.tcl
# Project:     Project Auris
# Description: xsim simulation of the I2S receiver testbench (tb_i2s_rx).
#
#              Creates a throwaway project, compiles the relevant RTL
#              (auris_pkg + i2s_rx) and the testbench, launches xsim,
#              runs for 1 ms, and tears down.
#
# Usage:
#   vivado -mode batch -source fpga/scripts/sim_i2s_rx.tcl
# =============================================================================

# ---------------------------------------------------------------------------
# 0. Path setup — anchor to the script's own directory so the script
#    works regardless of the caller's cwd.
# ---------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]
set rtl_dir    [file normalize "${script_dir}/../rtl"]
set sim_dir    [file normalize "${script_dir}/../sim"]
set sim_tb_dir [file join $sim_dir testbenches]
set work_dir   [file normalize "${script_dir}/../vivado_workspace/sim_i2s_rx"]

set proj_name  "sim_i2s_rx"
set part       "XC7S25-1CSGA225C"

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
#    2a. RTL: the I2S RX testbench only needs auris_pkg and i2s_rx.
#        We still glob the full RTL tree so the compile order is
#        deterministic and so adding new dependencies is a no-op.
#    2b. Testbench.
# ---------------------------------------------------------------------------
add_files -fileset sources_1 [glob -directory $rtl_dir **/*.sv]
add_files -fileset sim_1     [glob -directory $sim_tb_dir tb_i2s_rx.sv]

# ---------------------------------------------------------------------------
# 3. Top modules
#    The RTL top is dummy (won't be elaborated); the sim top is tb_i2s_rx.
# ---------------------------------------------------------------------------
set_property top tb_i2s_rx [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# ---------------------------------------------------------------------------
# 4. Launch and run
# ---------------------------------------------------------------------------
puts "Launching xsim ..."
launch_simulation -simulator xsim

# 1 ms is enough to exercise many LRCLK frames at 48 kHz while keeping
# the wall-clock cost of the run in single-digit seconds.
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
