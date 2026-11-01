# Build and verification commands

Run commands from the repository root. The saved FPGA evidence uses Vivado 2026.1 on Windows, part xc7s25csga324-1 and
XFFT v9.1. Older Vivado versions have not been revalidated here. Vivado must be installed with the Spartan-7 device and
vendor simulation libraries. These scripts generate local files under ignored workspaces.

## Implementation

```sh
vivado -mode batch -source fpga/scripts/build_project.tcl
```

The script creates/imports both FFT IPs, applies the required configuration, and checks synthesis/implementation
completion plus a nonempty bitstream. It writes `fpga/vivado_proj/auris.runs/impl_1/top.bit` and project-root
timing/utilization reports. This entry has saved successful execution evidence; it was inspected, not rerun during
cleanup. Coefficient export generation is not a prerequisite for hardware initialization.

## Vivado simulation

```sh
vivado -mode batch -source fpga/scripts/sim_reset_release.tcl
vivado -mode batch -source fpga/scripts/sim_cdc_stress.tcl
vivado -mode batch -source fpga/scripts/sim_top_reset.tcl
vivado -mode batch -source fpga/scripts/sim_pipeline_reconstruction.tcl
vivado -mode batch -source fpga/scripts/sim_all.tcl
```

Reset/CDC and cold top-reset entries have focused recorded passes. The reconstruction entry exists and generates
test-local vendor IP, but its current complete execution is not certified by the older standalone reconstruction log.
The full suite discovers registered benches and rejects missing entries; a listed command is not a claim that the entire
final suite has passed.

The shared simulator contract requires `test_done=1`, an existing transcript, and no Error/Fatal diagnostics. An early
finish or exit zero is insufficient. Retain source hashes, tool version, configuration, test completion, counts, and
limitations with every new public result.

`fpga/scripts/test_reconstruction.ps1` is a legacy standalone path with specific generated-IP layout assumptions and an
explicit VivadoBin parameter. Prefer the maintained Tcl entry above for a fresh project; preserve old standalone results
as historical evidence.

## Python/Tcl runner checks without Vivado

```sh
python -B -m unittest tools.validation.test_sim_runner
```

Requires Python with tkinter/Tcl support. It tests failure propagation in the aggregate Tcl runner with temporary
fixtures; it does not simulate RTL. This command is run during cleanup and its actual outcome is recorded in [cleanup
validation](CLEANUP_VALIDATION.md).

Python analysis/export tools require Python 3.10+ and NumPy where used; selected filter tools additionally use SciPy.
[Tools documentation](../../tools/README.md) distinguishes exports, models, and physical measurements.

## GitHub Actions scope

The CI workflow lints RTL/Python/Markdown, performs a Verilator lint step, runs selected directional/combined I²S tests,
and generates inspection exports. The job named build-fpga is lint-only. No Actions job here runs Vivado implementation
or the entire vendor-IP suite. Workflow inspection does not establish remote CI success; check the actual next run.

The documentation workflow checks public Markdown and links. Release packaging uses generated inspection exports and the
canonical BOM, not an automatically built hardware-validated bitstream.
