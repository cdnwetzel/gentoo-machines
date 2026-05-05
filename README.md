# gentoo-machines

Multi-machine Gentoo Linux kernel configurations, portage settings, and automated install tooling. Each machine has a tuned kernel `.config`, `make.conf`, programmatic `kernel_config.sh`, and hardware documentation derived from live harvesting.

## Machines

| Machine | CPU | GPU | Status | Current OS |
|---------|-----|-----|--------|------------|
| [Dell XPS 15 9510](machines/xps-9510/) | i7-11800H (Tiger Lake-H) | Intel UHD + NVIDIA RTX 3050 Ti | **Production** | Gentoo |
| [ASRock B550](machines/asrock-b550/) | Ryzen 9 5950X (Zen 3, 16C/32T) | NVIDIA RTX 3060 Ti (GA104) | **Production** | Gentoo |
| [Dell Precision T5810](machines/precision-t5810/) | Xeon E5-2699v4 (22C/44T) | 2x NVIDIA RTX A4500 (Ampere, 20GB ECC, NVLink) | **Production** | Gentoo |
| [Surface Pro 6](machines/surface-pro-6/) | i5-8250U (Kaby Lake-R) | Intel UHD 620 | **Production** | Gentoo |
| [Beelink MINI S](machines/beelink-minis/) | Celeron N5095A (Jasper Lake) | Intel UHD Gen11 LP | **Production** | Gentoo |
| [Dell OptiPlex 3090 SFF](machines/optiplex-3090/) | i5-10505 (Comet Lake, 6C/12T) | Intel UHD 630 + NVIDIA RTX A1000 8GB | **Production** | Gentoo |
| [Dell XPS 13 9315](machines/xps-9315/) | i5-1230U (Alder Lake) | Intel Iris Xe | Config maintained | Windows (returned) |
| [MacBook Pro 12,1 (2015)](machines/mbp-2015/) | i7-5557U (Broadwell) | Intel Iris 6100 | Retired (config maintained) | macOS 12 (kids' machine) |
| [Intel NUC11TNBi5](machines/nuc11/) | i5-1135G7 (Tiger Lake) | Intel Iris Xe | Ready to build | Ubuntu |
| [Surface Pro 9](machines/surface-pro-9/) | 12th Gen Intel | Intel Iris Xe | Planned | Windows 11 Pro |
| [Dell Precision 7960](machines/precision-7960/) | Xeon W5-3433 (Sapphire Rapids) | RTX Pro 6000 Blackwell 96GB (600W) + RTX 5080 16GB Blackwell | Reference only | RHEL 10.1 |

NVIDIA machines use **proprietary nvidia-drivers** (`kernel-open` on Turing+). The Precision 7960 stays on RHEL 10.1 for production AI/ML workloads. All production machines track **6.18 LTS** (EOL Dec 2027) via `~amd64` keywords.

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
│   ├── asrock-b550/       # ASRock B550 / Ryzen 9 5950X (Zen 3 + NVIDIA Ampere) - PRODUCTION
│   ├── precision-t5810/   # Dell Precision T5810 / Xeon E5 (Broadwell-EP + dual NVIDIA) - PRODUCTION
│   ├── surface-pro-6/     # Surface Pro 6 (Kaby Lake-R + Marvell WiFi + HiDPI) - PRODUCTION
│   ├── beelink-minis/     # Beelink MINI S (Jasper Lake mini-PC, always-on) - PRODUCTION
│   ├── mbp-2015/          # MacBook Pro 12,1 (Broadwell + Apple SMC + brcmfmac) - Retired
│   ├── xps-9315/          # Dell XPS 13 9315 (Alder Lake) - Config maintained
│   ├── nuc11/             # Intel NUC11TNBi5 (Tiger Lake) - Ready to build
│   ├── precision-7960/    # Dell Precision 7960 / Xeon W5 (Sapphire Rapids) - Reference only
│   └── surface-pro-9/     # Surface Pro 9 - Planned
│   # Each production machine directory typically contains:
│   #   .config, kernel_config.sh, make.conf, HARDWARE.md, world,
│   #   package.use, package.accept_keywords, package.env,
│   #   sysctl-performance.conf, zram-init.conf, grub,
│   #   gentoo_install_part{1,2,3_chroot}.sh (3-phase automated install).
├── tools/
│   ├── harvest.sh                   # General-purpose hardware inventory (17 sections)
│   ├── deep_harvest.sh              # Deep hardware discovery with module/firmware detection
│   ├── machine-profile.sh           # Shared feature-flag library sourced by other tools
│   ├── kconfig-lint.sh              # Static kernel config validator (5 checks, ~19K symbols)
│   ├── kernel-config-template.sh    # Auto-generate kernel_config.sh from harvest data
│   ├── generate-config.sh           # Assisted config generation (.config, make.conf, HARDWARE.md)
│   ├── generate-install.sh          # Generate 3-phase install scripts from harvest + profile
│   ├── test-generate-install.sh     # Regression harness for generate-install.sh
│   ├── test-fixtures/               # Synthetic harvests exercising feature gates
│   ├── update-system.sh             # Prompted system update workflow with resume
│   ├── build-kernel-remote.sh       # Cross-compile and deploy kernels over SSH
│   └── verify-install.sh            # Post-reboot deep verification (auto-detects machine)
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

### generate-install.sh — 3-Phase Install Script Generator
Produces a starting-point skeleton of the three install scripts (`gentoo_install_part1.sh`, `part2.sh`, `part3_chroot.sh`) for a new machine. Parses harvest section 8 for block devices (authoritative — avoids the live-USB false positive that pure driver detection hits) and consults `machine-profile.sh` feature flags to gate platform-specific blocks (NVIDIA modprobe, Apple mbpfan, Surface HiDPI, Dell EFI fallback, laptop TLP, desktop always-on elogind drop-in, firmware verification keyed to WiFi/BT driver).

```bash
tools/generate-install.sh <new-machine> <base-machine> <harvest-dir>
```

A companion harness (`tools/test-generate-install.sh`) runs the generator against three synthetic fixtures under `tools/test-fixtures/` and asserts that each feature gate fires correctly — 42 checks across `intel-sata-desktop`, `amd-nvme-nvidia-desktop`, and `apple-broadwell-laptop` profiles.

### machine-profile.sh — Feature Flag Library
Shared hardware-detection helper that parses `harvest.sh` output into 30+ feature flags (CPU, GPU generation, WiFi/BT driver, audio type, storage, Ethernet, platform vendor, boot type, suspend caps, chassis, Thunderbolt, ISH, SAM, EDAC, NUMA). Sourced by other tools rather than executed directly.

```bash
HARVEST=/path/to/hardware_inventory.log source tools/machine-profile.sh
# now use $HAS_NVIDIA_GPU, $WIFI_DRIVER, $IS_LAPTOP, etc.

# Or print a summary:
HARVEST=... MP_SUMMARY=1 bash tools/machine-profile.sh
```

### verify-install.sh — Post-Reboot Verification
Deep verification across 8 sections: kernel/boot, GPU (detects i915/nvidia-smi/nouveau clashes), networking (WiFi driver + firmware + NM state), audio (ALSA + PipeWire), storage (zram + swap), services (machine-conditional), user/permissions, and machine-specific checks. Auto-detects machine from DMI. Exit code equals failure count.

```bash
sudo tools/verify-install.sh
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

| Setting | XPS 9510 | B550 | T5810 | SP6 | Beelink | OptiPlex 3090 | NUC11 | XPS 9315 |
|---------|----------|------|-------|-----|---------|---------------|-------|----------|
| `-march=` | `tigerlake` | `znver3` | `broadwell` | `skylake` | `tremont` | `skylake` | `tigerlake` | `alderlake` |
| `VIDEO_CARDS` | `intel iris nvidia` | `nvidia` | `nvidia` | `intel` | `intel` | `intel iris nvidia` | `intel iris` | `intel iris` |
| AVX-512 | Yes | No | No | No | No | No | Yes | No |
| Hybrid cores | No | No | No | No | No | No | No | Yes |
| CPU vendor | Intel | AMD | Intel | Intel | Intel | Intel | Intel | Intel |

## Machine Notes

### Production: XPS 9510 (Hybrid GPU)
Intel iGPU + NVIDIA RTX 3050 Ti with PRIME/Optimus, proprietary nvidia-drivers. PipeWire audio, SSTP VPN, thermald + tlp power management. Dual NVMe, 32GB RAM, zram 8GB zstd swap. Full 3-phase automated install.

### Production: Precision T5810 (Xeon Broadwell-EP)
Xeon E5-2699v4 (22C/44T), 256GB DDR4 ECC, **2x NVIDIA RTX A4500 (GA102GL Ampere, 20GB GDDR6 ECC each, NVLink-bridged → 40GB tensor-parallel pool, compute 8.6)**, Samsung 990 PRO 2TB NVMe. C610/X99 chipset, `-march=broadwell`, performance-first (no power savings). Dev/test bench for AI inference and LoRA fine-tuning (7B–13B models). Originally shipped with 2x GTX 1050 Ti (Pascal) — upgraded to A4500 + NVLink for tensor-parallel workloads.

### Production: Surface Pro 6
Kaby Lake-R i5, Marvell 88W8897 WiFi (not Intel), 8GB RAM. 2736x1824 PixelSense display with 150% HiDPI scaling. WiFi power save workarounds for suspend reliability. Full 3-phase automated install with HiDPI configuration throughout (LightDM, XFCE, GTK greeter).

### Retired (config maintained): MacBook Pro 12,1 (2015)
Returned to macOS 12 as a kids' machine. Kernel config and install scripts are maintained in the repo for reference. Full Apple hardware support: applesmc, mbpfan, bcm5974, brcmfmac, CS4208 audio.

### Production: ASRock B550 Phantom Gaming-ITX/ax (First AMD)
Ryzen 9 5950X (16C/32T, Zen 3), 64GB DDR4-3200, NVIDIA RTX 3060 Ti (GA104 Ampere, `kernel-open`), Intel AX200 WiFi/BT, Intel I225-V 2.5GbE, MAXIO MAP1202 2TB NVMe, AIO liquid cooling. First AMD platform in the fleet — AMD-specific drivers throughout: `amd-pstate`, `k10temp`, `piix4_smbus`, `ccp` (PSP), `edac_mce_amd`. No Intel iGPU, no MEI, no i801. 22-phase `kernel_config.sh`, 3-phase automated install scripts, 46GB portage tmpfs with disk fallback.

### Production: Beelink MINI S (Always-On Mini PC)
Celeron N5095A (4C/4T, Jasper Lake/Tremont — no HT, no AVX/AVX2), 8GB DDR4-2666 single-channel, Intel UHD Gen11 LP, Intel Wireless-AC 3165, Realtek RTL8168 GbE, 256GB M.2 SATA SSD (no NVMe on this board). Always-on via elogind drop-in that disables all sleep/suspend. 4GB portage tmpfs with disk fallback for large packages (binary-only browsers).

### Production: OptiPlex 3090 SFF (Hybrid GPU Desktop)
i5-10505 (Comet Lake, 6C/12T, no AVX-512), 16GB DDR4-2666 single-channel, Intel UHD 630 + NVIDIA RTX A1000 8GB GDDR6 (GA107 Ampere, `kernel-open`), no WiFi/BT, Realtek RTL8168 GbE, 256GB M.2 2230 NVMe. Q470 chipset. **BIOS gotcha**: ships with SATA in Intel RST/RAID mode — must switch to AHCI before Linux can see the NVMe. 7GB portage tmpfs with disk fallback (CONSTRAINED 16GB profile). The A1000 is the hand-me-down from the Precision 7960's secondary slot.

### Reference Only: Precision 7960 (Multi-GPU Xeon W)
Dual NVIDIA Blackwell GPUs (**RTX Pro 6000 Blackwell 96GB GDDR7, 600W** + **RTX 5080 16GB GDDR7**), Xeon W5-3433 (Sapphire Rapids, AVX-512 + AMX), 128GB DDR5 ECC, 4x Samsung PM9C1a 1.8TB RAID10 via VMD. Stays on RHEL 10.1 for production AI/ML workloads. Hardware harvested for reference only. The original secondary RTX A1000 was relocated to the OptiPlex 3090 and replaced by the 5080.

### Kernel Strategy

All production machines use `gentoo-sources` with manual configuration via per-machine `kernel_config.sh` scripts — not distribution kernels (`gentoo-kernel`/`gentoo-kernel-bin`). No initramfs or dracut — root-path drivers (NVMe, AHCI, ext4) are built-in (=y). `installkernel` with the `grub` USE flag auto-updates GRUB on `make install`. Old kernels are cleaned with `eclean-kernel -n 3` (keep current + 2 rollback). See `tools/update-system.sh` for the complete guided workflow.

## Contributing

Scope is **x86/x64 Intel and AMD**. The best way to contribute is to add a new machine — harvest your hardware, run the generators, and submit the resulting configs so the next person with similar hardware gets a working starting point automatically.

**AI-assisted contributions are welcome.** Every commit in this repo is `Co-Authored-By: Claude` — that's how it gets built. The filter isn't on whether you used an LLM; it's on whether the machine actually boots and passes verification. Those requirements apply equally to human and AI-assisted work.

**Quality bar for new-machine PRs:** see `machines/asrock-b550/` as a reference — kernel config, make.conf, full 3-phase install scripts, HARDWARE.md, and a STATUS.md marking the install date.

**New-machine PR checklist:**

1. Harvest on the target: `sudo tools/harvest.sh && sudo -E tools/deep_harvest.sh`
2. Run the three generators (`kernel-config-template.sh`, `generate-config.sh`, `generate-install.sh`) — see [INSTALL.md § Adding a New Machine](INSTALL.md#adding-a-new-machine)
3. Install on the actual hardware and boot it — we don't merge machines that haven't been proven to boot
4. Paste the output of `sudo tools/verify-install.sh` into the PR description (failure count must be zero)
5. Include the harvest logs under `machines/<your-machine>/harvest/` (or reference them in the PR) so the nearest-base suggester has something to score against later

**For changes that aren't a new machine** (tool fixes, generator improvements, gap-closing on items from [`backlog.md`](backlog.md)): please open an issue first describing the problem and the proposed approach. One paragraph is plenty — it just keeps us aligned before you spend time.

**What we're not looking for:** cosmetic rewrites, speculative refactors, or contributions outside the x86 Intel/AMD scope.
