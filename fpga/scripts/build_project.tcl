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
set proj_dir_override ""
set self_test_enable 0
set self_test_loopback_enable 0
for {set i 0} {$i < [llength $argv]} {incr i} {
    set a [lindex $argv $i]
    switch -- $a {
        --clean  { set do_clean 1 }
        --part   { incr i; set part [lindex $argv $i] }
        --jobs   { incr i; set jobs [lindex $argv $i] }
        --proj-dir { incr i; set proj_dir_override [lindex $argv $i] }
        --self-test { set self_test_enable 1 }
        --self-loopback { set self_test_loopback_enable 1 }
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
if {$proj_dir_override ne ""} {
    set proj_dir $proj_dir_override
}

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
puts "  self_test  = $self_test_enable"
puts "  self_loop  = $self_test_loopback_enable"
puts "============================================================"

# ---------------------------------------------------------------------------
# 3. Optionally wipe the previous project so no stale cache pollutes a
#    deliberate clean build. Normal builds preserve the project directory,
#    which allows Hardware Manager and the GUI to remain open.
# ---------------------------------------------------------------------------
if {[llength [get_projects -quiet]] > 0} {
    catch { close_project -quiet }
}

if {$do_clean && [file exists $proj_dir]} {
    if {[catch { file delete -force $proj_dir } delete_err]} {
        puts "ERROR: unable to delete existing project directory: $proj_dir"
        puts "ERROR: $delete_err"
        puts "Close any open Vivado project, hardware manager, xsim, or file browser using this directory, then rerun."
        error "Cannot clean project: $delete_err"
    }
}

# ---------------------------------------------------------------------------
# 4. Create or reopen the project.
#    Normal builds reopen the existing project so Vivado does not try to
#    delete its active run directories. --clean is the explicit destructive
#    path that recreates the project from scratch.
#    target_language = Verilog is the correct value; SystemVerilog is
#    parsed by Vivado's Verilog front-end.
#    simulator_language = Mixed supports a future VHDL testbench if one
#    is ever added.
# ---------------------------------------------------------------------------
set project_file [file join $proj_dir "${proj_name}.xpr"]
if {!$do_clean && [file exists $project_file]} {
    open_project $project_file
} else {
    create_project -force $proj_name $proj_dir -part $part
}

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

# Optional bring-up generics for board-only validation without codecs.
set top_generics [format "SELF_TEST_ENABLE=%d SELF_TEST_LOOPBACK_ENABLE=%d" \
    $self_test_enable $self_test_loopback_enable]
set_property generic $top_generics [get_filesets sources_1]
puts "Applied top generics: $top_generics"

# Existing run directories are valid only after their sources are refreshed.
# Reset them explicitly on a non-clean rebuild instead of deleting the whole
# project tree.
foreach run_name {synth_1 impl_1} {
    if {[llength [get_runs -quiet $run_name]] > 0} {
        reset_run $run_name
    }
}

# ---------------------------------------------------------------------------
# 6. Add constraints
# ---------------------------------------------------------------------------
puts "Adding constraints from $con_dir ..."
add_files -fileset constrs_1 [glob -directory $con_dir *.xdc]
# CDC clock queries require the board clocks to exist first.
set_property PROCESSING_ORDER LATE [get_files cdc_fifo.xdc]

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

# Register both cores in every project, including a normal cold build.
# Accept the historical nested layout and the conventional flat layout, but
# reject ambiguity instead of silently choosing a potentially stale core.
foreach core_name {fft_256_core ifft_256_core} {
    if {[llength [get_ips -quiet $core_name]] == 0} {
        set candidates {}
        foreach xci [list \
            [file join $ip_dir $core_name ${core_name}.xci] \
            [file join $ip_dir $core_name $core_name ${core_name}.xci]] {
            if {[file exists $xci]} { lappend candidates $xci }
        }
        if {[llength $candidates] > 1} {
            error "Ambiguous IP configurations for $core_name: $candidates"
        } elseif {[llength $candidates] == 1} {
            read_ip [lindex $candidates 0]
        } else {
            # create_ip adds the module-name directory itself.
            create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 \
                -module_name $core_name -dir $ip_dir
        }
    }
    set core [get_ips -quiet $core_name]
    if {[llength $core] != 1} {
        error "Expected exactly one registered IP named $core_name"
    }
    if {[get_property IS_LOCKED $core]} {
        error "IP $core_name is locked; resolve its Vivado/IP version before building"
    }
    # Reapply the design contract even when importing a cached configuration.
    set_property -dict $xfft_cfg $core
    generate_target all $core
}
update_compile_order -fileset sources_1
puts "FFT and IFFT registered and generated."

# ---------------------------------------------------------------------------
# 8. Synthesis
# ---------------------------------------------------------------------------
puts "Launching synth_1 ..."
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
set synth_progress [get_property PROGRESS [get_runs synth_1]]
set synth_status [get_property STATUS [get_runs synth_1]]
if {$synth_progress ne "100%" || ![string match "synth_design Complete*" $synth_status]} {
    puts "ERROR: synthesis failed (progress = $synth_progress, status = $synth_status)"
    puts "See ${proj_dir}/${proj_name}.runs/synth_1/logs/ for details."
    error "Synthesis did not complete successfully"
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
set impl_progress [get_property PROGRESS [get_runs impl_1]]
set impl_status [get_property STATUS [get_runs impl_1]]
if {$impl_progress ne "100%" || ![string match "write_bitstream Complete*" $impl_status]} {
    puts "ERROR: implementation failed (progress = $impl_progress, status = $impl_status)"
    puts "See ${proj_dir}/${proj_name}.runs/impl_1/logs/ for details."
    error "Implementation did not complete successfully"
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
if {![file exists $bit_path] || [file size $bit_path] == 0} {
    error "Build completed without a nonempty bitstream: $bit_path"
}
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
