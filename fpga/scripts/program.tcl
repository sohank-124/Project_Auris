# =============================================================================
# File:        program.tcl
# Project:     Project Auris
# Description: Program a built bitstream onto the Arty S7-25 over the
#              on-board USB-JTAG bridge (FT2232HQ).
#
# Usage:
#   vivado -mode batch -source fpga/scripts/program.tcl
#   vivado -mode batch -source fpga/scripts/program.tcl -tclargs --bit path/to/top.bit
#
# Optional TCL args:
#   --bit <path>   : bitstream file (default: ./vivado_proj/auris.runs/impl_1/top.bit)
#   --url  <url>   : hw_server URL  (default: localhost:3121)
#
# Pre-requisites:
#   1. The Digilent cable plugin (or stock Xilinx cable driver) is
#      installed on this machine.
#   2. The Arty S7-25 is connected via USB and powered on.
#   3. Vivado's hw_server is running on the URL given by --url (the
#      default assumes a local server on port 3121).
#
#      If you are using Digilent's hw_server (shipped with Adept),
#      it also defaults to localhost:3121. If you are running a remote
#      hw_server, use --url hostname:3121.
# =============================================================================

# ---------------------------------------------------------------------------
# 0. Argument parsing
# ---------------------------------------------------------------------------
set bit_file "./vivado_proj/auris.runs/impl_1/top.bit"
set hw_url   "localhost:3121"
for {set i 0} {$i < [llength $argv]} {incr i} {
    set a [lindex $argv $i]
    switch -- $a {
        --bit { incr i; set bit_file [lindex $argv $i] }
        --url { incr i; set hw_url   [lindex $argv $i] }
        default { puts "Unknown arg: $a (ignored)" }
    }
}

# Resolve bitstream to an absolute path relative to the current working dir.
set bit_abs [file normalize $bit_file]
if {![file exists $bit_abs]} {
    puts "ERROR: bitstream not found: $bit_abs"
    puts "Run fpga/scripts/build_project.tcl first, or pass --bit <path>."
    return 1
}

puts "============================================================"
puts "  Project Auris - programming"
puts "  bit_file   = $bit_abs"
puts "  hw_url     = $hw_url"
puts "============================================================"

# ---------------------------------------------------------------------------
# 1. Open Hardware Manager
# ---------------------------------------------------------------------------
open_hw_manager

# ---------------------------------------------------------------------------
# 2. Connect to hw_server
#    -quiet suppresses the verbose connect banner.
# ---------------------------------------------------------------------------
puts "Connecting to hw_server at $hw_url ..."
connect_hw_server -url $hw_url

# ---------------------------------------------------------------------------
# 3. Open the target
#    On the Arty S7-25 the FT2232HQ presents a single JTAG chain
#    containing one device, xc7s25_0. open_hw_target without a name
#    auto-selects the first available target.
# ---------------------------------------------------------------------------
puts "Opening target ..."
open_hw_target

# ---------------------------------------------------------------------------
# 4. Identify the FPGA on the chain
#    get_hw_devices lists every device on the active target. On a
#    Arty S7-25 this is a single xc7s25_0.
# ---------------------------------------------------------------------------
set devs [get_hw_devices]
if {[llength $devs] == 0} {
    puts "ERROR: no JTAG devices found. Check USB and power."
    catch { close_hw_target }
    catch { disconnect_hw_server }
    catch { close_hw_manager }
    return 1
}

# Prefer xc7s25_0 if present; otherwise fall back to whatever was found.
set fpga_dev ""
foreach d $devs {
    if {[string match -nocase "*xc7s25*" $d]} {
        set fpga_dev $d
        break
    }
}
if {$fpga_dev eq ""} {
    set fpga_dev [lindex $devs 0]
    puts "WARNING: xc7s25 not found on chain; using $fpga_dev"
}
puts "Target device: $fpga_dev"
current_hw_device [get_hw_devices $fpga_dev]

# ---------------------------------------------------------------------------
# 5. Assign the bitstream and program
#    -verbose prints the per-stage progress (bitstream load, CRC, etc.).
# ---------------------------------------------------------------------------
puts "Assigning PROGRAM.FILE = $bit_abs ..."
set_property PROGRAM.FILE $bit_abs [current_hw_device]

puts "Programming ..."
program_hw_devices [current_hw_device]

# ---------------------------------------------------------------------------
# 6. Tear down
# ---------------------------------------------------------------------------
puts "Closing hardware manager ..."
catch { close_hw_target }
catch { disconnect_hw_server }
catch { close_hw_manager }

puts "============================================================"
puts "  Programming complete."
puts "    bitstream  : $bit_abs"
puts "    device     : $fpga_dev"
puts "============================================================"
return 0
