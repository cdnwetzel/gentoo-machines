# Backlog

## Medium Priority — Kernel Config

(none — all XPS 9510 kernel config items resolved)

## Medium Priority — Hardware Tasks (require physical access)

- [ ] Install Gentoo on NUC11 — configs ready, follow INSTALL.md [hardware]
- [ ] Unify git identity on NUC11 + Precision 7960 [hardware]
- [ ] Test USB-C hub (Anker 7-in-1) on XPS 9510 — HDMI + USB 3.0 devices [hardware]
- [ ] Test clamshell mode on XPS 9510 with AOC 34" external [hardware]

## Medium Priority — New Tool Candidates

- [ ] **Unified install script generator**: `tools/generate-install.sh <machine> <base-machine>` — create all 3 part scripts from harvest data + feature detection [repo]
- [x] **Machine feature profile**: tools/machine-profile.sh — shared library, 30+ variables, sourced by kernel-config-template.sh [repo]

## Parked

- [ ] Evaluate kernel 7.x upgrade — 6.18 LTS covers all machines until Dec 2027. Revisit when 7.x LTS declared + NVIDIA driver support confirmed (likely late 2027). [all machines]

## Low Priority

- [ ] Harvest ASRock B550 / Ryzen 9 5950X (Fedora 42) [hardware]
- [ ] Harvest Surface Pro 9 (Windows 11 Pro) [hardware]
- [ ] All machines: consider `CONFIG_SECURITY_LOCKDOWN_LSM=y` for defense-in-depth [repo]

## Completed

### Session 2026-03-19
- [x] SP6: fix WiFi resume after s2idle — pre-suspend module unload + post-resume reload + NM cycling
- [x] SP6: remove bogus mwifiex driver_mode=0x3, NM-only powersave
- [x] Precision 7960: harvest via SSH + HARDWARE.md (reference only)
- [x] NUC11: fix make.conf $(nproc) — hardcoded -j8 -l8
- [x] harvest.sh: fix -march for Sapphire Rapids + 6 other CPU models
- [x] harvest.sh: Section 3 expansion (SMBIOS, DMI processor, memory layout)
- [x] harvest.sh: Section 16 CPU Topology, Section 17 Power & Performance
- [x] harvest.sh: Ventoy/live USB boot media detection
- [x] deep_harvest.sh: nvidia-smi + driver version, firmware sysfs fallback
- [x] kernel-config-template.sh: power profile (desktop=PERFORMANCE, laptop=SCHEDUTIL)
- [x] kernel-config-template.sh: multi-GPU count, SATA vs NVMe boot detection
- [x] Install scripts: root checks (8 scripts), dispatch-conf (4 scripts)
- [x] Install scripts: blkid UUID validation, stage3 auto-discovery from mirror
- [x] tools/verify-install.sh: standalone post-reboot deep verification

### Session 2026-03-31
- [x] XPS 9510: enable NVME_HWMON in kernel_config.sh + rebuild (POWER_SUPPLY_HWMON, THERMAL_HWMON, INTEL_RAPL, SCHED_AUTOGROUP, BLK_DEV_THROTTLING were already set)
- [x] XPS 9510: update NVIDIA driver version refs 590.48→595.58.03 across docs
- [x] Disable tap-to-click / tap-to-drag in shared touchpad config (accidental input)

### Prior sessions
- [x] Execute Surface Pro 6 Gentoo install
- [x] Post-install SP6 verification: WiFi, display, audio, zram, brightness, GPU
- [x] SP6: fix overnight battery drain — optimized s2idle + WiFi resume hook
- [x] SP6: fix 6 install bugs, validate configs, wire disable-wakeup, add powertop
- [x] SP6: sysctl tuning, PERF_EVENTS_INTEL_RAPL, SCHED_AUTOGROUP, KSM
- [x] MBP 2015: upgrade install scripts, hibernate setup, HiDPI, restore scripts
- [x] MBP 2015: power tuning (thermald, brcmfmac power_save, sysctl, powertop)
- [x] MBP 2015: kernel config (SCHED_AUTOGROUP, SCHEDUTIL, KSM, CPU_FREQ_STAT)
- [x] MBP 2015: FaceTime camera — closed (high-maintenance, not worth it)
- [x] XPS 9510: migrate kernel 6.12 → 6.18 LTS
- [x] XPS 9510: hibernate setup, battery thresholds, NVMe APST, sysctl tuning
- [x] XPS 9510: install unzip, firefox-bin, flatpak, RMI4 touchpad
- [x] Precision T5810: harvest + configs + install scripts + 13-phase build (2026-03-11)
- [x] Build kconfig-lint.sh, kernel-config-template.sh, enhance harvest.sh
- [x] Rename repo, restore GitHub PAT to VTOYEFI USB
- [x] Report ipu-bridge bug (Gentoo #970769), investigate intel_idle Tiger Lake
