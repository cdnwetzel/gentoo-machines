# Checkpoint - 2026-02-27

## Session Summary

Integrated Surface Pro 6 and MacBook Pro 2015 build artifacts from Ventoy USB into the repo. Surface Pro 6 is fully harvested, documented, and scripted — ready to execute install. MBP 2015 is in production; missing build scripts and config files were added to the repo for reproducibility.

## What Was Done

### Surface Pro 6 — Full Build Prep Integrated
- Imported complete Surface Pro 6 build directory from `/media/cwetzel/VTOYEFI/surfacepro6/`
- **Hardware**: Intel i5-8250U (Kaby Lake-R), 8GB LPDDR3, 238GB SK hynix NVMe, Intel UHD 620, Marvell 88W8897 WiFi (NOT Intel), Realtek ALC298 audio, Surface Type Cover
- **Known HW defect**: Touchscreen non-functional on this specific unit (hardware, not driver)
- **Target kernel**: 6.18.x gentoo-sources, `-march=skylake` (correct GCC arch for Kaby Lake)
- **Files added to repo** (`machines/surface-pro-6/`):
  - `make.conf` — Skylake march, -j9, 4GB tmpfs
  - `kernel_config.sh` — Programmatic kernel config script (scripts/config based)
  - `package.use`, `package.env`, `portage_env_notmpfs.conf`, `world`
  - `iptsd.conf`, `iptsd-device.conf`, `50-iptsd.rules` — Surface touch/pen input
  - `fedora-reference.config` — Fedora 43 kernel 6.18.8 config for cross-reference
  - `HARDWARE.md` — Complete hardware inventory from 5 harvest rounds
  - `INSTALL_PREFLIGHT.md` — 13-phase install checklist
  - `INSTALL_GOTCHAS.md` — 20 lessons learned from prior builds
  - `EXEC_SEQUENCE.md` — 7-step quick reference
  - `FEDORA_REFERENCE.md` — Config mined from running Fedora
  - `KERNEL_CONFIG_CROSSREF.md` — Kernel config decisions explained
  - `gentoo_install_part1.sh` — Partition + format NVMe
  - `gentoo_install_part2.sh` — Stage3 + config copy + chroot prep
  - `gentoo_install_part3_chroot.sh` — 13-phase one-shot chroot install
- **Status**: Ready to execute. Run part1 → part2 → part3 from Fedora live USB, ~3.5 hours.

### MacBook Pro 2015 — Production Files Integrated
- Imported missing build artifacts from `/media/cwetzel/VTOYEFI/mbp2015/`
- MBP 2015 is running **production** Gentoo (kernel 6.18.12-gentoo)
- **Files added to repo** (`machines/mbp-2015/`):
  - `kernel_config.sh` — Programmatic kernel config (Broadwell + Apple HW)
  - `post_install_setup.sh` — Post-kernel install reference steps
  - `wifi_firmware_fix.sh` — BCM43602 firmware symlink/check script
  - `package.env` — Large package tmpdir override (chromium, firefox, llvm, rust, gcc)
  - `portage_env_notmpfs.conf` — Fallback PORTAGE_TMPDIR to disk
  - `gentoo_install_part1.sh` — Disk partitioning from live USB
  - `gentoo_install_part2.sh` — Stage3 + chroot + build

### Documentation & Repo Updates
- Updated CLAUDE.md with Surface Pro 6 details and new file listings
- Updated backlog.md — marked SP6/MBP harvesting done, added install task
- Updated checkpoint.md (this file)
- Updated auto-memory with SP6 status

## Previous Sessions (Abbreviated)

### 2026-02-22: XPS 9510 to Production
- XPS 15 9510 brought to full production: kernel tuning, PipeWire audio, Dell hotkeys, SSTP VPN, Remmina, USB-C hub, nvidia fixes, intel_idle patch, module-rebuild `env -i` fix
- See git log for detailed phase-by-phase history

### 2026-02-25: MacBook Pro 2015 to Production
- MBP 12,1 brought to production: kernel 6.18.12, Broadwell tuning, Apple HW (applesmc, brcmfmac, CS4208 audio, bcm5974 trackpad), mbpfan, zram, XFCE desktop

## Current State

### Machine Status
| Machine | Status | Next Step |
|---------|--------|-----------|
| Dell XPS 13 9315 | Production (Gentoo) | Maintenance only |
| Intel NUC11TNBi5 | Config ready | Boot live USB, follow INSTALL.md |
| Dell XPS 15 9510 | Production (Gentoo) | Test USB-C hub, clamshell mode |
| MacBook Pro 12,1 (2015) | **Production (Gentoo)** | Maintenance only |
| Surface Pro 6 | **Ready to install** | Run install scripts from Ventoy |
| ASRock B550 / Ryzen 9 5950X | Placeholder | Harvest on Fedora 42 |
| Dell Precision T5810 | Placeholder | Harvest on Fedora 42 |
| Dell Precision 7960 | Placeholder | Harvest on RHEL 10.1 |
| Surface Pro 9 | Placeholder | Harvest on Windows 11 Pro |

### Surface Pro 6 — Key Gotchas for Install Day
1. Disable Secure Boot first (Volume Up + Power in Surface UEFI)
2. WiFi is **Marvell 88W8897** — wpa_supplicant needed in chroot before reboot
3. `DRM_I915=m` mandatory (firmware loading)
4. 4GB tmpfs — large packages go to disk via `package.env`
5. Touchscreen hardware defect — not blocking, treat as laptop
6. `-march=skylake` (not kabylake — doesn't exist in GCC)

## Next Steps (Priority Order)

1. **Execute Surface Pro 6 install TONIGHT** — boot Ventoy, run part1 → part2 → part3
   - Disable Secure Boot first (Volume Up + Power)
   - Scripts at `/media/cwetzel/VTOYEFI/surfacepro6/`
   - Key gotchas: Marvell WiFi (not Intel), i915=m, 4GB tmpfs, -march=skylake
2. **Test USB-C hub on XPS 9510** — Anker 7-in-1, HDMI + USB 3.0
3. **Test clamshell mode on XPS 9510** — AOC 34" external
4. **Install Gentoo on NUC11** — follow INSTALL.md
5. **Harvest remaining machines** — B550, T5810, 7960
