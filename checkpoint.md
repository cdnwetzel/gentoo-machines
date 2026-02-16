# Checkpoint - 2026-02-16

## Session Summary

Transformed the repository from a single Dell XPS 9315 kernel config into a multi-machine Gentoo Linux kernel configuration framework supporting 8 machines.

## What Was Done

### Phase 1: Repository Restructure
- Reorganized flat layout into `machines/`, `tools/`, `shared/` directories
- Moved XPS 9315 files to `machines/xps-9315/` (.config, make.conf, fstab, grub, INSTALL.md)
- Moved harvest scripts to `tools/` (harvest.sh, deep_harvest.sh, build-kernel-remote.sh)
- Moved shared portage files to `shared/` (world, package.use, package.accept_keywords, package.license, openrc-services, portage-env)
- Created placeholder directories for 6 future machines with .gitkeep files

### Phase 2: NUC11 Kernel Config
- Generated `machines/nuc11/.config` from XPS 9315 base with 33 config changes
- **Enabled**: igc (dual 2.5GbE), ahci/SATA, igen6_edac, tps6598x, mtd/spi_nor, parport, intel_powerclamp, mei_hdcp/pxp, sof_tigerlake, ee1004, acpi_tad, serial_multi_instantiate
- **Disabled**: All Dell drivers (16 options), IPU6 camera, ISH, MEI VSC, intel_hfi_thermal, sched_mc_prio

### Phase 3: NUC11 make.conf
- Created with `-march=tigerlake` and dynamic `$(nproc)` parallelism

### Phase 4: Hardware Documentation
- Created `machines/nuc11/HARDWARE.md` from Ubuntu harvest data
- Created `machines/xps-9315/HARDWARE.md` from existing documentation

### Phase 5: Documentation
- Rewrote `CLAUDE.md` for multi-machine framework (8 machines, all tools)
- Rewrote `README.md` with machine table, new layout, per-machine differences
- Created root `INSTALL.md` — general-purpose guide that works on any machine

### Phase 6: Tools
- Generalized `build-kernel-remote.sh` to use associative array for multi-target
- Created `generate-config.sh` — uses `claude -p` to analyze harvest data and auto-generate .config, make.conf, HARDWARE.md for new machines
- Updated `make.conf` files to use `$(nproc)` instead of hardcoded `-j8`

## Current State

### Commits
- `bdb5804` - Restructure repo for multi-machine, add NUC11
- `df0fdb4` - Add general install guide, AI config generator, dynamic parallelism

### Machine Status
| Machine | Status | Next Step |
|---------|--------|-----------|
| Dell XPS 13 9315 | Production (Gentoo running) | Maintenance only |
| Intel NUC11TNBi5 | Config ready, needs Gentoo install | Boot live USB, follow INSTALL.md |
| Dell XPS 15 9510 | Placeholder only | Harvest on Ubuntu 24.04 |
| ASRock B550 / Ryzen 9 5950X | Placeholder only | Harvest on Fedora 42 (has SATA SSDs) |
| Dell Precision T5810 | Placeholder only | Harvest on Fedora 42 |
| Dell Precision 7960 | Placeholder only | Harvest on RHEL 10.1 |
| Surface Pro 6 | Placeholder only | Harvest on Fedora 43 (needs linux-surface patches) |
| Surface Pro 9 | Placeholder only | Harvest on Windows 11 Pro (or install Linux first) |

## Next Steps (Priority Order)

1. **Install Gentoo on NUC11** — boot from live USB, follow INSTALL.md with `MACHINE=nuc11`
2. **Harvest remaining machines** — run harvest scripts on each machine's current OS
3. **Generate configs** — use `generate-config.sh` or manual process for each new machine
4. **NVIDIA machines** — XPS 9510, ASRock B550, Precision 7960 need nvidia-drivers planning
5. **Surface machines** — research linux-surface patches for Pro 6 and Pro 9
6. **Consider renaming GitHub repo** — current name `gentoo_dell_xps9315` doesn't reflect multi-machine scope

## Files Modified This Session
- `CLAUDE.md` — complete rewrite for multi-machine
- `README.md` — complete rewrite for multi-machine
- `INSTALL.md` — new general-purpose install guide (root level)
- `machines/xps-9315/.config` — moved from root
- `machines/xps-9315/make.conf` — moved + dynamic $(nproc)
- `machines/xps-9315/fstab` — moved from root
- `machines/xps-9315/grub` — moved from root
- `machines/xps-9315/HARDWARE.md` — new
- `machines/xps-9315/INSTALL.md` — moved from root (XPS-specific guide preserved)
- `machines/nuc11/.config` — new (derived from XPS with 33 changes)
- `machines/nuc11/make.conf` — new (-march=tigerlake)
- `machines/nuc11/HARDWARE.md` — new (from harvest data)
- `tools/build-kernel-remote.sh` — generalized for multi-target
- `tools/generate-config.sh` — new (Claude-powered config generation)
- `tools/harvest.sh` — moved from root
- `tools/deep_harvest.sh` — moved from root
- `shared/*` — all moved from root
