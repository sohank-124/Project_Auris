"""Check publishable paths and saved evidence without invoking FPGA tools."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[2]


def candidate_files() -> list[Path]:
    """Include unstaged work; exclude local-only files using Git's own rules."""
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
        capture_output=True,
        check=True,
    )
    return sorted(
        {ROOT / name.decode("utf-8") for name in result.stdout.split(b"\0") if name}
    )


def markdown_anchors(path: Path) -> set[str]:
    anchors: set[str] = set()
    text = re.sub(r"```.*?```", "", path.read_text(encoding="utf-8"), flags=re.S)
    counts: dict[str, int] = {}
    for heading in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", text, re.M):
        slug = re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-")
        count = counts.get(slug, 0)
        anchors.add(f"{slug}-{count}" if count else slug)
        counts[slug] = count + 1
    anchors.update(re.findall(r'(?:id|name)=[\"\']([^\"\']+)', text))
    return anchors


def main() -> int:
    failures: list[str] = []
    files = candidate_files()
    public = {p.resolve() for p in files}
    documents = [p for p in files if p.suffix == ".md"]
    links = 0
    for path in documents:
        if not path.is_file():
            failures.append(f"Missing tracked document: {path.relative_to(ROOT)}")
            continue
        # Historical Markdown remains subject to path checks; literal fenced
        # examples and text snapshots are not interpreted as live links.
        body = re.sub(r"```.*?```", "", path.read_text(encoding="utf-8"), flags=re.S)
        for match in re.finditer(r"\[[^\]]*\]\((<[^>]+>|[^\s)]+)\)", body):
            target = match.group(1).strip("<>")
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc:
                continue
            links += 1
            destination = (path.parent / unquote(parsed.path)).resolve()
            label = f"{path.relative_to(ROOT)} -> {target}"
            if not destination.exists():
                failures.append(f"Broken local link: {label}")
            elif destination.is_file() and destination not in public:
                failures.append(f"Link depends on ignored/unpublished file: {label}")
            elif parsed.fragment and destination.suffix == ".md":
                if unquote(parsed.fragment) not in markdown_anchors(destination):
                    failures.append(f"Missing heading anchor: {label}")

    benches = sorted((ROOT / "fpga/sim/testbenches").glob("tb_*.sv"))
    for bench in benches:
        entry = ROOT / "fpga/scripts" / f"sim_{bench.stem[3:]}.tcl"
        if not entry.is_file() or entry.resolve() not in public:
            failures.append(f"Unregistered/unpublished bench: {bench.name}")

    evidence_root = ROOT / "docs/verification/evidence"
    for manifest in sorted(evidence_root.glob("*/SHA256SUMS.json")):
        for name, expected in json.loads(manifest.read_text()).items():
            path = manifest.parent / name
            if (
                not path.is_file()
                or hashlib.sha256(path.read_bytes()).hexdigest() != expected
            ):
                failures.append(f"Evidence checksum mismatch: {path.relative_to(ROOT)}")

    snapshot = ROOT / "archive/documentation/pre-cleanup-2026-10-30/SHA256SUMS.json"
    if snapshot.exists():
        for name, expected in json.loads(snapshot.read_text()).items():
            path = snapshot.parent / name
            if (
                not path.is_file()
                or hashlib.sha256(path.read_bytes()).hexdigest() != expected
            ):
                failures.append(f"Archive checksum mismatch: {path.relative_to(ROOT)}")

    oversized = [p for p in files if p.is_file() and p.stat().st_size > 5_000_000]
    failures.extend(
        f"Review public file over 5 MB: {p.relative_to(ROOT)}" for p in oversized
    )
    print(
        f"Checked {len(documents)} public Markdown files, {links} local links, "
        f"{len(benches)} test registrations, saved checksums and public file sizes."
    )
    for failure in failures:
        print(f"FAIL: {failure}")
    if failures:
        return 1
    print("REPOSITORY_CHECK_PASS (no network, synthesis, simulation or board testing)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
