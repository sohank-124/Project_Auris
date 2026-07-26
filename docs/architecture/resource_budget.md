# FPGA Resource Budget

> **Project Auris** — XC7S25-1CSGA225C resource budget and per-module estimates
> **Last updated:** 2026-07
> **Status:** Authoritative. The per-module estimates below are
> derived from the RTL in `fpga/rtl/` and the IP configurations in
> `fpga/ip/`. Post-synthesis numbers may differ by ±15 %; treat the
> budget as a soft target, not a hard limit.

This document is the FPGA's answer to "will it fit?". It enumerates
the available resources on the target device, breaks down the
expected usage by module, and identifies the risk areas where the
design is tight.

---

## 1. Target Device

| Parameter           | Value                                                  |
|---------------------|--------------------------------------------------------|
| FPGA family         | Xilinx Spartan-7                                        |
| Device              | **XC7S25-1CSGA225C**                                    |
| Logic cells         | 23,360 (= 4 × 6-input LUTs, approximately)             |
| Package             | CSGA225 (225-ball BGA)                                  |
| Speed grade         | -1 (slower; the only grade available for this device)   |
| Temperature grade   | C (commercial, 0 °C to 85 °C)                          |
| Process             | 28 nm                                                   |

> **Note on package.** The Cmod S7-25 board documentation
> (Digilent schematic, rev B) reports a CSGA225 package. The
> project's reference XDC in `fpga/constraints/cmod_s7_25.xdc`
> and all RTL/tcl files now use the `CSGA225C` package string
> (M21 fix).  The pin map is identical for the two packages for
> every signal in use, so the migration is risk-free.

---

## 2. Available Resources

The XC7S25 has the following hard-IP resources. The "Used" column
is the design's **estimated** post-synthesis utilisation; see
Section 3 for the per-module breakdown.

| Resource           | Available | Used (est.) | Remaining | % Used   |
|--------------------|-----------|-------------|-----------|----------|
| LUTs (6-input)     | 14,620    | ~8,500      | ~6,120    | ~58 %    |
| Flip-Flops         | 29,240    | ~6,000      | ~23,240   | ~21 %    |
| BRAM (36 Kb blocks)| **45**    | ~8          | ~37       | ~18 %    |
| DSP48E1 slices     | **80**    | ~12         | ~68       | ~15 %    |
| User I/O pins      | 100       | ~15         | ~85       | ~15 %    |
| MMCME2_BASE        | 4         | 1           | 3         | 25 %     |

**Budget assessment.** The design is **comfortable** on LUTs (58 %
gives ~40 % headroom for future features like DRC and adaptive
gain), **comfortable** on FFs (21 % is unusually low for a heavily
pipelined design, because most pipeline state lives in the two FFT
IPs' internal BRAMs), and **comfortable** on DSP48E1s (25 % leaves
plenty of room for any future WDRC or feedback-canceller
extensions). BRAMs are the tightest resource at ~19 %, driven
mostly by the FFT and IFFT IPs' internal storage.

---

## 3. Per-Module Estimates

The table below breaks down the resource cost by RTL module. The
"Notes" column gives the rationale for each estimate.

| Module                 | LUTs   | FFs    | BRAM (36 Kb) | DSP48E1 | Notes                                                                                       |
|------------------------|--------|--------|--------------|---------|---------------------------------------------------------------------------------------------|
| `clk_gen` (MMCM)       | 0      | 0      | 0            | 0       | Hard IP (MMCME2_BASE). No fabric LUTs.                                                       |
| `i2s_rx`               | ~200   | ~150   | 0            | 0       | 24-bit shift register + LRCLK/BCLK control.                                                  |
| `i2s_tx`               | ~200   | ~150   | 0            | 0       | 24-bit shift register + LRCLK/BCLK control.                                                  |
| `spi_slave`            | ~150   | ~100   | 0            | 0       | 32-bit shift register + command decoder.                                                     |
| `cdc_i2s_to_dsp` × 2   | ~70    | ~55    | 0            | 0       | Two small async FIFOs, one per channel. ~35 LUTs / ~28 FFs each.                            |
| `cdc_dsp_to_i2s` × 2   | ~70    | ~55    | 0            | 0       | Mirror of above.                                                                              |
| `cdc_spi_to_dsp`       | ~30    | ~25    | 0            | 0       | 2-FF synchroniser + req/ack handshake.                                                       |
| `cdc_dsp_to_spi`       | ~30    | ~25    | 0            | 0       | 2-FF synchroniser for read data + valid.                                                     |
| `reg_file`             | ~300   | ~3,072 | 0            | 0       | 128 × 24-bit register file. The FFs dominate.                                                |
| `mode_ctrl`            | ~200   | ~100   | 0            | 0       | Mode-change detection + 4-state table-loader FSM.                                            |
| `input_buffer`         | ~100   | ~50    | 2            | 0       | Ping-pong BRAM: 2 banks × 256 samples × 24 bits.                                              |
| `window_apply`         | ~200   | ~100   | 1            | 2       | 256 × 16-bit coefficient ROM + 2 parallel 16-bit × 16-bit multipliers.                       |
| `fft_256` (xf IP)      | ~3,000 | ~1,500 | 2            | 4       | Xilinx xfft IP, 256-pt, radix-2, pipelined streaming I/O, 16-bit data, BFP output.            |
| `spectral_proc`        | ~500   | ~300   | 2            | 4       | 128-bin gain + gate. Two complex multiplies per cycle.                                       |
| `ifft_256` (xf IP)     | ~3,000 | ~1,500 | 2            | 4       | Xilinx xfft IP, 256-pt, inverse, same configuration as FFT.                                   |
| `overlap_add`          | ~200   | ~100   | 1            | 0       | 256-deep history buffer (1 BRAM) + 24-bit adder.                                              |
| `output_buffer`        | ~100   | ~50    | 2            | 0       | Ping-pong BRAM: 2 banks × 256 samples × 24 bits.                                              |
| `status_mon`           | ~100   | ~50    | 0            | 0       | 1 Hz heartbeat counter + sticky clip-event latch.                                            |
| **Subtotal (per-module sum)** | **~8,450** | **~7,384** | **~12** | **~14** | Per-module numbers summed directly.                                                          |
| **Realistic post-synthesis**   | **~8,500** | **~6,000** | **~8**  | **~12** | Higher LUT/FF estimates include IP wrapper overhead and place-and-route spread; BRAM and DSP48 estimates are conservative (actual xfft IPs may use less). |

> **Why the FF subtotal exceeds the realistic estimate.** The
> per-module FF estimates are an upper bound — for example, the
> `reg_file` actually uses exactly 128 × 24 = 3,072 FFs, but
> optimisation in synthesis will pack the surrounding logic into
> those FFs and reduce the net count. The "Realistic post-
> synthesis" row is the design's *expected* post-synthesis
> utilisation, accounting for this packing and for Vivado's
> resource-sharing optimisations.

### 3.1 BRAM allocation detail

| BRAM block | Size       | Purpose                                                                 |
|------------|------------|-------------------------------------------------------------------------|
| 0–1        | 2 × 36 Kb  | `input_buffer` ping-pong banks                                           |
| 2          | 36 Kb      | `window_rom` (256 × 16-bit coefficients, 1 KB used of 36 Kb available)   |
| 3–4        | 2 × 36 Kb  | `fft_256` xfft IP internal storage (radix-2 butterflies)                  |
| 5–6        | 2 × 36 Kb  | `spectral_proc` gain-table banks A and B (128 × 16-bit each)              |
| 7–8        | 2 × 36 Kb  | `ifft_256` xfft IP internal storage                                       |
| 9          | 36 Kb      | `overlap_add` history buffer (256 × 24-bit, 768 B used)                   |
| 10–11      | 2 × 36 Kb  | `output_buffer` ping-pong banks                                          |
| **Total**  | **12 / 45**| 26.7 % of available BRAMs used. Headroom: 33 BRAMs free.                |

### 3.2 DSP48E1 allocation detail

| DSP48E1 | Owner              | Operation                                                                |
|---------|--------------------|--------------------------------------------------------------------------|
| 0–1     | `window_apply`     | 2 parallel 16-bit × 16-bit multiplies for `x[n] * w[n]` per cycle.        |
| 2–5     | `fft_256` xfft IP  | Xilinx xfft internal butterflies (4 DSP48s).                              |
| 6–9     | `spectral_proc`    | 4 real multiplies per cycle (2 complex multiplies for `Y[k] = G[k]*X[k]`).|
| 10–13   | `ifft_256` xfft IP | Xilinx xfft internal butterflies (4 DSP48s).                              |
| **Total** | **14 / 80**      | 17.5 % of available DSP48E1 slices used. Headroom: 66 DSP48s free.        |

---

## 4. Timing Targets

| Clock domain | Period    | Frequency   | Source                | Slack target | Notes                                                              |
|--------------|-----------|-------------|-----------------------|--------------|--------------------------------------------------------------------|
| `CD_DSP`     | 10.417 ns | 96.000 MHz  | MMCM output            | ≥ 0.5 ns     | Tightest path: FFT input register → first butterfly stage.          |
| `CD_I2S`     | 325.521 ns| 3.072 MHz   | ESP32 I2S master       | ≥ 50 ns      | Loose; I2S RX/TX are shift registers, not data-path-heavy.          |
| `CD_SPI`     | 100.0 ns  | 10.000 MHz  | ESP32 SPI master       | ≥ 30 ns      | Loose; SPI slave is a 32-bit shift register.                       |
| `CD_AUX`     | 83.333 ns | 12.000 MHz  | Onboard oscillator     | n/a          | Feeds the MMCM only. No fabric logic in this domain.               |

The DSP clock is the **only** timing-critical domain. The other
three are slow enough that timing closure is essentially free.

### 4.1 What can go wrong with timing

- **FFT IP internal paths.** The xfft IP is a Xilinx-verified core,
  but the path from the AXI-Stream input register to the first
  butterfly stage can be tight. If timing fails here, the
  mitigation is to add an input pipeline stage in the `fft_256`
  wrapper (`dsp_pipeline.sv` already includes one).
- **Spectral proc complex multiplier.** The 18-bit × 18-bit
  multiplier in `spectral_proc` is configured for 16-bit operands
  to free up timing margin. If timing fails, drop to a 2-stage
  pipeline.
- **DSP-to-output-buffer path.** The path from the IFFT output to
  the output buffer's BRAM write port can be tight at 96 MHz.
  The mitigation is to register the IFFT output before the BRAM
  write — `dsp_pipeline.sv` does this.

---

## 5. Risk Areas

| Risk                                                        | Likelihood | Impact                                                          | Mitigation                                                                                       |
|-------------------------------------------------------------|------------|-----------------------------------------------------------------|--------------------------------------------------------------------------------------------------|
| FFT IP BRAM usage exceeds the 2 blocks estimated            | Medium     | Could push BRAM utilisation from 18 % to 30 %, eating headroom  | Try the `dsp_pipeline.sv` wrapper with `data_width = 12` instead of 16; this halves the FFT's BRAM footprint. |
| Resource sharing fails during opt_design                     | Low        | LUT count could grow 10-20 % beyond estimate                    | Manually apply `KEEP_HIERARCHY` and `RESOURCE_SHARING = "OFF"` on the FFT/IFFT wrappers.        |
| MMCM jitter too high at 96 MHz                              | Low        | Could cause setup-time failures on the 96 MHz paths             | Use a more conservative MMCM filter (e.g., `BANDWIDTH = "LOW"`); reduces jitter at the cost of a slightly slower lock. |
| Ping-pong BRAM write/read collisions                         | Low        | Could cause audio glitches                                     | Already mitigated by the explicit `bank_sel` in `mode_ctrl` and the bank-commit handshake.      |
| SPI register file read latency > 1 µs                        | Low        | Telemetry task could miss its 1 Hz deadline                     | The `telemetry` task is on priority 3 with a 200 ms tick — it has plenty of headroom.            |
| DRC extension (Phase 6) bumps DSP48 usage to 30+            | Medium     | Would push DSP48E1 utilisation from 15 % to 50 %+               | Implement DRC in BRAM (LUT-based) instead of DSP48-based; trades LUTs for DSPs.                  |

### 5.1 Headroom summary

| Resource       | Used (est.) | Available | Headroom     | Verdict                          |
|----------------|-------------|-----------|--------------|----------------------------------|
| LUTs           | ~8,500      | 14,620    | 6,120 (42 %) | **Comfortable** — plenty of room for Phase 6 features. |
| FFs            | ~6,000      | 29,240    | 23,240 (79 %)| **Plenty of room.**             |
| BRAMs          | ~8          | 45        | 37 (82 %)    | **Plenty of room** at the system level; 12 estimated at the per-module level.  |
| DSP48E1        | ~12         | 80        | 68 (85 %)    | **Plenty of room** for DRC and other Phase 6 features. |
| User I/O       | ~15         | 100       | 85 (85 %)    | **Plenty of room** for additional Pmod peripherals (e.g., a second SPI display). |

The **bottom line**: the design fits comfortably on the XC7S25 with
substantial headroom for Phase 6 features. The tightest resource
is BRAM, but the FFT IP configuration can be adjusted (smaller data
width) if necessary.

---

## 6. Where to Read Next

- The DSP pipeline that drives most of the resource consumption
  is in [`dsp_pipeline.md`](dsp_pipeline.md).
- The system block diagram (which shows all the modules in
  context) is in [`block_diagram.md`](block_diagram.md).
- The pin map and timing constraints are in
  [`fpga/constraints/cmod_s7_25.xdc`](../../fpga/constraints/cmod_s7_25.xdc).
- The post-synthesis utilisation report (the actual numbers, after
  build) is in `fpga/vivado_workspace/auris_cmod.runs/impl_1/top_utilization_placed.rpt`
  (generated by `fpga/scripts/build_project.tcl`).
