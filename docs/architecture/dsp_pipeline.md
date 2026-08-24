# DSP Signal Processing Pipeline

> **Project Auris** — 256-pt FFT-based spectral audio processor
> **Last updated:** 2026-07
> **Status:** Authoritative. The math, data formats, and latency
> budget below match the RTL in `fpga/rtl/dsp/` and the parameters
> in [`fpga/rtl/pkg/auris_pkg.sv`](../../fpga/rtl/pkg/auris_pkg.sv).

This document describes the in-FPGA audio processing pipeline in
detail: every block from the I2S RX port to the I2S TX port, the
mathematical operation performed at each stage, the fixed-point
format used at every interface, and the latency contributed by
each stage.

For a high-level block diagram, see
[`block_diagram.md`](block_diagram.md). For the clock-domain
crossings into and out of the pipeline, see
[`clock_domains.md`](clock_domains.md).

---

## 1. Overview

The DSP pipeline is a **256-point FFT-based spectral processor** that
operates at a 48 kHz sample rate with **50% overlap-add** and a
**Hann analysis/synthesis window**. The pipeline accepts a stream of
24-bit audio samples from the I2S RX block, applies a per-bin
frequency-domain gain (and a per-bin noise gate), and emits a
processed 24-bit stream to the I2S TX block. All processing happens
in the **96 MHz DSP clock domain** (`CD_DSP`).

The pipeline is parameterised on `FFT_LEN = 256` (in
`auris_pkg.sv`); changing this constant in one place resizes every
block in the chain, although the FPGA resource budget would need to
be re-validated for any value other than 256.

---

## 2. Signal Chain

The pipeline is a sequence of ten stages. Each stage hands off to
the next via a small FIFO, register, or ping-pong BRAM, so the
stages can run at slightly different rates without losing data.

| #  | Stage             | Module                  | Purpose                                                                                                |
|----|-------------------|-------------------------|--------------------------------------------------------------------------------------------------------|
| 1  | I2S RX            | `i2s_rx.sv`             | 24-bit samples at 48 kHz, L/R interleaved. BCLK-domain output, latched on LRCLK falling edge.          |
| 2  | CDC I2S → DSP     | `cdc_i2s_to_dsp.sv`     | Cross from 3.072 MHz BCLK to 96 MHz DSP. Async FIFO with Gray-coded pointers, 4 deep.                    |
| 3  | Input Buffer      | `input_buffer.sv`       | Accumulate 256 samples into a ping-pong BRAM. Bank A fills while bank B is consumed by the FFT, then swap. |
| 4  | Window Apply      | `window_apply.sv`       | Multiply each sample by `hann[n]` from `window_rom.sv`. Q2.14 coefficients.                              |
| 5  | FFT               | `fft_256.sv`            | 256-point radix-2 FFT (Xilinx xfft IP, pipelined streaming I/O, 16-bit data, BFP scaling).               |
| 6  | Spectral Proc     | `spectral/spectral_proc.sv` | Multiply each of 128 bins by its gain (Q2.14) and zero any bin below the noise-gate threshold.       |
| 7  | IFFT              | `ifft_256.sv`           | 256-point inverse FFT (Xilinx xfft IP, same configuration as FFT).                                      |
| 8  | Overlap-Add       | `overlap_add.sv`        | Reconstruct continuous output by summing the current frame with the previous frame's second half.       |
| 9  | Output Buffer     | `output_buffer.sv`      | Ping-pong BRAM. The DSP writes one bank while the I2S side reads the other.                              |
| 10 | Volume Control    | `volume_ctrl.sv`        | 31-level Q2.14 multiply of the reconstructed samples. Level 31 = unity (0x4000); level 0 = mute. Sits between OLA and output_buffer. |
| 11 | CDC DSP → I2S     | `cdc_dsp_to_i2s.sv`     | Cross back to 3.072 MHz BCLK. Async FIFO, 4 deep. I2S TX consumes one L/R pair per LRCLK falling edge.   |

A block-level view of the chain is in
[`block_diagram.md`](block_diagram.md) Section 1.

---

## 3. Mathematical Details

This section is the math reference for the pipeline. All formulas
use 0-based indexing unless noted.

### 3.1 Hann analysis/synthesis window

The Hann window is a symmetric raised-cosine window:

```
w[n] = 0.5 - 0.5 * cos(2π * n / (N - 1))   for n = 0, 1, ..., N - 1
```

With `N = 256`, the coefficients are pre-computed by
`tools/win_gen/gen_hann_coeffs.py` and stored in
`window_rom.sv` as 16-bit Q2.14 values (`hann_256.hex` /
`hann_256.coe`). The window satisfies the **COLA** (Constant
Overlap-Add) condition at 50% overlap:

```
w[n] + w[n + N/2] = 1.0   for all n = 0, 1, ..., N/2 - 1
```

This identity is what makes overlap-add reconstruction
distortion-free. Proof: by the symmetry `w[N-1-n] = w[n]`, the
sum of the two windows at the overlap boundary is constant.

### 3.2 FFT

The forward FFT computes:

```
X[k] = Σ_{n=0}^{N-1}  x[n] * exp(-j * 2π * k * n / N)
       for k = 0, 1, ..., N - 1
```

The implementation uses the Xilinx xfft IP in **pipelined streaming
I/O** mode, with **radix-2/burst I/O architecture**, **16-bit fixed-
point input**, and **block-floating-point (BFP) output**. The BFP
format automatically scales each block's output exponent to
maximise dynamic range; the exponent is captured once per block and
applied to the spectral processing stage.

### 3.3 Per-bin gain and noise gate

For each of the 128 stored bins (`k = 0, 1, ..., 127`), the
spectral processor computes:

```
Y[k] = G[k] * X[k]   if  |X[k]| >= threshold
Y[k] = 0              otherwise
```

Where `G[k]` is the **per-bin gain** (Q2.14, from the active gain
table bank) and `threshold` is the per-mode noise-floor
threshold. The threshold is part of the per-mode configuration
shipped inside `mode_ctrl.sv`'s pre-computed tables; the
Speech mode applies gating, the other modes do not. The gain-
table values are generated by
`tools/profile_gen/gen_default_tables.py` and stored as constant
data inside the `mode_ctrl.sv` RTL.

The 128 upper bins (`k = 128, ..., 255`) are the conjugates of the
lower bins (`X[k] = conj(X[N-k])`) and are written back
automatically by the spectral processor before the IFFT.

### 3.4 IFFT

The inverse FFT computes:

```
y[n] = (1 / N) * Σ_{k=0}^{N-1}  Y[k] * exp(+j * 2π * k * n / N)
       for n = 0, 1, ..., N - 1
```

The 1/N scaling is **absorbed into the per-bin gain** at synthesis
time (the gain table is pre-divided by 256 by the tool
`tools/profile_gen/gen_gain_profile.py`). This avoids a multiply
inside the IFFT, saving 2 DSP48E1 slices per bin.

### 3.5 Overlap-Add

The output reconstruction is the standard 50% overlap-add:

```
out[2*m + i]     = y_prev[N/2 + i] + y_curr[i]      for i = 0, ..., N/2 - 1
out[2*(m+1) + i] = y_curr[N/2 + i]                  (will be summed with next frame)
```

Where `y_prev` is the previous frame's IFFT output, `y_curr` is
the current frame's, and `m` is the frame index. Because of the
COLA condition on the Hann window, the sum of the two overlapping
windowed contributions equals the underlying signal exactly, up
to the quantisation error of the IFFT output.

### 3.6 End-to-end transfer function

The end-to-end transfer function (assuming no clipping) is:

```
Y[ω] ≈ G[ω] * X[ω]
```

Where `G[ω]` is the linearly-interpolated per-bin gain at angular
frequency `ω`, and the approximation is exact at the bin centres
and within ±1 bin width of them. This is a per-bin frequency
shaping — the spectral processor is a *programmable 128-band
graphic equaliser* with a noise gate.

---

## 4. Data Formats

The pipeline uses four distinct fixed-point formats. They are
chosen to maximise SNR at each interface while keeping the FPGA
resource cost in budget.

| Signal / Interface              | Format              | Range                              | Notes                                                                       |
|---------------------------------|---------------------|------------------------------------|-----------------------------------------------------------------------------|
| Input audio (I2S RX → CDC)      | 24-bit two's complement | [−2²³, 2²³ − 1]                | Matches the INMP441 native output. Sign-extended to 32 bits inside the FPGA. |
| I2S ↔ DSP CDC FIFO data         | 24-bit two's complement | [−2²³, 2²³ − 1]                | No re-quantisation in the CDC.                                              |
| Window coefficients (`window_rom`) | 16-bit Q2.14 unsigned | [0.0, ≈ 1.0]                   | Pre-computed by `tools/win_gen/gen_hann_coeffs.py`.                        |
| FFT input / IFFT output         | 16-bit two's complement | [−2¹⁵, 2¹⁵ − 1]                | 24-bit I2S samples are truncated to the upper 16 bits via `hi16()` in `auris_pkg.sv`. |
| FFT internal (BFP)              | 16-bit mantissa + 5-bit exponent | mantissa in [−1, 1), exponent in [0, 30] | Xilinx xfft IP. The exponent is passed through to spectral_proc and the IFFT scales the input by 2^(−exponent). |
| Per-bin gain (gain table)       | 16-bit Q2.14 unsigned | [0.0, ≈ 2.0]                    | `0x4000` = 1.0×, `0x0000` = mute, `0x7FFF` ≈ 1.9999×.                       |
| Master volume                   | 5-bit (0..31, mapped linearly to Q2.14 inside `volume_ctrl.sv`) | [0.0, ≈ 1.0] | Level 0 = mute; level 31 = unity (0x4000 Q2.14). The 5-bit level comes from the inline volume FSM in `top.sv` driven by BTN2/BTN3. |
| Output audio (DSP → I2S TX)     | 24-bit two's complement | [−2²³, 2²³ − 1]                | Sign-extended from 16-bit IFFT output, scaled by volume, sat24 at the volume stage. |

**Q2.14 encoding.** A Q2.14 unsigned value `q` represents the
real number `q / 2¹⁴`. So `0x4000 = 16384 / 16384 = 1.0`, and
`0x2000 = 8192 / 16384 = 0.5`. The format is unsigned because
gain values are always non-negative; the *signal* it multiplies
is a signed two's-complement integer.

---

## 5. Latency Budget

The end-to-end latency is dominated by the input-buffer fill time
(one frame = 256 samples = 5.33 ms at 48 kHz) and the FFT/IFFT
pipelining. The table below counts cycles at 96 MHz and time in
microseconds.

| Stage                     | Cycles (at 96 MHz)      | Time (µs)  | Notes                                                                  |
|---------------------------|--------------------------|------------|------------------------------------------------------------------------|
| I2S RX → CDC handshake    | 1 (handshake pulse)      | 0.01       | FIFO throughput, not latency.                                          |
| Input buffer fill         | 512                      | 5.33       | 256 samples × 2 (96 / 48 MHz over-sample)                              |
| Window apply              | 256                      | 2.67       | One multiply per sample, fully pipelined.                              |
| FFT (pipelined)           | ≈ 2,048                  | 21.3       | 8 stages × 256 cycles per stage, with overlap from pipelining.          |
| Spectral proc             | 128                      | 1.33       | One bin per cycle.                                                     |
| IFFT (pipelined)          | ≈ 2,048                  | 21.3       | Same as FFT.                                                           |
| Overlap-add               | 256                      | 2.67       | One add per output sample, fully pipelined.                             |
| Output buffer → CDC       | 1 (handshake pulse)      | 0.01       | FIFO throughput.                                                       |
| **Algorithmic total**     | **≈ 5,250 cycles**       | **≈ 54.7 µs** | Excludes the 5.33 ms input-buffer fill.                              |
| **End-to-end (with fill)** | —                      | **≈ 5.33 ms** | Limited by the LRCLK period at 48 kHz (one frame = 256 samples = 5.33 ms). |

The 5.33 ms end-to-end latency is the *algorithmic* latency. The
**perceived** latency (mic to headphone) is slightly higher because
of the analog path (mic + DAC converter latency ≈ 1 ms each) and
the I2S codec pipeline delay. Total perceived latency is on the
order of **7–8 ms**, well below the 20 ms threshold for detecting
audio delay in headphones.

> **Latency check.** The latency_analysis tool at
> `tools/latency_analysis/compute_latency.py` measures the actual
> latency on a built-and-flashed bitstream using a known input
> signal. Run it after every major pipeline change to confirm the
> theoretical 5.33 ms hasn't drifted.

---

## 6. Resource Estimates

The DSP pipeline is the dominant consumer of FPGA resources. The
table below breaks down the estimated cost per stage. The system-
level totals (across all modules, not just the pipeline) are in
[`resource_budget.md`](resource_budget.md).

### 6.1 BRAM usage

| Module              | BRAM (36 Kb blocks) | Bytes stored  | Notes                                                       |
|---------------------|---------------------|---------------|-------------------------------------------------------------|
| `input_buffer`      | 2                   | 2 × 256 × 24 = 1,536 B / block ≈ 1.5 KB / block | Ping-pong BRAM: 2 banks × 256 samples × 24 bits.       |
| `output_buffer`     | 2                   | 1.5 KB / block | Same as input_buffer.                                       |
| `window_rom`        | 1                   | 256 × 16 = 512 B | Single-port ROM, initialised from `hann_256.coe`.         |
| `fft_256` (xf IP)   | 2                   | ≈ 2 KB total  | Xilinx xfft IP, 256-pt, 16-bit data, BFP.                   |
| `ifft_256` (xf IP)  | 2                   | ≈ 2 KB total  | Same as FFT.                                                |
| `spectral_proc`     | 2                   | 2 × 128 × 16 = 1 KB / block | Two gain-table banks (double-buffered). |
| `overlap_add`       | 1                   | 256 × 24 = 768 B | History buffer for the previous frame's second half.    |
| **Pipeline total**  | **≈ 12**            |               | BRAM usage is tight; see [`resource_budget.md`](resource_budget.md) Section 4 for risk. |

### 6.2 DSP48E1 usage

| Module                | DSP48E1 | Notes                                                              |
|-----------------------|---------|--------------------------------------------------------------------|
| `window_apply`        | 2       | Two 16-bit × 16-bit multipliers operating in parallel.             |
| `spectral_proc`       | 4       | Two complex multiplies (4 real multipliers) per cycle, pipelined.  |
| `fft_256` (xf IP)     | 4       | Xilinx xfft IP, 256-pt, radix-2.                                  |
| `ifft_256` (xf IP)    | 4       | Same as FFT.                                                       |
| **Pipeline total**    | **≈ 14**| Of the 48 DSP48E1 slices on the XC7S25.                            |

### 6.3 LUT / FF usage

See [`resource_budget.md`](resource_budget.md) Section 2 for the
per-module breakdown. The two FFT IPs (FFT and IFFT) are the
single largest LUT consumers at ~3,000 LUTs each, accounting for
≈ 70 % of the pipeline's LUT cost.

---

## 7. Where to Read Next

- The system block diagram (showing the pipeline in context) is in
  [`block_diagram.md`](block_diagram.md).
- The four clock domains and the FIFOs that cross between the I2S
  domain and the DSP domain are in
  [`clock_domains.md`](clock_domains.md).
- The historical SPI register map (no longer in the build) is
  preserved in [`register_map.md`](register_map.md) for reference.
- The historical ESP32 firmware architecture (no longer in the
  build) is preserved in [`firmware_arch.md`](firmware_arch.md)
  for reference.
- The system-level resource budget is in
  [`resource_budget.md`](resource_budget.md).
- The latency_analysis tool (which measures the actual
  end-to-end latency on a built bitstream) is in
  `tools/latency_analysis/`.
