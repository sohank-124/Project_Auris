# =============================================================================
# File:        build_project.tcl
# Project:     Project Auris — FPGA-Accelerated Assistive Audio
# Target:      Digilent Arty S7-25 Rev. E (Spartan-7 XC7S25-1CSGA324C)
#
# Description: Vivado PROJECT-MODE build script.
#
#              Produces a fully placed, routed, and bitstreamed design for
#              the Project Auris top module. All outputs land in
#              ${proj_dir}/${proj_name}.runs/.
#
# Usage:
#   vivado -mode batch -source fpga/scripts/build_project.tcl
#
# Optional TCL args:
#   --clean       : wipe the project directory before recreating
#   --part <str>  : override the target part (default XC7S25-1CSGA324C)
#   --jobs  <n>   : parallel synthesis / implementation jobs (default 4)
#
# Steps performed:
#   1. Parse CLI args
#   2. (optionally) wipe the project directory
#   3. create_project in project mode
#   4. add RTL sources (recursive)
#   5. add constraints
#   6. create and configure FFT + IFFT IPs (xf v9.1)
#   7. launch synth_1, wait, dump synth reports
#   8. launch impl_1 -to_step write_bitstream, wait, dump impl reports
#   9. print summary, close project
# =============================================================================

# ---------------------------------------------------------------------------
# 0. Helper: locate ourselves regardless of cwd.
#    [file dirname [info script]] is the directory this script lives in
#    (i.e. fpga/scripts). All other paths are derived from it so the
#    script behaves the same whether Vivado is invoked from the repo
#    root, from fpga/, or from fpga/scripts/.
# ---------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]
set rtl_dir    [file normalize "${script_dir}/../rtl"]
set con_dir    [file normalize "${script_dir}/../constraints"]
set ip_dir     [file normalize "${script_dir}/../ip"]
set sim_dir    [file normalize "${script_dir}/../sim"]

# ---------------------------------------------------------------------------
# 1. Parse arguments
# ---------------------------------------------------------------------------
set do_clean 0
set jobs     4
set part "xc7s25csga324-1"
for {set i 0} {$i < [llength $argv]} {incr i} {
    set a [lindex $argv $i]
    switch -- $a {
        --clean  { set do_clean 1 }
        --part   { incr i; set part [lindex $argv $i] }
        --jobs   { incr i; set jobs [lindex $argv $i] }
        default  { puts "Unknown arg: $a (ignored)" }
    }
}

# ---------------------------------------------------------------------------
# 2. Project variables
#    proj_name / proj_dir are the ONLY relative-to-cwd paths in this
#    script; everything else is anchored to script_dir.
# ---------------------------------------------------------------------------
set proj_name "auris"
set proj_dir  "./vivado_proj"

puts "============================================================"
puts "  Project Auris - Vivado build"
puts "  part       = $part"
puts "  proj_name  = $proj_name"
puts "  proj_dir   = $proj_dir"
puts "  rtl_dir    = $rtl_dir"
puts "  con_dir    = $con_dir"
puts "  ip_dir     = $ip_dir"
puts "  jobs       = $jobs"
puts "  do_clean   = $do_clean"
puts "============================================================"

# ---------------------------------------------------------------------------
# 3. Wipe previous project so no stale cache pollutes the new one.
#    file delete -force is a no-op when $proj_dir does not exist.
# ---------------------------------------------------------------------------
file delete -force $proj_dir

# ---------------------------------------------------------------------------
# 4. Create the project
#    -force overwrites any existing project of the same name.
#    target_language = Verilog is the correct value; SystemVerilog is
#    parsed by Vivado's Verilog front-end.
#    simulator_language = Mixed supports a future VHDL testbench if one
#    is ever added.
# ---------------------------------------------------------------------------
create_project -force $proj_name $proj_dir -part $part

set_property target_language   Verilog [current_project]
set_property simulator_language Mixed   [current_project]

# ---------------------------------------------------------------------------
# 5. Add RTL sources (recursive over all subdirectories)
# ---------------------------------------------------------------------------
puts "Adding RTL from $rtl_dir ..."
# Vivado's add_files natively recurses into directories: passing a
# directory path (rather than individual file paths) causes Vivado to
# discover every file with a valid extension (.sv, .v, .vhd, etc.)
# under that directory and all its descendants.  This relies on
# Vivado's built-in filesystem walk, which reaches any directory
# depth — no Tcl glob recursion is needed.
add_files -fileset sources_1 $rtl_dir

# Make the design's top module explicit. The top is the file-level
# SystemVerilog module `top`, NOT a file name.
set_property top top [get_filesets sources_1]

# ---------------------------------------------------------------------------
# 6. Add constraints
# ---------------------------------------------------------------------------
puts "Adding constraints from $con_dir ..."
add_files -fileset constrs_1 [glob -directory $con_dir *.xdc]

# ---------------------------------------------------------------------------
# 7. IP cores
#    7a. Clocking Wizard — SKIPPED.
#        The clk_gen.sv RTL module instantiates the MMCME2_BASE primitive
#        directly, so we do not need the clk_wiz IP. If the RTL is later
#        refactored to use the Clocking Wizard, uncomment the block
#        below.
#
#    7b. FFT 256-point core (xf v9.1, Pipelined Streaming I/O, BFP)
#    7c. IFFT 256-point core (same xfft IP, FWD_INV=0 at runtime)
#        xfft v9.1 supports a runtime FWD_INV bit on s_axis_config_tdata
#        that selects forward (1) or inverse (0) transform. The two
#        instances are therefore identical in configuration; the only
#        difference is how the FWD_INV bit is wired at the top level.
# ---------------------------------------------------------------------------

# Ensure the IP output directory exists.
file mkdir $ip_dir

# Shared xfft configuration block (used by both FFT and IFFT).
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

# 7b. FFT instance
#     Wipe any previous output directory first: if stale fft_256_core(_N)
#     subdirs are present, Vivado silently appends a _N suffix to the new
#     one, which is how dozens of stale versions accumulated here.
#     The -dir target must exist (create_ip does not create it).
if {[llength [get_ips fft_256_core]] > 0} {
    remove_ip [get_ips fft_256_core]
}
file delete -force [file join $ip_dir fft_256_core]
file mkdir [file join $ip_dir fft_256_core]
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
    -module_name fft_256_core \
    -dir [file join $ip_dir fft_256_core]
set_property -dict $xfft_cfg [get_ips fft_256_core]
generate_target all [get_ips fft_256_core]

# 7c. IFFT instance
if {[llength [get_ips ifft_256_core]] > 0} {
    remove_ip [get_ips ifft_256_core]
}
file delete -force [file join $ip_dir ifft_256_core]
file mkdir [file join $ip_dir ifft_256_core]
create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
    -module_name ifft_256_core \
    -dir [file join $ip_dir ifft_256_core]
set_property -dict $xfft_cfg [get_ips ifft_256_core]
generate_target all [get_ips ifft_256_core]

puts "IP generation complete:"
puts "  ${ip_dir}/fft_256_core/fft_256_core.xci"
puts "  ${ip_dir}/ifft_256_core/ifft_256_core.xci"

# ---------------------------------------------------------------------------
# 8. Synthesis
# ---------------------------------------------------------------------------
puts "Launching synth_1 ..."
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
set synth_status [get_property PROGRESS [get_runs synth_1]]
if {$synth_status ne "100%"} {
    puts "ERROR: synthesis failed (progress = $synth_status)"
    puts "See ${proj_dir}/${proj_name}.runs/synth_1/logs/ for details."
    return 1
}

# Dump synthesis reports
puts "Writing synth reports ..."
open_run synth_1
report_utilization    -file [file join $proj_dir utilization_synth.rpt]
report_timing_summary -file [file join $proj_dir timing_synth.rpt]
close_design

# ---------------------------------------------------------------------------
# 9. Implementation + bitstream
# ---------------------------------------------------------------------------
puts "Launching impl_1 (through write_bitstream) ..."
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
set impl_status [get_property PROGRESS [get_runs impl_1]]
if {$impl_status ne "100%"} {
    puts "ERROR: implementation failed (progress = $impl_status)"
    puts "See ${proj_dir}/${proj_name}.runs/impl_1/logs/ for details."
    return 1
}

# Dump implementation reports
puts "Writing impl reports ..."
open_run impl_1
report_utilization      -file [file join $proj_dir utilization_impl.rpt]
report_timing_summary   -file [file join $proj_dir timing_impl.rpt]
report_power            -file [file join $proj_dir power_impl.rpt]
report_clock_interaction -file [file join $proj_dir clock_interaction.rpt]
close_design

# ---------------------------------------------------------------------------
# 10. Summary
# ---------------------------------------------------------------------------
set bit_path [file join $proj_dir ${proj_name}.runs impl_1 top.bit]
puts "============================================================"
puts "  Build complete."
puts "  Bitstream : $bit_path"
puts "  Reports   : ${proj_dir}/utilization_*.rpt"
puts "              ${proj_dir}/timing_*.rpt"
puts "              ${proj_dir}/power_impl.rpt"
puts "              ${proj_dir}/clock_interaction.rpt"
puts "============================================================"

# ---------------------------------------------------------------------------
# 11. Close
# ---------------------------------------------------------------------------
close_project
return 0
