# SPI Register Map

> **HISTORICAL REFERENCE — not part of the current architecture.**
>
> **Project Auris** — Original FPGA register file that was accessed by the ESP32 over SPI (multi-MCU build). **Last
> updated:** 2026-08-12 (FPGA-only migration: banner refreshed; body retained verbatim for the historical record).
> **Status:** Archived for historical reference only. The SPI slave, the `reg_file.sv` module, the `cdc_spi_to_dsp.sv` /
> `cdc_dsp_to_spi.sv` CDC modules, and the firmware `/firmware/` tree have all been removed from the FPGA-only build.
> The register map below is **no longer externally accessible** — there is no host processor that can read or write
> these registers at runtime.
>
> In the FPGA-only architecture, every field previously written over SPI is now controlled internally:
>
> - Mode is driven by the 2-bit `current_mode` register in `top.sv`, which is updated by `BTN0` / `BTN1`. The current
>   mode numbering is **0 = General, 1 = Speech, 2 = Music, 3 = Hearing** (the historical numbering was 0 = General, 1 =
>   Hearing, 2 = Speech, 3 = Bypass — the new numbering adds Music and drops Bypass).
> - Volume is driven by the 5-bit `volume_level` register in `top.sv`, which is updated by `BTN2` / `BTN3`. The mapping
>   is linear in Q2.14: `vol_q14 = level * (16384/31) ≈ level * 529`.
> - The per-bin gain table is driven by the pre-computed per-mode tables inside `mode_ctrl.sv`. There is no runtime way
>   for a user to change individual bins.
> - Telemetry (peak levels, frame counter, error flags) is computed inside `dsp_pipeline.sv` but not exposed on any
>   external interface; observability is via the STATUS0 (heartbeat) and STATUS2 (sticky clip) LEDs.
>
> The `firmware/` tree (ESP-IDF, ESP32 firmware) is **retained on disk** per the 2026-08-12 migration brief; it is
> identical in content to `archive/firmware/`. It is **not** part of the current build and is not compiled or flashed.
>
> For the current architecture, see [`docs/fpga_only_architecture.md`](../fpga_only_architecture.md). For the current
> mode/volume/gain-table architecture, see [`modes_and_gains.md`](modes_and_gains.md).

The original architecture (now superseded) used a 128-entry × 24-bit register file accessible to the ESP32 over a SPI
link. Writes set the operating mode, master volume, per-bin gain table, and DSP control fields. Reads return telemetry
(peak levels, frame counter, error flags). The register file was the _only_ mechanism by which the ESP32 could change
the FPGA's behaviour at runtime.

---

## 1. SPI Protocol

### 1.1 Physical layer

| Parameter      | Value                                        |
| -------------- | -------------------------------------------- |
| Mode           | SPI Mode 0 (CPOL=0, CPHA=0)                  |
| Clock polarity | SCLK idle low                                |
| Clock phase    | Sample on rising edge, propagate on falling  |
| Bit order      | MSB first                                    |
| Max clock      | 10 MHz (conservative; ESP32 capable of more) |
| Slave select   | Active low, with Pmod JA pull-up             |
| Word size      | 32 bits per transaction                      |

### 1.2 Frame format

Each transaction is exactly **32 bits (4 bytes)**, sent MSB first. The frame is laid out as follows:

| Bit [31]    | Bits [30:24] | Bit [23] | Bits [22:0]  |
| ----------- | ------------ | -------- | ------------ |
| `0` (start) | `ADDR[6:0]`  | `R/W`    | `DATA[22:0]` |

Where:

- **Bit 31** is a start marker. The host drives it to `0`; the FPGA drops the transaction silently if it is `1`. The
  CS_N line actually delimits frame boundaries, so the start bit is mostly observational.

- **`ADDR`** is a 7-bit address (`0x00..0x7F`) that directly indexes the 128-entry register file.

- **`R/W`** is the read/write bit: `0` = write, `1` = read. On a read the host still drives a full 32-bit frame; the
  FPGA latches the request and shifts out the read data in the _next_ transaction.

- **`DATA`** is a 23-bit payload. On read transactions, the FPGA shifts out the data for `ADDR` in the _next_ CS-low
  window. On write transactions, the FPGA latches `DATA` into `ADDR` on the final SCLK rising edge. The internal
  register file is 24 bits wide; the on-wire data field is the lower 23 bits and the FPGA zero-pads the MSB on write.

### 1.3 Read latency

A read transaction takes **two** 32-bit frames on the wire:

1. **Frame 1 (command):** host sends `0 | ADDR | R/W=1 | 0x7FFFFF`. The FPGA latches the request.
2. **Frame 2 (data):** host sends a _dummy_ 32-bit frame (`0xFFFFFFFF` is a common choice). On the second frame's MOSI,
   the FPGA drives the read data on MISO. The response layout is the same as the request: bit 31 = 0 (start marker),
   bits 30:24 = echo of the requested address, bit 23 = 0, bits 22:0 = the register data (23 bits, masked by the host to
   recover it).

The two-frame latency is 4 µs at 10 MHz. The firmware's `auris_spi_read` helper handles this transparently and returns
the 23-bit value to the caller.

### 1.4 Latency budget (M36)

The read latency from a host SPI read request to a returned value is the sum of the following pipeline stages. All times
assume SCLK = 10 MHz, DSP clock = 96 MHz.

| Stage                                | Time         | Notes                                          |
| ------------------------------------ | ------------ | ---------------------------------------------- |
| SCLK: shift in 32-bit request        | 3.2 µs       | 32 bits @ 10 MHz                               |
| `cdc_spi_to_dsp` req/ack handshake   | < 1 µs       | 2-FF synchroniser on each side                 |
| `reg_file` 1-cycle read mux          | 10.4 ns      | 1 DSP cycle                                    |
| `cdc_dsp_to_spi` 2-FF read-data sync | 20.8 ns      | 2 DSP cycles                                   |
| SCLK: shift out 32-bit response      | 3.2 µs       | 32 bits @ 10 MHz (next transaction)            |
| **Total (host-to-host)**             | **≈ 6.5 µs** | 2 transactions at 3.2 µs each + ~100 ns of CDC |

In the worst case the host sees a 6.5 µs gap between the issued read and the received data. The firmware hides this by
issuing back-to-back transactions.

---

### 1.5 Timing

```text
              +-----+-----+-----+-----+-----+-----+-----+-----+
   SCLK  _____|     |_____|     |_____|     |_____|     |_____|
         ^    ^     ^     ^     ^     ^     ^     ^     ^     ^
         |    |     |     |     |     |     |     |     |     |
   MOSI  CMD--ADDR-DATA--- ...  CMD--ADDR-DATA--- ...  CMD--ADDR
         ^                                ^                   ^
         |                                |                   |
   CS_N  _|                                |___________________|
         start of txn 1                start of txn 2
```

Each bit is sampled on the rising edge of SCLK. CS_N must be held low for the entire 32-bit frame and de-asserted
between frames.

---

## 2. Register Map

The register file is 128 × 24 bits, addressed by a 7-bit `ADDR`. The table below lists every defined address. Unlisted
addresses (`0x0A..0x0F`, `0x14..0x1F`, `0x25..0x7D`, `0x80..0xFF` are out of range) read as `0x000000` and ignore
writes.

| Address (hex)                        | Name                            | Access   | Reset      | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ------------------------------------ | ------------------------------- | -------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `0x00`                               | `REG_VERSION`                   | R        | `0x000100` | RTL version. Major in bits [23:16], minor in bits [15:8], patch in bits [7:0]. `0x000100` = v0.1.0 (initial bring-up). The ESP32 reads this on boot to confirm a valid bitstream is loaded.                                                                                                                                                                                                                                                                                                                                                  |
| `0x01`                               | `REG_STATUS`                    | R        | `0x000000` | Status flags. Bit definitions: `bit0 = ready` (MMCM locked, DSP out of reset), `bit1 = locked` (CDC synchronisers stable), `bit2 = clip` (sticky clip-event indicator), `bit3 = dsp_en` (DSP pipeline running), `bits[5:4] = mode` (echo of the current `REG_MODE` value), `bits[23:6] = reserved` (read as 0). The `ready` and `locked` bits are live health signals from the FPGA (not hard-coded).                                                                                                                                        |
| `0x02`                               | `REG_CONTROL`                   | RW       | `0x000000` | Global control bits. `bit0 = dsp_enable` (1 = run the spectral pipeline, 0 = bypass the pipeline and pass the input straight to the output — single-cycle mux in `dsp_pipeline.sv`). `bits[23:1] = reserved` (write 0, ignore on read). Note: there is no `soft_reset` bit in this revision; reset is exclusively via the MMCM `locked` signal through `reset_sync_stretch`.                                                                                                                                                                 |
| `0x03`                               | `REG_MODE`                      | RW       | `0x000000` | Operating mode. Valid values: `0x0` = General, `0x1` = Hearing, `0x2` = Speech, `0x3` = Bypass. Writes outside this set are silently ignored. A mode write triggers `mode_ctrl` to load the corresponding default gain table into the inactive bank and commit. The Bypass mode loads a flat unity-gain table (no shaping); it does **not** by itself short-circuit the DSP pipeline — for a true wire-level bypass, the host must also clear `REG_CONTROL[0]` (`dsp_enable = 0`).                                                           |
| `0x04`                               | `REG_VOLUME`                    | RW       | `0x000000` | Master (pre-spectral) volume, **5-bit unsigned** (steps 0..31). The FPGA mirrors bits [4:0] to its volume output; bits [23:5] are reserved. `0` = mute, `16` = ~50 %, `31` = max. The ESP32 setter `auris_fpga_set_volume` writes the raw 5-bit value (no shift); the FPGA's volume block applies a piecewise-linear dB-to-Q2.14 mapping internally.                                                                                                                                                                                         |
| `0x05`                               | `REG_NOISE_FLOOR`               | RW       | `0x000000` | Noise-gate floor, **8-bit Q2.14 amplitude** (left-aligned in 24 bits: `nf << 8`). A bin with magnitude below this value is zeroed by the spectral processor. Default reset value is `0x00`; mode_ctrl overrides to the mode-specific default on a mode change.                                                                                                                                                                                                                                                                               |
| `0x06`                               | `REG_NOISE_GATE_RATIO`          | RW       | `0x000000` | Ratio applied inside the noise gate's soft-knee region, **8-bit Q2.14** (left-aligned: `ratio << 8`). `0xFF00` ≈ 1.0× (passthrough), `0x0000` = full attenuation.                                                                                                                                                                                                                                                                                                                                                                            |
| `0x07`                               | `REG_DRC_THRESHOLD`             | RW       | `0x000000` | Dynamic-range-compressor threshold, **12-bit Q2.14** (left-aligned: `thr << 12`). Bin magnitudes above this value are compressed by `REG_DRC_RATIO`.                                                                                                                                                                                                                                                                                                                                                                                         |
| `0x08`                               | `REG_DRC_RATIO`                 | RW       | `0x000000` | Compression ratio above `REG_DRC_THRESHOLD`, **5-bit** (left-aligned: `ratio << 19`). Values 1..16 map to compression ratios.                                                                                                                                                                                                                                                                                                                                                                                                                |
| `0x09`                               | `REG_MASTER_GAIN`               | RW       | `0x000000` | Master (post-spectral, pre-output) gain, **16-bit Q2.14 signed** (left-aligned in 24 bits: `q14 << 8`). The full 16-bit range (`0x0000..0x7FFF`) covers 0.0× to ≈ 1.99994×.                                                                                                                                                                                                                                                                                                                                                                  |
| `0x0A`                               | (reserved for `REG_HW_VERSION`) | R        | `0x000000` | Reserved for the hardware-revision register. Not exposed in this RTL revision; reads return `0x000000`, writes are ignored. Will become a read-only revision code (`0x00` = revision A prototype) once the bitstream is tagged.                                                                                                                                                                                                                                                                                                              |
| `0x10`                               | `REG_GAIN_ADDR`                 | RW       | `0x000000` | Indirect gain-table **address**. Bits [6:0] select the bin index `0..127`; bits [23:7] are reserved (write 0). The host writes the starting bin index here, then streams `REG_GAIN_DATA` writes — the FPGA **auto-increments** `REG_GAIN_ADDR` on every `REG_GAIN_DATA` write (see `reg_file.sv`).                                                                                                                                                                                                                                           |
| `0x11`                               | `REG_GAIN_DATA`                 | RW       | `0x000000` | Indirect gain-table **data**. Bits [15:0] hold the **16-bit Q2.14 signed** gain value (direct, not left-aligned). Bits [23:16] are reserved (write 0). On every write, the FPGA also bumps `REG_GAIN_ADDR` so the next `REG_GAIN_DATA` write lands in the next bin. The write is staged in a per-bank register; it is **not** applied to the active gain table until `REG_GAIN_COMMIT` is written.                                                                                                                                           |
| `0x12`                               | `REG_GAIN_BANK`                 | RW       | `0x000000` | Bank selector for the indirect gain-table write. **2-bit** field (banks 0 and 1 are defined; values 2 and 3 are reserved and behave as bank 0). `mode_ctrl` automatically commits the freshly-loaded bank after a mode change.                                                                                                                                                                                                                                                                                                               |
| `0x13`                               | `REG_GAIN_COMMIT`               | W        | `0x000000` | Commit the staged gain-table write. Writing any value (conventionally `0x01`) makes the bank selected by `REG_GAIN_BANK` the new active bank. Reads return `0x000000`.                                                                                                                                                                                                                                                                                                                                                                       |
| `0x20`                               | `REG_PEAK_LEVEL`                | R        | `0x000000` | Peak **input** level since last read, 24-bit magnitude. Reading this register clears it (write-1-to-clear semantics on the underlying sticky register), so the next read returns the peak that has accumulated _since_ this read.                                                                                                                                                                                                                                                                                                            |
| `0x21`                               | `REG_OUT_PEAK`                  | R        | `0x000000` | Peak **output** level since last read, 24-bit magnitude. Same clearing semantics as `REG_PEAK_LEVEL`.                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `0x22`                               | `REG_FRAME_COUNT_L`             | R        | `0x000000` | Lower 24 bits of the DSP frame counter. Increments once per completed 256-pt FFT/IFFT cycle. Combined with `REG_FRAME_COUNT_H` to form a 32-bit monotonically-increasing count.                                                                                                                                                                                                                                                                                                                                                              |
| `0x23`                               | `REG_FRAME_COUNT_H`             | R        | `0x000000` | **Upper 8 bits** of the DSP frame counter (FPGA returns `frame_count[31:24]` in the low 8 bits of the read response; bits 23:8 are zero). Combined with `REG_FRAME_COUNT_L` to form a 32-bit count.                                                                                                                                                                                                                                                                                                                                          |
| `0x24`                               | `REG_ERROR_FLAGS`               | RW (W1C) | `0x000000` | Sticky error flags. Reading returns the latched error bits; writing 1 to a bit position clears that bit (W1C). The firmware's `auris_fpga_read_error_flags` performs a read-then-write-back to clear the latched bits. Bit definitions: `bit0 = i2s_overflow` (i2s_rx dropped a sample), `bit1 = i2s_underflow` (i2s_tx ran out of data), `bit2 = fft_overflow` (FFT BFP exponent saturated), `bit3 = frame_drop` (dsp_pipeline missed a frame), `bit4 = gain_range` (host wrote an out-of-range gain), `bits[23:5] = reserved` (read as 0). |
| `0x7E`                               | `REG_SCRATCH`                   | RW       | `0x000000` | Scratch register. No hardware effect; intended for host-side self-tests and SPI link verification (write a pattern, read it back).                                                                                                                                                                                                                                                                                                                                                                                                           |
| `0x7F`                               | `REG_LOOPBACK`                  | RW       | `0x000000` | SPI loopback. When non-zero, the FPGA echoes any subsequent MOSI byte back on MISO without latching it into the register file. Used to validate the SPI link timing independently of the DSP.                                                                                                                                                                                                                                                                                                                                                |
| `0x0A..0x0F, 0x14..0x1F, 0x25..0x7D` | `RESERVED`                      | R        | `0x000000` | Reserved for future use. Reads return `0x000000`, writes are ignored.                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |

> The table above is the **canonical architectural register map**, generated from the RTL localparam constants in
> [`fpga/rtl/pkg/auris_pkg.sv`](../../fpga/rtl/pkg/auris_pkg.sv) and mirrored in the firmware `#define` constants in the
> archived [`fpga_config.h`](../../archive/firmware/components/fpga_config/fpga_config.h). These three locations MUST
> be kept in lock-step — when one changes, change all three in the same commit.

### 2.1 Reset values

The reset values in the table assume the FPGA's MMCM has just locked. The DSP is held in reset for 16 cycles of the 96
MHz clock (≈ 167 ns) by `reset_sync_stretch`, so all RW registers reach their default values before the ESP32's first
SPI transaction completes.

`REG_VERSION` is read-only and reflects the bitstream identity; the ESP32 reads it on boot to confirm that a valid
bitstream is loaded. `REG_STATUS` is also read-only and reflects the live health of the DSP pipeline.

---

## 3. Gain Table Format

The gain table is the heart of the spectral processor. It is a length-128 array of Q2.14 values, one per FFT bin (the
upper 128 bins of the 256-point FFT are conjugates of the lower 128 and are not stored separately). The full 128-entry
table is **double- buffered** (two banks, A and B) and accessed **indirectly** through four registers (`REG_GAIN_ADDR`,
`REG_GAIN_DATA`, `REG_GAIN_BANK`, `REG_GAIN_COMMIT`) rather than via a flat register window.

### 3.1 Address mapping

Each bin is identified by its index `n = 0..127`. The mapping from bin index to frequency is:

```text
freq_Hz = bin × (48000 / 256) = bin × 187.5
```

There is no fixed register address for bin `n`; the bin is addressed _by value_ over the indirect-access registers
described below. The current RTL uses `GAIN_TABLE_DEPTH = 128`; the constant lives in
[`fpga/rtl/pkg/auris_pkg.sv`](../../fpga/rtl/pkg/auris_pkg.sv) (`GAIN_TABLE_DEPTH`).

### 3.2 Indirect write sequence

To write a single bin, the ESP32 performs four SPI transactions in this exact order:

```c
// 1. Select the target bank (0 = A, 1 = B)
auris_spi_write(REG_GAIN_BANK,  bank);

// 2. Select the target bin (0..127) — the FPGA will auto-increment
//    this on every subsequent REG_GAIN_DATA write.
auris_spi_write(REG_GAIN_ADDR,  bin);

// 3. Write the 16-bit Q2.14 value (direct, NOT left-aligned; the
//    FPGA truncates the upper 8 bits of the 24-bit register).
auris_spi_write(REG_GAIN_DATA,  (uint16_t)q14_value);

// 4. Commit the bank (makes the inactive bank active)
auris_spi_write(REG_GAIN_COMMIT, 0x01);
```

The `mode_ctrl` block in the FPGA detects the commit and synchronises the bank swap to the next FFT frame boundary, so
the active bank toggles with no audible click. Reads of the gain table are not exposed through the register file — the
host writes only; the spectral processor reads the active bank on every frame.

M8/M29: The FPGA auto-increments `REG_GAIN_ADDR` on every `REG_GAIN_DATA` write (see `reg_file.sv`). A full 128-bin
table upload therefore requires only:

1. 1× `REG_GAIN_BANK` read (to find the active bank)
2. 1× `REG_GAIN_BANK` write (select the inactive bank)
3. 1× `REG_GAIN_ADDR` write (set start address to 0)
4. 128× `REG_GAIN_DATA` writes (one per bin; address auto-increments)
5. 1× `REG_GAIN_COMMIT` write
6. 1× `REG_GAIN_BANK` write (restore the original active bank)

= **133 SPI transactions** total ≈ 43 µs of wire time at 10 MHz.

### 3.3 Q2.14 fixed-point

Each gain entry is a **16-bit signed Q2.14** value (M20: the field is _signed_, two's-complement; the docs previously
described it as unsigned). The representable range is `[-2.0, +1.99994]`. The default table in `mode_ctrl.sv` loads
`UNITY_GAIN_Q14 = 0x4000 = +1.0×` into every bin.

| Hex value | Q2.14 value | Gain (linear) | Gain (dB)      |
| --------- | ----------- | ------------- | -------------- |
| `0x0000`  | 0.0         | 0.000×        | −∞             |
| `0x2000`  | +0.5        | 0.500×        | −6.0           |
| `0x4000`  | +1.0        | 1.000×        | 0.0            |
| `0x6000`  | +1.5        | 1.500×        | +3.5           |
| `0x7FFF`  | ≈ +1.99994  | 1.99994×      | +6.0           |
| `0x8000`  | −2.0        | -2.000×       | invalid (mute) |
| `0xC000`  | −1.0        | -1.000×       | invalid (mute) |

The valid range for gain values is `0x0000..0x7FFF` (0.0× to ≈ 2.0×). Negative values are written as a phase-inversion;
the spectral processor does not interpret negative gains as attenuation and would need a `abs()` wrapper before
multiplication.

### 3.4 Frequency resolution

At 48 kHz sample rate and 256-point FFT, each bin covers exactly 187.5 Hz. The 128 stored bins therefore cover 0 Hz to
24 kHz (Nyquist), with bin 0 = DC and bin 127 = 23.8125 kHz. Bin 128 is the Nyquist frequency and is also its own
conjugate.

---

## 4. Access Patterns

### 4.1 Initialisation sequence

The ESP32 brings up the FPGA in the following order. Each SPI write is one 32-bit frame (~4 µs at 10 MHz); the
gain-table load is the only multi-frame operation.

```c
// 1. Confirm a valid bitstream is loaded. Non-zero REG_VERSION is the
//    cheapest "FPGA is alive" check; a stuck-at-zero read means the
//    MMCM has not locked yet, the bitstream is corrupt, or the SPI
//    link itself is broken.
uint32_t ver = auris_spi_read(REG_VERSION);
ESP_LOGI("fpga", "FPGA RTL v%u.%u.%u",
         (ver >> 16) & 0xFF, (ver >> 8) & 0xFF, ver & 0xFF);
assert(ver != 0x000000);

// 2. Clear any latched error flags (read-modify-write W1C).
//    auris_fpga_read_error_flags does this automatically.
uint32_t errs = 0;
auris_fpga_read_error_flags(&errs);
if (errs) {
    ESP_LOGW("fpga", "FPGA reported errors on boot: 0x%05x", errs);
}

// 3. Set the operating mode (default after boot is General).
auris_spi_write(REG_MODE, MODE_HEARING);

// 4. Set the master volume (5-bit value 0..31, raw).
auris_spi_write(REG_VOLUME, 16);  // ~50 %

// 5. Set the master (post-spectral) gain. 16-bit Q2.14, left-aligned
//    in 24 bits via << 8. 0x4000 << 8 = 0x400000 = 1.0x unity.
auris_spi_write(REG_MASTER_GAIN, 0x4000u << 8);

// 6. Optionally load a custom gain table using the indirect access.
//    M8: the FPGA auto-increments REG_GAIN_ADDR on every REG_GAIN_DATA
//    write, so we set the start address once and stream 128 data words.
auris_spi_write(REG_GAIN_BANK, 0);                        // stage into bank A
auris_spi_write(REG_GAIN_ADDR, 0);                        // start at bin 0
for (int bin = 0; bin < 128; bin++) {
    auris_spi_write(REG_GAIN_DATA, (uint16_t)gain_table[bin]);
}
auris_spi_write(REG_GAIN_COMMIT, 0x01);                   // activate bank A
```

### 4.2 Runtime mode change

A mode change is a single SPI write. The `mode_ctrl` module in the FPGA detects the mode write (edge-detected in the DSP
domain) and reloads the default gain table for the new mode into the inactive bank, then commits it. The user can then
fine-tune individual bins on the _new active_ bank without disturbing playback.

```c
// User pressed the "mode" button
auris_mode_t new_mode = auris_mode_cycle();
auris_spi_write(REG_MODE, (uint32_t)new_mode);
// mode_ctrl auto-loads the default table for new_mode
// (no further ESP32 action required)
```

### 4.3 Telemetry read

Telemetry is read at 1 Hz by the `telemetry` task. Each read is a single 32-bit frame; the status and error fields are
read in a fixed order to minimise wire traffic.

```c
uint32_t status      = auris_spi_read(REG_STATUS);
uint32_t peak_in     = auris_spi_read(REG_PEAK_LEVEL);
uint32_t peak_out    = auris_spi_read(REG_OUT_PEAK);
uint32_t frame_count = auris_spi_read(REG_FRAME_COUNT_L)
                     | ((auris_spi_read(REG_FRAME_COUNT_H) & 0xFFu) << 24);
uint32_t errs        = 0;
auris_fpga_read_error_flags(&errs);   // reads and W1C-clears in one call

if (peak_out >= 0x700000) {
    // about -3 dBFS; warn the user
    led_indicator_set_pattern(LED_PATTERN_PEAK_WARNING);
}
if (errs) {
    ESP_LOGW("fpga", "FPGA error flags: 0x%05x", errs);
}
```

### 4.4 Bypass for diagnostics

For end-to-end loopback tests, the ESP32 can put the FPGA in a diagnostic pass-through mode. Note that only the
**control-bit bypass** is a true wire-level short-circuit; the **mode-driven bypass** is just a flat unity-gain profile
and the DSP pipeline still runs.

1. **Mode-driven unity** — write `MODE_BYPASS` (= `0x3`) to `REG_MODE`. The `mode_ctrl` block loads a flat unity-gain
   profile (every bin = 1.0×). The DSP pipeline still runs; this mode is for "I want a flat response, but the FFT/IFFT
   path should still be active" scenarios.
2. **Control-bit wire-level bypass** — clear `bit0` of `REG_CONTROL` (`auris_spi_write(REG_CONTROL, 0x00)`). The
   `dsp_pipeline.sv` output mux routes the I2S RX inputs directly to the I2S TX outputs, skipping the window / FFT /
   spectral / IFFT / OLA stages entirely. This is the only true wire-level bypass.

The control-bit bypass (option 2) is preferred for diagnostic loopback because it isolates the I2S / CDC / DAC plumbing
from any DSP question. The audio path becomes mic → I2S RX → CDC → I2S TX → DAC. Latency drops to the single-CDC-FIFO
delay (~100 µs) and any audio quality issue can be unambiguously attributed to the analog or I2S plumbing rather than to
the DSP.

---

## 5. Where to Read Next

- The signal-processing side of the gain table (where it is applied, how it interacts with the noise gate, how it is
  double-buffered) is in [`dsp_pipeline.md`](dsp_pipeline.md).
- The four clock domains that the SPI bus crosses, and the CDC strategy, are in [`clock_domains.md`](clock_domains.md).
- The top-level diagram showing the SPI master and slave is in [`block_diagram.md`](block_diagram.md).
- The system-level register-map constants in the RTL are in
  [`fpga/rtl/pkg/auris_pkg.sv`](../../fpga/rtl/pkg/auris_pkg.sv).
- The system-level register-map constants in the firmware are in
  [`archive/firmware/components/fpga_config/fpga_config.h`](../../archive/firmware/components/fpga_config/fpga_config.h).
