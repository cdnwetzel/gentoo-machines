# Backlog

## Medium Priority — Kernel Config

(none — all XPS 9510 kernel config items resolved)

## Medium Priority — Hardware Tasks (require physical access)

- [ ] **T5810 GPU upgrade**: Replace 2x GTX 1050 Ti with 1x RTX A1000 8GB (hand-me-down from 7960) [hardware]
  - Remove Pascal cards, install A1000, migrate nvidia-drivers 580.xx → 595.x+, enable kernel-open
  - Update: kernel_config.sh, package.accept_keywords, package.use, HARDWARE.md, make.conf
- [ ] Install Gentoo on NUC11 — configs ready, follow INSTALL.md [hardware]
- [ ] Unify git identity on NUC11 + Precision 7960 [hardware]
- [ ] Test USB-C hub (Anker 7-in-1) on XPS 9510 — HDMI + USB 3.0 devices [hardware]
- [ ] Test clamshell mode on XPS 9510 with AOC 34" external [hardware]

## Medium Priority — New Tool Candidates

- [ ] **Nearest-base suggester for config generation**: extend `generate-config.sh` / `generate-install.sh` (or add a `tools/suggest-base.sh` helper) that scores every existing machine in the library against a new machine's harvest using `machine-profile.sh` features (CPU vendor/march, GPU topology, WiFi driver, platform vendor, chassis type, storage mix) and prints a ranked list of the closest 3 matches. Goal: make onboarding accessible — the user no longer has to know which machine is "closest" before running the generators. Stretch: auto-feed the top match as the default `<base-machine>` arg. [repo]

- [ ] **Identify deficiencies in hardware coverage** (scope: x86/x64 Intel + AMD only — no ARM, Apple Silicon, or non-x86 mobile). Inventory what's blocking the repo from supporting nearly any mainstream Intel/AMD machine and keep the list current as hardware lands. Current fleet covers Intel (Broadwell through Sapphire Rapids, Jasper Lake/Tremont) + AMD Zen 3, Intel iGPU + NVIDIA (Pascal through Ampere), iwlwifi/brcmfmac/mwifiex, EFI boot, Dell/Apple/Surface/generic platforms. Known gaps, ranked by real-world prevalence on x86:

  **Tier 1 — highest impact (most real-world machines blocked today):**
  - **AMD GPU** (Radeon iGPU on Ryzen APUs + discrete Radeon). `machine-profile.sh` detects `HAS_AMD_GPU` but no reference machine exists; no `VIDEO_CARDS="amdgpu radeonsi"` pattern, no `amdgpu` firmware wiring in any `kernel_config.sh`. Blocks every Ryzen APU laptop (7040/8040 series) and AMD gaming desktop without NVIDIA.
  - **Lenovo / HP / ASUS platform drivers**. Profile has `PLATFORM=lenovo|hp|asus` hooks but no machine exercises them. No `THINKPAD_ACPI` / `HP_WMI` / `ASUS_WMI` enabled in any kernel config, no per-vendor ACPI workarounds, no TrackPoint/fingerprint/charge-threshold patterns. ThinkPads are arguably the most common Linux laptop.
  - **Realtek PCIe WiFi** (`rtw88`, `rtw89`). Common in budget and newer Lenovo/ASUS/Acer laptops. Profile detects the driver but kernel-config template and install scripts have no firmware verification block for it.

  **Tier 2 — moderate:**
  - **MediaTek WiFi** (`mt76`). Framework laptop 16, some AMD boards.
  - **Qualcomm Atheros** (`ath11k`, `ath12k`). Premium laptops (Samsung Galaxy Book), newer Dells.
  - **eMMC storage** (`MMC_SDHCI` driver path, distinct from NVMe). Low-end laptops, chromebooks.
  - **AMD-specific extras**: `amd-pstate-epp`, GPU reset handling for APUs, hybrid `amdgpu` + discrete NVIDIA on Ryzen laptops.

  **Tier 3 — niche but rising:**
  - **Steam Deck / handheld form factor** (AMD APU + gamepad HID + TDP control).
  - **Intel Arc discrete GPU** (`VIDEO_CARDS="intel iris xe"` for DG2).
  - **Intel VMD / RAID storage** (7960 has it but its install is reference-only — pattern unproven).
  - **Legacy BIOS boot**. All current `part1`/`part3` scripts hardcode EFI.
  - **Secure Boot enrollment** (MOK). Currently assumed disabled.

  **Realistic path to close Tier 1** (no AMD GPU or AMD laptop hardware currently accessible): two tracks in parallel.
  1. **Generator-side coverage** (doable today, no new hardware): extend `kernel-config-template.sh` and `generate-install.sh` to emit correct AMD-GPU / Lenovo-platform / Realtek-WiFi blocks from harvest data alone. `machine-profile.sh` already sets the flags; the templates need feature gates for `amdgpu`/`radeonsi` in `VIDEO_CARDS`, `THINKPAD_ACPI`/`HP_WMI`/`ASUS_WMI` in kernel config, and `rtw88`/`rtw89` firmware verification in part3. Someone with the hardware could run the generators and get a working install without us touching their config.
  2. **Community-contributed harvests**: document the contribution flow clearly (run `harvest.sh` + `deep_harvest.sh`, open a PR with the two logs and the generated configs under `machines/<new-name>/`). Each landed contribution becomes a reference for nearest-base suggester scoring.

  Aspirational: if AMD Ryzen laptop access becomes available later (ideally a Ryzen ThinkPad — covers AMD CPU + AMD GPU + Lenovo platform in one machine), first-party reference configs would also slot in via the existing onboarding flow. [repo, hardware]
- [x] **Unified install script generator**: `tools/generate-install.sh <machine> <base> <harvest-dir>` — generates all 3 part scripts from harvest section 8 + machine-profile.sh feature gates (2026-04-16) [repo]
- [x] **Machine feature profile**: tools/machine-profile.sh — shared library, 30+ variables, sourced by kernel-config-template.sh [repo]

## Parked

- [ ] Evaluate kernel 7.x upgrade — 6.18 LTS covers all machines until Dec 2027. Revisit when 7.x LTS declared + NVIDIA driver support confirmed (likely late 2027). [all machines]

## Low Priority

- [x] Harvest ASRock B550 / Ryzen 9 5950X — installed Gentoo, configs trued up (2026-04-16) [hardware]
- [ ] Harvest Surface Pro 9 (Windows 11 Pro) [hardware]
- [ ] All machines: consider `CONFIG_SECURITY_LOCKDOWN_LSM=y` for defense-in-depth [repo]

## Completed

### Session 2026-04-27 (mid-OptiPlex install)
- [x] **Username prompt during install**: `tools/generate-install.sh:743` no longer hardcodes `USERNAME="chris"` — prompts with `chris` as default. Swept all 7 machine `gentoo_install_part3_chroot.sh` scripts: 4 had `chris` inlined directly into useradd/passwd/verify lines (mbp-2015, xps-9510, precision-t5810, surface-pro-6, asrock-b550); 2 already used `$USERNAME` constant (beelink-minis, optiplex-3090) — all now share the prompt pattern.
- [x] **SOF kernel config: bug class eradicated across the repo**. Cause: `tools/kernel-config-template.sh` SOF block contained 3 invalid symbols (`SND_SOC_SOF_PCI_INTEL_TGL`, `SND_SOC_SOF_INTEL_PCI`, plus a bool-vs-tristate misuse on `SND_SOC_SOF_INTEL_TOPLEVEL`) that propagated to 6 machine `kernel_config.sh` files. Effect was masked because legacy `snd_hda_intel` HDA path silently carried audio. Fixes:
  - Template now emits proper hierarchy: `SND_SOC_SOF_TOPLEVEL` (parent gate, bool) → `SND_SOC_SOF_INTEL_TOPLEVEL` (Intel subgroup, bool) → `SND_SOC_SOF_PCI` (PCI bus, tristate) → chip-specific `SND_SOC_SOF_<CHIPNAME>` (auto-selects family + COMMON + SOF).
  - Chip selection driven by new `SOF_CHIP` variable in `tools/machine-profile.sh` mapped from `GCC_MARCH` (CometLake/AlderLake/TigerLake/JasperLake/etc.). Disambiguates `skylake` → KabyLake by CPU model number.
  - Added `SND_HDA_CODEC_REALTEK` to template's SOF branch (analog out via HDA-Link).
  - Per-machine sweep: optiplex-3090 + xps-9315 → proper enable hierarchy; xps-9510 + surface-pro-6 + asrock-b550 + beelink-minis + precision-t5810 → cleaner `--disable SND_SOC_SOF_TOPLEVEL` (kills entire subtree at parent).
- [x] **kconfig-lint integrated into install flow**. `tools/generate-install.sh` part2 now stages `kconfig-lint.sh` into `${CONFIG_STAGE}/`; part3 phase 2 runs lint after `kernel_config.sh` and prompts to abort on FAIL. Updated `kconfig-lint.sh:192` `FW_DRIVERS` watchlist: removed stale `SND_SOC_SOF_PCI_INTEL_TGL/MTL` (no longer in mainline), added 13 chip-specific SOF symbols.

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
