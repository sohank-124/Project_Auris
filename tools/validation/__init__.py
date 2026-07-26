"""
Project Auris — Cross-stage validation utilities.

Submodules
----------
check_parseval
    Parseval's theorem checker in floating-point and Q2.14 fixed-point.
check_cola
    Constant Overlap-Add checker for windowed frame reconstruction.
check_gain_table
    Range, monotonicity, smoothness, and DC-unity checks for a
    per-bin gain table.
compare_bitstream
    Hex / float / bit-accurate file comparator for regression testing
    of generated tables.
"""

__all__ = [
    "check_parseval",
    "check_cola",
    "check_gain_table",
    "compare_bitstream",
]
