# Development Log

Development history for the gentoo-machines framework. Records architectural decisions, tooling evolution, and notable fixes across the project lifecycle.

## update-system.sh — Full System Update Workflow

### Rename and Feature Expansion
Renamed `update-kernel.sh` → `update-system.sh` to reflect expanded scope: portage sync, @world packages, config file merging (dispatch-conf), kernel build/install, post-reboot verification, and cleanup.

**Phase order**: `fetch → world → config-update → check → prepare → build → install → reboot → verify → clean` (10 phases).

### eclean-kernel Integration
Added `fetch` and `clean` subcommands. `fetch` handles `emerge --sync`, `emerge gentoo-sources`, auto-detect newest kernel, `eselect kernel set`. `clean` runs `eclean-kernel -n 3` (keep current + 2 rollback) then `grub-mkconfig`. Added `app-admin/eclean-kernel` to shared world.

### Initial Implementation
~970 lines. Auto-detects machine via hostname + DMI fallback. Config strategy: same-series (copy .config + olddefconfig) vs cross-series (defconfig + kernel_config.sh + olddefconfig). Machine registry: xps-9510, mbp-2015, surface-pro-6, nuc11. Patch registry with version-range scoping. NVIDIA handling: source symlink fix + @module-rebuild. State persisted to `/var/lib/kernel-update/`.

## build-kernel-remote.sh Improvements
Removed dracut reference (no initramfs), made KVER dynamic (detected from target's /usr/src/linux symlink), added all production machines to TARGETS.

## Kernel Config Tooling (3 tools)

### kconfig-lint.sh — Static Config Validator (360 lines)
Parses all 1812 Kconfig files into a 19414-symbol TSV database (~2s). 5 checks: `--module` on bool (FAIL), missing parent toggles (WARN), firmware driver =y (WARN), unsatisfied deps (WARN), unknown options (INFO). Immediately caught a real bug: XPS 9315 `SND_SOC_SOF_INTEL_TOPLEVEL` is bool but was set with `--module`, silently disabling SOF audio.

### harvest.sh Enhancements (+263 lines, 15 sections total)
Sections 9-15: CPU_FLAGS_X86 via cpuid2cpuflags, audio subsystem (SOF vs HDA), platform vendor (DMI classification), boot type (EFI/BIOS/Secure Boot), suspend capabilities, loaded firmware mapping, GCC -march suggestion.

### kernel-config-template.sh — Skeleton Generator (1279 lines)
Parses harvest log to auto-detect CPU, GPU, WiFi (8 vendors), audio, storage, platform (6 vendors), Ethernet, Thunderbolt, ISH, cameras. Generates 26-phase kernel_config.sh and auto-runs kconfig-lint.

## MBP 2015 Install Scripts
Upgraded to gold standard: 13-phase chroot install (part3), complete staging + fstab generation (part2), zram ZSTD fix.

## Surface Pro 6

### HiDPI Scaling (150% / 144 DPI)
2736x1824 PixelSense display (267 PPI). LightDM login: `xserver-command=X -dpi 144` + display-setup script. XFCE: Xft/DPI=144, cursor size 36, xrandr autostart. restore-desktop.sh auto-detects Surface via DMI.

### First Boot
All 63 world packages installed. Desktop restore (keybindings, panels, PipeWire, displays), system restore (elogind, ACPI lid, LightDM, touchpad, KSM).

### Config Validation
Fixed critical filename mismatch bug (8 refs): `kernel_config_surface_pro6.sh` → `kernel_config.sh`. Fixed stale `-march=kabylake` → `-march=skylake`. Validated make.conf and kernel_config.sh against HARDWARE.md.

## XPS 9510

### Touchpad Fix
Enabled RMI4 subsystem (RMI4_CORE, RMI4_I2C, RMI4_SMB, RMI4_F11, RMI4_F12, RMI4_F30) and HID_RMI. Synaptics touchpad was falling back to generic HID without these — no two-finger scrolling, poor palm rejection.

### Live System Verification
Applied live-fixes.sh: CPU_FLAGS_X86 (31 flags, 10 more than initially predicted), INPUT_DEVICES=libinput, ccache on /data, package.env for 6 large packages, 24G portage tmpfs, fastfetch. @world rebuild: 26 packages with new CPU_FLAGS_X86. Kernel config dogfooding found and fixed 5 issues (parent toggles, bool vs tristate).

## Upstream Investigations

### intel_idle Tiger Lake
Traced full git history of `intel_idle_ids[]` in upstream kernel. CML/ICL-client/TGL/RKL were never in the table (not removed — never merged). Rafael Wysocki deliberately stopped adding client CPUs after Kaby Lake (Dec 2019), relying on ACPI `_CST` fallback. Root cause is Dell BIOS only exposing 3 of 8 C-states. **Decision**: keep as local patch only — LKML submission not viable.

### ipu-bridge Double-Brace
Filed [Bug 970769](https://bugs.gentoo.org/970769) on Gentoo Bugzilla. Closed: local filesystem corruption, not present in official sources.

## MBP installkernel Fix
Added `sys-kernel/installkernel grub` to package.use — now matches XPS 9510/9315/SP6 pattern (auto grub-mkconfig on `make install`).

## Machine Status

| Machine | Status |
|---------|--------|
| Dell XPS 15 9510 | Production |
| MacBook Pro 12,1 (2015) | Production |
| Surface Pro 6 | Production |
| Dell XPS 13 9315 | Production (config maintained) |
| Dell Precision T5810 | Built (awaiting first boot) |
| Intel NUC11TNBi5 | Config ready |
| ASRock B550 / Ryzen 9 5950X | Planned |
| Dell Precision 7960 | Reference only |
| Surface Pro 9 | Planned |
