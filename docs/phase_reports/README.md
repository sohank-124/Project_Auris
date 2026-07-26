# Phase Reports

> **Project Auris** — End-of-phase reflection notes.
> **Last updated:** 2026-07
> **Status:** Authoritative. The template below is the structure
> that every phase report in this directory follows. The completed
> reports are listed in §3 and are written at the end of each
> phase, after the exit criteria from
> [`docs/ROADMAP.md`](../ROADMAP.md) §2 are met.

This README is a rewrite of the earlier stub. The previous
version had a 7-line template and a "to be filled in" note; the
version below expands the template into a full, opinionated
structure that captures goals, accomplishments, challenges,
learnings, metrics, artifacts, next steps, and reflection. The
completed-reports table in §3 tracks which phase reports are
in flight; §4 explains how to use the template.

A phase report is the author's most honest document in the
project. It is the place where things-that-didn't-work are
recorded, where surprises are named, and where the next phase
inherits not just the working code but the *wisdom* about how
to build the next piece.

---

## 1. Overview

A phase report is written at the end of each of the project's
6 phases. It is a structured reflection on what was built, what
was learned, what surprised the author, and what should change
in the next phase. The report is filed in this directory as
`phase_<N>.md` (e.g., `phase_0.md`, `phase_1.md`, ...).

The report has **three audiences**:

1. **The author, in 12 months.** When the next phase is being
   planned, the report is the first place to look for "what
   worked, what didn't, and what we said we'd do differently."
2. **A college-admissions reader.** A well-written phase report
   demonstrates engineering rigour, self-awareness, and the
   ability to learn from failure. The reports are the most
   quotable college-application artefact after the demo video
   and the technical report.
3. **A future contributor.** If the project is ever picked up
   by a community member, the phase reports are the "history"
   of the codebase — the *why* behind the *what*.

A phase report is **not** a status update. It is not "we built
X, Y, and Z." It is "we built X, Y, and Z, *and here's what
that taught us*."

---

## 2. Report Template

The full template is below. Use it as a Markdown skeleton;
copy it into `phase_<N>.md` and fill in every section. Do not
leave sections empty; if a section is not applicable, write
"N/A — <reason>" so the reader knows the section was
considered and explicitly excluded.

````markdown
# Phase N: <Title>

> **Project Auris** — Phase N report
> **Date:** YYYY-MM-DD (date the report was written)
> **Duration:** <start date> to <end date> (<N> weeks)
> **Author:** <name>
> **Phase goal:** <one-sentence summary from docs/ROADMAP.md §2>

## Goals

What this phase was supposed to accomplish. Pulled directly
from the entry criteria and tasks in `docs/ROADMAP.md` §2.<N>;
copied verbatim, with any pre-phase adjustments noted.

- [ ] Goal 1
- [ ] Goal 2
- [ ] Goal 3

## Accomplishments

What was actually built. For each goal above, describe:

- **What shipped.** Link to the commit, the bitstream, the
  firmware, the test results.
- **How it was verified.** What test was run, what
  measurement was taken, what the result was.
- **Where it lives.** Link to the file, the directory, the
  documentation page.

Aim for 3–5 bullet points per major goal. Use the metrics
table in §5 for the quantitative results.

## Challenges

What went wrong, what surprised the author, what took longer
than expected. For each challenge, describe:

- **What happened.** Concrete, specific. Avoid generic
  statements like "we had bugs" — name the bug.
- **Why it happened.** Root-cause analysis. Be honest.
- **How we fixed it.** The actual fix, not just the symptom.
- **Time cost.** How much time the fix added to the phase.

This section is the most important. A reader can predict a
project's future trajectory by reading this section.

## Key Learnings

The general lessons — abstracted from the specific challenges
above. What would the author tell a friend who is starting a
similar project?

- **Lesson 1.** <one-sentence summary, then 1–2 paragraphs
  of explanation>
- **Lesson 2.** ...
- **Lesson 3.** ...

The lessons should be *transferable*, not specific to this
project. ("We learned to check the XDC before running
synthesis" is not a lesson; "we learned to verify the pin
constraints before relying on the LED to indicate
correctness" is.)

## Metrics

The quantitative results from this phase. The table format is
the same for every phase; it makes cross-phase comparison easy.

| Metric | Target | Actual | Pass/Fail | Notes |
|--------|--------|--------|-----------|-------|
| Latency (Bypass) | < 1 ms | 0.7 ms | PASS | Measured with oscilloscope, 10 trials |
| FFT throughput | 96 MHz | 96 MHz | PASS | MMCM lock verified |
| LUT utilisation | ≤ 9,000 | 8,500 | PASS | Post-route, see report appendix |
| ... | ... | ... | ... | ... |

Add rows for every measurement taken during the phase; link
to the raw CSV in
`docs/MEASUREMENT_METHODOLOGY/measurements/`.

## Artifacts Produced

The concrete deliverables of this phase. List every file,
document, test, and artefact that was created.

- **Code:** <list of files added or significantly modified,
  with one-line descriptions>
- **Documentation:** <list of docs added or updated, with
  links>
- **Tests:** <list of testbenches, integration tests, and
  measurement scripts>
- **Hardware:** <list of parts ordered, breadboards wired,
  PCBs received>
- **Photos / videos:** <links to photos and videos taken
  during the phase>

## Next Phase

What the next phase will tackle. Pull the entry criteria from
`docs/ROADMAP.md` §2.<N+1>; list the tasks and the
exit criteria. Note any open questions or risks that should
be tracked.

- **Entry criteria for next phase:** <list>
- **Open questions:** <list>
- **Risks to track:** <list, with the corresponding risk
  register ID from docs/ROADMAP.md §4>

## Reflection

The author's honest, unstructured reflection on the phase.
This is the place for the things that don't fit anywhere
else: the late-night debugging sessions, the moments of
frustration, the moments of joy, the conversations with
friends, the unexpected turns.

This section is the most personal. It is also the most
useful for the three audiences listed in §1. Aim for 200–500
words.

## Appendix

Optional. Include raw measurement data, oscilloscope
screenshots, oscilloscope captures, FPGA resource-utilisation
reports, or any other supporting material that does not fit
inline. Use a clear naming convention:
`phase_<N>_appendix_<topic>.{csv,png,csv,pdf}`.
````

### 2.1 Template usage notes

- The Goals and Accomplishments sections should be roughly
  the same length; the goal is for the Accomplishments to
  answer the Goals point-by-point.
- The Challenges section is *required* — even if the phase
  went perfectly, the author should reflect on the
  near-misses, the things that almost went wrong, and the
  decisions that were considered but not taken.
- The Metrics section should have at least 3 rows, even if
  the values are "N/A — not yet measured." A future reader
  will want to compare the values across phases.
- The Artifacts Produced section should be exhaustive. The
  point is to make it easy to find *everything* that was
  touched during the phase.
- The Reflection section is intentionally unstructured. It
  is the place where the author can be most human.

---

## 3. Completed Reports

The table below tracks which phase reports have been written.
A report is "in progress" once the phase's exit criteria are
met (per `docs/ROADMAP.md` §2) and "done" once it has been
committed to this directory.

| Phase | Report | Date | Status |
|-------|--------|------|--------|
| Phase 0 | [`phase_0.md`](phase_0.md) | ⬜ | ⬜ Not started |
| Phase 1 | [`phase_1.md`](phase_1.md) | ⬜ | ⬜ Not started |
| Phase 2 | [`phase_2.md`](phase_2.md) | ⬜ | ⬜ Not started |
| Phase 3 | [`phase_3.md`](phase_3.md) | ⬜ | ⬜ Not started |
| Phase 4 | [`phase_4.md`](phase_4.md) | ⬜ | ⬜ Not started |
| Phase 5 | [`phase_5.md`](phase_5.md) | ⬜ | ⬜ Not started |

### 3.1 Status legend

- ⬜ Not started — the phase has not yet been completed, or
  the report has not yet been started.
- 🔧 In progress — the report is being drafted.
- ✅ Done — the report has been committed to this directory.
- 📝 Under review — the report is being reviewed by a
  collaborator before being finalised.

### 3.2 Cross-references

Every phase report should cross-reference:

- The corresponding section in
  [`docs/ROADMAP.md`](../ROADMAP.md) §2 for goals, tasks,
  and exit criteria.
- The corresponding measurements in
  [`docs/MEASUREMENT_METHODOLOGY.md`](../MEASUREMENT_METHODOLOGY.md)
  for the metrics and pass/fail criteria.
- The corresponding architecture docs in
  [`docs/architecture/`](../architecture/) for the
  technical details.
- The corresponding design decisions in
  [`docs/DESIGN_DECISIONS.md`](../DESIGN_DECISIONS.md) for
  the rationale behind the technology choices.

---

## 4. How to Use This Template

### 4.1 When to write a phase report

A phase report is written at the **end of a phase**, after the
exit criteria are met. The cadence is:

1. Run the exit-criteria measurements (per
   [`docs/MEASUREMENT_METHODOLOGY.md`](../MEASUREMENT_METHODOLOGY.md)).
2. Update the [`docs/ROADMAP.md`](../ROADMAP.md) phase
   table to mark the phase complete.
3. Open a new Git branch named `phase-report/<N>`.
4. Copy the template in §2 into `phase_<N>.md` and fill it
   in.
5. Open a pull request; review with a collaborator or
   mentor.
6. Merge to main; tag the commit with the phase number
   (e.g., `git tag -a phase-0-complete -m "..."`).

### 4.2 Time budget

A phase report takes **2–4 hours** to write well. Budget this
time *separately* from the phase itself; do not try to write
the report as the last step of the phase, when the author is
tired and the project is in flux. The report is most useful
when the author is one week past the phase's completion, when
the dust has settled and the lessons are clear.

### 4.3 Tone and voice

Write in the first person, present tense for the present
state, past tense for the events of the phase. The report is
a personal reflection, not a press release. The author should
sound like themselves, not like a corporate project manager.

Examples of good tone:

- "I underestimated the time it would take to install
  Vivado. The WebPack licence download alone took three
  days."
- "The first time the FPGA bitstream programmed and the LED
  blinked at 1 Hz, I knew the project was real."

Examples of bad tone (avoid):

- "The team successfully delivered all phase objectives on
  time and on budget."
- "There were no major challenges during this phase."

### 4.4 Length

A phase report should be **800–2000 words** in the main body
(Goals through Reflection). The Appendix is unbounded.
Shorter reports are fine for early phases (where there is
less to reflect on); longer reports are appropriate for the
MVP phase (Phase 2) and the integration phase (Phase 4).

### 4.5 Visual aids

Include photos, oscilloscope screenshots, FPGA
resource-utilisation reports, and measurement plots. A
report with at least 2 visual aids is more readable and more
memorable. Save the visual aids in
`docs/phase_reports/figures/phase_<N>/` and link them with
relative paths.

### 4.6 Cross-linking

Every phase report should include a "Where to Read Next"
section that links to:

- The next phase's report (when it exists).
- The corresponding architecture documents in
  [`docs/architecture/`](../architecture/).
- The corresponding measurements in
  [`docs/MEASUREMENT_METHODOLOGY.md`](../MEASUREMENT_METHODOLOGY.md).
- The risk register in [`docs/ROADMAP.md`](../ROADMAP.md) §4.

This makes the report a node in the documentation graph,
not an isolated file.

### 4.7 Review checklist

Before marking a phase report as done, the author should
verify:

- [ ] Every section of the template is filled in (no
  empty sections, no "TBD").
- [ ] The Goals section matches the entry criteria in
  `docs/ROADMAP.md` §2 for this phase.
- [ ] The Accomplishments section references specific commits
  and specific files.
- [ ] The Challenges section is honest and specific (no
  euphemisms).
- [ ] The Metrics section has at least 3 rows with quantitative
  data.
- [ ] The Artifacts Produced section is exhaustive.
- [ ] The Reflection section is personal and at least 200
  words.
- [ ] The report is spell-checked and proof-read.
- [ ] The report has been read by at least one other person
  (a parent, a teacher, a friend, a mentor).
- [ ] The report has been committed to the `main` branch
  and tagged with the phase number.

### 4.8 When to update an existing phase report

A phase report is **immutable** once committed. If a new
discovery changes the report's content (e.g., a measurement
taken two months after the phase ended reveals a previously
unknown issue), the author should:

1. Leave the original report untouched.
2. Add a "Postscript" section to the report with the date
   and the new finding.
3. Reference the postscript in the next phase's report.

This preserves the historical record while allowing for
corrections. The postscript is a feature, not a bug — the
*evolution* of understanding is itself a useful record.

---

## 5. Where to Read Next

- The 6-phase development plan and the per-phase exit
  criteria are in
  [`docs/ROADMAP.md`](../ROADMAP.md) §2.
- The measurement methodology that defines "done" for each
  phase's exit criteria is in
  [`docs/MEASUREMENT_METHODOLOGY.md`](../MEASUREMENT_METHODOLOGY.md).
- The design decisions that justify the technology choices
  are in [`docs/DESIGN_DECISIONS.md`](../DESIGN_DECISIONS.md).
- The architecture documents that each phase builds upon
  are in [`docs/architecture/`](../architecture/).
- The college-application framing of the project, including
  the role of the phase reports in the application
  portfolio, is in
  [`docs/college_app/README.md`](../college_app/README.md).
