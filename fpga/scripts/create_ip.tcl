# =============================================================================
# File:        create_ip.tcl
# Project:     Project Auris
# Description: Standalone IP generation script. Produces the two Xilinx
#              LogiCORE IPs that the design depends on (FFT and IFFT,
#              both xfft v9.1) under fpga/ip/.
#
#              Can be run standalone, OR sourced from build_project.tcl.
#              When sourced, this script creates a throwaway project to
#              host the IP cores (so the IPs are generated against a
#              known-good part) and closes that project when done.
#
# Usage:
#   vivado -mode batch -source fpga/scripts/create_ip.tcl
# =============================================================================

# ---------------------------------------------------------------------------
# 0. Path setup
# ---------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]
set ip_dir     [file normalize "${script_dir}/../ip"]

set temp_proj_name "auris_ip_gen"
set temp_proj_dir  [file join $ip_dir $temp_proj_name]
set part "xc7s25csga225-1"

puts "============================================================"
puts "  Project Auris - IP generation"
puts "  ip_dir        = $ip_dir"
puts "  temp project  = $temp_proj_dir"
puts "  part          = $part"
puts "============================================================"

# ---------------------------------------------------------------------------
# 1. Make sure the output directory exists
# ---------------------------------------------------------------------------
file mkdir $ip_dir

# ---------------------------------------------------------------------------
# 2. Throwaway project to host the IPs
#    xfft v9.1 requires a project context for `create_ip`. We use a
#    scratch project under fpga/ip/auris_ip_gen/ that is safe to delete
#    after generation.
# ---------------------------------------------------------------------------
create_project -force $temp_proj_name $temp_proj_dir -part $part
set_property target_language   Verilog [current_project]
set_property simulator_language Mixed   [current_project]

# ---------------------------------------------------------------------------
# 3. Shared xfft v9.1 configuration
#    The two instances are identical in configuration. They differ only
#    in the runtime FWD_INV bit of s_axis_config_tdata: 1 for forward
#    (FFT), 0 for inverse (IFFT).
# ---------------------------------------------------------------------------
set xfft_cfg [list \
    CONFIG.transform_length          {256} \
    CONFIG.target_clock_frequency    {96} \
    CONFIG.input_data_width          {16} \
    CONFIG.phase_factor_width        {16} \
    CONFIG.data_format               {FixedPoint} \
    CONFIG.scaling_options           {Block Floating Point} \
    CONFIG.rounding_modes            {Convergent Rounding} \
    CONFIG.architecture              {Pipelined Streaming I/O} \
    CONFIG.output_ordering           {Natural Order} \
    CONFIG.throttle                  {Realtime} \
    CONFIG.aresetn                   {true} \
    CONFIG.mem_options_data          {Block RAM} \
    CONFIG.mem_options_phase_factors {Block RAM} \
    CONFIG.mem_options_hybrid        {false} \
]

# ---------------------------------------------------------------------------
# 4. FFT instance
# ---------------------------------------------------------------------------
set fft_dir [file join $ip_dir fft_256_core]
file mkdir $fft_dir
if {[llength [get_ips fft_256_core]] > 0} {
    remove_ip [get_ips fft_256_core]
}
puts "Creating IP: fft_256_core ..."
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
    -module_name fft_256_core \
    -dir $fft_dir
set_property -dict $xfft_cfg [get_ips fft_256_core]
generate_target all [get_ips fft_256_core]
puts "  -> ${fft_dir}/fft_256_core.xci"

# ---------------------------------------------------------------------------
# 5. IFFT instance
# ---------------------------------------------------------------------------
set ifft_dir [file join $ip_dir ifft_256_core]
file mkdir $ifft_dir
if {[llength [get_ips ifft_256_core]] > 0} {
    remove_ip [get_ips ifft_256_core]
}
puts "Creating IP: ifft_256_core ..."
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
    -module_name ifft_256_core \
    -dir $ifft_dir
set_property -dict $xfft_cfg [get_ips ifft_256_core]
generate_target all [get_ips ifft_256_core]
puts "  -> ${ifft_dir}/ifft_256_core.xci"

# ---------------------------------------------------------------------------
# 6. Close the throwaway project
# ---------------------------------------------------------------------------
close_project

puts "============================================================"
puts "  IP generation complete."
puts "    ${ip_dir}/fft_256_core/fft_256_core.xci"
puts "    ${ip_dir}/ifft_256_core/ifft_256_core.xci"
puts "============================================================"
return 0
