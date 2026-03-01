# Backlog

## High Priority
- [ ] Execute Surface Pro 6 Gentoo install (scripts ready, ~3.5 hours)
- [ ] Post-install SP6 verification: WiFi, display, audio, zram, brightness, GPU

## Medium Priority
- [ ] Install Gentoo on NUC11 — follow INSTALL.md
- [ ] Test USB-C hub (Anker 7-in-1) on XPS 9510 — HDMI + USB 3.0 devices
- [ ] Test clamshell mode on XPS 9510 with AOC 34" external
- [ ] MBP 2015: investigate FaceTime camera (facetimehd out-of-tree driver)
- [ ] MBP 2015: fix GRUB installkernel to use version suffix (avoid manual cp after make install)
- [ ] Run kconfig-lint against MBP 2015 / SP6 on their target kernel versions (6.12.58 INFOs may clear)

## Low Priority
- [ ] Rename GitHub repo (gentoo_dell_xps9315 → gentoo-machines or similar)
- [ ] Harvest ASRock B550 / Ryzen 9 5950X (Fedora 42)
- [ ] Harvest Dell Precision T5810 (Fedora 42)
- [ ] Harvest Dell Precision 7960 (RHEL 10.1)
- [ ] Harvest Surface Pro 9 (Windows 11 Pro)
- [ ] Report ipu-bridge-fix-double-brace.patch upstream (Gentoo or kernel bugzilla)
- [ ] Submit intel_idle Tiger Lake patch upstream to LKML
- [ ] MBP 2015: add WiFi NVRAM txt file for full 5GHz channel support (optional)
- [ ] MBP 2015: consider blacklisting thunderbolt module to save ~2W idle power

## Completed
- [x] Build kconfig-lint.sh — static kernel config validator (5 checks, 19K symbols)
- [x] Enhance harvest.sh with 7 new sections (CPU_FLAGS_X86, audio, vendor, EFI, suspend, firmware, -march)
- [x] Build kernel-config-template.sh — skeleton generator from harvest data
- [x] Fix XPS 9315 SND_SOC_SOF_INTEL_TOPLEVEL bug (bool, not tristate) — caught by kconfig-lint
