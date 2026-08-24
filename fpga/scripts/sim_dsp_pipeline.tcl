# =============================================================================
# File:        sim_dsp_pipeline.tcl
# Project:     Project Auris
# Description: xsim simulation of the full DSP pipeline testbench
#              (tb_dsp_pipeline).
#
#              The DSP pipeline runs at 96 MHz and processes 256-point
#              FFT frames every 128 new samples (i.e. ~2.67 ms per
#              frame at 48 kHz). 8 ms of simulated time is long enough
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
set work_dir   [file normalize "${script_dir}/../vivado_proj/sim_dsp_pipeline"]

set proj_name  "sim_dsp_pipeline"
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
# ---------------------------------------------------------------------------
add_files -fileset sources_1 $rtl_dir

set tb_path [file join $sim_tb_dir tb_dsp_pipeline.sv]
if {![file exists $tb_path]} {
    puts "ERROR: testbench not found: $tb_path"
    puts "Create fpga/sim/testbenches/tb_dsp_pipeline.sv before running this script."
    close_project
    return 1
}
add_files -fileset sim_1 $tb_path

# ---------------------------------------------------------------------------
# 3. Generate FFT/IFFT IP cores needed by dsp_pipeline
# ---------------------------------------------------------------------------
set ip_dir [file normalize "${script_dir}/../ip"]
file mkdir $ip_dir

set xfft_cfg [list \
    CONFIG.transform_length             {256} \
    CONFIG.target_clock_frequency       {96} \
    CONFIG.input_width                  {16} \
    CONFIG.phase_factor_width           {16} \
    CONFIG.data_format                  {fixed_point} \
    CONFIG.scaling_options              {block_floating_point} \
    CONFIG.rounding_modes               {convergent_rounding} \
    CONFIG.implementation_options       {pipelined_streaming_io} \
    CONFIG.output_ordering              {natural_order} \
    CONFIG.throttle_scheme              {realtime} \
    CONFIG.aresetn                      {true} \
    CONFIG.memory_options_data          {block_ram} \
    CONFIG.memory_options_phase_factors {block_ram} \
    CONFIG.memory_options_hybrid        {false} \
]

if {[llength [get_ips fft_256_core]] > 0} { remove_ip [get_ips fft_256_core] }
# Wipe the previous output dir so Vivado does not create fft_256_core_N.
# The -dir target must exist (create_ip does not create it).
file delete -force [file join $ip_dir fft_256_core]
file mkdir [file join $ip_dir fft_256_core]
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
    -module_name fft_256_core \
    -dir [file join $ip_dir fft_256_core]
set_property -dict $xfft_cfg [get_ips fft_256_core]
generate_target simulation [get_ips fft_256_core]

if {[llength [get_ips ifft_256_core]] > 0} { remove_ip [get_ips ifft_256_core] }
# Wipe the previous output dir so Vivado does not create ifft_256_core_N.
file delete -force [file join $ip_dir ifft_256_core]
file mkdir [file join $ip_dir ifft_256_core]
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
    -module_name ifft_256_core \
    -dir [file join $ip_dir ifft_256_core]
set_property -dict $xfft_cfg [get_ips ifft_256_core]
generate_target simulation [get_ips ifft_256_core]

# ---------------------------------------------------------------------------
# 4. Top
# ---------------------------------------------------------------------------
set_property top tb_dsp_pipeline [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# ---------------------------------------------------------------------------
# 5. Launch and run
# ---------------------------------------------------------------------------
puts "Launching xsim ..."
launch_simulation

# 8 ms of simulated time = enough for pipeline fill + output drain
puts "Running 8 ms ..."
run 8 ms

# ---------------------------------------------------------------------------
# 6. Tear down
# ---------------------------------------------------------------------------
close_sim -force
close_project

puts "============================================================"
puts "  Sim complete: $proj_name"
puts "  Waveform    : ${work_dir}/${proj_name}.sim/sim_1/behav/xsim/xsimulator.wdb"
puts "============================================================"
return 0
