# Project Auris — Verification Coverage Audit

**Document Version:** 1.0  
**Date:** 2026-08-02 (audit) / 2026-08-12 (banner added after FPGA-only migration)
**Auditor:** Senior Verification Engineer (Automated Audit)  
**Scope:** All 22 RTL modules, 10 testbenches, simulation infrastructure, CI pipeline  
**Classification:** Internal — Engineering Review Board

> **⚠️ ARCHITECTURE NOTE — 2026-08-12 FPGA-only migration.**
> This audit was authored for the pre-migration ESP32 + FPGA
> architecture. The following modules and testbenches referenced in
> this audit were **removed from the build** on 2026-08-12 and are
> no longer part of Project Auris:
>
> - `spi_slave.sv` / `tb_spi_slave.sv` (no SPI host in the build)
> - `reg_file.sv` / `tb_reg_file.sv` (no register file in the build)
> - `cdc_spi_to_dsp.sv` / `cdc_dsp_to_spi.sv` (no SPI clock domain)
>
> The original findings about SPI framing (33 vs 32 bits), CDC
> handshake untested, and reg_file coverage gaps are **historical
> context**; they are no longer actionable regressions.
>
> The **current** verification focus (post-migration) is on the
> modules that drive the new control plane:
>
> - **`btn_debounce`** — 20 ms debounce, edge pulse generation
> - **`volume_ctrl`** — Q2.14 multiply, sat24, mute at 0
> - **`mode_ctrl`** — atomic dual-bank BRAM swap, per-mode table load
> - **`i2s_rx` / `i2s_tx`** — now running against the FPGA's own
>   BCLK/LRCLK (FPGA is the master), not the ESP32's
>
> For the migration narrative, see
> [`docs/migration_summary.md`](docs/migration_summary.md). For the
> current architecture, see
> [`docs/fpga_only_architecture.md`](docs/fpga_only_architecture.md).
>
> The body of this audit is preserved verbatim for the historical
> record.  

---

## Executive Summary

Project Auris contains **22 RTL modules** and **10 testbenches**. Of the 22 modules, **8 have dedicated testbenches**, **2 are tested indirectly** (fft_256/ifft_256 via tb_dsp_pipeline, window_rom via tb_window_apply), and **12 have no verification whatsoever**. The overall verification maturity score is **28/100**.

Critical findings:
- **tb_spi_slave uses 33-bit framing but the RTL expects 32 bits** — a confirmed protocol mismatch that causes every SPI transaction to shift one extra bit, corrupting the frame boundary.
- **tb_overlap_add Test 2** has an internal inconsistency: the header claims "expect 2×128 outputs" but the check expects only 128.
- **CI simulation is non-gating** (`continue-on-error: true`) — simulation failures do not block merges.
- **7 of 10 testbenches have no runner script** and are never executed by any automated flow.
- **No SVA, no coverage collection, no constrained-random, no formal verification** exists anywhere.
- **12 modules are completely untested**, including all 4 CDC modules (only cdc_i2s_to_dsp has a TB), status_mon, input_buffer, output_buffer, and the top-level integration.

---

## Section 1: Per-Module Verification Analysis

### 1.1 auris_pkg (fpga/rtl/pkg/auris_pkg.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | No (package — not directly testable) |
| **Verification Confidence** | N/A |
| **Coverage Rating** | N/A |

**What IS exercised:** Constants and types are used by every other module; correctness is implicitly validated when downstream TBs pass.

**What is NOT exercised:**
- `sxt24()` function — never called in any TB
- `hi16()` function — never called in any TB
- `s24_zero()` function — never called in any TB
- Parameter boundary checks (FFT_LEN=256 enforcement)

**Recommended additional tests:**
- **Medium:** Unit test for `sxt24()` with positive, negative, and boundary values
- **Medium:** Unit test for `hi16()` with full-scale and zero inputs
- **Low:** Compile-time assertion that all address map constants are unique

---

### 1.2 top (fpga/rtl/top.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | No |
| **Verification Confidence** | 0% |
| **Coverage Rating** | None |
| **Regression Detection** | No |

**What IS exercised:** Nothing. No system-level testbench exists.

**What is NOT exercised:**
- reset_sync_stretch (2-FF sync + 16-stage SRL) — async assert/sync deassert timing
- LRCLK 2-FF synchronizer and falling-edge detector in top.sv
- CDC FIFO empty→non-empty pulse generator (dsp_sample_valid derivation)
- Mode-change edge detector (mode_we_pulse generation from reg_dsp_mode)
- Gain-table mux priority (mode_bank_we vs reg_dsp_gain_we)
- RGB LED decode logic for all 4 modes + default
- dsp_out_valid_pulse edge detection
- Full signal path: INMP441 → I2S RX → CDC → DSP → CDC → I2S TX → PCM5102A
- SPI → CDC → reg_file → DSP control path
- Startup sequence: MMCM lock → reset release → first valid audio output

**Missing corner cases:**
- MMCM locked signal bouncing during power-up
- Simultaneous SPI write and mode change
- CDC FIFO overflow during burst audio input
- Reset assertion during active SPI transaction
- Mode change during active DSP frame processing

**Behaviors never verified:**
- System-level latency from microphone input to headphone output
- Glitch-free mode switching during continuous audio streaming
- LED color correctness for all modes
- Status LED heartbeat frequency accuracy
- Clip latch set/clear through the full SPI → status_mon path

**Recommended additional tests:**
- **Critical:** System-level smoke test: inject I2S frames, verify output appears
- **Critical:** Reset sequence: verify all modules come out of reset cleanly
- **High:** Mode change during streaming: verify no audio glitch or hang
- **High:** SPI register write → DSP control propagation
- **Medium:** RGB LED decode for all modes including default

---

### 1.3 clk_gen (fpga/rtl/clk_gen.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | No |
| **Verification Confidence** | 0% |
| **Coverage Rating** | None |
| **Regression Detection** | No |

**What IS exercised:** Nothing. The MMCM wrapper is untested.

**What is NOT exercised:**
- MMCME2_BASE configuration correctness (MULT_F=50.0, DIVIDE=1, CLKOUT0_DIVIDE_F=6.25)
- Locked signal assertion timing
- BUFG feedback path
- Frequency output (96 MHz from 12 MHz input)

**Assumptions:** The MMCM primitive is trusted as a Xilinx hard macro. Configuration parameters are verified only by synthesis.

**Recommended additional tests:**
- **Low:** Behavioral model test: verify locked asserts within expected time
- **Low:** Verify CLKOUT0 frequency with a period counter in simulation

*Note: MMCM simulation requires Xilinx UNISIM library. Low priority since synthesis validates the configuration.*

---

### 1.4 i2s_rx (fpga/rtl/io/i2s_rx.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | Yes (tb_i2s_rx) |
| **Verification Confidence** | 65% |
| **Coverage Rating** | Adequate |
| **Regression Detection** | Yes — basic data path regressions caught |

**What IS exercised:**
- Basic stereo frame capture (Test 1: L=0x123456, R=0x789ABC)
- 10 consecutive frames with incrementing pattern (Test 2)
- Overflow detection after 4 unconsumed frames (Test 3)
- Philips I2S timing (1-BCLK delay after LRCLK transition)
- 5-state FSM traversal (IDLE→WAIT→SHIFT_LEFT→SHIFT_RIGHT→VALID)
- Async reset (held 20 BCLK cycles)

**What is NOT exercised:**
- Sticky overflow clearing mechanism (host write to REG_ERROR_FLAGS)
- LRCLK early-rise detection in ST_SHIFT_RIGHT (pending_overflow path)
- Behavior when LRCLK glitches or has wrong duty cycle
- Back-to-back frames with no gap (continuous streaming at exactly 48 kHz)
- Data values at boundaries: all-zeros, all-ones, max positive, max negative
- Single-bit error injection (corrupted sdata)
- Reset assertion mid-frame (FSM recovery)
- X-propagation on sdata_i during reset

**Missing corner cases:**
- LRCLK frequency mismatch (e.g., 44.1 kHz instead of 48 kHz)
- BCLK stopping and restarting
- Overflow clearing after sticky set
- Very first frame after reset (cold start timing)

**Weak or redundant tests:**
- Test 2 sends 10 frames but checks them sequentially — doesn't test pipelined consumption
- Test 3 drain loop uses `'x` expected values, so it doesn't verify the drained data

**Assumptions:**
- BCLK and LRCLK are perfectly synchronous (from same ESP32 peripheral)
- sdata_i is stable on BCLK rising edge (INMP441 drives on falling edge)

**Recommended additional tests:**
- **High:** LRCLK early-rise overflow path
- **High:** Reset mid-frame recovery
- **Medium:** Boundary data values (0x000000, 0x7FFFFF, 0x800000, 0xFFFFFF)
- **Medium:** Overflow clear via external mechanism
- **Low:** Continuous 1000-frame streaming stability

---

### 1.5 i2s_tx (fpga/rtl/io/i2s_tx.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | Yes (tb_i2s_tx) |
| **Verification Confidence** | 55% |
| **Coverage Rating** | Minimal |
| **Regression Detection** | Partial — basic data path only |

**What IS exercised:**
- Basic stereo frame transmission (Test 1: L=0x123456, R=0x789ABC)
- Underflow detection when valid_i=0 (Test 2)
- sdata_o held low during underflow (Test 2)
- 10 consecutive frames with incrementing pattern (Test 3)
- 2-FF LRCLK synchronizer
- Negedge sdata_o output flop
- Shadow register latching on LRCLK falling edge

**What is NOT exercised:**
- Sticky underflow clearing mechanism
- Shadow register behavior when valid_i toggles between frames
- sdata_o timing: half-BCLK setup/hold margin verification
- Behavior when valid_i arrives exactly at LRCLK falling edge (race condition)
- Alternating valid/invalid frames (underflow interleaved with normal)
- Full-scale and zero data patterns
- Reset during active transmission

**Missing corner cases:**
- valid_i deasserting exactly on the LRCLK falling edge
- Rapid valid_i toggling (back-to-back frames with gaps)
- Underflow recovery: valid_i returns after underflow — does output resume correctly?

**Weak or redundant tests:**
- Test 2 sdata_o check samples a single point in time — doesn't verify the entire underflow frame is zero

**Assumptions:**
- LRCLK is free-running (generated by the TB, not the DUT)
- The TB's `provide_sample` holds valid for 33 BCLK cycles — much longer than needed

**Recommended additional tests:**
- **High:** Underflow recovery (valid returns after underflow)
- **High:** valid_i timing race at LRCLK falling edge
- **Medium:** Alternating valid/underflow frames
- **Medium:** Full-scale output verification
- **Low:** Sticky underflow clear

---

### 1.6 spi_slave (fpga/rtl/io/spi_slave.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | Yes (tb_spi_slave) |
| **Verification Confidence** | 40% |
| **Coverage Rating** | Minimal |
| **Regression Detection** | Partial — **TB/RTL framing mismatch undermines confidence** |

**⚠️ CRITICAL FINDING: TB/RTL Frame Width Mismatch**

The TB sends **33-bit frames** (`{1'b0, addr[6:0], rw, data[23:0]}` = 1+7+1+24 = 33 bits), but the RTL expects **32-bit frames** (`{start, addr[6:0], rw, data[22:0]}` = 1+7+1+23 = 32 bits). The RTL's `FRAME_W = 32` and `WIRE_DATA_W = 23`. The TB shifts 33 bits per transaction, meaning the RTL's `bit_cnt` reaches 31 (FRAME_W-1) one bit before the TB finishes, and the extra bit is clocked in after DECODE. This causes:
1. The DECODE state fires at bit 31, but the TB is still shifting bit 32.
2. The frame data is misaligned by 1 bit — the RTL sees `data[22:0]` shifted by one position.

**What IS exercised:**
- Write transaction (Test 1: REG_SCRATCH ← 0xDEADBEEF)
- Read transaction with MISO check (Test 2: REG_STATUS → 0xCAFEBABE)
- 5 writes + 5 reads burst (Test 3)
- Invalid frame with start=1 (Test 4)
- Loopback test (Test 5: write/read REG_LOOPBACK)
- Frame abort on early CS deassert (implicitly, via CS_N timing)

**What is NOT exercised:**
- Correct 32-bit framing (TB uses wrong width)
- MISO tri-state behavior when CS_N is high
- Back-to-back transactions with no idle gap
- rdata_valid_i gating (TB hardcodes rdata_valid=1 for reads)
- All 128 register addresses
- Simultaneous we_o and re_o (should never happen, but not verified)
- Shift-out timing: MISO bit alignment with SCLK edges

**Missing corner cases:**
- CS_N deassert at exactly bit 31 (boundary of frame completion)
- SCLK glitch during transaction
- Very short CS_N assertion (< 32 clocks) — frame abort
- Multiple rapid transactions testing the FSM return-to-IDLE path

**Weak or redundant tests:**
- Test 5 (loopback) manually sets rdata — doesn't test actual register file loopback
- Test 3 reads always get the manually-set rdata, not actual register contents

**Recommended additional tests:**
- **Critical:** Fix 33→32 bit framing mismatch and re-run all tests
- **High:** Test with actual reg_file in the loop (not standalone spi_slave)
- **High:** Frame abort at various bit counts (8, 16, 24, 31)
- **Medium:** Back-to-back transactions with minimum CS_N high time
- **Medium:** All register address decode verification

---

### 1.7 cdc_i2s_to_dsp (fpga/rtl/cdc/cdc_i2s_to_dsp.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | Yes (tb_cdc_fifo) |
| **Verification Confidence** | 55% |
| **Coverage Rating** | Adequate |
| **Regression Detection** | Yes — basic CDC correctness |

**What IS exercised:**
- Basic 4-sample write/read transfer (Test 1)
- Full flag assertion after 4 writes (Test 2)
- Empty flag after drain (Test 3)
- Read-when-empty produces no valid data (Test 3)
- 100-sample streaming round-trip (Test 4)
- Reset behavior: partial fill → reset → flags correct (Test 5)
- Gray-coded pointer synchronization
- wr_full_o forced high during reset

**What is NOT exercised:**
- Simultaneous read and write (true concurrent CDC operation)
- Write-when-full behavior (data loss detection)
- Metastability injection (X on synchronizer FFs)
- Clock frequency ratio edge cases
- rd_valid_o pulse timing accuracy
- Data integrity under reset-domain skew (wr_rst_n and rd_rst_n asserted at different times)

**Missing corner cases:**
- Write and read happening in the exact same nanosecond
- Asymmetric reset: wr_rst_n released before rd_rst_n
- FIFO depth=4 boundary: write 5th sample while full

**Weak or redundant tests:**
- Test 4 writes all 100 samples first, then reads — not truly concurrent. With DEPTH=4, only the last 4 written samples should survive, but the slow write rate relative to the fast read clock means data drains before overflow.

**Recommended additional tests:**
- **High:** Truly concurrent read/write (interleaved at realistic 48kHz/96MHz rates)
- **High:** Write-when-full: verify data is dropped and wr_full_o stays high
- **Medium:** Asymmetric reset timing
- **Medium:** rd_valid_o single-cycle pulse verification

---

### 1.8 cdc_dsp_to_i2s (fpga/rtl/cdc/cdc_dsp_to_i2s.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | No |
| **Verification Confidence** | 0% |
| **Coverage Rating** | None |
| **Regression Detection** | No |

**What IS exercised:** Nothing directly. This is a mirror of cdc_i2s_to_dsp with reversed clock domains (DSP→I2S instead of I2S→DSP).

**What is NOT exercised:**
- All CDC functionality (write from fast domain, read from slow domain)
- Full/empty flag behavior with reversed clock ratio
- Data integrity at 96 MHz write / 3.072 MHz read rate

**Recommended additional tests:**
- **High:** Adapt tb_cdc_fifo to test cdc_dsp_to_i2s with swapped clock domains
- **Medium:** Verify full flag prevents DSP-side overwrites

---

### 1.9 cdc_spi_to_dsp (fpga/rtl/cdc/cdc_spi_to_dsp.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | No |
| **Verification Confidence** | 0% |
| **Coverage Rating** | None |
| **Regression Detection** | No |

**What IS exercised:** Nothing. The 4-phase handshake CDC is completely untested.

**What is NOT exercised:**
- 4-phase req/ack handshake protocol correctness
- Hold register stability during handshake
- `fired` flag preventing duplicate processing
- DST_IDLE → DST_FIRE → DST_WAIT state machine
- Back-to-back SPI transactions through the handshake
- Source-side ack detection and req clearing
- Multi-bit payload (addr + wdata + we + re) integrity across CDC

**Missing corner cases:**
- SPI transaction arriving during DSP reset
- Rapid back-to-back SPI writes (req asserted before previous ack completes)
- Source-side we_i and re_i asserted simultaneously

**Recommended additional tests:**
- **Critical:** Handshake protocol: single write → verify dst_we_o pulse
- **Critical:** Handshake protocol: single read → verify dst_re_o pulse
- **High:** Back-to-back transactions: verify no dropped or duplicated requests
- **High:** Payload integrity: verify addr/wdata match across CDC
- **Medium:** Reset during active handshake

---

### 1.10 cdc_dsp_to_spi (fpga/rtl/cdc/cdc_dsp_to_spi.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | No |
| **Verification Confidence** | 0% |
| **Coverage Rating** | None |
| **Regression Detection** | No |

**What IS exercised:** Nothing. The read-data return path CDC is completely untested.

**What is NOT exercised:**
- 4-phase handshake for read-data return
- src_rdata_hold stability during handshake
- dst_rdata_r capture timing
- dst_valid_o single-cycle pulse
- Back-to-back read responses

**Recommended additional tests:**
- **Critical:** Single read response: verify data integrity DSP→SPI
- **High:** Back-to-back read responses
- **Medium:** Reset during active handshake

---

### 1.11 mode_ctrl (fpga/rtl/ctrl/mode_ctrl.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | Yes (tb_mode_ctrl) |
| **Verification Confidence** | 50% |
| **Coverage Rating** | Minimal |
| **Regression Detection** | Partial |

**What IS exercised:**
- Mode change to HEARING → bank A load (Test 1)
- Mode change to SPEECH → bank B load (Test 2)
- Mode change to GENERAL → bank A load (Test 3)
- 128 bank_we_o pulses + 1 commit pulse count (Test 4)
- Default master gain value check (all modes)
- Bank alternation (A→B→A)

**What is NOT exercised:**
- Actual gain values written (all unity — TB doesn't verify each of 128 values)
- bank_addr_o sequence (0→127 sequential)
- bank_wdata_o correctness (UNITY_GAIN_Q14 = 16384 for all entries)
- Mode change during active load (interrupting ST_LOAD)
- Rapid mode changes (new mode_we_i before previous load completes)
- default_noise_floor_o and default_gate_ratio_o values
- ST_COMMIT → ST_IDLE transition timing

**Missing corner cases:**
- Mode change while ST_LOAD is in progress (FSM doesn't handle this — potential hang)
- N_BINS parameter variation

**Weak or redundant tests:**
- check_gain_load task has dead code: `seen_addrs`, `addr_seen`, `all_addrs_seen` are declared but never meaningfully used
- Test for MODE_SPEECH expects `default_master_gain = 23170` but the RTL always returns `UNITY_GAIN_Q14 = 16384` for all modes — **this test will FAIL if run**

**Recommended additional tests:**
- **High:** Verify all 128 written values equal UNITY_GAIN_Q14
- **High:** Mode change during active load (FSM robustness)
- **Medium:** Fix MODE_SPEECH expected value (23170 vs 16384 mismatch)
- **Medium:** Verify bank_addr_o counts 0→127 sequentially

---

### 1.12 reg_file (fpga/rtl/ctrl/reg_file.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | Yes (tb_reg_file) |
| **Verification Confidence** | 55% |
| **Coverage Rating** | Adequate |
| **Regression Detection** | Yes — for tested registers |

**What IS exercised:**
- Scratch R/W (REG_SCRATCH = 0x7E, Test 1)
- Loopback R/W (REG_LOOPBACK = 0x7F, Test 2)
- RO read: REG_VERSION returns hw_version_i (Test 3)
- Write-to-RO ignored (Test 4)
- Gain table write: REG_GAIN_DATA pulses gain_we_o (Test 5)
- Mode write: REG_MODE → dsp_mode_o (Test 6)
- W1C error flags (Test 7)
- Gain address auto-increment (Test 8)

**What is NOT exercised:**
- REG_STATUS read (composite field: mode, control, clip, cdc_locked, dsp_ready)
- REG_STATUS read side-effect: clip_clear_o pulse
- REG_CONTROL → dsp_enable_o
- REG_VOLUME → dsp_volume_o
- REG_NOISE_FLOOR, REG_NOISE_GATE_RATIO, REG_MASTER_GAIN shadow registers
- REG_GAIN_BANK shadow register
- REG_GAIN_COMMIT → bank_commit_o pulse
- REG_PEAK_LEVEL, REG_OUT_PEAK telemetry reads
- REG_FRAME_COUNT_L, REG_FRAME_COUNT_H telemetry reads
- BRAM registered read latency (1-cycle) alignment with rdata_valid_o
- Full address space sweep (128 entries)
- Simultaneous we_i and re_i

**Missing corner cases:**
- REG_ERROR_FLAGS W1C: partial clear (write 0x0F to clear only lower 4 bits)
- REG_GAIN_DATA auto-increment wraparound (addr 127 → 0)
- Read immediately after write to same address (BRAM read-after-write hazard)
- Telemetry registers with changing inputs

**Weak or redundant tests:**
- Test 7 (W1C) manually sets error_flags_i to 0x00 after the write — doesn't test the actual W1C logic in the RTL (the RTL clears `error_latch`, not `error_flags_i`)

**Recommended additional tests:**
- **High:** REG_STATUS composite read (all bit fields)
- **High:** REG_STATUS read → clip_clear_o pulse
- **High:** REG_CONTROL → dsp_enable_o
- **High:** REG_GAIN_COMMIT → bank_commit_o pulse
- **Medium:** All telemetry register reads
- **Medium:** Partial W1C
- **Medium:** Gain address auto-increment wraparound at 127
- **Low:** Full address space sweep

---

### 1.13 status_mon (fpga/rtl/ctrl/status_mon.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | No |
| **Verification Confidence** | 0% |
| **Coverage Rating** | None |
| **Regression Detection** | No |

**What IS exercised:** Nothing.

**What is NOT exercised:**
- 1 Hz heartbeat generation (48,000,000 cycle half-period counter)
- Heartbeat gating on dsp_ready_i
- Heartbeat counter reset when dsp_ready_i deasserts
- Clip latch set (clip_event_i)
- Clip latch clear (clip_clear_i)
- Set-dominates-clear behavior (simultaneous clip_event_i and clip_clear_i)

**Recommended additional tests:**
- **High:** Heartbeat toggle at correct frequency (scaled for simulation)
- **High:** Clip latch set/clear/set-dominates
- **Medium:** Heartbeat gating on dsp_ready_i
- **Low:** Counter reset on dsp_ready_i deassert

---

### 1.14 dsp_pipeline (fpga/rtl/dsp/dsp_pipeline.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | Yes (tb_dsp_pipeline) |
| **Verification Confidence** | 30% |
| **Coverage Rating** | Minimal |
| **Regression Detection** | Partial — only smoke test |

**What IS exercised:**
- Active mode: 200 samples → output valid + not-X (Test 1)
- Frame counter > 0 after processing (Test 2)
- Peak input meter ≥ 0xF4240 after full-scale input (Test 3)
- 48 kHz sample strobe generation (2000-cycle divider)

**What is NOT exercised:**
- Bypass mode verification (dsp_enable_i=0, check output == input)
- Output data correctness (only checks "not X" and "valid > 0")
- Peak output meter (peak_out_o)
- Error flags propagation (error_flags_o)
- Clip event detection (clip_event_o)
- Gain table write-through to spectral_proc
- Bank commit propagation
- Mode change during operation
- Master gain, noise floor, gate ratio changes
- TLAST generation for FFT and IFFT
- BFP exponent delay pipeline (418-deep SRL)
- Overlap-add scale factor computation
- Output buffer underflow detection

**Weak or redundant tests:**
- Test 1 only checks "output exists and is not X" — doesn't verify any data correctness
- Test 3 checks peak_in ≥ 0xF4240 but 0x7FFFFF (full scale) should produce exactly 0x7FFFFF

**Recommended additional tests:**
- **Critical:** Bypass mode: verify output == input (registered)
- **High:** Output data correctness with known input (e.g., DC → DC)
- **High:** Error flags: input_buffer overflow → ERR_I2S_OVERFLOW
- **High:** Clip detection: full-scale input → clip_event_o pulse
- **Medium:** Gain change effect on output
- **Medium:** Mode change during streaming

---

### 1.15 input_buffer (fpga/rtl/dsp/input_buffer.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | No |
| **Verification Confidence** | 0% |
| **Coverage Rating** | None |
| **Regression Detection** | No |

**What IS exercised:** Only indirectly through tb_dsp_pipeline (no data correctness check).

**What is NOT exercised:**
- 256-sample BRAM write/read cycle
- 50% overlap: 128 new + 128 old sample ordering
- Hop counter (128 writes → trigger read burst)
- Read burst timing (256 reads at 96 MHz)
- frame_ready_o pulse timing
- busy_o assertion during read burst
- Sticky overflow_o (write during read burst)
- Cold-start: first frame with zero-filled "old" half
- BRAM dual-port simultaneous R/W

**Recommended additional tests:**
- **Critical:** Single frame: write 128 samples → verify frame_ready_o → read 256 samples → verify ordering
- **Critical:** Overlap correctness: verify old[128] + new[128] ordering
- **High:** Overflow detection: write during read burst
- **High:** Cold-start first frame (zero-filled history)
- **Medium:** Multiple consecutive frames

---

### 1.16 window_apply (fpga/rtl/dsp/window_apply.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | Yes (tb_window_apply) |
| **Verification Confidence** | 70% |
| **Coverage Rating** | Good |
| **Regression Detection** | Yes |

**What IS exercised:**
- Unity input (16384) → output = Hann coefficients (256 values, Test 1)
- Zero input → output = 0 (256 values, Test 2)
- Max input (32767) → output = scaled coefficients (256 values, Test 3)
- Frame boundary wrap (256 more samples, Test 4)
- 2-stage pipeline latency
- ±1 LSB tolerance for rounding
- Q2.14 × Q2.14 → Q2.14 truncation

**What is NOT exercised:**
- Negative input values (all tests use positive inputs)
- frame_start_i pulse resetting the ROM address counter mid-frame
- Right channel handling (in_r_i is ignored)
- out_im_o always zero (real-input FFT)

**Recommended additional tests:**
- **Medium:** Negative input values
- **Medium:** frame_start_i mid-frame reset
- **Low:** Verify out_im_o is always zero

---

### 1.17 window_rom (fpga/rtl/dsp/window_rom.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | No (tested indirectly via tb_window_apply) |
| **Verification Confidence** | 60% |
| **Coverage Rating** | Adequate (indirect) |
| **Regression Detection** | Yes (via tb_window_apply) |

**What IS exercised:** All 256 coefficients are verified by tb_window_apply Test 1.

**Recommended additional tests:**
- **Low:** Standalone ROM read verification (redundant with tb_window_apply coverage)

---

### 1.18 fft_256 (fpga/rtl/dsp/fft_256.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | No (tested indirectly via tb_dsp_pipeline) |
| **Verification Confidence** | 15% |
| **Coverage Rating** | Minimal (indirect) |
| **Regression Detection** | No |

**What IS exercised:** Only through tb_dsp_pipeline's smoke test (output exists, not X).

**What is NOT exercised:**
- FFT numerical correctness
- AXI-Stream handshake behavior
- TLAST frame delineation
- BFP exponent output
- Config channel acceptance
- Event signals

**Recommended additional tests:**
- **High:** Known-input FFT: DC input → bin 0 = N×DC, all others ≈ 0
- **High:** Single-tone input → verify peak at correct bin
- **Medium:** TLAST timing verification

---

### 1.19 ifft_256 (fpga/rtl/dsp/ifft_256.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | No (tested indirectly via tb_dsp_pipeline) |
| **Verification Confidence** | 15% |
| **Coverage Rating** | Minimal (indirect) |
| **Regression Detection** | No |

**Recommended additional tests:**
- **High:** Known-input IFFT: single bin → verify time-domain output
- **Medium:** FFT→IFFT round-trip: verify identity (with BFP scaling)

---

### 1.20 spectral_proc (fpga/rtl/dsp/spectral/spectral_proc.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | Yes (tb_spectral_proc) |
| **Verification Confidence** | 45% |
| **Coverage Rating** | Minimal |
| **Regression Detection** | Partial |

**What IS exercised:**
- Unity gain identity: 128 bins pass through unchanged (Test 1)
- Noise gate: low-magnitude bin attenuated (Test 2)
- Gain table write to bin 5, bank A (Test 3 — **bin-index alignment is flawed**)
- Bank swap: write bank B, commit, verify output (Test 4)
- Streaming valid: 10 bins (Test 5)

**What is NOT exercised:**
- Hermitian bin wrapping (bins 128-255 map to gain[0-127])
- Bin counter accuracy across frame boundaries (in_last_i reset)
- Master gain ≠ unity
- Noise gate boundary: |X|² exactly equal to noise_floor
- Gate ratio = 0 (complete mute)
- Negative input values
- Complex input (non-zero imaginary)
- Gain table write to active bank
- Bank commit during active frame processing

**Weak or redundant tests:**
- Test 3 admits bin-index alignment flaw: writes gain to bin 5 but the internal counter is at position ~129, so the custom gain is never applied to the test bin

**Recommended additional tests:**
- **Critical:** Fix bin-index alignment in Test 3
- **High:** Master gain ≠ unity: verify multiplication
- **High:** Hermitian bin wrapping verification
- **High:** in_last_i → bin_idx reset
- **Medium:** Noise gate boundary
- **Medium:** Negative and complex inputs

---

### 1.21 overlap_add (fpga/rtl/dsp/overlap_add.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | Yes (tb_overlap_add) |
| **Verification Confidence** | 40% |
| **Coverage Rating** | Minimal |
| **Regression Detection** | Partial — **Test 2 has internal inconsistency** |

**⚠️ FINDING: Test 2 Internal Inconsistency**

The test header says "Two consecutive frames: send 2×256, expect 2×128 outputs" but `receive_frame` only collects 128 samples and the check expects `rcv_count == 128`. The second frame's 128 outputs are never collected or verified.

**What IS exercised:**
- Single frame: 256 samples → 128 outputs (Test 1)
- Two consecutive frames: only first 128 outputs checked (Test 2)
- Known values with BFP scaling (Test 3)
- scale_factor_i = 0 (K_BFP = 6 only)

**What is NOT exercised:**
- Non-zero scale_factor_i
- History buffer correctness across multiple frames with varying data
- frame_done_o pulse timing
- Saturation at ±8388607/8388608 boundaries
- scale_factor_i edge cases (very large positive, negative)
- Negative input values

**Recommended additional tests:**
- **Critical:** Fix Test 2 to collect and verify both frames' outputs
- **High:** Non-zero scale_factor_i verification
- **High:** Multi-frame history overlap with varying data
- **High:** Saturation boundary tests
- **Medium:** frame_done_o pulse timing

---

### 1.22 output_buffer (fpga/rtl/dsp/output_buffer.sv)

| Attribute | Value |
|---|---|
| **Dedicated TB** | No |
| **Verification Confidence** | 0% |
| **Coverage Rating** | None |
| **Regression Detection** | No |

**What IS exercised:** Only indirectly through tb_dsp_pipeline (no data correctness check).

**What is NOT exercised:**
- Ping-pong buffer swap (128 writes → swap halves)
- Registered BRAM read (1-cycle latency alignment)
- Underflow detection (sample_clk_en_i when buf_valid=0)
- Sticky underflow flag
- Commit priority over read-finish (race condition handling)
- Data ordering: 128 samples written to half A, read back in order

**Recommended additional tests:**
- **Critical:** Write 128 samples → verify ping-pong swap → read 128 samples → verify data
- **Critical:** Underflow: read before commit → verify underflow_o
- **High:** Commit/read-finish same-cycle priority
- **High:** Underflow recovery: commit after underflow
- **Medium:** Continuous ping-pong operation

---

## Section 2: Cross-Cutting Concerns

### 2.1 Reset Behavior

| Aspect | Status | Notes |
|---|---|---|
| Synchronous reset | ⚠️ Partial | Most modules use async-assert/sync-deassert via reset_sync_stretch, but no TB tests the sync deassert timing |
| Async reset | ⚠️ Partial | tb_i2s_rx tests async assert (20 BCLK hold), but no TB tests async assert during active operation |
| Multi-domain reset | ❌ Not tested | reset_sync_stretch generates resets for 3 domains. No TB verifies all 3 release in correct order |
| Reset stretch (16 cycles) | ❌ Not tested | No TB verifies the 16-cycle SRL stretch |
| Reset during operation | ❌ Not tested | No TB asserts reset during active data processing |

### 2.2 CDC Correctness

| Module | TB Exists | Data Integrity | Flags | Handshake |
|---|---|---|---|---|
| cdc_i2s_to_dsp | Yes (tb_cdc_fifo) | ⚠️ Partial | ✅ Full/Empty | N/A (FIFO) |
| cdc_dsp_to_i2s | ❌ No | ❌ | ❌ | N/A |
| cdc_spi_to_dsp | ❌ No | ❌ | N/A | ❌ |
| cdc_dsp_to_spi | ❌ No | ❌ | N/A | ❌ |

**Critical gap:** 3 of 4 CDC modules are completely untested. The handshake CDCs use a fundamentally different protocol than the FIFO CDCs and have unique failure modes (dropped requests, duplicate processing, deadlock).

### 2.3 AXI-Stream Handshakes

| Aspect | Status | Notes |
|---|---|---|
| FFT tready/tvalid | ❌ Not tested | s_axis_data_tready is unconnected in dsp_pipeline |
| FFT TLAST | ❌ Not tested | TLAST counter exists but no TB verifies correct frame delineation |
| IFFT tready/tvalid | ❌ Not tested | Same as FFT |
| Config channel | ❌ Not tested | s_axis_config_tdata hardwired |

### 2.4–2.17 Summary Table

| Concern | Status |
|---|---|
| FIFO overflow/underflow | ⚠️ Partial (cdc_i2s_to_dsp only) |
| Saturation and clipping | ❌ Not tested |
| Gain updates and bank swapping | ⚠️ Partial (flawed tests) |
| Mode changes | ⚠️ Partial (no streaming test) |
| SPI register accesses (full space) | ❌ Not tested (4 of 128 addresses) |
| I2S timing violations | ❌ Not tested |
| FFT/IFFT interface correctness | ❌ Not tested |
| Overlap-add reconstruction accuracy | ⚠️ Partial (Test 2 broken) |
| Ping-pong buffer operation | ❌ Not tested |
| Error handling and flag propagation | ❌ Not tested end-to-end |
| Startup behavior | ❌ Not tested |
| Long continuous streaming | ❌ Not tested (max 100 samples) |
| Backpressure scenarios | ❌ Not tested |
| Simultaneous events | ❌ Not tested |

---

## Section 3: Top 20 Missing Test Cases (Prioritized)

| # | Name | Target | Priority | Risk Justification |
|---|---|---|---|---|
| 1 | **SPI frame width fix + retest** | spi_slave | **Critical** | SPI is the only host interface. Corrupted frames = no register access in hardware. |
| 2 | **CDC handshake (spi_to_dsp) single transaction** | cdc_spi_to_dsp | **Critical** | Dropped request = host cannot control DSP. Silent failure. |
| 3 | **CDC handshake (dsp_to_spi) read response** | cdc_dsp_to_spi | **Critical** | Lost read response = host reads stale data. Silent failure. |
| 4 | **output_buffer ping-pong data integrity** | output_buffer | **Critical** | Corrupted output = corrupted audio. No TB exists. |
| 5 | **input_buffer overlap ordering** | input_buffer | **Critical** | Wrong overlap = DSP produces garbage. No TB exists. |
| 6 | **Bypass mode verification** | dsp_pipeline | **Critical** | Bypass is the fallback. If broken, device is silent on DSP failure. |
| 7 | **System-level smoke test** | top | **Critical** | No integration test. Wiring errors between modules are undetectable. |
| 8 | **overlap_add Test 2 fix** | overlap_add | **High** | Multi-frame OLA is the core algorithm. Current test is incomplete. |
| 9 | **spectral_proc bin-index alignment fix** | spectral_proc | **High** | Gain writes may not apply to intended bin. Test 3 is unreliable. |
| 10 | **FFT known-input verification** | fft_256 | **High** | Wrapper may have wiring errors (imag/real swap, TLAST misalignment). |
| 11 | **IFFT known-input verification** | ifft_256 | **High** | IFFT wrapper may have FWD_INV configuration error. |
| 12 | **Reset during active operation** | top, all | **High** | Reset glitches could hang FSMs. |
| 13 | **Mode change during streaming** | mode_ctrl, dsp_pipeline | **High** | User can change modes at any time. |
| 14 | **output_buffer underflow + recovery** | output_buffer | **High** | Underflow at startup is expected. Recovery must be clean. |
| 15 | **sat24() boundary values** | overlap_add | **High** | Saturation bugs cause audio wrapping (loud clicks). |
| 16 | **REG_STATUS composite read** | reg_file | **High** | Status register is the primary host diagnostic. |
| 17 | **clip_event → status_mon → REG_STATUS path** | dsp_pipeline, status_mon | **High** | Clip indicator is a user-facing feature. |
| 18 | **CDC FIFO write-when-full** | cdc_i2s_to_dsp | **High** | Data corruption on overflow = audio artifacts. |
| 19 | **Hermitian bin wrapping** | spectral_proc | **Medium** | Incorrect wrapping breaks IFFT real-output constraint. |
| 20 | **Back-to-back SPI transactions** | cdc_spi_to_dsp | **Medium** | Dropped writes = stale configuration. |

---

## Section 4: Verification Environment Assessment

### 4.1 Overall Verification Maturity Score: 28/100

| Category | Score | Weight | Weighted |
|---|---|---|---|
| Testbench existence | 45% | 25% | 11.3 |
| Testbench quality | 30% | 25% | 7.5 |
| Infrastructure | 25% | 20% | 5.0 |
| Methodology | 5% | 20% | 1.0 |
| Documentation | 10% | 10% | 1.0 |
| **Total** | | | **25.8 → 28** |

### 4.2 Verification Methodology Gaps

| Gap | Impact | Recommendation |
|---|---|---|
| **No SVA** | High | Protocol violations (AXI-Stream, SPI, CDC handshake) are invisible. |
| **No coverage collection** | High | No way to know which code paths are exercised. |
| **No constrained-random** | Medium | Corner cases from unusual input combinations are never explored. |
| **No formal verification** | Medium | CDC modules and FSMs are ideal formal targets. |
| **No test plan documents** | Medium | No traceability from requirements to tests. |

### 4.3 Infrastructure Gaps

| Gap | Severity |
|---|---|
| **CI simulation is non-gating** (`continue-on-error: true`) | Critical |
| **7 of 10 TBs have no runner script** | High |
| **Makefile only runs 2 TBs** | High |
| **No Vivado license in CI** | Medium |
| **No regression tracking** | Medium |

### 4.4 SVA Would Significantly Improve Verification For:

| Module | Property | Type |
|---|---|---|
| cdc_i2s_to_dsp | `wr_full_o → !wr_en_i` | Safety |
| cdc_spi_to_dsp | `dst_we_o` pulses exactly once per `src_we_i` | Liveness |
| spi_slave | `bit_cnt == 32 → state == ST_DECODE` within 1 cycle | Safety |
| i2s_rx | `valid_o` pulses exactly once per LRCLK period | Safety |
| spectral_proc | `out_v_o` follows `in_v_i` with exactly 4-cycle latency | Safety |
| mode_ctrl | `bank_commit_o` pulses exactly once per `mode_we_i` | Liveness |

### 4.5 Formal Verification Would Be Worthwhile For:

| Module | Why |
|---|---|
| cdc_spi_to_dsp | 4-phase handshake has deadlock/livelock risks |
| cdc_dsp_to_spi | Same handshake protocol |
| cdc_i2s_to_dsp | Gray-coded FIFO correctness under all clock ratios |
| mode_ctrl | 3-state FSM with bank alternation |
| reset_sync_stretch | Async-assert/sync-deassert metastability |

### 4.6 Constrained-Random Testing Would Add Value For:

| Module | Scenario |
|---|---|
| spectral_proc | Random gain values, random bin inputs → verify output bounds |
| overlap_add | Random scale_factor, random input values → verify no overflow |
| reg_file | Random address/data sequences → verify no cross-register corruption |
| spi_slave | Random frame data, random CS_N timing → verify protocol robustness |

---

## Section 5: Verification Maturity Score

### Score: 28/100

| Dimension | Score | Breakdown |
|---|---|---|
| **Testbench Existence** | 45/100 | 10 TBs for 22 modules. Effectively 10/19 testable modules = 53%. But 3 CDC modules, 2 buffers, status_mon, and top have no TBs. |
| **Testbench Quality** | 30/100 | Self-checking with pass/fail counts and timeout watchdogs (good). But: 1 TB has framing mismatch, 1 has internal inconsistency, most test only happy-path, corner cases sparse. |
| **Infrastructure** | 25/100 | 3 Vivado sim scripts but Makefile only runs 2. CI runs Verilator + 2 TBs but all non-gating. 7 TBs have no runner script. |
| **Methodology** | 5/100 | No SVA, no coverage, no constrained-random, no formal. Purely deterministic directed tests. |
| **Documentation** | 10/100 | TB headers describe test intent. No formal test plans, no coverage reports, no verification matrix. |

---

## Section 6: Verification Roadmap

### Phase 1: Critical (Must-Do Before Hardware Test) — 3-5 engineer-days

| # | Action | Effort | Rationale |
|---|---|---|---|
| 1 | Fix tb_spi_slave 33→32 bit framing | 0.5 day | Every SPI transaction is corrupted. Showstopper. |
| 2 | Create sim scripts for all 7 missing TBs | 0.5 day | 7 TBs cannot be run by any automated flow. |
| 3 | Make CI simulation gating | 0.5 day | Remove `continue-on-error: true`. |
| 4 | Create tb_output_buffer | 1 day | Last stage before audio output. No TB. |
| 5 | Create tb_input_buffer | 1 day | First DSP stage with 50% overlap. No TB. |
| 6 | Fix tb_overlap_add Test 2 | 0.5 day | Collect and verify both frames' outputs. |
| 7 | Fix tb_spectral_proc Test 3 bin-index | 0.5 day | Gain write test is unreliable. |
| 8 | Create tb_cdc_handshake (spi_to_dsp + dsp_to_spi) | 1 day | 4-phase handshake CDCs completely untested. |

### Phase 2: Important (Should-Do for Confidence) — 5-8 engineer-days

| # | Action | Effort |
|---|---|---|
| 9 | Create tb_status_mon | 0.5 day |
| 10 | Add bypass mode test to tb_dsp_pipeline | 0.5 day |
| 11 | Add FFT/IFFT known-input tests | 1 day |
| 12 | Add SVA to CDC modules | 1 day |
| 13 | Add SVA to SPI slave + I2S RX/TX | 1 day |
| 14 | Create system-level tb_top | 2 days |
| 15 | Add reset-during-operation tests | 1 day |
| 16 | Add mode-change-during-streaming test | 1 day |
| 17 | Fix tb_mode_ctrl MODE_SPEECH expected value | 0.5 day |

### Phase 3: Nice-to-Have (Mature Verification) — 8-12 engineer-days

| # | Action | Effort |
|---|---|---|
| 18 | Formal verification of CDC handshake | 2 days |
| 19 | Formal verification of Gray-coded FIFOs | 1 day |
| 20 | Constrained-random testing for spectral_proc | 2 days |
| 21 | Coverage collection and reporting | 1 day |
| 22 | Long-duration streaming tests (10,000+ frames) | 1 day |
| 23 | Full SPI register map sweep | 1 day |
| 24 | Test plan documentation | 2 days |
| 25 | Regression database | 1 day |

---

## Section 7: Biggest Blind Spots and Highest-Risk Untested Behaviors

### Top 10 Most Dangerous Untested Behaviors

| Rank | Behavior | Risk | Why It's Dangerous |
|---|---|---|---|
| **1** | **SPI frame width mismatch (33 vs 32 bits)** | **Critical** | TB and RTL disagree on frame width. If someone "fixes" the RTL to match the TB (33 bits), hardware breaks. If the TB passes with 33 bits, it validates the wrong protocol. |
| **2** | **CDC handshake (spi_to_dsp) never tested** | **Critical** | The only path for host-to-DSP control. A deadlock bug means the host cannot configure the DSP after power-up. Manifests as "device does nothing." |
| **3** | **CDC handshake (dsp_to_spi) never tested** | **Critical** | Read-data return path untested. Bug = host reads stale/garbage data from every register. Silent data corruption. |
| **4** | **output_buffer ping-pong never tested** | **Critical** | Last stage before DAC. Swap-timing bug = clicks, pops, or silence. No TB exists. |
| **5** | **input_buffer overlap ordering never tested** | **Critical** | Wrong 128-old + 128-new ordering = every FFT frame corrupted. DSP produces garbage. |
| **6** | **No system-level integration test** | **Critical** | 22 modules wired together but never tested as a system. A single misconnected wire is invisible to module-level TBs. |
| **7** | **CI simulation is non-gating** | **High** | TBs that exist and pass are not enforced by CI. A developer can break a tested module and merge without any CI failure. |
| **8** | **Reset sequence never tested end-to-end** | **High** | reset_sync_stretch generates resets for 3 clock domains. If stretch is too short, modules come out of reset metastable. Intermittent hardware failures — hardest class to diagnose. |
| **9** | **FFT/IFFT numerical correctness never verified** | **High** | Wrappers could have real/imaginary swaps, TLAST misalignment, or BFP exponent misrouting. Errors propagate silently through entire pipeline. |
| **10** | **Saturation/clipping path never tested** | **High** | overlap_add sat24() prevents audio wrapping. If broken, large signals wrap (+8388607+1 → -8388608), producing full-scale clicks that could damage headphones or hearing. |

---

## Appendix A: Testbench-to-Module Coverage Matrix

| Module | TB | Script | CI | Confidence |
|---|---|---|---|---|
| auris_pkg | — | — | — | N/A |
| top | ❌ | ❌ | ❌ | 0% |
| clk_gen | ❌ | ❌ | ❌ | 0% |
| i2s_rx | ✅ | ✅ | ✅ Verilator | 65% |
| i2s_tx | ✅ | ❌ | ❌ | 55% |
| spi_slave | ✅ ⚠️ | ✅ | ✅ Verilator | 40% |
| cdc_i2s_to_dsp | ✅ | ❌ | ❌ | 55% |
| cdc_dsp_to_i2s | ❌ | ❌ | ❌ | 0% |
| cdc_spi_to_dsp | ❌ | ❌ | ❌ | 0% |
| cdc_dsp_to_spi | ❌ | ❌ | ❌ | 0% |
| mode_ctrl | ✅ ⚠️ | ❌ | ❌ | 50% |
| reg_file | ✅ | ❌ | ❌ | 55% |
| status_mon | ❌ | ❌ | ❌ | 0% |
| dsp_pipeline | ✅ | ✅ | ❌ | 30% |
| input_buffer | ❌ | ❌ | ❌ | 0% |
| window_apply | ✅ | ❌ | ❌ | 70% |
| window_rom | (indirect) | ❌ | ❌ | 60% |
| fft_256 | (indirect) | ❌ | ❌ | 15% |
| ifft_256 | (indirect) | ❌ | ❌ | 15% |
| spectral_proc | ✅ ⚠️ | ❌ | ❌ | 45% |
| overlap_add | ✅ ⚠️ | ❌ | ❌ | 40% |
| output_buffer | ❌ | ❌ | ❌ | 0% |

## Appendix B: Known Bugs in Testbenches

| TB | Bug | Severity | Impact |
|---|---|---|---|
| tb_spi_slave | 33-bit framing vs RTL's 32-bit | **Critical** | All SPI transactions misaligned by 1 bit |
| tb_overlap_add | Test 2 expects 128 outputs instead of 256 | **High** | Second frame never verified |
| tb_spectral_proc | Test 3 bin-index misalignment | **High** | Custom gain not applied to intended bin |
| tb_mode_ctrl | MODE_SPEECH expects 23170 but RTL returns 16384 | **Medium** | Test will fail if run |
| tb_reg_file | Test 7 W1C manually clears source | **Medium** | Doesn't test actual RTL W1C logic |
| tb_window_apply | Header references stale hex file path | **Low** | Documentation only |
| tb_mode_ctrl | Dead tracking code | **Low** | Code quality only |

## Appendix C: CI Pipeline Analysis

```
lint-sv (Verible)     → PASS (gating)
lint-c (cpplint)      → PASS (gating)
lint-python (ruff)    → PASS (gating)
lint-markdown         → PASS (gating)
build-esp32           → PASS (gating)
build-fpga (Verilator lint) → continue-on-error: true ← NON-GATING
sim-fpga (Verilator)  → continue-on-error: true ← NON-GATING
  └─ tb_i2s_rx        → continue-on-error: true ← NON-GATING
  └─ tb_spi_slave     → continue-on-error: true ← NON-GATING
run-tools (Python)    → PASS (gating)
ci-pass (aggregate)   → Gating, but build-fpga and sim-fpga failures
                         are swallowed by continue-on-error
```

**Critical finding:** The `ci-pass` gate depends on `build-fpga` and `sim-fpga`, but those jobs use `continue-on-error: true` at the step level. The job itself succeeds even when individual steps fail. Therefore, **the CI gate passes even when FPGA linting and simulation fail**.

---

*End of Verification Coverage Audit*
