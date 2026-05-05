# Dell Precision 7960 / Xeon W5-3433

**Status**: Reference only — stays on RHEL 10.1

Production AI/ML workstation. Dual NVIDIA Blackwell GPUs:
- **RTX PRO 6000 Blackwell Workstation Edition** — 96 GB GDDR7, 600W, primary AI/ML
- **RTX 5080** — 16 GB GDDR7, secondary compute (replaced the original RTX A1000, which was relocated to the OptiPlex 3090)

Hardware was harvested 2026-03-19 (pre-GPU-swap). HARDWARE.md still reflects that snapshot for the secondary slot — re-harvest required for the RTX 5080's PCI/subsystem IDs and audio device. No Gentoo install planned.
