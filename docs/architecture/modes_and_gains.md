# Profiles, volume, and indicators

[mode_ctrl.sv](../../fpga/rtl/ctrl/mode_ctrl.sv) embeds the four piecewise-constant gain tables. They are experimental
listening profiles, not individualized audiological prescriptions. Frequency bin spacing is 48000/256 = 187.5 Hz. The
authoritative values are the RTL arrays, not a separately generated fitting curve.

| ID | Profile | Gain shape in stored bins | Master / base threshold / attenuation ratio (raw words) | RGB |
| --- | --- | --- | --- | --- |
| 0 | General | Unity throughout | 16384 / 4096 / 12288 | Green |
| 1 | Speech | Bins 4..20 at unity; lower and upper bins strongly attenuated | 17203 / 16384 / 9830 | Blue |
| 2 | Music | Bins 1..3 and 32..127 at unity; middle bins attenuated | 16384 / 2048 / 13926 | Magenta |
| 3 | Hearing | Piecewise high-frequency emphasis; inspect GAIN_HEARING for exact words | 18022 / 32768 / 9011 | Red |

Master and ratio words use 14 fractional bits. The base threshold is normalized power in the same fractional scaling,
not an amplitude threshold. General has a flat gain table but still has gating; it is not the bypass path. The adaptive
floor in top may exceed the base value.

## Bank ownership

The mode FSM remembers the latest requested mode. It loads 128 words into the inactive bank, issues a commit request,
then waits for spectral_proc to acknowledge the active bank. The spectral processor changes banks at the first valid bin
of a frame and captures master, floor, and ratio for that frame. The old bank cannot be reused before acknowledgement.

In plain language, every frame gets one coherent profile. This avoids a frame containing a partially rewritten table.

[Frame-switch testing](../../fpga/sim/testbenches/tb_spectral_frames.sv) exercises every commit position; [mode
ownership testing](../../fpga/sim/testbenches/tb_mode_ownership.sv) connects the loader and processor. See [recorded
results](../verification/VERIFICATION_STATUS.md) for source-version limits.

## Buttons and LEDs

Current top and constraints use active-high buttons and RGB outputs. BTN0 increments profile modulo four; BTN1
decrements. BTN2 raises volume by four levels to a maximum of 31; BTN3 lowers it by four levels to zero. Debouncing
provides one event per accepted
press. There are 32 settings including mute, not 31 usable settings.

STATUS0 is the heartbeat. STATUS2 is a sticky combined error indication described in [STATUS2](../hardware/STATUS2.md).
It does not identify the error category or prove that audio is correct. Self-test RGB colors override normal profile
colors.

The internal bypass interface exists in dsp_pipeline, but production top keeps processing enabled. There is no host
register interface, runtime audiogram upload, or button-accessible bypass in the current build.

See [demonstration profile ranges](../hardware/DEMO_PROFILES.md) and the [video folder](../media/README.md).
