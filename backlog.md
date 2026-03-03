# Backlog

## High Priority
- [x] Execute Surface Pro 6 Gentoo install (scripts ready, ~3.5 hours) [hardware]
- [x] Post-install SP6 verification: WiFi, display, audio, zram, brightness, GPU [hardware]
- [x] MBP 2015: upgrade install scripts to XPS/SP6 standard — 9 orphaned files, filename mismatch, zram algo inconsistency [repo]

## Medium Priority
- [ ] MBP 2015: investigate FaceTime camera (facetimehd out-of-tree driver) [repo+hardware]
- [ ] Install Gentoo on NUC11 — follow INSTALL.md [hardware]
- [ ] Unify git identity across remaining dev machines — ~~XPS 9510~~, ~~Surface Pro 6~~, MBP 2015, NUC11, Precision 7960 [hardware]
- [ ] Test USB-C hub (Anker 7-in-1) on XPS 9510 — HDMI + USB 3.0 devices [hardware]
- [ ] Test clamshell mode on XPS 9510 with AOC 34" external [hardware]

## Low Priority
- [ ] Harvest ASRock B550 / Ryzen 9 5950X (Fedora 42) [hardware]
- [ ] Harvest Dell Precision T5810 (Fedora 42) [hardware]
- [ ] Harvest Dell Precision 7960 (RHEL 10.1, harvest only — stays production AI/ML) [hardware]
- [ ] Harvest Surface Pro 9 (Windows 11 Pro) [hardware]
- [ ] MBP 2015: add WiFi NVRAM txt file for full 5GHz channel support (optional) [repo+hardware]
- [ ] MBP 2015: consider blacklisting thunderbolt module to save ~2W idle power [repo+hardware]

## Completed
- [x] Audit XPS 9510 + MBP 2015 install scripts for orphaned files (XPS clean, MBP needs work)
- [x] SP6: fix 6 install bugs — GRUB defaults, WiFi power save, LightDM HiDPI staging, ccache, ACPI_DPTF, local.d scripts
- [x] Rename local directory ~/ai/gentoo_dell_xps9315 → ~/ai/gentoo-machines (already done)
- [x] Validate SP6 configs: fix filename mismatch bug (8 refs), validate make.conf + kernel_config.sh vs HARDWARE.md
- [x] Build kconfig-lint.sh — static kernel config validator (5 checks, 19K symbols)
- [x] Enhance harvest.sh with 7 new sections (CPU_FLAGS_X86, audio, vendor, EFI, suspend, firmware, -march)
- [x] Build kernel-config-template.sh — skeleton generator from harvest data
- [x] Fix XPS 9315 SND_SOC_SOF_INTEL_TOPLEVEL bug (bool, not tristate) — caught by kconfig-lint
- [x] MBP 2015: add installkernel with grub USE flag (auto grub-mkconfig on make install)
- [x] Run kconfig-lint against MBP 2015 / SP6 — 0 FAILs on both (WARNs/INFOs only, kernel version diffs)
- [x] Rename GitHub repo (gentoo_dell_xps9315 → gentoo-machines) + set description + update 11 files
- [x] Report ipu-bridge double-brace to Gentoo Bugzilla — Bug 970769 (closed: local corruption, not in official sources)
- [x] intel_idle Tiger Lake: investigated upstream — intentional omission, Dell firmware bug, keeping as local patch
- [x] XPS 9510: install unzip, firefox-bin, flatpak + flathub + xdg-desktop-portal-gtk
- [x] XPS 9510: enable RMI4 for Synaptics touchpad (two-finger scroll + palm rejection)
