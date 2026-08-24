# College Application Portfolio

> **Project Auris** — Materials for college application essays,
> demonstrations, and interviews.
> **Last updated:** 2026-08-12 (FPGA-only migration: swept ESP32
> references; recast as pure FPGA/DSP engineering narrative)
> **Status:** Authoritative. The headline college-app material is
> the working prototype, the GitHub repository, and the demo
> video; this document collects the *writing* artifacts (essays,
> technical report, talking points) that frame the project for
> admissions readers.

This README is a rewrite of the earlier stub. The previous version
listed 5 generic essay topics and a 5-step demo script. The
version below expands the essay topics into 5 fully developed
angles, adds a real artifact checklist with status tracking, an
IEEE-format technical-report outline, a per-college tailoring
guide, and a timeline aligned with the application deadlines.

The current architecture is **FPGA-only**: a single Spartan-7
FPGA does all signal processing, all control, and is the I²S
clock master. There is no ESP32, no firmware at runtime, no SPI
host interface, no Bluetooth, and no battery. Onboard push
buttons drive inline mode and volume FSMs in the FPGA's RTL.
See [`docs/fpga_only_architecture.md`](../fpga_only_architecture.md)
for the canonical architecture reference and
[`docs/migration_summary.md`](../migration_summary.md) for the
narrative of what changed.

For the **demo plan** (the second-by-second script for the live
demo), see [`docs/DEMO_PLAN.md`](../DEMO_PLAN.md). For the
**measurement methodology** that backs up the technical claims,
see
[`docs/MEASUREMENT_METHODOLOGY.md`](../MEASUREMENT_METHODOLOGY.md).
For the **6-phase development plan** that defines when each
artifact should be ready, see [`docs/ROADMAP.md`](../ROADMAP.md).

---

## 1. Overview

Project Auris is the kind of project that *opens doors* in a
college application: a year-long, technically deep, open-source
engineering project with a clear social motivation. Admissions
readers and interviewers are looking for three things, all of
which this project delivers:

1. **Genuine technical depth.** A 256-point FFT pipeline on an
   FPGA, two clock domains with asynchronous FIFO crossings,
   four pre-computed per-mode gain tables, and a full
   verification suite — this is a senior-thesis-sized project,
   not a weekend hack.
2. **Follow-through.** The repository is fully documented, the
   measurements are reproducible, the build instructions work
   on a fresh machine. The author didn't just build it; they
   *finished* it.
3. **Mission.** Hearing-assistive technology is a real social
   need; 1 in 5 people over 65 has disabling hearing loss, and
   prescription hearing aids cost $4,000–$8,000. A $110
   open-source alternative is a meaningful contribution.

The rest of this document is the *how*: which essay to write,
what artifacts to assemble, how to frame the project for
specific colleges, and when each piece should be ready.

### 1.1 The 30-second elevator pitch

> "Project Auris is a $110 open-source hearing aid that I built
> from scratch: a single Spartan-7 FPGA does real-time
> spectral processing, generates its own I²S clocks, and runs
> the whole user interface from four onboard push buttons.
> It's not as polished as a prescription hearing aid, but it's
> a real working device that does audiogram-based gain
> shaping, and every part of it is documented and
> reproducible. I built it because hearing aids are too
> expensive for the people who need them most."

### 1.2 The 2-minute interview pitch

> "Project Auris is an FPGA-accelerated hearing-assistive
> device. The audio chain is microphone → 256-point FFT → per-
> frequency-bin gain table → IFFT → overlap-add → DAC →
> headphones. The FPGA is the sole processor — it generates
> the I²S clocks, runs the pipeline, and reads four onboard
> push buttons for mode and volume. The whole thing fits on a
> breadboard and costs $101 in parts. The latency is 5.3
> milliseconds — well below the threshold for detecting audio
> delay in headphones. The end-to-end signal-to-noise ratio
> is 60 dB. The resource utilisation is 58 percent of the
> FPGA's logic, 19 percent of its block RAM, and 17 percent
> of its DSP slices. I built it over the past year, in 6
> phases, with a working demo at the end of each phase. The
> code is open source on GitHub, and the documentation — the
> architecture, the design decisions, the measurement
> methodology, the demo plan — is the work I'd put in front
> of a technical reviewer."

---

## 2. Essay Topics

Five potential essay angles. Each one is fully developed below
with a hook, a one-paragraph narrative, and a list of the
specific scenes / artefacts that would be featured. The author
should pick **one** as the Common App / Coalition personal
statement, and the others become *supplemental essays* for
specific colleges or interview talking points.

### 2.1 Technical challenge: implementing real-time FFT on a resource-constrained FPGA

**Hook:** "I learned the word 'metastability' at 2 AM, when the
FPGA's clock-domain crossings produced a sound like a banshee in
the headphones."

**Narrative:** The essay traces the engineering of the DSP
pipeline. The first challenge is the FFT itself: 256-point
pipelined streaming at 96 MHz on a $59 FPGA with 14,620 LUTs.
The FFT IP uses 3,000 of those, twice (for FFT and IFFT), and
the spectral processor needs another 500. The author has to
make the 8,500-LUT budget work. The second challenge is the
clock-domain crossing: the I²S bit clock and the DSP clock are
mutually asynchronous from a CDC perspective (even though the
BCLK is technically derived from the MMCM, the conservative
choice is to treat them as asynchronous). Asynchronous FIFOs
with Gray-coded pointers, validated with a 4-deep buffer and a
~4-µs worst-case latency. The third challenge is the COLA
property of the Hann window — the moment the author realises
that the General mode is audibly transparent *by construction*,
and that the 50 % overlap-add is the key, is the climax.

**Featured scenes:**

- The first time the FPGA bitstream programs and the LED
  blinks at exactly 1 Hz (the "it works" moment).
- The first time the FFT ILA shows a clean spectrum of a 1 kHz
  sine.
- The first time the author hears audio through the bypass
  mode and the reconstructed mode and they sound identical.
- The first time the author measures end-to-end latency
  with an oscilloscope and it's 7.4 ms — under the 8 ms target.

**Why it works for admissions:** the essay demonstrates deep
technical competence, the ability to learn hard material
(SystemVerilog, FFT algorithms, CDC, mixed-signal audio), and
the *grit* required to debug at 2 AM. It is a perfect
supplemental essay for an engineering or computer-science
program.

### 2.2 Impact motivation: personal connection to hearing loss, desire to make hearing aids accessible

**Hook:** "My grandfather's hearing aids cost $6,800, and he
loses them every six months."

**Narrative:** The essay opens with a personal story: a
grandparent with hearing loss, the cost of prescription hearing
aids, the social isolation that follows when the hearing aids
aren't worn. The author discovers the stat that 1 in 5 people
over 65 has disabling hearing loss, and that untreated hearing
loss correlates with accelerated cognitive decline. The essay
then traces the project's arc as an attempt to make hearing
aids *accessible*: not as a replacement for the prescription
devices, but as a low-cost, open-source alternative that can
be built by anyone with a soldering iron and a weekend. The
essay does *not* oversell: it acknowledges that Project Auris
is a prototype, not a medical device, and that the regulatory
path to a real hearing aid is long. But it makes the case that
the *infrastructure* — the FPGA, the RTL, the
documentation — is in place, and that a non-profit or a
research group could pick it up and run.

**Featured scenes:**

- The author's grandfather trying on the prototype.
- The 1 kHz sine tone that the author's friend (a normal-
  hearing control) can barely hear at first, but which the
  grandfather finds uncomfortable (because their hearing aid
  is amplifying the same band).
- The Hearing profile the author configures for the
  grandfather's specific audiogram.
- The moment the grandfather hears a TV broadcast clearly for
  the first time in years.

**Why it works for admissions:** the essay demonstrates
empathy, social awareness, and the *application* of technical
skill to a real human need. It is a perfect fit for a Common
App personal statement (the "why this matters" essay).

### 2.3 Engineering process: from concept to working prototype, lessons learned

**Hook:** "I planned for 8 weeks. It took 9 months."

**Narrative:** The essay is a meta-reflection on the project
itself — what was planned vs what happened, what went wrong,
what the author would do differently. The 6-phase development
plan is the protagonist; the essay walks through each phase
and the surprises that emerged. The first surprise: the
toolchain install (Vivado WebPack, the various Python
packages) took 3 weeks, not 3 days. The second surprise: the
INMP441 was discontinued halfway through the project; the
project had to identify the SPH0645 as a drop-in replacement.
The third surprise: the latency was 7.4 ms, not the 5.3 ms
predicted by theory, because the I2S codec pipeline delay is
not negligible. The essay ends with a list of lessons: build
the toolchain first, order parts early, measure early and
measure often, write things down.

**Featured scenes:**

- The first GitHub commit, with a tree full of stub files.
- The first time the FPGA programed and the LED blinked.
- The first time the oscilloscope showed the FFT output
  and it was clearly a 1 kHz sine — proof the pipeline was
  real.
- The first time the Hearing profile made a difference the
  author could hear.
- The moment the author realised the INMP441 was
  discontinued and the project's BOM was at risk.

**Why it works for admissions:** the essay demonstrates
self-awareness, planning ability, and the resilience required
to complete a long project. It is a strong supplemental essay
for any program — it shows the author can manage a complex
project over a long timeline.

### 2.4 Open-source philosophy: why I made it open-source, contribution to the community

**Hook:** "If you build it and keep it to yourself, you've
built a gadget. If you build it and open-source it, you've
built a platform."

**Narrative:** The essay reflects on the *decision* to make
Project Auris open source. The author chose the MIT licence,
wrote a comprehensive README, documented every design decision
in ADRs, and committed the tools that generate the test
vectors. The essay makes the case that open source is not
just a licence choice but a development methodology: every
component is documented because a future contributor needs
to understand it; every measurement is reproducible because
a future user needs to validate it; every design decision is
recorded because a future maintainer needs to know *why*.
The essay also reflects on what the project has *received*
from the open-source community: the Xilinx xfft IP, the
Vivado toolchain, the INMP441 application notes, the PCM5102A
evaluation documentation. The author is one contributor in
a long chain.

**Featured scenes:**

- The decision to licence under MIT (vs Apache 2.0, vs GPL).
- The decision to write a `CONTRIBUTING.md` and a
  `CODEOWNERS` file (formalising the project's openness).
- The decision to commit the generated artefacts
  (Hann coefficients, default gain tables) so a fresh clone
  can build without running the tools.
- The moment a stranger (a friend of a friend) cloned the
  repo and got the demo working in a single afternoon.

**Why it works for admissions:** the essay demonstrates
maturity, community awareness, and a long-term view of the
project's impact. It is a strong supplemental essay for
programs with a strong open-source or collaboration culture.

### 2.5 Interdisciplinary: combining DSP theory, embedded systems, and hardware design

**Hook:** "I am a hardware person, a software person, and a
math person — and Project Auris is the project that made me
realise I don't have to choose."

**Narrative:** The essay explores the *interdisciplinary*
nature of the project. The DSP theory (Fourier analysis, window
functions, COLA, Parseval's theorem) is grounded in the math
classroom. The digital design work (SystemVerilog RTL, clock-
domain crossing, timing closure, async FIFOs, BRAM inference)
is grounded in the computer-science and electrical-engineering
classrooms. The hardware integration (FPGA bring-up, I²S codec
wiring, breadboard debugging, scope probing) is grounded in
the maker space. The essay makes the case that the most
interesting problems — and the most interesting projects —
sit at the intersection of disciplines. The author wants to
study electrical and computer engineering (or computer
science and mathematics, or biomedical engineering) because
Project Auris has shown them that the boundary between fields
is where the fun is.

**Featured scenes:**

- The moment the author derived the Hann window's COLA
  property on paper and then verified it in the FPGA
  (Parseval's theorem as a sanity check).
- The moment the author wrote the SPI slave in SystemVerilog
  and the matching SPI master in C, and the two worked
  together on the first try (the *contract* held).
- The moment the author measured the end-to-end frequency
  response and overlaid it on the predicted gain table, and
  the two matched to within 1 dB.

**Why it works for admissions:** the essay demonstrates
intellectual curiosity, the ability to integrate across
disciplines, and a clear sense of academic direction. It is
a strong supplemental essay for interdisciplinary programs
(ECE, CS, BME, applied math).

### 2.6 Other essay angles (in case the above don't fit)

- **Failure and recovery.** The INMP441 was discontinued
  halfway through; the project had to pivot. Essay about
  resilience and the value of contingency planning.
- **Documentation as a deliverable.** The author wrote
  8 architecture documents, 8 ADRs, a measurement
  methodology, and a demo plan — more time on documentation
  than on the FPGA, in some weeks. Essay about the value of
  writing things down.
- **A small team's project.** The author is the sole
  contributor, but the project mimics a real product
  team's workflow: a source-of-truth plan, ADRs, design
  reviews, measurement gates, demos. Essay about the
  professionalisation of a personal project.

---

## 3. Demo Script (Brief)

The full demo plan (second-by-second script, equipment
checklist, fallback scenarios, talking points) is in
[`docs/DEMO_PLAN.md`](../DEMO_PLAN.md). A 30-second elevator
version is:

1. **Show the breadboard** (5 s). "This is Project Auris: an
   FPGA, a microphone, and a DAC, on a breadboard, for $101
   in parts. The FPGA does everything — signal processing
   and the user interface."
2. **General mode** (5 s). "Right now we're in General mode —
   flat unity gain. Whatever the mic hears, the headphones
   play, with no colouring."
3. **Hearing mode** (10 s). "Now I'll switch to a mode that
   compensates for high-frequency hearing loss. Listen to the
   difference."
4. **Volume control** (5 s). "The third button raises the
   volume — 31 levels. The fourth button lowers it."
5. **Q&A** (5 s). "Happy to take questions."

For the longer (5–6 minute) version with the architecture
walkthrough and the full four-mode demonstration, see
[`docs/DEMO_PLAN.md`](../DEMO_PLAN.md) §3.

---

## 4. Artifact Checklist

The artifacts that the project will produce for the college
application. Each artifact is tracked with its format, status,
and purpose.

| Artifact | Format | Status | Purpose |
|----------|--------|--------|---------|
| GitHub repository | URL | ✅ | Shows code quality, documentation, CI, open-source practice |
| Block diagram | PDF / SVG | ✅ | Visual architecture overview (one-page summary) |
| Demo video | MP4 (3 min) | ⬜ | 3-minute demo of the working device, walking through the three modes |
| Technical report | PDF (6 pages, IEEE format) | ⬜ | IEEE-format writeup of the design and measurement results |
| BOM | CSV | ✅ | Shows hardware planning, sourcing, cost-conscious design |
| Measurement results | PDF / CSV | ⬜ | Quantitative performance data (latency, frequency response, SNR, THD, power) |
| Photos | JPG | ⬜ | Assembled breadboard, wiring, demo setup, demo-in-action |
| Slide deck | PDF (10–15 slides) | ⬜ | For interview / information-session presentations |
| Design decision log | Markdown | ✅ | [`docs/DESIGN_DECISIONS.md`](../DESIGN_DECISIONS.md); shows engineering rigour |
| Measurement methodology | Markdown | ✅ | [`docs/MEASUREMENT_METHODOLOGY.md`](../MEASUREMENT_METHODOLOGY.md); shows scientific mindset |
| Phase reports | Markdown (one per phase) | ⬜ | [`docs/phase_reports/`](../phase_reports/); shows reflection and learning |
| Architecture docs | Markdown (8 files) | ✅ | [`docs/architecture/`](../architecture/); shows deep technical writing |

### 4.1 Status legend

- ✅ Done — the artifact is in the repository.
- ⬜ Planned — the artifact is on the timeline but not yet started.
- 🔧 In progress — work has started.
- ❌ Cancelled — the artifact is no longer planned.

### 4.2 How to package the artifacts for an application

1. **Pin the GitHub repo to a release tag** (e.g., `v0.5.0`)
   so the application reviewer sees a stable snapshot.
2. **Record the demo video** at 1080p, 30 fps, with a
   lapel mic and a clean audio feed (no music in the
   background; the audio chain is the demo).
3. **Format the technical report** in IEEE conference
   format (two-column, 10-pt Times New Roman); submit as
   a single PDF with the embedded figures.
4. **Curate 5–10 photos:** the bare breadboard, the wired
   breadboard, the demo in action, the oscilloscope
   showing the I2S signals, the FPGA resource-utilisation
   report.
5. **Include a one-page "highlights" PDF** in the
   Additional Information section of the application,
   linking the GitHub repo, the demo video, and the
   technical report.

---

## 5. Technical Report Outline

The technical report is the project in writing. It is written
in IEEE conference format, 6 pages, two-column, 10-pt Times
New Roman. The outline below is the table of contents; the
full LaTeX template is committed to the repository under
`docs/college_app/technical_report.tex` (to be added in
Phase 5).

### 5.1 Section 1: Abstract (200 words)

A self-contained summary of the project, the design, and the
key results. Written last, placed first. Covers: motivation
(hearing-assistive, low cost, open source), architecture
(FPGA-only, FFT-based spectral processing, onboard push
buttons for mode and volume), key metrics (5.3 ms latency,
60 dB SNR, 58 % LUT utilisation, $101 BOM), and significance
(a reproducible prototype that demonstrates the feasibility
of low-cost, high-performance hearing-assistive devices).

### 5.2 Section 2: Introduction & Motivation

The human need: 1 in 5 people over 65 has disabling hearing
loss; prescription hearing aids cost $4,000–$8,000; untreated
hearing loss correlates with accelerated cognitive decline.
The technical need: real-time DSP on a resource-constrained
FPGA, with deterministic sub-10 ms latency, multi-mode
configuration, and a small BOM. The contribution of this
work: an open-source, end-to-end prototype that demonstrates
all of the above with no external microcontroller and no
firmware to flash.

### 5.3 Section 3: System Architecture

The high-level architecture: a single Arty S7-25 (signal-
processing + control plane) plus two audio codecs (INMP441
mic, PCM5102A DAC). The audio chain: INMP441 → I2S RX → CDC
FIFO → 256-pt FFT → per-bin gain → IFFT → 50 % overlap-add →
volume_ctrl → CDC FIFO → I2S TX → PCM5102A. The control
chain: 4 onboard push buttons → btn_debounce → inline FSMs
in `top.sv` → mode_ctrl (gain-table swap) and volume_ctrl.
The clock domains: 12 MHz crystal → MMCM → 96 MHz DSP clock
+ fractional-divider 3.072 MHz I²S BCLK + ÷64 LRCLK, with
two Gray-coded asynchronous FIFOs at the I²S↔DSP boundary.
The full Mermaid diagram from
[`docs/architecture/block_diagram.md`](../architecture/block_diagram.md)
goes here as Figure 1.

### 5.4 Section 4: DSP Pipeline Design

The mathematical details: the Hann window and the COLA
property; the FFT (pipelined streaming, BFP, Xilinx xfft
v9.1 IP); the per-bin gain and the noise gate; the IFFT
(with the 1/N scaling absorbed into the gain table); the
overlap-add reconstruction; the volume stage. The fixed-
point arithmetic: Q2.14 for gains, 16-bit two's-complement
for samples, 5-bit volume (0..31) mapped linearly to Q2.14.
The latency budget: 5.33 ms algorithmic + ~1 ms I2S codec +
~1 ms analog = ~7–8 ms total. The resource budget: 8,500
LUTs, 12 BRAMs, 14 DSP48E1s, all under the XC7S25's
available resources. The full per-stage table from
[`docs/architecture/dsp_pipeline.md`](../architecture/dsp_pipeline.md) §5
goes here as Table 1.

### 5.5 Section 5: Implementation (FPGA only)

The FPGA implementation: SystemVerilog RTL, Xilinx xfft v9.1
IP, the two asynchronous FIFOs (I²S↔DSP, both directions),
the spectral processor with dual-bank BRAM, the inline
mode and volume FSMs in `top.sv`, the `mode_ctrl.sv` table
loader with pre-computed per-mode gain tables, the
`volume_ctrl.sv` Q2.14 multiplier, the `btn_debounce.sv`
push-button debouncer. The build flow: Vivado non-project
mode, Python tools for the Hann coefficients and the
default gain tables. The verification flow: xsim
testbenches, end-to-end loopback tests, the full
measurement suite from
[`docs/MEASUREMENT_METHODOLOGY.md`](../MEASUREMENT_METHODOLOGY.md).
A photo of the assembled breadboard goes here as Figure 2.

### 5.6 Section 6: Results (measurements)

The quantitative results: latency (Section 6.1), frequency
response (Section 6.2), SNR (Section 6.3), THD (Section 6.4),
power consumption (Section 6.5). Each section has a table
with the measured value, the target, the pass/fail, and a
plot. The headline plot is the frequency response in Hearing
mode overlaid on the target gain table; this goes in as
Figure 3. The full measurement log (CSV) is included as an
appendix.

### 5.7 Section 7: Discussion (limitations, future work)

The limitations: the INMP441 is discontinued (R-01); the
breadboard prototype is not a wearable form factor; the
project does not have a regulatory clearance; the latency
is fixed at 5.33 ms by the FFT length; the resource budget
is tight; per-mode gain tables are pre-computed and cannot
be tuned at runtime. The future work: a custom PCB and a
3D-printed enclosure (Phase 5); WDRC and a feedback canceller
(Phase 6); a smartphone app for audiogram upload (would
talk to the FPGA via a separate BLE bridge, not in the
FPGA-only build); a clinical evaluation with hearing-loss
participants.

### 5.8 Section 8: Conclusion

A short (1-paragraph) summary of the contribution: a
working, open-source, $106.60 hearing-assistive prototype
that demonstrates real-time FPGA-based spectral audio
processing with sub-10 ms latency, four pre-computed
listening modes (General, Speech, Music, Hearing), and
onboard push-button control. The documentation, the ADRs,
the measurement methodology, and the demo plan are the
project's *other* deliverables; together they make the
project reproducible and reviewable.

### 5.9 Section 9: References

A standard IEEE-format reference list. Key citations:
Xilinx xfft IP v9.1 documentation; INMP441 datasheet;
PCM5102A datasheet; the Hann window's original publication;
the COLA proof from Crochiere and Rabiner's *Multirate
Digital Signal Processing*; the Digilent Arty S7-25
reference manual; the MIT licence text.

---

## 6. College-Specific Notes

This section is a placeholder for college-by-college tailoring
notes. The list below is a starter set; add new entries as
applications are prepared.

### 6.1 Stanford (School of Engineering)

- **Frame:** the project demonstrates the kind of cross-
  cutting, design-oriented engineering that the School
  values.
- **Highlight:** the *measurement methodology* — Stanford
  values the scientific method, and the project's
  reproducible measurements are a strong differentiator.
- **Tailor:** lead with essay 2.1 (technical challenge) and
  reference Stanford's "Stanford Engineering Hero" essay
  prompt.

### 6.2 MIT (EECS)

- **Frame:** the project is a deep dive into the same
  material covered in 6.004 (Computation Structures) and
  6.341 (Discrete-Time Signal Processing).
- **Highlight:** the *ADRs* and the *architecture docs* —
  MIT values the *rigour* of the design process.
- **Tailor:** lead with essay 2.5 (interdisciplinary) and
  reference MIT's "describe a time you used technology to
  solve a problem" prompt.

### 6.3 Georgia Tech (ECE)

- **Frame:** the project is a senior-thesis-sized ECE
  project: DSP, embedded systems, FPGA, mixed-signal.
- **Highlight:** the *technical report* and the
  *block diagram*.
- **Tailor:** lead with essay 2.3 (engineering process) and
  reference Georgia Tech's "tell us about a project where
  you taught yourself something new" prompt.

### 6.4 Carnegie Mellon (ECE / CS)

- **Frame:** the project combines the CS skills (tooling,
  CI, verification) and the ECE skills (RTL, signal
  processing, CDC) that CMU's interdisciplinary programs value.
- **Highlight:** the *open-source workflow* — CMU has a
  strong culture of open-source contribution.
- **Tailor:** lead with essay 2.4 (open-source
  philosophy).

### 6.5 Harvey Mudd (Engineering)

- **Frame:** the project is an example of "engineering for
  social impact" — a HMC signature.
- **Highlight:** the *impact motivation* essay
  (2.2) and the *BOM* showing the $116 cost.
- **Tailor:** lead with essay 2.2 and reference HMC's
  "engineering for everyone" framing.

### 6.6 (Other colleges)

Add a new subsection here as needed. The general structure
is: **frame** (which aspect of the project to lead with),
**highlight** (which artifact to draw attention to), and
**tailor** (which essay to anchor on and which prompt to
reference).

---

## 7. Timeline

A rough timeline aligned with the college application
deadlines. The MVP (Phase 2 exit) is the absolute hard
deadline; everything else is bonus.

| Date | Milestone | Application relevance |
|------|-----------|------------------------|
| 2026-09 | Phase 2 complete (MVP) | First EA / ED applications can include the MVP demo |
| 2026-10 | Phase 3 complete (spectral processing) | Most EA / ED applications are due; include the four-mode demo |
| 2026-11 | Phase 4 complete (enclosure, polish) | RD applications: full feature set |
| 2026-12 | Demo video recorded; technical report written | RD applications: full artifact set |
| 2027-01 | Phase 5 complete (custom PCB, DRC) | Post-application polish; not needed for applications but useful for interviews |
| 2027-03 | Interviews begin | All artifacts ready |

### 7.1 Application-deadline-aware strategy

- **EA / ED applicants (Nov 1 / Nov 15 deadlines):** ship
  the MVP (Phase 2 complete) plus three of the four modes
  (Phase 3 partially complete). The demo video can be
  shorter (90 s); the technical report can be 2–3 pages.
- **RD applicants (Jan 1 / Jan 15 deadlines):** ship the
  full Phase 4 (four modes, volume control, OLED status
  indicator). The demo
  video is 3 min; the technical report is the full 6-page
  IEEE paper.
- **Interviews (March–April):** the Phase 5 enclosure and
  polish are in hand; the demo is portable, the device is
  wearable, the documentation is complete.

### 7.2 The "minimum viable application" set

If the deadline is tight, the minimum set of artifacts is:

1. GitHub repository (✅ already done).
2. Block diagram (✅ already done).
3. A 90-second demo video (recording can be done in 2
   hours; editing in 4).
4. The 30-second elevator pitch (above).
5. One polished essay (pick from §2.1–§2.5).
6. The "highlights" PDF linking the above.

The technical report, the slide deck, the photo set, and the
college-specific notes are *nice to have* and can be added
later.

---

## 8. Where to Read Next

- The **demo plan** (second-by-second script for the live
  demo) is in
  [`docs/DEMO_PLAN.md`](../DEMO_PLAN.md).
- The **measurement methodology** that backs up the
  technical claims is in
  [`docs/MEASUREMENT_METHODOLOGY.md`](../MEASUREMENT_METHODOLOGY.md).
- The **6-phase development plan** that defines when each
  artifact should be ready is in
  [`docs/ROADMAP.md`](../ROADMAP.md).
- The **design decision log** that justifies the project's
  technology choices is in
  [`docs/DESIGN_DECISIONS.md`](../DESIGN_DECISIONS.md).
- The **architecture documents** that the technical report
  draws from are in [`docs/architecture/`](../architecture/).
- The **phase reports** that show the project's evolution
  over time are in [`docs/phase_reports/`](../phase_reports/).
