# gentoo-machines

Multi-machine Gentoo Linux kernel configurations, portage settings, and automated install tooling. Each machine has a tuned kernel `.config`, `make.conf`, programmatic `kernel_config.sh`, and hardware documentation derived from live harvesting.

## Machines

| Machine | CPU | GPU | Status | Current OS |
|---------|-----|-----|--------|------------|
| [Dell XPS 15 9510](machines/xps-9510/) | i7-11800H (Tiger Lake-H) | Intel UHD + NVIDIA RTX 3050 Ti | **Production** | Gentoo |
| [MacBook Pro 12,1 (2015)](machines/mbp-2015/) | i7-5557U (Broadwell) | Intel Iris 6100 | **Retired** | macOS 12 (kids' machine) |
| [Surface Pro 6](machines/surface-pro-6/) | i5-8250U (Kaby Lake-R) | Intel UHD 620 | **Production** | Gentoo |
| [Dell XPS 13 9315](machines/xps-9315/) | i5-1230U (Alder Lake) | Intel Iris Xe | **Production** (config maintained) | Windows (returned) |
| [Intel NUC11TNBi5](machines/nuc11/) | i5-1135G7 (Tiger Lake) | Intel Iris Xe | Ready to build | Ubuntu |
| [ASRock B550](machines/asrock-b550/) | Ryzen 9 5950X (Zen 3, 16C/32T) | NVIDIA RTX 3060 Ti (GA104) | **Building** | Gentoo (installing) |
| [Dell Precision T5810](machines/precision-t5810/) | Xeon E5-2699v4 | 2x NVIDIA GTX 1050 Ti | **Production** | Gentoo |
| [Dell Precision 7960](machines/precision-7960/) | Xeon W5-3433 | RTX Pro 6000 96GB + RTX A1000 8GB | Reference only | RHEL 10.1 |
| [Surface Pro 9](machines/surface-pro-9/) | 12th Gen Intel | Intel Iris Xe | Planned | Windows 11 Pro |

NVIDIA machines use **proprietary nvidia-drivers**. The Precision 7960 stays on RHEL 10.1 for production AI/ML workloads. All production machines track **6.18 LTS** (EOL Dec 2027) via `~amd64` keywords.

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
│   ├── mbp-2015/          # MacBook Pro 12,1 Early 2015 (Broadwell) - RETIRED
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
│   ├── xps-9315/          # Dell XPS 13 9315 (Alder Lake) - PRODUCTION (config maintained)
│   │   ├── .config        # Kernel config
│   │   ├── make.conf      # Portage build settings (-march=alderlake)
│   │   └── HARDWARE.md    # Hardware reference
│   ├── nuc11/             # Intel NUC11TNBi5 (Tiger Lake) - READY TO BUILD
│   │   ├── .config        # Kernel config (derived from xps-9315)
│   │   ├── make.conf      # Portage build settings (-march=tigerlake)
│   │   └── HARDWARE.md    # Hardware reference
│   ├── asrock-b550/       # ASRock B550 / Ryzen 9 5950X - BUILDING
│   ├── precision-t5810/   # Dell Precision T5810 / Xeon E5 - PRODUCTION
│   ├── precision-7960/    # Dell Precision 7960 / Xeon W5 - REFERENCE ONLY
│   └── surface-pro-9/     # Surface Pro 9 - PLANNED
├── tools/
│   ├── harvest.sh         # General-purpose hardware inventory (15 sections)
│   ├── deep_harvest.sh    # Deep hardware discovery with module/firmware detection
│   ├── kconfig-lint.sh    # Static kernel config validator (5 checks, 19K symbols)
│   ├── kernel-config-template.sh  # Auto-generate kernel_config.sh from harvest data
│   ├── update-system.sh            # Prompted system update workflow with resume
│   ├── build-kernel-remote.sh     # Cross-compile and deploy kernels over SSH
│   └── generate-config.sh         # Assisted config generation (uses Claude CLI)
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
├── CLAUDE.md              # Project context and technical reference
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

### generate-config.sh — Assisted Config Generation
Analyzes harvest data against a base config and generates `.config`, `make.conf`, and `HARDWARE.md`. Uses Claude CLI for hardware diff analysis.

```bash
tools/generate-config.sh <new-machine> <base-machine> <harvest-dir>
```

### update-system.sh — System Update Tool

End-to-end update workflow for production machines. Auto-detects machine via hostname + DMI fallback. Handles portage sync, system package updates, config file merging (dispatch-conf), kernel config migration, build, install, NVIDIA module rebuild, post-reboot verification, and old kernel cleanup.

**Default usage** — prompted step-by-step with resume:

```bash
sudo tools/update-system.sh           # walks through all phases, prompts Y/n/skip at each step
# reboot when prompted
sudo tools/update-system.sh           # resumes with verify + clean
```

The `full` workflow runs 10 phases in order: `fetch` → `world` → `config-update` → `check` → `prepare` → `build` → `install` → reboot → `verify` → `clean`. Progress is saved to `/var/lib/kernel-update/full-progress`, so the workflow survives interruption and reboot. On resume, completed phases are skipped. Type `reset` at the resume prompt to start over.

**Individual subcommands** — run any phase standalone:

```bash
sudo tools/update-system.sh fetch          # sync portage + install gentoo-sources + eselect kernel + news
sudo tools/update-system.sh world          # emerge @world + preserved-rebuild + depclean
sudo tools/update-system.sh config-update  # merge updated config files via dispatch-conf
tools/update-system.sh check               # pre-flight: versions, disk, patches, config strategy
tools/update-system.sh prepare             # backup .config, migrate config, apply patches, lint
tools/update-system.sh build               # compile with make -j$(nproc)
sudo tools/update-system.sh install        # modules_install + make install + NVIDIA rebuild
tools/update-system.sh verify              # post-reboot: dmesg, drivers, GPU, WiFi, zram, services
sudo tools/update-system.sh clean          # eclean-kernel -n 3 (keep current + 2 rollback)
```

**Options:**

| Flag | Description |
|------|-------------|
| `--dry-run` | Preview what each phase would do without making changes |
| `--machine NAME` | Override auto-detection (valid: xps-9510, mbp-2015, surface-pro-6, nuc11, asrock-b550, precision-t5810) |
| `-h`, `--help` | Show usage |

**Config strategy:** same-series updates (e.g., 6.18.12 → 6.18.16) copy the running `.config` and run `make olddefconfig`. Cross-series migrations (e.g., 6.12 → 6.18) start from `make defconfig`, apply the machine's `kernel_config.sh`, then run `make olddefconfig`.

### build-kernel-remote.sh — Cross-Compile and Deploy
Build kernels on a powerful host and deploy over SSH. Auto-detects kernel version from target.

```bash
tools/build-kernel-remote.sh <target> {pull|build|deploy|all}
```

## Quick Start

### Update an existing machine

```bash
sudo tools/update-system.sh           # prompted workflow: sync, update, build, install
# reboot
sudo tools/update-system.sh           # resume: verify + clean
```

### Deploy a kernel config manually

```bash
cp machines/<machine>/.config /usr/src/linux/.config
cd /usr/src/linux
make olddefconfig
make -j$(nproc)
make modules_install
make install
grub-mkconfig -o /boot/grub/grub.cfg
```

### Initial Gentoo installation

See **[INSTALL.md](INSTALL.md)** for the complete step-by-step guide. Each production machine has 3-phase automated install scripts (`gentoo_install_part{1,2,3}_chroot.sh`) for reproducible installs from a live USB.

## Portage Configuration

Shared portage files in `shared/` work across all machines. Machine-specific settings (compiler flags, video cards) are in each machine's `make.conf`.

### Common Settings
- **Profile**: `default/linux/amd64/23.0`
- **Init**: OpenRC (no systemd)
- **Desktop**: XFCE with LightDM
- **Python**: 3.13 / 3.14

### Per-Machine Differences

| Setting | XPS 9510 | Surface Pro 6 | T5810 | B550 | NUC11 | XPS 9315 |
|---------|----------|---------------|-------|------|-------|----------|
| `-march=` | `tigerlake` | `skylake` | `broadwell` | `znver3` | `tigerlake` | `alderlake` |
| `VIDEO_CARDS` | `intel iris nvidia` | `intel` | `nvidia` | `nvidia` | `intel iris` | `intel iris` |
| AVX-512 | Yes | No | No | No | Yes | No |
| Hybrid cores | No | No | No | No | No | Yes |
| CPU vendor | Intel | Intel | Intel | AMD | Intel | Intel |

## Machine Notes

### Production: XPS 9510 (Hybrid GPU)
Intel iGPU + NVIDIA RTX 3050 Ti with PRIME/Optimus, proprietary nvidia-drivers. PipeWire audio, SSTP VPN, thermald + tlp power management. Dual NVMe, 32GB RAM, zram 8GB zstd swap. Full 3-phase automated install.

### Retired: MacBook Pro 12,1 (2015)
Returned to macOS 12 as kids' machine. Configs preserved for reference. Had full Apple hardware support: applesmc, mbpfan, bcm5974, brcmfmac, CS4208 audio.

### Production: Surface Pro 6
Kaby Lake-R i5, Marvell 88W8897 WiFi (not Intel), 8GB RAM. 2736x1824 PixelSense display with 150% HiDPI scaling. WiFi power save workarounds for suspend reliability. Full 3-phase automated install with HiDPI configuration throughout (LightDM, XFCE, GTK greeter).

### Reference Only: Precision 7960 (Multi-GPU Xeon W)
Dual NVIDIA GPUs (RTX Pro 6000 96GB + RTX A1000 8GB), Xeon W5-3433. Stays on RHEL 10.1 for production AI/ML workloads. Hardware harvested for reference only.

### Building: ASRock B550 Phantom Gaming-ITX/ax (First AMD)
Ryzen 9 5950X (16C/32T, Zen 3), 64GB DDR4-3200, NVIDIA RTX 3060 Ti (GA104 Ampere, `kernel-open`), Intel AX200 WiFi/BT, Intel I225-V 2.5GbE, MAXIO MAP1202 2TB NVMe, AIO liquid cooling. First AMD platform in the fleet — AMD-specific drivers throughout: `amd-pstate`, `k10temp`, `piix4_smbus`, `ccp` (PSP), `edac_mce_amd`. No Intel iGPU, no MEI, no i801. 22-phase `kernel_config.sh`, 3-phase automated install scripts, 46GB portage tmpfs with disk fallback.

### Production: Precision T5810 (Xeon Broadwell-EP)
Xeon E5-2699v4 (22C/44T), 256GB DDR4 ECC, 2x NVIDIA GTX 1050 Ti, Samsung 990 PRO 2TB NVMe. C610/X99 chipset, `-march=broadwell`, performance-first (no power savings). Dev/test for AI inference: 7B models on CPU, 1.5B on GPU. Mirrors production 7960.

### Kernel Strategy

All production machines use `gentoo-sources` with manual configuration via per-machine `kernel_config.sh` scripts — not distribution kernels (`gentoo-kernel`/`gentoo-kernel-bin`). No initramfs or dracut — root-path drivers (NVMe, AHCI, ext4) are built-in (=y). `installkernel` with the `grub` USE flag auto-updates GRUB on `make install`. Old kernels are cleaned with `eclean-kernel -n 3` (keep current + 2 rollback). See `tools/update-system.sh` for the complete guided workflow.
