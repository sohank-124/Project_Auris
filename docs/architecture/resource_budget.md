# Implemented resources and timing

These are saved Vivado 2026.1 production-top results dated 2026-10-30, not per-module estimates. The [verification
evidence](../verification/VERIFICATION_STATUS.md) identifies the exact input manifest and copied reports.

| Resource | Used | Available | Utilization |
| --- | --- | --- | --- |
| LUTs | 6165 | 14600 | 42.23% |
| Flip-flops | 9851 | 29200 | 33.74% |
| BRAM36-equivalent tiles | 6.5 | 45 | 14.44% |
| DSP48E1 slices | 28 | 80 | 35.00% |

The saved design also uses 3 BUFGs and 1 MMCM. Slice occupancy is 65.53%; unused LUT count alone does not describe
routing or packing headroom. No speculative future-feature capacity is guaranteed.

## Timing interpretation

Setup checks ensure data arrives before capture. Hold checks ensure it stays stable after capture. The critical path is
the path with the least slack for the check, not necessarily the longest geometric route.

The saved route has setup slack +0.696 ns, hold slack +0.019 ns, no failing setup/hold endpoints, and no unconstrained
internal endpoints under the reported checks. There is no current failing data path in this evidence.

Critical setup runs from volume_level_reg[0] through volume gain arithmetic to a volume output register. Data delay is
9.439 ns: 5.725 ns combinational logic plus 3.714 ns routing. Clock distribution, fanout, placement, and route affect
margin. Critical hold is inside the encrypted IFFT: 0.318 ns data delay, 0.148 ns cell and 0.170 ns route. The positive
hold margin is small but meets the modeled requirement.

In plain language, the implemented FPGA meets the saved timing model. The external interface budgets are recorded in the
[hardware timing contract](../hardware/TIMING_CONTRACT.md).

No extra pipeline stage is proposed. Registering a long combinational path can split setup delay but adds cycles,
registers, alignment checks, and architectural obligations; it is not a general fix for a short hold path or an
incorrect constraint model. Recent spectral-stage work is documented in the [decision
record](../development/ENGINEERING_DECISIONS.md).
