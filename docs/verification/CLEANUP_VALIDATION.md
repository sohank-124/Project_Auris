# Repository cleanup validation

Documentation and organization cleanup dated 2026-10-30. These checks validate the repository presentation, not new FPGA
functionality. Original documents, raw audit evidence, baseline hashes and the exact publication-candidate inventory
remain local under `.audit_verification/repository_cleanup/`.

## Executed checks

| Check | Outcome |
| --- | --- |
| Pre-existing RTL/constraints/benches/scripts/analysis input hashes | 123 of 123 unchanged from the start of cleanup |
| Makefile byte comparison | Unchanged |
| Saved implementation manifest | All 82 recorded input files match the cleanup source snapshot |
| Local documentation links and publication availability | Repository checker passes; includes relative targets and heading anchors |
| HDL test registration | All 24 active benches have public simulation entries |
| Tcl syntax completeness | 29 scripts complete according to Tcl info complete; no Vivado commands executed |
| Literal script file references | 47 literal bench/constraint/shared-runner references resolve |
| Aggregate simulation runner contract | Seven Python/Tcl fixture tests pass; no RTL simulation |
| Evidence/archive integrity | Selected report/transcript hashes and 24 original document snapshot hashes pass |
| Python syntax | New repository checker parses successfully |
| Basic Markdown layout | Maintained prose fits 120-column policy; code fences balanced |
| README style | No em dashes or badge claims |
| Git whitespace | git diff --check passes |
| Publication files | Reviewed 284 candidates, about 3.17 MiB total; largest file about 1.29 MiB; no file over 5 MB |
| Generated/tracked output review | No previously tracked bitstreams, waveforms, logs, reports or generated IP/project trees found |
| Ignore policy | Raw audits, working checklist and generated exports ignored; public source/research/evidence remain eligible |
| Credential indicators | Bounded pattern scan found no private-key, GitHub-token, AWS-key or Google-API-key matches; not a security guarantee |
| Git index | No staged changes; no commit/push/history operation |

Counts describe this cleanup checkpoint; rerunning the checker after future additions can change them. Public report
files are intentionally selected copies, not accidentally tracked build trees.

Commands executed with the installed Python runtime:

```sh
python -B tools/validation/check_repository.py
python -B -m unittest tools.validation.test_sim_runner
git diff --check
```

Additional local scripts compared SHA-256 input baselines, checked Tcl completeness and literal references, inspected
ignore behavior/publication candidates, and checked Markdown layout. They do not execute a Vivado build or certify
remote CI.

## Tools unavailable or not run

Markdownlint was absent from the local npm cache. Attempts to obtain markdownlint/Ruff/PyYAML failed or were stopped
after unavailable registry access; pip reported DNS resolution failures. No full markdownlint, Ruff formatter/lint, or
YAML-parser pass is claimed. Maintained Markdown is wrapped and local paths are checked, but remote Actions must still
validate its tool-specific rules.

No Vivado synthesis, implementation, bitstream programming, complete HDL suite, physical microphone/DAC test,
external-link network check or audio measurement was run for this cleanup. Existing saved FPGA results are identified in
[verification status](VERIFICATION_STATUS.md), without upgrading historical simulation results to current passes.

## Publication review

All original local changes remain. Archive snapshots preserve superseded text; raw investigations are local-only. The
new public evidence set includes original report warnings and unresolved limitations. Existing source comments with
historical descriptions and generated attribution are retained; current subsystem references explain the differences.

Before pushing, review intended tracked and untracked files together, include essential new source/constraint/test
entries and public evidence, let Actions run, and record actual board observations separately. Physical results should
update [the pending validation record](../hardware/HARDWARE_VALIDATION.md) only after testing.
