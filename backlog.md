# Backlog

## High Priority
- [ ] Execute Surface Pro 6 Gentoo install (scripts ready, ~3.5 hours)
- [ ] Post-install SP6 verification: WiFi, display, audio, zram, brightness, GPU

## Medium Priority
- [ ] Unify git identity across all dev machines — `git config --global user.name "Chris Wetzel"` + `git config --global user.email "chris@cwetzel.com"` on: XPS 9510 (Gentoo), MBP 2015 (Gentoo), NUC11 (Ubuntu), Mac Studio (macOS), Precision 7960 (RHEL 10.1), Surface Pro 6 (post-install)
- [ ] Install Gentoo on NUC11 — follow INSTALL.md
- [ ] Test USB-C hub (Anker 7-in-1) on XPS 9510 — HDMI + USB 3.0 devices
- [ ] Test clamshell mode on XPS 9510 with AOC 34" external
- [ ] MBP 2015: investigate FaceTime camera (facetimehd out-of-tree driver)

## Low Priority
- [ ] Rename local directory ~/ai/gentoo_dell_xps9315 → ~/ai/gentoo-machines
- [ ] Harvest ASRock B550 / Ryzen 9 5950X (Fedora 42)
- [ ] Harvest Dell Precision T5810 (Fedora 42)
- [ ] Harvest Dell Precision 7960 (RHEL 10.1, harvest only — stays production AI/ML)
- [ ] Harvest Surface Pro 9 (Windows 11 Pro)
- [ ] MBP 2015: add WiFi NVRAM txt file for full 5GHz channel support (optional)
- [ ] MBP 2015: consider blacklisting thunderbolt module to save ~2W idle power

## Completed
- [x] Validate SP6 configs: fix filename mismatch bug (8 refs), validate make.conf + kernel_config.sh vs HARDWARE.md
- [x] Build kconfig-lint.sh — static kernel config validator (5 checks, 19K symbols)
- [x] Enhance harvest.sh with 7 new sections (CPU_FLAGS_X86, audio, vendor, EFI, suspend, firmware, -march)
- [x] Build kernel-config-template.sh — skeleton generator from harvest data
- [x] Fix XPS 9315 SND_SOC_SOF_INTEL_TOPLEVEL bug (bool, not tristate) — caught by kconfig-lint
- [x] MBP 2015: add installkernel with grub USE flag (auto grub-mkconfig on make install)
- [x] Run kconfig-lint against MBP 2015 / SP6 — 0 FAILs on both (WARNs/INFOs only, kernel version diffs)
- [x] Rename GitHub repo (gentoo_dell_xps9315 → gentoo-machines) + set description + update 11 files
- [x] Report ipu-bridge double-brace to Gentoo Bugzilla — Bug 970769
- [x] intel_idle Tiger Lake: investigated upstream — intentionally omission, Dell firmware bug, keeping as local patch
- [x] XPS 9510: install unzip, firefox-bin, flatpak + flathub + xdg-desktop-portal-gtk
