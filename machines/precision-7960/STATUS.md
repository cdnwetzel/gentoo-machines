# Dell Precision 7960 / Xeon W5-3433

**Status**: Reference only — stays on RHEL 10.1

Production AI/ML workstation. Dual NVIDIA Blackwell GPUs, **both 16 GB**:
- **RTX 5080** — 16 GB GDDR7 (replaced the original RTX A1000, which was relocated to the OptiPlex 3090)
- **RTX 5060 Ti OC** — 16 GB GDDR7

**The RTX PRO 6000 Blackwell 96 GB was sold (2026, months before 2026-09-03) and is no longer in this machine.** Earlier revisions of this file and of HARDWARE.md listed it as the primary GPU; that was stale and produced wrong capacity planning downstream. Current total VRAM is **32 GB across two unlinked cards** — consumer Blackwell has no NVLink, and the two cards are mismatched, so this is not a tensor-parallel host.

Hardware was harvested 2026-03-19, before both GPU changes. HARDWARE.md still reflects that snapshot — **re-harvest required** for the 5080's and 5060 Ti's PCI/subsystem IDs, audio devices, and i2c topology. No Gentoo install planned.
