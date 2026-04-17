# Changelog

Significant development milestones for the gentoo-machines framework, ordered most recent first. For day-to-day work, see `backlog.md`.

## 2026-04 — Install Script Generator + Cronie Baseline

- **`tools/generate-install.sh`**: new generator for the three install scripts (`part1`/`part2`/`part3_chroot`), driven by `tools/machine-profile.sh` feature flags and harvest section 8 block-device parsing. Feature-gated output for NVIDIA, Intel microcode, Bluetooth service, laptop TLP, Apple mbpfan, Surface HiDPI, Dell EFI fallback, and desktop always-on elogind drop-ins.
- **`tools/test-generate-install.sh`**: 42-check regression harness covering three synthetic fixtures (`intel-sata-desktop`, `amd-nvme-nvidia-desktop`, `apple-broadwell-laptop`). Each fixture asserts both presence and absence of feature-gated blocks.
- **Cronie baseline**: added `sys-process/cronie` to `shared/world` and all machine worlds, plus the service to every part3 install script. `shared/low-battery-hibernate.sh` and `shared/fstrim-weekly` assumed cron was available; now it universally is.
- **`machine-profile.sh` bugfix**: `NVIDIA_GPU_COUNT=$(grep -c ... || echo 1)` was capturing both the grep "0" and the fallback "1" on no-match, producing an integer-test error downstream.

## 2026-04 — Beelink MINI S Production

- Installed Gentoo on Beelink MINI S (Celeron N5095A, Jasper Lake). 4C/4T Tremont, no HT, no AVX/AVX2. SATA-only board (no NVMe). Always-on mini-PC — elogind drop-in disables all sleep/suspend handling.
- Renamed directory `beelink-minis-n5095` → `beelink-minis`.
- Forced `performance` CPU frequency governor by disabling kernel alternatives to `powersave`/`schedutil` (no throttling wanted on always-on box).

## 2026-04 — ASRock B550 Production (First AMD)

- Installed Gentoo on ASRock B550 Phantom Gaming-ITX/ax (Ryzen 9 5950X, Zen 3). First AMD platform in the fleet — AMD-specific drivers (`amd-pstate`, `k10temp`, `piix4_smbus`, `ccp`, `edac_mce_amd`) and no Intel i801/MEI/iGPU.
- NVIDIA RTX 3060 Ti (GA104 Ampere) with `kernel-open` USE flag.
- 22-phase `kernel_config.sh`, 3-phase automated install scripts, 46GB portage tmpfs with disk fallback.

## 2026-03 — Precision T5810 Production

- Installed Gentoo on Dell Precision T5810 (Xeon E5-2699v4, 22C/44T, Broadwell-EP). 256GB DDR4 ECC, 2x NVIDIA GTX 1050 Ti (Pascal, `nvidia-drivers` 580.xx legacy branch), Samsung 990 PRO 2TB NVMe. C610/X99 chipset — no LPSS/Pinctrl, I2C via i801 SMBus only.
- Boot media: SABRENT Ventoy USB. part1 script includes absolute device-ID exclusion to protect it.
- Performance-first: C-states disabled in BIOS, `GOV_PERFORMANCE`, always-on workstation.

## 2026-03 — Kernel Config Tooling Suite

- **`tools/kconfig-lint.sh`**: static validator for `kernel_config.sh` scripts. Parses all Kconfig files (~19K symbols, ~2s) and cross-references every `scripts/config` call. Catches 5 classes of silent bug: `--module` on bool options, missing parent toggles, firmware drivers built-in (=y) without initramfs, unsatisfied dependencies, and unknown config symbols (typos/renames).
- **`tools/kernel-config-template.sh`**: auto-generates a 26-phase `kernel_config.sh` from harvest data. Detects CPU, GPU (Intel/NVIDIA/AMD), WiFi (8 vendors), audio (SOF/HDA + codec), storage, platform (Dell/Apple/Surface/Lenovo/HP/ASUS), Ethernet, Thunderbolt, ISH sensors, cameras.
- **`tools/harvest.sh`** expansion: sections 9-17 cover `CPU_FLAGS_X86` via `cpuid2cpuflags`, SOF vs HDA detection, DMI platform classification, EFI/BIOS/Secure Boot, suspend capabilities, loaded firmware, GCC `-march` suggestion, CPU topology, power/performance profile, Ventoy/live-USB boot media detection.

## 2026-03 — `tools/update-system.sh`

- Renamed `update-kernel.sh` → `update-system.sh` to reflect expanded scope. Phase order: `fetch → world → config-update → check → prepare → build → install → reboot → verify → clean`.
- Guided prompted workflow with Y/n/skip at each phase, resumable via `/var/lib/kernel-update/full-progress`. Individual subcommands remain standalone.
- Machine auto-detection (hostname + DMI fallback), patch registry with version-range scoping, config-migration strategy (same-series copies `.config` + `olddefconfig`; cross-series uses `defconfig` + `kernel_config.sh` + `olddefconfig`), `eclean-kernel -n 3` for old-kernel cleanup.
- NVIDIA handling: source symlink fix + `@module-rebuild` on install.

## 2026-02 — Surface Pro 6 Production

- Installed Gentoo on Surface Pro 6 (i5-8250U, Kaby Lake-R). Marvell 88W8897 WiFi (not Intel), 8GB soldered LPDDR3, 2736x1824 PixelSense (150% HiDPI / 144 DPI).
- HiDPI plumbed through LightDM (`xserver-command=X -dpi 144` + display-setup script), XFCE (`Xft/DPI=144`, cursor size 36, xrandr autostart), and GTK greeter. `shared/restore-desktop.sh` auto-detects Surface via DMI.
- WiFi resume reliability: pre-suspend module unload + post-resume reload + NetworkManager cycling via elogind sleep hook; NetworkManager-managed power save (no driver-level `driver_mode` flags).

## 2026-02 — MBP 2015 & XPS 9510 Production Baselines

- **XPS 15 9510**: Tiger Lake-H + NVIDIA RTX 3050 Ti hybrid graphics (PRIME/Optimus), migrated from 6.12 → 6.18 LTS, hibernate + battery thresholds + NVMe APST, RMI4 touchpad enabled, PipeWire audio.
- **MBP 2015**: Broadwell + Apple hardware (applesmc, mbpfan, bcm5974 trackpad, brcmfmac WiFi, CS4208 audio). Power tuning (thermald, brcmfmac `power_save`, sysctl, powertop). `sys-kernel/installkernel` with `grub` USE flag for auto `grub-mkconfig` on `make install`.
- Returned to macOS 12 as a kids' machine — kernel config and install scripts remain in the repo for reference.

## Upstream Investigations

### `intel_idle` Tiger Lake
Traced the full git history of `intel_idle_ids[]` in the upstream kernel. CML, ICL-client, TGL, and RKL were never in the table — not removed, never merged. Rafael Wysocki deliberately stopped adding client CPUs after Kaby Lake (Dec 2019, commit `18734958e9bf`), relying on ACPI `_CST` fallback. The XPS 9510 BIOS exposes only 3 of 8 C-states via `_CST`. Carried as a local patch (`patches/intel_idle-add-tiger-lake.patch`); not submitted to LKML.

### `ipu-bridge` Double-Brace
Filed Gentoo [Bug 970769](https://bugs.gentoo.org/970769). Closed: local filesystem corruption, not present in official sources. Patch retained for reference.

## Machine Status Snapshot

| Machine | Status |
|---------|--------|
| Dell XPS 15 9510 | Production |
| ASRock B550 (Ryzen 9 5950X) | Production |
| Dell Precision T5810 | Production |
| Surface Pro 6 | Production |
| Beelink MINI S | Production |
| Dell XPS 13 9315 | Config maintained (Windows returned) |
| MacBook Pro 12,1 (2015) | Retired — config maintained (macOS kids' machine) |
| Intel NUC11TNBi5 | Config ready — awaiting install |
| Dell Precision 7960 | Reference only (RHEL 10.1 for production AI/ML) |
| Surface Pro 9 | Planned |
