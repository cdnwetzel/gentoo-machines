# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Multi-machine Gentoo Linux kernel configuration framework. Each machine directory under `machines/` contains a tuned kernel `.config`, `make.conf`, and hardware documentation.

## Repository Structure

```
machines/           Per-machine kernel configs, make.conf, hardware docs
  xps-9315/         Dell XPS 13 9315 (Alder Lake) - PRODUCTION
  nuc11/            Intel NUC11TNBi5 (Tiger Lake) - READY TO BUILD
  xps-9510/         Dell XPS 15 9510 (Tiger Lake-H) - PRODUCTION
  asrock-b550/      ASRock B550 / Ryzen 9 5950X (planned)
  precision-t5810/  Dell Precision T5810 / Xeon E5 (planned)
  precision-7960/   Dell Precision 7960 / Xeon W5 (planned)
  surface-pro-6/    Surface Pro 6 (planned)
  surface-pro-9/    Surface Pro 9 (planned)
tools/              harvest.sh, deep_harvest.sh, build-kernel-remote.sh, generate-config.sh
shared/             Common portage files, XFCE desktop config restore scripts
patches/            Kernel patches
INSTALL.md          General-purpose installation guide (any machine)
```

## Target Machines

| # | Machine | CPU | GPU | Kernel Status | Current OS |
|---|---------|-----|-----|---------------|------------|
| 1 | Dell XPS 13 9315 | i5-1230U (Alder Lake) | Intel Iris Xe | Production | Gentoo |
| 2 | Intel NUC11TNBi5 | i5-1135G7 (Tiger Lake) | Intel Iris Xe | Ready to build | Ubuntu |
| 3 | Dell XPS 15 9510 | i7-11800H (Tiger Lake-H) | Intel UHD + NVIDIA RTX 3050 Ti | Production | Gentoo |
| 4 | ASRock B550 | Ryzen 9 5950X | NVIDIA RTX 3060 Ti | Planned | Fedora 42 |
| 5 | Dell Precision T5810 | Xeon E5-2699v4 | TBD | Planned | Fedora 42 |
| 6 | Dell Precision 7960 | Xeon W5-3433 | RTX Pro 6000 96GB + RTX A1000 8GB | Planned | RHEL 10.1 |
| 7 | Surface Pro 6 | 8th Gen Intel | Intel UHD 620 | Planned | Fedora 43 |
| 8 | Surface Pro 9 | 12th Gen Intel | Intel Iris Xe | Planned | Windows 11 Pro |

NVIDIA machines will use **proprietary nvidia-drivers**. Surface machines will need **linux-surface** kernel patches.

## Machine-Specific Details

### Dell XPS 13 9315 (Production)

- **Kernel**: Linux 6.12.58-gentoo
- **Architecture**: x86_64, hybrid P-Core/E-Core (Alder Lake)
- **Compiler flags**: `-march=alderlake -O2 -pipe`
- **Key drivers**: i915, iwlwifi (AX211), nvme, sof-audio, intel_ipu6, intel_ish, ppp (SSTP VPN)
- **Firmware**: Embedded in kernel (i915/adlp_*, iwlwifi-so-a0-gf-a0-*, intel/ibt-0040-0041.*)
- **Full install guide**: `machines/xps-9315/INSTALL.md`
- **Hardware ref**: `machines/xps-9315/HARDWARE.md`

### Intel NUC11TNBi5 (Ready to Build)

- **Kernel**: Derived from XPS 9315 config with NUC11-specific changes
- **Architecture**: x86_64, uniform 4C/8T (Tiger Lake, AVX-512)
- **Compiler flags**: `-march=tigerlake -O2 -pipe`
- **Key drivers**: i915, iwlwifi (AX201), igc (dual 2.5GbE), ahci, nvme, snd_hda_intel, tps6598x
- **Key differences from XPS**: No camera/ISP, no Dell drivers, no ISH, has SATA, dual Ethernet, SPI flash, EDAC
- **Firmware**: Loaded from /lib/firmware/ (i915/tgl_*, iwlwifi-QuZ-*, intel/ibt-20-*)
- **Hardware ref**: `machines/nuc11/HARDWARE.md`

## Tools

### harvest.sh
General-purpose hardware inventory (works on any Linux system):
```bash
sudo tools/harvest.sh
```

### deep_harvest.sh
Deep hardware discovery with module and firmware detection:
```bash
sudo -E tools/deep_harvest.sh
```

### build-kernel-remote.sh
Cross-compile and deploy kernels over SSH:
```bash
tools/build-kernel-remote.sh <target> {pull|build|deploy|all}
# Targets: xps-9315, nuc11
```

### generate-config.sh
AI-powered config generation for new machines using Claude CLI:
```bash
tools/generate-config.sh <new-machine> <base-machine> <harvest-dir>
# Example: tools/generate-config.sh precision-t5810 nuc11 /tmp/t5810-harvest/
```
Analyzes harvest data against a base config and generates `.config`, `make.conf`, and `HARDWARE.md`.

## Kernel Build Commands

```bash
# Copy machine config to kernel source
cp machines/<machine>/.config /usr/src/linux/.config

# Build
cd /usr/src/linux
make oldconfig        # Update config for kernel version differences
make -j$(nproc)

# Install (requires root)
make modules_install
make install
grub-mkconfig -o /boot/grub/grub.cfg
```

## Portage Configuration

Shared files in `shared/` apply to all machines:

| File | Portage Location |
|------|-----------------|
| `shared/world` | `/var/lib/portage/world` |
| `shared/package.use` | `/etc/portage/package.use/` |
| `shared/package.accept_keywords` | `/etc/portage/package.accept_keywords/` |
| `shared/package.license` | `/etc/portage/package.license/` |
| `shared/openrc-services` | Reference for `rc-update` commands |
| `shared/portage-env` | `/etc/portage/env/` |
| `shared/restore-desktop.sh` | User restore: XFCE keybindings, panels, displays, xhost autostart |
| `shared/restore-system.sh` | Root restore: elogind, ACPI lid toggle, LightDM config |
| `shared/xfce4-keybindings.sh` | Restore script for XFCE keyboard shortcuts (Super+Arrow tiling, etc.) |
| `shared/xfce4-panel.sh` | Restore script for XFCE panel layout (top bar + autohide dock) |
| `shared/xfce4-displays.xml` | XFCE display profile (clamshell mode, AOC 34" external) |
| `shared/acpi-lid.sh` | ACPI lid script: toggles eDP-1 on lid open/close, centered below AOC |
| `shared/acpi-default.sh` | ACPI default handler with lid event wired to lid.sh |
| `shared/lightdm-display-setup.sh` | LightDM greeter display setup for clamshell mode |
| `shared/lightdm.conf` | Full LightDM config with display-setup-script wired in |
| `shared/logind.conf` | elogind config (lid-close-docked=ignore for clamshell mode) |

Machine-specific `make.conf` files go to `/etc/portage/make.conf`.

### Common Settings
- **Profile**: `default/linux/amd64/23.0`
- **Init**: OpenRC (no systemd)
- **Desktop**: XFCE with LightDM
- **Python**: 3.12 / 3.13

## Config Generation Workflow

New machine configs can be generated automatically or manually:

### Automated (recommended)
```bash
# 1. Harvest on target machine (any Linux distro)
sudo tools/harvest.sh && sudo -E tools/deep_harvest.sh

# 2. Copy logs to build host, then generate config
tools/generate-config.sh <new-machine> <closest-base> <harvest-dir>

# 3. On target: resolve deps and build
cd /usr/src/linux && make olddefconfig && make -j$(nproc)
```

### Manual
1. Run `harvest.sh` and `deep_harvest.sh` on target (via current OS)
2. Copy closest existing `.config` as base
3. Enable drivers for new hardware (from harvest PCI/module list)
4. Disable drivers not present on new hardware
5. Update firmware references
6. Run `make olddefconfig` on target to resolve dependencies
7. Boot, verify with `lspci -k` and `dmesg | grep -i error`

### Dell XPS 15 9510 (Production)

- **Kernel**: Linux 6.12.58-gentoo
- **Architecture**: x86_64, uniform 8C/16T (Tiger Lake-H, AVX-512)
- **Compiler flags**: `-march=tigerlake -O2 -pipe`
- **Key drivers**: i915 (module), nvidia 590.48 (proprietary), iwlwifi (AX203, module), nvme, snd_hda_intel, btusb
- **Firmware**: Loaded from /lib/firmware/ (i915/tgl_*, iwlwifi-QuZ-a0-hr-b0-*, intel/ibt-20-*)
- **Critical**: All firmware-dependent drivers MUST be modules (=m), not built-in — no initramfs
- **GPU**: Hybrid Intel UHD + NVIDIA RTX 3050 Ti (PRIME/Optimus, nvidia-drivers)
- **Hardware ref**: `machines/xps-9510/HARDWARE.md`

## Future Machine Notes

- **ASRock B550**: First AMD — `CONFIG_CPU_SUP_AMD`, `CONFIG_AMD_IOMMU`, `-march=znver3`, SATA SSDs still in use
- **Precision T5810**: Broadwell-EP Xeon — ECC memory, `-march=broadwell`, older chipset
- **Precision 7960**: Modern Xeon W + dual NVIDIA — most complex config, multi-GPU with different NVIDIA cards
- **Surface Pro 6/9**: Need linux-surface kernel patches for touchscreen, cameras, battery, etc.
