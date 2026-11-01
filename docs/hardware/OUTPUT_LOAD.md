# DAC output load contract

The PCM5102A is a stereo line-output DAC. TI specifies a minimum load resistance
of 1 kΩ per output; 16–32 Ω headphones are not a supported direct load.
Source: [TI PCM5102A datasheet, features and recommended operating
conditions](https://www.ti.com/lit/ds/symlink/pcm5102a.pdf).

For electrical verification, use a line input or measurement load meeting that
minimum. OUTL and OUTR are separate single-ended outputs referenced to ground.
Do not treat them as a differential headphone pair.

For headphone operation, the required connection is DAC line outputs -> verified
headphone amplifier -> headphones. If the breakout already includes an amplifier,
its schematic must identify that stage and its permitted headphone impedance.
A 3.5 mm connector is not evidence of an amplifier.

Document the breakout output stage, amplifier (if present), permitted load, supply and wiring alongside the hardware record.