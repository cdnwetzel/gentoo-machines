# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Multi-machine Gentoo Linux kernel configuration framework. Each machine directory under `machines/` contains a tuned kernel `.config`, `make.conf`, and hardware documentation.

## Repository Structure

```
machines/           Per-machine kernel configs, make.conf, hardware docs
  xps-9315/         Dell XPS 13 9315 (Alder Lake) - PRODUCTION (config maintained)
  nuc11/            Intel NUC11TNBi5 (Tiger Lake) - READY TO BUILD
  xps-9510/         Dell XPS 15 9510 (Tiger Lake-H) - PRODUCTION
  mbp-2015/         MacBook Pro 12,1 Early 2015 (Broadwell) - PRODUCTION
  asrock-b550/      ASRock B550 / Ryzen 9 5950X (planned)
  precision-t5810/  Dell Precision T5810 / Xeon E5 (planned)
  precision-7960/   Dell Precision 7960 / Xeon W5 (reference only)
  surface-pro-6/    Surface Pro 6 (Kaby Lake-R) - PRODUCTION
  surface-pro-9/    Surface Pro 9 (planned)
tools/              harvest.sh, deep_harvest.sh, kconfig-lint.sh, kernel-config-template.sh, build-kernel-remote.sh, generate-config.sh, update-system.sh
shared/             Common portage files, XFCE desktop config restore scripts
patches/            Kernel patches
INSTALL.md          General-purpose installation guide (any machine)
```

## Target Machines

| # | Machine | CPU | GPU | Kernel Status | Current OS |
|---|---------|-----|-----|---------------|------------|
| 1 | Dell XPS 13 9315 | i5-1230U (Alder Lake) | Intel Iris Xe | Production (config maintained) | Windows (returned) |
| 2 | Intel NUC11TNBi5 | i5-1135G7 (Tiger Lake) | Intel Iris Xe | Ready to build | Ubuntu |
| 3 | Dell XPS 15 9510 | i7-11800H (Tiger Lake-H) | Intel UHD + NVIDIA RTX 3050 Ti | Production | Gentoo |
| 4 | MacBook Pro 12,1 (2015) | i7-5557U (Broadwell) | Intel Iris 6100 | Production | Gentoo |
| 5 | ASRock B550 | Ryzen 9 5950X | NVIDIA RTX 3060 Ti | Planned | Fedora 42 |
| 6 | Dell Precision T5810 | Xeon E5-2699v4 | 2x NVIDIA GTX 1050 Ti | Planned | Fedora 42 |
| 7 | Dell Precision 7960 | Xeon W5-3433 | RTX Pro 6000 96GB + RTX A1000 8GB | Reference only | RHEL 10.1 (production AI/ML) |
| 8 | Surface Pro 6 | i5-8250U (Kaby Lake-R) | Intel UHD 620 | Production | Gentoo |
| 9 | Surface Pro 9 | 12th Gen Intel | Intel Iris Xe | Planned | Windows 11 Pro |

NVIDIA machines will use **proprietary nvidia-drivers**. Surface Pro 6 runs stock gentoo-sources; Surface Pro 9 will need **linux-surface** kernel patches.

All production machines track **6.18 LTS** (EOL Dec 2027) via `=sys-kernel/gentoo-sources-6.18* ~amd64` in their `package.accept_keywords`. Use `tools/update-system.sh` for guided system and kernel updates.

## Machine-Specific Details

### Dell XPS 13 9315 (Configs Updated)

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

### MacBook Pro 12,1 Early 2015 (Production)

- **Kernel**: Linux 6.18.12-gentoo
- **Architecture**: x86_64, 2C/4T (Broadwell)
- **Compiler flags**: `-march=broadwell -O2 -pipe`
- **Key drivers**: i915 (module), brcmfmac (BCM43602 WiFi), btusb+btbcm (BT), snd_hda_codec_cs420x (CS4208 audio), bcm5974 (trackpad), applesmc (fan/thermal), thunderbolt (Falcon Ridge)
- **Firmware**: Loaded from /lib/firmware/ (brcm/brcmfmac43602-pcie.*, regulatory.db)
- **Apple-specific**: hid_apple (fnmode=3), applesmc (35 sensors), mbpfan, apple_gmux (backlight), smc::kbd_backlight
- **Boot params**: `libata.force=noncq reboot=pci fbcon=font:TER16x32 i915.enable_fbc=1 i915.enable_psr=2`
- **Not working**: FaceTime camera (needs out-of-tree facetimehd driver)
- **Hardware ref**: `machines/mbp-2015/HARDWARE.md`

## Tools

### harvest.sh
General-purpose hardware inventory (works on any Linux system, 15 sections):
```bash
sudo tools/harvest.sh
```
Sections 1-8: PCI devices, CPU, DMI/BIOS, I2C, USB, loaded modules, firmware, storage.
Sections 9-15: CPU_FLAGS_X86, audio subsystem (SOF vs HDA), platform vendor, boot type (EFI/BIOS/Secure Boot), suspend capabilities (s2idle vs S3), loaded firmware mapping, GCC `-march` suggestion.

### deep_harvest.sh
Deep hardware discovery with module and firmware detection:
```bash
sudo -E tools/deep_harvest.sh
```

### kconfig-lint.sh
Static validator for kernel_config.sh scripts — catches 5 classes of silent bugs:
```bash
tools/kconfig-lint.sh machines/xps-9510/kernel_config.sh [/usr/src/linux]
```

| Severity | Check | Example bug caught |
|----------|-------|-------------------|
| FAIL | `--module` on bool option | `DELL_SMBIOS_WMI`, `SND_SOC_SOF_INTEL_TOPLEVEL` |
| WARN | Missing parent toggle | `X86_PLATFORM_DRIVERS_DELL` not set before Dell drivers |
| WARN | Firmware driver set =y (built-in) | `DRM_I915=y` without initramfs |
| WARN | Dependency not satisfied | dep not set anywhere in script |
| INFO | Unknown config option | typos, renamed symbols, wrong kernel version |

Parses all Kconfig files into a symbol database (~19K symbols, ~2s), then cross-references every `scripts/config` call. Requires kernel source tree.

### kernel-config-template.sh
Generate a machine-specific kernel_config.sh skeleton from harvest data:
```bash
tools/kernel-config-template.sh <machine-name> <harvest-log>
# Example: tools/kernel-config-template.sh precision-t5810 /tmp/t5810-harvest/hardware_inventory.log
```
Auto-detects CPU, GPU, WiFi (8 vendors), audio (SOF/HDA), storage, platform vendor (Dell/Apple/Surface/Lenovo/HP/ASUS), Ethernet, Thunderbolt, ISH sensors, cameras. Generates a complete 26-phase kernel_config.sh and auto-runs kconfig-lint on the output.

### update-system.sh
System update tool for production machines. Auto-detects machine via hostname + DMI:
```bash
sudo tools/update-system.sh                      # full prompted workflow (default), resumes after reboot
sudo tools/update-system.sh --dry-run             # preview all phases
sudo tools/update-system.sh fetch                 # emerge --sync + gentoo-sources + eselect kernel set + news
sudo tools/update-system.sh world                 # emerge @world + preserved-rebuild + depclean
sudo tools/update-system.sh config-update         # merge updated config files via dispatch-conf
tools/update-system.sh check                      # pre-flight: versions, disk, patches, config strategy
tools/update-system.sh prepare                    # backup .config, migrate config, apply patches, lint
tools/update-system.sh build                      # make -j$(nproc) with timing
sudo tools/update-system.sh install               # modules_install + make install + NVIDIA rebuild
tools/update-system.sh verify                     # post-reboot checks: dmesg, drivers, GPU, WiFi, zram
sudo tools/update-system.sh clean                 # eclean-kernel -n 3, keep current + 2 rollback
tools/update-system.sh all                        # prepare + build + install
tools/update-system.sh --machine xps-9510 check   # override auto-detection
```

The `full` workflow (default) prompts Y/n/skip before each phase and saves progress to `/var/lib/kernel-update/full-progress`. After install it detects the reboot boundary and exits; re-running `full` resumes with verify + clean. Individual subcommands work standalone for manual use.

Config strategy: same-series (copy .config + olddefconfig), cross-series (defconfig + kernel_config.sh + olddefconfig). Machine registry covers xps-9510, mbp-2015, surface-pro-6, nuc11.

### build-kernel-remote.sh
Cross-compile and deploy kernels over SSH (auto-detects KVER from target):
```bash
tools/build-kernel-remote.sh <target> {pull|build|deploy|all}
# Targets: xps-9510, mbp-2015, surface-pro-6, nuc11
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
| `shared/openrc-services` | Reference for `rc-update` commands (machine-conditional annotations) |
| `shared/portage-env` | `/etc/portage/env/` |
| `shared/restore-desktop.sh` | User restore: XFCE keybindings, panels, displays, HiDPI (auto-detect), xhost autostart |
| `shared/restore-system.sh` | Root restore: elogind, ACPI lid toggle, LightDM config |
| `shared/xfce4-keybindings.sh` | Restore script for XFCE keyboard shortcuts (Super+Arrow tiling, Super+Enter maximize, Super+Space search, etc.) |
| `shared/xfce4-panel.sh` | Restore script for XFCE panel layout (top bar + autohide dock) |
| `shared/xfce4-displays.xml` | XFCE display profile (clamshell mode, AOC 34" external) |
| `shared/acpi-lid.sh` | ACPI lid script: toggles eDP-1 on lid open/close, centered below AOC |
| `shared/acpi-default.sh` | ACPI default handler with lid event wired to lid.sh |
| `shared/lightdm-display-setup.sh` | LightDM greeter display setup for clamshell mode |
| `shared/lightdm.conf` | Full LightDM config with display-setup-script wired in |
| `shared/logind.conf` | elogind config (lid-close-docked=ignore for clamshell mode) |
| `shared/30-touchpad.conf` | Xorg libinput: tap-to-click, natural scroll, disable-while-typing |
| `shared/hibernate-setup.sh` | One-time swap file + GRUB resume setup for hibernate (interactive, idempotent) |
| `shared/low-battery-hibernate.sh` | Cron monitor: auto-hibernate at 5% battery (laptops); desktops use apcupsd |
| `shared/ksm.start` | KSM enable script, installed to `/etc/local.d/ksm.start` |
| `shared/fstrim-weekly` | Weekly SSD TRIM maintenance script |
| `shared/xhost-local.desktop` | XDG autostart: `xhost +local:` for X11 access |
| `patches/README.md` | Kernel patch descriptions and upstream status |
| `patches/ipu-bridge-fix-double-brace.patch` | Fix double-brace build failure in ipu-bridge (gentoo-sources 6.12.58) |
| `patches/intel_idle-add-tiger-lake.patch` | Add Tiger Lake to intel_idle for proper C-state management |
| `shared/INSTALL_GOTCHAS.md` | Universal install gotchas (25 lessons from all machines) |
| `shared/machine-checklist.md` | Universal onboarding checklist for new machines |
| `backlog.md` | Prioritized open items tracker |
| `checkpoint.md` | Session-by-session progress log |

Machine-specific `make.conf` files go to `/etc/portage/make.conf`.

### Common Settings
- **Profile**: `default/linux/amd64/23.0`
- **Init**: OpenRC (no systemd)
- **Desktop**: XFCE with LightDM
- **Python**: 3.13 / 3.14

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

## Additional Machine Details

### Dell XPS 15 9510 (Production)

- **Kernel**: Linux 6.12.58-gentoo
- **Architecture**: x86_64, uniform 8C/16T (Tiger Lake-H, AVX-512)
- **Compiler flags**: `-march=tigerlake -O2 -pipe`
- **Key drivers**: i915 (module), nvidia 590.48.01 (proprietary), iwlwifi (AX203, module), nvme, snd_hda_intel, btusb, r8152 (USB Ethernet)
- **Firmware**: Loaded from /lib/firmware/ (i915/tgl_*, iwlwifi-QuZ-a0-hr-b0-*, intel/ibt-20-*)
- **Critical**: All firmware-dependent drivers MUST be modules (=m), not built-in — no initramfs
- **NVIDIA deps**: `DRM_QXL=m` required to pull in `DRM_TTM_HELPER` (nvidia-drivers build dependency on kernel 6.11+)
- **GPU**: Hybrid Intel UHD + NVIDIA RTX 3050 Ti (PRIME/Optimus, nvidia-drivers)
- **Kernel install**: `sys-kernel/installkernel` with `grub` USE flag — auto-runs grub-mkconfig on `make install`
- **USB-C hubs**: Anker 7-in-1 tested (HDMI, PD, USB-A/C, SD/TF, Ethernet via r8152/ax88179/cdc_ether)
- **Performance**: THP (always), MGLRU, KSM, NR_CPUS=16, zram 8GB zstd swap
- **Power/Thermal**: thermald + tlp (auto performance on AC, powersave on battery)
- **Sysctl**: vm.swappiness=10, dirty_ratio=40, TCP tuning (`sysctl-performance.conf`)
- **Audio**: PipeWire + WirePlumber (replaces PulseAudio), xfce4-pulseaudio-plugin for tray volume
- **Dev stack**: Python 3.13, PyTorch 2.10+CUDA, transformers, langchain, chromadb, faiss, jupyter, pyodbc+MSSQL ODBC 18
- **Editors**: VS Code, Geany
- **Node**: v24.11.1 + nvm
- **Hardware ref**: `machines/xps-9510/HARDWARE.md`

### XPS 9510 Machine-Specific Files

| File | Purpose |
|------|---------|
| `machines/xps-9510/.config` | Kernel config (Tiger Lake-H + NVIDIA + USB-C hub + perf tuning) |
| `machines/xps-9510/make.conf` | Portage: `-march=tigerlake`, VIDEO_CARDS="intel iris nvidia" |
| `machines/xps-9510/fstab` | Dual NVMe layout: root (nvme0n1) + /data (nvme1n1) |
| `machines/xps-9510/grub` | GRUB defaults: i915.enable_guc=3, nvidia dynamic power |
| `machines/xps-9510/sysctl-performance.conf` | VM/network tuning for 32GB RAM + dual NVMe |
| `machines/xps-9510/zram-init.conf` | 8GB zstd compressed swap config |
| `machines/xps-9510/HARDWARE.md` | Full hardware + software environment reference |
| `machines/xps-9510/ksm.start` | KSM enable script (also in shared/) |
| `machines/xps-9510/99-module-rebuild.install` | Kernel postinst hook: auto `emerge @module-rebuild` with KERNEL_DIR set |
| `machines/xps-9510/POST-REBOOT.md` | Post-install verification checklist |
| `machines/xps-9510/package.use` | USE overrides for XPS 9510 packages (PipeWire, NVIDIA, fwupd) |
| `machines/xps-9510/prime-run` | NVIDIA PRIME Optimus wrapper script |
| `machines/xps-9510/kernel_config.sh` | 26-phase programmatic kernel config (Tiger Lake-H + NVIDIA) |
| `machines/xps-9510/world` | Installed package set (61 packages) |
| `machines/xps-9510/package.env` | Large package disk fallback (6 packages) |
| `machines/xps-9510/portage_env_notmpfs.conf` | Disk PORTAGE_TMPDIR for large builds |
| `machines/xps-9510/package.accept_keywords` | ~amd64 keywords |
| `machines/xps-9510/tlp.conf` | TLP power: performance on AC, powersave on battery |
| `machines/xps-9510/live-fixes.sh` | Apply CPU_FLAGS_X86 fix + optimizations to live system |
| `machines/xps-9510/gentoo_install_part1.sh` | Partition dual NVMe from live USB |
| `machines/xps-9510/gentoo_install_part2.sh` | Stage3 + config staging + chroot prep |
| `machines/xps-9510/gentoo_install_part3_chroot.sh` | 13-phase one-shot chroot install (NVIDIA phases) |
| `machines/xps-9510/KERNEL_CONFIG_CROSSREF.md` | Kernel config decisions (NVIDIA dep chain, built-in vs module) |
| `machines/xps-9510/INSTALL_GOTCHAS.md` | 10 XPS 9510-specific install lessons |
| `machines/xps-9510/INSTALL_PREFLIGHT.md` | 13-phase install checklist with NVIDIA verification |

### MBP 2015 Machine-Specific Files

| File | Purpose |
|------|---------|
| `machines/mbp-2015/.config` | Kernel config (Broadwell + Apple HW + THP/MGLRU/PREEMPT tuning) |
| `machines/mbp-2015/make.conf` | Portage: `-march=broadwell`, VIDEO_CARDS="intel", ccache, 12G tmpfs |
| `machines/mbp-2015/fstab` | Single SSD: root (sda3) + boot (sda2) + EFI (sda1) + portage tmpfs |
| `machines/mbp-2015/grub` | GRUB defaults: libata.force=noncq, reboot=pci, i915 power saving |
| `machines/mbp-2015/mbpfan.conf` | Fan control: 1300-6199 RPM, low=55 high=80 max=86 |
| `machines/mbp-2015/zram-init.conf` | 4GB zstd compressed swap config |
| `machines/mbp-2015/disable-wakeup.start` | Prevent immediate wake from suspend (LID0/XHC1) |
| `machines/mbp-2015/setup-hotkeys.sh` | XFCE Fn row keybindings + pulseaudio panel plugin |
| `machines/mbp-2015/package.accept_keywords` | ~amd64 keywords: mbpfan, networkmanager-sstp |
| `machines/mbp-2015/package.use` | USE overrides: libdbusmenu gtk3 (remmina dep) |
| `machines/mbp-2015/world` | Installed package set |
| `machines/mbp-2015/HARDWARE.md` | Full hardware + software environment reference |
| `machines/mbp-2015/kernel_config.sh` | Programmatic kernel config script (scripts/config based) |
| `machines/mbp-2015/post_install_setup.sh` | Post-kernel install reference (superseded by part3) |
| `machines/mbp-2015/wifi_firmware_fix.sh` | BCM43602 firmware symlink/check script |
| `machines/mbp-2015/package.env` | Large package tmpdir override (chromium, firefox, llvm, rust, gcc) |
| `machines/mbp-2015/portage_env_notmpfs.conf` | Fallback PORTAGE_TMPDIR to disk |
| `machines/mbp-2015/gentoo_install_part1.sh` | Disk partitioning from live USB |
| `machines/mbp-2015/gentoo_install_part2.sh` | Stage3 + config staging + chroot prep |
| `machines/mbp-2015/gentoo_install_part3_chroot.sh` | 13-phase one-shot chroot install |

### Surface Pro 6 (Production)

- **Kernel**: Linux 6.18.12-gentoo
- **Architecture**: x86_64, 4C/8T (Kaby Lake-R)
- **Compiler flags**: `-march=skylake -O2 -pipe` (GCC has no `-march=kabylake`)
- **Key drivers**: i915 (module, KBL GT2), mwifiex_pcie (Marvell 88W8897 WiFi), snd_hda_intel (ALC298), surface_aggregator, btmrvl_sdio (Marvell BT)
- **Firmware**: Loaded from /lib/firmware/ (i915/kbl_dmc_*, mrvl/pcie8897_uapsta.bin, mrvl/usb8897_uapsta.bin)
- **Critical**: DRM_I915=m (module), WiFi is Marvell NOT Intel, no initramfs
- **Display**: 2736x1824 PixelSense (267 PPI, 3:2 aspect), 150% HiDPI scaling (144 DPI)
- **Storage**: SK hynix BC501 NVMe 238GB, no swap partition (4GB zram zstd)
- **RAM**: 8GB LPDDR3 (soldered), 4GB portage tmpfs with disk fallback for large packages
- **Input**: Type Cover USB HID (keyboard + touchpad), touchscreen non-functional (HW defect)
- **Suspend**: s2idle only (no S3 deep sleep)
- **Hardware ref**: `machines/surface-pro-6/HARDWARE.md`

### Surface Pro 6 Machine-Specific Files

| File | Purpose |
|------|---------|
| `machines/surface-pro-6/make.conf` | Portage: `-march=skylake`, VIDEO_CARDS="intel", 4GB tmpfs |
| `machines/surface-pro-6/kernel_config.sh` | Programmatic kernel config (scripts/config based) |
| `machines/surface-pro-6/package.use` | USE: installkernel+grub, networkmanager-sstp gui |
| `machines/surface-pro-6/package.accept_keywords` | ~amd64 keywords: networkmanager-sstp, gentoo-sources 6.18 LTS |
| `machines/surface-pro-6/package.env` | Large package tmpdir override |
| `machines/surface-pro-6/portage_env_notmpfs.conf` | Fallback PORTAGE_TMPDIR to disk |
| `machines/surface-pro-6/world` | Target package set (64 packages) |
| `machines/surface-pro-6/iptsd.conf` | Surface touch/pen input daemon config |
| `machines/surface-pro-6/iptsd-device.conf` | Surface Pro 6 specific IPTSD device config |
| `machines/surface-pro-6/50-iptsd.rules` | udev rules for IPTSD |
| `machines/surface-pro-6/fedora-reference.config` | Fedora 43 kernel 6.18.8 config (cross-reference) |
| `machines/surface-pro-6/HARDWARE.md` | Complete hardware inventory (5 harvest rounds) |
| `machines/surface-pro-6/INSTALL_PREFLIGHT.md` | 13-phase install checklist |
| `machines/surface-pro-6/INSTALL_GOTCHAS.md` | 20 lessons learned from prior builds |
| `machines/surface-pro-6/EXEC_SEQUENCE.md` | 7-step quick reference |
| `machines/surface-pro-6/FEDORA_REFERENCE.md` | Config mined from running Fedora |
| `machines/surface-pro-6/KERNEL_CONFIG_CROSSREF.md` | Kernel config decisions explained |
| `machines/surface-pro-6/grub` | GRUB defaults: i915 power saving, HiDPI console font, 1024x768 menu |
| `machines/surface-pro-6/sysctl-performance.conf` | VM/network tuning for 8GB RAM + NVMe |
| `machines/surface-pro-6/zram-init.conf` | 4GB zstd compressed swap config |
| `machines/surface-pro-6/mwifiex.conf` | Marvell 88W8897 WiFi power-save disable (modprobe.d) |
| `machines/surface-pro-6/wifi-powersave.conf` | NetworkManager WiFi power save disable |
| `machines/surface-pro-6/wifi-reload.sh` | elogind sleep hook: reload mwifiex on resume |
| `machines/surface-pro-6/wifi-recover.sh` | Manual WiFi recovery script (/usr/local/bin/wifi-recover) |
| `machines/surface-pro-6/disable-wakeup.start` | Prevent spurious s2idle wake (LID0/XHC1) |
| `machines/surface-pro-6/fstrim-weekly.start` | Weekly SSD TRIM via /etc/local.d/ |
| `machines/surface-pro-6/gentoo_install_part1.sh` | Partition + format NVMe |
| `machines/surface-pro-6/gentoo_install_part2.sh` | Stage3 + config copy + chroot prep |
| `machines/surface-pro-6/lightdm.conf` | LightDM config with HiDPI (xserver-command=X -dpi 144) |
| `machines/surface-pro-6/lightdm-display-setup.sh` | LightDM display-setup: xrandr --dpi 144 for login screen |
| `machines/surface-pro-6/hidpi-setup.sh` | XFCE HiDPI: Xft/DPI=144, cursor size 36, .Xresources, xrandr autostart |
| `machines/surface-pro-6/Xresources` | Persistent X11 DPI config (Xft.dpi=144, Xcursor.size=36) |
| `machines/surface-pro-6/xrandr-dpi.desktop` | XDG autostart: xrandr --dpi 144 on every login |
| `machines/surface-pro-6/lightdm-gtk-greeter.conf` | LightDM greeter HiDPI (Sans 16, xft-dpi=144) |
| `machines/surface-pro-6/gentoo_install_part3_chroot.sh` | 13-phase one-shot chroot install |

## Future Machine Notes

- **ASRock B550**: First AMD — `CONFIG_CPU_SUP_AMD`, `CONFIG_AMD_IOMMU`, `-march=znver3`, SATA SSDs still in use
- **Precision T5810**: Broadwell-EP Xeon — ECC memory, 2x NVIDIA GTX 1050 Ti, `-march=broadwell`, older chipset
- **Precision 7960**: Reference only — stays on RHEL 10.1 production for AI/ML, no Gentoo install
- **Surface Pro 9**: Will need linux-surface kernel patches for touchscreen, cameras, battery, etc. (Surface Pro 6 runs without them — touchscreen is a HW defect on this unit).
