# =============================================================================
# Top-level Makefile orchestrating FPGA builds (FPGA-only migration)
# -----------------------------------------------------------------------------
# Migration date: 2026-08 (Phase 5 cleanup)
#   * ESP32 / ESP-IDF targets removed (esp, esp-flash, esp-monitor)
#   * sim_spi_slave removed from fpga-sim (SPI RTL is archived, not active)
#   * Original SPI RTL files retained under fpga/rtl/ as dead modules for
#     reference; archival copies live under archive/rtl/.
# =============================================================================
.PHONY: help fpga fpga-clean fpga-sim all clean

# Default target
help:
	@echo "Project Auris build orchestration"
	@echo ""
	@echo "Targets:"
	@echo "  make fpga         Build FPGA bitstream (Vivado batch mode)"
	@echo "  make fpga-clean   Wipe Vivado workspace"
	@echo "  make fpga-sim     Run all FPGA testbenches in xsim"
	@echo "  make tools        Run code generators (Hann coeffs, gain tables)"
	@echo "  make all          Build tools and FPGA bitstream"
	@echo "  make clean        Wipe all build outputs"

# ----- Tools -----
tools:
	@echo "==> Generating Hann window coefficients..."
	cd tools && python win_gen/gen_hann_coeffs.py
	@echo "==> Generating default gain profile tables..."
	cd tools && python profile_gen/gen_default_tables.py

# ----- FPGA -----
fpga:
	@echo "==> Building FPGA bitstream with Vivado..."
	vivado -mode batch -source fpga/scripts/build_project.tcl

fpga-clean:
	rm -rf vivado_proj/ fpga/*.runs/ fpga/*.cache/

fpga-sim:
	vivado -mode batch -source fpga/scripts/sim_i2s_rx.tcl
	# sim_spi_slave.tcl removed in Phase 5 (FPGA-only migration, 2026-08).
	# SPI RTL is archived under archive/rtl/ and not part of the active build.

# ----- ESP32 (DISABLED — FPGA-only migration, Phase 5, 2026-08) -----
# The ESP32 is no longer part of the hardware. The FPGA handles all
# control, mode switching, and volume management via onboard pushbuttons.
# Firmware sources are preserved under archive/firmware/ for reference.
# These targets are intentionally retained as commented stubs so the
# migration boundary is explicit and the firmware can be resurrected later.
#
# esp:
# 	cd firmware && idf.py build
#
# esp-flash:
# 	cd firmware && idf.py -p $(ESP_PORT) flash
#
# esp-monitor:
# 	cd firmware && idf.py -p $(ESP_PORT) monitor

# ----- Combined -----
all: tools fpga

clean: fpga-clean
