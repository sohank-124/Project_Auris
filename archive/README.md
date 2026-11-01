# Historical source and documentation

This directory is outside the active FPGA build. Nothing here is a current hardware specification or a claim of current verification.

| Path | Historical purpose |
| --- | --- |
| `firmware/` | Removed ESP32/ESP-IDF control plane |
| `rtl/` | Removed SPI slave/register file and SPI clock crossings |
| `tb/` | Retired SPI/register tests |
| `scripts/` | Retired simulation entries |
| [Documentation snapshots](documentation/pre-cleanup-2026-10-30/README.md) | Original pre-cleanup documents with historical explanations and mistakes preserved |

The current system uses FPGA-generated clocks and onboard buttons. See [current architecture](../docs/architecture/README.md), [engineering decisions](../docs/development/ENGINEERING_DECISIONS.md), and [verification status](../docs/verification/VERIFICATION_STATUS.md).

Raw intermediate audit work remains local in `.audit_verification/`; selected evidence is published under `docs/verification/evidence/`. Meaningful failures are retained and summarized, not rewritten into successes.
