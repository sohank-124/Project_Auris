# Project role and provenance

Project Auris is a solo project led by Sohan, covering architecture, RTL integration, debugging, verification, and
documentation. This scope was confirmed by the project owner during the 2026-10-30 cleanup. It does not mean every line
was written without tools or outside references.

The FFT and IFFT are AMD/Xilinx XFFT IP, wrapped and integrated with the project's buffering, control, and numerical
logic. Board and device documentation come from their manufacturers. Seventeen RTL files retain `Author: [generated]`
labels. Automated audit and repair records are preserved locally, and selected source-bound findings are published under
verification and research.

The exact division of tool-assisted text and code versus handwritten material has not been established file by
file. Existing attribution is retained. No claim of independently handwriting every source file is made. Before
publishing a more detailed authorship statement, the owner should confirm assistance and provenance rather than infer it
from commit author fields.

The development record emphasizes decisions and reproducible checks that the project lead can explain: frame ownership,
exponent association, fixed-point thresholds, reset sequencing, and physical timing assumptions. These are documented
outcomes; automated prose is not independent expert endorsement.
