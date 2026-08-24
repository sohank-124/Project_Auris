# Session Summary — 2026-08-12

> **📌 Meta-document banner (added 2026-08-12 documentation sweep).**
> This is the working session summary for the 2026-08-12 FPGA-only
> migration work. It is preserved verbatim as a historical
> record of what was done in that session, including verification
> infrastructure improvements (Section 2). The companion document
> [`docs/fpga_only_migration_forensic_audit_2026-08-12.md`](docs/fpga_only_migration_forensic_audit_2026-08-12.md)
> documents the pre-migration state. The narrative of what
> changed during the migration (motivation, removed modules,
> documentation impact, remaining out-of-scope items) is in
> [`docs/migration_summary.md`](docs/migration_summary.md). The
> file-level documentation audit (which files were touched by the
> docs sweep) is in [`docs/documentation_audit.md`](docs/documentation_audit.md).
>
> This banner was added by the 2026-08-12 documentation sweep.
> The body of this session summary is unchanged.

## 1. Verification Coverage Audit — Implementation Status

**Task:** Compare `verification_coverage_audit.md` against the current repository.

**Key findings:**
- Audit maturity score: **28/100** (unchanged)
- **0 of 3** critical findings resolved
- **1 of 7** known testbench bugs fixed (tb_window_apply stale hex path comment)
- **2 of 7** TB bugs partially addressed (tb_overlap_add Test 2 header fixed; tb_spectral_proc Test 3 acknowledged but not fixed)
- All 8 Phase 1 critical actions are **still outstanding**

**Table produced:** 36-row matrix mapping each audit finding to current status, file/line evidence, and remaining work.

---

## 2. Verification Infrastructure Improvements (Implemented)

**Scope:** `.github/workflows/` and `fpga/scripts/` only. No RTL or testbench changes.

### Files Created (7)

| File | Testbench | Run Duration |
|------|-----------|--------------|
| `fpga/scripts/sim_i2s_tx.tcl` | `tb_i2s_tx.sv` | 1 ms |
| `fpga/scripts/sim_cdc_fifo.tcl` | `tb_cdc_fifo.sv` | 100 µs |
| `fpga/scripts/sim_window_apply.tcl` | `tb_window_apply.sv` | 1 ms |
| `fpga/scripts/sim_spectral_proc.tcl` | `tb_spectral_proc.sv` | 1 ms |
| `fpga/scripts/sim_reg_file.tcl` | `tb_reg_file.sv` | 100 µs |
| `fpga/scripts/sim_overlap_add.tcl` | `tb_overlap_add.sv` | 1 ms |
| `fpga/scripts/sim_mode_ctrl.tcl` | `tb_mode_ctrl.sv` | 100 µs |

All follow the established pattern: Vivado non-project batch simulation, part `xc7s25csga324-1`, full RTL tree + specific testbench.

### Files Modified (3)

1. **`fpga/scripts/sim_all.tcl`** — Replaced hardcoded 3-script list with glob-based auto-discovery of all `sim_*.tcl` files (excluding itself). Added `Discovered:` block printing found scripts.

2. **`.github/workflows/ci.yml`** — Removed 5 `continue-on-error: true` directives from simulation steps. Replaced `exit 0` fallbacks with `::error::` annotations and `exit 1`. Added simulation summary step with `if: always()`. Updated Verilator limitations comment to clarify lint is now gating.

3. **`fpga/scripts/sim_dsp_pipeline.tcl`** — Fixed stale comments (header said "10 ms", inline said "15 ms", actual run is "8 ms"). All four references now consistent at 8 ms.

### Before vs After

| Metric | Before | After |
|--------|--------|-------|
| Testbenches with sim scripts | 3 of 10 (30%) | **10 of 10 (100%)** |
| sim_all.tcl coverage | 3 TBs (hardcoded) | **10 TBs (auto-discovered)** |
| CI gating on simulation | ❌ Non-gating | ✅ **Gating** |
| CI failure visibility | Silent (`exit 0`) | **Visible** (`::error::`) |
| CI simulation summary | None | **Yes** |

### Remaining Infrastructure Gaps
- No SVA assertions
- No coverage collection
- CI only runs 2 TBs with Verilator (8 require Vivado xsim)
- `fpga/generated/hann_256.hex` missing (non-blocking — RTL self-generates coefficients)
- 12 modules still have no testbench (RTL/TB task, not infrastructure)

---

## 3. Mode Switching & UI Audit

**Task:** Determine whether the current FPGA implementation supports changing hearing modes using onboard buttons/switches.

### Signal Path Trace

```
ESP32 GPIO33 (MODE button, active-low w/ pull-up)
  ↓ firmware/button_handler.c:73-95
5-tap debounce (10 ms) + edge detection
  ↓ FreeRTOS queue
mode_task → auris_mode_cycle() → (current + 1) % 4
  ↓ SPI (Pmod JA1-4, 10 MHz)
fpga/rtl/io/spi_slave.sv — 32-bit frame decode
  ↓ cdc_spi_to_dsp.sv (4-phase handshake)
reg_file.sv:224-228 — REG_MODE write → dsp_mode_o
  ↓ top.sv:533-541 — edge detect → mode_we_pulse
mode_ctrl.sv FSM — ST_IDLE→ST_LOAD (128×unity)→ST_COMMIT
  ↓ dual-bank atomic swap
spectral_proc active_bank toggles → per-bin gains
  ↓ top.sv:638-669
RGB LED recolours (green/blue/cyan/red)
```

### Key Answers

| Question | Answer |
|----------|--------|
| Can a user press a button and change modes? | **Yes** — at control and LED level |
| Are modes audibly different? | **No** — all four load identical unity gain tables |
| Buttons on FPGA or ESP32? | **ESP32** GPIO33/32/25 (not on FPGA) |
| How many modes? | 4: GENERAL(0), HEARING(1), SPEECH(2), BYPASS(3) |
| Dead code? | 7 confirmed items (unconnected mode_we_o, dead mode_default_* nets, unused spectral_proc.mode_i, hard-coded unity in lookup_gain, gen_default_tables.py output never imported) |
| What's missing for audibly distinct modes? | Implement `lookup_gain` dispatch in mode_ctrl (replace hard-coded unity with per-mode tables from `gen_default_tables.py`) |

---

## 4. ESP32 Architecture Investigation

**Challenge:** "where do u see esp in the architrecture"

### Discovery

**AGENTS.md "Permanent Hardware" section does NOT list an ESP32.** It lists only: Arty S7-25 FPGA, INMP441, PCM5102A, headphones, buttons ("connected to FPGA I/O"), RGB LED, status LEDs.

**Every other artifact names ESP32-DevKitC-32E as real hardware:**
- `hardware/bom/bom.csv:3` — BOM line item
- `firmware/` — Real ESP-IDF project (40 files, 12 components)
- `fpga/rtl/top.sv:55-56` — "ESP32 is the I2S master, FPGA is the slave"
- `fpga/rtl/io/spi_slave.sv:5` — "Receives 32-bit frames from the ESP32"
- `docs/architecture/clock_domains.md:22-23` — 4th clock domain generated by ESP32
- `docs/DESIGN_DECISIONS.md:127-147` — ADR-002 "Use ESP32 as Controller" (accepted)
- CI `build-esp32` job (gating)

### I2S Master Contradiction

AGENTS.md claims INMP441 is the I2S master — this is **physically impossible** (INMP441's SCK/WS are inputs). The ESP32 generates BCLK/LRCLK. AGENTS.md is the outlier.

---

## 5. ESP32 → FPGA-Only Migration Plan

**Goal:** Remove ESP32 entirely. FPGA becomes sole controller.

### Confirmed Design Decisions

| Decision | Choice |
|----------|--------|
| Volume control | ✓ Implement real digital volume stage in RTL |
| Profile persistence | ✓ Boot to defaults each power cycle (no NVS) |
| Firmware disposition | ✓ Move to `archive/firmware-esp32/` |
| I2S clock architecture | ✓ Shared MMCM, related clock domains (614.4 MHz VCO) |
| Bypass semantics | ✓ Implement true bypass via dsp_enable |

### Change Surface

| Category | Count | Detail |
|----------|-------|--------|
| **DELETE** | ~45 files | Full `firmware/` tree (40 files), 3 SPI RTL modules, 2 obsolete TBs, 1 sim script, 3 BOM lines, 3 Makefile targets, 1 CI job |
| **ADD** | 4 RTL modules | `button_debounce.sv`, `local_ctrl.sv` (replaces reg_file), `gain_table_rom.sv`, volume stage (+ LRCLK in clk_gen) |
| **MODIFY** | ~7 RTL + XDC | `top.sv` (major), `clk_gen.sv` (major — MMCM VCO 614.4 MHz), `mode_ctrl.sv` (major — ROM source), `status_mon.sv`, `auris_pkg.sv`, XDC rewrite |
| **REWRITE** | ~20 docs | WIRING.md (biggest), README, ENGINEERING_DESIGN, 2 ADRs superseded, ROADMAP, etc. |
| **NEW TBs** | 3 | `tb_btn_debounce`, `tb_i2s_clk_gen`, `tb_mode_fsm` |
| **UNCHANGED** | 10 RTL | Entire audio DSP data path (i2s_rx/tx, CDC FIFOs, window, FFT/IFFT, buffers, overlap_add, spectral_proc) |

### Plan Review — Double-Check Findings

**3 material issues identified:**
1. **Button polarity wrong** — Arty S7-25 buttons are active-LOW (not active-high). Fix: invert in top.sv before debounce, remove PULLUP assumption from XDC.
2. **MMCM VCO fractional encoding not specified** — 614.4 MHz requires `CLKFBOUT_MULT=51` + `CLKFBOUT_FRAC=400`. Need to verify jitter on 3.072 MHz CLKOUT1 for DAC timing.
3. **Volume stage contract under-specified** — volume should be post-DSP (after overlap_add) to not affect internal SNR.

**9 minor gaps identified:** Reset architecture (dead SPI reset path), BTN3 function unspecified, heartbeat disposition, gain-ROM power-on self-load ambiguous, no resource delta estimate, Hermitian symmetry TB missing, audit score not recomputed, stub-deletion list missing, no rollback strategy.

### Phased Plan

| Phase | Content | Est. Effort |
|-------|---------|-------------|
| 0 | Baseline + archive firmware | 0.5 day |
| 1 | Clock generation (614.4 MHz VCO, BCLK/LRCLK) | 1-2 days |
| 2 | Button input (+ Phase 2.5 polarity fix) | 1 day |
| 3 | Local control plane (replaces SPI) | 1-2 days |
| 4 | Per-mode gain ROM + Hermitian symmetry | 1-2 days |
| 5 | Volume stage + true bypass | 1 day |
| 6 | Constraints, CI, docs | 1-2 days |
| 7 | Full verification + regression | 1 day |
| **Total** | | **7-11 engineer-days** |

---

## 6. File Inventory

### Files Created (this session)
- `fpga/scripts/sim_i2s_tx.tcl`
- `fpga/scripts/sim_cdc_fifo.tcl`
- `fpga/scripts/sim_window_apply.tcl`
- `fpga/scripts/sim_spectral_proc.tcl`
- `fpga/scripts/sim_reg_file.tcl`
- `fpga/scripts/sim_overlap_add.tcl`
- `fpga/scripts/sim_mode_ctrl.tcl`
- `SESSION_SUMMARY_2026-08-12.md` (this file)

### Files Modified (this session)
- `fpga/scripts/sim_all.tcl` — auto-discovery via glob
- `.github/workflows/ci.yml` — removed continue-on-error, gating simulation, summary step
- `fpga/scripts/sim_dsp_pipeline.tcl` — fixed stale run-duration comments

### Key Files Read/Audited (no modifications)
- `verification_coverage_audit.md` (full audit)
- `fpga/rtl/top.sv` — port list, SPI wiring, mode-control path, button/switch connections
- `fpga/rtl/ctrl/mode_ctrl.sv` — FSM, lookup_gain, bank-swap logic
- `fpga/rtl/ctrl/reg_file.sv` — REG_MODE write, SPI-facing port
- `fpga/rtl/pkg/auris_pkg.sv` — mode constants, register map
- `fpga/rtl/io/spi_slave.sv` — 32-bit frame decoder
- `fpga/rtl/io/i2s_rx.sv` + `i2s_tx.sv` — I2S slave assumptions
- `fpga/rtl/clk_gen.sv` — MMCM configuration
- `fpga/rtl/dsp/spectral_proc.sv` — gain banks, Hermitian symmetry
- `fpga/constraints/arty_s7_25.xdc` — pin constraints
- `firmware/` tree — ESP32 components (12 total)
- `docs/hardware/WIRING.md`, `docs/hardware/BOM.md`, `docs/hardware/README.md`
- `docs/architecture/clock_domains.md`, `docs/architecture/firmware_arch.md`
- `docs/DESIGN_DECISIONS.md` — ADRs 002, 007
- `hardware/bom/bom.csv`
- All 10 testbenches in `fpga/sim/testbenches/`

---

## 7. Unresolved Items / Open Actions

| Item | Priority | Owner |
|------|----------|-------|
| Fix tb_spi_slave 33-bit vs 32-bit framing mismatch | **Critical** | RTL/TB task |
| Create tb_output_buffer, tb_input_buffer, tb_cdc_handshake, tb_top | **Critical** | RTL/TB task |
| Fix tb_overlap_add Test 2 (collect both frames) | High | TB task |
| Fix tb_spectral_proc Test 3 bin-index alignment | High | TB task |
| Fix tb_mode_ctrl MODE_SPEECH expected value (23170 vs 16384) | Medium | TB task |
| Test sim_all.tcl locally (needs Vivado) | Medium | User |
| Fix AGENTS.md I2S master attribution | Medium | Docs |
| Execute ESP32→FPGA migration (Phases 0-7) | **Major** | RTL + Docs + CI |
| Implement per-mode gain tables in mode_ctrl | High | RTL |
| Add SVA assertions on CDC + protocol modules | High | RTL |
| Run `gen_hann_coeffs.py` to populate fpga/generated/ | Low | User |
| Clean up stale empty dirs at fpga/sim_*/ | Low | Infrastructure |
