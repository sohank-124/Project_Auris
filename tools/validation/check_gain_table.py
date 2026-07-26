"""
Project Auris — Gain-table sanity checks.

A "good" 128-bin per-channel gain table must satisfy several
properties before it is loaded into the FPGA:

* Every entry must lie within the supported dB range.
* Adjacent bins should not change by more than a few dB at a time
  (smoothness), and the global shape should be physically
  plausible (no erratic spikes).
* The DC bin (index 0) should be 0 dB ± a small tolerance to
  avoid amplifying DC bias / turn-on transients.
* If the table is derived from an audiogram, it should be
  monotonically non-decreasing through the high-frequency region
  whenever the underlying hearing loss is monotonically
  non-decreasing in that region.

Each check returns a small tuple of ``(ok, ...)`` values; the
combined :func:`validate_gain_table` runs them all and aggregates
the results.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Dict, List, Tuple

_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import GAIN_DB_MIN, GAIN_DB_MAX


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------
def check_gain_range(gains_db: List[float],
                     lo: float = GAIN_DB_MIN,
                     hi: float = GAIN_DB_MAX) -> Tuple[bool, float, float]:
    """Check every entry lies within ``[lo, hi]`` (dB).

    Returns ``(ok, min_gain, max_gain)``.
    """
    if not gains_db:
        return (True, 0.0, 0.0)
    g_min = min(gains_db)
    g_max = max(gains_db)
    return ((g_min >= lo and g_max <= hi), g_min, g_max)


def check_monotonicity(gains_db: List[float],
                       expected_direction: str = "any") -> Tuple[bool, int]:
    """Check that the gain curve is monotonic in the requested direction.

    Parameters
    ----------
    expected_direction : str
        ``"increasing"``, ``"decreasing"``, or ``"any"`` (no check).

    Returns
    -------
    (ok, n_violations) : Tuple[bool, int]
        ``n_violations`` is the number of adjacent pairs that violate
        the requested direction.  ``ok`` is True iff there are zero
        violations (or direction is ``"any"``).
    """
    if not gains_db or len(gains_db) < 2:
        return (True, 0)
    if expected_direction == "any":
        return (True, 0)

    n_viol = 0
    for i in range(1, len(gains_db)):
        d = gains_db[i] - gains_db[i - 1]
        if expected_direction == "increasing" and d < 0:
            n_viol += 1
        elif expected_direction == "decreasing" and d > 0:
            n_viol += 1
    return (n_viol == 0, n_viol)


def check_smoothness(gains_db: List[float],
                     max_step_db: float = 3.0) -> Tuple[bool, float, int]:
    """Check that no adjacent step exceeds ``max_step_db`` dB.

    Returns ``(ok, max_step_db, n_violations)``.
    """
    if not gains_db or len(gains_db) < 2:
        return (True, 0.0, 0)
    max_step = 0.0
    n_viol = 0
    for i in range(1, len(gains_db)):
        d = abs(gains_db[i] - gains_db[i - 1])
        if d > max_step:
            max_step = d
        if d > max_step_db:
            n_viol += 1
    return (n_viol == 0, max_step, n_viol)


def check_dc_unity(gains_db: List[float],
                   tol_db: float = 0.1) -> Tuple[bool, float]:
    """Check the DC-bin (index 0) gain is 0 dB within ``tol_db``.

    Returns ``(ok, dc_gain_db)``.
    """
    if not gains_db:
        return (True, 0.0)
    return (abs(gains_db[0]) <= tol_db, float(gains_db[0]))


# ---------------------------------------------------------------------------
# Aggregate
# ---------------------------------------------------------------------------
def validate_gain_table(gains_db: List[float],
                        audiogram: List[float] = None) -> Dict:
    """Run all the gain-table checks and return a structured report.

    Parameters
    ----------
    gains_db : list of float
        The 128-bin gain table to validate.
    audiogram : list of float, optional
        If provided, the per-band insertion-gain table is recomputed
        from the audiogram (half-gain rule) and the gain table is
        additionally compared to it for overall shape agreement.

    Returns
    -------
    dict
        ``{"all_passed", "n_bins", "checks": {...}, "summary": "..."}``.
    """
    if not gains_db:
        return {
            "all_passed": True,
            "n_bins": 0,
            "checks": {},
            "summary": "empty table — nothing to check",
        }

    range_ok, g_min, g_max = check_gain_range(gains_db)
    smooth_ok, max_step, n_step_viol = check_smoothness(gains_db)
    dc_ok, dc_gain = check_dc_unity(gains_db)

    # Monotonicity: require the curve to be non-decreasing for bins
    # in the speech band (1 kHz..4 kHz).  Indices 21..85 in a 256-pt
    # FFT (FS=48 kHz) cover roughly 1-4 kHz.
    mono_ok, n_mono_viol = check_monotonicity(
        gains_db[21:86], expected_direction="increasing"
    )

    checks: Dict = {
        "gain_range":   {"ok": range_ok, "min_db": g_min, "max_db": g_max},
        "smoothness":   {"ok": smooth_ok, "max_step_db": max_step,
                         "n_violations": n_step_viol},
        "dc_unity":     {"ok": dc_ok, "dc_gain_db": dc_gain},
        "monotonicity": {"ok": mono_ok, "n_violations": n_mono_viol,
                         "band": "1-4 kHz (bins 21..85)"},
    }

    # Optional audiogram comparison.
    if audiogram is not None and len(audiogram) == 7:
        from common.audiogram import Audiogram
        from common.constants import N_BINS
        expected = Audiogram(list(audiogram), label="validation").to_bin_gains()
        max_err = max(abs(g - e) for g, e in zip(gains_db, expected)) \
            if expected else 0.0
        shape_ok = max_err <= 3.0
        checks["audiogram_shape"] = {
            "ok": shape_ok,
            "max_error_db": max_err,
            "tolerance_db": 3.0,
        }

    all_ok = all(c["ok"] for c in checks.values())
    return {
        "all_passed": all_ok,
        "n_bins": len(gains_db),
        "checks": checks,
        "summary": ("all checks passed" if all_ok
                    else f"{sum(1 for c in checks.values() if not c['ok'])} "
                         f"of {len(checks)} checks failed"),
    }


# ---------------------------------------------------------------------------
# I/O helpers
# ---------------------------------------------------------------------------
def _read_gain_file(path: Path) -> List[float]:
    out: List[float] = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            try:
                out.append(float(s.split(",")[0].split()[0]))
            except ValueError:
                continue
    return out


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Gain-table sanity checker.")
    p.add_argument("--gain-file", type=Path, required=True,
                   help="Gain table file (one float per line).")
    p.add_argument("--audiogram", default=None,
                   help="Optional 7-value audiogram, e.g. '0,0,10,25,35,40,45'")
    args = p.parse_args(argv)

    gains = _read_gain_file(args.gain_file)
    if not gains:
        raise SystemExit(f"error: no data read from {args.gain_file}")
    print(f"Loaded {len(gains)} gain values from {args.gain_file}")

    audio = None
    if args.audiogram:
        audio = [float(x) for x in args.audiogram.split(",")]

    report = validate_gain_table(gains, audiogram=audio)
    print(f"All passed: {report['all_passed']}")
    print(f"Summary   : {report['summary']}")
    for k, v in report["checks"].items():
        status = "PASS" if v["ok"] else "FAIL"
        print(f"  [{status}] {k}: {v}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
