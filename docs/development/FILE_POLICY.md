# File-management and publication policy

## Public source and engineering record

Track active RTL, constraints, testbenches, maintained scripts, Python generators, configuration, workflows, and concise
current documentation. Keep substantive investigations in `docs/research/`, decisions and lessons in
`docs/development/`, and result claims in `docs/verification/VERIFICATION_STATUS.md`.

A research note should identify its question, implementation context, alternatives, observations, conclusion, and
uncertainty. Failed approaches belong when they explain a decision. Do not manufacture a successful experiment or remove
unresolved limitations for presentation.

## Public verification evidence

Put a bounded evidence set under `docs/verification/evidence/<date-or-investigation>/`: source hashes,
tool/configuration identity, meaningful reports/transcripts, and scope limitations. Selected `.rpt` and text transcripts
in that directory are intentionally publishable despite general build-output ignore rules. Do not commit a complete
Vivado workspace.

The existing saved report copies preserve original contents. New physical measurements belong in a dated subdirectory
under `docs/hardware/measurements/` when actual data exists. Include setup, instrument settings, source/bitstream
identity, raw data, units, analysis method, and limitations. Link demonstration media from the hardware record.

## Local-only material

`.audit_verification/` retains raw automated audits, repair workspaces, source backups, intermediate experiments and
bulky tool output. `REPAIR_CHECKLIST.md` remains a local chronological working record. These files are preserved, not
deleted. Important conclusions and unresolved issues are summarized publicly with selected supporting evidence.

Ignore regenerated IP/project trees, simulator databases, waveforms, bitstreams, caches, virtual environments, temporary
outputs, and coefficient inspection exports. Existing local application-planning documents stay local. Do not use a
general rule to hide all audits or research Markdown.

## Historical records

`archive/` holds removed ESP32/SPI source and superseded documentation. The pre-cleanup documentation snapshots use
`.md.txt` to preserve original bytes and relative references without presenting them as maintained Markdown. They may
contain mistakes, unsupported statements, institutional language, and broken historical references. They are historical
source records, not current specifications.

Small compatibility pages at old document paths point to current references. They avoid breaking incoming links without
repeating technical specifications. Every current subsystem has one primary explanation linked from
`docs/architecture/README.md`.

## Before publication

Run the repository checker, inspect all candidate tracked/untracked files, and verify the intended evidence is not
ignored. No cleanup command stages or commits files. A copied report proves only its recorded run. If implementation
inputs change, retain the older result with its source identity and produce a new result before upgrading its status.
