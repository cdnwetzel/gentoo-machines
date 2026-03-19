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
- [ ] Enable `CONFIG_NVME_HWMON=y` on XPS 9510 — NVMe thermal monitoring (SP6 done) [repo] (deferred: machine not available)
- [ ] Enable `CONFIG_POWER_SUPPLY_HWMON=y` on XPS 9510 — battery monitoring via hwmon (MBP + SP6 done) [repo] (deferred: machine not available)
- [ ] Enable `CONFIG_THERMAL_HWMON=y` on XPS 9510 — thermal zone sysfs export (MBP + SP6 done) [repo] (deferred: machine not available)
- [x] Change `CONFIG_CPU_FREQ_DEFAULT_GOV` to SCHEDUTIL on MBP 2015 — XPS 9510 still pending [repo]
- [ ] Enable `CONFIG_INTEL_RAPL=y` on XPS 9510 — currently only RAPL_CORE enabled [repo]
- [x] Enable `CONFIG_PERF_EVENTS_INTEL_RAPL=m` on SP6 — power profiling per-domain [repo]
- [ ] Fix XPS 9510 kernel_config.sh mismatches — `SCHED_AUTOGROUP`, `BLK_DEV_THROTTLING` in script but disabled in .config [repo]

### XPS 9510 Power & Battery
- [x] XPS 9510: run `shared/hibernate-setup.sh` — 31GB swap file + GRUB resume + low-battery monitor [hardware]
- [x] XPS 9510: add Dell battery charge thresholds to tlp.conf — `START_CHARGE_THRESH_BAT0=40` / `STOP_CHARGE_THRESH_BAT0=80` [repo+hardware]

### MBP 2015 Power & Tuning
- [x] MBP 2015: install `sys-power/thermald` — CPU freq management via RAPL [hardware]
- [x] MBP 2015: create `/etc/modprobe.d/brcmfmac.conf` with `power_save=1` — saves 2-5W [repo+hardware]
- [x] MBP 2015: create sysctl tuning file — swappiness, dirty_ratio, sched_autogroup, TCP [repo]
- [x] MBP 2015: install `sys-power/powertop` — profile actual power draw after reboot [hardware]
- [x] MBP 2015: investigate Apple SMC battery charge threshold — not supported (no charge_control_* sysfs) [hardware]
- [x] MBP 2015: kernel rebuild needed — repo .config has SCHED_AUTOGROUP, SCHEDUTIL governor, CPU_FREQ_STAT but running kernel doesn't [hardware]

### SP6 Power & Tuning
- [x] SP6: re-test WiFi power save on kernel 6.18 — closed: removed bogus driver_mode=0x3 (NXP vendor param, ignored by mainline), power save disabled via NM wifi-powersave.conf only [hardware]
- [x] SP6: create sysctl tuning file — swappiness, dirty_ratio, sched_autogroup, TCP tuning [repo]
- [x] SP6: wire `disable-wakeup.start` to `/etc/local.d/` — added to part3 phase 11 [repo]
- [x] SP6: add `sys-power/powertop` to world file + `CPU_FREQ_STAT` to kernel config [repo]
- [x] SP6: fix overnight battery drain — hibernate crashes (KBL i915 + NVMe swap file, 6 attempts, all modes), switched to optimized s2idle: restored PSR + DC states (~1-1.5%/hr), idle action changed to suspend. WiFi resume fixed (2026-03-19): pre-suspend module unload + post-resume reload + NM cycling in elogind hook. Hibernate kept as critical-battery last resort (crash stops drain). [hardware]

## Medium Priority — Other
- [x] MBP 2015: investigate FaceTime camera (facetimehd out-of-tree driver) — closed: works but high-maintenance (manual rebuild every kernel update, no ebuild, suspend issues), not worth it [repo+hardware]
- [ ] Install Gentoo on NUC11 — follow INSTALL.md [hardware] (deferred: machine not available)
- [x] Restore GitHub PAT to VTOYEFI USB — portable git credential store for push from any machine (2026-03-11) [repo]
- [ ] Unify git identity across remaining dev machines — ~~XPS 9510~~, ~~Surface Pro 6~~, ~~MBP 2015~~, NUC11, Precision 7960 [hardware]
- [ ] Test USB-C hub (Anker 7-in-1) on XPS 9510 — HDMI + USB 3.0 devices [hardware]
- [ ] Test clamshell mode on XPS 9510 with AOC 34" external [hardware]

## Medium Priority — Tooling Improvements

### harvest.sh Enhancements
- [ ] Section 3 expansion: full `dmidecode -t bios/system/baseboard/processor/memory` (ECC type, DIMM layout, socket, max turbo, board model, SMBIOS version) [repo]
- [ ] Section 16: BIOS Power Config — C-state status, CPU governor, pstate mode (critical for workstation vs laptop) [repo]
- [ ] Section 17: CPU Topology — NUMA nodes, cache hierarchy, socket count (`lscpu --extended`) [repo]
- [ ] Boot media exclusion: detect and flag Ventoy/live USB drives by device ID or VTOYEFI label [repo]

### deep_harvest.sh Enhancements
- [ ] NVIDIA GPU details: `nvidia-smi -q` if proprietary driver loaded, or parse PCI subsystem vendor [repo]
- [ ] Firmware loading from sysfs: try `/sys/class/firmware/` when dmesg rotates [repo]

### kernel-config-template.sh Enhancements
- [ ] Power profile auto-detect: workstation (no battery, chassis tower) → default GOV_PERFORMANCE [repo]
- [ ] Multi-GPU detection: count NVIDIA GPUs, note in kernel_config.sh header [repo]
- [ ] SATA vs NVMe boot: auto-determine boot drive from harvest data [repo]

### Install Script Improvements
- [ ] Stage3 auto-discovery: auto-discover latest stage3 from mirror directory listing in part2 scripts [repo]
- [ ] Standardize root handling: add root check or sudo prefix across all install scripts [repo]
- [ ] Post-format blkid verification in part1 scripts (lsblk shows stale cache) [repo]
- [ ] Mirror fallback or speed test in part2 scripts [repo]
- [ ] Add `sudo` to verification `ls` commands in part2 [repo]
- [ ] Audit all machines' make.conf for `$(nproc)` usage — Portage doesn't evaluate shell commands [repo]
- [ ] Always include `-wext` with `-wifi` for NetworkManager in wired-only machine configs [repo]
- [ ] Add `gui-libs/libwlembed gtk` to shared/package.use if other XFCE machines need it [repo]
- [ ] Integrate deep sanity check into part3 as replacement for simpler Phase 13 [repo]
- [ ] Add `dispatch-conf` or `etc-update` step to part3 after Phase 6 [repo]

### New Tool Candidates
- [ ] **bios-harvest.sh**: dedicated BIOS/UEFI settings dump (`dmidecode` all types, `efivar --list`, power/thermal, virtualization, boot order) [repo]
- [ ] **Unified install script generator**: `tools/generate-install.sh <machine> <base-machine>` — create all 3 part scripts from harvest data + feature detection [repo]
- [ ] **Machine feature profile**: auto-detect HAS_WIFI, HAS_BLUETOOTH, IS_LAPTOP, HAS_NVIDIA from harvest data → service list, packages, Phase 11 config [repo]
- [ ] **Per-machine world file generator**: start from shared world, subtract inapplicable packages [repo]
- [ ] **Phase 13 auto-generation**: verify list generated from Phase 8 service list, not manually maintained [repo]
- [ ] **Part3 non-interactive mode**: `chpasswd` instead of `passwd`, `--yes`/`--non-interactive` flag [repo]
- [ ] **Part3 depclean phase**: Phase 6.5 for `emerge --depclean` + `@preserved-rebuild` [repo]

## Parked
- [ ] Evaluate kernel 7.x upgrade — NUMA improvements not relevant (all single-socket), NVIDIA 580.xx/590.xx won't support 7.0 at launch, 6.18 LTS covers us until Dec 2027. Revisit when 7.x LTS is declared and hits gentoo-sources ~amd64 (likely late 2027). [all machines]

## Low Priority
- [ ] Harvest ASRock B550 / Ryzen 9 5950X (Fedora 42) [hardware]
- [x] Generate T5810 install scripts (part1/2/3) with SABRENT Ventoy exclusion safety [repo]
- [x] T5810 Gentoo build: all 13 phases complete, deep sanity passed 0 fail/0 warn, ready for first boot (2026-03-11) [hardware]
- [x] Harvest Dell Precision T5810 (Fedora 43 live USB) — harvest + configs generated + sanity-checked 2026-03-11 [hardware]
- [x] Harvest Dell Precision 7960 (RHEL 10.1, reference only — stays production AI/ML) — harvested 2026-03-19 via SSH, HARDWARE.md generated [hardware]
- [ ] Harvest Surface Pro 9 (Windows 11 Pro) [hardware]
- [x] MBP 2015: WiFi NVRAM txt — not needed, 5GHz works (ch153, 540Mbit/s), dmesg warnings cosmetic [repo+hardware]
- [x] MBP 2015: blacklist thunderbolt module to save ~2W idle power [repo+hardware]
- [ ] All machines: consider `CONFIG_SECURITY_LOCKDOWN_LSM=y` for defense-in-depth [repo]
- [x] XPS 9510: add NVMe APST latency tuning (`nvme_core.default_ps_max_latency_us=5000`) [repo]
- [x] XPS 9510: add `vm.max_map_count=262144` to sysctl for PyTorch/CUDA large models [repo]

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
