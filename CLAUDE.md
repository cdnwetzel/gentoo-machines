# CLAUDE.md

Project context and technical reference for this repository. Used by contributors and automated tooling to understand the structure, conventions, and machine-specific details.

## Project Overview

Multi-machine Gentoo Linux kernel configuration framework. Each machine directory under `machines/` contains a tuned kernel `.config`, `make.conf`, and hardware documentation.

## Repository Structure

```
machines/           Per-machine kernel configs, make.conf, hardware docs
  xps-9315/         Dell XPS 13 9315 (Alder Lake) - PRODUCTION (config maintained)
  nuc11/            Intel NUC11TNBi5 (Tiger Lake) - READY TO BUILD
  xps-9510/         Dell XPS 15 9510 (Tiger Lake-H) - PRODUCTION
  mbp-2015/         MacBook Pro 12,1 Early 2015 (Broadwell) - RETIRED (macOS 12, kids' machine)
  asrock-b550/      ASRock B550 / Ryzen 9 5950X - PRODUCTION
  precision-t5810/  Dell Precision T5810 / Xeon E5 - PRODUCTION
  precision-7960/   Dell Precision 7960 / Xeon W5 (reference only)
  surface-pro-6/    Surface Pro 6 (Kaby Lake-R) - PRODUCTION
  surface-pro-9/    Surface Pro 9 (planned)
tools/              harvest.sh, deep_harvest.sh, kconfig-lint.sh, kernel-config-template.sh, machine-profile.sh, build-kernel-remote.sh, generate-config.sh, generate-install.sh, test-generate-install.sh, update-system.sh, verify-install.sh
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
| 4 | MacBook Pro 12,1 (2015) | i7-5557U (Broadwell) | Intel Iris 6100 | Retired | macOS 12 (kids' machine) |
| 5 | ASRock B550 | Ryzen 9 5950X | NVIDIA RTX 5060 Ti 16GB (Blackwell) | Production | Gentoo |
| 6 | Dell Precision T5810 | Xeon E5-2699v4 | 2x NVIDIA RTX A4500 (Ampere, 20GB ECC each, NVLink) | Production | Gentoo |
| 7 | Dell Precision 7960 | Xeon W5-3433 16C/32T (Sapphire Rapids) | RTX PRO 6000 Blackwell 96GB (600W) + RTX 5080 16GB Blackwell | Reference only (harvested) | RHEL 10.1 (production AI/ML) |
| 8 | Surface Pro 6 | i5-8250U (Kaby Lake-R) | Intel UHD 620 | Production | Gentoo |
| 9 | Surface Pro 9 | 12th Gen Intel | Intel Iris Xe | Planned | Windows 11 Pro |
| 10 | Beelink MINI S | Celeron N5095A (Jasper Lake) | Intel UHD (Gen11 LP) | Production | Gentoo |
| 11 | Dell OptiPlex 3090 SFF | i5-10505 (Comet Lake) | Intel UHD 630 + NVIDIA RTX A1000 8GB | Production | Gentoo |

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

### MacBook Pro 12,1 Early 2015 (Retired — macOS 12, kids' machine)

- **Last Gentoo kernel**: Linux 6.18.12-gentoo
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

Config strategy: kernel_config.sh is always applied (idempotent) on every build. Same-series: copy .config + kernel_config.sh + olddefconfig. Cross-series: defconfig + kernel_config.sh + olddefconfig. Machine registry covers xps-9510, mbp-2015, surface-pro-6, nuc11, precision-t5810.

### build-kernel-remote.sh
Cross-compile and deploy kernels over SSH (auto-detects KVER from target):
```bash
tools/build-kernel-remote.sh <target> {pull|build|deploy|all}
# Targets: xps-9510, mbp-2015, surface-pro-6, nuc11
```

### generate-config.sh
Assisted config generation for new machines using Claude CLI:
```bash
tools/generate-config.sh <new-machine> <base-machine> <harvest-dir>
# Example: tools/generate-config.sh precision-t5810 nuc11 /tmp/t5810-harvest/
```
Analyzes harvest data against a base config and generates `.config`, `make.conf`, and `HARDWARE.md`.

### generate-install.sh
3-phase install script generator for new machines:
```bash
tools/generate-install.sh <new-machine> <base-machine> <harvest-dir>
# Example: tools/generate-install.sh precision-7960 precision-t5810 /tmp/7960-harvest/
```
Emits `gentoo_install_part{1,2,3_chroot}.sh` feature-gated via `machine-profile.sh`. Parses harvest section 8 directly for block-device candidates (authoritative — avoids live-USB false positives). Feature gates: NVIDIA modprobe, Intel microcode, BT service, laptop TLP, Apple mbpfan, Surface HiDPI, Dell EFI fallback, desktop always-on elogind drop-in, firmware verification keyed to WiFi/BT driver. Output is a starting skeleton — machine-unique quirks (Dell `i915.enable_guc=3`, Surface IPTSD, Apple `applesmc` verification) are left as TODO comments for hand-edit.

### test-generate-install.sh
Regression harness for `generate-install.sh`. Runs the generator against three synthetic fixtures under `tools/test-fixtures/` (`intel-sata-desktop.harvest`, `amd-nvme-nvidia-desktop.harvest`, `apple-broadwell-laptop.harvest`) and asserts each feature gate fires correctly (presence + absence checks + `bash -n` on all three generated parts). 42 total checks.
```bash
tools/test-generate-install.sh
```

### machine-profile.sh
Shared hardware detection library — parses harvest.sh output into feature flags. Sourced by other tools, not run directly:
```bash
HARVEST="/path/to/hardware_inventory.log"
source tools/machine-profile.sh
# Now use: $CPU_VENDOR, $HAS_NVIDIA_GPU, $WIFI_DRIVER, $IS_LAPTOP, etc.

# Or run standalone for a summary:
HARVEST="/path/to/hardware_inventory.log" MP_SUMMARY=1 bash tools/machine-profile.sh
```
Sets 30+ variables: CPU (vendor, model, threads, march, flags), GPU (Intel gen, NVIDIA count, AMD), WiFi/BT drivers, audio type/codec, storage (NVMe/SATA/boot drive), Ethernet drivers, platform vendor, boot type, suspend, chassis/form factor, and hardware features (Thunderbolt, ISH, SAM, EDAC, NUMA).

### verify-llm.sh
Thin HTTP wrapper around the XPS-9510 Ollama verifier. Callable from any AI peer (T5810, asrock-b550, 7960):
```bash
echo "1+1 = 3" | tools/verify-llm.sh --task fact-check
tools/verify-llm.sh --task judge --criterion "answer is grounded in sources" --payload answer.txt
tools/verify-llm.sh --task json-schema --schema schema.json --payload doc.json
tools/verify-llm.sh --task code-review --payload diff.patch
```
Returns single-line JSON `{verdict, reasoning, model, ms}`. Exit 0=pass, 1=fail, 2=error. Default endpoint `xps-9510.lan:11434`, override via `OLLAMA_HOST` env. Tasks: `yes-no`, `fact-check`, `json-schema`, `judge`, `code-review`.

### verify-install.sh
Post-reboot deep verification — auto-detects machine from DMI:
```bash
sudo tools/verify-install.sh
```

8 verification sections: kernel/boot, GPU (i915/nvidia-smi/nouveau clash), networking (WiFi driver + firmware + NM state), audio (ALSA + PipeWire), storage (zram + swap), services (machine-conditional), user/permissions, and machine-specific checks (SP6 SAM/battery, MBP applesmc/sensors, XPS PRIME/TLP, T5810 ECC errors). Exit code = failure count.

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
| `shared/35-intel-microcode.install` | Install to `/etc/kernel/preinst.d/` — quiet override for upstream Intel microcode hook (drops `--list-all --list` dump on every `make install`) |
| `shared/xhost-local.desktop` | XDG autostart: `xhost +local:` for X11 access |
| `patches/README.md` | Patch descriptions and upstream status |
| `patches/ipu-bridge-fix-double-brace.patch` | Fix double-brace build failure in ipu-bridge (gentoo-sources 6.12.58) |
| `patches/intel_idle-add-tiger-lake.patch` | Add Tiger Lake to intel_idle for proper C-state management |
| `shared/INSTALL_GOTCHAS.md` | Universal install known issues (28 lessons from all machines) |
| `shared/machine-checklist.md` | Universal onboarding checklist for new machines |
| `backlog.md` | Prioritized open items tracker |

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

- **AI verifier role**: Always-on Ollama HTTP service on `:11434` serving `qwen2.5:3b-instruct-q4_K_M` from `/data/ml-models/ollama/`. Firewall-restricted to local AI peers (T5810 primary, asrock-b550, 7960 VPN-only). RAPL PL1=35W/PL2=60W cap via `powercap-profile.sh` keeps thermals stable during sustained calls. Bigger nodes invoke via `tools/verify-llm.sh` for LLM-as-judge / schema / fact-check verification.
- **Kernel**: Linux 6.18.18-gentoo
- **Architecture**: x86_64, uniform 8C/16T (Tiger Lake-H, AVX-512)
- **Compiler flags**: `-march=tigerlake -O2 -pipe`
- **Key drivers**: i915 (module), nvidia 595.58.03 (proprietary), iwlwifi (AX203, module), nvme, snd_hda_intel, btusb, r8152 (USB Ethernet)
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
| `machines/xps-9510/powercap-profile.sh` | RAPL PL1/PL2 setter (35W/60W) — thermal envelope for sustained inference |
| `machines/xps-9510/powercap-profile.initd` | OpenRC service: apply RAPL caps at boot |
| `machines/xps-9510/ollama.confd` | Ollama daemon env: LAN bind, /data model storage, flash attention |
| `machines/xps-9510/ollama.initd` | OpenRC service for upstream Ollama binary |
| `machines/xps-9510/nftables-ollama.nft` | Firewall: restrict :11434 to T5810/asrock/7960 peers |
| `machines/xps-9510/nftables-ollama.initd` | OpenRC service: loads ruleset with `before ollama` ordering (no startup race) |
| `machines/xps-9510/INFERENCE_BASELINE.md` | Tokens/sec + thermal baseline template for the verifier model |

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

### Dell Precision T5810 (Harvested + Configs Generated)

- **Kernel**: Linux 6.18.16-gentoo (Production)
- **Architecture**: x86_64, 22C/44T (Broadwell-EP, AVX2, no AVX-512)
- **Compiler flags**: `-march=broadwell -O2 -pipe`
- **Key drivers**: nvidia 580.142 (2x GA102GL RTX A4500 Ampere, proprietary current branch, CUDA 13.0, compute 8.6), e1000e (I217-LM), nvme, ahci, snd_hda_intel (Realtek ALC3220 + 2x NVIDIA GA102 HDMI)
- **NVIDIA**: Ampere — current driver branch (no legacy pin). `kernel-open` modules supported (Turing+) but not enabled by default; closed-source modules in use.
- **NVLink**: 4-link bridge active between GPU0↔GPU1 (~56 GB/s per direction, `nvidia-smi topo -m` → NV4) — enables practical tensor parallelism across the 40 GB ECC pool
- **Firmware**: Loaded from /lib/firmware/ (nvidia/ga102/*)
- **No Intel iGPU**: Xeon E5 — discrete NVIDIA only
- **No WiFi**: Desktop workstation, wired Ethernet only
- **ECC**: 256GB DDR4 ECC (8x32GB Hynix), sb_edac EDAC driver
- **Performance**: C-states disabled in BIOS, GOV_PERFORMANCE, always-on workstation
- **Chipset**: C610/X99 (no LPSS/Pinctrl, I2C via i801 SMBus only)
- **AI compression layer**: Headroom proxy on `127.0.0.1:8787` (OpenRC service `headroom-proxy`) compresses LLM inputs before they reach vLLM. Validated at ~30% real prompt-token savings on cwdotcom-shaped RAG payloads with semantic preservation across factual recall, multi-fact, synthesis, and refusal-case queries. Venv at `~/.local/headroom-venv` (5.3 GB, slim `[proxy,ml,code]` extras). Local-only — no LAN exposure today.
- **Hardware ref**: `machines/precision-t5810/HARDWARE.md`

### Precision T5810 Machine-Specific Files

| File | Purpose |
|------|---------|
| `machines/precision-t5810/.config` | Kernel config (base from XPS 9510, needs kernel_config.sh + olddefconfig) |
| `machines/precision-t5810/make.conf` | Portage: `-march=broadwell`, VIDEO_CARDS="nvidia", 128GB tmpfs |
| `machines/precision-t5810/kernel_config.sh` | Generated programmatic kernel config (26 phases) |
| `machines/precision-t5810/HARDWARE.md` | Full hardware inventory |
| `machines/precision-t5810/sysctl-performance.conf` | VM/network tuning for 256GB RAM + NVMe |
| `machines/precision-t5810/zram-init.conf` | 16GB zstd compressed swap (safety net, 6% of RAM) |
| `machines/precision-t5810/world` | Package set (no WiFi/BT/laptop packages) |
| `machines/precision-t5810/package.accept_keywords` | ~amd64 keywords: gentoo-sources 6.18 LTS, NVIDIA |
| `machines/precision-t5810/package.use` | USE: installkernel+grub, NVIDIA, NM -wifi -bluetooth |
| `machines/precision-t5810/gentoo_install_part1.sh` | Partition Samsung 990 PRO 2TB NVMe (SABRENT exclusion) |
| `machines/precision-t5810/gentoo_install_part2.sh` | Stage3 + config staging + chroot prep |
| `machines/precision-t5810/gentoo_install_part3_chroot.sh` | 13-phase one-shot chroot install (NVIDIA, no WiFi) |
| `machines/precision-t5810/ONE_OFF_TOOLS.md` | Manual commands, tooling improvements, generalization learnings |
| `machines/precision-t5810/headroom-proxy.initd` | OpenRC service: Headroom proxy on :8787 (multi-turn agents; not used by cwdotcom — prefix-freeze mismatch) |
| `machines/precision-t5810/headroom-proxy.confd` | Env config for the proxy: bind, upstream URL (vLLM :8004), CCR off, log file |
| `machines/precision-t5810/headroom-lib-server.py` | FastAPI wrapper: exposes `headroom.compress()` library directly, bypasses proxy prefix-freeze (cwdotcom's fit) |
| `machines/precision-t5810/headroom-lib.initd` | OpenRC service: headroom-lib-server on :8788 (cwdotcom compression endpoint) |
| `machines/precision-t5810/headroom-lib.confd` | Env config for the lib server: bind 127.0.0.1:8788, shares venv with headroom-proxy |
| ~~`machines/precision-t5810/harvest/`~~ | Harvest logs not committed (generated at `/tmp/t5810-harvest/` during build) |

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
| `machines/surface-pro-6/INSTALL_GOTCHAS.md` | 21 lessons learned from prior builds |
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
| `machines/surface-pro-6/logind-idle-hibernate.conf` | elogind drop-in: hibernate after 15min idle (safety net) |
| `machines/surface-pro-6/xfce4-power-manager.sh` | XFCE PM + screensaver idle config (hibernate 10min battery) |
| `machines/surface-pro-6/xidletime.c` | X11 idle time query tool (libXss, compile with gcc -lX11 -lXss) |
| `machines/surface-pro-6/idle-hint-bridge.sh` | Bridge X11 idle → elogind IdleHint (xfce4-screensaver workaround) |
| `machines/surface-pro-6/idle-hint-bridge.desktop` | XDG autostart for idle-hint-bridge |
| `machines/surface-pro-6/resume-device.start` | Set /sys/power/resume at boot (enables hibernate with swap file) |
| `machines/surface-pro-6/gentoo_install_part3_chroot.sh` | 13-phase one-shot chroot install |

### ASRock B550 Phantom Gaming-ITX/ax (Production)

- **Kernel**: Linux 6.18.21-gentoo
- **Architecture**: x86_64, 16C/32T (Zen 3 / Vermeer, AVX2, SHA, no AVX-512)
- **Compiler flags**: `-march=znver3 -O2 -pipe`
- **Key drivers**: nvidia (RTX 5060 Ti GB206 Blackwell 16GB, kernel-open REQUIRED), iwlwifi (AX200), igc (I225-V 2.5GbE), nvme, ahci, snd_hda_intel, btusb+btintel, k10temp, ccp, piix4_smbus
- **Firmware**: Loaded from /lib/firmware/ (iwlwifi-cc-a0-*, intel/ibt-0040-0041.*, nvidia/gb206/*, amd-ucode/*)
- **Critical**: First AMD build — no Intel iGPU, DRM_I915 disabled, piix4 I2C (not i801)
- **NVIDIA**: GB206 Blackwell REQUIRES kernel-open modules (closed-source not supported for Blackwell), nvidia-drivers 595.58.03, CUDA 13.2
- **No ECC**: 64GB DDR4-3200 (2x32GB Corsair), non-ECC
- **Hardware ref**: `machines/asrock-b550/HARDWARE.md`

### ASRock B550 Machine-Specific Files

| File | Purpose |
|------|---------|
| `machines/asrock-b550/kernel_config.sh` | 22-phase programmatic kernel config (Zen 3 + NVIDIA Ampere) |
| `machines/asrock-b550/make.conf` | Portage: `-march=znver3`, VIDEO_CARDS="nvidia", 46GB tmpfs |
| `machines/asrock-b550/HARDWARE.md` | Full hardware inventory |
| `machines/asrock-b550/world` | Package set (WiFi + BT + NVIDIA) |
| `machines/asrock-b550/package.accept_keywords` | ~amd64 keywords: gentoo-sources 6.18 LTS, NVIDIA |
| `machines/asrock-b550/package.use` | USE: installkernel+grub, NVIDIA kernel-open, NM wifi+bluetooth |
| `machines/asrock-b550/package.env` | Large package disk fallback (7 packages) |
| `machines/asrock-b550/portage_env_notmpfs.conf` | Disk PORTAGE_TMPDIR for large builds |
| `machines/asrock-b550/sysctl-performance.conf` | VM/network tuning for 64GB RAM + NVMe |
| `machines/asrock-b550/zram-init.conf` | 8GB zstd compressed swap config |
| `machines/asrock-b550/gentoo_install_part1.sh` | Partition MAXIO MAP1202 2TB NVMe |
| `machines/asrock-b550/gentoo_install_part2.sh` | Stage3 + config staging + chroot prep |
| `machines/asrock-b550/gentoo_install_part3_chroot.sh` | 13-phase one-shot chroot install (WiFi + BT + NVIDIA) |

### Beelink MINI S (Production)

- **Kernel**: Linux 6.18.22-gentoo
- **Architecture**: x86_64, 4C/4T (Jasper Lake / Tremont, no HT, no AVX/AVX2)
- **Compiler flags**: `-march=tremont -O2 -pipe`
- **Key drivers**: i915 (module, JSL UHD Gen11 LP), iwlwifi (Wireless-AC 3165), r8169 (RTL8168h GbE), ahci (SATA SSD), snd_hda_intel, btusb+btintel
- **Firmware**: Loaded from /lib/firmware/ (i915/icl_dmc_*, iwlwifi-7265D-*, regulatory.db)
- **No NVIDIA**: Intel iGPU only
- **Storage**: 256GB M.2 SATA SSD (no NVMe on this board), ext4 root
- **RAM**: 8GB DDR4-2666 single-channel (1 of 2 SODIMM slots populated)
- **Always-on**: elogind drop-in disables all sleep/suspend, no lid (mini PC)
- **Network**: Wired Ethernet primary (r8169), WiFi available (iwlwifi 3165)
- **Hardware ref**: `machines/beelink-minis/HARDWARE.md`

### Beelink MINI S Machine-Specific Files

| File | Purpose |
|------|---------|
| `machines/beelink-minis/kernel_config.sh` | Programmatic kernel config (Jasper Lake + SATA + WiFi) |
| `machines/beelink-minis/make.conf` | Portage: `-march=tremont`, VIDEO_CARDS="intel", 4GB tmpfs |
| `machines/beelink-minis/HARDWARE.md` | Full hardware inventory |
| `machines/beelink-minis/INSTALL_GOTCHAS.md` | Install lessons learned |
| `machines/beelink-minis/world` | Package set (WiFi + BT, no NVIDIA) |
| `machines/beelink-minis/package.accept_keywords` | ~amd64 keywords: gentoo-sources 6.18 LTS |
| `machines/beelink-minis/package.use` | USE: installkernel+grub, NM wifi+bluetooth |
| `machines/beelink-minis/package.env` | Large package disk fallback |
| `machines/beelink-minis/portage_env_notmpfs.conf` | Disk PORTAGE_TMPDIR for large builds |
| `machines/beelink-minis/sysctl-performance.conf` | VM/network tuning for 8GB RAM + SATA |
| `machines/beelink-minis/zram-init.conf` | 4GB zstd compressed swap config |
| `machines/beelink-minis/grub` | GRUB defaults |
| `machines/beelink-minis/gentoo_install_part1.sh` | Partition 256GB SATA SSD |
| `machines/beelink-minis/gentoo_install_part2.sh` | Stage3 + config staging + chroot prep |
| `machines/beelink-minis/gentoo_install_part3_chroot.sh` | 13-phase one-shot chroot install (WiFi + BT + always-on) |

### Dell OptiPlex 3090 SFF (Production)

- **Kernel**: Linux 6.18.24-gentoo
- **Architecture**: x86_64, 6C/12T (Comet Lake / Skylake-derived, AVX2, no AVX-512)
- **Compiler flags**: `-march=skylake -O2 -pipe`
- **Key drivers**: i915 (UHD 630, Comet Lake-S GT2), nvidia (RTX A1000 GA107 Ampere, kernel-open), r8169 (Realtek RTL8168 GbE), nvme, ahci, snd_hda_intel + snd_sof_pci_intel_cnl (Realtek ALC3246 + NVIDIA HDMI), dell_smbios, dell_wmi
- **Firmware**: Loaded from /lib/firmware/ (i915/kbl_dmc_*, nvidia/ga107/*, intel-ucode 0x000a0655)
- **CRITICAL — BIOS RAID trap**: Q470 SATA controller defaults to Intel RST/RAID mode. Must switch to **AHCI** in BIOS before Linux can see the NVMe. Switching breaks any pre-existing Windows boot unless prepped (Safe Boot trick).
- **Hybrid GPU**: Intel UHD 630 + NVIDIA A1000 — desktop, no Optimus power switching needed (nvidia-drivers as primary, intel iGPU available for DisplayPort outputs)
- **NVIDIA**: GA107 Ampere → kernel-open modules eligible (Turing+), latest nvidia-drivers branch (no legacy pin)
- **No WiFi/BT**: Dell SFF, wired only
- **RAM**: 16GB DDR4-2666 single-channel (1 of 2 slots populated, M378A2G43BB3-CWE) — adding 2nd 16GB DIMM doubles memory bandwidth
- **Storage**: 256GB M.2 2230 NVMe, no secondary SATA disk
- **Build profile**: CONSTRAINED (16GB → 7GB tmpfs + disk fallback for chromium/llvm/rust/qtwebengine/gcc)
- **Power/Thermal**: intel_pstate active, S3 deep + hibernate supported. SFF thermals tighter than tower — sustained turbo may downclock
- **Hardware ref**: `machines/optiplex-3090/HARDWARE.md`

### OptiPlex 3090 Machine-Specific Files

| File | Purpose |
|------|---------|
| `machines/optiplex-3090/kernel_config.sh` | Programmatic kernel config (auto-generated, Comet Lake + i915 + NVIDIA) |
| `machines/optiplex-3090/make.conf` | Portage: `-march=skylake`, VIDEO_CARDS="intel iris nvidia", 7GB tmpfs |
| `machines/optiplex-3090/HARDWARE.md` | Full hardware inventory + BIOS AHCI flip warning |
| `machines/optiplex-3090/world` | Package set (NVIDIA, no WiFi/BT, no laptop power mgmt) |
| `machines/optiplex-3090/package.accept_keywords` | ~amd64 keywords: gentoo-sources 6.18 LTS |
| `machines/optiplex-3090/package.use` | USE: installkernel+grub, NVIDIA kernel-open, NM -wifi -bluetooth |
| `machines/optiplex-3090/package.env` | Large package disk fallback (chromium/llvm/rust/qtwebengine/gcc/google-chrome) |
| `machines/optiplex-3090/portage_env_notmpfs.conf` | Disk PORTAGE_TMPDIR for large builds |
| `machines/optiplex-3090/sysctl-performance.conf` | VM/network tuning for 16GB RAM + NVMe |
| `machines/optiplex-3090/zram-init.conf` | 8GB zstd compressed swap (50% of RAM, real working swap) |
| `machines/optiplex-3090/99-module-rebuild.install` | Kernel postinst hook: auto `emerge @module-rebuild` for NVIDIA |
| `machines/optiplex-3090/gentoo_install_part1.sh` | Partition 256GB NVMe (TARGET=/dev/nvme0n1, requires AHCI in BIOS) |
| `machines/optiplex-3090/gentoo_install_part2.sh` | Stage3 + config staging + chroot prep |
| `machines/optiplex-3090/gentoo_install_part3_chroot.sh` | 13-phase one-shot chroot install (NVIDIA, no WiFi) |

## Future Machine Notes

- **OptiPlex 3090 SFF**: Production. Installed 2026-04-28, first boot straight to desktop. i5-10505 (Comet Lake, 6C/12T, no AVX-512), 16GB DDR4-2666 single-channel (1 of 2 slots populated), Intel UHD 630 + NVIDIA RTX A1000 8GB GDDR6 (GA107 Ampere, kernel-open, nvidia 595.58.03), no WiFi/BT, Realtek RTL8168 GbE, 256GB M.2 2230 NVMe, `-march=skylake`, Q470 chipset. Base: precision-t5810. **CRITICAL**: BIOS ships with SATA in Intel RST/RAID mode — must switch to AHCI before Linux can see the NVMe. 7GB tmpfs + disk fallback (CONSTRAINED 16GB profile). S3 deep + hibernate supported.
- **Beelink MINI S**: Production. Celeron N5095A (4C/4T, Jasper Lake/Tremont), 8GB DDR4-2666 single-channel, Intel UHD Gen11 LP, Intel 3165 WiFi/BT, Realtek GbE, 256GB M.2 SATA SSD, `-march=tremont`. Installed 2026-04-15. Always-on mini PC. 4GB tmpfs + disk fallback. S3 deep sleep supported but disabled (always-on).
- **ASRock B550**: Production. First AMD build. Ryzen 9 5950X (16C/32T, Zen 3), 64GB DDR4-3200, NVIDIA RTX 5060 Ti (GB206 Blackwell 16GB GDDR7, kernel-open REQUIRED), Intel AX200 WiFi/BT, Intel I225-V 2.5GbE, MAXIO MAP1202 2TB NVMe, `-march=znver3`, AMD B550 chipset. Installed 2026-04-05. GPU upgraded from RTX 3060 Ti (GA104 Ampere 8GB) 2026-07-24. 1TB SATA SSD unused. 46GB tmpfs + disk fallback. S3 deep sleep supported.
- **Precision T5810**: Broadwell-EP Xeon E5-2699v4 (22C/44T) — 256GB DDR4 ECC, 2x NVIDIA RTX A4500 (GA102GL Ampere, 20GB GDDR6 ECC each, NVLink-bridged for 40GB tensor-parallel pool, compute 8.6), Samsung 990 PRO 2TB NVMe, `-march=broadwell`, C610/X99 chipset. Harvest + configs generated 2026-03-11; GPUs upgraded from 2x GTX 1050 Ti (Pascal) to 2x A4500 + NVLink for AI/ML workloads (driver 580.142, current branch — no legacy pin). Performance-first (no power savings). Boot media: SABRENT Ventoy USB (DO NOT TOUCH).
- **Precision 7960**: Reference only — stays on RHEL 10.1 production for AI/ML, no Gentoo install. Harvested 2026-03-19; **GPU config has since changed** — re-harvest pending for PCI-level details. Xeon W5-3433 16C/32T (Sapphire Rapids, AVX-512 + AMX), 128GB DDR5 ECC, **RTX PRO 6000 Blackwell 96GB GDDR7 (600W) + RTX 5080 16GB GDDR7 Blackwell** (the original secondary RTX A1000 was relocated to the OptiPlex 3090). NVIDIA 590.48.01 CUDA 13.1 at last harvest, 4x Samsung PM9C1a 1.8TB RAID10 via VMD, Aquantia 10GbE + Intel 1GbE, `-march=sapphirerapids`
- **Surface Pro 9**: Will need linux-surface kernel patches for touchscreen, cameras, battery, etc. (Surface Pro 6 runs without them — touchscreen is a HW defect on this unit).
