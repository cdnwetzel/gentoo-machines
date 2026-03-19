# Backlog

## Medium Priority — Kernel Config (deferred: machines not available)

- [ ] XPS 9510: enable `NVME_HWMON`, `POWER_SUPPLY_HWMON`, `THERMAL_HWMON`, `INTEL_RAPL` [repo]
- [ ] XPS 9510: fix kernel_config.sh mismatches — `SCHED_AUTOGROUP`, `BLK_DEV_THROTTLING` in script but disabled in .config [repo]

## Medium Priority — Hardware Tasks (require physical access)

- [ ] Install Gentoo on NUC11 — configs ready, follow INSTALL.md [hardware]
- [ ] Unify git identity on NUC11 + Precision 7960 [hardware]
- [ ] Test USB-C hub (Anker 7-in-1) on XPS 9510 — HDMI + USB 3.0 devices [hardware]
- [ ] Test clamshell mode on XPS 9510 with AOC 34" external [hardware]

## Medium Priority — Tooling Improvements

### harvest.sh Enhancements
- [ ] Section 3 expansion: full `dmidecode -t bios/system/baseboard/processor/memory` (ECC type, DIMM layout, socket, max turbo, board model, SMBIOS version) [repo]
- [ ] Section 16: BIOS Power Config — C-state status, CPU governor, pstate mode [repo]
- [ ] Section 17: CPU Topology — NUMA nodes, cache hierarchy, socket count (`lscpu --extended`) [repo]
- [ ] Boot media exclusion: detect and flag Ventoy/live USB drives by device ID or VTOYEFI label [repo]
- [x] Fix `-march` detection — added Sapphire Rapids, Rocket Lake, Arrow Lake, Lunar Lake, extra variants [repo]

### deep_harvest.sh Enhancements
- [x] NVIDIA GPU details: `nvidia-smi` + driver version if proprietary driver loaded [repo]
- [ ] Firmware loading from sysfs: try `/sys/class/firmware/` when dmesg rotates [repo]

### kernel-config-template.sh Enhancements
- [ ] Power profile auto-detect: workstation (no battery, chassis tower) → default GOV_PERFORMANCE [repo]
- [ ] Multi-GPU detection: count NVIDIA GPUs, note in kernel_config.sh header [repo]
- [ ] SATA vs NVMe boot: auto-determine boot drive from harvest data [repo]

### Install Script Improvements
- [ ] Stage3 auto-discovery: auto-discover latest stage3 from mirror directory listing in part2 scripts [repo]
- [ ] Standardize root handling: add root check or sudo prefix across all install scripts [repo]
- [ ] Post-format blkid verification in part1 scripts (lsblk shows stale cache) [repo]
- [x] Audit all machines' make.conf for `$(nproc)` usage — NUC11 fixed, all others clean [repo]
- [ ] Integrate deep sanity check into part3 as replacement for simpler Phase 13 [repo]
- [ ] Add `dispatch-conf` or `etc-update` step to part3 after Phase 6 [repo]

### New Tool Candidates
- [ ] **Unified install script generator**: `tools/generate-install.sh <machine> <base-machine>` — create all 3 part scripts from harvest data + feature detection [repo]
- [ ] **Machine feature profile**: auto-detect HAS_WIFI, HAS_BLUETOOTH, IS_LAPTOP, HAS_NVIDIA from harvest data → service list, packages, config [repo]

## Parked
- [ ] Evaluate kernel 7.x upgrade — 6.18 LTS covers all machines until Dec 2027. Revisit when 7.x LTS declared + NVIDIA driver support confirmed (likely late 2027). [all machines]

## Low Priority
- [ ] Harvest ASRock B550 / Ryzen 9 5950X (Fedora 42) [hardware]
- [ ] Harvest Surface Pro 9 (Windows 11 Pro) [hardware]
- [ ] All machines: consider `CONFIG_SECURITY_LOCKDOWN_LSM=y` for defense-in-depth [repo]

## Completed
- [x] Execute Surface Pro 6 Gentoo install
- [x] Post-install SP6 verification: WiFi, display, audio, zram, brightness, GPU
- [x] SP6: fix overnight battery drain — optimized s2idle + WiFi resume hook (2026-03-19)
- [x] SP6: WiFi power save cleanup — removed bogus driver_mode, NM-only powersave
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
- [x] Precision 7960: harvest via SSH + HARDWARE.md (2026-03-19, reference only)
- [x] Build kconfig-lint.sh, kernel-config-template.sh, enhance harvest.sh
- [x] Rename repo, restore GitHub PAT to VTOYEFI USB
- [x] Report ipu-bridge bug (Gentoo #970769), investigate intel_idle Tiger Lake
