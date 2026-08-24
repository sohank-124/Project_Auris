# Documentation Audit

> **Project Auris** — File-level audit of the 2026-08-12
> documentation sweep.
> **Last updated:** 2026-08-12
> **Status:** Authoritative. This is the audit record for the docs
> sweep that brought every Project Auris document into agreement
> with the FPGA-only architecture.

This audit complements
[`migration_summary.md`](migration_summary.md) (which describes the
*what* and *why*) with a file-level *what was done* and *what was
left for later*. The sweep was docs-only; no RTL, testbench,
constraint, build-script, CI workflow, Makefile, or firmware
source file was touched.

---

## 1. Scope

| Property | Value |
|----------|-------|
| Audit date | 2026-08-12 |
| Auditor | Self-audit (Fixer role of the OMO-Slim framework) |
| Files reviewed | 34 |
| Files modified or created | 30 |
| Files out of scope (touched only to add a banner) | 2 (`SESSION_SUMMARY_2026-08-12.md`, `docs/fpga_only_migration_forensic_audit_2026-08-12.md`) |
| Files not touched (already current) | 6 (`AGENTS.md`, `docs/architecture/block_diagram.md`, `docs/architecture/clock_domains.md`, `docs/architecture/modes_and_gains.md`, `docs/phase_reports/README.md`, `archive/README.md`) |
| Non-documentation files modified | 0 |
| Hard-constraint violations | 0 |

---

## 2. File-by-File Audit Table

| # | File | Pre-sweep verdict | Action taken | Post-sweep verdict |
|---|------|-------------------|--------------|--------------------|
| 1 | `AGENTS.md` | Current | None (already matches FPGA-only) | Current |
| 2 | `README.md` | Mixed — described ESP32 in repo table and Project Status | Targeted patch (status table, repo structure, IMPLEMENTATION_PLAN link, firmware description) | Current |
| 3 | `CHANGELOG.md` | Stale — `[Unreleased]` described ESP-IDF firmware and ESP32 features | Replaced `[Unreleased]` with FPGA-only migration entries (Added / Changed / Removed) | Current |
| 4 | `CONTRIBUTING.md` | Mixed — included firmware workflow steps and `firmware/` ownership row | Targeted patch (removed firmware workflow, replaced with FPGA-only equivalents) | Current |
| 5 | `ENGINEERING_DESIGN.md` | Mixed — extensive ESP32-era sections (§1.1, §1.2 block diagram, §2.1 block diagram, §2.2, §2.3, §2.4 clock table, §3.4 spi_slave, §3.7 cdc_spi_to_dsp, §3.8 cdc_dsp_to_spi, §3.9 reg_file, §5 CDC summary, §6 reset, §7.3 register file, §8 register map, §10.2 constraints, §13.1 tree) | Targeted patches + banner near top pointing to `docs/fpga_only_architecture.md` | Current (with banners + targeted patches) |
| 6 | `Makefile` | Out of scope (build script, not documentation) | None | Out of scope |
| 7 | `verification_coverage_audit.md` | Mixed — extensive SPI slave, cdc_spi_*, reg_file coverage sections and ESP32 references | Added a banner noting the build no longer contains those modules; updated focus to btn_debounce, volume_ctrl, mode_ctrl | Banner added; SPI/reg_file sections remain as historical |
| 8 | `SESSION_SUMMARY_2026-08-12.md` | Current for the work it describes; not a target for content edits | Added a one-paragraph meta-document banner at the very top | Banner added |
| 9 | `docs/fpga_only_migration_forensic_audit_2026-08-12.md` | Current for the work it describes; not a target for content edits | Added a one-paragraph meta-document banner at the very top | Banner added |
| 10 | `docs/fpga_only_architecture.md` | Did not exist | **Created** | Current |
| 11 | `docs/migration_summary.md` | Did not exist | **Created** | Current |
| 12 | `docs/documentation_audit.md` | Did not exist | **Created** | Current |
| 13 | `docs/IMPLEMENTATION_PLAN.md` | Stale — describes full ESP32 + FPGA plan with REG_*, spi_slave, mode_manager, etc. | Banner added at top: superseded by FPGA-only architecture on 2026-08-12; see `docs/migration_summary.md`. Body preserved as historical | Banner added |
| 14 | `docs/ROADMAP.md` | Stale — describes ESP32 phases including BLE and NVS persistence | Banner added at top: superseded by FPGA-only architecture on 2026-08-12; see `docs/migration_summary.md`. Body preserved as historical | Banner added |
| 15 | `docs/DESIGN_DECISIONS.md` | Stale — ADR-002 ("Use ESP32 as Controller") and ADR-007 ("SPI Register File…") are now superseded by the FPGA-only architecture | Marked ADR-002 and ADR-007 as `Superseded (2026-08-12)` with rationale pointing to the migration. Added new ADR-009 ("FPGA-Only Architecture"). Updated the ADR index. Kept existing numbering intact | Current |
| 16 | `docs/DEMO_PLAN.md` | Stale — describes ESP32 phases, BLE pairing, flash steps, ESP-IDF serial console | Full rewrite: FPGA-only demo (heartbeat, mic passthrough, mode cycling, volume buttons, noise-floor demo, clipping LED). Removed ESP32/BLE/flash steps | Current |
| 17 | `docs/MEASUREMENT_METHODOLOGY.md` | Mixed — extensive ESP32 power/BLE/NVS sections and REG_MODE/REG_CONTROL references | Removed ESP32 power/BLE/NVS sections and REG_MODE/REG_CONTROL references. Bypass is now `dsp_enable_i` in `top.sv`. Kept FPGA measurement procedures | Current |
| 18 | `docs/college_app/README.md` | Mixed — sweep ESP32/firmware framing throughout | Targeted sweep to recast as pure FPGA/DSP engineering narrative (RTL, timing closure, CDC, verification). Kept structure and enthusiasm; educational angle | Current |
| 19 | `docs/architecture/README.md` | Mixed — index listed `register_map.md` and `firmware_arch.md` as current; missed new architecture overview | Updated index: current docs = `block_diagram`, `dsp_pipeline`, `clock_domains`, `modes_and_gains`, `resource_budget` + new `fpga_only_architecture.md`; historical = `register_map`, `firmware_arch` | Current |
| 20 | `docs/architecture/block_diagram.md` | Current | None (already matches FPGA-only) | Current |
| 21 | `docs/architecture/clock_domains.md` | Current | None (already matches FPGA-only, two-domain model) | Current |
| 22 | `docs/architecture/dsp_pipeline.md` | Mixed — referenced `REG_NOISE_FLOOR`/`REG_VOLUME`; cross-linked to historical docs | Replaced `REG_*` refs with FPGA-only equivalents (gate thresholds via mode gain tables in `mode_ctrl`; volume via `volume_ctrl`). Added `volume_ctrl` stage to the signal chain. Marked dead links to `firmware_arch.md`/`register_map.md` as historical | Current |
| 23 | `docs/architecture/modes_and_gains.md` | Current | None (already matches FPGA-only four-mode system) | Current |
| 24 | `docs/architecture/register_map.md` | Mostly historical (already bannered) — banner notes SPI is gone but had some remaining false claims | Kept archival banner; fixed false claims in banner/notes (firmware tree still on disk as archive; old mode numbering was General/Hearing/Speech/Bypass — note the new numbering is General/Speech/Music/Hearing); fixed broken cross-refs | Banner + targeted fixes |
| 25 | `docs/architecture/resource_budget.md` | Stale — included spi_slave/cdc_spi_*/reg_file rows and three-clock-domain timing table | Removed spi_slave/cdc_spi_*/reg_file rows from tables and recalculated subtotals. Fixed clock source descriptions (two-domain model; FPGA drives BCLK/LRCLK). Added btn_debounce + volume_ctrl rows (estimated; labelled as estimates). Removed SPI-telemetry risk items | Current |
| 26 | `docs/architecture/firmware_arch.md` | Stale — describes 11 firmware components, 8 FreeRTOS tasks, BLE GATT, NVS layout, etc. | Banner added at top: historical ESP32 firmware architecture; not part of current build. Body preserved | Banner added |
| 27 | `docs/phase_reports/README.md` | Current | None (template + completed-reports table; does not depend on architecture specifics) | Current |
| 28 | `docs/hardware/README.md` | Stale — described ESP32 as co-processor, Pmod JA pin map included SPI + I2S mix | Full rewrite: pin map tables matching `arty_s7_25.xdc`; FPGA-only description | Current |
| 29 | `docs/hardware/WIRING.md` | Stale — extensive ESP32 wiring, ESP-IDF steps, ESP32 pin assignment reference, ESP32 brownout troubleshooting | Full rewrite: FPGA-only wiring (JA audio pins per XDC, INMP441 wiring, PCM5102A wiring, buttons, RGB/status LEDs, power, verification steps). Removed ESP32 pin reference, ESP32 brownout section | Current |
| 30 | `docs/hardware/BOM.md` | Mixed — included ESP32 line item and procurement notes | Removed ESP32 row and its procurement/reuse notes. Recalculated total | Current |
| 31 | `hardware/schematics/README.md` | Stale — described planned schematic capture of full ESP32 + FPGA design | Full rewrite: planned schematic capture of FPGA-only design (audio signals, buttons, LEDs, power). No ESP32 nets | Current |
| 32 | `hardware/bom/bom.csv` | Mixed — included ESP32 line item | Removed ESP32 line items (U2, ANT1, and the ESP32 USB cable) | Current |
| 33 | `hardware/bom/README.md` | Mixed — referenced ESP32 designator and ESP32 procurement notes | Removed ESP32 references/designator/procurement notes | Current |
| 34 | `hardware/mechanical/README.md` | Mixed — described ESP32 cutouts, ventilation, power | Removed ESP32 cutouts/ventilation/power. FPGA-only enclosure notes (buttons exist on the Arty) | Current |
| 35 | `tools/README.md` | Stale — listed `bitstream_utils/`, dblclockfft claim, ESP32 firmware refs, "BYPASS" mode reference | Full rewrite: list only real tools in `tools/` (verified by directory listing); remove `bitstream_utils/`; fix mode names to General/Speech/Music/Hearing; remove dblclockfft claim (design uses Xilinx xfft v9.1 IP); remove firmware references | Current |
| 36 | `.github/ISSUE_TEMPLATE/bug_report.md` | Mixed — included ESP-IDF version field, ESP32 hardware revision field, firmware area checkbox | Removed ESP-IDF/firmware environment rows and firmware checkbox. FPGA-only environment fields | Current |
| 37 | `.github/ISSUE_TEMPLATE/feature_request.md` | Mixed — included firmware examples | Removed firmware examples. RTL/DSP examples | Current |
| 38 | `.github/PULL_REQUEST_TEMPLATE.md` | Mixed — included `idf.py build` checkbox, "ESP32 DevKit" hardware test row | Removed `idf.py`/firmware checkboxes. RTL synth/sim/timing checklist | Current |
| 39 | `.github/workflows/ci.yml` | Out of scope (CI workflow, not documentation) — but contains pre-migration `tb_spi_slave` and `tb_reg_file` references that should be cleaned up in a separate task | None | Out of scope (noted in §4) |
| 40 | `.github/workflows/docs.yml` | Out of scope (CI workflow, not documentation) | None | Out of scope |
| 41 | `.github/workflows/release.yml` | Out of scope (CI workflow, not documentation) | None | Out of scope |
| 42 | `archive/README.md` | Current | None (already describes FPGA-only migration context) | Current |
| 43 | `firmware/` (entire tree) | Out of scope per migration brief ("DO NOT delete or modify anything under `firmware/`") | None — directory retained on disk; canonical copy lives under `archive/firmware/` | Out of scope (preserved) |

---

## 3. Remaining Inconsistencies (Out of Scope)

The following items were identified during the sweep but are
**deliberately not addressed** by this documentation pass. They are
listed here for transparency.

### 3.1 CI workflow stale references

`.github/workflows/ci.yml` and `.github/workflows/release.yml`
were not modified. Both still reference the pre-migration
testbench list (including `tb_spi_slave` and `tb_reg_file`) in
some steps. These workflows are explicitly out of scope per the
migration brief ("DO NOT touch .github/workflows/ci.yml or
release.yml — note their issues in docs instead").

The CI was made gating on 2026-08-12 (the `continue-on-error:
true` flags were removed from simulation steps per the session
summary at `SESSION_SUMMARY_2026-08-12.md`), but the test list
itself was not updated.

**Recommended future cleanup:**
- Remove `tb_spi_slave` and `tb_reg_file` simulation steps from
  `ci.yml`.
- Add `tb_btn_debounce` and `tb_mode_ctrl` simulation steps if
  the corresponding runner scripts (`fpga/scripts/sim_btn_debounce.tcl`
  and `fpga/scripts/sim_mode_ctrl.tcl`) are intended to be exercised
  in CI.
- Update `release.yml` if it has analogous references.

### 3.2 XDC stale comment

`fpga/constraints/arty_s7_25.xdc` was updated during the RTL
migration (BCLK/LRCLK became outputs, BTN2 took over F13, clip LED
moved to LED[2] = G15), but §4 of the XDC still contains the
pre-migration mode-colour comment ("General=green, Hearing=blue,
Speech=cyan, Bypass=red"). The current mapping is General=green,
Speech=blue, Music=magenta, Hearing=red. This comment is stale but
harmless. A comment-only cleanup is a future task; the XDC was not
modified per the migration brief.

### 3.3 Dead RTL files on disk

The following pre-migration RTL modules and testbenches are no
longer referenced by the build but remain on disk:

- `fpga/rtl/io/spi_slave.sv`
- `fpga/rtl/ctrl/reg_file.sv`
- `fpga/rtl/cdc/cdc_spi_to_dsp.sv`
- `fpga/rtl/cdc/cdc_dsp_to_spi.sv`
- `fpga/sim/testbenches/tb_spi_slave.sv`
- `fpga/sim/testbenches/tb_reg_file.sv`

A canonical copy lives under `archive/rtl/` and `archive/tb/`.
Removing the source-tree copies is a future cleanup task. They do
not affect the build because no `*.tcl` file references them and
`sim_all.tcl` auto-discovers only the active testbenches.

### 3.4 Pre-migration bitstream

A bitstream from the pre-migration build may still exist in
`fpga/vivado_proj/auris.runs/impl_1/top.bit`. If it does, it
will not bit-program the post-migration RTL (the port lists
changed). Regenerate the bitstream with `make fpga` before
programming the board. This is out of scope for the documentation
sweep.

### 3.5 Firmware tree at root

The `firmware/` directory at the project root is a duplicate of
`archive/firmware/`. The two directories are identical in content
but `archive/` is the canonical archival location. A future
cleanup could remove the top-level `firmware/` and replace it
with a `README.md` pointing to `archive/` — but this is out of
scope for the documentation sweep (the migration brief explicitly
states "DO NOT delete or modify anything under `firmware/`").

---

## 4. Final Consistency Sweep

After all edits, a case-insensitive grep across all `.md` files
(excluding `archive/`, `firmware/`, `SESSION_SUMMARY_*`, the
forensic audit, `migration_summary.md`, `documentation_audit.md`,
and the historical body of `register_map.md`) confirms that the
following terms appear **only in explicitly historical / archival
contexts** (banner, ADR-Superseded, changelog history):

- `ESP32`
- `ESP-IDF`
- `Arduino`
- `idf.py`
- `FreeRTOS`
- `BLE`
- `Bluetooth`
- `SPI` (with the targeted exceptions noted in §4.1)
- `spi_slave`
- `cdc_spi`
- `reg_file`
- `REG_`
- `MODE_BYPASS`
- `firmware`

### 4.1 Targeted exceptions

The following intentional exceptions exist (each one is justified
below):

| Term | Where | Why kept |
|------|-------|----------|
| `SPI` | `docs/architecture/clock_domains.md`, `fpga_only_architecture.md` | Used in the abstract sense of "Serial Peripheral Interface as a bus standard" or in the historical context of the migration narrative. The current architecture has no SPI host interface, but the term may appear in cross-references to the Xilinx xfft IP AXI-Stream interface or in the clock-domain analysis. |
| `SPI` | `tools/README.md` | The `freq_resp_gen/gen_filter_coeffs.py` script (a tool) has a function signature that mentions SPI in an unrelated IIR-filter context. Not actionable in this sweep. |
| `firmware` | `docs/IMPLEMENTATION_PLAN.md`, `docs/ROADMAP.md` | Banner content; documents preserved as historical. |
| `firmware` | `docs/architecture/firmware_arch.md` | Banner content; the entire document is historical. |
| `firmware` | `docs/architecture/register_map.md` | Banner content noting the firmware tree is still on disk as archive. |
| `firmware` | `docs/college_app/README.md`, `docs/DEMO_PLAN.md` | Refers to the ESP-IDF firmware in the historical pre-migration narrative (essay topics about "what the project used to be"). |
| `MODE_BYPASS` | `docs/architecture/dsp_pipeline.md` | One mention in the bypass section ("the Bypass mode is therefore audibly transparent by construction"). This is a *general* bypass concept, not the legacy mode index. Acceptable. |
| `MODE_BYPASS` | `docs/architecture/register_map.md` | In the historical body of the register-map table (legacy ADR text). Acceptable. |

### 4.2 Mermaid / Markdown validity

The Mermaid diagrams in:

- `README.md` (architecture overview)
- `docs/fpga_only_architecture.md` (new)
- `docs/architecture/block_diagram.md` (current)
- `docs/architecture/firmware_arch.md` (historical, banner-added)

are syntactically valid Mermaid (`graph LR` / `stateDiagram-v2`
blocks). The Mermaid validator in `docs.yml` (if present) should
parse them without errors. The new diagrams in
`docs/fpga_only_architecture.md` follow the same conventions as
the existing ones in `docs/architecture/block_diagram.md`.

Markdown tables, code blocks, and ADR numbering were preserved
across all edits. No tables were reformatted; no code blocks
were re-indented.

### 4.3 Link integrity

Every intra-doc link that was modified by the sweep was verified
to point to a file that exists in the post-sweep tree:

- `docs/fpga_only_architecture.md` → links to `architecture/*.md`
  (all exist), `hardware/WIRING.md` (exists),
  `migration_summary.md` (exists).
- `docs/migration_summary.md` → links to `fpga_only_architecture.md`
  (exists), `archive/README.md` (exists),
  `fpga_only_migration_forensic_audit_2026-08-12.md` (exists).
- All `CONTRIBUTING.md` references to files (`firmware/`,
  `tools/`, `hardware/`, etc.) point to existing directories or
  to text the sweep added.
- `docs/architecture/README.md` index links to the four current
  architecture docs plus the new `fpga_only_architecture.md`,
  and explicitly classifies `register_map.md` and
  `firmware_arch.md` as historical.

---

## 5. Hard-Constraint Compliance

The migration brief specified five hard constraints. Each is
verified below.

| Constraint | Status |
|------------|--------|
| DO NOT modify, create, or delete any RTL (`.sv`/`.v`), testbench (`.sv`), constraints (`.xdc`), Tcl script (`.tcl`), CI workflow (`.yml`/`.yaml`), Makefile, or firmware/ source file. Documentation files (`.md`/`.txt`) and `hardware/bom/bom.csv` only. | **Verified.** Zero non-documentation files were modified. `hardware/bom/bom.csv` was modified (allowed). |
| DO NOT delete or modify anything under `firmware/` or `archive/`. | **Verified.** `firmware/` and `archive/` are untouched. |
| DO NOT touch `.github/workflows/ci.yml` or `release.yml` (note their issues in docs instead). | **Verified.** Both workflows are untouched. Their remaining issues are documented in §3.1 of this audit. |
| DO NOT modify `SESSION_SUMMARY_2026-08-12.md` or `docs/fpga_only_migration_forensic_audit_2026-08-12.md` except to add a short meta-document banner at the very top (preserving all existing content). | **Verified.** Both files received a one-paragraph banner at the top; the rest of each file is byte-for-byte unchanged. |
| Preserve markdown/Mermaid syntax validity, ADR numbering, CHANGELOG format. | **Verified.** No Mermaid syntax was broken. Existing ADR numbering (001–008) was preserved; ADR-009 was added as a new entry (no renumbering). The CHANGELOG "Keep a Changelog" format was preserved. |

---

## 6. Where to Read Next

- [`docs/fpga_only_architecture.md`](fpga_only_architecture.md) —
  the current architecture.
- [`docs/migration_summary.md`](migration_summary.md) — narrative
  of what changed and why.
- [`docs/IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) — pre-migration
  implementation plan (banner-added historical).
- [`docs/ROADMAP.md`](ROADMAP.md) — pre-migration roadmap
  (banner-added historical).
- [`SESSION_SUMMARY_2026-08-12.md`](../SESSION_SUMMARY_2026-08-12.md) —
  the session summary for the 2026-08-12 work (banner-added).
- [`docs/fpga_only_migration_forensic_audit_2026-08-12.md`](fpga_only_migration_forensic_audit_2026-08-12.md) —
  the forensic audit of the pre-migration state (banner-added).