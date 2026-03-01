# gentoo_config

Multi-machine Gentoo Linux kernel configurations and portage settings. Each machine has a tuned kernel `.config`, `make.conf`, and hardware documentation.

## Machines

| Machine | CPU | GPU | Kernel Status | Current OS |
|---------|-----|-----|---------------|------------|
| [Dell XPS 13 9315](machines/xps-9315/) | i5-1230U (Alder Lake) | Intel Iris Xe | **Production** | Gentoo |
| [Intel NUC11TNBi5](machines/nuc11/) | i5-1135G7 (Tiger Lake) | Intel Iris Xe | **Ready to build** | Ubuntu |
| [Dell XPS 15 9510](machines/xps-9510/) | i7-11800H (Tiger Lake-H) | Intel UHD + NVIDIA RTX 3050 Ti | **Production** | Gentoo |
| [MacBook Pro 12,1 (2015)](machines/mbp-2015/) | i7-5557U (Broadwell) | Intel Iris 6100 | **Production** | Gentoo |
| [ASRock B550](machines/asrock-b550/) | Ryzen 9 5950X | NVIDIA RTX 3060 Ti | Planned | Fedora 42 |
| [Dell Precision T5810](machines/precision-t5810/) | Xeon E5-2699v4 | TBD | Planned | Fedora 42 |
| [Dell Precision 7960](machines/precision-7960/) | Xeon W5-3433 | RTX Pro 6000 96GB + RTX A1000 8GB | Planned | RHEL 10.1 |
| [Surface Pro 6](machines/surface-pro-6/) | i5-8250U (Kaby Lake-R) | Intel UHD 620 | **Ready to install** | Fedora 43 |
| [Surface Pro 9](machines/surface-pro-9/) | 12th Gen Intel | Intel Iris Xe | Planned | Windows 11 Pro |

NVIDIA machines will use **proprietary nvidia-drivers**. Surface machines will need **linux-surface** kernel patches.

## Repository Layout

```
gentoo_config/
├── machines/
│   ├── xps-9315/          # Dell XPS 13 9315 (Alder Lake) - PRODUCTION
│   │   ├── .config        # Linux kernel configuration
│   │   ├── make.conf      # Portage build settings (-march=alderlake)
│   │   ├── fstab          # Filesystem layout template
│   │   ├── grub           # GRUB bootloader config
│   │   ├── HARDWARE.md    # Hardware reference
│   │   └── INSTALL.md     # Step-by-step installation guide
│   ├── nuc11/             # Intel NUC11TNBi5 (Tiger Lake) - READY
│   │   ├── .config        # Kernel config (derived from xps-9315)
│   │   ├── make.conf      # Portage build settings (-march=tigerlake)
│   │   └── HARDWARE.md    # Hardware reference
│   ├── xps-9510/          # Dell XPS 15 9510 (Tiger Lake-H + NVIDIA) - PRODUCTION
│   │   ├── .config        # Kernel config (hybrid GPU, USB-C hub, perf tuning)
│   │   ├── make.conf      # Portage build settings (-march=tigerlake)
│   │   ├── fstab          # Dual NVMe layout
│   │   ├── grub           # GRUB config (i915 GuC, NVIDIA dynamic power)
│   │   ├── HARDWARE.md    # Hardware + software environment reference
│   │   └── ...            # sysctl, zram, ksm, prime-run, module-rebuild hook
│   ├── mbp-2015/          # MacBook Pro 12,1 Early 2015 (Broadwell) - PRODUCTION
│   │   ├── .config        # Kernel config (Apple HW, THP/MGLRU tuning)
│   │   ├── make.conf      # Portage build settings (-march=broadwell)
│   │   ├── fstab          # Single SSD layout
│   │   ├── grub           # GRUB config (libata.force=noncq, reboot=pci)
│   │   ├── HARDWARE.md    # Hardware reference
│   │   └── ...            # mbpfan, zram, hotkeys, install scripts, wifi fix
│   ├── surface-pro-6/     # Surface Pro 6 (Kaby Lake-R) - READY TO INSTALL
│   │   ├── make.conf      # Portage build settings (-march=skylake)
│   │   ├── kernel_config.sh  # Programmatic kernel config (generated at install)
│   │   ├── HARDWARE.md    # Hardware reference (5 harvest rounds)
│   │   └── ...            # 3-phase install scripts, IPTSD, docs
│   ├── asrock-b550/       # ASRock B550 / Ryzen 9 5950X - PLANNED
│   ├── precision-t5810/   # Dell Precision T5810 / Xeon E5 - PLANNED
│   ├── precision-7960/    # Dell Precision 7960 / Xeon W5 - PLANNED
│   └── surface-pro-9/     # Surface Pro 9 - PLANNED
├── tools/
│   ├── harvest.sh         # General-purpose hardware inventory
│   ├── deep_harvest.sh    # Deep hardware discovery
│   ├── build-kernel-remote.sh  # Cross-compile and deploy kernels
│   └── generate-config.sh # AI-powered config generation (uses Claude CLI)
├── shared/
│   ├── world              # Common installed package list
│   ├── package.use        # Per-package USE flags
│   ├── package.accept_keywords
│   ├── package.license
│   ├── openrc-services    # OpenRC service configuration
│   ├── portage-env        # Portage environment overrides
│   ├── restore-desktop.sh # XFCE desktop restore (keybindings, panels, displays)
│   ├── restore-system.sh  # System restore (elogind, ACPI, LightDM)
│   ├── fstrim-weekly      # SSD TRIM maintenance script
│   └── ...                # LightDM, logind, ACPI, touchpad, KSM configs
├── patches/               # Kernel patches
│   ├── ipu-bridge-fix-double-brace.patch
│   └── intel_idle-add-tiger-lake.patch
├── CLAUDE.md
├── INSTALL.md              # General-purpose installation guide
└── README.md
```

## Quick Start

### Deploy an existing config

```bash
# Copy machine config to kernel source
cp machines/xps-9315/.config /usr/src/linux/.config

# Build
cd /usr/src/linux
make olddefconfig
make -j$(nproc)

# Install (as root)
make modules_install
make install
grub-mkconfig -o /boot/grub/grub.cfg
```

### Cross-compile on a build host

```bash
# Build XPS kernel on a powerful machine, deploy over SSH
tools/build-kernel-remote.sh xps-9315 all

# Build NUC11 kernel
tools/build-kernel-remote.sh nuc11 all
```

### Harvest hardware info from a new machine

```bash
# Run on the target machine (requires root)
sudo tools/harvest.sh           # Basic inventory
sudo -E tools/deep_harvest.sh   # Deep discovery with module list
```

### Generate config for a new machine (AI-powered)

```bash
# Requires Claude CLI (claude command)
# Analyzes harvest data against a base config to generate .config, make.conf, HARDWARE.md
tools/generate-config.sh precision-t5810 nuc11 /tmp/t5810-harvest/
```

### Full installation

See **[INSTALL.md](INSTALL.md)** for the complete step-by-step guide that works on any supported machine.

## Portage Configuration

Shared portage files in `shared/` work across all machines. Machine-specific settings (compiler flags, video cards) are in each machine's `make.conf`.

### Common Settings
- **Profile**: `default/linux/amd64/23.0`
- **Init**: OpenRC (no systemd)
- **Desktop**: XFCE with LightDM
- **Python**: 3.12 / 3.13

### Per-Machine Differences

| Setting | XPS 9315 | XPS 9510 | MBP 2015 | NUC11 | Surface Pro 6 | Future AMD |
|---------|----------|----------|----------|-------|---------------|------------|
| `-march=` | `alderlake` | `tigerlake` | `broadwell` | `tigerlake` | `skylake` | `znver3` |
| `VIDEO_CARDS` | `intel iris` | `intel iris nvidia` | `intel` | `intel iris` | `intel` | `nvidia` |
| AVX-512 | No | Yes | No | Yes | No | No |
| Hybrid cores | Yes | No | No | No | No | No |

## Upstream Contributions

- **[Bug 970769](https://bugs.gentoo.org/970769)** — Reported double-brace typo in `drivers/media/pci/intel/ipu-bridge.c` in gentoo-sources-6.12.58. Causes build failure with GCC <15. Fixed in mainline Linux; Gentoo-specific backport error. Patch included in `patches/`.

## Machine Notes

### Production: XPS 9510 (Hybrid GPU)
Intel iGPU + NVIDIA RTX 3050 Ti with PRIME/Optimus, proprietary nvidia-drivers 590.48. PipeWire audio, SSTP VPN, thermald + tlp power management. Dual NVMe, 32GB RAM, zram 8GB zstd swap.

### Production: MacBook Pro 12,1 (2015)
Broadwell i7 with full Apple hardware support: applesmc, mbpfan, bcm5974 trackpad, brcmfmac WiFi, CS4208 audio. Battery via ACPI_SBS, THP/MGLRU/zram tuning. Fn hotkeys via acpilight + xfconf.

### Ready: Surface Pro 6
Kaby Lake-R i5, Marvell WiFi (not Intel), 8GB RAM. 3-phase automated install scripts ready. Config generated at install time via `kernel_config.sh`. IPTSD touch daemon configured (touchscreen HW defective on this unit).

### Future: ASRock B550 (First AMD)
Ryzen 9 5950X with SATA SSDs. Needs `CONFIG_CPU_SUP_AMD`, `CONFIG_AMD_IOMMU`, `-march=znver3`.

### Future: Precision T5810 (Xeon Broadwell-EP)
ECC memory, `-march=broadwell`, older PCH. Currently runs Fedora 42.

### Future: Precision 7960 (Multi-GPU Xeon W)
Most complex config: dual NVIDIA GPUs (RTX Pro 6000 96GB + RTX A1000 8GB), Xeon W5-3433. Currently runs RHEL 10.1.

### Future: Surface Pro 9
12th Gen Intel Alder Lake, requires linux-surface kernel patches. Currently runs Windows 11 Pro.
