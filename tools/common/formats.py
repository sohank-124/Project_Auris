"""
Project Auris — File-format writers for FPGA bitstream initialisation.

The DSP toolchain emits tables that must be loaded into Block-RAM
(``$readmemh``, Xilinx COE, Altera MIF) or consumed by other tools
(JSON, TSV). This module centralises the writers so all generators
produce consistent output.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, Iterable, List, Sequence


# ---------------------------------------------------------------------------
# Low-level writers
# ---------------------------------------------------------------------------
def _ensure_parent(path: Path) -> None:
    """Create the parent directory of ``path`` if necessary."""
    p = path.parent
    if p and not p.exists():
        p.mkdir(parents=True, exist_ok=True)


def _to_hex_word(v: int, width: int = 4) -> str:
    """Format ``v`` as a zero-padded uppercase hex string of ``width`` chars."""
    return f"{(int(v) & ((1 << (4 * width)) - 1)):0{4 * width}X}"


# ---------------------------------------------------------------------------
# Public writers
# ---------------------------------------------------------------------------
def write_hex(values: Sequence[int],
              path: Path,
              header: str = "") -> None:
    """Write ``values`` as 4-char hex, one per line.

    Parameters
    ----------
    values : sequence of int
        Values are masked to 16 bits before being written, so callers may
        pass raw signed integers.
    path : Path
        Destination file.
    header : str
        If non-empty, written as a ``// ...`` comment block at the top.
    """
    _ensure_parent(path)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        if header:
            for line in header.splitlines() or [""]:
                f.write(f"// {line}\n" if line else "//\n")
        for v in values:
            f.write(f"{_to_hex_word(v, width=4)}\n")


def write_coe(values: Sequence[int],
              path: Path,
              radix: int = 16,
              width: int = 16) -> None:
    """Write ``values`` in Xilinx COE format.

    The output begins with ``memory_initialization_radix=<radix>;`` and
    a ``memory_initialization_vector=`` block whose contents are
    comma-separated values terminated with a semicolon.  For ``radix==16``
    each value is rendered as a 4-character hex word (``width`` bits
    are honoured); for ``radix==10`` and ``radix==2`` plain decimal /
    binary forms are emitted.
    """
    if radix not in (2, 10, 16):
        raise ValueError(f"write_coe: radix must be 2, 10, or 16 (got {radix})")
    _ensure_parent(path)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"memory_initialization_radix={radix};\n")
        f.write("memory_initialization_vector=\n")
        for i, v in enumerate(values):
            sep = "," if i < len(values) - 1 else ";"
            if radix == 16:
                f.write(f"{_to_hex_word(v, width=width // 4)}{sep}\n")
            elif radix == 2:
                f.write(f"{int(v) & ((1 << width) - 1):0{width}b}{sep}\n")
            else:  # radix == 10
                f.write(f"{int(v)}{sep}\n")


def write_mif(values: Sequence[int],
              path: Path,
              depth: int,
              width: int = 16) -> None:
    """Write ``values`` in Altera MIF format.

    Parameters
    ----------
    depth : int
        Total memory depth; if ``len(values) < depth`` the remainder is
        filled with zero.
    width : int
        Memory data width in bits.
    """
    _ensure_parent(path)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(f"DEPTH = {depth};\n")
        f.write(f"WIDTH = {width};\n")
        f.write("ADDRESS_RADIX = HEX;\n")
        f.write("DATA_RADIX = HEX;\n")
        f.write("CONTENT\n")
        f.write("BEGIN\n")
        # Pad the list to the requested depth.
        padded: List[int] = list(values) + [0] * max(0, depth - len(values))
        for i, v in enumerate(padded):
            f.write(f"{i:04X} : {_to_hex_word(v, width=width // 4)};\n")
        f.write("END;\n")


def write_readmemb(values: Sequence[int],
                   path: Path) -> None:
    """Write ``values`` in ``$readmemb``-compatible binary form.

    Each value is rendered as a ``width``-bit binary string, one per line.
    """
    _ensure_parent(path)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("// $readmemb-compatible binary file (synthesizable).\n")
        for v in values:
            f.write(f"{int(v) & 0xFFFF:016b}\n")


# ---------------------------------------------------------------------------
# Human-readable and JSON writers
# ---------------------------------------------------------------------------
def write_txt_table(rows: Sequence[Dict],
                    path: Path,
                    columns: Sequence[str]) -> None:
    """Write a list of dicts as a tab-separated table.

    The header row is the column names; missing keys are emitted as
    empty strings.  Floats are formatted with 6 significant digits.
    """
    _ensure_parent(path)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("# " + "\t".join(columns) + "\n")
        for row in rows:
            cells = []
            for c in columns:
                v = row.get(c, "")
                if isinstance(v, float):
                    cells.append(f"{v:.6g}")
                else:
                    cells.append(str(v))
            f.write("\t".join(cells) + "\n")


def write_json(data: Dict, path: Path) -> None:
    """Write ``data`` as pretty-printed JSON (indent=2)."""
    _ensure_parent(path)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=False)
        f.write("\n")


# ---------------------------------------------------------------------------
# Composite writer
# ---------------------------------------------------------------------------
def write_all(values: Sequence[int],
              base_path: Path,
              header: str = "") -> None:
    """Write ``values`` in .hex, .coe, and .txt forms (no extension).

    The three files share the same ``base_path`` and are suffixed with
    ``.hex``, ``.coe``, and ``.txt`` respectively.  The .txt file is a
    decimal dump ``idx, value`` per line.
    """
    write_hex(values, Path(str(base_path) + ".hex"), header=header)
    write_coe(values, Path(str(base_path) + ".coe"))
    _ensure_parent(Path(str(base_path) + ".txt"))
    with open(Path(str(base_path) + ".txt"), "w", encoding="utf-8",
              newline="\n") as f:
        if header:
            for line in header.splitlines() or [""]:
                f.write(f"# {line}\n" if line else "#\n")
        for i, v in enumerate(values):
            f.write(f"{i:5d}, {int(v)}\n")
