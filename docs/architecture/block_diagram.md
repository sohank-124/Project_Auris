# System architecture and ownership

The FPGA is the I²S master for both external devices. All runtime audio processing and controls are in
[top.sv](../../fpga/rtl/top.sv). The assembled audio path has been demonstrated by the project owner; see the [hardware
record](../hardware/HARDWARE_VALIDATION.md).

```text
INMP441 -> I²S RX -> RX CDC pair -> input_buffer -> window_apply
 -> FFT input FIFO -> FFT -> spectral_proc -> IFFT input FIFO -> IFFT
 -> overlap_add -> volume_ctrl -> output_buffer -> TX CDC pair
 -> I²S TX -> PCM5102A line output
```

In plain language, samples become overlapping blocks for frequency processing, then return to a paced sample stream.
Buffers preserve order at each boundary.

| Block | Ownership and contract |
| --- | --- |
| RX/TX | 24-bit Philips I²S, 32-bit channel slots; TX changes serial output on falling BCLK |
| CDC pair in each direction | Two depth-4 LUTRAM FIFOs; both channels accepted/popped together |
| Input buffer | One circular 256 x 48-bit RAM; every 128 inputs publishes 256 chronological samples; initial history masked to zero |
| Window | Left input only, upper 16 sample bits, periodic Hann; imaginary input zero |
| FFT/IFFT | Separate XFFT v9.1 instances; 256 points, 16-bit data, BFP, natural order, pipelined streaming, realtime configuration |
| Spectral processor | Seven registered stages; gain symmetry, saturating multiply, threshold-dependent attenuation |
| Exponent queue | Frame metadata in transaction order, independent of assumed transform latency |
| Overlap-add | Previous second half plus current first half; each restored with its own exponent |
| Volume | 32 settings numbered 0..31; 0 mute, 31 exact unity |
| Output buffer | Two owned 128-sample blocks in a 256 x 48-bit RAM; paced by input sample-valid |

An output-buffer overrun rejects an entire incoming block and preserves unread data. CDC overfill rejects a stereo pair.
These are bounded loss policies, not guarantees against all possible stalls.

The processed stream is mono, copied to both headphone channels. The received right channel is not independently
spectrally processed. The bypass mux inside dsp_pipeline passes both input channels through a one-cycle register while
the processing chain continues internally. Production top ties DSP enable high; there is no onboard bypass button.

[Controls](modes_and_gains.md), [numerical contracts](dsp_pipeline.md), and [clock boundaries](clock_domains.md) provide
the subsystem details. The historical ESP32/SPI source is retained only under [archive](../../archive/README.md).
