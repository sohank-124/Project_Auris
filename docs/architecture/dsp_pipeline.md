# DSP mathematics and numerical contracts

This is the current numerical reference for [dsp_pipeline.sv](../../fpga/rtl/dsp/dsp_pipeline.sv). Supported production
configuration: N=256, hop H=128, 48 kHz audio, 24-bit signed external samples, 16-bit transform mantissas. Several
modules explicitly reject other sizes. Changing one package constant does not resize the complete design.

## Window and reconstruction

[window_apply](../../fpga/rtl/dsp/window_apply.sv) takes the signed upper 16 bits of the left sample, an arithmetic
24-to-16 reduction. The right input is unused by the DSP. [window_rom](../../fpga/rtl/dsp/window_rom.sv) defines a
periodic Hann:

```text
w[n] = (1 - cos(2*pi*n/N))/2,  0 <= n < N
w[n] + w[n+N/2] = 1          in exact arithmetic
q[n] = round(16384*w[n])
u[n] = trunc_arithmetic((x24[n] >>> 8) * q[n] / 16384)
```

The half-hop identity follows because cos(theta+pi)=-cos(theta). A symmetric Hann with denominator N-1 does not have
this exact identity at an N/2 hop. Quantization and transform arithmetic introduce error, so the implementation is not
claimed to be distortion-free. There is one analysis window; there is no second synthesis-window multiplier.

In plain language, neighboring blocks have complementary tapers. Their sum reconstructs a unity-processed signal
approximately, subject to fixed-point error. This identity alone does not characterize nonlinear gating or arbitrary
changing profiles.

## Transform scaling and frame metadata

The vendor configuration is fixed-point with block-floating-point (BFP) scaling. BFP represents a frame with integer
mantissas and a shared exponent. For stored forward output M:

```text
M[k] approximately FFT(u)[k] / 2^E_fft
IFFT hardware is an unnormalized inverse transform
v[n] approximately inverse_unscaled(processed M)[n] / 2^E_ifft
```

The unnormalized forward/inverse pair contributes N=256. In the unity path this cancels the input's factor 1/256 from
dropping eight sample bits. The implementation therefore restores E_fft+E_ifft, with no pre-divide-by-256 gain table and
no additional fixed output multiply. This is the implemented numerical convention, supported by the historical vendor
reconstruction experiment, not a claim of bit-perfect recovery.

An 8-entry metadata FIFO captures forward-frame exponents and associates them with inverse output frames in transaction
order. It replaces any reliance on the unused legacy BFP_PIPE_DELAY constant. Each overlap contribution is restored
before addition:

```text
out[i] = sat24((current[i] << E_current) + (history[i] << E_history))
```

History stores mantissas and retains its old frame exponent. Adding mantissas first under one exponent would be wrong
when adjacent exponents differ. The first output hop represents zero history; startup and queue delays are not useful
steady-state audio measurements.

## Gain and threshold attenuation

[spectral_proc](../../fpga/rtl/dsp/spectral/spectral_proc.sv) consumes all 256 complex bins. Its 128 stored gain words
map by:

```text
j = k                  for k <= 128
j = 256-k              for k > 128
address = min(j,127)    (Nyquist extends word 127)
```

There are 129 unique bins including DC and Nyquist for a real 256-point transform. The current interface deliberately
stores 128 words and shares the final word with Nyquist. It does not synthesize missing conjugate data; both halves
arrive from the FFT and receive mirrored gains.

Gain words are unsigned 16-bit values with 14 fractional bits, range 0..65535/16384 (just below 4). Samples are signed.
Effective gain is `(bin_gain * master_gain) >> 14`, retained in 18 bits. A below-threshold bin uses `(effective_gain *
gate_ratio) >> 14`, retained in 20 bits. Signed complex products are arithmetically shifted and saturated to 16 bits.

For stored re/im, exponent E, and integer threshold T:

```text
restored_power = (re^2 + im^2) << (2*E)
threshold_power = T << 30
attenuate when restored_power < threshold_power; equality stays open
```

T/16384 describes power of the forward spectrum normalized as FFT(u)/(256*16384), where u is the integer transform
input. Equivalently, normalized power is restored_power/2^44. The 30-bit shift follows from power normalization by 256^2
and T's 14 fractional bits. The supported forward exponent is at most 16. Arithmetic comparisons preserve full precision
in 64 bits.

This is threshold-dependent attenuation, not spectral subtraction, learned noise classification, or a demonstrated
speech-enhancement algorithm. All profiles have nonzero base thresholds and attenuation ratios. The top-level heuristic
raises the floor from the squared smoothed absolute input level; speech also contributes to that tracker.

The seven registered stages are gain lookup, effective-gain multiplication, magnitude-square/attenuated-gain
calculation, power restoration, gain selection, complex multiplication, and saturation. Valid and last metadata follow
the data stages.

## Controls, saturation, and limits

Bank ownership and scalar settings are captured at the first bin of a frame. [Profile controls](modes_and_gains.md)
document the handshake. Frame consistency does not establish click-free transitions.

[volume_ctrl](../../fpga/rtl/dsp/volume_ctrl.sv) applies rounded `16384*level/31` after overlap-add, before output
buffering. Unity is exactly 16384. The sample container is 24 bits; internal 16-bit quantization means this is not a
claim of 24-bit effective precision.

Saturation prevents wraparound but is nonlinear. The clipping event currently detects input samples at the numeric rail;
it is not a comprehensive detector for internal spectral or overlap-add saturation. See [known
limitations](../verification/VERIFICATION_STATUS.md).

## Latency

A 256-sample span is 5.333 ms and the 128-sample hop is 2.667 ms at 48 kHz. Neither number is a measured
microphone-to-output latency. Frame position, transform cycles, queue wait, CDC/serializer phase, and codec delay all
contribute. No current physical latency result is available.

The [latency tools](../../tools/README.md) calculate conditional estimates or analyze separately captured signals.
Record actual hardware measurements with [the validation template](../hardware/HARDWARE_VALIDATION.md).
