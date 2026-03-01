# Universal Machine Onboarding Checklist
# For adding any new machine to the Gentoo framework

## Step 1: Hardware Inventory

Run on the target machine (any Linux distro — Fedora, Ubuntu, etc.):

```bash
# Clone the repo
git clone https://github.com/cdnwetzel/gentoo-machines.git
cd gentoo-machines

# Basic hardware inventory
sudo tools/harvest.sh

# Deep hardware discovery (module + firmware detection)
sudo -E tools/deep_harvest.sh
```

Copy harvest logs to your build host for analysis.

## Step 2: Create Machine Directory

```bash
mkdir -p machines/<machine-name>
```

### Minimum Required Files

| File | Purpose | Source |
|------|---------|--------|
| `make.conf` | Portage configuration | Template from closest existing machine |
| `kernel_config.sh` | Programmatic kernel config | Adapt from closest machine + harvest data |
| `world` | Package set | Start from shared/world, add/remove per machine |
| `HARDWARE.md` | Hardware reference | Generated from harvest logs |

### Recommended Files

| File | Purpose | Source |
|------|---------|--------|
| `package.use` | Machine-specific USE overrides | Copy relevant entries from shared/package.use |
| `package.env` | Large package disk fallback | Adjust tmpfs size for machine RAM |
| `portage_env_notmpfs.conf` | Disk fallback config | Identical across all machines |
| `package.accept_keywords` | Keyword overrides | As needed |
| `fstab` | Filesystem table | Adapt for disk layout |
| `zram-init.conf` | Compressed swap config | Scale for machine RAM |
| `sysctl-performance.conf` | VM/network tuning | Scale for machine RAM + storage |

### Optional Files (for fresh installs)

| File | Purpose |
|------|---------|
| `gentoo_install_part1.sh` | Disk partitioning from live USB |
| `gentoo_install_part2.sh` | Stage3 + config staging |
| `gentoo_install_part3_chroot.sh` | One-shot chroot install |
| `INSTALL_PREFLIGHT.md` | 13-phase install checklist |
| `INSTALL_GOTCHAS.md` | Machine-specific gotchas |
| `KERNEL_CONFIG_CROSSREF.md` | Kernel config decisions |
| `tlp.conf` | Power management (laptops) |
| `grub` | GRUB defaults |

### NVIDIA Machines (additional files)

| File | Purpose |
|------|---------|
| `99-module-rebuild.install` | Auto-rebuild nvidia on kernel update |
| `prime-run` | NVIDIA PRIME Render Offload wrapper |

## Step 3: Create make.conf

Use the closest existing machine as a template. Key sections to customize:

1. **Hardware header** (20-line comment block): All confirmed PCI devices, firmware
2. **Compiler flags**: `-march=<arch>` from GCC docs (see shared/INSTALL_GOTCHAS.md #18)
3. **Parallelism**: `MAKEOPTS="-j$(nproc+1) -l$(nproc)"`, scale EMERGE_DEFAULT_OPTS
4. **Tmpfs**: Size based on RAM (see shared/INSTALL_GOTCHAS.md #21)
5. **USE flags**: Add/remove hardware-specific flags (nvidia, thunderbolt, etc.)
6. **VIDEO_CARDS**: `intel iris` / `intel iris nvidia` / `amdgpu` / etc.
7. **CPU_FLAGS_X86**: **ALWAYS run cpuid2cpuflags** (Gotcha #25)
8. **MICROCODE_SIGNATURES**: CPU family/model/stepping from harvest data

## Step 4: Create kernel_config.sh

Start from the closest existing machine's script. Key adaptations:

- **Phase 1** (remove base-machine hardware): Remove drivers for hardware not present
- **Phase 2** (processor): NR_CPUS, -march, hybrid scheduling, thermal
- **Phase 7-8** (GPU): i915 params, NVIDIA deps, or AMDGPU
- **Phase 9** (audio): HDA vs SOF (check PCI ID)
- **Phase 10** (WiFi): Intel iwlwifi vs Marvell mwifiex vs Broadcom brcmfmac
- **Phase 26** (disable): Remove drivers for absent hardware

## Step 5: Generate Config (Automated)

```bash
# Automated approach using Claude CLI
tools/generate-config.sh <new-machine> <closest-base> <harvest-dir>
```

This generates `.config`, `make.conf`, and `HARDWARE.md` from harvest data.

## Step 6: Build & Test

```bash
# On target machine
cd /usr/src/linux
make defconfig                    # or copy base .config
bash /path/to/kernel_config.sh    # apply machine customizations
make olddefconfig                 # resolve dependencies
make -j$(nproc)                   # build
make modules_install
make install
```

## Step 7: Verify

```bash
# After reboot
zcat /proc/config.gz | grep IKCONFIG      # config readable?
dmesg | grep -i error                      # any errors?
lspci -k                                   # all drivers loaded?
nvidia-smi                                 # (NVIDIA machines)
swapon --show                              # zram working?
sensors                                    # thermal sensors?
nmtui                                      # WiFi?
pactl info | grep "Server Name"            # PipeWire?
```

## Step 8: Document & Commit

1. Update HARDWARE.md with any new findings from live verification
2. Update CLAUDE.md with new machine entry
3. Commit all files
4. Push to GitHub

## Example: Adding ASRock B550 (Ryzen 9 5950X + RTX 3060 Ti)

1. **Harvest**: Boot Fedora 42, run harvest.sh + deep_harvest.sh
2. **Base**: Use XPS 9510 as base (also has NVIDIA)
3. **Customize**:
   - `-march=znver3` (Zen 3)
   - Remove Intel-specific: INTEL_PSTATE, INTEL_IDLE, i915, iwlwifi
   - Add AMD-specific: CPU_SUP_AMD, AMD_IOMMU, AMDGPU (if swapping GPUs), ACPI_CPUFREQ
   - Keep: NVIDIA deps (DRM_QXL trick), 99-module-rebuild.install, prime-run
   - Storage: SATA SSDs (AHCI=y built-in, not just NVMe)
   - Ethernet: onboard (igb or r8169, check harvest)
   - Audio: check HDA vs HD Audio (likely snd_hda_intel)
4. **NR_CPUS=32** (16C/32T), tmpfs scale for RAM amount

## Example: Adding Precision T5810 (Xeon E5-2699v4)

1. **Harvest**: Boot Fedora 42, run harvest.sh + deep_harvest.sh
2. **Base**: Use NUC11 as base (similar Intel platform, no laptop features)
3. **Customize**:
   - `-march=broadwell` (Broadwell-EP)
   - NR_CPUS=44 (22C/44T)
   - EDAC=y (ECC memory)
   - NUMA=y
   - Large RAM sysctl (adjust dirty_ratio, cache_pressure)
   - C-state management for Xeon
   - No laptop features (no battery, no backlight, no tlp)
