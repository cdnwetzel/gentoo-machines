# Checkpoint - 2026-02-27

## Session Summary

Completed MacBook Pro 2015 setup: audio, hotkeys, kernel tuning, battery fix, zram, and full system audit. Fixed zram-init config bug affecting both MBP 2015 and Surface Pro 6 install scripts. All MBP 2015 config files saved to repo.

## What Was Done

### MacBook Pro 2015 — Audio & Hotkeys
- Installed `alsa-utils`, confirmed PipeWire 1.4.10 + WirePlumber already running
- Created PipeWire autostart desktop entry
- Installed `acpilight` for display brightness control, added chris to `video` group
- Created `setup-hotkeys.sh` for XFCE Fn row: F1/F2 brightness, F5/F6 kbd backlight, F10 mute
- Added xfce4-pulseaudio-plugin to top panel (handles F11/F12 volume natively)
- Fixed DBUS session detection for xfconf-query (auto-detect from xfce4-session /proc/environ)
- Set udev permissions for intel_backlight and smc::kbd_backlight (video group write)

### MacBook Pro 2015 — Kernel Rebuild
- Enabled `CONFIG_ACPI_SBS=m` — Apple Smart Battery System (fixed empty BAT0)
- Enabled `CONFIG_TRANSPARENT_HUGEPAGE=y` (always) — performance tuning
- Enabled `CONFIG_LRU_GEN=y` + `CONFIG_LRU_GEN_ENABLED=y` — MGLRU
- Enabled `CONFIG_ZRAM_BACKEND_ZSTD=y`, `CONFIG_CRYPTO_ZSTD=y` — zstd for zram/zswap
- Switched `CONFIG_ZSWAP_COMPRESSOR_DEFAULT` from lzo to zstd
- Disabled `CONFIG_NUMA` — single socket laptop
- Kernel build #5 deployed, verified after reboot

### MacBook Pro 2015 — System Setup
- Installed `lm-sensors`, `usbutils`, `acpid`, `zram-init`
- Enabled services: `alsasound` (boot), `acpid` (default), `zram-init` (boot), `acpilight` (boot)
- Created `/etc/local.d/disable-wakeup.start` — prevents immediate resume from suspend (LID0/XHC1)
- Deployed `zram-init.conf` — 4GB zstd compressed swap

### zram-init Config Bug Fix (MBP 2015 + Surface Pro 6)
- Root-caused zram-init silently doing nothing: `num_devices="1"` is REQUIRED — `ZramSanityCheck` returns false without it and `start()` exits rc 0
- Also fixed `comp0` → `algo0` (correct variable name per init script's `ZramIgnore` function)
- Fixed in MBP 2015 `zram-init.conf`, Surface Pro 6 `gentoo_install_part3_chroot.sh` and `INSTALL_PREFLIGHT.md`

### GRUB Boot Fix
- `make install` on MBP writes to `/boot/vmlinuz` (no version suffix), but GRUB looks for `vmlinuz-*`
- Fix: `cp /boot/vmlinuz /boot/vmlinuz-6.18.12-gentoo` then `dracut --force` and `grub-mkconfig`
- Note for future: ensure installkernel copies with version suffix, or always run grub-mkconfig after

### Repo Setup
- Created `machines/mbp-2015/` with 14 files: .config, make.conf, fstab, grub, world, mbpfan.conf, zram-init.conf, disable-wakeup.start, setup-hotkeys.sh, package.accept_keywords, package.use, HARDWARE.md
- Updated CLAUDE.md: added MBP 2015 to machine table, details section, and file listing
- Full system audit documented in HARDWARE.md

### Research: MBP 2015 on Gentoo
- FaceTime camera needs out-of-tree `facetimehd` driver + firmware extraction (low priority)
- WiFi .txt/.clm_blob firmware files missing (non-fatal, may limit some 5GHz channels)
- SD card reader may disappear after suspend (xhci_hcd quirks=0x80 workaround)
- Thunderbolt 2 draws ~2W idle — consider blacklisting if unused
- HiDPI: 2x scaling available via Gdk/WindowScalingFactor if needed

## Previous Sessions (Abbreviated)

### 2026-02-27: Surface Pro 6 + MBP 2015 Repo Integration
- Imported SP6 install scripts and MBP build artifacts from Ventoy USB

### 2026-02-22: XPS 9510 to Production
- Full production: kernel tuning, PipeWire, Dell hotkeys, SSTP VPN, Remmina, nvidia fixes

### 2026-02-25: MacBook Pro 2015 Initial Production
- MBP 12,1 to production: kernel 6.18.12, Apple HW, mbpfan, XFCE desktop

## Current State

### Machine Status
| Machine | Status | Next Step |
|---------|--------|-----------|
| Dell XPS 13 9315 | Production (Gentoo) | Maintenance only |
| Intel NUC11TNBi5 | Config ready | Boot live USB, follow INSTALL.md |
| Dell XPS 15 9510 | Production (Gentoo) | Test USB-C hub, clamshell mode |
| MacBook Pro 12,1 (2015) | **Production (Gentoo) — VERIFIED** | Maintenance only |
| Surface Pro 6 | **Ready to install** | Run install scripts from Ventoy |
| ASRock B550 / Ryzen 9 5950X | Placeholder | Harvest on Fedora 42 |
| Dell Precision T5810 | Placeholder | Harvest on Fedora 42 |
| Dell Precision 7960 | Placeholder | Harvest on RHEL 10.1 |
| Surface Pro 9 | Placeholder | Harvest on Windows 11 Pro |

### MBP 2015 Verification Commands
```bash
uname -a                                                    # Kernel #5, PREEMPT_DYNAMIC
cat /sys/class/power_supply/BAT0/capacity                   # Battery %
cat /sys/kernel/mm/transparent_hugepage/enabled              # [always]
cat /sys/kernel/mm/lru_gen/enabled                          # 0x0007
swapon --show                                               # zram 4G zstd
cat /sys/block/zram0/comp_algorithm                         # [zstd]
sensors                                                     # Thermals (needs lm-sensors)
speaker-test -c2 -t wav                                     # Audio
# F1/F2 brightness, F5/F6 kbd backlight, F10-F12 volume    # Hotkeys (manual)
```

## Next Steps (Priority Order)

1. **Execute Surface Pro 6 install** — boot Ventoy, run part1 → part2 → part3
2. **Test USB-C hub on XPS 9510** — Anker 7-in-1, HDMI + USB 3.0
3. **Test clamshell mode on XPS 9510** — AOC 34" external
4. **Install Gentoo on NUC11** — follow INSTALL.md
5. **Harvest remaining machines** — B550, T5810, 7960
