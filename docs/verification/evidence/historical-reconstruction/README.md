# Historical vendor reconstruction result

The saved transcript reports VENDOR_RECONSTRUCTION_PASS: 16 frames, 2048 overlap-add samples, 1920 final buffered samples, 11 exponent changes, maximum absolute error 709 against an 8192-count bound. It is dated 2026-10-29 in the simulator transcript.

[sources.json](sources.json) records original RTL, testbench, and vendor-model hashes with machine-specific root removed. [changed_since_run.json](changed_since_run.json) lists differing or missing current inputs at cleanup. This is evidence for the recorded earlier revision, not a current-revision pass. The complete old source snapshot is not reconstructed from hashes.

The bench uses 128-sample bursts followed by 4096-cycle gaps, unity gains, silence/DC/ramp/impulse/tones and amplitude changes. It checks source-aligned samples and metadata; it does not establish sustained 48 kHz scheduling, all-profile response, audio quality, or physical latency. The missing final 128 source samples require another frame to flush; expected counts are explicit in the bench.

[Original transcript](vendor_reconstruction_run.txt). [Current testbench](../../../../fpga/sim/testbenches/tb_pipeline_reconstruction.sv). Original local evidence is preserved in `.audit_verification/repair_runs/`.
