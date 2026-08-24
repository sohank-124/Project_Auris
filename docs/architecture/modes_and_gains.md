# Modes and Gain Tables

> **Project Auris** — Listening modes, pre-computed per-mode gain
> tables, LED colour mapping, and button assignment.
> **Last updated:** 2026-08 (FPGA-only migration).
> **Status:** Authoritative. The pre-computed gain tables below are
> the ones shipped inside `fpga/rtl/ctrl/mode_ctrl.sv` and are loaded
> into the spectral processor's dual-port BRAM by `mode_ctrl`. The
> LED colour map is the one decoded by the inline `case` statement in
> `top.sv`. The button assignment is the one routed through
> `btn_debounce.sv` to the FSMs in `top.sv`.

This document is the single-pane-of-glass reference for the FPGA-only
audio processing pipeline's user-facing behaviour. It describes:

1. The four listening modes and their frequency-response goals.
2. The pre-computed 128-bin per-mode gain tables (Q2.14 values).
3. The RGB LED colour that indicates the current mode.
4. The button assignments (BTN0..BTN3).

For the architectural context (where mode_ctrl fits in the pipeline,
how the dual-bank BRAM is committed atomically, etc.) see
[`block_diagram.md`](block_diagram.md). For the register-level details
of the historical SPI register file (now removed from the build), see
[`register_map.md`](register_map.md) — note that the SPI register map
is archived for historical reference only and is not part of the
current FPGA-only build.

---

## 1. Listening Modes

Project Auris ships **four** listening modes, indexed by a 2-bit
`current_mode` register:

| Mode ID | Name      | RGB LED colour | Use case                                                       |
|--------:|-----------|----------------|----------------------------------------------------------------|
| `0`     | General   | Green          | Transparent passthrough. Flat unity gain across all bins.      |
| `1`     | Speech    | Blue           | Vocal presence boost with high-shelf roll-off. Sibilance tame. |
| `2`     | Music     | Magenta        | Flat mids with sub-bass lift and air/sparkle shelf.            |
| `3`     | Hearing   | Red            | Ski-slope high-frequency emphasis for HF hearing loss.         |

The mode is changed with the onboard push buttons:

- **BTN0** — mode increment (cycles `General → Speech → Music →
  Hearing → General …`).
- **BTN1** — mode decrement (cycles in reverse). Unsigned 2-bit
  arithmetic gives natural wrap-around (`3 - 1 = 2`, `0 - 1 = 3`).

On every mode change, the inline FSM in `top.sv` asserts a single-cycle
`mode_we_pulse`, which the `mode_ctrl` module uses to reload the new
mode's gain table into the inactive bank of the spectral processor's
dual-port BRAM and atomically commit the swap (no audible click).

The 2-bit `current_mode` register also drives the RGB LED directly
through a combinational `case` in `top.sv` (see Section 3).

### 1.1 Frequency-resolution context

The pipeline runs a 256-point FFT at 48 kHz, so each of the 128
unique bins covers a frequency interval of `48 kHz / 256 = 187.5 Hz`.
Bin index `n ∈ [0, 127]` corresponds to the centre frequency
`freq_Hz = n × 187.5`:

| Bin range  | Centre-frequency range |
|------------|------------------------|
| `0`        | 0 Hz (DC)              |
| `1..3`     | 187.5 Hz to 750 Hz     |
| `4..7`     | 750 Hz to 1.5 kHz      |
| `8..15`    | 1.5 kHz to 3.0 kHz     |
| `16..31`   | 3.0 kHz to 6.0 kHz     |
| `32..63`   | 6.0 kHz to 12.0 kHz    |
| `64..95`   | 12.0 kHz to 18.0 kHz   |
| `96..127`  | 18.0 kHz to 24 kHz (Nyquist) |

All four pre-computed gain tables below use **piecewise-constant
curves** — each row of 8 bins shares the same Q2.14 coefficient.
This keeps the table small (128 × 16 bits = 256 bytes per mode) and
makes the response easy to inspect at a glance. Finer-grained shaping
(e.g. per-mode interpolation of audiogram data) is a later phase.

---

## 2. Pre-computed Gain Tables

All gain values are expressed in **Q2.14 fixed-point** (unsigned,
16 bits), with the encoding `gain_linear = q14_value / 16384`. The
important reference points are:

| Q2.14 (hex) | Linear gain | Gain (dB) | Use                                         |
|------------:|------------:|----------:|---------------------------------------------|
| `0x0000`    | 0.000×      | −∞        | Mute (zero bin)                             |
| `0x2000`    | 0.500×      | −6.0      | Half-attenuation                            |
| `0x4000`    | 1.000×      | 0.0       | Unity (passthrough)                         |
| `0x6000`    | 1.500×      | +3.5      | Mild boost                                  |
| `0x7FFF`    | ≈ 1.9999×   | +6.0      | Maximum valid (still in unsigned range)     |

The tables below show the Q2.14 hex value on each row and the
corresponding linear multiplier / dB value in parentheses. The bins
are listed in 8-wide rows; the columns within a row all share the
same coefficient.

### 2.1 Mode 0 — General (transparent passthrough)

**Goal.** Flat unity-gain across the entire spectrum; the user hears
exactly what the microphone captures.

**LED colour.** Green (RGB LED0 drive: R=1, G=0, B=1, active-low).

**Curve description.** Every bin is `0x4000` (1.00×, 0.0 dB). No
frequency-dependent shaping.

```
bin  0..  7: 0x4000 (1.000×,  0.0 dB)
bin  8.. 15: 0x4000 (1.000×,  0.0 dB)
bin 16.. 23: 0x4000 (1.000×,  0.0 dB)
bin 24.. 31: 0x4000 (1.000×,  0.0 dB)
bin 32.. 39: 0x4000 (1.000×,  0.0 dB)
bin 40.. 47: 0x4000 (1.000×,  0.0 dB)
bin 48.. 55: 0x4000 (1.000×,  0.0 dB)
bin 56.. 63: 0x4000 (1.000×,  0.0 dB)
bin 64.. 71: 0x4000 (1.000×,  0.0 dB)
bin 72.. 79: 0x4000 (1.000×,  0.0 dB)
bin 80.. 87: 0x4000 (1.000×,  0.0 dB)
bin 88.. 95: 0x4000 (1.000×,  0.0 dB)
bin 96..103: 0x4000 (1.000×,  0.0 dB)
bin104..111: 0x4000 (1.000×,  0.0 dB)
bin112..119: 0x4000 (1.000×,  0.0 dB)
bin120..127: 0x4000 (1.000×,  0.0 dB)
```

### 2.2 Mode 1 — Speech (vocal presence boost with high-shelf roll-off)

**Goal.** Lift vocal fundamentals (200 Hz to 4 kHz), suppress
sub-bass handling noise, and roll off sibilance / high-frequency
harshness above 6 kHz.

**LED colour.** Blue (RGB LED0 drive: R=1, G=1, B=0, active-low).

**Curve description.** A low-cut below 750 Hz, a strong presence
boost across the vocal fundamental range (750 Hz to 4 kHz), a
gentle taper into the upper mid-range (4 kHz to 6 kHz), and a mild
high-shelf roll-off (0.90×) above 6 kHz to tame sibilance and
listening fatigue.

```
bin  0..  1: 0x2000 (0.500×,  -6.0 dB)   suppress sub-bass / handling noise
bin  2..  3: 0x3000 (0.750×,  -2.5 dB)   gentle low-cut above 375 Hz
bin  4..  7: 0x7000 (1.750×,  +4.8 dB)   presence boost on vocal fundamentals
bin  8.. 15: 0x7000 (1.750×,  +4.8 dB)
bin 16.. 20: 0x7000 (1.750×,  +4.8 dB)
bin 21.. 23: 0x5333 (1.300×,  +2.3 dB)   taper above 4 kHz
bin 24.. 31: 0x5333 (1.300×,  +2.3 dB)
bin 32..127: 0x39C2 (0.900×,  -0.9 dB)   gentle high-shelf roll-off (sibilance tame)
```

### 2.3 Mode 2 — Music (flat mids with sub-bass lift and air shelf)

**Goal.** Lift sub-bass fundamentals below ~190 Hz for body and
warmth; keep the vocal and instrument range (190 Hz to 6 kHz) flat
for accurate timbre; add an air/sparkle shelf above 6 kHz for
openness and detail.

**LED colour.** Magenta (RGB LED0 drive: R=0, G=1, B=0, active-low).

**Curve description.** A 1.20× DC bin lifts the very lowest
frequencies (DC + bin 1) slightly; the 190 Hz to 6 kHz mid range
stays at unity; an air/sparkle shelf at 1.15× sits above 6 kHz.

```
bin   0     : 0x4CCD (1.200×,  +1.6 dB)   gentle DC / sub-bass lift
bin   1..  7: 0x4000 (1.000×,   0.0 dB)   flat through vocal & instrument range
bin   8.. 15: 0x4000 (1.000×,   0.0 dB)
bin  16.. 23: 0x4000 (1.000×,   0.0 dB)
bin  24.. 31: 0x4000 (1.000×,   0.0 dB)
bin  32..127: 0x49A9 (1.150×,  +1.2 dB)   air / sparkle shelf above 6 kHz
```

### 2.4 Mode 3 — Hearing (ski-slope HF emphasis for high-frequency loss)

**Goal.** A mild ski-slope response that compensates the most common
form of high-frequency hearing loss: gentle attenuation below 600 Hz
to avoid masking, a rising slope into the consonant range, a strong
boost through 4 kHz to 8 kHz (the speech-intelligibility range), and
a gradual descent above 8 kHz so the very high frequencies are
emphasised but not piercing.

**LED colour.** Red (RGB LED0 drive: R=0, G=1, B=1, active-low).

**Curve description.** 0.90× below 600 Hz, 1.20× from 600 Hz to
2.25 kHz (rising slope), 1.60× from 2.25 kHz to 4.5 kHz (consonant
boost), 2.00× from 4.5 kHz to 8.25 kHz (peak), and a 1.60× shelf
above 8.25 kHz.

```
bin  0..  2: 0x39C2 (0.900×,  -0.9 dB)   mild low-cut to avoid masking
bin  3..  7: 0x4CCD (1.200×,  +1.6 dB)   upward slope (mild ski-slope loss)
bin  8.. 10: 0x4CCD (1.200×,  +1.6 dB)
bin 11.. 15: 0x6666 (1.600×,  +4.1 dB)   consonant / speech-intelligibility boost
bin 16.. 20: 0x6666 (1.600×,  +4.1 dB)
bin 21.. 23: 0x8000 (2.000×,  +6.0 dB)   peak: HF hearing-loss compensation
bin 24.. 31: 0x8000 (2.000×,  +6.0 dB)
bin 32.. 39: 0x8000 (2.000×,  +6.0 dB)
bin 40.. 42: 0x8000 (2.000×,  +6.0 dB)
bin 43.. 47: 0x6666 (1.600×,  +4.1 dB)   gradual descent above 8 kHz
bin 48..127: 0x6666 (1.600×,  +4.1 dB)
```

---

## 3. RGB LED Colour Map

The Arty S7-25's RGB LED0 is **active-low** (`1'b0` = ON, `1'b1` =
OFF). The 2-bit `current_mode` register drives the following
combinational decoder in `top.sv`:

| `current_mode` | Mode name | R pin | G pin | B pin | Resulting colour      |
|---------------:|-----------|------:|------:|------:|-----------------------|
| `2'd0`         | General   | `1`   | `0`   | `1`   | **Green**             |
| `2'd1`         | Speech    | `1`   | `1`   | `0`   | **Blue**              |
| `2'd2`         | Music     | `0`   | `1`   | `0`   | **Magenta** (R+B)     |
| `2'd3`         | Hearing   | `0`   | `1`   | `1`   | **Red**               |
| `default`      | (unused)  | `1`   | `1`   | `1`   | **Off** (all dark)    |

The XDC pin assignments are:

- `led_rgb_r` → `J15` (RGB0-R, Bank 15, LVCMOS33)
- `led_rgb_g` → `G17` (RGB0-G, Bank 15, LVCMOS33)
- `led_rgb_b` → `F15` (RGB0-B, Bank 15, LVCMOS33)

All three pins are `set_false_path -to` in the XDC (the LED changes
on a 1-2 Hz timescale at most; there is no benefit in having Vivado
optimise its placement).

---

## 4. Button Assignments

The four onboard push buttons (BTN0..BTN3) are the **sole** user
input surface in the FPGA-only architecture. They are all active-low
on the Arty S7-25 (pressed = `0`, released = `1`) and are debounced
in `btn_debounce.sv` before they reach the FSMs in `top.sv`.

| Button  | Function            | Behaviour                                                                          | Saturation limits             |
|--------:|---------------------|------------------------------------------------------------------------------------|-------------------------------|
| `BTN0`  | Mode **increment**  | `current_mode <= current_mode + 1` (wraps 3 → 0) on a single press pulse          | None — natural 2-bit wrap     |
| `BTN1`  | Mode **decrement**  | `current_mode <= current_mode - 1` (wraps 0 → 3) on a single press pulse          | None — natural 2-bit wrap     |
| `BTN2`  | Volume **up**       | `volume_level <= volume_level + 1` on a single press pulse                         | Saturates at `5'd31` (unity)  |
| `BTN3`  | Volume **down**     | `volume_level <= volume_level - 1` on a single press pulse                         | Saturates at `5'd0`  (mute)   |

### 4.1 Debounce timing

The `btn_debounce.sv` module is parameterised on:

- `CLK_FREQ_HZ = 96_000_000` (the DSP clock).
- `DEBOUNCE_MS = 20` (20 ms debounce window — standard for
  mechanical tactile switches).
- `NUM_BUTTONS = 4`.

The debouncer outputs a 1-cycle `press_pulse` on the leading edge
of every press and a 1-cycle `release_pulse` on the trailing edge.
The FPGA-only build consumes only `press_pulse`; `release_pulse` is
left available in case a future revision wants to implement
"long-press" detection (e.g. hold BTN0 for 1 s to reset to General).

### 4.2 Volume level mapping

The 5-bit `volume_level` (`0..31`) is converted to a Q2.14
multiplier by the `volume_ctrl` module inside `dsp_pipeline.sv`:

```
vol_q14 = level × (16384 / 31) ≈ level × 529
```

In other words:

| `volume_level` | `vol_q14` (decimal) | `vol_q14` (hex) | Linear gain   | Gain (dB)   |
|---------------:|--------------------:|----------------:|--------------:|------------:|
| `0` (mute)     | `0`                 | `0x0000`        | 0.000×        | −∞          |
| `1`            | `529`               | `0x0211`        | 0.032×        | −29.7       |
| `8`            | `4,232`            | `0x1088`        | 0.258×        | −11.7       |
| `16`           | `8,464`            | `0x2110`        | 0.516×        | −5.7        |
| `24`           | `12,696`           | `0x3198`        | 0.774×        | −2.2        |
| `31` (unity)   | `16,384`           | `0x4000`        | 1.000×        | 0.0         |

The mapping is **linear** in linear gain (not in dB): each step
adds `~0.032×` (or about `−0.27 dB` at the unity end). This was a
deliberate engineering trade-off — a perceptually-uniform dB-stepped
volume curve would require either a small LUT or a per-step piecewise
linear approximation, both of which exceed the value of the
improvement for an FPGA demo project. The volume starts at `31`
(unity) on FPGA reset so users hear audio immediately on power-up;
BTN3 presses from idle decrement toward mute.

### 4.3 Mode-change feedback

A successful mode change produces three observable effects:

1. The RGB LED colour changes within one DSP cycle of the
   `current_mode` register being updated (combinational decoder, no
   debounce on the LED side).
2. The `mode_we_pulse` fires for one DSP cycle. `mode_ctrl`
   consumes this pulse and reloads the inactive BRAM bank with the
   new mode's 128 coefficients over ~128 DSP cycles, then asserts
   `bank_commit_o` to swap banks atomically. The commit is
   synchronous to the DSP clock and cannot produce an audible click.
3. The `mode_default_master_gain_o` / `mode_default_noise_floor_o`
   / `mode_default_gate_ratio_o` outputs are computed
   combinationally by `mode_ctrl`, but in the FPGA-only build they
   are not consumed (the DSP pipeline's scalar controls are
   hardwired to unity gain / conservative floor / unity ratio).
   They remain available in case a future revision adds new
   per-mode scalar control.

---

## 5. Where to Read Next

- The DSP math, fixed-point formats, and per-stage latency live in
  [`dsp_pipeline.md`](dsp_pipeline.md).
- The system block diagram showing how `mode_ctrl` connects into
  the spectral processor is in [`block_diagram.md`](block_diagram.md).
- The two clock domains (CD_DSP and CD_I2S) and their crossings are
  in [`clock_domains.md`](clock_domains.md).
- The original SPI register map (now removed from the build, but
  preserved here for historical reference) is in
  [`register_map.md`](register_map.md).
- The pre-computed gain tables inside `mode_ctrl.sv` are the
  authoritative source for the exact Q2.14 coefficients; this
  document summarises them in human-readable form.
