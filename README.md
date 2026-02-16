# gentoo_config

Multi-machine Gentoo Linux kernel configurations and portage settings. Each machine has a tuned kernel `.config`, `make.conf`, and hardware documentation.

## Machines

| Machine | CPU | GPU | Kernel Status | Current OS |
|---------|-----|-----|---------------|------------|
| [Dell XPS 13 9315](machines/xps-9315/) | i5-1230U (Alder Lake) | Intel Iris Xe | **Production** | Gentoo |
| [Intel NUC11TNBi5](machines/nuc11/) | i5-1135G7 (Tiger Lake) | Intel Iris Xe | **Ready to build** | Ubuntu |
| [Dell XPS 15 9510](machines/xps-9510/) | 11th Gen Intel | Intel + NVIDIA RTX 3050 Ti | Planned | Ubuntu 24.04 LTS |
| [ASRock B550](machines/asrock-b550/) | Ryzen 9 5950X | NVIDIA RTX 3060 Ti | Planned | Fedora 42 |
| [Dell Precision T5810](machines/precision-t5810/) | Xeon E5-2699v4 | TBD | Planned | Fedora 42 |
| [Dell Precision 7960](machines/precision-7960/) | Xeon W5-3433 | RTX Pro 6000 96GB + RTX A1000 8GB | Planned | RHEL 10.1 |
| [Surface Pro 6](machines/surface-pro-6/) | 8th Gen Intel | Intel UHD 620 | Planned | Fedora 43 |
| [Surface Pro 9](machines/surface-pro-9/) | 12th Gen Intel | Intel Iris Xe | Planned | Windows 11 Pro |

NVIDIA machines will use **proprietary nvidia-drivers**.

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
│   ├── xps-9510/          # Dell XPS 15 9510 - PLANNED
│   ├── asrock-b550/       # ASRock B550 / Ryzen 9 5950X - PLANNED
│   ├── precision-t5810/   # Dell Precision T5810 / Xeon E5 - PLANNED
│   ├── precision-7960/    # Dell Precision 7960 / Xeon W5 - PLANNED
│   ├── surface-pro-6/     # Surface Pro 6 - PLANNED
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
│   └── portage-env        # Portage environment overrides
├── patches/               # Kernel patches
│   └── ipu-bridge-fix-double-brace.patch
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

| Setting | XPS 9315 | NUC11 | Future AMD |
|---------|----------|-------|------------|
| `-march=` | `alderlake` | `tigerlake` | `znver3` |
| `VIDEO_CARDS` | `intel iris` | `intel iris` | `nvidia` |
| AVX-512 | No | Yes | No |
| Hybrid cores | Yes | No | No |

## Machine Notes

### Future: XPS 9510 (Hybrid GPU)
Intel iGPU + NVIDIA RTX 3050 Ti requires PRIME/Optimus setup with proprietary nvidia-drivers.

### Future: ASRock B550 (First AMD)
Ryzen 9 5950X with SATA SSDs. Needs `CONFIG_CPU_SUP_AMD`, `CONFIG_AMD_IOMMU`, `-march=znver3`.

### Future: Precision T5810 (Xeon Broadwell-EP)
ECC memory, `-march=broadwell`, older PCH. Currently runs Fedora 42.

### Future: Precision 7960 (Multi-GPU Xeon W)
Most complex config: dual NVIDIA GPUs (RTX Pro 6000 96GB + RTX A1000 8GB), Xeon W5-3433. Currently runs RHEL 10.1.

### Future: Surface Pro 6
8th Gen Intel, requires linux-surface kernel patches. Currently runs Fedora 43.

### Future: Surface Pro 9
12th Gen Intel Alder Lake, requires linux-surface kernel patches. Currently runs Windows 11 Pro.
