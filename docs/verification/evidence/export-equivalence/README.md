# Recorded coefficient export equivalence

Copied from the local F30 investigation. [comparison.txt](comparison.txt) records 256 exact ordered Hann words and 512 default mode words, plus output-path and release-staging checks. [source_sha256.json](source_sha256.json) identifies the original inputs. This historical result is not a new full-suite or synthesis result.

The comparison CSVs retain individual observations. `verify_rom.tcl`, `tb_f30_rom.sv`, and `check_exports.py` are original investigation scripts preserved as evidence, not installed entry points: they may reference their original evidence-directory layout. Use the current [reproduction guidance](../../REPRODUCING.md) for maintained commands.

The periodic Hann is computed inside window_rom; default mode words are embedded inside mode_ctrl. Exports are inspection artifacts and are not loaded by active RTL.
