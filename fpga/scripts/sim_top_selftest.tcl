# =============================================================================
# File:        sim_top_selftest.tcl
# Project:     Project Auris
# Description: xsim simulation for top-level self-test mode using JA7->JA6
#              digital loopback emulation in tb_top_selftest.
# =============================================================================

set script_dir [file normalize [file dirname [info script]]]
set rtl_dir    [file normalize "${script_dir}/../rtl"]
set sim_dir    [file normalize "${script_dir}/../sim"]
set sim_tb_dir [file join $sim_dir testbenches]
set work_dir   [file normalize "${script_dir}/../vivado_proj/sim_top_selftest_final"]

set proj_name  "sim_top_selftest"
set part       "xc7s25csga324-1"

puts "============================================================"
puts "  Sim: $proj_name"
puts "  rtl_dir    = $rtl_dir"
puts "  sim_tb_dir = $sim_tb_dir"
puts "  work_dir   = $work_dir"
puts "  part       = $part"
puts "============================================================"

file mkdir $work_dir
create_project -force $proj_name $work_dir -part $part

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

add_files -fileset sources_1 $rtl_dir

set tb_path [file join $sim_tb_dir tb_top_selftest.sv]
if {![file exists $tb_path]} {
    puts "ERROR: testbench not found: $tb_path"
    close_project
    return 1
}
add_files -fileset sim_1 $tb_path

# Generate FFT/IFFT simulation targets used under top->dsp_pipeline.
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
file delete -force [file join $ip_dir fft_256_core]
file mkdir [file join $ip_dir fft_256_core]
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
    -module_name fft_256_core \
    -dir [file join $ip_dir fft_256_core]
set_property -dict $xfft_cfg [get_ips fft_256_core]
generate_target simulation [get_ips fft_256_core]

if {[llength [get_ips ifft_256_core]] > 0} { remove_ip [get_ips ifft_256_core] }
file delete -force [file join $ip_dir ifft_256_core]
file mkdir [file join $ip_dir ifft_256_core]
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
    -module_name ifft_256_core \
    -dir [file join $ip_dir ifft_256_core]
set_property -dict $xfft_cfg [get_ips ifft_256_core]
generate_target simulation [get_ips ifft_256_core]

set_property top tb_top_selftest [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Launching xsim ..."
launch_simulation

puts "Running 15 ms ..."
run 15 ms

close_sim -force
close_project

puts "============================================================"
puts "  Sim complete: $proj_name"
puts "============================================================"
return 0
