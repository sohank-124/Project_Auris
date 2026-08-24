# Project Auris — Session Summary: FPGA-Only Verification

**Date:** 2026-08-12
**Scope:** Forensic audit → verification recovery → Campaign 3 execution → final state.

---

## 1. What Was Done — Phase 1: Forensic Audit

A read-only audit (`docs/fpga_only_migration_forensic_audit_2026-08-12.md`) established the truth of the repository state:

| Question | Answer |
|----------|--------|
| Did the Aug-12 migration happen? | **PARTIALLY** — source-level only, all uncommitted (single commit `683acb0`, 2026-07-25) |
| Can the FPGA operate without ESP32? | **YES** at source level (FPGA generates I2S clocks, reads buttons, applies modes/volume, drives RGB) |
| Four modes implemented? | PARTIALLY — **Hermitian symmetry violated** in 3/4 gain tables |
| Gain curves correct? | PARTIALLY — Q2.14 values correct, tables asymmetric |
| Buttons → modes/volume? | YES (wired and verified) |
| FPGA-generated I2S clocking? | YES (`clk_gen.sv`: MMCM + fractional ÷31.25 BCLK, ÷64 LRCLK) |
| Volume in datapath? | YES (`volume_ctrl` between overlap-add and output buffer) |
| RGB mode indication? | YES (green/blue/magenta/red, active-low) |
| Migrated design synthesized? | **NO** — only a July-28 pre-migration bitstream existed |
| ESP32 runtime dependency? | **NONE** in instantiated RTL (dead SPI files still on disk, live `firmware/` tree not deleted) |

---

## 2. What Was Done — Phase 2: Verification Recovery

### 2.1 RTL bugs proven and fixed

| File | Bug | Fix | Proof |
|------|-----|-----|-------|
| `mode_ctrl.sv` | **Hermitian symmetry violated** — SPEECH (62/127 pairs), MUSIC (62/127), HEARING (64/127). `spectral_proc` indexes a 128-entry table with a wrapping counter requiring `gain[k]==gain[128-k]`; violation injects imaginary residue into the right channel. | Mirrored entries 1..63 into 65..127 (EQ intent preserved). | Arithmetic verification; tb_spectral_proc PASS 141/141 |
| `mode_ctrl.sv` | **Width-extension bug** — `2'(~active_bank)` evaluated as `~(2'(active_bank))` producing bank_sel 2/3 instead of 0/1. | `active_bank ? 2'd0 : 2'd1` | tb_mode_ctrl PASS 10/10 |
| `overlap_add.sv` | **out_v_o window = 127 cycles/frame** (1 bogus output at head, 2 valid outputs dropped at tail) — valid flag delayed 2 cycles vs 3-cycle data latency. | Added `hist_v_r2` 3rd delay stage; gate `<= HALF+2`; `out_v <= hist_v_r2 && sample_cnt>=3` → exactly 128 aligned outputs. | tb_overlap_add PASS 8/8 |
| `i2s_tx.sv` | Redundant `initial` block = multiple-procedural-driver LRM violation. | Deleted (async reset covers all registers). | Clean elaboration |
| `cdc_i2s_to_dsp.sv` | Same redundant `initial` block. | Deleted. | Clean elaboration |
| `cdc_dsp_to_i2s.sv` | Same redundant `initial` block. | Deleted. | Clean elaboration |

### 2.2 Testbench repairs (all 9)

- **tb_window_apply** — VCD path
- **tb_spectral_proc** — send_bin single-cycle pulse (was ~5-cycle injection → every check read the previous bin); `check_bin_range` signed arithmetic (unsigned `1-2` wrapped to 4.29 G → equal values "failed"); Test4 writes bin 1 (counter had advanced past bin 0); pipeline drains
- **tb_overlap_add** — fork send/receive (output produced during send)
- **tb_mode_ctrl** — wait for boot `initial_load`; bank expectations corrected to A,B,A,B→A parity
- **tb_btn_debounce** — CLK_HALF 1000× unit bug; Test6 pre-release hold + counter reset after it; Test5 patterns
- **tb_i2s_rx** — send/check forked (1-cycle `valid_o` strobe); declarations hoisted
- **tb_i2s_tx** — deadlock edge-waits fixed (`prev_lrclk` had been re-sampled every negedge → tautology); LRCLK init phase `1'b1`; edge-pair sync; valid held 130 negedges; capture skip 4→3; right channel captured back-to-back
- **tb_cdc_fifo** — registered-valid/comb-data alignment via 1-cycle delayed `rd_data_d`; Test4 serial write-1/read-1; Test5 flags checked post-reset; illegal part-select fixed
- **tb_dsp_pipeline** — `volume_i` wired to 5'd31 (was floating to X)

Scripts: `sim_btn_debounce.tcl` (100 µs→600 ms), `sim_mode_ctrl.tcl` (100 µs→500 µs), `sim_cdc_fifo.tcl` (100 µs→2 ms).

---

## 3. What Was Done — Phase 3: Campaign 3 Execution

Ran the full suite repeatedly, classified every failure (RTL / TB / infrastructure / expected), fixed only verified issues, reran until stable.

### Final campaign results

| TB | Result | Pass/Fail |
|----|--------|-----------|
| window_apply | **PASS** | 1024/1024 |
| mode_ctrl | **PASS** | 10/10 |
| overlap_add | **PASS** | 8/8 |
| spectral_proc | **PASS** | 141/141 |
| i2s_tx | **PASS** | 13/13 |
| btn_debounce | **PASS** | 31/31 |
| cdc_fifo | **PARTIAL** | 92/108 |
| i2s_rx | **FAIL** | 1/13 |
| dsp_pipeline | **TIMEOUT** | — |

### RTL bugs proven but NOT fixed (escalated, documented)

1. **i2s_rx right-channel FSM misalignment** — left channel decodes correctly; right channel returns shifted/garbage data (0x00789a for 0x789abc, then 0x00f135 after TB alignment attempts). The right channel does not apply the standard I2S 1-BCLK delay consistently — it would mis-capture a real INMP441 right channel. RTL fix needed in `i2s_rx.sv`.
2. **i2s_rx overflow_o unreachable** — `pending_overflow` set in ST_SHIFT_RIGHT but cleared in ST_VALID before any wait state can assert it. Dead logic.

---

## 4. What Still Needs to Be Finished

### 4.1 RTL fixes (highest priority — genuine hardware defects)

- [ ] **Fix `i2s_rx.sv` right-channel FSM** — apply the standard I2S 1-BCLK delay / correct shift start for the right channel so `right_o` captures correctly. Re-run `sim_i2s_rx` until it passes.
- [ ] **Fix `i2s_rx.sv` overflow_o** — either remove the dead `pending_overflow`/`overflow_o` logic or wire it to a reachable assertion point (e.g., a new-sample-before-consume condition). Decide intent, then re-run.

### 4.2 cdc_fifo streaming data-integrity (partial)

- [ ] Investigate Test 4's persistent TB-vs-RTL CDC timing with the waveform (`fpga/vivado_proj/sim_cdc_fifo/sim_cdc_fifo.sim/sim_1/behav/xsim/xsimulator.wdb`). Flags (full/empty/reset) all pass; the RTL is a correct Cummings async FIFO by inspection. The 96/3.072 = 31.25 non-integer clock ratio defeats 4 different TB read strategies. Either find the correct TB alignment or classify as a documented TB limitation.

### 4.3 Full-pipeline verification

- [ ] **dsp_pipeline sim** — currently TIMEOUT (behavioral xsim of dual 256-pt xfft IP > 10 min). Options: hardware-accelerated sim, longer budget, or accept as infrastructure-limited. Compiles + elaborates cleanly.
- [ ] **Volume path end-to-end** — `volume_i` now wired in tb_dsp_pipeline; needs the pipeline sim to actually run to confirm the datapath.

### 4.4 Coverage gaps (no test exists)

- [ ] **RGB LED decoder** (top.sv combinational case) — add a TB or a top-level check.
- [ ] **clk_gen I2S clock generation** (BCLK ÷31.25 fractional divider, LRCLK ÷64) — add a standalone TB.
- [ ] **Top-level elaboration test** — every sim compiles the full RTL tree, but there is no dedicated top-level TB.

### 4.5 Synthesis / implementation of the migrated design

- [ ] **Run the full Vivado flow on the migrated RTL** (the only existing bitstream is the July-28 pre-migration build). Achieve timing closure, verify the migrated design is synthesizable, generate a bitstream.
- [ ] Optionally validate on hardware (Arty S7-25 + INMP441 + PCM5102A).

### 4.6 Repository hygiene (from the forensic audit — not yet done)

- [ ] **Commit all uncommitted work** (entire migration + verification changes are uncommitted on top of `683acb0`).
- [ ] **Delete the live `firmware/` tree** (duplicated in `archive/`; declared archived but never removed).
- [ ] **Remove/archive dead SPI RTL** (`spi_slave.sv`, `cdc_spi_to_dsp.sv`, `cdc_dsp_to_spi.sv`, `reg_file.sv`, their TBs + sim scripts) or stop `build_project.tcl`'s recursive `add_files` from compiling them.
- [ ] **Version-control `archive/`** (currently untracked — would not survive a clean clone).
- [ ] **Update stale docs**: WIRING.md, ENGINEERING_DESIGN.md, IMPLEMENTATION_PLAN.md, firmware_arch.md (all still describe the ESP32-era architecture); fix `modes_and_gains.md` hex constants; fix `modes_and_gains.md` / top.sv STATUS1-vs-STATUS2 comment mismatch.
- [ ] **Clean CI** — `ci.yml` still compiles `tb_spi_slave` (dead RTL); PR/issue templates still reference ESP32.

---

## 5. Deliverables Produced

| File | Content |
|------|---------|
| `docs/fpga_only_migration_forensic_audit_2026-08-12.md` | Read-only forensic audit of the migration state |
| `docs/verification_recovery_report.md` | Final verification recovery report (Campaign 3 results, RTL changes with proofs, failure classifications, checklist) |
| `docs/session_summary_fpga_only_verification.md` | This file |

---

*End of session summary.*
