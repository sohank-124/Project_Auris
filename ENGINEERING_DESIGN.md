# Project Auris — Engineering Design Document

> **Document Purpose:** Onboard a new FPGA engineer to the Project Auris RTL design. **Last Updated:** 2026-08-12
> (banner + targeted patches; pre-migration body preserved) **Target Device:** Digilent Arty S7-25 Rev. E (Spartan-7
> XC7S25-1CSGA324C) **Toolchain:** Xilinx Vivado 2024.x, SystemVerilog-2009
>
> **⚠️ ARCHITECTURE BANNER — 2026-08-12 FPGA-only migration.** This document was authored for the pre-migration ESP32 +
> FPGA architecture. Several sections below describe the SPI bus, the ESP32 host, the 4-phase SPI↔DSP CDC handshake,
> the 128-entry register file, the ESP32 firmware integration, and the three clock-domain crossing topology (DSP / I2S /
> SPI). Those modules and topologies were removed on 2026-08-12. The FPGA-only architecture is **two clock domains
> only** (CD_DSP at 96 MHz and CD_I2S at 3.072 MHz / 48 kHz) with **two async FIFO CDCs**, **no SPI host**, and **no
> ESP32**. Onboard push buttons drive inline mode and volume FSMs in `top.sv`.
>
> **For the current architecture, see** [`docs/fpga_only_architecture.md`](docs/fpga_only_architecture.md).
>
> The sections below retain their pre-migration text for the historical record. Each ESP32-era section has been
> annotated with `[FPGA-only 2026-08-12: ...]` markers explaining what changed. **Do not** implement anything described
> in the pre-migration body; it is no longer in the build.

---

## 1. Executive Summary

### 1.1 Project Purpose

Project Auris is an educational FPGA project that implements a real-time spectral audio processor on a Spartan-7 FPGA.
The system captures audio from an INMP441 MEMS microphone via I2S, processes it through a 256-point FFT-based spectral
pipeline (windowing, per-bin gain, noise gate, overlap-add reconstruction), and outputs the processed audio to a
PCM5102A DAC driving wired headphones.

**[FPGA-only 2026-08-12]** An ESP32 microcontroller **is no longer** in the build. The FPGA is the sole control and
signal-processing entity. Onboard push buttons drive inline mode and volume FSMs in `top.sv`. The FPGA generates the I2S
bus clocks (BCLK 3.072 MHz, LRCLK 48 kHz) on-board via the MMCM in `clk_gen.sv`.

The project demonstrates FPGA engineering practices — RTL design, DSP, timing closure, clock-domain crossing, and
modular system architecture. **It is not a commercial or medical hearing aid.**

### 1.2 High-Level Architecture

```text
[FPGA-only 2026-08-12: The pre-migration ASCII diagram above showed an
ESP32 microcontroller connected to the FPGA over SPI. That hardware is
gone. The current architecture is:

   INMP441 (I2S slave)  <-- SD -->  FPGA (Arty S7-25)  -- SD -->  PCM5102A (I2S slave) --> headphones
                                  BCLK, LRCLK  -->  both codecs (FPGA is the master)

The FPGA drives BCLK and LRCLK to both codecs, receives mic data from
the INMP441, processes through the FFT pipeline, drives processed audio
to the PCM5102A. Onboard push buttons (BTN0-3) drive the mode and volume
FSMs inside the FPGA; the RGB LED indicates the active mode; STATUS0
toggles at 1 Hz as a heartbeat; STATUS2 is a sticky clip indicator.
See docs/fpga_only_architecture.md for the canonical block diagram.]
```

### 1.3 Major Design Goals

1. **Correctness above all** — no hacks for compilation convenience
2. **Professional RTL quality** — parameterized, modular, well-commented
3. **Real-time operation** — 48 kHz throughput sustained at 96 MHz DSP clock
4. **Demonstrate CDC expertise** — two asynchronous clock domains with proper async FIFOs
5. **Spartan-7 optimized** — BRAM inference, LUTRAM where appropriate, DSP48E1 for multiplies
6. **Educational value** — code that teaches, not just works

**[FPGA-only 2026-08-12]** Goal #4 was previously "three asynchronous clock domains" (DSP / I2S / SPI). The SPI clock
domain was removed when the ESP32 was removed. The two remaining domains (CD_DSP and CD_I2S) are still treated as
mutually asynchronous in the XDC, and the two CDC FIFOs are explicitly designed to handle the crossing regardless of
phase.

### 1.4 Current Implementation Status

**Implemented (FPGA-only build, 2026-08-12):**

- Two clock domains: 96 MHz DSP, 3.072 MHz I2S BCLK (48 kHz LRCLK derived)
- MMCM-based clock generation (12 MHz → 96 MHz) + fractional divide-by-31.25 BCLK divider
- FPGA is the I2S master; INMP441 and PCM5102A are I2S slaves
- I2S slave receiver (INMP441) and slave transmitter (PCM5102A)
- Mode controller with pre-computed per-mode gain tables (4 modes: General, Speech, Music, Hearing)
- Full spectral DSP pipeline: input buffer → Hann window → 256-pt FFT → spectral proc (per-bin gain + noise gate) →
  256-pt IFFT → overlap-add → volume_ctrl → output buffer
- BFP exponent alignment for overlap-add
- CDC: two async FIFOs (I2S↔DSP, ×2 for L/R), Gray-coded pointers, depth 4
- Button debouncer: 4 active-low buttons, 20 ms debounce
- Inline FSMs in top.sv for mode (2-bit, wraps) and volume (5-bit, saturates 0..31)
- Status monitor: 1 Hz heartbeat, sticky clip latch, RGB LED mode indicator
- Bypass mode: direct passthrough of post-CDC input to output (1-cycle register)

**[FPGA-only 2026-08-12]** The following items were in the pre-migration "Implemented" list and have been **removed**
from the build:

- ~~SPI Mode-0 slave with 32-bit frame protocol~~ — no host interface
- ~~Register file (128 × 24-bit BRAM + shadow FFs)~~ — mode/volume driven by inline FSMs
- ~~CDC: 4-phase handshake (SPI↔DSP)~~ — no SPI clock domain

**[FPGA-only 2026-08-12]** The following items were in the pre-migration "Not Yet Implemented" list and are now
**implemented** in the FPGA-only build:

- ~~Per-mode gain shaping (audiogram compensation, speech enhancement)~~ — done; four pre-computed gain tables in
  `mode_ctrl.sv`
- ~~Digital volume control~~ — done; `volume_ctrl.sv` with 31 levels

**Not Yet Implemented (still accurate):**

- DRC (Dynamic Range Compression) — Phase 4
- Formal verification

---

## 2. System Architecture

### 2.1 Complete Block Diagram

```text
[FPGA-only 2026-08-12: The ASCII diagram above showed an ESP32 connected
to the FPGA over SPI in a third clock domain (CD_SPI at ≤10 MHz). That
hardware and topology are gone. The current architecture is the
FPGA-only two-domain topology:

                             ┌─────────────────────────────────────────────────────────┐
                             │                    Spartan-7 FPGA                         │
                             │                                                          │
   ┌──────────┐             │  ┌────────┐   ┌───────┐                                  │
   │ 12 MHz   │─────────────►│  │ MMCM  │──►│  DSP  │──► DSP Domain (96 MHz)             │
   │  Osc.    │             │  │ 96 MHz │   │ Reset │                                  │
   └──────────┘             │  └────────┘   └───────┘                                  │
                            │  ┌────────┐   + frac. divider (31.25) + ÷64 LRCLK     │
                            │  │  clk   │                                            │
                            │  │  gen   │──► i2s_bclk_o (3.072 MHz, OUTPUT)          │
                            │  └────────┘──► i2s_lrclk_o (48 kHz, OUTPUT)              │
                            │                                                          │
   ┌──────────┐             │  ┌────────┐    ┌─────────┐                              │
   │ INMP441  │──I2S────────│─►│ i2s_rx │─CDC─► i2s_to  │                              │
   │  (MIC)   │  (FPGA mstr)│  └────────┘ FIFO  dsp       │──► input_buffer → window  │
   └──────────┘             │   I2S BCLK           │   │    apply → fft_256 →         │
                            │   (3.072 MHz)        │   │    spectral_proc →           │
                            │                      ▼   │    ifft_256 → overlap_add    │
                            │  ┌─────────────┐ dsp_out_l/r (96 MHz)                    │
                            │  │ dsp_pipeline │──►  ... → output_buffer → volume_ctrl  │
                            │  └─────────────┘        │                                │
                            │                          ▼                               │
                            │  ┌─────────┐  ┌─────┐ ┌─────┐                            │
                            │  │ cdc_    │  │ i2s │ │PCM5102A │──► headphones          │
                            │  │ dsp_to_ │─►│ tx  │►│        │                          │
                            │  │ i2s     │  └─────┘ └────────┘                          │
                            │  └─────────┘                                            │
                            └─────────────────────────────────────────────────────────┘

Onboard push buttons (BTN0-3, active-low, debounced in btn_debounce.sv)
  drive inline mode and volume FSMs inside top.sv. The RGB LED
  indicates the active mode. STATUS0 is a 1 Hz heartbeat; STATUS2 is
  a sticky clip indicator. There is no SPI host, no register file,
  and no third clock domain.

See docs/fpga_only_architecture.md for the canonical Mermaid
block diagram and the per-stage description.]
```

### 2.2 End-to-End Audio Path

```text
[FPGA-only 2026-08-12: The pre-migration text called the INMP441 the
"I2S Master" and the PCM5102A an "I2S Slave". The FPGA is now the I2S
master for both directions. The FPGA drives BCLK and LRCLK to both
codecs.]

INMP441 (I2S Slave)              FPGA (I2S Master)              PCM5102A (I2S Slave)
     │                                   │                            │
     │  BCLK (3.072 MHz) ◄───────────────┼───────────────► (codec)    │
     │  LRCLK (48 kHz)   ◄───────────────┼───────────────► (codec)    │
     │  SDATA ──────────────────────────►│ i2s_rx ──► CDC ──► DSP     │
     │                                   │                pipeline     │
     │                                   │ DSP ──► CDC ──► i2s_tx ────┤► DIN
     │                                   │                            │
```

**Data Format:** 24-bit, MSB-first, standard I2S (Philips) mode, 48 kHz sample rate, stereo (left channel processed,
right channel duplicated for MVP).

### 2.3 Control Path

```text
[FPGA-only 2026-08-12: The control path no longer traverses a SPI bus.
The ESP32 host, the spi_slave, the reg_file, and the SPI↔DSP CDC
handshakes are gone. Control inputs are entirely internal to the FPGA:

  BTN0..3 (active-low, on Arty S7-25 PCB)
     │
     ▼
  btn_debounce.sv (20 ms, press/release edge pulses)
     │
     ├──► inline mode FSM (top.sv, 2-bit, wraps): current_mode
     │       │
     │       ├──► mode_ctrl.sv  (loads pre-computed per-mode gain
     │       │      table into inactive bank of spectral_proc's BRAM)
     │       │              │
     │       │              ▼
     │       │      spectral_proc (per-bin gain + noise gate)
     │       │
     │       └──► RGB LED decoder (top.sv, active-low drive)
     │
     └──► inline volume FSM (top.sv, 5-bit, saturates 0..31): volume_level
             │
             └──► dsp_pipeline.volume_i → volume_ctrl (Q2.14 multiply
                    + sat24, mute at level 0) → output_buffer

Mode and volume changes are entirely internal to the CD_DSP clock
domain (96 MHz); they do not cross any clock domain.

For the historical pre-migration SPI control path, see the
un-annotated paragraph below.]
```

**[Historical — pre-migration]** ESP32 (SPI Master, Mode 0) FPGA (SPI Slave):

```text
ESP32 (SPI Master, Mode 0)          FPGA (SPI Slave)
     │                                   │
     │  SCLK (≤10 MHz) ──────────────────┤
     │  MOSI (32-bit frame) ────────────►│ spi_slave
     │◄─ MISO (24-bit read data) ────────┤
     │  CS_N ───────────────────────────►│
     │                                   │
     │                                   │ spi_slave ──► CDC handshake ──► reg_file
     │                                   │ reg_file ◄── CDC handshake ◄── (read data)
     │                                   │ reg_file ──► mode_ctrl, dsp_pipeline
```

**SPI Frame Format (32 bits, MSB-first):**

```text
Bit 31:    Start marker (must be 0)
Bits 30:24: 7-bit register address
Bit 23:    R/W# (1 = read, 0 = write)
Bits 22:0:  23-bit data payload (zero-extended to 24 bits internally)
```

The response is shifted out MSB-first on the subsequent transaction.

### 2.4 Clock Domains

| Domain | Clock        | Frequency | Source                                                               | Purpose                                                                                                           |
| ------ | ------------ | --------- | -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| CD_DSP | `clk_96mhz`  | 96 MHz    | MMCME2_BASE from 12 MHz osc                                          | All DSP processing, mode/volume FSMs, mode_ctrl, status_mon, button debouncer, DSP-side of the I2S↔DSP CDC FIFOs |
| CD_I2S | `i2s_bclk_o` | 3.072 MHz | **FPGA-generated** (`clk_gen.sv` fractional divider, 96 MHz ÷ 31.25) | I2S RX/TX serialization, BCLK output pin to both codecs, LRCLK output pin (÷64 from BCLK)                         |

[FPGA-only 2026-08-12: `i2s_bclk_o` is **now an output**, not an input. The ESP32-derived CD_SPI domain (≤10 MHz) is
gone. There are only two clock domains in this build.]

The two domains are **treated as mutually asynchronous** even though `i2s_bclk_o` is technically derived from the same
MMCM as `clk_96mhz`. The `set_clock_groups -asynchronous` declaration in `arty_s7_25.xdc` instructs Vivado to skip
inter-domain timing analysis and trust the two CDC FIFOs.

### 2.5 Reset Architecture

```text
[FPGA-only 2026-08-12: The pre-migration diagram above had three
reset_sync_stretch instances — one per clock domain (DSP, I2S, SPI).
The SPI domain is gone. There are now two instances — one for
CD_DSP and one for CD_I2S — sourced from the same MMCM `locked`
signal:]

clk_dsp_locked (MMCM) ──► reset_sync_stretch ──► rst_dsp_n  (96 MHz domain)
                        └──► reset_sync_stretch ──► rst_i2s_n (3.072 MHz BCLK domain)
```

Each reset generator provides:

- 2-FF synchronizer for safe CDC of the async reset source
- 16-cycle SRL-based stretcher (sync deassert, async assert)
- Independent per-domain reset output

The MMCM `locked` signal is the root reset source. All domains come out of reset only after the MMCM achieves lock.

---

## 3. Module Reference

### 3.1 `clk_gen` — Clock Generator

**Purpose:** MMCME2_BASE primitive wrapper that multiplies the 12 MHz onboard oscillator to 96 MHz for the DSP domain.

**Ports:**

- `clk_in1` (in): 12 MHz from onboard oscillator
- `clk_out1` (out): 96 MHz DSP clock, BUFG-distributed
- `locked` (out): MMCM lock indicator

**Configuration:** `CLKFBOUT_MULT_F=50.0`, `DIVCLK_DIVIDE=1`, `CLKOUT0_DIVIDE_F=6.25`. VCO = 12 × 50 / 1 = 600 MHz
(Spartan-7 MMCM minimum). Output = 600 / 6.25 = 96 MHz.

**Notes:** Implements MMCME2_BASE directly rather than using the Clocking Wizard IP, making the design portable across
Vivado versions without depending on a generated `.xci` file.

### 3.2 `i2s_rx` — I2S Slave Receiver

**Purpose:** Deserializes I2S bitstream from INMP441 MEMS microphone into 24-bit left/right samples.

**Ports:**

- `bclk_i`, `lrclk_i`, `sdata_i`, `rst_n_i` (inputs)
- `left_o[23:0]`, `right_o[23:0]`, `valid_o`, `overflow_o` (outputs)

**FSM:** `IDLE → WAIT → SHIFT_LEFT → SHIFT_RIGHT → VALID → IDLE`

**Key Detail:** Implements standard I2S (Philips) mode with 1-BCLK delay after LRCLK transition before capturing MSB.
The WAIT state absorbs this delay.

**Domain:** CD_I2S (BCLK domain). Outputs must cross CDC into CD_DSP.

### 3.3 `i2s_tx` — I2S Slave Transmitter

**Purpose:** Serializes 24-bit samples into I2S bitstream for PCM5102A DAC.

**Ports:**

- `bclk_i`, `lrclk_i`, `rst_n_i`, `left_i[23:0]`, `right_i[23:0]`, `valid_i` (inputs)
- `sdata_o`, `underflow_o` (outputs)

**FSM:** `IDLE → SHIFT_LEFT → SHIFT_RIGHT → IDLE`

**Key Detail:** `sdata_o` is clocked on the BCLK **falling** edge (separate `always_ff @(negedge bclk_i)` block) to give
the PCM5102A a half-period of setup+hold margin on the subsequent rising edge. The shift register and FSM run on the
BCLK rising edge.

**Underflow:** If `valid_i` is low at the LRCLK falling edge, the transmitter emits 24 bits of zero (silence) and
latches `underflow_o` sticky-high.

**Domain:** CD_I2S (BCLK domain). Inputs arrive via CDC from CD_DSP.

### 3.4 `spi_slave` — SPI Mode-0 Slave

**[FPGA-only 2026-08-12]** The `spi_slave` module has been **removed from the build**. There is no host SPI interface in
the FPGA-only architecture; mode and volume are driven by onboard push buttons through inline FSMs in `top.sv`. The
original source is preserved under `archive/rtl/spi_slave.sv` for historical reference.

**Purpose (historical):** Received 32-bit SPI frames from the ESP32 host, decoded the register address/RW/data, and
presented the decoded transactions to the CDC handshake module.

**Ports (historical):**

- `sclk_i`, `cs_n_i`, `mosi_i`, `rst_n_i`, `rdata_i[23:0]`, `rdata_valid_i` (inputs)
- `miso_o`, `addr_o[6:0]`, `wdata_o[23:0]`, `we_o`, `re_o` (outputs)

**FSM (historical):** `IDLE → SHIFT → DECODE → IDLE`

**Frame abort (historical):** If CS_N goes high before 32 bits are received, the partial shift register is discarded.

**Key Detail (historical):** MISO was driven combinationally (forced to 0 when CS_N was high for bus safety). The 23-bit
on-wire data field was zero-padded to 24 bits in `wdata_o`.

**Domain (historical):** CD_SPI (SCLK domain). No longer in the build.

### 3.5 `cdc_i2s_to_dsp` — CDC: I2S BCLK → DSP

**Purpose:** Asynchronous FIFO transporting 24-bit audio samples from the slow I2S domain to the fast DSP domain.

**Architecture:** 4-entry distributed-RAM FIFO with 3-bit Gray-coded pointers and 2-FF synchronizers.

**Key Details:**

- `ram_style = "distributed"` to use LUTRAM (saves BRAM)
- `ASYNC_REG = "TRUE"` on all synchronizer FFs
- Full-flag forced high during reset (Xilinx convention)
- Output valid is a registered 1-cycle pulse

**Domain Crossing:** Write side on BCLK, read side on 96 MHz DSP clock.

### 3.6 `cdc_dsp_to_i2s` — CDC: DSP → I2S BCLK

**Purpose:** Functionally identical to `cdc_i2s_to_dsp` but data flows from fast DSP domain to slow I2S domain. Same
4-entry distributed-RAM FIFO architecture.

### 3.7 `cdc_spi_to_dsp` — CDC: SPI SCLK → DSP (Handshake)

**[FPGA-only 2026-08-12]** The `cdc_spi_to_dsp` module has been **removed from the build**. There is no SPI clock domain
in the FPGA-only architecture; the only clock-domain crossings are the two I2S↔DSP async FIFOs. The original source is
preserved under `archive/rtl/cdc_spi_to_dsp.sv` for historical reference.

**Purpose (historical):** Transported multi-bit SPI control payloads (address + data + we/re flags) from the SPI domain
to the DSP domain using a 4-phase request-acknowledge handshake.

**Why a handshake instead of a FIFO (historical):** A 31-bit wide bus could not safely use parallel 2-FF synchronizers
because bits arrived skewed and the destination could sample transient intermediate values. The handshake guaranteed the
payload was stable before the destination sampled it.

**Protocol (4-phase, return-to-zero, historical):**

1. SPI side: latch payload, assert `req`
2. `req` 2-FF synced into DSP domain → `dst_req_sync[1]`
3. DSP side: on rising edge of `dst_req_sync[1]`, pulse we_o/re_o for one DSP cycle, assert `ack`
4. `ack` 2-FF synced back to SPI domain → clears `req`, both sides return to idle

**Domain Crossing (historical):** Write side on SCLK, read side on 96 MHz DSP clock.

### 3.8 `cdc_dsp_to_spi` — CDC: DSP → SPI SCLK (Handshake)

**[FPGA-only 2026-08-12]** The `cdc_dsp_to_spi` module has been **removed from the build**. There is no SPI clock domain
in the FPGA-only architecture. The original source is preserved under `archive/rtl/cdc_dsp_to_spi.sv` for historical
reference.

**Purpose (historical):** Counterpart to `cdc_spi_to_dsp`. Transported 24-bit read data from the DSP domain back to the
SPI domain using the same 4-phase handshake protocol.

**Key Detail (historical):** Data was held stable in `src_rdata_hold` from the time `src_req` was asserted until
`src_ack_sync[1]` was observed high, ensuring the slow SPI domain always saw a clean multi-bit value alongside its valid
strobe.

### 3.9 `reg_file` — Register File

**[FPGA-only 2026-08-12]** The `reg_file` module has been **removed from the build**. There is no SPI host interface to
read or write registers at runtime. Mode, volume, and gain tables are all driven internally:

- Mode is the 2-bit `current_mode` register in `top.sv`, updated by BTN0 / BTN1.
- Volume is the 5-bit `volume_level` register in `top.sv`, updated by BTN2 / BTN3.
- Per-bin gain tables are pre-computed inside `mode_ctrl.sv`; each mode change loads the corresponding table into the
  inactive bank of `spectral_proc`'s dual-port BRAM and atomically commits.
- Telemetry (peak meters, frame counter, error flags) is computed inside `dsp_pipeline.sv` and surfaced via the onboard
  STATUS0 (heartbeat) and STATUS2 (sticky clip) LEDs.

The original source is preserved under `archive/rtl/reg_file.sv` for historical reference.

**Purpose (historical):** 128 × 24-bit SPI-accessible register storage with BRAM inference, shadow registers for
DSP-facing combinational outputs, and special write side-effects.

**Architecture (historical):**

- **BRAM array:** 128 × 24-bit, `ram_style = "block"`, non-reset (required for BRAM inference on Spartan-7)
- **Shadow FFs:** 9 entries × 24 bits for addresses accessed combinationally by the DSP pipeline (mode, volume, gains,
  control)
- **Registered read path:** 1-cycle BRAM read latency with registered output mux

**Special operations (historical):**

- `REG_GAIN_DATA` (0x11): pulse gain_we_o, auto-increment gain address
- `REG_GAIN_COMMIT` (0x13): pulse bank_commit_o
- `REG_MODE` (0x03): update mode shadow
- `REG_ERROR_FLAGS` (0x24): write-1-to-clear
- `REG_STATUS` read: pulse clip_clear_o

**Domain (historical):** CD_DSP (96 MHz). Removed from the build.

### 3.10 `mode_ctrl` — Mode Controller

**Purpose:** On a mode-change event, loads a full default gain table (128 entries) into the inactive bank of
spectral_proc's dual-port BRAM, then atomically commits the bank swap.

**FSM:** `ST_IDLE → ST_LOAD → ST_COMMIT → ST_IDLE`

**Current Implementation:** For MVP, all modes load a flat unity-gain table (UNITY_GAIN_Q14 = 16384). Mode-specific
shaping (audiogram compensation, speech enhancement) is reserved for Phase 4.

**Key Detail:** Writes to the INACTIVE bank only. The bank swap is a single-cycle commit, so the audio path experiences
no gain glitches during mode transitions.

**Domain:** CD_DSP (96 MHz).

### 3.11 `status_mon` — Status Monitor

**Purpose:** Generates a 1 Hz heartbeat on `status_led_o` and latches clip events on `status_clip_o`.

**Ports:**

- `clk_i`, `rst_n_i`, `dsp_ready_i`, `clip_event_i`, `clip_clear_i` (inputs)
- `heartbeat_o`, `clip_latch_o` (outputs)

**Heartbeat:** Free-running toggle at HEARTBEAT_HZ (1 Hz). Held low when `dsp_ready_i` is low. Counter is sized for
HALF_PERIOD = 48,000,000 cycles (26 bits used, 28 allocated).

**Clip latch:** SR flip-flop — set on `clip_event_i`, cleared on `clip_clear_i`. Set dominates if both assert
simultaneously.

**Domain:** CD_DSP (96 MHz).

### 3.12 `dsp_pipeline` — DSP Pipeline Top-Level

**Purpose:** Top-level wrapper that instantiates and connects every DSP processing stage from input buffer through
overlap-add.

**Sub-modules instantiated:** `input_buffer`, `window_apply`, `fft_256`, `spectral_proc`, `ifft_256`, `overlap_add`,
`output_buffer`.

**Additional responsibilities:**

- FFT/IFFT TLAST generation (256-sample frame markers via 8-bit counters)
- BFP exponent delay pipeline (418-cycle SRL) for overlap-add alignment
- Control value truncation (24-bit → 16-bit Q2.14) for spectral_proc
- Output mux: bypass mode vs pipeline output
- Telemetry collection: peak meters, frame counter, error flags, clip detection

**Domain:** CD_DSP (96 MHz).

### 3.13 `input_buffer` — Input Buffer

**Purpose:** Accumulates 256-sample frames with 128-sample (50%) overlap from the incoming 48 kHz sample stream.

**Architecture:** Single true-dual-port 256 × 48-bit BRAM (packed `{right, left}`). Writes at 48 kHz sample rate; reads
at 96 MHz in 256-sample bursts.

**Trigger:** Every 128 writes (hop completion), a 256-sample burst read is triggered starting from the oldest sample
(`wr_ptr + 1`), wrapping at address 256. This naturally produces 128 "old" + 128 "new" samples — exactly what 50%
overlap-add requires.

**Overflow:** Sticky flag set if a write occurs during a read burst.

### 3.14 `window_apply` — Window Function

**Purpose:** Multiplies incoming 24-bit samples by a 256-entry Hann window (Q2.14) and presents the result to the FFT as
16-bit Q2.14 real/imaginary values.

**Pipeline:** 2 cycles total — Cycle 1: window ROM read; Cycle 2: signed multiply + truncate to Q2.14.

**Notes:** Left channel only is processed (MEMS mic is mono). Right channel data is present but the imaginary channel is
hardwired to zero for real-input FFT.

### 3.15 `window_rom` — Hann Window Coefficient ROM

**Purpose:** 256 × 16-bit ROM containing Hann window coefficients computed at elaboration time via `$cos()`.

**Formula:** `w[n] = 0.5 * (1 - cos(2πn/256))` in Q2.14 format.

**Key Detail:** Uses elaboration-time `$cos()` evaluation inside an `initial` block. Vivado infers this as a distributed
ROM with no external file dependency.

### 3.16 `fft_256` / `ifft_256` — FFT/IFFT IP Wrappers

**Purpose:** Thin AXI-Stream wrappers around the Xilinx xfft v9.1 IP core.

**Configuration (both instances):**

- Transform length: 256
- Architecture: Pipelined Streaming I/O
- Data width: 16-bit fixed-point
- Scaling: Block Floating Point (BFP)
- Output ordering: Natural order
- Rounding: Convergent
- Phase factor width: 16
- Memory: Block RAM for data and phase factors

**Difference:** `fft_256` drives `s_axis_config_tdata = 8'd1` (FWD_INV=1, forward). `ifft_256` drives
`s_axis_config_tdata = 8'd0` (FWD_INV=0, inverse).

**Output:** `m_axis_data_tdata[31:0] = {imag[15:0], real[15:0]}`, `m_axis_data_tuser[7:0]` = BFP block exponent.

### 3.17 `spectral_proc` — Spectral Processor

**Purpose:** Per-bin frequency-domain processing — gain application, master gain, and spectral noise gate.

**Pipeline (4 stages):**

1. **Gain lookup:** Read per-bin gain from active bank of dual-port BRAM
2. **Master gain:** `effective_gain = bin_gain × master_gain` (Q2.14 multiply)
3. **|X|² computation:** `mag² = re² + im²` for noise gate threshold
4. **Gate + multiply:** If `mag² < noise_floor`, apply `gate_ratio` attenuation; multiply bin by gated gain

**Gain Table:** 2 banks × 128 bins × 16 bits (Q2.14). Host writes inactive bank; `bank_commit_i` toggles active bank
atomically.

**Hermitian Constraint:** The 7-bit bin counter wraps after 127, so bins 128–255 receive gains from indices 0–127. For
real IFFT output, the gain table must satisfy `gain[k] = gain[128-k]` for k=1..127. MVP uses unity gain (trivially
satisfies this).

**Domain:** CD_DSP (96 MHz).

### 3.18 `overlap_add` — Overlap-Add Reconstructor

**Purpose:** Reconstructs the continuous output stream from overlapping IFFT frames using 50% overlap-add with BFP-aware
dynamic scaling.

**Algorithm:**

- History buffer: 128 × 48-bit single-port BRAM
- For samples 0–127: `output[n] = sat24((current[n] + history[n]) <<< (E_fft + E_ifft + 6))`
- For samples 128–255: `history[n-128] = current[n]` (store for next frame)

**Pipeline:** 2-stage — Stage 1: BRAM read → adder → variable barrel shifter; Stage 2: saturation → output register.

**Key Detail:** The `+6` constant compensates for static pipeline attenuation (window truncation, OLA structure, Q2.14
conversions).

### 3.19 `output_buffer` — Output Buffer

**Purpose:** Ping-pong buffer bridging the DSP domain's bursty output to the I2S TX's steady 48 kHz consumption rate.

**Architecture:** Single 256 × 48-bit BRAM (two halves of 128 samples each), registered read path. While DSP writes one
half, I2S reads the other. Halves swap on write completion.

**Underflow:** If the I2S read strobe fires before a complete half is available, output is forced to zero and
`underflow_o` is set sticky.

### 3.20 `top` — Top-Level Module

**Purpose:** Instantiates all sub-modules, connects clock/reset/CDC infrastructure, generates mode-change pulses, muxes
gain-table sources (host vs mode_ctrl), drives RGB LED.

**Key Connections:**

- CDC I2S→DSP: 2 instances (left + right channels), edge-detect empty→non-empty for `dsp_sample_valid` pulse generation
- CDC DSP→I2S: 2 instances (left + right channels), LRCLK falling-edge read strobe
- Gain table mux: `mode_ctrl` takes priority during table loads; host per-bin writes otherwise
- Mode-change pulse: edge-detect on `reg_dsp_mode` to drive `mode_ctrl`

---

## 4. DSP Pipeline

### 4.1 Step-by-Step Walkthrough

#### Stage 0: I2S Sample Arrival

The INMP441 MEMS microphone is configured as the I2S master, generating BCLK (3.072 MHz) and LRCLK (48 kHz). The FPGA
`i2s_rx` module deserializes the SDATA line into 24-bit left and right samples. On every complete L/R pair, `valid_o`
pulses for one BCLK cycle.

#### Stage 1: CDC I2S → DSP

The `cdc_i2s_to_dsp` async FIFO receives the sample and crosses it into the 96 MHz DSP domain. In `top.sv`, the FIFO
empty-flag is edge-detected to generate a single-cycle `dsp_sample_valid` pulse per new sample. Because 48 kHz is far
slower than 96 MHz, the FIFO stays near-empty (0–1 entries).

#### Stage 2: Input Buffer (Frame Accumulation)

The `input_buffer` writes each incoming sample into a 256 × 48-bit true-dual-port BRAM at the write pointer. Every 128
samples (one hop), the module triggers a 256-sample burst read starting from `wr_ptr + 1` (the oldest sample). This
produces a frame of 128 old samples + 128 new samples — the input for 50% overlap-add.

**Latency contribution:** 0–127 samples (0–2.65 ms), averaging ~1.32 ms at 48 kHz.

#### Stage 3: Windowing

The `window_apply` module multiplies each 24-bit sample by the corresponding Hann window coefficient (16-bit Q2.14 from
`window_rom`). Output is a 16-bit Q2.14 real value with imaginary = 0.

**Pipeline:** 2 cycles. Q-format: Q2.14 × Q2.14 → Q2.14 (bits [27:12] of product).

#### Stage 4: Forward FFT

The `fft_256` wrapper feeds the windowed samples into the xfft v9.1 IP core. 256 samples enter; 256 complex bins exit.
The IP uses Block Floating Point (BFP) scaling — it adjusts internal scaling per stage and outputs a block exponent
(`fft_blk_exp`) alongside the data.

**Latency:** ~414 cycles (pipelined streaming, N=256).

#### Stage 5: Spectral Processing

The `spectral_proc` module receives FFT bins sequentially (0–255) and applies:

1. Per-bin gain from active bank of dual-port BRAM
2. Master gain multiplication (effective_gain = bin_gain × master_gain)
3. Noise gate: if |X|² < noise_floor, attenuate by gate_ratio

The 7-bit bin counter wraps, so bins 128–255 share gain table indices 0–127. For real IFFT output, the gain table must
be symmetric: `gain[k] = gain[128-k]`.

**Pipeline:** 4 cycles. All multiplies in Q2.14 (16-bit signed).

#### Stage 6: Inverse FFT

The `ifft_256` wrapper feeds the processed bins into a second xfft v9.1 instance configured for inverse transform
(`FWD_INV=0`). Output is 256 time-domain samples with a second block exponent (`ifft_blk_exp`).

**Latency:** ~414 cycles.

#### Stage 7: BFP Exponent Alignment

The `fft_blk_exp` is delayed through a 418-cycle SRL pipeline (`BFP_PIPE_DELAY` in auris_pkg) so it arrives at
`overlap_add` synchronized with the corresponding IFFT output frame. The scale factor is `E_fft + E_ifft`.

**Pipeline depth:** 418 = 4 (spectral_proc) + ~414 (IFFT).

#### Stage 8: Overlap-Add

The `overlap_add` module reconstructs the continuous audio stream:

- For samples 0–127: `out[n] = sat24((cur[n] + hist[n]) <<< (E_fft + E_ifft + 6))`
- For samples 128–255: `hist[n-128] = cur[n]`
- Outputs exactly 128 samples per frame

**Pipeline:** 2 stages. The `+6` corrects for static window/OLA attenuation.

#### Stage 9: Output Buffer

The `output_buffer` ping-pong buffer receives 128-sample bursts from overlap_add and delivers them one sample at a time
on each 48 kHz `sample_clk_en_i` strobe.

#### Stage 10: CDC DSP → I2S

The `cdc_dsp_to_i2s` async FIFO crosses each output sample from the 96 MHz DSP domain back to the 3.072 MHz I2S BCLK
domain.

#### Stage 11: I2S Transmission

The `i2s_tx` module serializes each 24-bit sample into the I2S bitstream for the PCM5102A DAC. The DAC converts the
digital stream to analog and drives the headphone output.

### 4.2 Q-Formats

| Signal              | Format                | Range                       | Notes                   |
| ------------------- | --------------------- | --------------------------- | ----------------------- |
| I2S sample in/out   | 24-bit signed integer | ±8,388,607                  | Raw audio samples       |
| Window coefficients | 16-bit unsigned Q2.14 | [0, 16384]                  | Hann window, 0.0 to 1.0 |
| FFT/IFFT data       | 16-bit signed Q2.14   | ±(2 - 2⁻¹⁴)                 | BFP-scaled internally   |
| Per-bin gain        | 16-bit signed Q2.14   | ±(2 - 2⁻¹⁴)                 | Unity = 16384           |
| Master gain         | 16-bit signed Q2.14   | ±(2 - 2⁻¹⁴)                 | Applied after bin gain  |
| Noise floor         | 16-bit signed Q2.14   | Magnitude-squared threshold |                         |
| Gate ratio          | 16-bit signed Q2.14   | Attenuation when gated      |                         |
| OLA history         | 48-bit (2×24) packed  | ±8,388,607                  | Pre-shift, raw samples  |
| BFP exponents       | 8-bit unsigned        | 0–16 per stage              | Summed for OLA shift    |

### 4.3 FFT/IFFT Usage

Both FFT and IFFT use the Xilinx xfft v9.1 LogiCORE IP with identical configuration:

| Parameter          | Value                   |
| ------------------ | ----------------------- |
| Transform length   | 256                     |
| Architecture       | Pipelined Streaming I/O |
| Input width        | 16 bits                 |
| Phase factor width | 16 bits                 |
| Data format        | Fixed-point             |
| Scaling            | Block Floating Point    |
| Output ordering    | Natural order           |
| Rounding           | Convergent              |
| Clock frequency    | 96 MHz                  |
| AXI reset          | Enabled                 |

The two instances differ only in the runtime FWD_INV bit: 1 for FFT, 0 for IFFT.

### 4.4 Windowing

**Window:** Hann (Hanning) window, N=256.

**Formula:** `w[n] = 0.5 × (1 − cos(2πn/256))` for n = 0..255. _(Periodic Hann — denominator is N=256, not N−1=255. The
window is periodic, so the next frame's first sample matches this frame's last. Both periodic and symmetric Hann satisfy
the COLA condition with 50% overlap, so OLA reconstruction is identical either way.)_

**Format:** 16-bit unsigned Q2.14. Maximum value = 16384 = 1.0 in Q2.14.

**Generation:** Computed at RTL elaboration time using `$cos()` in an initial block. No external coefficient file
needed.

**Application:** Left-channel sample (upper 16 bits of 24-bit value) multiplied by window coefficient. Result truncated
to Q2.14. Imaginary channel = 0 (real-input FFT).

### 4.5 Overlap-Add

**Overlap:** 50% (128-sample hop, 256-sample frame).

**COLA Condition:** The Hann window with 50% overlap satisfies the Constant OverLap-Add condition — the sum of the
overlapped window functions equals a constant for all sample positions when using a Hann window. This guarantees gain
stability through the OLA reconstruction.

**BFP Scaling:** The static pipeline attenuation (from window truncation, Q2.14 conversions, and the OLA structure) is
compensated by an additional left-shift of 6 bits. The dynamic BFP scaling adds `E_fft + E_ifft` more bits, making the
total shift `E_fft + E_ifft + 6`.

**Saturation:** Output is clamped to ±8,388,607 (24-bit signed range).

### 4.6 Gain Table Operation

The gain table in `spectral_proc` is a dual-bank structure:

- **Bank A** and **Bank B**: each 128 × 16-bit BRAM
- **Active bank:** read by the DSP pipeline for per-bin gain
- **Inactive bank:** written by the host (SPI → reg_file → spectral_proc) or by mode_ctrl

**Atomic bank swap:** On `bank_commit_i`, the `active_bank` register toggles. Since the pipeline reads from the
previously-active bank during the entire frame, and the swap happens on the commit pulse (not mid-frame), there is no
gain glitch in the audio path.

**Host write path:** The host writes individual gain values to the inactive bank via `REG_GAIN_ADDR` + `REG_GAIN_DATA`.
Each write auto-increments the address. On `REG_GAIN_COMMIT`, the bank swap occurs.

**Mode load path:** On a mode change, `mode_ctrl` loads a full 128-entry default table into the inactive bank (one entry
per cycle, 128 cycles total), then commits.

**Symmetry constraint:** For real IFFT output, the gain table must satisfy `gain[k] = gain[128-k]` for k = 1..127. This
is automatically true for unity gain (MVP). Future per-mode tables must enforce this.

### 4.7 BFP Exponent Alignment

**Problem:** The FFT produces a block exponent (`fft_blk_exp`) at the END of the forward transform, but the overlap-add
module needs this exponent synchronized with the output of the IFFT — which arrives ~418 cycles later (spectral_proc
pipeline + IFFT latency).

**Solution:** A 418-deep shift register pipeline delays `fft_blk_exp` so it emerges at the same time as the
corresponding IFFT output frame:

```text
fft_blk_exp → [SRL delay line: 418 stages] → fft_exp_aligned
ifft_blk_exp ───────────────────────────────────────────────┐
                                                            ├→ ola_scale_factor = fft_exp_aligned + ifft_blk_exp
```

Vivado infers this as SRL32E shift-register LUTs (not FFs), saving ~3,300 flip-flops.

### 4.8 Pipeline Latency Summary

| Stage                              | Cycles @ 96 MHz | Time         |
| ---------------------------------- | --------------- | ------------ |
| CDC I2S→DSP                        | ~4              | ~42 ns       |
| Input buffer read burst            | 256             | 2.67 µs      |
| Window apply                       | 258             | 2.69 µs      |
| FFT (xfft v9.1, N=256)             | ~414            | 4.31 µs      |
| Spectral proc (4-stage × 256 bins) | 260             | 2.71 µs      |
| IFFT (xfft v9.1, N=256)            | ~414            | 4.31 µs      |
| Overlap-add (256 inputs)           | ~259            | 2.70 µs      |
| Output buffer (BRAM + alignment)   | ~2              | 21 ns        |
| CDC DSP→I2S                        | ~3 BCLK         | ~1 µs        |
| **Total fixed pipeline**           | **~1,870**      | **~19.5 µs** |

Variable latency from input buffer accumulation (0–2.65 ms) dominates total end-to-end delay.

---

## 5. Clock Domain Crossing

### 5.1 CDC Path Summary

| Path         | Source Domain      | Dest Domain        | Width          | Method                               | Module           |
| ------------ | ------------------ | ------------------ | -------------- | ------------------------------------ | ---------------- |
| I2S RX → DSP | CD_I2S (3.072 MHz) | CD_DSP (96 MHz)    | 24 bits × 2 ch | Async FIFO, Gray pointers, 2-FF sync | `cdc_i2s_to_dsp` |
| DSP → I2S TX | CD_DSP (96 MHz)    | CD_I2S (3.072 MHz) | 24 bits × 2 ch | Async FIFO, Gray pointers, 2-FF sync | `cdc_dsp_to_i2s` |

[FPGA-only 2026-08-12: The SPI → DSP and DSP → SPI CDC rows have been **removed**. There is no SPI clock domain in this
build; the two audio-path FIFOs are the only clock-domain crossings.]

### 5.2 FIFO Strategy (Audio Paths)

**Architecture:** Classic dual-clock asynchronous FIFO with:

- Binary write/read pointers, Gray-coded before crossing
- 2-FF synchronizers with `ASYNC_REG = "TRUE"` on each stage
- Full/empty detection via Gray code comparison:
  - Empty: `rd_gray == wr_gray_sync`
  - Full: `wr_gray == {~rd_gray_sync[PW-1:PW-2], rd_gray_sync[PW-3:0]}`

**Depth:** 4 entries. This is sufficient because the DSP domain (96 MHz) is 31× faster than the I2S sample rate (48 kHz
effective), so the DSP always drains the FIFO faster than the I2S fills it. A depth of 4 provides headroom for scheduler
jitter without consuming a full BRAM tile.

**Storage:** Distributed RAM (`ram_style = "distributed"`). For 4 entries × 24 bits = 96 bits total, LUTRAM is far more
efficient than BRAM (which would consume a full 18 Kb tile for the same 96 bits).

**Key design choice:** Full flag is forced high during reset (Xilinx convention). This prevents the producer from
writing before the first read-pointer synchronization completes, avoiding a cold-start corruption scenario.

### 5.3 Handshake Strategy (Control Path)

**Architecture:** 4-phase request-acknowledge handshake (return-to-zero).

**Why a handshake:** The SPI→DSP payload is 31 bits wide (7-bit address + 24-bit data + we + re). A plain parallel 2-FF
synchronizer would risk the destination sampling a transient value where bits from the old and new transaction are
mixed. The handshake guarantees:

1. The payload is latched and stable in the source domain before `req` is asserted
2. The destination only samples the payload after `req` has been synchronized and the payload has been stable for ≥2
   destination clock cycles
3. The source holds the payload stable until the destination acknowledges

**Sequence:**

```text
Source (SPI)                    Destination (DSP)
    │                                │
    ├─ latch payload, req=1 ────────►│ (payload stable)
    │                                ├─ 2-FF sync req
    │                                ├─ detect rising edge
    │                                ├─ pulse we_o/re_o
    │  ◄──────────── ack=1 ──────────┤
    ├─ see ack, req=0 ──────────────►│
    │                                ├─ see req=0, ack=0
    │  ◄──────────── ack=0 ──────────┤
    ├─ idle                          ├─ idle
```

**Throughput:** One transaction per ~4 source clock cycles + ~6 destination clock cycles. At 10 MHz SPI clock, this
supports ~2M transactions/second — far exceeding the expected control rate.

### 5.4 Synchronizers

All CDC modules use 2-FF synchronizers with the `(* ASYNC_REG = "TRUE" *)` attribute on every synchronizer flip-flop.
This attribute:

- Tells the Vivado placer to pack the two FFs into the same slice (minimizing routing delay between them)
- Reduces the metastability mean-time-between-failure (MTBF) to >10⁶ years for Spartan-7 at these clock rates

### 5.5 Why Each Approach Was Chosen

| Path               | Method            | Rationale                                                                                                                             |
| ------------------ | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Audio (I2S↔DSP)   | Async FIFO        | Continuous streaming data at fixed rate; FIFO provides buffering for rate mismatch; Gray pointers avoid multi-bit synchronizer issues |
| Control (SPI↔DSP) | 4-phase handshake | Sporadic, multi-bit payloads; handshake guarantees data stability without a full FIFO; minimal resource usage                         |

---

## 6. Reset Strategy

### 6.1 MMCM Lock

The MMCM `locked` output is the root reset source for the entire FPGA design. It is asserted only after the MMCM
achieves lock (VCO stable, output clocks valid). This guarantees that no logic operates on a gyrating or absent clock.

### 6.2 Reset Synchronizers

Each clock domain has an independent `reset_sync_stretch` module:

```text
src_rst_n_i (async) ──► [2-FF sync] ──► [16-bit SRL stretcher] ──► dst_rst_n_o (sync)
```

**2-FF synchronizer:** Safely crosses the async reset assertion into the destination clock domain. Both FFs have
`ASYNC_REG = "TRUE"`.

**SRL stretcher:** A 16-bit shift register that fills with 1s after the synchronized reset deasserts. The output
(`dst_rst_n_o`) goes high only when ALL bits are 1 — i.e., 16 cycles after the synchronized deassertion. This provides:

- **Async assert:** FFs cleared immediately (via async clear pin)
- **Sync deassert:** All FFs released simultaneously, 16 cycles after the last potentially metastable transition
- **Glitch filtering:** Short noise pulses on the reset source are absorbed by the shift register

**Stretcher depth:** 16 cycles (parameter `RESET_STRETCH_CYCLES`). On Spartan-7, this infers as an SRL16E primitive — a
single LUT per bit.

### 6.3 Per-Domain Reset Distribution

Three instances of `reset_sync_stretch` in `top.sv`:

| Instance    | Source      | Destination Domain        |
| ----------- | ----------- | ------------------------- |
| `u_rst_dsp` | MMCM locked | 96 MHz DSP domain         |
| `u_rst_i2s` | MMCM locked | 3.072 MHz I2S BCLK domain |
| `u_rst_spi` | MMCM locked | ≤10 MHz SPI SCLK domain   |

All share the same root source (MMCM locked) but stretch independently in their respective clock domains.

### 6.4 BRAM Reset Philosophy

Spartan-7 BRAM storage cells do NOT have an asynchronous reset pin. Including BRAM arrays inside
`always_ff @(posedge clk or negedge rst_n)` blocks forces Vivado to dissolve the BRAM into individual flip-flops (Synth
8-4767), consuming thousands of FFs.

**Design approach:** BRAM arrays live in non-reset `always_ff @(posedge clk)` blocks. Spartan-7 BRAM initializes to zero
after configuration, so the cold-start behavior is identical to a reset — all storage starts at zero. Only control FFs
(pointers, state machines, output registers) retain async reset.

**Affected modules:** `reg_file`, `input_buffer`, `output_buffer`, `overlap_add` (history buffer).

### 6.5 Startup Behavior

1. Power-on → FPGA configuration from SPI flash
2. Configuration complete → MMCM starts, `locked` initially low
3. All three `reset_sync_stretch` modules hold their domains in reset
4. MMCM achieves lock (typically <100 µs) → `locked` goes high
5. Synchronizers propagate the deassertion; stretchers count 16 cycles
6. All domains come out of reset simultaneously (from their perspective)
7. CDC FIFOs start with full-flag high (Xilinx convention) → prevents premature writes
8. First read-pointer synchronization propagates → FIFOs become operational
9. I2S samples begin flowing; first 256-sample frame has zeroed history (cold-start artifact, single frame)

---

## 7. Memory Architecture

### 7.1 BRAM Usage

| Module          | Array         | Dimensions    | Total Bits       | Inferred as                      |
| --------------- | ------------- | ------------- | ---------------- | -------------------------------- |
| `input_buffer`  | `mem`         | 256 × 48 bits | 12,288           | True dual-port BRAM              |
| `output_buffer` | `mem`         | 256 × 48 bits | 12,288           | Single-port BRAM                 |
| `reg_file`      | `regs`        | 128 × 24 bits | 3,072            | Single-port BRAM                 |
| `spectral_proc` | `gain_bank_a` | 128 × 16 bits | 2,048            | Single-port BRAM                 |
| `spectral_proc` | `gain_bank_b` | 128 × 16 bits | 2,048            | Single-port BRAM                 |
| `overlap_add`   | `history`     | 128 × 48 bits | 6,144            | Single-port BRAM                 |
| **Total BRAM**  |               |               | **~37,888 bits** | **~2.5 BRAM tiles (18 Kb each)** |

The xfft v9.1 IP cores also consume BRAM internally for data and phase factor storage (configured via
`memory_options_data = block_ram`, `memory_options_phase_factors = block_ram`), not reflected above.

### 7.2 LUTRAM Usage

| Module               | Array | Dimensions    | Total Bits      | Inferred as                |
| -------------------- | ----- | ------------- | --------------- | -------------------------- |
| `cdc_i2s_to_dsp` × 2 | `mem` | 4 × 24 bits   | 96              | Distributed RAM            |
| `cdc_dsp_to_i2s` × 2 | `mem` | 4 × 24 bits   | 96              | Distributed RAM            |
| `window_rom`         | `mem` | 256 × 16 bits | 4,096           | Distributed ROM            |
| **Total LUTRAM**     |       |               | **~4,288 bits** | **~67 LUTs (64 bits/LUT)** |

### 7.3 Register File Organization

**BRAM array:** `regs[0:127]` — 128 × 24-bit, `ram_style = "block"`. Non-reset for BRAM inference.

**Shadow FFs** (9 entries × 24 bits = 216 FFs): Mirror specific addresses for combinational DSP access:

- `mode_reg` → `reg_dsp_mode`
- `volume_reg` → `dsp_volume_o` (reserved, not yet connected to DSP)
- `noise_floor_reg` → `noise_floor_o`
- `gate_ratio_reg` → `gate_ratio_o`
- `master_gain_reg` → `master_gain_o`
- `gain_addr_reg` → `gain_addr_o`
- `gain_data_reg` → `gain_wdata_o`
- `gain_bank_reg` → `gain_bank_o`
- `control_reg` → `dsp_enable_o`

**Read path:** Registered (1-cycle BRAM latency). Read-only addresses (status, telemetry) are muxed from live inputs
rather than BRAM storage.

### 7.4 Buffer Organization

**Input buffer:** 256 × 48-bit true-dual-port BRAM, packed as `{right[23:0], left[23:0]}`. Write port at 48 kHz sample
rate; read port at 96 MHz burst rate.

**Output buffer:** 256 × 48-bit single-port BRAM. Upper half (addr[7]=1) = bank B, lower half (addr[7]=0) = bank A.
Ping-pong swapping on write completion.

**Overlap-add history:** 128 × 48-bit single-port BRAM. Read during first half of frame; write during second half. Never
simultaneous R/W on same address.

### 7.5 Gain Tables

Dual-bank (`gain_bank_a`, `gain_bank_b`), each 128 × 16-bit. Both initialized to UNITY_GAIN_Q14 (16384) via initial
blocks. Host writes target the inactive bank; `bank_commit_i` atomically swaps. Both banks inferred as BRAM.

### 7.6 Window ROM

256 × 16-bit, elaboration-time computed via `$cos()`. Inferred as distributed ROM (LUT-based). No BRAM usage.

---

## 8. Register Map

### 8.1 Address Map

| Address | Name                   | R/W | Width | Description                                                                                   |
| ------- | ---------------------- | --- | ----- | --------------------------------------------------------------------------------------------- |
| `0x00`  | `REG_VERSION`          | RO  | 24    | Hardware version (7 bits, currently 0x0A)                                                     |
| `0x01`  | `REG_STATUS`           | RO  | 8     | Status flags (ready, locked, clip, dsp_en, mode)                                              |
| `0x02`  | `REG_CONTROL`          | RW  | 1     | Bit 0: dsp_enable (1=run, 0=bypass)                                                           |
| `0x03`  | `REG_MODE`             | RW  | 2     | Operating mode (0=General, 1=Hearing, 2=Speech, 3=Bypass)                                     |
| `0x04`  | `REG_VOLUME`           | RW  | 5     | Volume level (0–31). **Reserved: not yet wired to DSP**                                       |
| `0x05`  | `REG_NOISE_FLOOR`      | RW  | 16    | Noise gate threshold (Q2.14 magnitude-squared)                                                |
| `0x06`  | `REG_NOISE_GATE_RATIO` | RW  | 16    | Noise gate attenuation ratio (Q2.14)                                                          |
| `0x07`  | `REG_DRC_THRESHOLD`    | RW  | 24    | DRC threshold. **Reserved: DRC not yet implemented**                                          |
| `0x08`  | `REG_DRC_RATIO`        | RW  | 24    | DRC ratio. **Reserved: DRC not yet implemented**                                              |
| `0x09`  | `REG_MASTER_GAIN`      | RW  | 16    | Master gain (Q2.14). Applied after per-bin gain                                               |
| `0x10`  | `REG_GAIN_ADDR`        | RW  | 7     | Per-bin gain address pointer (0–127)                                                          |
| `0x11`  | `REG_GAIN_DATA`        | WO  | 16    | Per-bin gain value (Q2.14). Write auto-increments address                                     |
| `0x12`  | `REG_GAIN_BANK`        | RW  | 2     | Target bank for gain writes (0=A, 1=B)                                                        |
| `0x13`  | `REG_GAIN_COMMIT`      | WO  | 1     | Atomic bank swap command (any write commits)                                                  |
| `0x20`  | `REG_PEAK_LEVEL`       | RO  | 24    | Peak input level (absolute value, sampled on valid)                                           |
| `0x21`  | `REG_OUT_PEAK`         | RO  | 24    | Peak output level                                                                             |
| `0x22`  | `REG_FRAME_COUNT_L`    | RO  | 24    | Frame counter, lower 24 bits                                                                  |
| `0x23`  | `REG_FRAME_COUNT_H`    | RO  | 8     | Frame counter, upper 8 bits                                                                   |
| `0x24`  | `REG_ERROR_FLAGS`      | W1C | 8     | Error flags: I2S overflow(0), I2S underflow(1), FFT overflow(2), frame drop(3), gain range(4) |
| `0x7E`  | `REG_SCRATCH`          | RW  | 24    | Scratch register for SPI loopback testing                                                     |
| `0x7F`  | `REG_LOOPBACK`         | RW  | 24    | Loopback test register                                                                        |

**Key:** RO = Read-Only, RW = Read-Write, WO = Write-Only, W1C = Write-1-to-Clear

### 8.2 REG_STATUS Bit Fields (8 bits)

| Bit | Name            | Description                                           |
| --- | --------------- | ----------------------------------------------------- |
| 0   | `STATUS_READY`  | MMCM locked AND DSP out of reset                      |
| 1   | `STATUS_LOCKED` | CDC synchronizers stable (all three domains in reset) |
| 2   | `STATUS_CLIP`   | Sticky clip-event indicator (cleared on read)         |
| 3   | `STATUS_DSP_EN` | DSP pipeline running (dsp_enable = 1)                 |
| 5:4 | `STATUS_MODE`   | Current operating mode (0–3)                          |
| 7:6 | Reserved        | —                                                     |

### 8.3 REG_ERROR_FLAGS Bit Fields (8 bits, W1C)

| Bit | Name                | Description                                                    |
| --- | ------------------- | -------------------------------------------------------------- |
| 0   | `ERR_I2S_OVERFLOW`  | i2s_rx dropped a sample (input buffer write during read burst) |
| 1   | `ERR_I2S_UNDERFLOW` | i2s_tx ran out of data (output buffer empty on read strobe)    |
| 2   | `ERR_FFT_OVERFLOW`  | FFT BFP exponent saturated (reserved, tied to 0 for MVP)       |
| 3   | `ERR_FRAME_DROP`    | dsp_pipeline missed a frame (reserved, tied to 0 for MVP)      |
| 4   | `ERR_GAIN_RANGE`    | Host wrote out-of-range gain value (reserved, not yet checked) |
| 7:5 | Reserved            | —                                                              |

### 8.4 Implemented vs Reserved

**Fully implemented:** REG_VERSION, REG_STATUS, REG_CONTROL, REG_MODE, REG_NOISE_FLOOR, REG_NOISE_GATE_RATIO,
REG_MASTER_GAIN, REG_GAIN_ADDR, REG_GAIN_DATA, REG_GAIN_BANK, REG_GAIN_COMMIT, REG_PEAK_LEVEL, REG_OUT_PEAK,
REG_FRAME_COUNT_L, REG_FRAME_COUNT_H, REG_ERROR_FLAGS, REG_SCRATCH, REG_LOOPBACK

**Reserved (infrastructure exists, DSP path incomplete):** REG_VOLUME (register and shadow FF exist; dsp_pipeline has no
volume input), REG_DRC_THRESHOLD, REG_DRC_RATIO (register exists; DRC module not implemented)

[FPGA-only 2026-08-12: The §8 register map above is entirely **historical**. The `reg_file.sv` module is no longer in
the build, so none of the REG_* addresses are externally accessible. Mode, volume, and gain tables are driven by onboard
push buttons through inline FSMs in `top.sv`. The full historical register map is preserved in
`docs/architecture/register_map.md` for reference. See `docs/fpga_only_architecture.md` for the current control
architecture.]

---

## 9. Timing and Performance

### 9.1 Pipeline Stages

The DSP pipeline has a total of approximately 1,870 clock cycles of fixed latency at 96 MHz (~19.5 µs), with variable
input buffer accumulation adding 0–2.65 ms.

### 9.2 Latency Estimates

| Metric                        | Value                              |
| ----------------------------- | ---------------------------------- |
| Fixed pipeline latency        | ~1,870 cycles @ 96 MHz = ~19.5 µs  |
| Input buffer accumulation     | 0–127 samples @ 48 kHz = 0–2.65 ms |
| Total end-to-end (typical)    | ~1.35 ms (~65 samples)             |
| Total end-to-end (worst-case) | ~2.69 ms (~129 samples)            |
| Group delay through FFT/IFFT  | ~8.6 µs (2 × ~414 cycles)          |

### 9.3 Critical Paths

| Path        | Source            | Destination                | Est. Delay | Notes                                                 |
| ----------- | ----------------- | -------------------------- | ---------- | ----------------------------------------------------- |
| OLA Stage 1 | BRAM read         | shifted_l/r register       | ~5.5 ns    | BRAM→25b adder→48b barrel shift; pipelined to Stage 2 |
| Spectral S3 | in_re_s2/in_im_s2 | mag_sq_s3 register         | ~5.0 ns    | Dual 16×16 multiply→32b adder                         |
| Spectral S4 | mag_sq_s3         | out_re_o/out_im_o register | ~5.0 ns    | Comparator→mux→dual 16×16 multiply                    |

All estimated delays are well within the 10.4 ns period at 96 MHz. The design has been synthesized and implemented
successfully on the target device.

### 9.4 Resource-Heavy Modules

| Module                      | Primary Resource           | Estimated Usage                          |
| --------------------------- | -------------------------- | ---------------------------------------- |
| `fft_256_core` (xfft v9.1)  | DSP48E1, BRAM              | ~8 DSP slices, ~6 BRAM tiles             |
| `ifft_256_core` (xfft v9.1) | DSP48E1, BRAM              | ~8 DSP slices, ~6 BRAM tiles             |
| `input_buffer`              | BRAM                       | 1 BRAM tile (256×48, true dual-port)     |
| `output_buffer`             | BRAM                       | 1 BRAM tile (256×48)                     |
| `overlap_add`               | BRAM, LUT (barrel shifter) | 1 BRAM tile (128×48), ~48 LUTs           |
| `spectral_proc`             | BRAM, DSP48E1              | 2 BRAM tiles (gain banks), ~3 DSP slices |
| `window_apply`              | DSP48E1                    | 1 DSP slice (16×16 multiply)             |

**Target device capacity:** XC7S25 has 80 DSP48E1 slices, 45 BRAM tiles (18 Kb each), 23,360 logic cells. The design
comfortably fits within these resources.

### 9.5 Expected Operating Frequency

**Target:** 96 MHz DSP domain. Achieved in synthesis and implementation with positive slack.

**I2S domain:** 3.072 MHz (fixed by audio standard). Far below the Spartan-7 maximum I/O rate.

**SPI domain:** ≤10 MHz (limited by ESP32 SPI peripheral). Well below Spartan-7 capabilities.

---

## 10. FPGA Implementation Notes

### 10.1 Xilinx-Specific Features

- **MMCME2_BASE:** Instantiated directly in `clk_gen.sv` rather than via Clocking Wizard IP. Configuration uses VCO at
  600 MHz (Spartan-7 MMCM minimum) with fractional output division to 96 MHz.
- **SRL16E/SRL32E:** Shift-register LUT primitives inferred for BFP exponent pipeline (418 stages) and reset stretchers
  (16 stages).
- **ASYNC_REG attribute:** Applied to all CDC synchronizer flip-flops to ensure tight placement and minimize
  metastability MTBF.
- **ram_style attribute:** `"block"` for all large storage arrays to force BRAM inference; `"distributed"` for small CDC
  FIFOs to use LUTRAM.
- **BUFG:** Explicitly instantiated for MMCM feedback and DSP clock distribution.

### 10.2 Constraints

The `arty_s7_25.xdc` constraints file defines:

1. **Pin assignments:** All I/O pins mapped to Pmod JA connector (I2S only — JA4-JA7), onboard LEDs, RGB LED, and 4 push
   buttons
2. **Clock definitions:** `clk_12mhz` (83.333 ns), `i2s_bclk` (325.521 ns, FPGA-generated)
3. **Clock groups:** The two domains (DSP family and BCLK) declared mutually asynchronous
4. **I/O timing:** Input/output delays for I2S (±10 ns)
5. **False paths:** Async output paths to LEDs, LRCLK, and button inputs (buttons are debounced before use)
6. **Bitstream config:** SPIx4 configuration, 33 MHz CCLK, compressed bitstream

[FPGA-only 2026-08-12: Items 5 and 6 in the pre-migration list are **no longer applicable**:

- `i2s_bclk_i` is now `i2s_bclk_o` — an FPGA output, not an input.
- `spi_sclk_i` is gone — no SPI clock domain.
- The non-dedicated clock routing trick for external clocks is no longer needed; BCLK is generated on-board.
- The SPI MISO ±5 ns constraint is gone — no MISO output.]

### 10.3 FFT IP

Both FFT and IFFT use xfft v9.1 with identical configuration (see §4.3). Generated via `create_ip.tcl`. The two
instances share the same `.xci` configuration; the only difference is the runtime FWD_INV bit.

**Important:** The xfft IP requires a project context for generation. The `create_ip.tcl` script creates a throwaway
project (`auris_ip_gen`) under `fpga/ip/`, configures and generates both IPs, then closes the project.

### 10.4 MMCM

The MMCM multiplies the 12 MHz onboard oscillator to 96 MHz:

```text
f_out = f_in × CLKFBOUT_MULT_F / (DIVCLK_DIVIDE × CLKOUT0_DIVIDE_F)
      = 12 × 50.0 / (1 × 6.25)
      = 600 / 6.25
      = 96 MHz
```

The VCO runs at 600 MHz (Spartan-7 MMCME2_BASE minimum allowed VCO frequency). This constrains the multiplication
factors — `CLKFBOUT_MULT_F=50.0` is the smallest integer multiplier that reaches the 600 MHz minimum (12 × 50 = 600).

### 10.5 Clock Routing Decisions

- **DSP clock (96 MHz):** MMCM output → BUFG → global clock network. This is the primary high-fanout clock.
- **I2S BCLK (3.072 MHz):** [FPGA-only 2026-08-12] **FPGA-generated** by the fractional divide-by-31.25 counter in
  `clk_gen.sv`, distributed via a BUFG (`bufg_bclk`) to the Pmod JA BCLK output pin and to the `i2s_rx`/`i2s_tx`
  modules. The XDC declares it as a `create_generated_clock` whose source is the MMCM's CLKOUT0. Marked as mutually
  asynchronous with the `clk_12mhz` family via `set_clock_groups -asynchronous`. The pre-migration ESP32-supplied BCLK
  input no longer applies.
- **SPI SCLK:** [FPGA-only 2026-08-12] **Removed** — no SPI clock domain in the FPGA-only build.

### 10.6 BRAM Inference Strategy

To reliably infer BRAM on Spartan-7, the design follows these rules:

1. Storage arrays are in `always_ff @(posedge clk)` blocks (NO async reset in sensitivity list)
2. Read data is registered (1-cycle latency)
3. `ram_style = "block"` attribute is explicitly applied
4. Control logic (pointers, state, output FFs) may use async reset — only the storage array must avoid it

This approach is documented in each affected module's header comment and was applied as a targeted fix after Synth
8-4767 warnings revealed FF dissolution of BRAM arrays.

---

## 11. Current Limitations

### 11.1 Features Intentionally Incomplete

1. **Per-mode gain tables:** `mode_ctrl` loads unity gain for all modes. Phase 4 will add mode-specific shaping
   (audiogram compensation for Hearing mode, high-frequency emphasis for Speech mode) sourced from
   `tools/profile_gen/gen_default_tables.py`.

2. **Digital volume control:** `REG_VOLUME` (0x04) is stored and shadowed but not connected to the DSP pipeline.
   `dsp_pipeline` has no volume input port. Implementation requires adding a multiply stage (Q2.14 × 5-bit volume)
   before the output buffer.

3. **DRC (Dynamic Range Compression):** `REG_DRC_THRESHOLD` (0x07) and `REG_DRC_RATIO` (0x08) are reserved. The
   `AURIS_ENABLE_DRC` parameter exists (set to 1 in the package) but no DRC module is instantiated.

4. **Telemetry:** `AURIS_ENABLE_TELEMETRY` is set to 0. Peak meters and frame counter are functional; streaming
   telemetry to the host is not implemented.

### 11.2 Design Tradeoffs

1. **Real-input FFT:** Only the left channel is processed. The right channel data is present in the pipeline but the
   window_apply module hardwires `out_im_o` to zero, making this a real-input FFT. Stereo processing would require a
   second FFT/IFFT pair (doubling DSP slice usage).

2. **Gain table symmetry:** The Hermitian wrapping constraint (`gain[k] = gain[128-k]`) means the gain table has only 65
   independent entries (gain[0] through gain[64]) rather than 128. This is a fundamental limitation of the real-input
   FFT + wrapping approach. Future enhancement: add a hardware mirroring stage for bins 129–255.

3. **DC/Nyquist coupling:** Bin 128 (Nyquist) receives gain[0] due to the counter wrap, coupling DC and Nyquist gains.
   For most audio processing this is acceptable since neither DC nor Nyquist carries perceptually significant energy.

4. **Truncation, not rounding:** All Q2.14 multiplies use truncation (bits [29:14]) rather than convergent rounding.
   This introduces a -0.5 LSB bias per multiply. Acceptable for MVP; audible only at very low signal levels.

### 11.3 Technical Debt

1. **BFP_PIPE_DELAY hardcoded:** The value 418 is derived from known IP latency but must be re-verified if the xfft IP
   is regenerated with different parameters. There is no automated latency extraction from the IP.

2. **mode_we_o dead port:** `reg_file` has a `mode_we_o` output (pulses on REG_MODE write) but it is not connected at
   the top level. `top.sv` implements its own edge-detect for mode changes. The port is benign dead code.

3. **dsp_volume_o unconnected:** The volume shadow register is updated on SPI writes but the output port is not
   connected at the top level and `dsp_pipeline` has no volume input. Documented as "reserved for future digital
   volume."

4. **Multiple IP generation artifacts:** The `fpga/ip/` directory contains ~47 generated FFT/IFFT core versions (version
   suffixes `_1` through `_23`). Only the base `.xci` files are canonical; the rest are accumulated regeneration
   artifacts.

### 11.4 Known Simulation Limitations

1. **xfft v9.1 C-model:** The IP behavioral simulation models require pre-compiled shared libraries. Simulation of
   `dsp_pipeline` in its entirety depends on these models being available.
2. **CDC simulation:** Async FIFO behavior with actual clock phase relationships is not fully exercised in the current
   testbench suite. The testbenches typically drive both sides from the same clock for simplicity.
3. **BRAM initialization in sim:** Initial blocks set BRAM contents to zero for simulation determinism. This matches
   Spartan-7 post-configuration behavior but is technically a simulation-only construct.

### 11.5 Future Enhancements (Phase 4+)

| Feature              | Description                                                 | Effort |
| -------------------- | ----------------------------------------------------------- | ------ |
| Per-mode gain tables | Audiogram-based shaping, speech emphasis curves             | Medium |
| Digital volume       | Multiply stage before output buffer                         | Low    |
| DRC module           | Dynamic range compression                                   | High   |
| Stereo processing    | Dual FFT/IFFT path                                          | High   |
| Gain table mirroring | Hardware enforcement of Hermitian symmetry                  | Low    |
| Streaming telemetry  | UART or SPI streaming of peak/frame data                    | Medium |
| Formal verification  | Assertion-based verification of CDC and pipeline handshakes | High   |

---

## 12. Verification Status

### 12.1 Existing Testbenches

| Testbench             | Target Module               | Status                                       |
| --------------------- | --------------------------- | -------------------------------------------- |
| `tb_cdc_fifo.sv`      | Async FIFO (cdc_i2s_to_dsp) | Exists; coverage unknown                     |
| `tb_dsp_pipeline.sv`  | Full DSP pipeline           | Exists; depends on xfft sim models           |
| `tb_i2s_rx.sv`        | I2S slave receiver          | Exists; sim project available                |
| `tb_i2s_tx.sv`        | I2S slave transmitter       | Exists                                       |
| `tb_mode_ctrl.sv`     | Mode controller FSM         | Exists                                       |
| `tb_overlap_add.sv`   | Overlap-add reconstructor   | Exists                                       |
| `tb_reg_file.sv`      | Register file               | Exists                                       |
| `tb_spectral_proc.sv` | Spectral processor          | Exists                                       |
| `tb_spi_slave.sv`     | SPI slave                   | Exists; sim project with waveforms available |
| `tb_window_apply.sv`  | Window function + ROM       | Exists                                       |

### 12.2 Current Verification Coverage

**FACT:** Testbenches exist for all major modules. At least `spi_slave`, `i2s_rx`, and `dsp_pipeline` have standalone
Vivado simulation projects with waveform outputs (`.wdb`/`.vcd` files present in `vivado_proj/sim_*/`).

**INFERENCE:** The testbenches likely focus on functional correctness (does the module produce the right output for
given inputs). Coverage of corner cases (reset behavior, overflow/underflow, timing edge cases, CDC metastability) is
unknown.

**ASSUMPTION:** CDC crossing correctness has not been formally verified. The design relies on well-known CDC patterns
(Gray FIFOs, 4-phase handshake) but has not been subjected to CDC-specific verification (e.g., Vivado CDC report, formal
CDC analysis).

### 12.3 Remaining Work

1. **Full pipeline simulation:** End-to-end test with a known input signal (sine sweep, impulse) and comparison of
   output against a Python reference model.
2. **CDC verification:** Run Vivado `report_cdc` and review all unsynchronized paths. Add bus-skew protocols where
   needed.
3. **Timing corner cases:** Verify timing at all process/voltage/temperature corners, not just typical.
4. **Formal verification:** Assertion-based verification of FIFO full/empty conditions, handshake protocol compliance,
   and gain table bank-switch atomicity.
5. **Python co-simulation:** The `tools/` directory contains Python reference implementations (FFT validation, COLA
   checker, gain table validator). These should be integrated into a regression flow.

### 12.4 Suggested Future Verification

| Task                               | Priority | Approach                                                                  |
| ---------------------------------- | -------- | ------------------------------------------------------------------------- |
| End-to-end impulse response        | High     | Python-generated test vector → simulation → compare with Python reference |
| CDC path verification              | High     | Vivado `report_cdc` + manual review                                       |
| Gain table symmetry enforcement    | Medium   | Assertion in spectral_proc or Python pre-check                            |
| Overlap-add COLA verification      | Medium   | Python `check_cola.py` already exists                                     |
| Reset sequence verification        | Low      | Multi-domain reset release simulation                                     |
| Bit-level accuracy vs Python model | Low      | Co-simulation framework                                                   |

---

## 13. File Organization

### 13.1 Directory Structure

```text
Project_Auris/
├── README.md                    # Project overview
├── ENGINEERING_DESIGN.md        # This document
├── Makefile                     # Top-level build orchestration
│
├── docs/                        # Design documentation
│   ├── architecture/            #   Architecture descriptions
│   ├── hardware/                #   Schematics, BOM, wiring
│   └── phase_reports/           #   Phase completion reports
│
├── fpga/                        # All FPGA-related files
│   ├── rtl/                     #   RTL source (SystemVerilog)
│   │   ├── top.sv               #     Top-level module
│   │   ├── clk_gen.sv           #     MMCM wrapper
│   │   ├── pkg/auris_pkg.sv     #     Shared package
│   │   ├── cdc/                 #     Clock domain crossing modules
│   │   ├── ctrl/                #     Control modules (reg_file, mode_ctrl, status_mon)
│   │   ├── io/                  #     I/O modules (i2s_rx, i2s_tx, spi_slave)
│   │   └── dsp/                 #     DSP pipeline modules
│   │       └── spectral/        #       Spectral processor
│   ├── constraints/arty_s7_25.xdc  #  Pin assignments + timing constraints
│   ├── scripts/                 #   Vivado Tcl scripts
│   │   ├── build_project.tcl    #     Full project build
│   │   ├── create_ip.tcl        #     IP core generation
│   │   └── sim_*.tcl            #     Simulation scripts
│   ├── sim/testbenches/         #   Testbench files
│   └── ip/                      #   Generated IP cores
│       ├── fft_256_core/        #     xfft v9.1 (forward)
│       └── ifft_256_core/       #     xfft v9.1 (inverse)
│
├── firmware/                    # [FPGA-only 2026-08-12] HISTORICAL — retained on disk; identical to archive/firmware/. Not part of the build.
│   ├── main/                    #   Application entry point (historical)
│   └── components/              #   Per-peripheral components (historical)
│       ├── spi_master/          #     SPI master driver (historical)
│       ├── fpga_config/         #     Register map mirror (historical)
│       ├── audio_driver/        #     I2S configuration (historical)
│       └── ...                  #     (battery, buttons, LED, etc.) (historical)
│
├── archive/                     # [FPGA-only 2026-08-12] Canonical archive of pre-migration source
│   ├── firmware/                #   ESP-IDF firmware tree (canonical archive copy)
│   ├── rtl/                     #   spi_slave, reg_file, cdc_spi_to_dsp, cdc_dsp_to_spi
│   └── tb/                      #   tb_spi_slave, tb_reg_file
│
├── tools/                       # Python tooling
│   ├── win_gen/                 #   Window coefficient generation
│   ├── fft_gen/                 #   FFT reference / validation
│   ├── profile_gen/             #   Gain profile generation
│   ├── validation/              #   COLA, Parseval, gain table checks
│   └── latency_analysis/        #   Latency measurement tools
│
├── hardware/                    # Hardware design files
│   ├── schematics/              #   Circuit diagrams
│   ├── bom/                     #   Bill of materials
│   └── mechanical/              #   Enclosure models
│
└── vivado_proj/                 # Vivado project directory
    ├── auris.xpr                #   Project file
    └── auris.runs/              #   Synthesis + implementation runs
```

### 13.2 Build Flow

```text
1. Generate IP cores:    vivado -mode batch -source fpga/scripts/create_ip.tcl
2. Build project:        vivado -mode batch -source fpga/scripts/build_project.tcl
   (Steps 1 + 2 can be combined; build_project.tcl sources create_ip.tcl internally)
3. Program device:       vivado -mode batch -source fpga/scripts/program.tcl
```

### 13.3 Simulation Flow

Individual simulation scripts exist in `fpga/scripts/`:

```text
vivado -mode batch -source fpga/scripts/sim_spi_slave.tcl
vivado -mode batch -source fpga/scripts/sim_i2s_rx.tcl
vivado -mode batch -source fpga/scripts/sim_dsp_pipeline.tcl
vivado -mode batch -source fpga/scripts/sim_all.tcl
```

### 13.4 IP Generation Flow

The `create_ip.tcl` script:

1. Creates a throwaway Vivado project (`auris_ip_gen`)
2. Configures and generates `fft_256_core` (xfft v9.1, forward)
3. Configures and generates `ifft_256_core` (xfft v9.1, inverse)
4. Closes the throwaway project
5. Generated `.xci` files are placed in `fpga/ip/fft_256_core/` and `fpga/ip/ifft_256_core/`

Both IP instances share identical configuration; they differ only in the runtime FWD_INV bit (1 for FFT, 0 for IFFT).

---

## 14. Design Decisions

### 14.1 Why 256-Point FFT?

A 256-point FFT at 48 kHz gives a bin spacing of 48,000/256 = 187.5 Hz. This provides adequate frequency resolution for
audio processing (human hearing has ~24 critical bands, each ~1/3 octave wide). A 256-point transform also fits
comfortably in Spartan-7 BRAM and DSP resources.

### 14.2 Why 50% Overlap?

50% overlap (128-sample hop) with a Hann window satisfies the COLA (Constant OverLap-Add) condition, meaning the sum of
overlapped window functions is constant for all output samples. This eliminates amplitude modulation artifacts (audible
"fluttering") at frame boundaries. The tradeoff is 2× computational load compared to 0% overlap.

### 14.3 Why Block Floating Point (BFP)?

BFP scales the entire FFT frame by a single exponent rather than scaling each stage individually (as in fixed-point with
rounding). This:

- Preserves more dynamic range than static scaling
- Avoids the SNR degradation of convergent rounding at each stage
- Adds only 8 bits of sideband data (the block exponent)

The BFP exponent is then used for output scaling in overlap-add, recovering the full dynamic range.

### 14.4 Why MMCME2_BASE Instead of Clocking Wizard?

The MMCME2_BASE primitive is instantiated directly in RTL rather than via a generated Clocking Wizard IP. This avoids a
dependency on a `.xci` file that could become incompatible across Vivado versions. The configuration (multiply/divide
ratios, bandwidth) is explicit in the SystemVerilog parameter list, making it version-control-friendly and reviewable.

### 14.5 Why Distributed RAM for CDC FIFOs but BRAM for Audio Buffers?

**CDC FIFOs (4 entries × 24 bits = 96 bits):** Distributed RAM (LUTRAM) costs ~2 LUTs. A BRAM tile is 18 Kb — using it
for 96 bits would waste >99% of the tile and consume a scarce resource. LUTRAM is the correct choice for tiny FIFOs.

**Audio buffers (256 entries × 48 bits = 12,288 bits):** BRAM is the only practical choice. Implementing a 256×48 array
in flip-flops would consume ~12,000 FFs — nearly half the device. BRAM uses 1 tile and leaves FFs free for logic.

### 14.6 Why 4-Phase Handshake for SPI→DSP CDC?

The SPI→DSP payload is 31 bits wide (7 addr + 24 data + we + re). A bus this wide cannot safely use parallel 2-FF
synchronizers because:

1. Each bit's synchronizer has independent metastability resolution time
2. Bits that resolve in different clock cycles would be sampled as a mixed old/new value

A 4-phase handshake avoids this by:

1. Making the payload stable before asserting `req`
2. Waiting for `req` to be synchronized before the destination samples the payload
3. Holding the payload stable until the destination acknowledges

A Gray-coded FIFO could also work but would require ~31 bits of Gray code (wasteful) and LUTRAM depth equal to the bus
width (also wasteful for a ~2 Kbps control path).

### 14.7 Why Async BRAM Reset Avoidance?

Spartan-7 BRAM storage cells do not have an asynchronous reset input. If a BRAM array is placed inside an
`always_ff @(posedge clk or negedge rst_n)` block, Vivado's synthesizer cannot map it to a BRAM primitive (because the
primitive has no reset pin on the storage). It falls back to implementing the array in flip-flops — 128×24 = 3,072 FFs
for the register file alone. Moving BRAM arrays to non-reset `always_ff` blocks forces BRAM inference.

Since Spartan-7 BRAM initializes to 0 after configuration, the functional behavior at startup is identical to a reset
(all-zero storage).

### 14.8 Why Unity Gain for MVP?

All modes load unity gain tables. This keeps the audio path transparent — the output is essentially a delayed copy of
the input (plus the FFT→IFFT round-trip quantization). This allows independent validation of:

1. The I2S chain (correct data capture and transmission)
2. The CDC infrastructure (no sample corruption)
3. The FFT/IFFT round-trip (no spectral distortion)
4. The overlap-add (no amplitude modulation)

Once the transparent path is validated, mode-specific gain shaping can be layered on top with confidence.

### 14.9 Why Single-Channel (Left-Only) Processing?

The INMP441 is a mono MEMS microphone. Though it outputs stereo I2S (left and right channels carry identical data), the
FPGA processes only the left channel. The right channel is available in the data path but is not processed. Dual-channel
processing (for a future stereo microphone) would require a second complete FFT/IFFT pipeline — doubling DSP48E1 and
BRAM usage, which exceeds this phase's resource budget and educational scope.

### 14.10 Why SRL for Reset Stretching and BFP Delay?

Shift-register LUTs (SRL16E/SRL32E) implement long delay lines using a single LUT per bit, rather than one FF per bit.
For the BFP exponent pipeline (418 stages × 8 bits), SRL saves ~3,300 FFs. For the reset stretchers (16 stages × 3
domains × 1 bit), SRL saves 45 FFs. These are small savings but represent good Spartan-7 optimization practice.

---

## 15. Appendix

### 15.1 Glossary

| Term      | Definition                                                                                        |
| --------- | ------------------------------------------------------------------------------------------------- |
| **BFP**   | Block Floating Point — a scaling method where an entire block of samples shares a single exponent |
| **COLA**  | Constant OverLap-Add — the condition ensuring overlapped window functions sum to a constant       |
| **CDC**   | Clock Domain Crossing — transferring signals between asynchronous clock domains                   |
| **DRC**   | Dynamic Range Compression — non-linear amplitude processing                                       |
| **FF**    | Flip-Flop — a single-bit register                                                                 |
| **FFT**   | Fast Fourier Transform — converts time-domain to frequency-domain                                 |
| **I2S**   | Inter-IC Sound — a serial bus protocol for digital audio                                          |
| **IFFT**  | Inverse Fast Fourier Transform — converts frequency-domain to time-domain                         |
| **LUT**   | Look-Up Table — the basic logic element in an FPGA                                                |
| **MMCM**  | Mixed-Mode Clock Manager — Xilinx clock generation primitive                                      |
| **MTBF**  | Mean Time Between Failures — reliability metric for synchronizer metastability                    |
| **OLA**   | OverLap-Add — a method for reconstructing continuous signals from overlapped FFT frames           |
| **Q2.14** | Fixed-point format: 2 integer bits + 14 fractional bits, signed                                   |
| **SRL**   | Shift Register LUT — a LUT configured as a shift register (SRL16E = 16-bit, SRL32E = 32-bit)      |
| **STFT**  | Short-Time Fourier Transform — FFT applied to windowed segments of a continuous signal            |

### 15.2 Acronyms

| Acronym | Expansion                                       |
| ------- | ----------------------------------------------- |
| AXI     | Advanced eXtensible Interface                   |
| BCLK    | Bit Clock (I2S)                                 |
| BOM     | Bill of Materials                               |
| BRAM    | Block RAM                                       |
| BUFG    | Global Clock Buffer                             |
| CS      | Chip Select (SPI)                               |
| DAC     | Digital-to-Analog Converter                     |
| DSP     | Digital Signal Processing / DSP48E1 slice       |
| FSM     | Finite State Machine                            |
| I2S     | Inter-IC Sound                                  |
| IP      | Intellectual Property (Xilinx IP core)          |
| LRCLK   | Left/Right Clock (I2S word clock)               |
| LUTRAM  | Look-Up Table configured as RAM                 |
| MEMS    | Micro-Electro-Mechanical System                 |
| MISO    | Master In Slave Out (SPI)                       |
| MMCM    | Mixed-Mode Clock Manager                        |
| MOSI    | Master Out Slave In (SPI)                       |
| MVP     | Minimum Viable Product                          |
| PCM     | Pulse-Code Modulation                           |
| RTL     | Register Transfer Level                         |
| SCLK    | Serial Clock (SPI)                              |
| SPI     | Serial Peripheral Interface                     |
| VCO     | Voltage-Controlled Oscillator (within MMCM/PLL) |

### 15.3 Important Constants

| Constant               | Value     | Definition                                     |
| ---------------------- | --------- | ---------------------------------------------- |
| `FFT_LEN`              | 256       | FFT/IFFT transform length                      |
| `HALF`                 | 128       | Half FFT length (hop size, history depth)      |
| `GAIN_TABLE_DEPTH`     | 128       | Per-bin gain table entries (FFT_LEN / 2)       |
| `FFT_DATA_W`           | 16        | FFT/IFFT data width (Q2.14)                    |
| `I2S_DATA_W`           | 24        | I2S sample width                               |
| `WINDOW_DATA_W`        | 16        | Window coefficient width (Q2.14)               |
| `CDC_FIFO_DEPTH`       | 4         | Async FIFO depth                               |
| `BFP_PIPE_DELAY`       | 418       | BFP exponent alignment delay (4 + ~414 cycles) |
| `K_BFP`                | 6         | Static OLA shift correction                    |
| `UNITY_GAIN_Q14`       | 16384     | Unity gain in Q2.14 (1.0 × 2^14)               |
| `RESET_STRETCH_CYCLES` | 16        | Reset stretcher depth                          |
| `DSP_CLK_FREQ`         | 96 MHz    | DSP domain clock frequency                     |
| `I2S_BCLK_FREQ`        | 3.072 MHz | I2S bit clock (64 × 48 kHz)                    |
| `I2S_FS`               | 48 kHz    | Audio sample rate                              |

### 15.4 Parameter Relationships

```text
FFT_LEN = 256
├── HALF = FFT_LEN / 2 = 128
│   ├── GAIN_TABLE_DEPTH = 128 (= HALF, unique bins for real FFT)
│   ├── overlap_add history depth = 128 (= HALF)
│   ├── output_buffer ping-pong half = 128 (= HALF)
│   └── input_buffer hop size = 128 (= HALF)
│
├── FFT_ADDR_W = $clog2(256) = 8
│
├── BFP_PIPE_DELAY = 418
│   ├── spectral_proc pipeline = 4 cycles
│   └── IFFT latency (N=256, pipelined streaming) ≈ 414 cycles
│
└── All CDC modules: DEPTH = CDC_FIFO_DEPTH = 4
```

### 15.5 Clock Frequencies

| Clock        | Frequency | Period     | Source                                                                                     | Domain           |
| ------------ | --------- | ---------- | ------------------------------------------------------------------------------------------ | ---------------- |
| `clk_12mhz`  | 12 MHz    | 83.333 ns  | Onboard oscillator                                                                         | — (feeds MMCM)   |
| `clk_96mhz`  | 96 MHz    | 10.417 ns  | MMCM CLKOUT0                                                                               | CD_DSP           |
| `i2s_bclk_o` | 3.072 MHz | 325.521 ns | [FPGA-only 2026-08-12] FPGA-generated via `clk_gen.sv` fractional divider (96 MHz ÷ 31.25) | CD_I2S           |
| `spi_sclk_i` | ≤10 MHz   | ≥100 ns    | [FPGA-only 2026-08-12] Removed — no SPI clock domain                                       | — (not in build) |
| MMCM VCO     | 600 MHz   | 1.667 ns   | MMCM internal                                                                              | —                |

---

End of Engineering Design Document.
