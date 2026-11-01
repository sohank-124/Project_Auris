# Working on Auris

Auris is a solo engineering project. Changes should be small enough to explain and verify. Existing generated/vendor
attribution must remain truthful.

Before changing RTL, identify whether a failure originates in design logic, stimulus/checkers, scripts/IP setup,
constraints, or physical implementation. Explain the intended behavior, alternatives, numerical widths,
throughput/latency, and expected resource/timing effects. Do not change correct RTL to compensate for a broken test
harness.

Keep current architecture documentation aligned with the sources and identify which tests were actually executed. A
saved pass applies to its recorded source/configuration; do not upgrade a claim because a script exists or a simulator
exits zero. Document untested behavior explicitly.

Use [build/test commands](docs/verification/REPRODUCING.md) and the [file policy](docs/development/FILE_POLICY.md). Run
`python -B tools/validation/check_repository.py` before publishing documentation. It performs local path, evidence and
registration checks, not synthesis or RTL verification. Review Git status manually; this workflow does not stage, commit
or push automatically.

Hardware measurements must identify actual setup and bitstream and stay separate from planned tests. Do not claim
clinical benefit or completed physical validation without evidence.
