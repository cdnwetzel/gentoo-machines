# gentoo-machines

Multi-machine Gentoo Linux kernel configurations, portage settings, and automated install tooling. Each machine has a tuned kernel `.config`, `make.conf`, programmatic `kernel_config.sh`, and hardware documentation derived from live harvesting.

## Machines

| Machine | CPU | GPU | Status | Current OS |
|---------|-----|-----|--------|------------|
| [Dell XPS 15 9510](machines/xps-9510/) | i7-11800H (Tiger Lake-H) | Intel UHD + NVIDIA RTX 3050 Ti | **Production** | Gentoo |
| [MacBook Pro 12,1 (2015)](machines/mbp-2015/) | i7-5557U (Broadwell) | Intel Iris 6100 | **Production** | Gentoo |
| [Surface Pro 6](machines/surface-pro-6/) | i5-8250U (Kaby Lake-R) | Intel UHD 620 | **Production** | Gentoo |
| [Dell XPS 13 9315](machines/xps-9315/) | i5-1230U (Alder Lake) | Intel Iris Xe | Configs updated | Windows (returned) |
| [Intel NUC11TNBi5](machines/nuc11/) | i5-1135G7 (Tiger Lake) | Intel Iris Xe | Ready to build | Ubuntu |
| [ASRock B550](machines/asrock-b550/) | Ryzen 9 5950X | NVIDIA RTX 3060 Ti | Planned | Fedora 42 |
| [Dell Precision T5810](machines/precision-t5810/) | Xeon E5-2699v4 | TBD | Planned | Fedora 42 |
| [Dell Precision 7960](machines/precision-7960/) | Xeon W5-3433 | RTX Pro 6000 96GB + RTX A1000 8GB | Harvest only | RHEL 10.1 |
| [Surface Pro 9](machines/surface-pro-9/) | 12th Gen Intel | Intel Iris Xe | Planned | Windows 11 Pro |

NVIDIA machines use **proprietary nvidia-drivers**. The Precision 7960 stays on RHEL 10.1 for production AI/ML workloads.

## Repository Layout

```
gentoo-machines/
├── machines/
│   ├── xps-9510/          # Dell XPS 15 9510 (Tiger Lake-H + NVIDIA) - PRODUCTION
│   │   ├── .config        # Kernel config (hybrid GPU, USB-C hub, perf tuning)
│   │   ├── make.conf      # Portage build settings (-march=tigerlake)
│   │   ├── kernel_config.sh  # 26-phase programmatic kernel config
│   │   ├── fstab          # Dual NVMe layout
│   │   ├── grub           # GRUB config (i915 GuC, NVIDIA dynamic power)
│   │   ├── HARDWARE.md    # Hardware + software environment reference
│   │   └── ...            # sysctl, zram, tlp, prime-run, 3-phase install scripts
│   ├── mbp-2015/          # MacBook Pro 12,1 Early 2015 (Broadwell) - PRODUCTION
│   │   ├── .config        # Kernel config (Apple HW, THP/MGLRU tuning)
│   │   ├── make.conf      # Portage build settings (-march=broadwell)
│   │   ├── kernel_config.sh  # Programmatic kernel config (Apple-specific)
│   │   ├── fstab          # Single SSD layout
│   │   ├── grub           # GRUB config (libata.force=noncq, reboot=pci)
│   │   ├── HARDWARE.md    # Hardware reference
│   │   └── ...            # mbpfan, zram, hotkeys, 3-phase install scripts, wifi fix
│   ├── surface-pro-6/     # Surface Pro 6 (Kaby Lake-R) - PRODUCTION
│   │   ├── make.conf      # Portage build settings (-march=skylake)
│   │   ├── kernel_config.sh  # Programmatic kernel config (Marvell WiFi, Surface HW)
│   │   ├── HARDWARE.md    # Hardware reference (5 harvest rounds)
│   │   └── ...            # 3-phase install scripts, HiDPI, IPTSD, WiFi power save fix
│   ├── xps-9315/          # Dell XPS 13 9315 (Alder Lake) - CONFIGS UPDATED
│   │   ├── .config        # Kernel config
│   │   ├── make.conf      # Portage build settings (-march=alderlake)
│   │   └── HARDWARE.md    # Hardware reference
│   ├── nuc11/             # Intel NUC11TNBi5 (Tiger Lake) - READY TO BUILD
│   │   ├── .config        # Kernel config (derived from xps-9315)
│   │   ├── make.conf      # Portage build settings (-march=tigerlake)
│   │   └── HARDWARE.md    # Hardware reference
│   ├── asrock-b550/       # ASRock B550 / Ryzen 9 5950X - PLANNED
│   ├── precision-t5810/   # Dell Precision T5810 / Xeon E5 - PLANNED
│   ├── precision-7960/    # Dell Precision 7960 / Xeon W5 - HARVEST ONLY
│   └── surface-pro-9/     # Surface Pro 9 - PLANNED
├── tools/
│   ├── harvest.sh         # General-purpose hardware inventory (15 sections)
│   ├── deep_harvest.sh    # Deep hardware discovery with module/firmware detection
│   ├── kconfig-lint.sh    # Static kernel config validator (5 checks, 19K symbols)
│   ├── kernel-config-template.sh  # Auto-generate kernel_config.sh from harvest data
│   ├── build-kernel-remote.sh     # Cross-compile and deploy kernels over SSH
│   └── generate-config.sh         # AI-powered config generation (uses Claude CLI)
├── shared/
│   ├── world              # Common installed package list
│   ├── package.use        # Per-package USE flags
│   ├── package.accept_keywords
│   ├── package.license
│   ├── openrc-services    # OpenRC service configuration reference
│   ├── restore-desktop.sh # XFCE desktop restore (keybindings, panels, HiDPI auto-detect)
│   ├── restore-system.sh  # System restore (elogind, ACPI, LightDM)
│   ├── fstrim-weekly      # SSD TRIM maintenance script
│   └── ...                # LightDM, logind, ACPI, touchpad, KSM configs
├── patches/               # Kernel patches with upstream investigation notes
│   ├── ipu-bridge-fix-double-brace.patch
│   └── intel_idle-add-tiger-lake.patch
├── CLAUDE.md              # AI assistant context (project structure, machine details)
├── INSTALL.md             # General-purpose installation guide (any machine)
└── README.md
```

## Tools

### harvest.sh — Hardware Inventory
General-purpose hardware discovery (15 sections). Works on any Linux distribution. Detects CPU, GPU, WiFi, audio (SOF vs HDA), storage, platform vendor, boot type, suspend capabilities, loaded firmware, and suggests GCC `-march` flags.

```bash
sudo tools/harvest.sh
```

### kconfig-lint.sh — Kernel Config Validator
Static analysis for `kernel_config.sh` scripts. Parses all Kconfig files (~19K symbols) and cross-references every `scripts/config` call against the kernel source tree. Catches 5 classes of silent bugs:

| Severity | Check | Example |
|----------|-------|---------|
| FAIL | `--module` on bool option | `SND_SOC_SOF_INTEL_TOPLEVEL` silently ignored |
| WARN | Missing parent toggle | Dell drivers invisible without `X86_PLATFORM_DRIVERS_DELL` |
| WARN | Firmware driver built-in (=y) | `DRM_I915=y` without initramfs |
| WARN | Unsatisfied dependency | Dep not set anywhere in script |
| INFO | Unknown config option | Typos, renamed symbols, wrong kernel version |

```bash
tools/kconfig-lint.sh machines/xps-9510/kernel_config.sh [/usr/src/linux]
```

### kernel-config-template.sh — Config Skeleton Generator
Auto-generates a complete `kernel_config.sh` from harvest data. Detects CPU, GPU (Intel/NVIDIA/AMD), WiFi (8 vendors), audio (SOF/HDA + codec), storage, platform (Dell/Apple/Surface/Lenovo/HP/ASUS), Ethernet, Thunderbolt, ISH sensors, cameras. Outputs a 26-phase script and auto-runs kconfig-lint on the result.

```bash
tools/kernel-config-template.sh <machine-name> <harvest-log>
```

### generate-config.sh — AI-Powered Config Generation
Uses Claude CLI to analyze harvest data against a base config and generate `.config`, `make.conf`, and `HARDWARE.md`.

```bash
tools/generate-config.sh <new-machine> <base-machine> <harvest-dir>
```

### build-kernel-remote.sh — Cross-Compile and Deploy
Build kernels on a powerful host and deploy over SSH.

```bash
tools/build-kernel-remote.sh <target> {pull|build|deploy|all}
```

## Quick Start

### Deploy an existing config

```bash
cp machines/<machine>/.config /usr/src/linux/.config
cd /usr/src/linux
make olddefconfig
make -j$(nproc)
make modules_install
make install
grub-mkconfig -o /boot/grub/grub.cfg
```

### Full installation

See **[INSTALL.md](INSTALL.md)** for the complete step-by-step guide. Each production machine also has 3-phase automated install scripts (`gentoo_install_part{1,2,3}_chroot.sh`) for reproducible installs.

## Portage Configuration

Shared portage files in `shared/` work across all machines. Machine-specific settings (compiler flags, video cards) are in each machine's `make.conf`.

### Common Settings
- **Profile**: `default/linux/amd64/23.0`
- **Init**: OpenRC (no systemd)
- **Desktop**: XFCE with LightDM
- **Python**: 3.13 / 3.14

### Per-Machine Differences

| Setting | XPS 9510 | MBP 2015 | Surface Pro 6 | NUC11 | XPS 9315 | Future AMD |
|---------|----------|----------|---------------|-------|----------|------------|
| `-march=` | `tigerlake` | `broadwell` | `skylake` | `tigerlake` | `alderlake` | `znver3` |
| `VIDEO_CARDS` | `intel iris nvidia` | `intel` | `intel` | `intel iris` | `intel iris` | `nvidia` |
| AVX-512 | Yes | No | No | Yes | No | No |
| Hybrid cores | No | No | No | No | Yes | No |

## Machine Notes

### Production: XPS 9510 (Hybrid GPU)
Intel iGPU + NVIDIA RTX 3050 Ti with PRIME/Optimus, proprietary nvidia-drivers. PipeWire audio, SSTP VPN, thermald + tlp power management. Dual NVMe, 32GB RAM, zram 8GB zstd swap. Full 3-phase automated install.

### Production: MacBook Pro 12,1 (2015)
Broadwell i7 with full Apple hardware support: applesmc (35 sensors), mbpfan (fan control), bcm5974 (trackpad), brcmfmac (BCM43602 WiFi), CS4208 (audio). GRUB with `--removable` for Apple EFI. THP/MGLRU/zram tuning, Fn hotkeys via acpilight. Full 3-phase automated install.

### Production: Surface Pro 6
Kaby Lake-R i5, Marvell 88W8897 WiFi (not Intel), 8GB RAM. 2736x1824 PixelSense display with 150% HiDPI scaling. WiFi power save workarounds for suspend reliability. Full 3-phase automated install with HiDPI configuration throughout (LightDM, XFCE, GTK greeter).

### Harvest Only: Precision 7960 (Multi-GPU Xeon W)
Dual NVIDIA GPUs (RTX Pro 6000 96GB + RTX A1000 8GB), Xeon W5-3433. Stays on RHEL 10.1 for production AI/ML workloads. Hardware harvested for reference only.

### Planned: ASRock B550 (First AMD)
Ryzen 9 5950X with SATA SSDs. First AMD build — needs `CONFIG_CPU_SUP_AMD`, `CONFIG_AMD_IOMMU`, `-march=znver3`.

### Planned: Precision T5810 (Xeon Broadwell-EP)
ECC memory, `-march=broadwell`, older PCH. Currently runs Fedora 42.
