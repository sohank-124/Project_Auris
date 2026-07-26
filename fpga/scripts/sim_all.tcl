# =============================================================================
# File:        sim_all.tcl
# Project:     Project Auris
# Description: Master simulation script. Sources each per-testbench sim
#              script in sequence, captures pass/fail, and prints a
#              summary table.
#
#              Each child script is fully self-contained (creates its
#              own project in vivado_workspace/sim_*/). This script just
#              sequences them and aggregates results.
#
# Usage:
#   vivado -mode batch -source fpga/scripts/sim_all.tcl
# =============================================================================

# ---------------------------------------------------------------------------
# 0. Path setup
# ---------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]

# Order matters only for readability. The tests are independent.
set sim_scripts [list \
    [file join $script_dir sim_i2s_rx.tcl] \
    [file join $script_dir sim_spi_slave.tcl] \
    [file join $script_dir sim_dsp_pipeline.tcl] \
]

puts "============================================================"
puts "  Project Auris - master sim run"
puts "  script_dir  = $script_dir"
puts "  # of sims   = [llength $sim_scripts]"
puts "============================================================"

# ---------------------------------------------------------------------------
# 1. Run each sim, capturing pass/fail
#    `catch` swallows the TCL error from a child script (typically a
#    compile error, missing testbench file, or xsim $fatal). We treat
#    any catch non-zero result as a failure of that test.
# ---------------------------------------------------------------------------
set results [list]
foreach s $sim_scripts {
    set name [file rootname [file tail $s]]
    puts ""
    puts "------------------------------------------------------------"
    puts "  Running: $name"
    puts "------------------------------------------------------------"

    # Make sure the testbench file exists before we even try to source.
    # Some sims check this themselves; we double-check here to give a
    # clear PASS/FAIL line for the test rather than a TCL error trace.
    set tb_name "tb_[string range $name 4 end].sv"
    set tb_path [file normalize [file join $script_dir .. sim testbenches $tb_name]]
    if {![file exists $tb_path]} {
        puts "  SKIP: testbench not found: $tb_path"
        lappend results [list $name SKIP "testbench file missing"]
        continue
    }

    set start_ms [clock milliseconds]
    set err [catch {
        source $s
    } result]
    set elapsed_ms [expr {[clock milliseconds] - $start_ms}]

    if {$err} {
        puts ""
        puts "  FAILED: $name (after ${elapsed_ms} ms)"
        puts "  TCL error: $result"
        lappend results [list $name FAIL $result]
    } else {
        puts ""
        puts "  PASSED: $name (in ${elapsed_ms} ms)"
        lappend results [list $name PASS "-"]
    }
}

# ---------------------------------------------------------------------------
# 2. Summary
# ---------------------------------------------------------------------------
puts ""
puts "============================================================"
puts "  Simulation summary"
puts "============================================================"
set n_pass 0
set n_fail 0
set n_skip 0
foreach r $results {
    set name [lindex $r 0]
    set stat [lindex $r 1]
    puts [format "  %-20s  %s" $name $stat]
    switch -- $stat {
        PASS { incr n_pass }
        FAIL { incr n_fail }
        SKIP { incr n_skip }
    }
}
puts "------------------------------------------------------------"
puts [format "  %d passed, %d failed, %d skipped" $n_pass $n_fail $n_skip]
puts "============================================================"

# Exit code: non-zero if anything failed. Useful for CI runners.
if {$n_fail > 0} {
    return 1
}
return 0
