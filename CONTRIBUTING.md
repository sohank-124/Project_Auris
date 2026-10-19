# Contributing to Project Auris

Thank you for your interest in Project Auris. Whether you are fixing a typo, porting a peripheral driver, or proposing
a new listening mode, this guide explains the workflow for focused changes and clear reviews.

Project Auris is an educational FPGA/DSP project. Contributions should be focused, tested, and accompanied by any
documentation updates needed to keep the design easy to understand.

---

## Table of Contents

1. [How to Contribute](#how-to-contribute)
2. [Branch Model](#branch-model)
3. [Code Style](#code-style)
4. [Testing Expectations](#testing-expectations)
5. [PR Process](#pr-process)
6. [Reporting Issues](#reporting-issues)
7. [Questions?](#questions)

---

## How to Contribute

We follow [GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow). In short:

1. **Fork** this repository to your own GitHub account.
2. **Create a branch** from `main` for your change (see [Branch Model](#branch-model)).
3. **Make your change** in focused, well-described commits.
4. **Push** your branch to your fork.
5. **Open a Pull Request** against `main` in this repository. Fill in the PR template, link any related issues, and
   include screenshots or recordings for user-visible changes.
6. **Iterate** on review feedback. Maintainers may request changes, ask for additional tests, or ask you to rebase onto
   the latest `main`.
7. Once CI is green and approvals are in, a maintainer will **squash-merge** your PR. The squashed commit message will
   follow the Conventional Commits format.

If you are working on a large change (new subsystem, new mode, new hardware revision), please open an issue first to
discuss the design before writing code. A short design note in the issue avoids wasted effort and keeps the architecture
coherent.

---

## Branch Model

Use a short-lived branch for each change and open a pull request against `main`.

### Naming convention

Use a category prefix followed by a short kebab-cased description:

| Prefix      | Use for                                                             |
| ----------- | ------------------------------------------------------------------- |
| `feature/`  | New functionality, new modules, new listening modes                 |
| `fix/`      | Bug fixes in any subsystem                                          |
| `refactor/` | Code or documentation restructuring with no behaviour change        |
| `docs/`     | Documentation-only changes (markdown, diagrams, comments)           |
| `chore/`    | Tooling, CI, build scripts, dependency bumps                        |
| `hw/`       | Hardware design (schematics, BOM, mechanical)                       |
| `exp/`      | Throwaway experiments; clearly marked as such in the PR description |

Examples: `feature/fft-overlap-add`, `fix/btn-debounce-glitch`, `docs/architecture-clock-domains`,
`chore/update-vivado-2024.2`.

### Keeping branches current

Rebase your branch onto `main` before requesting review:

```bash
git fetch origin
git rebase origin/main
git push --force-with-lease
```

Avoid merge commits from `main` inside your feature branch — they make the review diff harder to read and complicate
bisecting.

---

## Code Style

Each language has a single, enforced style. The CI pipeline runs the linter for every PR; please run it locally before
pushing.

| Language      | Style / tool                                                                                            | Config file                           |
| ------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| SystemVerilog | [Verible](https://github.com/chipsalliance/verible) `verible-verilog-lint` and `verible-verilog-format` | `.verible.rules` in `fpga/`           |
| Python        | `ruff` (lint + format) targeting PEP 8                                                                  | `pyproject.toml` in `tools/`          |
| Markdown      | `markdownlint` with the default rules                                                                   | `.markdownlint.json` at the repo root |
| Tcl (Vivado)  | `tclfmt` if available, otherwise 4-space indent and 100-column wrap                                     | manual                                |
| YAML          | `yamllint` with the default rules                                                                       | `.yamllint` at the repo root          |

### General principles

- Prefer **explicit** over clever. This codebase is read by college admissions reviewers and future contributors, not
  just by tools.
- Comment **why**, not **what**. If a line is genuinely tricky, a one-line rationale above it is more valuable than a
  paraphrase of the code.
- Keep modules small. A single SystemVerilog file should fit on one screen where possible; a single C source file should
  not exceed a few hundred lines.
- No trailing whitespace. Files end with a single newline.

---

## Testing Expectations

Every PR must leave the tree in a known-good state. At minimum:

- **FPGA** — if you touch anything under `fpga/`, run the relevant testbenches with `make fpga-sim` and confirm they
  pass. New RTL blocks must ship with at least one focused testbench under `fpga/sim/testbenches/`.
- **Tools** — if you touch anything under `tools/`, run the affected scripts on the bundled defaults and check the
  generated `.hex` / `.coe` artefacts into `fpga/generated/`.
- **Docs** — if you touch anything under `docs/` or any top-level markdown, run `markdownlint` and resolve all warnings.
- **CI** — all workflows defined in `.github/workflows/` must pass on your PR before it can be merged.

> **No firmware.** The FPGA-only build has no firmware at runtime. There is no `firmware/` step in the build. The
> `firmware/` directory is retained on disk per the 2026-08-12 migration brief (identical to `archive/firmware/`); it is
> not compiled or flashed and is not part of the build.

Coverage targets are informal at this stage, but a testbench that only exercises the reset path is not acceptable for
new code.

---

## PR Process

### Before opening

- Rebase onto the latest `main`.
- Run the linters and the test suite locally.
- Update documentation that the change affects (header comments, phase reports, the implementation plan, the BOM, etc.).
- If the PR is non-trivial, write a short summary of the design choices in the PR description. Reviewers will read this
  first.

### Opening

- Use the **pull request template** that GitHub auto-fills. Fill in every section, including the "How was this tested?"
  checkbox list.
- Link the issue the PR closes with `Closes #123` in the description.
- Keep the diff focused. A PR that mixes a typo fix, a refactor, and a new feature is harder to review and slower to
  merge. Open separate PRs.

### Review

- Keep review discussion respectful and technically focused.
- CI must be green. If CI fails, fix it or explain in the PR description why the failure is unrelated and can be safely
  ignored.
- Reviewers may request changes. Address them with follow-up commits rather than force-pushing the original commits away
  — this preserves the discussion in the PR timeline.

### Merging

- We **squash-merge** by default. The squashed commit message should follow
  [Conventional Commits](https://www.conventionalcommits.org/): `feat: add Music mode gain table to mode_ctrl` or
  `fix(rtl): btn_debounce double-fire`.

## Reporting Issues

Bug reports and feature requests are tracked as GitHub issues. Please use the issue templates:

- **Bug report** — for FPGA, tool, build, or hardware issues
- **Feature request** — for new listening modes, new peripherals, or new tools
- **Documentation** — for typos, missing information, or unclear passages in any `*.md` under `docs/` or the repo root
- **Hardware** — for wiring mistakes, BOM corrections, or mechanical issues

A good issue includes: a one-line summary, steps to reproduce (for bugs), the expected vs. actual behaviour, your
toolchain versions, and any relevant logs or screenshots.

---

## Questions?

If you are unsure about a design decision, a contribution workflow, or just want to bounce an idea around, open an issue
in [GitHub Issues](https://github.com/sohank-124/Project_Auris/issues) to discuss it before you commit to a PR.
