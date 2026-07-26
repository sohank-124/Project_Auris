"""
Project Auris — FFT configuration generator.

Provides:

* A reference O(N^2) DFT / IDFT used for validating the synthesised
  hardware FFT.
* A :class:`FFTConfig` dataclass capturing the architectural
  parameters of the target FFT core.
* A Vivado TCL emitter that instantiates the Xilinx xfft IP with
  those parameters.

The synthesised FFT in the Project Auris FPGA fabric is a
radix-2 DIT streaming FFT (the Xilinx xfft IP, configured in
pipelined-streaming mode with block-floating-point scaling).  This
module does not run Vivado; it only emits a TCL script that the
designer can ``source`` inside the Vivado Tcl console.
"""

from __future__ import annotations

import argparse
import cmath
import math
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Dict, List

# Make direct invocation work.
_HERE = Path(__file__).resolve().parent
_TOOLS = _HERE.parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from common.constants import N_FFT
from common.formats import write_json


# ---------------------------------------------------------------------------
# FFT configuration dataclass
# ---------------------------------------------------------------------------
@dataclass
class FFTConfig:
    """Configuration for the synthesised FFT / IFFT core."""
    n_points: int = 256
    data_width: int = 16
    twiddle_width: int = 16
    architecture: str = "radix2_dit"     # radix2_dit, radix2_dif, radix4, ...
    scaling: str = "block_floating"      # none | block_floating | per_stage
    phase_factor_width: int = 16
    output_ordering: str = "natural"     # natural | bit_reversed
    runt_time: int = 8                   # clocks per data sample in pipelined mode
    complex: bool = True                 # complex input/output

    def __post_init__(self) -> None:
        # Sanity: N_FFT must be a power of two in [16, 65536].
        if not (16 <= self.n_points <= 65536):
            raise ValueError(f"FFTConfig: n_points out of range ({self.n_points})")
        if self.n_points & (self.n_points - 1):
            raise ValueError(
                f"FFTConfig: n_points must be a power of two (got {self.n_points})"
            )
        if not (8 <= self.data_width <= 32):
            raise ValueError(
                f"FFTConfig: data_width must be in [8, 32] (got {self.data_width})"
            )
        if self.architecture not in (
            "radix2_dit", "radix2_dif", "radix4_burst", "radix4_pipelined",
            "radix2_lite", "pipe_streaming",
        ):
            raise ValueError(
                f"FFTConfig: unsupported architecture {self.architecture!r}"
            )
        if self.scaling not in ("none", "block_floating", "per_stage"):
            raise ValueError(
                f"FFTConfig: scaling must be none | block_floating | per_stage "
                f"(got {self.scaling!r})"
            )
        if self.output_ordering not in ("natural", "bit_reversed"):
            raise ValueError(
                f"FFTConfig: output_ordering must be natural or bit_reversed"
            )


# ---------------------------------------------------------------------------
# Reference DFT / IDFT
# ---------------------------------------------------------------------------
def reference_dft(x: List[complex]) -> List[complex]:
    """O(N^2) reference Discrete Fourier Transform.

    Computes ``X[k] = sum_{n=0}^{N-1} x[n] * exp(-j * 2 * pi * k * n / N)``.
    """
    n = len(x)
    if n == 0:
        return []
    if n & (n - 1):
        raise ValueError("reference_dft: length must be a power of two")
    w = -2.0 * math.pi / n
    return [sum(x[m] * cmath.exp(1j * w * k * m) for m in range(n))
            for k in range(n)]


def reference_idft(X: List[complex]) -> List[complex]:
    """O(N^2) reference Inverse Discrete Fourier Transform.

    Computes ``x[n] = (1/N) * sum_{k=0}^{N-1} X[k] * exp(+j * 2 * pi * k * n / N)``.
    """
    n = len(X)
    if n == 0:
        return []
    if n & (n - 1):
        raise ValueError("reference_idft: length must be a power of two")
    w = 2.0 * math.pi / n
    return [sum(X[k] * cmath.exp(1j * w * k * m) for k in range(n)) / n
            for m in range(n)]


# ---------------------------------------------------------------------------
# Config export
# ---------------------------------------------------------------------------
def generate_fft_config(cfg: FFTConfig) -> Dict[str, object]:
    """Return the FFT config as a plain dict (JSON-serialisable)."""
    d = asdict(cfg)
    # Add derived quantities useful to the RTL.
    n = cfg.n_points
    d["log2_n"] = int(math.log2(n))
    d["n_stages"] = d["log2_n"]
    d["butterflies_per_stage"] = n // 2
    return d


# ---------------------------------------------------------------------------
# Vivado TCL emitter
# ---------------------------------------------------------------------------
def generate_vivado_tcl(cfg: FFTConfig, out_path: Path) -> None:
    """Write a Vivado TCL script that instantiates the xfft IP.

    The script is self-contained: it can be ``source``-ed from the
    Vivado Tcl console after the user has created a fresh project
    targeting the appropriate Xilinx part.
    """
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    arch_map = {
        "radix2_dit": "1",     # Pipelined, streaming I/O
        "radix2_dif": "1",
        "radix4_burst": "0",
        "radix4_pipelined": "1",
        "radix2_lite": "2",
        "pipe_streaming": "1",
    }
    scaling_map = {
        "none": "0",
        "block_floating": "1",
        "per_stage": "2",
    }
    ordering_map = {
        "natural": "0",
        "bit_reversed": "1",
    }
    arch = arch_map[cfg.architecture]
    scaling = scaling_map[cfg.scaling]
    ordering = ordering_map[cfg.output_ordering]
    complex_in = "1" if cfg.complex else "0"

    tcl = []
    tcl.append("# =====================================================================")
    tcl.append(f"# Project Auris — {cfg.n_points}-point FFT configuration")
    tcl.append("# Generated by tools/fft_gen/gen_fft.py")
    tcl.append("# Source this script from a Vivado Tcl console.")
    tcl.append("# =====================================================================")
    tcl.append("")
    tcl.append("set ip_name fft_256")
    tcl.append(f"create_ip -name xfft -vendor xilinx.com -library ip ")
    tcl.append(f"  -version 9.1 \\")
    tcl.append(f"  -module_name $ip_name \\")
    tcl.append(f"  -dir [file normalize .]")
    tcl.append("")
    tcl.append(f"set_property -dict [list \\")
    tcl.append(f"  CONFIG.Component_Name      $ip_name \\")
    tcl.append(f"  CONFIG.FFT_Length          {{{cfg.n_points}}} \\")
    tcl.append(f"  CONFIG.Target_Clock_Frequency {{100}} \\")
    tcl.append(f"  CONFIG.Implementation       {{{arch}}} \\")
    tcl.append(f"  CONFIG.Scaling_Option       {{{scaling}}} \\")
    tcl.append(f"  CONFIG.Rounding_Modes       {{Truncation}} \\")
    tcl.append(f"  CONFIG.Data_Width           {{{cfg.data_width}}} \\")
    tcl.append(f"  CONFIG.Phase_Width          {{{cfg.phase_factor_width}}} \\")
    tcl.append(f"  CONFIG.Output_Ordering      {{{ordering}}} \\")
    tcl.append(f"  CONFIG.cyclic_prefix_insertion {{false}} \\")
    tcl.append(f"  CONFIG.complex_mult_type    {{Use_2_mults_and_engineer_a_conjugate_symmetry}} \\")
    tcl.append(f"  CONFIG.Number_Of_Stages     {{{cfg.n_stages if hasattr(cfg, 'n_stages') else int(math.log2(cfg.n_points))}}} \\")
    tcl.append(f"  CONFIG.Has_ARESETn          {{true}} \\")
    tcl.append(f"  CONFIG.Has_ACLKEN           {{true}} \\")
    tcl.append(f"  CONFIG.Xilinx_GUI_Presets   {{No_Resource_Sharing}} \\")
    tcl.append(f"  CONFIG.Clock_Period         {{10.0}} \\")
    tcl.append(f"  CONFIG.throttle_scheme      {{No_Throttling}} \\")
    tcl.append(f"] [get_ips $ip_name]")
    tcl.append("")
    tcl.append("# Generate the IP targets (synthesis + simulation).")
    tcl.append("generate_target {instantiation_template} [get_files $ip_name.xci]")
    tcl.append("generate_target {synthesis simulation} [get_files $ip_name.xci]")
    tcl.append("")
    tcl.append("# Export the .xci so the rest of the project can add it as a source.")
    tcl.append("set_property generate_synth_checkpoint true [get_files $ip_name.xci]")
    tcl.append("ipx::open_ipx_file $ip_name.xci")
    tcl.append("ipx::save_core $ip_name")
    tcl.append("")
    tcl.append("puts \"Generated $ip_name.xci in [pwd]\"")
    tcl.append("")

    out_path.write_text("\n".join(tcl), encoding="utf-8")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Generate FFT configuration and Vivado TCL.",
    )
    p.add_argument("--n-points", type=int, default=N_FFT)
    p.add_argument("--data-width", type=int, default=16)
    p.add_argument("--twiddle-width", type=int, default=16)
    p.add_argument("--phase-width", type=int, default=16)
    p.add_argument("--architecture",
                   choices=("radix2_dit", "radix2_dif",
                            "radix4_burst", "radix4_pipelined",
                            "radix2_lite", "pipe_streaming"),
                   default="radix2_dit")
    p.add_argument("--scaling",
                   choices=("none", "block_floating", "per_stage"),
                   default="block_floating")
    p.add_argument("--ordering",
                   choices=("natural", "bit_reversed"),
                   default="natural")
    p.add_argument("--out-dir", type=Path, default=Path("fpga/generated"))
    args = p.parse_args(argv)

    cfg = FFTConfig(
        n_points=args.n_points,
        data_width=args.data_width,
        twiddle_width=args.twiddle_width,
        phase_factor_width=args.phase_width,
        architecture=args.architecture,
        scaling=args.scaling,
        output_ordering=args.ordering,
    )

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    cfg_path = out_dir / "fft_config.json"
    write_json(generate_fft_config(cfg), cfg_path)
    print(f"  wrote {cfg_path}")

    tcl_path = out_dir / "fft_config.tcl"
    generate_vivado_tcl(cfg, tcl_path)
    print(f"  wrote {tcl_path}")

    # Reference DFT smoke test on an impulse.
    impulse = [1.0] + [0.0] * (cfg.n_points - 1)
    X = reference_dft(impulse)
    x_round = reference_idft(X)
    max_err = max(abs(a - b) for a, b in zip(impulse, x_round))
    print(f"Reference DFT round-trip max error on impulse: {max_err:.3e}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
