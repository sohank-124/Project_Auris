# Final FPGA-Only Migration Cleanup Audit — 2026-08-23

Scope: repository-wide cleanup verification of the ESP32/SPI/Cmod → Arty S7-25
FPGA-only migration. No RTL behaviour was changed. One concrete build error
introduced during artifact removal was fixed in build scripts (details below).
Nothing has been committed; all changes remain staged/unstaged in the working tree.

Environment: Vivado 2026.1 (`C:\AMDDesignTools\2026.1`), target `xc7s25csga324-1`.

---

## 1. Cleanup performed

| Action | Detail |
|---|---|
| Retired SPI/reg_file RTL | Deleted `spi_slave.sv`, `cdc_spi_to_dsp.sv`, `cdc_dsp_to_spi.sv`, `reg_file.sv` from `fpga/rtl/` (verified uninstantiated in `top.sv`; copies already in `archive/rtl/`) |
| Retired SPI/reg_file verification | Deleted `tb_spi_slave.sv`, `tb_reg_file.sv`; moved `sim_spi_slave.tcl`, `sim_reg_file.tcl` to new `archive/scripts/` |
| Retired ESP32 firmware | Deleted entire tracked `firmware/` tree (ESP-IDF project; full copy in `archive/firmware/`, recoverable from initial commit) |
| Removed Cmod constraint | `cmod_s7_25.xdc` deletion confirmed; **zero references** to it remain in any script, workflow, or Makefile |
| Purged generated IP artifacts | Deleted all of `fpga/ip/` (≈47 accumulated `fft_256_core_N` / `ifft_256_core_N` versions, `.dcp`s, sim netlists, bit-accurate cmodel zips, throwaway `auris_ip_gen` project). Verified first: every consumer (`build_project.tcl`, `create_ip.tcl`, `sim_dsp_pipeline.tcl`) regenerates IP via `create_ip`; nothing reads the checked-in outputs |
| Purged tool droppings | Root: `hs_err_pid*.{log,dmp}`, `vivado*.backup.*`, `vivado.{jou,log}`, `vivado_pid*.str`, `retry_open_fs.log`, `xvlog.log/.pb`, `xsim.dir/`, `.Xil/`, `fpga/vivado_proj/` (10 xsim scratch projects incl. stale `sim_spi_slave`) |
| Root-cause fix: IP version proliferation | All three IP-generating scripts now wipe **and recreate** each IP's output dir before `create_ip`. Previously Vivado silently appended `_N` when the target subdir existed — the direct cause of ~47 stale IP versions. Proven fixed: this build produced exactly `fft_256_core/fft_256_core.xci` and `ifft_256_core/ifft_256_core.xci`, unnumbered |
| Stale reference pruning | `ci.yml`: removed `tb_spi_slave` Verilator build/run steps, waveform path, summary entry. `sim_all.tcl`: emptied `archived_scripts` list (retired sims physically gone) |
| `.gitignore` | Added `xsim.dir/`, `*.pb`, `fpga/ip/` (IP output is fully regenerable; prevents recurrence) |
| Docs organization | Moved `SESSION_SUMMARY_2026-08-12.md` and `verification_coverage_audit.md` from repo root into `docs/` |

## 2. Files/artifacts removed

Tracked deletions (763 files): 715 under `fpga/ip/**` · 40 under `firmware/**` ·
4 RTL (`spi_slave`, `cdc_spi_to_dsp`, `cdc_dsp_to_spi`, `reg_file`) ·
2 testbenches · `sim_spi_slave.tcl` · `cmod_s7_25.xdc`.
Untracked garbage deleted from disk: crash logs, backup journals, `xsim.dir`,
`.Xil`, xsim scratch projects, `auris_ip_gen/`, 30 regenerated IP version dirs.

## 3. Files intentionally retained

- **`status_mon.sv`** — still instantiated by `top.sv:612` (heartbeat + clip LED); *not* SPI-era despite living beside retired modules.
- **`archive/{firmware,rtl,tb,scripts}/`** — deliberate migration boundary per Makefile/CI comments; `archive/README.md` updated to enumerate all sections.
- **Modified docs/CI/Makefile/bom** (71 tracked files) — legitimate migration content.
- **Untracked migration content (23 paths)** — legit, must be `git add`ed before any commit.
- `auris_pkg.sv` retains historical register-map comments mentioning firmware — cosmetic only.

⚠️ **Commit-completeness warning**: `arty_s7_25.xdc`, `volume_ctrl.sv`,
`btn_debounce.sv`, and `tb_btn_debounce.sv` are currently **untracked but
required by the build**. Committing only tracked deltas would produce a
broken tree (no constraints; unresolved `top.sv` instances).

## 4. Build result

**PASS** — clean project-mode run of `fpga/scripts/build_project.tcl`
(project wiped → IP regenerated → `synth_1` → `impl_1` → `write_bitstream`).

- Synthesis: 0 errors, **0 critical warnings**, 125 warnings (routine).
- Implementation: 0 critical warnings; routed timing summary reports
  **"All user specified timing constraints are met."**

One concrete build error surfaced mid-audit and was fixed: after deleting
`fpga/ip/`, `create_ip -dir` failed with `[Common 17-69] … does not exist`
— `create_ip` requires a pre-existing directory (it previously always
existed from earlier runs, which is also why `_N` suffixing occurred).
Fixed by delete-then-`file mkdir` in all three scripts. No RTL touched.

Utilization (post-route): LUT 5368/14600 (36.8%) · FF 9204/29200 (31.5%) ·
BRAM 5.5/45 (12.2%) · DSP48E1 24/80 (30%) · MMCM 1 · BUFG 3 · IOB 14/150.

## 5. Bitstream result

**PASS** — `vivado_proj/auris.runs/impl_1/top.bit` (738,636 bytes,
2026-08-23 23:30). Reports written to `vivado_proj/{timing_impl,
clock_interaction,utilization_impl,power_impl}.rpt`.

## 6. Timing result

**PASS** — both domains recognized and analyzed:

| Clock | Source | Period | Endpoints | WNS | TNS | WHS |
|---|---|---|---|---|---|---|
| `clk_dsp_raw` (96 MHz DSP) | auto-derived, MMCM CLKOUT0 | 10.417 ns | 15771 | **+0.353 ns** | 0.000 | +0.050 ns |
| `i2s_bclk` | XDC `create_generated_clock` on `u_clk_gen/bufg_bclk/O` | 333.332 ns (declared 3.000 MHz) | 443 | **+149.199 ns** | 0.000 | +0.074 ns |

- The Inter-Clock Table is **empty** → `set_clock_groups -asynchronous`
  correctly suppresses DSP↔BCLK analysis; CDC is delegated to the Gray-coded
  FIFOs as intended.
- I/O timing verified: **0 unconstrained I/O ports**. `i2s_adc_data_i` /
  `i2s_dac_data_o` carry ±10 ns I/O delays against `i2s_bclk`; buttons and
  LEDs/LRCLK are intentionally false-pathed.
- Note: declared BCLK period is 96/32 = 3.000 MHz vs. true hardware
  96/31.25 = 3.072 MHz — documented ~2.4 % approximation in the XDC;
  harmless given +149 ns slack.

## 7. Remaining blockers / observations

No functional blockers. Two advisory notes:

1. **XDC warning (cosmetic):** `Clock specified in more than one group:
   i2s_bclk` — `-include_generated_clocks clk_12mhz` already captures
   `i2s_bclk` (it is declared generated from the MMCM), so it lands in both
   async groups. Empirically harmless (inter-clock table empty; all
   constraints met). Future hygiene fix: name clocks explicitly in each
   group instead of using `-include_generated_clocks` on both sides.
   Not changed — timing passes and altering groups could alter analysis
   semantics without a concrete failure.
2. **Stale comment:** `mode_ctrl.sv:40` still says `mode_i // from reg_file`;
   the source is now the button FSM in `top.sv`. Comment-only; left
   untouched per audit rules.

## 8. Ready to commit?

**Yes — after staging the untracked migration files.** Recommended order:

```
git add -A            # picks up arty_s7_25.xdc, volume_ctrl.sv, btn_debounce.sv,
                      # tb/sim additions, archive/, docs/, all deletions
git status            # verify: no xsim.dir, no fpga/ip, no *.log/.jou/.pb
git commit
```

The working tree builds cleanly end-to-end from this exact state, which was
the acceptance criterion for this audit.
