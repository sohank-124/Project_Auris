# =============================================================================
# File:        sim_btn_debounce.tcl
# Project:     Project Auris
# Description: xsim simulation of the 4-button debouncer testbench
#              (tb_btn_debounce).
#
#              Compiles auris_pkg + btn_debounce + tb_btn_debounce, runs
#              for 100 us (well over the testbench's 25 ms scripted
#              stimulus + 20 ms debounce settle window per button), and
#              tears down.
#
#              The testbench internally uses a 1 MHz clock so the
#              effective simulated time is comfortable for xsim; the
#              100 us xsim run-time is more than enough to push every
#              test case through to the summary line.
#
# Usage:
#   vivado -mode batch -source fpga/scripts/sim_btn_debounce.tcl
# =============================================================================

# ---------------------------------------------------------------------------
# 0. Path setup — anchor to the script's own directory so the script
#    works regardless of the caller's cwd.
# ---------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]
set rtl_dir    [file normalize "${script_dir}/../rtl"]
set sim_dir    [file normalize "${script_dir}/../sim"]
set sim_tb_dir [file join $sim_dir testbenches]
set work_dir   [file normalize "${script_dir}/../vivado_proj/sim_btn_debounce"]

set proj_name  "sim_btn_debounce"
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
add_files -fileset sim_1     [glob -directory $sim_tb_dir tb_btn_debounce.sv]

# ---------------------------------------------------------------------------
# 3. Top modules
#    The RTL top is dummy (won't be elaborated); the sim top is tb_btn_debounce.
# ---------------------------------------------------------------------------
set_property top tb_btn_debounce [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# ---------------------------------------------------------------------------
# 4. Launch and run
# ---------------------------------------------------------------------------
puts "Launching xsim ..."
launch_simulation

# 100 us is sufficient because the testbench uses a 1 MHz internal clock
# (period 1000 ns) for simulation speed; the stimulus script finishes
# well before 100 us of simulated time.
puts "Running 600 ms ..."
run 600 ms

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
