# Contributing to Project Auris

Thank you for your interest in Project Auris. Whether you are fixing a
typo, porting a peripheral driver, drafting a phase report, or proposing a
new listening mode, this guide explains the workflow we follow so that
reviews stay fast and the history stays clean.

Project Auris is a college-application portfolio project maintained by a
small group of contributors. We use a lightweight GitHub Flow, a DCO
sign-off on every commit, and squash-merges to keep the main history
linear. Please read this document in full before opening a pull request.

---

## Table of Contents

1. [How to Contribute](#how-to-contribute)
2. [Developer Certificate of Origin (DCO)](#developer-certificate-of-origin-dco)
3. [Branch Model](#branch-model)
4. [Code Style](#code-style)
5. [Testing Expectations](#testing-expectations)
6. [PR Process](#pr-process)
7. [Pre-Push Checklist](#pre-push-checklist)
8. [Area Ownership](#area-ownership)
9. [Reporting Issues](#reporting-issues)
10. [Questions?](#questions)

---

## How to Contribute

We follow [GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow).
In short:

1. **Fork** this repository to your own GitHub account.
2. **Create a branch** from `main` for your change (see [Branch Model](#branch-model)).
3. **Make your change** in focused, well-described commits. Sign off each
   commit (see [DCO](#developer-certificate-of-origin-dco)).
4. **Push** your branch to your fork.
5. **Open a Pull Request** against `main` in this repository. Fill in the
   PR template, link any related issues, and include screenshots or
   recordings for user-visible changes.
6. **Iterate** on review feedback. Maintainers may request changes, ask
   for additional tests, or ask you to rebase onto the latest `main`.
7. Once CI is green and approvals are in, a maintainer will
   **squash-merge** your PR. The squashed commit message will follow the
   Conventional Commits format.

If you are working on a large change (new subsystem, new mode, new
hardware revision), please open an issue first to discuss the design
before writing code. A short design note in the issue avoids wasted
effort and keeps the architecture coherent.

---

## Developer Certificate of Origin (DCO)

Project Auris uses the [Developer Certificate of Origin v1.1](https://developercertificate.org/)
to certify that you have the right to contribute your work. The full
text is reproduced below.

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.

Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution, including
    all personal information I submit with it, is maintained
    indefinitely and may be redistributed consistent with this
    project or the open source license(s) involved.
```

To sign off, add a `Signed-off-by:` trailer to **every** commit message.
The easiest way to do this is to use `git commit -s`:

```bash
git commit -s -m "fpga: fix async FIFO underflow in cdc_i2s_to_dsp"
```

This appends a line of the form `Signed-off-by: Your Name
<you@example.com>` matching your git config. If you forget, the
DCO bot on the PR will flag the missing sign-off.

---

## Branch Model

The default branch is `main` and is **protected** — no direct pushes and
no force-pushes after the first commit. All work happens on short-lived
branches and lands via pull request.

### Naming convention

Use a category prefix followed by a short kebab-cased description:

| Prefix        | Use for                                                                |
|---------------|------------------------------------------------------------------------|
| `feature/`    | New functionality, new modules, new listening modes                    |
| `fix/`        | Bug fixes in any subsystem                                             |
| `refactor/`   | Code or documentation restructuring with no behaviour change           |
| `docs/`       | Documentation-only changes (markdown, diagrams, comments)             |
| `chore/`      | Tooling, CI, build scripts, dependency bumps                           |
| `hw/`         | Hardware design (schematics, BOM, mechanical)                          |
| `exp/`        | Throwaway experiments; clearly marked as such in the PR description    |

Examples: `feature/fft-overlap-add`, `fix/btn-debounce-glitch`,
`docs/architecture-clock-domains`, `chore/update-vivado-2024.2`.

### Keeping branches current

Rebase your branch onto `main` before requesting review:

```bash
git fetch origin
git rebase origin/main
git push --force-with-lease
```

Avoid merge commits from `main` inside your feature branch — they make the
review diff harder to read and complicate bisecting.

---

## Code Style

Each language has a single, enforced style. The CI pipeline runs the
linter for every PR; please run it locally before pushing.

| Language        | Style / tool                              | Config file                              |
|-----------------|-------------------------------------------|------------------------------------------|
| SystemVerilog   | [Verible](https://github.com/chipsalliance/verible) `verible-verilog-lint` and `verible-verilog-format` | `.verible.rules` in `fpga/`              |
| Python          | `ruff` (lint + format) targeting PEP 8     | `pyproject.toml` in `tools/`             |
| Markdown        | `markdownlint` with the default rules     | `.markdownlint.json` at the repo root    |
| Tcl (Vivado)    | `tclfmt` if available, otherwise 4-space indent and 100-column wrap | manual                                   |
| YAML            | `yamllint` with the default rules         | `.yamllint` at the repo root             |

### General principles

- Prefer **explicit** over clever. This codebase is read by college
  admissions reviewers and future contributors, not just by tools.
- Comment **why**, not **what**. If a line is genuinely tricky, a one-line
  rationale above it is more valuable than a paraphrase of the code.
- Keep modules small. A single SystemVerilog file should fit on one screen
  where possible; a single C source file should not exceed a few hundred
  lines.
- No trailing whitespace. Files end with a single newline.

---

## Testing Expectations

Every PR must leave the tree in a known-good state. At minimum:

- **FPGA** — if you touch anything under `fpga/`, run the relevant
  testbenches with `make fpga-sim` and confirm they pass. New RTL
  blocks must ship with at least one focused testbench under
  `fpga/sim/testbenches/`.
- **Tools** — if you touch anything under `tools/`, run the
  affected scripts on the bundled defaults and check the
  generated `.hex` / `.coe` artefacts into `fpga/generated/`.
- **Docs** — if you touch anything under `docs/` or any
  top-level markdown, run `markdownlint` and resolve all
  warnings.
- **CI** — all workflows defined in `.github/workflows/` must
  pass on your PR before it can be merged.

> **No firmware.** The FPGA-only build has no firmware at
> runtime. There is no `firmware/` step in the build. The
> `firmware/` directory is retained on disk per the 2026-08-12
> migration brief (identical to `archive/firmware/`); it is not
> compiled or flashed and is not part of the build.

Coverage targets are informal at this stage, but a testbench that only
exercises the reset path is not acceptable for new code.

---

## PR Process

### Before opening

- Rebase onto the latest `main`.
- Run the linters and the test suite locally.
- Update documentation that the change affects (header comments, phase
  reports, the implementation plan, the BOM, etc.).
- If the PR is non-trivial, write a short summary of the design choices
  in the PR description. Reviewers will read this first.

### Opening

- Use the **pull request template** that GitHub auto-fills. Fill in every
  section, including the "How was this tested?" checkbox list.
- Link the issue the PR closes with `Closes #123` in the description.
- Keep the diff focused. A PR that mixes a typo fix, a refactor, and a
  new feature is harder to review and slower to merge. Open separate PRs.

### Review

- Expect at least one review from a CODEOWNER of the affected area.
  Maintain a respectful, technically focused tone in review threads.
- CI must be green. If CI fails, fix it or explain in the PR description
  why the failure is unrelated and can be safely ignored.
- Reviewers may request changes. Address them with follow-up commits
  rather than force-pushing the original commits away — this preserves
  the discussion in the PR timeline.

### Merging

- We **squash-merge** by default. The squashed commit message should
  follow [Conventional Commits](https://www.conventionalcommits.org/):
  `feat: add Music mode gain table to mode_ctrl` or
  `fix(rtl): btn_debounce double-fire`.
- Releases are tagged by a maintainer from `main` after a meaningful
  batch of PRs has landed. The version follows
  [Semantic Versioning](https://semver.org/).

---

## Pre-Push Checklist

The repository ships with several upper-case placeholders that mark
the spots a maintainer must fill in before the **first** push to
GitHub. After that first commit, the values stay in lock-step with
GitHub, so the checklist only needs to be re-run when you onboard a
new project owner or change the project name.

### Find every placeholder in one command

```bash
grep -rn '<[A-Z_]*>' README.md CONTRIBUTING.md CODEOWNERS CITATION.cff .github/
```

A clean tree (post-substitution) should print **no** matches in
any of the four files outside this section. The shell-escaped
regex matches any all-caps token wrapped in angle brackets
(`OWNER`, `LAST_NAME`, `FIRST_NAME`, etc.). The lowercase
placeholder `you@example.com` in `CITATION.cff` is the single
exception; find it with a follow-up grep:

```bash
grep -n '<you>@example\.com' CITATION.cff
```

> **Note on false positives.** This pre-push section itself
> mentions the placeholders (using `⟨OWNER⟩` and the like, with
> Unicode angle brackets `⟨` `⟩` so the grep above does not match
> them). Treat any matches in this section as documentation and
> leave them alone.

### Placeholders and where they live

| Placeholder            | Replace with                  | Files it appears in                                                                                                |
|------------------------|-------------------------------|--------------------------------------------------------------------------------------------------------------------|
| `⟨OWNER⟩`              | Your GitHub username (or team slug) | `README.md`, `CONTRIBUTING.md`, `CODEOWNERS`, `CITATION.cff`, `.github/ISSUE_TEMPLATE/config.yml` |
| `⟨LAST_NAME⟩`          | Your last name                | `CITATION.cff`                                                                                                     |
| `⟨FIRST_NAME⟩`         | Your first name               | `CITATION.cff`                                                                                                     |
| `⟨you⟩@example.com`    | Your contact email            | `CITATION.cff`                                                                                                     |

Total: **25 occurrences of `⟨OWNER⟩` across 5 files**, plus 1
each of `⟨LAST_NAME⟩`, `⟨FIRST_NAME⟩`, and `⟨you⟩@example.com` in
`CITATION.cff`. The CI workflows in `.github/workflows/*.yml` do
not currently contain any upper-case placeholders, but they do
reference GitHub Actions by their canonical names (e.g.
`actions/checkout@v4`); you do not need to edit them for the
`⟨OWNER⟩` substitution.

### Step-by-step

1. **Decide on the GitHub owner.** This is the user or organisation
   that will host `https://github.com/⟨OWNER⟩/project-auris`. It
   appears in the README badge URLs, the `git clone` command, the
   `CODEOWNERS` review-routing handles, the issue-template contact
   links, and the `CITATION.cff` repository URL.
2. **Run the grep above.** It will list every line that still has
   a placeholder. Open each file and substitute.
3. **Verify zero matches in the substitution targets.** Re-run
   the grep; only the documentation references inside this
   `Pre-Push Checklist` section may remain. A clean run against
   the *other* files means the first push can proceed.
4. **Commit the substitutions as a single chore commit** with a
   message like `chore: replace ⟨OWNER⟩ placeholders with @your-username`.
   This keeps the substitutions easy to audit and easy to revert
   if the GitHub owner ever needs to change.
5. **Push** — see [PR Process](#pr-process) for the open-the-PR
   workflow.

> **Do not skip this checklist.** A repository pushed to GitHub
> with `⟨OWNER⟩` still in place will render broken badge images,
> route reviews to a non-existent user (`@⟨OWNER⟩`), and cite the
> wrong author in the "Cite this repository" panel. The first
> reviewer to spot it will request changes.

---

## Area Ownership

The `CODEOWNERS` file at the root of this repository is the
source of truth for review routing. Pull requests touching the
listed paths will automatically request a review from the listed
owners.

| Path                  | Owns                                                  |
|-----------------------|-------------------------------------------------------|
| `/fpga/`              | SystemVerilog RTL, constraints, testbenches, scripts  |
| `/tools/`             | Python code generators and validation tools            |
| `/hardware/`          | Schematics, BOM, mechanical notes                     |
| `/docs/`              | Architecture, hardware, phase reports, college app    |
| `/archive/`           | Historical ESP32 + FPGA source (read-only, preserved) |
| `/.github/workflows/` | CI workflows and GitHub Actions configuration        |

The `/firmware/` directory is the historical ESP32 firmware
tree. It is retained on disk per the 2026-08-12 migration brief
and is identical in content to `/archive/firmware/`. It is **not**
part of the build; changes to it require explicit coordination
with the archive canonical copy and are unlikely to be merged.

At the time of writing, all paths default to the project owner
(`@<OWNER>`). As additional maintainers join, add them to the
relevant section of `CODEOWNERS` rather than to the default.

---

## Reporting Issues

Bug reports and feature requests are tracked as GitHub issues. Please use
the issue templates:

- **Bug report** — for FPGA, tool, build, or hardware issues
- **Feature request** — for new listening modes, new
  peripherals, or new tools
- **Documentation** — for typos, missing information, or unclear passages
  in any `*.md` under `docs/` or the repo root
- **Hardware** — for wiring mistakes, BOM corrections, or
  mechanical issues

A good issue includes: a one-line summary, steps to reproduce (for bugs),
the expected vs. actual behaviour, your toolchain versions, and any
relevant logs or screenshots.

---

## Questions?

If you are unsure about a design decision, a contribution workflow, or
just want to bounce an idea around, open a thread in
[GitHub Discussions](https://github.com/<OWNER>/project-auris/discussions).
Discussions are a lower-friction venue than issues and are a good place
to talk through a proposal before you commit to a PR.
