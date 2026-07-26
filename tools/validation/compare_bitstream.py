"""
Project Auris — Bitstream / table comparator.

The DSP toolchain emits many small text / hex files (window
coefficients, twiddle factors, gain tables, …) that are loaded
into Block-RAMs at synthesis time.  Whenever a generator changes
its output the regression test suite must be able to confirm that
only the expected files have changed.

This module provides:

* :func:`compare_hex_files` — line-by-line hex comparison that
  tolerates comment lines and trivial whitespace differences.
* :func:`compare_float_arrays` — element-wise float comparison
  with a configurable tolerance.
* :func:`generate_diff_report` — a human-readable text diff
  between two sequences.
* :func:`regression_test` — compare every ``.hex`` (or other
  extension) file in a reference directory against the
  corresponding file in a test directory and return a summary
  dict suitable for CI consumption.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.formats import write_json


# ---------------------------------------------------------------------------
# Single-file hex comparison
# ---------------------------------------------------------------------------
_HEX_RE = re.compile(r"^[0-9A-Fa-f]+$")


def _normalise_hex_line(line: str) -> str:
    """Strip comments / whitespace and return a lower-case hex string."""
    s = line.split("//", 1)[0].split("#", 1)[0].strip()
    if not s:
        return ""
    # If the line is a single hex word, return it lower-cased.
    if _HEX_RE.match(s):
        return s.lower()
    # Otherwise try to find the last hex-looking token.
    toks = s.split()
    for tok in reversed(toks):
        if _HEX_RE.match(tok):
            return tok.lower()
    return ""


def compare_hex_files(file_a: Path, file_b: Path) -> Tuple[bool, int, List[int]]:
    """Line-by-line hex comparison of two files.

    Parameters
    ----------
    file_a, file_b : Path
        Paths to the two files.

    Returns
    -------
    (equal, n_compared, diff_indices) : Tuple[bool, int, list[int]]
        ``n_compared`` is the number of value lines actually compared;
        ``diff_indices`` is the list of line indices (0-based, after
        comments are stripped) that differ.
    """
    if not file_a.exists():
        return (False, 0, [-1])
    if not file_b.exists():
        return (False, 0, [-1])

    with open(file_a, "r", encoding="utf-8", errors="replace") as fa, \
         open(file_b, "r", encoding="utf-8", errors="replace") as fb:
        la = [_normalise_hex_line(l) for l in fa]
        lb = [_normalise_hex_line(l) for l in fb]

    # Drop empty lines.
    la = [x for x in la if x]
    lb = [x for x in lb if x]

    n = min(len(la), len(lb))
    diffs: List[int] = []
    for i in range(n):
        if la[i] != lb[i]:
            diffs.append(i)
    # Different lengths count as one trailing diff.
    if len(la) != len(lb):
        diffs.append(n)
    return (not diffs, n, diffs)


# ---------------------------------------------------------------------------
# Float array comparison
# ---------------------------------------------------------------------------
def compare_float_arrays(a: Sequence[float],
                         b: Sequence[float],
                         tol: float = 1e-6
                         ) -> Tuple[bool, float, List[int]]:
    """Element-wise comparison of two float arrays.

    Returns ``(equal, max_abs_error, diff_indices)``.  ``max_abs_error``
    is the largest absolute element-wise difference.
    """
    n = min(len(a), len(b))
    diffs: List[int] = []
    max_err = 0.0
    for i in range(n):
        e = abs(float(a[i]) - float(b[i]))
        if e > tol:
            diffs.append(i)
        if e > max_err:
            max_err = e
    if len(a) != len(b):
        diffs.append(n)
    return (not diffs, max_err, diffs)


# ---------------------------------------------------------------------------
# Human-readable diff
# ---------------------------------------------------------------------------
def generate_diff_report(a: Sequence, b: Sequence,
                         labels: Tuple[str, str] = ("A", "B"),
                         max_rows: int = 50) -> str:
    """Return a small text diff between two sequences.

    The report shows the index, both values, and the absolute
    difference for every mismatching entry, up to ``max_rows`` rows.
    """
    out: List[str] = []
    out.append(f"Diff report ({labels[0]} vs {labels[1]})")
    out.append(f"  len({labels[0]}) = {len(a)}, len({labels[1]}) = {len(b)}")
    n = min(len(a), len(b))
    n_diff = 0
    for i in range(n):
        av, bv = a[i], b[i]
        try:
            d = abs(float(av) - float(bv))
            if d == 0:
                continue
        except (TypeError, ValueError):
            if av == bv:
                continue
        n_diff += 1
        if n_diff <= max_rows:
            out.append(f"  [{i:5d}] {labels[0]}={av!r}  {labels[1]}={bv!r}")
    if n_diff > max_rows:
        out.append(f"  ... and {n_diff - max_rows} more differing entries")
    out.append(f"  total differing entries: {n_diff}")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Directory-level regression
# ---------------------------------------------------------------------------
def regression_test(reference_dir: Path,
                    test_dir: Path,
                    extensions: Sequence[str] = (".hex",),
                    tol: float = 1e-6) -> Dict:
    """Compare every file in ``reference_dir`` against ``test_dir``.

    Files whose extension is not in ``extensions`` are skipped.  The
    result is a dict that can be JSON-serialised for CI consumption.
    """
    reference_dir = Path(reference_dir)
    test_dir = Path(test_dir)
    if not reference_dir.exists():
        return {"reference_dir": str(reference_dir),
                "test_dir": str(test_dir),
                "ok": False,
                "error": "reference directory does not exist",
                "files": []}
    if not test_dir.exists():
        return {"reference_dir": str(reference_dir),
                "test_dir": str(test_dir),
                "ok": False,
                "error": "test directory does not exist",
                "files": []}

    files: List[Dict] = []
    for ref in sorted(reference_dir.iterdir()):
        if not ref.is_file():
            continue
        if ref.suffix.lower() not in extensions:
            continue
        test = test_dir / ref.name
        equal, n_compared, diffs = compare_hex_files(ref, test)
        files.append({
            "name": ref.name,
            "ref_path": str(ref),
            "test_path": str(test),
            "exists_in_test": test.exists(),
            "equal": bool(equal),
            "n_compared": n_compared,
            "n_diff": len(diffs),
            "diff_indices": diffs[:32],      # truncate for brevity
        })
    n_total = len(files)
    n_ok = sum(1 for f in files if f["equal"])
    return {
        "reference_dir": str(reference_dir),
        "test_dir": str(test_dir),
        "extensions": list(extensions),
        "ok": (n_ok == n_total and n_total > 0),
        "n_files": n_total,
        "n_ok": n_ok,
        "n_failed": n_total - n_ok,
        "files": files,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Compare hex / float bitstream files for regression testing.",
    )
    p.add_argument("--reference-dir", type=Path, required=True)
    p.add_argument("--test-dir", type=Path, required=True)
    p.add_argument("--extensions", nargs="*",
                   default=[".hex"],
                   help="File extensions to compare (default: .hex).")
    p.add_argument("--out", type=Path, default=None,
                   help="Optional JSON report output.")
    args = p.parse_args(argv)

    report = regression_test(args.reference_dir, args.test_dir,
                             extensions=tuple(args.extensions))
    print(f"Regression test: {args.reference_dir} vs {args.test_dir}")
    print(f"  files        = {report['n_files']}")
    print(f"  OK           = {report['n_ok']}")
    print(f"  failed       = {report['n_failed']}")
    for f in report["files"]:
        status = "PASS" if f["equal"] else "FAIL"
        print(f"  [{status}] {f['name']:30s} "
              f"n={f['n_compared']:5d}  diff={f['n_diff']:4d}")
    if args.out is not None:
        write_json(report, args.out)
        print(f"Wrote {args.out}")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
