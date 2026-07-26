"""
Project Auris — Latency report generator.

Combines the theoretical budget from
:mod:`tools.latency_analysis.compute_latency` with the measured
round-trip from :mod:`tools.latency_analysis.measure_roundtrip`
into a single report (JSON, HTML, or plain text) that the audio
team can paste into the test-summary ticket.

A :class:`LatencyBudget` is also checked against the system target
(``LATENCY_TARGET_MS``) and a pass / fail verdict is emitted.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Optional

_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import LATENCY_TARGET_MS, N_FFT
from common.formats import write_json

from .compute_latency import (
    LatencyBudget,
    compute_theoretical_latency,
    format_latency_table,
)


# ---------------------------------------------------------------------------
# Pass / fail
# ---------------------------------------------------------------------------
def check_latency_target(budget: LatencyBudget,
                         target_ms: float = LATENCY_TARGET_MS
                         ) -> tuple[bool, float]:
    """Return ``(passed, margin_ms)``.

    ``passed`` is True iff ``budget.total_ms <= target_ms``.  ``margin_ms``
    is ``target_ms - budget.total_ms`` (positive if the system meets the
    target, negative if it overruns).
    """
    margin = target_ms - budget.total_ms
    return (margin >= 0.0, margin)


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
def _html_escape(s: str) -> str:
    return (s.replace("&", "&amp;")
             .replace("<", "&lt;")
             .replace(">", "&gt;"))


def generate_latency_report(theoretical: LatencyBudget,
                            measured: Optional[dict] = None,
                            out_path: Optional[Path] = None,
                            format: str = "json",
                            target_ms: float = LATENCY_TARGET_MS
                            ) -> dict:
    """Build a latency report combining theoretical and measured data.

    Parameters
    ----------
    theoretical : LatencyBudget
        The static pipeline budget.
    measured : dict, optional
        Output of :func:`tools.latency_analysis.measure_roundtrip.measure_roundtrip_latency`.
    out_path : Path, optional
        If provided, the formatted report is written here.
    format : str
        ``"json"`` (default), ``"html"``, or ``"txt"``.
    target_ms : float
        Pass / fail target in ms.

    Returns
    -------
    dict
        The structured report.  Keys are ``timestamp``, ``target_ms``,
        ``passed``, ``margin_ms``, ``percentage`` (per-stage
        contribution), ``theoretical``, ``measured``.
    """
    passed, margin = check_latency_target(theoretical, target_ms=target_ms)
    total = max(theoretical.total_ms, 1e-12)
    percentage = {
        "codec_adc":   100.0 * theoretical.codec_adc_ms / total,
        "buffer_fill": 100.0 * theoretical.buffer_fill_ms / total,
        "fft":         100.0 * theoretical.fft_ms / total,
        "processing":  100.0 * theoretical.processing_ms / total,
        "ifft":        100.0 * theoretical.ifft_ms / total,
        "ola":         100.0 * theoretical.ola_ms / total,
        "codec_dac":   100.0 * theoretical.codec_dac_ms / total,
    }
    report = {
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "target_ms": target_ms,
        "passed": bool(passed),
        "margin_ms": margin,
        "percentage": {k: round(v, 3) for k, v in percentage.items()},
        "theoretical": asdict(theoretical),
        "measured": measured,
    }

    if out_path is not None:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        if format == "json":
            with open(out_path, "w", encoding="utf-8") as f:
                json.dump(report, f, indent=2)
                f.write("\n")
        elif format == "html":
            rows = "".join(
                f"<tr><td>{_html_escape(k)}</td>"
                f"<td>{theoretical.__dict__[k]:.4f}</td>"
                f"<td>{percentage[k]:.2f}%</td></tr>"
                for k in ("codec_adc_ms", "buffer_fill_ms", "fft_ms",
                          "processing_ms", "ifft_ms", "ola_ms",
                          "codec_dac_ms")
            )
            measured_html = ""
            if measured is not None:
                measured_html = (
                    "<h2>Measured round-trip</h2>"
                    f"<p>Delay: {measured.get('delay_ms', 0):.4f} ms "
                    f"({measured.get('sub_sample_delay_samples', 0):.3f} "
                    f"samples at {measured.get('fs', 0):.0f} Hz)</p>"
                )
            html = f"""<!doctype html>
<html><head><meta charset="utf-8">
<title>Project Auris — Latency report</title>
<style>
body{{font-family:system-ui,sans-serif;margin:2em;}}
table{{border-collapse:collapse;}}
td,th{{border:1px solid #ccc;padding:4px 12px;}}
.passed{{color:green;font-weight:bold;}}
.failed{{color:red;font-weight:bold;}}
</style></head><body>
<h1>Project Auris — Latency report</h1>
<p>Generated: {_html_escape(report['timestamp'])}</p>
<p>Total: <b>{theoretical.total_ms:.4f} ms</b> &mdash;
Target: <b>{target_ms:.4f} ms</b> &mdash;
Status: <span class="{'passed' if passed else 'failed'}">
{'PASS' if passed else 'FAIL'}</span></p>
<table><thead><tr><th>Stage</th><th>ms</th><th>%</th></tr></thead>
<tbody>{rows}
<tr><th>total</th><th>{theoretical.total_ms:.4f}</th>
<th>100.00%</th></tr></tbody></table>
{measured_html}
</body></html>
"""
            with open(out_path, "w", encoding="utf-8") as f:
                f.write(html)
        elif format == "txt":
            with open(out_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(f"Project Auris — Latency report\n")
                f.write(f"Generated: {report['timestamp']}\n")
                f.write(f"Target: {target_ms:.4f} ms\n")
                f.write(f"Status: {'PASS' if passed else 'FAIL'} "
                        f"(margin = {margin:+.4f} ms)\n\n")
                f.write(format_latency_table(theoretical, target_ms=target_ms))
                f.write("\n")
                if measured is not None:
                    f.write("\nMeasured round-trip:\n")
                    f.write(f"  delay_ms                = "
                            f"{measured.get('delay_ms', 0):.4f}\n")
                    f.write(f"  sub_sample_delay_samples = "
                            f"{measured.get('sub_sample_delay_samples', 0):.3f}\n")
                    f.write(f"  int_delay_samples        = "
                            f"{measured.get('int_delay_samples', 0)}\n")
                    f.write(f"  peak_correlation         = "
                            f"{measured.get('peak_correlation', 0):.6e}\n")
        else:
            raise ValueError(
                f"generate_latency_report: unknown format {format!r}"
            )

    return report


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: Optional[list] = None) -> int:
    p = argparse.ArgumentParser(
        description="Generate a latency report from a theoretical budget.",
    )
    p.add_argument("--n-fft", type=int, default=N_FFT)
    p.add_argument("--frame-advance", type=int, default=128)
    p.add_argument("--fs", type=float, default=48000.0)
    p.add_argument("--pipeline-stages", type=int, default=3)
    p.add_argument("--codec-delay-ms", type=float, default=0.5)
    p.add_argument("--target-ms", type=float, default=LATENCY_TARGET_MS)
    p.add_argument("--measured-json", type=Path, default=None,
                   help="Optional JSON file from measure_roundtrip.")
    p.add_argument("--format", choices=("json", "html", "txt"),
                   default="json")
    p.add_argument("--out", type=Path, default=Path("latency_report.json"))
    args = p.parse_args(argv)

    budget = compute_theoretical_latency(
        n_fft=args.n_fft,
        frame_advance=args.frame_advance,
        fs=args.fs,
        pipeline_stages=args.pipeline_stages,
        codec_delay_ms=args.codec_delay_ms,
    )
    measured = None
    if args.measured_json is not None and args.measured_json.exists():
        with open(args.measured_json, "r", encoding="utf-8") as f:
            measured = json.load(f)

    report = generate_latency_report(
        budget, measured=measured, out_path=args.out,
        format=args.format, target_ms=args.target_ms,
    )
    print(f"Report written to {args.out}")
    print(f"  total     = {budget.total_ms:.4f} ms")
    print(f"  target    = {args.target_ms:.4f} ms")
    print(f"  status    = {'PASS' if report['passed'] else 'FAIL'}")
    print(f"  margin    = {report['margin_ms']:+.4f} ms")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
