# =============================================================================
# Top-level Makefile orchestrating FPGA and ESP32 builds
# =============================================================================
.PHONY: help fpga fpga-clean fpga-sim esp esp-flash esp-monitor all clean

# Default target
help:
	@echo "Project Auris build orchestration"
	@echo ""
	@echo "Targets:"
	@echo "  make fpga         Build FPGA bitstream (Vivado batch mode)"
	@echo "  make fpga-clean   Wipe Vivado workspace"
	@echo "  make fpga-sim     Run all FPGA testbenches in xsim"
	@echo "  make esp          Build ESP32 firmware"
	@echo "  make esp-flash    Flash ESP32 (set ESP_PORT env var)"
	@echo "  make esp-monitor  Open serial monitor"
	@echo "  make tools        Run code generators (Hann coeffs, gain tables)"
	@echo "  make all          Build tools, FPGA, and ESP32"
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
	rm -rf vivado_workspace/ fpga/*.runs/ fpga/*.cache/

fpga-sim:
	vivado -mode batch -source fpga/scripts/sim_i2s_rx.tcl
	vivado -mode batch -source fpga/scripts/sim_spi_slave.tcl

# ----- ESP32 -----
esp:
	cd firmware && idf.py build

esp-flash:
	cd firmware && idf.py -p $(ESP_PORT) flash

esp-monitor:
	cd firmware && idf.py -p $(ESP_PORT) monitor

# ----- Combined -----
all: tools fpga esp

clean: fpga-clean
	cd firmware && idf.py fullclean
