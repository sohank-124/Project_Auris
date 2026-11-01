set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ../..]]
set work_dir [file join $root fpga/vivado_proj/sim_top_reset]
create_project -force sim_top_reset $work_dir -part xc7s25csga324-1
add_files [file join $root fpga/rtl]
add_files -fileset sim_1 [file join $root fpga/sim/testbenches/tb_top_reset.sv]
# Test-local IP generation keeps this entry usable from a cold checkout.
set ip_dir [file join $work_dir ip]
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

foreach core {fft_256_core ifft_256_core} {
 if {[llength [get_ips -quiet $core]] == 0} {
  create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 -module_name $core -dir $ip_dir
 }
 set_property -dict $xfft_cfg [get_ips $core]
 generate_target simulation [get_ips $core]
}
set_property top tb_top_reset [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
update_compile_order -fileset sim_1
source [file join $root fpga/scripts/simulation_common.tcl]
auris_run_simulation /tb_top_reset/test_done {300 us}
close_project
return 0
