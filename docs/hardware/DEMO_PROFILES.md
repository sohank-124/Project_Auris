# Demonstration profiles and button volume

These profiles deliberately exaggerate frequency differences for demonstrations.
At 48 kHz with a 256-point FFT, adjacent bins are 187.5 Hz apart.
Coefficients below are linear amplitude multipliers; transitions occur at bin boundaries.

| Profile | Bin ranges and gains |
| --- | --- |
| General | 0–127: 1.0 |
| Speech | 0–1: 0.0625; 2–3: 0.25; 4–20: 1.0; 21–31: 0.25; 32–127: 0.0625 |
| Music | 0: 0.0625; 1–3: 1.0; 4–20: 0.25; 21–31: 0.5; 32–127: 1.0 |
| Hearing | 0–3: 0.0625; 4–10: 0.125; 11–20: 0.5; 21–42: 1.0; 43–127: 0.5 |

The existing mode master gains and gating defaults remain in effect. Hearing is an educational high-frequency emphasis
profile, not a fitted hearing correction.

BTN2/BTN3 now move four volume levels per press, saturating at 31/0.
The 32-entry linear volume multiplier is unchanged. Starting at 31, eight down presses reach mute; eight up presses
return to unity. There is no hold-to-repeat behavior.

Changed RTL: ctrl/mode_ctrl.sv (constants), top.sv (saturating button step).
No pipeline stages, interface widths, clocks, or multiplier instances are added.
Expected side effects: stronger coloration, different overall loudness between modes, and coarser volume adjustment.
Actual resource use and timing require the new implementation reports.
