# Changelog

## Unreleased local work

### Repository documentation cleanup, 2026-10-30

- Replaced conflicting current documentation with a concise README, subsystem references, and public verification
  status.
- Published selected saved implementation/reset/CDC evidence with source identity and explicit historical reconstruction
  limits.
- Preserved superseded documentation as unchanged text snapshots and all raw local audit workspaces.
- Added research/decision summaries, contribution provenance, file-management policy, and a pending physical validation
  template.
- Kept FPGA RTL, constraints, testbenches, build/simulation scripts and existing Python analysis implementations
  unchanged by the documentation cleanup.

### Prior local implementation repairs

The working tree already contained substantial uncommitted repairs before this cleanup, including frame/scaling
arithmetic, gain ownership, buffering, I²S framing, CDC constraints, reset release and simulation-runner checks. Their
individual implementation dates and authorship are not reconstructed here. See [verification
status](docs/verification/VERIFICATION_STATUS.md) for evidence and limits.

## Committed milestones

The local Git history contains these broad milestones; dates below come from Git, not an inferred experiment timeline:

| Commit | Date | Recorded subject |
| --- | --- | --- |
| 8363c5a | 2026-10-19 | chore: keep application and process files local |
| 1ab41c7 | 2026-10-18 | Add FPGA self-test and project documentation |
| 3056d24 | 2026-08-24 | WIP: current work in progress |
| 683acb0 | 2026-07-25 | Initial Project Auris implementation (original subject contains a typo) |

The [original changelog](archive/documentation/pre-cleanup-2026-10-30/CHANGELOG.md.txt) is retained as historical
wording, not a verified release ledger. No commit, push or history rewrite was performed for this cleanup.
