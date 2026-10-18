# Project Auris From Zero

## A beginner's guide to the complete FPGA audio system

> Project Auris is an educational FPGA and DSP project built for the Digilent Arty S7-25 board. It is intended to demonstrate digital design, signal processing, clock-domain crossing, fixed-point arithmetic, verification, timing closure, and professional engineering practice.
>
> This is not a medically certified hearing aid. It is an engineering prototype and a college-application project.

---

## How to use this document

This guide explains the current codebase from the ground up. It assumes that you may know basic programming but do not yet know FPGA design.

Read it in this order:

1. Learn what an FPGA is and how this project is divided into hardware blocks.
2. Follow one audio sample from the microphone to the headphones.
3. Learn the clock domains and why clock-domain crossing is necessary.
4. Learn the DSP math: windows, FFTs, gains, noise gating, IFFT, overlap-add, and fixed-point numbers.
5. Learn how buttons and modes affect the signal.
6. Learn how the design is verified and programmed.
7. Read the limitations and remaining engineering work at the end.

The most important source files are linked throughout the guide. The source code is the final authority when a document and an implementation disagree.

---

# 1. The project in one sentence

Project Auris takes digital audio from an I2S microphone, moves it safely into a fast FPGA processing clock domain, analyzes it with a 256-point FFT, changes the level of frequency bands according to a listening mode, reconstructs the time-domain audio with an IFFT and overlap-add, and sends the result to an I2S headphone DAC.

The complete active signal path is:

```text
INMP441 microphone
    -> I2S receiver
    -> I2S-to-DSP asynchronous FIFOs
    -> input frame buffer
    -> Hann window
    -> 256-point FFT
    -> spectral gain and noise gate
    -> 256-point IFFT
    -> overlap-add reconstruction
    -> volume control
    -> output frame buffer
    -> DSP-to-I2S asynchronous FIFOs
    -> I2S transmitter
    -> PCM5102A DAC
    -> headphones
```

The FPGA is the center of the design. There is no active ESP32, no active SPI control bus, and no runtime firmware in the current architecture.

---

# 2. What an FPGA is

A normal program runs instructions one after another on a processor. An FPGA is different: your SystemVerilog code describes hardware circuits.

A useful mental model is:

- A `logic` signal is a wire or a stored bit.
- An `always_ff` block describes flip-flops, which remember values on clock edges.
- An `always_comb` block describes combinational logic, which calculates outputs from current inputs.
- A module is a reusable hardware block.
- A clock edge is a moment when synchronous registers update.
- Multiple modules can operate at the same time because they become separate circuits.

For example:

```systemverilog
always_ff @(posedge clk_i) begin
    if (enable_i)
        counter <= counter + 1'b1;
end
```

This does not mean "run a software loop." It creates a register and an adder. At every rising edge of `clk_i`, the register either holds its value or loads the incremented value.

The whole Project Auris design is therefore a hardware pipeline. Audio samples are continuously moving through registers, RAMs, multipliers, FFT hardware, and clock-domain crossing structures.

---

# 3. The top-level module

The top-level integration module is [`fpga/rtl/top.sv`](fpga/rtl/top.sv).

It is the module Vivado connects directly to the FPGA pins. It has ports for:

- The 12 MHz board oscillator.
- Four active-low push buttons.
- I2S BCLK and LRCLK outputs.
- I2S microphone data input.
- I2S DAC data output.
- Two status LEDs.
- Three active-low RGB LED signals.

The top module does not perform all processing itself. Its job is to connect the major blocks and control the system-level behavior.

The top-level responsibilities are:

1. Start the clock generator.
2. Generate synchronized reset signals.
3. Debounce the buttons.
4. Maintain the current mode and volume level.
5. Connect the I2S receiver and transmitter.
6. Connect the clock-domain crossing FIFOs.
7. Connect the DSP pipeline.
8. Connect the mode controller to the spectral gain-table memory.
9. Track status and clipping.
10. Optionally enable the board self-test.
11. Decode the RGB LED state.

The top module is the system's wiring harness and control center.

---

# 4. Hardware platform

The target board is the Digilent Arty S7-25 Rev. E.

The FPGA is a Xilinx Spartan-7 XC7S25-1CSGA324-1. Important resources include:

- 23,360 logic cells.
- 45 block-RAM tiles.
- 80 DSP48E1 multiplier/accumulator slices.
- 150 user I/O pins.
- A 12 MHz onboard oscillator.
- Four onboard push buttons.
- Single-color status LEDs.
- An active-low RGB LED.
- USB-JTAG programming through the board's USB interface.

The external audio hardware is:

- INMP441: I2S MEMS microphone.
- PCM5102A: I2S DAC and headphone output device.
- Wired headphones.

The FPGA is the I2S master. That means the FPGA generates the bit clock and word-select clock. The microphone and DAC are slaves that use those clocks.

The current pin mapping is defined in [`fpga/constraints/arty_s7_25.xdc`](fpga/constraints/arty_s7_25.xdc).

Important pins:

| Function | Board connection | FPGA signal |
|---|---|---|
| I2S BCLK | Pmod JA4 | `i2s_bclk_o` |
| I2S LRCLK | Pmod JA5 | `i2s_lrclk_o` |
| Microphone data | Pmod JA6 | `i2s_adc_data_i` |
| DAC data | Pmod JA7 | `i2s_dac_data_o` |
| Mode plus | BTN0 | `btn_i[0]` |
| Mode minus | BTN1 | `btn_i[1]` |
| Volume plus | BTN2 | `btn_i[2]` |
| Volume minus | BTN3 | `btn_i[3]` |

The XDC file also defines electrical standards, timing constraints, I/O delays, pull-down behavior, and FPGA configuration properties.

---

# 5. Clock architecture

The design uses two active clock domains:

| Domain | Clock | Purpose |
|---|---:|---|
| DSP domain | 96 MHz | Buttons, mode control, buffers, FFT processing, telemetry |
| I2S domain | 3.072 MHz BCLK | I2S receiver, I2S transmitter, codec-facing serial data |

LRCLK is derived from BCLK at 48 kHz. A 48 kHz stereo frame contains 64 BCLK cycles: 32 cycles for the left slot and 32 cycles for the right slot.

## 5.1 Why the clocks are different

The microphone and DAC need to move one stereo sample pair every 1/48,000 second. The DSP needs much faster clock cycles so it can perform thousands of operations between audio samples.

At 96 MHz, one audio sample period contains approximately:

```text
96,000,000 / 48,000 = 2,000 DSP clock cycles
```

That gives the FPGA time to fill buffers, run spectral processing, and prepare output data.

## 5.2 Clock generation

The clock generator is [`fpga/rtl/clk_gen.sv`](fpga/rtl/clk_gen.sv).

The 12 MHz oscillator feeds an Xilinx `MMCME2_BASE` primitive.

The MMCM uses:

```text
VCO frequency = 12 MHz * 50 = 600 MHz
DSP frequency = 600 MHz / 6.25 = 96 MHz
```

The I2S bit clock is made by dividing the 96 MHz clock with a fractional pattern. The required ratio is:

```text
96 MHz / 3.072 MHz = 31.25
```

A normal binary counter cannot divide by 31.25 exactly, so the design uses a repeating pattern of integer half-periods. Some periods are 31 clock cycles and some are 32 clock cycles. Across the repeated pattern, the average is exactly 31.25 DSP clocks per BCLK period.

This creates bounded timing jitter. The average frequency is correct, and the audio codecs are designed to tolerate the small edge-to-edge variation.

## 5.3 LRCLK generation

LRCLK is generated by counting BCLK edges. It changes state every 32 BCLK cycles, so:

```text
3.072 MHz / 64 = 48 kHz
```

The LRCLK level identifies the current channel slot:

- Low: left channel.
- High: right channel.

## 5.4 Clock reset and lock

The MMCM produces a `locked` signal after its output clock is stable. That signal is used as the source for reset generation.

The helper module `reset_sync_stretch`, located at the bottom of [`top.sv`](fpga/rtl/top.sv), provides reset behavior for each destination domain:

1. Assert reset asynchronously when the MMCM is not locked.
2. Synchronize reset release into the destination clock.
3. Hold reset for additional cycles so downstream logic starts cleanly.

This prevents the DSP and I2S logic from starting while their clocks are unstable.

---

# 6. Clock-domain crossing

A clock-domain crossing, or CDC, occurs when a signal created by one clock domain is used by another clock domain.

A single control bit can cross using synchronizer flip-flops. Audio samples are more complicated because:

- They are multi-bit values.
- The clocks have different frequencies and phases.
- The producer and consumer do not necessarily update at the same time.
- Sampling a multi-bit bus independently can capture a mixture of old and new bits.

Project Auris uses asynchronous FIFOs for audio data.

## 6.1 I2S-to-DSP FIFO

The implementation is [`fpga/rtl/cdc/cdc_i2s_to_dsp.sv`](fpga/rtl/cdc/cdc_i2s_to_dsp.sv).

There are two instances:

- One FIFO for the left sample.
- One FIFO for the right sample.

Each FIFO is four entries deep and uses:

- Binary read and write pointers locally.
- Gray-coded pointers crossing between domains.
- Two synchronizer stages for each pointer.
- Full and empty comparisons.
- Distributed RAM instead of a full block-RAM tile.

## 6.2 Why Gray code is used

A binary counter can change several bits at once. For example:

```text
0111 -> 1000
```

Four bits change. If another clock samples during that transition, it could see a combination that never existed.

A Gray-coded counter changes only one bit per increment. That makes it much safer to synchronize between unrelated clocks.

## 6.3 DSP-to-I2S FIFO

The reverse-direction FIFO is [`fpga/rtl/cdc/cdc_dsp_to_i2s.sv`](fpga/rtl/cdc/cdc_dsp_to_i2s.sv).

The DSP writes processed samples at 96 MHz. The I2S side reads them at the audio frame rate.

The FIFO absorbs short bursts and timing differences. The output path also includes an output buffer so the DSP can produce a frame in a burst while the I2S transmitter consumes samples steadily.

## 6.4 The small elastic XFFT buffers

The XFFT cores have AXI-Stream `TREADY` signals. The core may temporarily deassert `TREADY`, meaning:

```text
I am not accepting a new word on this clock edge.
```

The module [`fpga/rtl/dsp/axis_stream_fifo.sv`](fpga/rtl/dsp/axis_stream_fifo.sv) provides a four-entry elastic buffer in front of each XFFT input. Each buffered word includes:

- 16-bit real data.
- 16-bit imaginary data.
- One `TLAST` bit marking the end of a frame.

The buffer preserves data while the XFFT stalls. It also records an overflow if the stall lasts too long.

The focused test is:

```text
fpga/scripts/sim_xfft_handshake.tcl
```

Its testbench runs for 4 ms, which is enough to cross the previously observed XFFT stall point without waiting for the entire slow full-audio simulation.

The verified result is:

```text
XFFT_HANDSHAKE_PASS: no elastic-buffer overflow through 4 ms
```

This proves the tested stall interval does not overflow either elastic buffer. It does not prove that an arbitrarily long future stall can never overflow a four-entry buffer.

---

# 7. I2S audio protocol

I2S is a serial audio protocol. It sends each audio sample one bit at a time.

The relevant signals are:

- BCLK: bit clock.
- LRCLK or WS: left/right word-select clock.
- SDATA: serial audio data.

## 7.1 Philips I2S timing

In standard Philips I2S:

1. LRCLK changes to identify the next channel.
2. There is a one-bit timing offset.
3. The data bits are transmitted most-significant bit first.
4. Data changes on one clock edge and is sampled on the other edge.

The receiver and transmitter must agree about that timing exactly. A one-bit error shifts every sample and creates severe audio corruption.

## 7.2 I2S receiver

The receiver is [`fpga/rtl/io/i2s_rx.sv`](fpga/rtl/io/i2s_rx.sv).

Its state machine:

```text
ST_IDLE
    -> ST_WAIT
    -> ST_SHIFT_LEFT
    -> ST_WAIT_RIGHT
    -> ST_SHIFT_RIGHT
    -> ST_VALID
    -> ST_IDLE
```

The left channel begins after the LRCLK falling edge. The receiver waits for the Philips-I2S offset, shifts 24 bits, and stores the left sample.

It then ignores right-channel padding until LRCLK rises. It shifts the right sample and produces a one-clock `valid_o` pulse when both channels are ready.

The receiver also detects invalid LRCLK behavior during right-channel shifting and latches `overflow_o`.

The focused receiver simulation verifies:

- Known left/right sample values.
- Multiple consecutive frames.
- Overflow behavior.
- Recovery without stalling.

The current result is 13/13 passing checks.

## 7.3 I2S transmitter

The transmitter is [`fpga/rtl/io/i2s_tx.sv`](fpga/rtl/io/i2s_tx.sv).

It:

1. Waits for the left-channel frame boundary.
2. Captures a left/right pair when valid data is available.
3. Emits silence and raises `underflow_o` if data is unavailable.
4. Shifts the left sample MSB first.
5. Shifts the right sample MSB first.
6. Changes the serial data output on the BCLK falling edge so the codec can sample it on the rising edge.

The transmitter uses a small LRCLK synchronizer inside the BCLK domain. This is a defensive implementation choice, but its exact external timing should still be checked with the real PCM5102A and a logic analyzer.

---

# 8. Button control

The button input module is [`fpga/rtl/io/btn_debounce.sv`](fpga/rtl/io/btn_debounce.sv).

Mechanical buttons do not produce one clean electrical transition. When pressed, the contacts can rapidly bounce between zero and one for a short time.

If the raw signal were connected directly to the mode counter, one press could look like many presses.

The debouncer uses:

1. Two synchronizer flip-flops.
2. Active-low inversion.
3. A stability counter.
4. A debounced state register.
5. Rising-edge and falling-edge pulse generation.

The default debounce time is 20 ms:

```text
96,000,000 clock cycles/second * 0.020 seconds
= 1,920,000 stable cycles
```

The module produces:

- `btn_pressed_o`: current debounced pressed state.
- `btn_press_pulse_o`: one DSP-clock pulse when pressed.
- `btn_release_pulse_o`: one DSP-clock pulse when released.

The mode and volume logic in `top.sv` consumes the press pulses rather than the raw button state.

---

# 9. Modes and volume

## 9.1 Mode selection

The mode register is a two-bit value:

| Value | Mode | RGB color |
|---:|---|---|
| 0 | General | Green |
| 1 | Speech | Blue |
| 2 | Music | Magenta |
| 3 | Hearing | Red |

BTN0 increments the two-bit value. BTN1 decrements it. Two-bit arithmetic naturally wraps:

```text
3 + 1 -> 0
0 - 1 -> 3
```

The mode table controller is [`fpga/rtl/ctrl/mode_ctrl.sv`](fpga/rtl/ctrl/mode_ctrl.sv).

## 9.2 Why gain tables are double-buffered

A gain table contains one gain value for each frequency bin. Loading 128 values takes many clock cycles.

If the active table were edited while the DSP was reading it, some bins could use the old mode and other bins could use the new mode. That would create a mixed frame and possibly an audible glitch.

The design therefore uses two banks:

```text
Bank A: active audio table
Bank B: table currently being loaded
```

The controller writes the inactive bank. After all 128 values are written, it emits a one-cycle commit pulse. The spectral processor changes active banks atomically.

Scalar mode controls are also registered at the commit edge, so the master gain, noise floor, and gate ratio change together with the gain table.

## 9.3 Mode frequency curves

Each mode is a frequency response. A gain greater than one boosts a frequency region. A gain below one attenuates it.

The mode tables are stored as Q2.14 values:

| Decimal | Meaning |
|---:|---|
| 0 | Mute |
| 8192 | 0.5x |
| 16384 | 1.0x unity |
| 24576 | 1.5x |
| 32767 | Approximately 2.0x maximum safe positive value |

The current profiles are intentionally simple first-pass curves:

- General: flat unity.
- Speech: suppresses low-frequency rumble, boosts vocal presence, reduces high-frequency harshness.
- Music: keeps the midrange flat and adds gentle high-frequency openness.
- Hearing: attenuates lower frequencies and emphasizes speech-intelligibility regions.

The tables are mirrored for conjugate FFT bins so a real input remains compatible with a real-valued IFFT output.

## 9.4 Volume control

The volume level is a five-bit value from 0 through 31.

The volume module is [`fpga/rtl/dsp/volume_ctrl.sv`](fpga/rtl/dsp/volume_ctrl.sv).

The level is converted to a Q2.14 multiplier:

```text
volume_gain = level * 16384 / 31
```

Examples:

```text
level 0  -> 0.000x -> mute
level 16 -> approximately 0.516x
level 31 -> 1.000x -> unity
```

The audio sample is multiplied by this gain and shifted right by 14 bits because Q2.14 products contain 14 fractional bits.

---

# 10. Input buffering and frames

The input buffer is [`fpga/rtl/dsp/input_buffer.sv`](fpga/rtl/dsp/input_buffer.sv).

An FFT needs a block of samples, not one sample at a time. Project Auris uses 256-sample frames with 50% overlap.

At 48 kHz:

```text
256 samples / 48,000 samples per second = 5.333 ms
128 samples / 48,000 samples per second = 2.667 ms hop size
```

The buffer stores recent samples in BRAM. Every 128 new samples, it produces a 256-sample frame containing:

```text
128 samples from the previous history
+ 128 newest samples
```

The overlap is important because windowed FFT processing would otherwise create gaps between frames.

The input buffer also tracks whether a new sample arrives while it is still reading a frame. That condition becomes an overflow/error indicator.

---

# 11. The Hann window

The window module is [`fpga/rtl/dsp/window_apply.sv`](fpga/rtl/dsp/window_apply.sv), and its coefficients are supplied by [`window_rom.sv`](fpga/rtl/dsp/window_rom.sv).

## 11.1 Why a window is needed

An FFT treats each frame as though it repeats forever. If a frame begins and ends at different signal values, the artificial boundary looks like a sharp discontinuity.

A discontinuity spreads energy into many frequency bins. This is called spectral leakage.

A Hann window smoothly fades each frame toward zero at both ends:

```text
w[n] = 0.5 - 0.5 * cos(2*pi*n/(N-1))
```

For a 256-sample frame:

- `w[0]` is approximately zero.
- The center is near one.
- `w[255]` is approximately zero.

The window is represented in Q2.14. The value one is represented by 16384.

The windowed sample is approximately:

```text
windowed = sample * window_coefficient / 16384
```

The input is reduced from 24 bits to the upper 16 bits before entering the XFFT IP. This saves hardware and matches the configured XFFT data width.

The current pipeline processes a real-valued mono signal and duplicates the reconstructed real output to both headphone channels.

---

# 12. The FFT

The FFT wrapper is [`fpga/rtl/dsp/fft_256.sv`](fpga/rtl/dsp/fft_256.sv).

The actual transform is performed by Xilinx XFFT v9.1 IP generated by the Tcl build scripts.

The FFT converts time-domain samples into complex frequency-domain bins.

For a frame `x[n]`, the forward transform is:

```text
X[k] = sum from n=0 to N-1 of:
       x[n] * exp(-j * 2*pi*k*n/N)
```

Here:

- `n` identifies a time sample.
- `k` identifies a frequency bin.
- `j` is the imaginary unit.
- `N` is 256.

Each bin represents a frequency interval:

```text
48,000 Hz / 256 = 187.5 Hz per bin
```

Examples:

| Bin | Approximate center frequency |
|---:|---:|
| 0 | 0 Hz DC |
| 1 | 187.5 Hz |
| 8 | 1.5 kHz |
| 16 | 3.0 kHz |
| 32 | 6.0 kHz |
| 64 | 12.0 kHz |
| 127 | 23.8 kHz |

## 12.1 Block floating point

The XFFT uses block floating point. Instead of representing every value with a permanently fixed scale, the IP uses:

- A signed mantissa.
- A block exponent shared by a frame.

This allows the FFT to use the available 16-bit range more effectively. The exponent tells later logic how much scaling occurred.

The DSP pipeline delays the FFT exponent through a register/SRL pipeline so it arrives alongside the corresponding IFFT output frame.

## 12.2 AXI-Stream handshaking

The XFFT data interface uses the standard `valid/ready` convention:

```text
transfer occurs only when valid == 1 and ready == 1
```

The current design puts a four-entry elastic buffer before both FFT and IFFT inputs. This preserves each data word and its `TLAST` frame marker during short XFFT stalls.

The focused regression is [`fpga/scripts/sim_xfft_handshake.tcl`](fpga/scripts/sim_xfft_handshake.tcl). It passes through 4 ms without elastic-buffer overflow.

---

# 13. Spectral processing

The spectral processor is [`fpga/rtl/dsp/spectral/spectral_proc.sv`](fpga/rtl/dsp/spectral/spectral_proc.sv).

It receives a complex FFT value:

```text
X = real + j*imaginary
```

It performs four conceptual stages:

1. Read the active per-bin gain.
2. Multiply the bin gain by the mode master gain.
3. Compute approximate power.
4. Apply the noise gate and multiply the complex bin.

## 13.1 Complex gain multiplication

The gain is real-valued, so it scales both components:

```text
Y_real = X_real * gain
Y_imag = X_imag * gain
```

The phase is not changed by a real gain. Only the amplitude changes.

## 13.2 Magnitude-squared estimate

The processor estimates bin power using:

```text
power = real^2 + imaginary^2
```

This avoids an expensive square-root operation. For deciding whether a bin is quiet, comparing squared magnitudes is enough:

```text
sqrt(power) < threshold
```

is equivalent to:

```text
power < threshold^2
```

The current implementation uses a calibrated fixed-point threshold representation.

## 13.3 Noise gate

If a bin is below the noise floor, its gain is replaced by the mode's gate ratio:

```text
if power < noise_floor:
    gain = gate_ratio
else:
    gain = normal_gain
```

The result is attenuation rather than an abrupt hard zero. This reduces low-level background noise while avoiding an overly harsh on/off gate.

## 13.4 Hermitian symmetry

A real time-domain signal has conjugate symmetry in the FFT:

```text
X[N-k] = conjugate(X[k])
```

To keep the IFFT output real, the gain applied to each conjugate pair must match:

```text
gain[k] = gain[N-k]
```

The mode table lookup mirrors the upper half of the compact 128-entry table so this condition is enforced automatically.

---

# 14. The IFFT

The inverse FFT wrapper is [`fpga/rtl/dsp/ifft_256.sv`](fpga/rtl/dsp/ifft_256.sv).

The inverse transform is:

```text
y[n] = (1/N) * sum from k=0 to N-1 of:
       Y[k] * exp(+j*2*pi*k*n/N)
```

The IFFT converts the modified frequency spectrum back into time-domain samples.

The output is still represented at the XFFT's 16-bit width. The DSP pipeline sign-extends it back to 24 bits before overlap-add reconstruction.

Since the active input is real-valued and the gain is real-valued, the expected useful result is the real IFFT component. The current top-level audio path duplicates that reconstructed real signal to left and right output channels.

---

# 15. Overlap-add reconstruction

The overlap-add module is [`fpga/rtl/dsp/overlap_add.sv`](fpga/rtl/dsp/overlap_add.sv).

The Hann window reduces each frame at its edges. The next frame overlaps the previous frame by 128 samples. Adding the overlapping portions reconstructs a continuous signal.

For the first half of a frame:

```text
output[n] = current_frame[n] + previous_history[n]
```

For the second half:

```text
history[n] = current_frame[n + 128]
```

The module stores history in BRAM and uses a pipeline to align:

- The current IFFT sample.
- The delayed BRAM history sample.
- The valid signal.
- The block exponent scaling.

The output is saturated to the signed 24-bit audio range.

## 15.1 Why saturation matters

A fixed-width signed number can overflow. If an output above the maximum simply wraps around, a loud positive signal can become a large negative signal, causing severe distortion.

Saturation instead clamps the value:

```text
above +8,388,607 -> +8,388,607
below -8,388,608 -> -8,388,608
```

---

# 16. Volume control and output buffering

The volume controller applies a time-domain gain after spectral processing. This makes the user volume control independent from the frequency profile.

The output buffer is [`fpga/rtl/dsp/output_buffer.sv`](fpga/rtl/dsp/output_buffer.sv).

The DSP can produce a processed frame in a burst. The I2S transmitter consumes samples at a fixed audio rate. The output buffer separates those rates using two halves of BRAM:

```text
DSP writes one half
I2S reads the other half
```

When a half is full, the buffer commits it as the next read half. Underflow is detected if the I2S side requests a sample before a complete half is ready.

---

# 17. Telemetry and indicators

The status monitor is [`fpga/rtl/ctrl/status_mon.sv`](fpga/rtl/ctrl/status_mon.sv).

It provides:

- A heartbeat LED that indicates the FPGA is running.
- A sticky clipping indicator.

The clipping indicator stays active after a clipping event until FPGA reset. This is useful on hardware because a short audio event might otherwise be impossible to observe visually.

The RGB LED is decoded in `top.sv`:

| Mode | RGB result |
|---|---|
| General | Green |
| Speech | Blue |
| Music | Magenta |
| Hearing | Red |

During loopback self-test, the RGB LED is used for test status instead of mode display:

- Blinking yellow: collecting evidence.
- Cyan: sustained loopback pass.
- Red: detected mismatch.

---

# 18. Self-test and board bring-up

The optional self-test is controlled by top-level parameters:

```systemverilog
SELF_TEST_ENABLE
SELF_TEST_LOOPBACK_ENABLE
SELF_TEST_PASS_BITS
```

The deterministic stimulus source is [`fpga/rtl/dsp/selftest_stimulus.sv`](fpga/rtl/dsp/selftest_stimulus.sv).

When enabled, it generates internal audio-like samples instead of depending on the microphone. In loopback mode it uses a high-entropy pattern so a floating or pulled-down input is less likely to look valid by accident.

The testbench emulates a jumper:

```systemverilog
assign i2s_adc_data_i = i2s_dac_data_o;
```

The hardware procedure is:

1. Build with self-test and loopback enabled.
2. Program the Arty S7-25.
3. Connect JA7 to JA6 with a jumper.
4. Observe the RGB LED.
5. Remove the jumper and confirm the pass state does not remain valid.

The self-test proves digital continuity and I2S bit-level behavior. It does not prove microphone acoustics, DAC analog output, headphone quality, or medical usefulness.

---

# 19. Why the important design decisions were made

## Decision 1: FPGA-only control

The earlier architecture used an external controller. The current design moves mode selection, volume, timing, and audio processing into the FPGA.

Why:

- Fewer external dependencies.
- Cleaner demonstration of FPGA skill.
- Deterministic hardware behavior.
- Easier board-only bring-up.
- No firmware/RTL synchronization problem.

Tradeoff: the button interface is simple and there is no advanced user application yet.

## Decision 2: 256-point FFT

A larger FFT gives better frequency resolution but uses more memory, multipliers, and latency. A smaller FFT reduces cost but produces coarser bands.

At 256 points and 48 kHz, the resolution is 187.5 Hz per bin. That is detailed enough for an educational speech/hearing-assistive demonstrator while remaining plausible for the Spartan-7 resource budget.

## Decision 3: 50% overlap

A 50% overlap provides a good balance:

- It reduces discontinuities.
- It satisfies the Hann constant-overlap-add relationship.
- It gives a new processed hop every 128 samples.
- It costs more memory than non-overlapped processing but improves audio continuity.

## Decision 4: Xilinx XFFT IP

The FFT is mathematically complex and timing-sensitive. Using the proven Xilinx XFFT IP reduces risk compared with writing a full FFT engine from scratch.

The project still demonstrates substantial custom RTL around the IP:

- Framing.
- Windowing.
- Gain processing.
- BFP exponent alignment.
- Overlap-add.
- CDC.
- Controls.
- Verification.

## Decision 5: Fixed-point arithmetic

Floating point is expensive on a small FPGA. Fixed-point arithmetic uses predictable widths and can map efficiently to DSP48E1 slices.

The cost is that every multiplication and shift must be scaled deliberately. That is why Q2.14 appears throughout the gain and window logic.

## Decision 6: Asynchronous FIFOs for CDC

The clocks have different rates and phase relationships. An asynchronous FIFO provides a standard, reusable, verifiable boundary instead of attempting to synchronize a multi-bit audio bus directly.

## Decision 7: Double-buffered gain tables

A mode switch should not partially change a frame. Loading the inactive bank and swapping at one commit edge gives a clean transaction boundary.

## Decision 8: Board self-test

The self-test isolates digital FPGA/I2S problems from missing codec hardware. That makes bring-up faster and gives a visible demonstration even before the microphone and DAC arrive.

---

# 20. Build and simulation workflow

## 20.1 Normal self-test build

From the repository root:

```powershell
& "C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" `
  -mode batch `
  -source fpga/scripts/build_project.tcl `
  -tclargs --self-test --self-loopback
```

The script now reuses the existing Vivado project for normal builds. Use `--clean` only when you deliberately want to regenerate the project and IP.

## 20.2 Fresh recovery build

If an old Vivado run is locked, use a new output directory:

```powershell
& "C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" `
  -mode batch `
  -source fpga/scripts/build_project.tcl `
  -tclargs --clean --proj-dir .\vivado_proj_final_buffered --self-test --self-loopback
```

## 20.3 Program the FPGA

```powershell
& "C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" `
  -mode batch `
  -source fpga/scripts/program.tcl `
  -tclargs --bit .\vivado_proj_final_buffered\auris.runs\impl_1\top.bit
```

Alternatively, use Vivado Hardware Manager:

1. Open Hardware Manager.
2. Open target and auto-connect.
3. Select the Arty FPGA.
4. Choose the generated `top.bit`.
5. Program the device.

## 20.4 Focused simulations

Fast, valuable regressions:

```powershell
vivado -mode batch -source fpga/scripts/sim_i2s_rx.tcl
vivado -mode batch -source fpga/scripts/sim_mode_ctrl.tcl
vivado -mode batch -source fpga/scripts/sim_spectral_proc.tcl
vivado -mode batch -source fpga/scripts/sim_xfft_handshake.tcl
```

The focused XFFT test is preferred for backpressure validation because the full top-level XFFT behavioral model is computationally expensive.

The full simulation suite is:

```powershell
vivado -mode batch -source fpga/scripts/sim_all.tcl
```

Some XFFT-heavy tests can take a long time in behavioral simulation. A timeout is not automatically an RTL failure; it must be classified as infrastructure-limited unless an assertion or data check fails.

---

# 21. Verification strategy

A good FPGA verification strategy checks several different things.

## 21.1 Unit-level tests

These isolate one module:

- I2S receiver framing.
- I2S transmitter serialization.
- Button debouncing.
- Mode-table loading.
- Spectral gain and noise gate math.
- Window multiplication.
- Overlap-add timing.
- CDC FIFO flags and data movement.

Unit tests are fast and make failures easier to diagnose.

## 21.2 Integration tests

These connect multiple blocks:

- Top-level self-test.
- XFFT handshake test.
- DSP pipeline test.
- Clock/reset bring-up.

Integration tests catch wiring and latency mistakes that unit tests cannot.

## 21.3 Hardware tests

The Arty self-test uses an external jumper to test the digital I2S loop. The later codec test adds:

- Real INMP441 clocking.
- Real microphone serial data.
- Real PCM5102A timing.
- Analog output.
- Noise and wiring effects.
- Actual mode audibility.

## 21.4 Assertions

Assertions turn assumptions into executable checks. The XFFT path now asserts that an elastic input buffer never overflows during the focused test. This is stronger than merely observing that a waveform looks active.

---

# 22. Current verified status

The current implementation has strong prototype-level evidence:

- I2S receiver regression: 13/13 checks passed.
- Mode controller regression: 10/10 checks passed.
- Spectral processor regression: 141/141 checks passed.
- Focused XFFT handshake regression: passed through 4 ms with no elastic-buffer overflow.
- Final buffered routed build: completed successfully.
- Routed setup slack: approximately +0.806 ns.
- Routed hold slack: approximately +0.051 ns.
- Failing timing endpoints: zero.
- Bitstream generated successfully.

The final buffered bitstream was generated under:

```text
vivado_proj_final_buffered/auris.runs/impl_1/top.bit
```

---

# 23. What is not yet proven

This distinction is important for honest engineering.

## Proven at source or focused simulation level

- Module connectivity and syntax.
- I2S RX framing.
- Mode controller table commits.
- Spectral gain/gate arithmetic.
- Short XFFT backpressure behavior.
- Synthesis, placement, routing, and timing closure for the buffered build.

## Not fully proven yet

- Long-duration full-pipeline audio correctness in XSim.
- Every possible duration of XFFT backpressure.
- Real microphone-to-headphone acoustic performance.
- Noise performance on a breadboard.
- Personalized hearing fitting.
- Safety or medical effectiveness.

The full top-level XFFT behavioral simulation is very slow because it models two large vendor IP cores in software. That is why the focused handshake test exists.

---

# 24. How to explain this project in a college application

A strong explanation is:

> I designed an FPGA-only real-time audio processor for an Arty S7-25. The FPGA generates the I2S clocks, safely crosses audio between clock domains with Gray-coded asynchronous FIFOs, frames audio into overlapping windows, processes it through Xilinx FFT/IFFT IP, applies programmable fixed-point frequency shaping, and reconstructs the output with overlap-add. I verified the design with unit simulations, a board-level digital loopback self-test, focused AXI-stream backpressure assertions, and post-route timing analysis.

The impressive part is not only that the project has named modes. The impressive engineering story is:

1. You selected a constrained FPGA platform.
2. You designed a multi-clock audio architecture.
3. You used fixed-point math intentionally.
4. You used vendor IP where it reduced unnecessary risk.
5. You built custom logic around the IP.
6. You found a real XFFT backpressure problem.
7. You added elastic buffering and an assertion-based regression.
8. You reached routed timing closure.
9. You can explain what remains unproven instead of overstating the result.

That last point is a professional engineering behavior.

---

# 25. Glossary

**ASIC**: Application-specific integrated circuit. Hardware manufactured for one design.

**AXI-Stream**: A streaming handshake protocol commonly used by Xilinx IP. A transfer occurs when `valid` and `ready` are both high.

**BCLK**: I2S bit clock. It clocks individual serial audio bits.

**BFP**: Block floating point. A shared exponent scales a block of fixed-width mantissas.

**BRAM**: Block RAM. Dedicated memory resources inside the FPGA.

**CDC**: Clock-domain crossing. The safe transfer of information between different clocks.

**DSP48E1**: A Xilinx FPGA hardware slice optimized for multiplication, addition, and accumulation.

**FFT**: Fast Fourier Transform. An efficient algorithm for converting time-domain samples into frequency bins.

**Flip-flop**: A one-bit storage element updated by a clock edge.

**FPGA**: Field-programmable gate array. A chip whose hardware logic is configured by a bitstream.

**I2S**: Inter-IC Sound. A serial digital audio protocol.

**IFFT**: Inverse Fast Fourier Transform. Converts frequency bins back into time-domain samples.

**LRCLK/WS**: I2S word-select clock. Identifies left and right channel slots.

**MMCM**: Mixed-Mode Clock Manager. An FPGA clock primitive used to multiply and divide clock frequencies.

**Q2.14**: A fixed-point format with 14 fractional bits. Divide the stored integer by 16384 to recover the real value.

**TLAST**: AXI-Stream marker identifying the last transfer in a frame.

**TREADY**: AXI-Stream signal indicating that a receiver can accept a transfer.

**TVALID**: AXI-Stream signal indicating that a sender is presenting a valid transfer.

**Vivado**: AMD/Xilinx FPGA development software used for synthesis, implementation, simulation, and programming.

---

# 26. Final perspective

Project Auris is best understood as a hardware pipeline, not a normal software application.

Every decision is a balance:

- More precision costs more resources.
- More overlap improves audio continuity but increases memory and latency.
- More buffering improves stall tolerance but consumes RAM and registers.
- More aggressive gain improves audibility but increases clipping risk.
- More complex simulation increases confidence but can become too slow to run productively.

The current design demonstrates the complete engineering loop:

```text
choose architecture
    -> implement RTL
    -> simulate units
    -> integrate modules
    -> find real failures
    -> repair root causes
    -> synthesize and route
    -> inspect timing
    -> program hardware
    -> validate with a physical self-test
```

That loop is the central lesson of the project.
