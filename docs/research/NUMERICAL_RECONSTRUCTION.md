# Numerical reconstruction investigation

## Question and implementation context

How can a 24-bit input, 16-bit FFT/IFFT mantissas and variable frame exponents reconstruct a unity-processed signal
without a fixed gain mistake or inter-frame level discontinuity?

Source reasoning: [the DSP reference](../architecture/dsp_pipeline.md) derives the periodic Hann overlap identity and
normalization convention. Dropping eight input bits divides by 256; the unnormalized transform pair contributes 256.
Each frame's two BFP exponents must then be restored. Current/history contributions must be restored separately before
addition.

Plain language: the input loses scale before the FFT, the transform pair restores a fixed scale, and the shared
exponents account for additional frame-dependent scaling. Mixing the scaling of two different frames produces wrong
amplitudes.

## Alternatives and failure mechanisms

- A fixed exponent delay is simple but couples correctness to IP and pipeline latency. Transaction metadata adds queue
  state but makes association explicit.
- Adding mantissas before applying one exponent is cheaper to describe, but fails when neighboring frames use different
  scaling. Separate wide restoration costs arithmetic width and routing.
- Pre-dividing embedded gains by 256 would conflict with the current transform/input convention. Older documentation
  described that approach incorrectly; it is not the active implementation.
- The symmetric N-1 Hann is common for finite-record analysis, but its half-hop sum is not the exact periodic identity
  used here.

## Recorded experiment

An independent source-sample oracle supplied silence, DC, ramps, an impulse, bin-centered/off-bin tones, and amplitude
changes to the actual vendor-model pipeline. The [saved
run](../verification/evidence/historical-reconstruction/README.md) checked 16 frames, 2048 overlap-add and 1920 buffered
samples, including 11 exponent changes. It reported maximum absolute error 709 against an 8192-count limit.

This is a historical observation, not a rerun of the final sources. The [changed-input
list](../verification/evidence/historical-reconstruction/changed_since_run.json) includes current
spectral/pipeline/buffer edits. Inputs were burst-fed with drain gaps. A separately attempted 48 kHz-paced simulation
was stopped without a result, so no real-rate pass is claimed.

## What remains unknown

The absolute bound is about 0.098% of positive 24-bit full scale; that does not characterize relative error for small
signals, SNR, THD, gate artifacts, mode transitions, or physical audio. Per-segment RMS/relative error and a
current-revision sustained-rate run remain useful next measurements. The finite precision is part of the implementation
contract, not evidence of 24-bit effective audio quality.

[Coefficient export evidence](../verification/evidence/export-equivalence/README.md) separately checks actual ROM words
and embedded mode coefficients. It does not replace the full numerical experiment.
