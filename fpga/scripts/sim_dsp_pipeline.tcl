# =============================================================================
# File:        sim_dsp_pipeline.tcl
# Project:     Project Auris
# Description: xsim simulation of the full DSP pipeline testbench
#              (tb_dsp_pipeline).
#
#              The DSP pipeline runs at 96 MHz and processes 256-point
#              FFT frames every 128 new samples (i.e. ~2.67 ms per
#              frame at 48 kHz). 10 ms of simulated time is long enough
#              to capture multiple full FFT->IFFT cycles and observe
#              the overlap-add behavior end-to-end.
#
#              NOTE: this testbench instantiates a number of submodules
#              from rtl/dsp/. The script adds the full RTL tree, so
#              adding new pipeline stages is a no-op.
#
# Usage:
#   vivado -mode batch -source fpga/scripts/sim_dsp_pipeline.tcl
# =============================================================================

# ---------------------------------------------------------------------------
# 0. Path setup
# ---------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]
set rtl_dir    [file normalize "${script_dir}/../rtl"]
set sim_dir    [file normalize "${script_dir}/../sim"]
set sim_tb_dir [file join $sim_dir testbenches]
set work_dir   [file normalize "${script_dir}/../vivado_workspace/sim_dsp_pipeline"]

set proj_name  "sim_dsp_pipeline"
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
#    2a. Full RTL tree.
#    2b. The DSP pipeline testbench (must exist before this script runs;
#        see fpga/sim/testbenches/tb_dsp_pipeline.sv).
# ---------------------------------------------------------------------------
add_files -fileset sources_1 [glob -directory $rtl_dir **/*.sv]

set tb_path [file join $sim_tb_dir tb_dsp_pipeline.sv]
if {![file exists $tb_path]} {
    puts "ERROR: testbench not found: $tb_path"
    puts "Create fpga/sim/testbenches/tb_dsp_pipeline.sv before running this script."
    close_project
    return 1
}
add_files -fileset sim_1 $tb_path

# ---------------------------------------------------------------------------
# 3. Top
# ---------------------------------------------------------------------------
set_property top tb_dsp_pipeline [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# ---------------------------------------------------------------------------
# 4. Launch and run
# ---------------------------------------------------------------------------
puts "Launching xsim ..."
launch_simulation -simulator xsim

# 10 ms of simulated time = 960,000 cycles at 96 MHz = ~3-4 full FFT
# frames at 48 kHz. Adjust if the testbench needs more or less.
puts "Running 10 ms ..."
run 10 ms

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
