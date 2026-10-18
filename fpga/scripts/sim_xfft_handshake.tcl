set script_dir [file normalize [file dirname [info script]]]
set rtl_dir    [file normalize "${script_dir}/../rtl"]
set sim_dir    [file normalize "${script_dir}/../sim"]
set sim_tb_dir [file join $sim_dir testbenches]
set work_dir   [file normalize "${script_dir}/../vivado_proj/sim_xfft_handshake"]
set ip_dir     [file normalize "${script_dir}/../ip"]
set proj_name  "sim_xfft_handshake"
set part       "xc7s25csga324-1"

file mkdir $work_dir
create_project -force $proj_name $work_dir -part $part
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
add_files -fileset sources_1 $rtl_dir
add_files -fileset sim_1 [file join $sim_tb_dir tb_xfft_handshake.sv]

set xfft_cfg [list \
    CONFIG.transform_length {256} \
    CONFIG.target_clock_frequency {96} \
    CONFIG.input_width {16} \
    CONFIG.phase_factor_width {16} \
    CONFIG.data_format {fixed_point} \
    CONFIG.scaling_options {block_floating_point} \
    CONFIG.rounding_modes {convergent_rounding} \
    CONFIG.implementation_options {pipelined_streaming_io} \
    CONFIG.output_ordering {natural_order} \
    CONFIG.throttle_scheme {realtime} \
    CONFIG.aresetn {true} \
    CONFIG.memory_options_data {block_ram} \
    CONFIG.memory_options_phase_factors {block_ram} \
    CONFIG.memory_options_hybrid {false}]

foreach core {fft_256_core ifft_256_core} {
    set core_dir [file join $ip_dir $core]
    file mkdir $core_dir
    create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
        -module_name $core -dir $core_dir
    set_property -dict $xfft_cfg [get_ips $core]
    generate_target simulation [get_ips $core]
}

set_property top tb_xfft_handshake [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
puts "Running focused XFFT handshake check for 4 ms ..."
run 4 ms
close_sim -force
close_project
return 0