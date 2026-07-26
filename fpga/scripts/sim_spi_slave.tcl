# =============================================================================
# File:        sim_spi_slave.tcl
# Project:     Project Auris
# Description: xsim simulation of the SPI slave testbench (tb_spi_slave).
#
#              Compiles auris_pkg + spi_slave + tb_spi_slave, runs for
#              100 us (well over many SCLK periods at 10 MHz, well under
#              a wall-clock second), and tears down.
#
# Usage:
#   vivado -mode batch -source fpga/scripts/sim_spi_slave.tcl
# =============================================================================

# ---------------------------------------------------------------------------
# 0. Path setup
# ---------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]
set rtl_dir    [file normalize "${script_dir}/../rtl"]
set sim_dir    [file normalize "${script_dir}/../sim"]
set sim_tb_dir [file join $sim_dir testbenches]
set work_dir   [file normalize "${script_dir}/../vivado_workspace/sim_spi_slave"]

set proj_name  "sim_spi_slave"
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
# ---------------------------------------------------------------------------
add_files -fileset sources_1 [glob -directory $rtl_dir **/*.sv]
add_files -fileset sim_1     [glob -directory $sim_tb_dir tb_spi_slave.sv]

# ---------------------------------------------------------------------------
# 3. Top
# ---------------------------------------------------------------------------
set_property top tb_spi_slave [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# ---------------------------------------------------------------------------
# 4. Launch and run
# ---------------------------------------------------------------------------
puts "Launching xsim ..."
launch_simulation -simulator xsim

# 100 us covers ~1000 SCLK edges at 10 MHz, plenty for a few full
# SPI transactions.
puts "Running 100 us ..."
run 100 us

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
