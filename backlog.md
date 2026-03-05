# Backlog

## High Priority
- [x] Execute Surface Pro 6 Gentoo install (scripts ready, ~3.5 hours) [hardware]
- [x] Post-install SP6 verification: WiFi, display, audio, zram, brightness, GPU [hardware]
- [x] MBP 2015: upgrade install scripts to XPS/SP6 standard — 9 orphaned files, filename mismatch, zram algo inconsistency [repo]
- [x] XPS 9510: migrate kernel 6.12 → 6.18 LTS — use `tools/update-system.sh all` (cross-series, will use kernel_config.sh) [hardware]

## Medium Priority — Kernel & Power Optimization (All Machines)

### Cross-Machine Kernel Config (next rebuild)
- [x] Enable `CONFIG_SCHED_AUTOGROUP=y` on MBP 2015 + SP6 — XPS 9510 still pending [repo]
- [x] Enable `CONFIG_KSM=y` on MBP 2015 + SP6 [repo]
- [ ] Enable `CONFIG_NVME_HWMON=y` on XPS 9510 — NVMe thermal monitoring (SP6 done) [repo]
- [ ] Enable `CONFIG_POWER_SUPPLY_HWMON=y` on XPS 9510 — battery monitoring via hwmon (MBP + SP6 done) [repo]
- [ ] Enable `CONFIG_THERMAL_HWMON=y` on XPS 9510 — thermal zone sysfs export (MBP + SP6 done) [repo]
- [x] Change `CONFIG_CPU_FREQ_DEFAULT_GOV` to SCHEDUTIL on MBP 2015 — XPS 9510 still pending [repo]
- [ ] Enable `CONFIG_INTEL_RAPL=y` on XPS 9510 — currently only RAPL_CORE enabled [repo]
- [x] Enable `CONFIG_PERF_EVENTS_INTEL_RAPL=m` on SP6 — power profiling per-domain [repo]
- [ ] Fix XPS 9510 kernel_config.sh mismatches — `SCHED_AUTOGROUP`, `BLK_DEV_THROTTLING` in script but disabled in .config [repo]

### XPS 9510 Power & Battery
- [x] XPS 9510: run `shared/hibernate-setup.sh` — 31GB swap file + GRUB resume + low-battery monitor [hardware]
- [ ] XPS 9510: add Dell battery charge thresholds to tlp.conf — `START_CHARGE_THRESH_BAT0=40` / `STOP_CHARGE_THRESH_BAT0=80` [repo+hardware]

### MBP 2015 Power & Tuning
- [x] MBP 2015: install `sys-power/thermald` — CPU freq management via RAPL [hardware]
- [x] MBP 2015: create `/etc/modprobe.d/brcmfmac.conf` with `power_save=1` — saves 2-5W [repo+hardware]
- [x] MBP 2015: create sysctl tuning file — swappiness, dirty_ratio, sched_autogroup, TCP [repo]
- [x] MBP 2015: install `sys-power/powertop` — profile actual power draw after reboot [hardware]
- [x] MBP 2015: investigate Apple SMC battery charge threshold — not supported (no charge_control_* sysfs) [hardware]
- [x] MBP 2015: kernel rebuild needed — repo .config has SCHED_AUTOGROUP, SCHEDUTIL governor, CPU_FREQ_STAT but running kernel doesn't [hardware]

### SP6 Power & Tuning
- [ ] SP6: re-test WiFi power save on kernel 6.18 — currently disabled (`driver_mode=0x3`, NM `powersave=2`) due to old Marvell hang bugs [hardware]
- [x] SP6: create sysctl tuning file — swappiness, dirty_ratio, sched_autogroup, TCP tuning [repo]
- [x] SP6: wire `disable-wakeup.start` to `/etc/local.d/` — added to part3 phase 11 [repo]
- [x] SP6: add `sys-power/powertop` to world file + `CPU_FREQ_STAT` to kernel config [repo]

## Medium Priority — Other
- [x] MBP 2015: investigate FaceTime camera (facetimehd out-of-tree driver) — closed: works but high-maintenance (manual rebuild every kernel update, no ebuild, suspend issues), not worth it [repo+hardware]
- [ ] Install Gentoo on NUC11 — follow INSTALL.md [hardware]
- [ ] Unify git identity across remaining dev machines — ~~XPS 9510~~, ~~Surface Pro 6~~, ~~MBP 2015~~, NUC11, Precision 7960 [hardware]
- [ ] Test USB-C hub (Anker 7-in-1) on XPS 9510 — HDMI + USB 3.0 devices [hardware]
- [ ] Test clamshell mode on XPS 9510 with AOC 34" external [hardware]

## Low Priority
- [ ] Harvest ASRock B550 / Ryzen 9 5950X (Fedora 42) [hardware]
- [ ] Harvest Dell Precision T5810 (Fedora 42) [hardware]
- [ ] Harvest Dell Precision 7960 (RHEL 10.1, reference only — stays production AI/ML) [hardware]
- [ ] Harvest Surface Pro 9 (Windows 11 Pro) [hardware]
- [x] MBP 2015: WiFi NVRAM txt — not needed, 5GHz works (ch153, 540Mbit/s), dmesg warnings cosmetic [repo+hardware]
- [x] MBP 2015: blacklist thunderbolt module to save ~2W idle power [repo+hardware]
- [ ] All machines: consider `CONFIG_SECURITY_LOCKDOWN_LSM=y` for defense-in-depth [repo]
- [ ] XPS 9510: add NVMe APST latency tuning (`nvme_core.default_ps_max_latency_us=5000`) [repo]
- [ ] XPS 9510: add `vm.max_map_count=262144` to sysctl for PyTorch/CUDA large models [repo]

## Completed
- [x] MBP 2015: hibernate setup — 16GB swap file, GRUB resume params, low-battery cron monitor (5%)
- [x] MBP 2015: HiDPI setup (150%/144 DPI) — Xresources, xrandr autostart, LightDM, greeter, GRUB_GFXMODE
- [x] MBP 2015: run restore-desktop.sh + restore-system.sh + setup-hotkeys.sh
- [x] Add battery plugin (plugin-22) to shared xfce4-panel.sh
- [x] Update restore-system.sh to use machine-specific LightDM/greeter for HiDPI machines
- [x] Fix hibernate-setup.sh: crontab -l fails under set -e with no existing crontab
- [x] MBP 2015: add xrandr + xhost to world file
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
