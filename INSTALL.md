# Gentoo Linux Installation Guide

General-purpose installation guide for deploying Gentoo on any supported machine in this repository. Each machine has a pre-built kernel `.config` and `make.conf` that eliminates the hardest part of a Gentoo install — hardware-specific kernel configuration.

**Recommended path for supported machines:** use the machine-specific 3-phase automated install scripts (`gentoo_install_part1.sh` → `part2.sh` → `part3_chroot.sh`) in each production machine directory. They handle partitioning, stage3 extraction, config staging, chroot bootstrap, kernel build, package installation, and pre-reboot verification end-to-end. This manual guide covers the same ground step-by-step — use it if you prefer granular control, are adding a new machine, or need to debug a specific phase.

## Table of Contents

1. [Supported Machines](#supported-machines)
2. [Prerequisites](#prerequisites)
3. [Variables Used Throughout](#variables-used-throughout)
4. [Part 1: Preparation](#part-1-preparation)
5. [Part 2: Network Setup](#part-2-network-setup)
6. [Part 3: Disk Setup](#part-3-disk-setup)
7. [Part 4: Install Gentoo Base System](#part-4-install-gentoo-base-system)
8. [Part 5: Enter the New System (Chroot)](#part-5-enter-the-new-system-chroot)
9. [Part 6: Configure Portage and Update System](#part-6-configure-portage-and-update-system)
10. [Part 7: Build the Kernel](#part-7-build-the-kernel)
11. [Part 8: System Configuration](#part-8-system-configuration)
12. [Part 9: Install Desktop and Enable Services](#part-9-install-desktop-and-enable-services)
13. [Part 10: Create User and Finalize](#part-10-create-user-and-finalize)
14. [Part 11: Reboot](#part-11-reboot)
15. [Part 12: Post-Install Verification](#part-12-post-install-verification)
16. [Troubleshooting](#troubleshooting)
17. [Adding a New Machine](#adding-a-new-machine)
18. [Quick Reference](#quick-reference)
19. [Kernel Updates](#kernel-updates)

## Supported Machines

Before starting, confirm your target machine has a config ready:

| Machine | Directory | Config Status |
|---------|-----------|---------------|
| Dell XPS 15 9510 | `machines/xps-9510/` | Production |
| ASRock B550 / Ryzen 9 5950X | `machines/asrock-b550/` | Production |
| Dell Precision T5810 | `machines/precision-t5810/` | Production |
| Surface Pro 6 | `machines/surface-pro-6/` | Production |
| Beelink MINI S | `machines/beelink-minis/` | Production |
| Dell XPS 13 9315 | `machines/xps-9315/` | Config maintained |
| MacBook Pro 12,1 (2015) | `machines/mbp-2015/` | Retired (config maintained) |
| Intel NUC11TNBi5 | `machines/nuc11/` | Ready to build |
| Dell Precision 7960 | `machines/precision-7960/` | Reference only (RHEL) |
| Surface Pro 9 | `machines/surface-pro-9/` | Planned |

If your machine isn't listed or is "Planned", you'll need to generate a config first. See [Adding a New Machine](#adding-a-new-machine) at the end.

## Prerequisites

- A USB drive (4GB minimum)
- Internet connection (Ethernet preferred for reliability; WiFi works on most live ISOs)
- Basic comfort with the command line
- This repository cloned or downloaded somewhere accessible

## Variables Used Throughout

Replace these placeholders with your actual values:

| Variable | Example | Description |
|----------|---------|-------------|
| `MACHINE` | `nuc11` | Machine directory name from table above |
| `DISK` | `/dev/nvme0n1` or `/dev/sda` | Target disk (use `lsblk` to find) |
| `WIFI_IFACE` | `wlp0s20f3` | WiFi interface name (use `ip link`) |
| `HOSTNAME` | `nuc11-gentoo` | Your chosen hostname |
| `USERNAME` | `chris` | Your login username |
| `KVER` | `6.18.12-gentoo` | Kernel version from `ls /usr/src/` |

---

## Part 1: Preparation

### 1.1 Harvest Hardware Info (Optional but Recommended)

If the target machine is running another Linux distro, capture hardware info first. This validates the kernel config covers all your hardware:

```bash
# Clone this repo on the target machine (while still running current OS)
git clone https://github.com/YOUR_USER/gentoo-machines.git
cd gentoo-machines

# Run hardware inventory (requires root)
sudo tools/harvest.sh
sudo -E tools/deep_harvest.sh

# Save the output — compare later after Gentoo boots
```

### 1.2 Create a Bootable USB

On any Linux/Mac/Windows system, download a live Linux ISO:

- **Recommended**: [SystemRescue](https://www.system-rescue.org/Download/) — includes all tools needed, boots on everything
- **Alternative**: [Gentoo Minimal Install](https://www.gentoo.org/downloads/)

```bash
# On Linux/Mac (replace sdX with your USB device)
# WARNING: This will erase the USB drive!
# Use 'lsblk' to identify your USB drive — be careful!

dd if=systemrescue-x.xx-amd64.iso of=/dev/sdX bs=4M status=progress
sync
```

On Windows, use [Rufus](https://rufus.ie/) or [Etcher](https://etcher.io/).

### 1.3 Configure BIOS

Boot into BIOS (usually F2, Del, or F10 at POST):

| Setting | Value | Notes |
|---------|-------|-------|
| Secure Boot | **Disabled** | Can re-enable later with custom keys |
| SATA Operation | **AHCI** | Required for Linux SATA support |
| USB Boot | **Enabled** | Needed to boot the live USB |
| Boot Order | USB first | Temporary — change back after install |

Common BIOS keys by vendor:
- **Dell**: F2 (setup), F12 (boot menu)
- **Intel NUC**: F2 (setup), F10 (boot menu)
- **ASRock**: F2/Del (setup), F11 (boot menu)
- **Surface**: Volume-Up + Power (UEFI)

### 1.4 Boot from USB

1. Insert USB drive
2. Restart and hit the boot menu key (see above)
3. Select your USB drive
4. Choose default boot option

---

## Part 2: Network Setup

### 2.1 Wired Ethernet (Simplest)

If your machine has Ethernet (NUC11 has dual 2.5GbE, desktops typically have it):

```bash
# Should auto-configure via DHCP
ip link        # Find interface name (enp58s0, eth0, etc.)
dhcpcd enp58s0 # If not auto-configured

# Verify
ping -c 3 gentoo.org
```

### 2.2 WiFi (If No Ethernet)

```bash
# Find your WiFi interface
ip link
# Look for wlp*, wlan0, etc.

# Option A: wpa_supplicant (always available)
wpa_passphrase "YourNetworkName" "YourPassword" > /etc/wpa_supplicant.conf
wpa_supplicant -B -i WIFI_IFACE -c /etc/wpa_supplicant.conf
dhcpcd WIFI_IFACE

# Option B: nmtui (if available on your live ISO)
nmtui

# Verify
ping -c 3 gentoo.org
```

---

## Part 3: Disk Setup

### 3.1 Identify Your Disk

```bash
lsblk
# NVMe drives:  /dev/nvme0n1
# SATA drives:  /dev/sda
# Look for the drive matching your target disk size
```

### 3.2 Partition Layout

Recommended layout — adjust sizes based on your drive:

| # | Size | Filesystem | Mount | Purpose |
|---|------|------------|-------|---------|
| 1 | 512M | FAT32 | `/boot/efi` | UEFI boot (required) |
| 2 | 2x-3x RAM | swap | [SWAP] | Swap space (helps with compiling) |
| 3 | 50G | ext4 | `/` | Root filesystem |
| 4 | 40G | XFS | `/var/tmp` | Portage compile workspace (XFS faster for this) |
| 5 | remainder | XFS | `/home` | Your files |

**Sizing notes**:
- Swap: 2x RAM for machines with <16GB, 1x RAM for >16GB, minimum 8G
- Root 50G: Generous for Gentoo base + desktop + packages
- `/var/tmp` 40G: Large package builds (chromium, llvm) need 20G+ temp space
- If disk is small (<256G), you can skip the separate `/var/tmp` and `/home` partitions

### 3.3 Partition the Drive

**WARNING: This erases everything on the target drive!**

```bash
fdisk /dev/DISK
```

Inside fdisk:

```
g                    # Create new GPT partition table

n                    # Partition 1: EFI
1
[Enter]
+512M
t
1                    # Type: EFI System

n                    # Partition 2: Swap
2
[Enter]
+24G                 # Adjust to your RAM size
t
2
19                   # Type: Linux swap

n                    # Partition 3: Root
3
[Enter]
+50G

n                    # Partition 4: Portage tmpdir
4
[Enter]
+40G

n                    # Partition 5: Home
5
[Enter]
[Enter]              # Use remaining space

p                    # Review partition table
w                    # Write and exit
```

### 3.4 Format the Partitions

```bash
# Replace DISK with your actual device (nvme0n1, sda, etc.)
# NVMe partitions use 'p' prefix: nvme0n1p1, nvme0n1p2, ...
# SATA partitions use no prefix: sda1, sda2, ...

mkfs.vfat -F 32 /dev/DISKp1          # EFI (must be FAT32)
mkswap /dev/DISKp2 && swapon /dev/DISKp2   # Swap
mkfs.ext4 /dev/DISKp3                # Root
mkfs.xfs /dev/DISKp4                 # Portage tmpdir
mkfs.xfs /dev/DISKp5                 # Home
```

### 3.5 Mount the Filesystems

```bash
mount /dev/DISKp3 /mnt/gentoo
mkdir -p /mnt/gentoo/{boot/efi,home,var/tmp}
mount /dev/DISKp1 /mnt/gentoo/boot/efi
mount /dev/DISKp4 /mnt/gentoo/var/tmp
mount /dev/DISKp5 /mnt/gentoo/home

# Verify
df -h | grep gentoo
```

---

## Part 4: Install Gentoo Base System

### 4.1 Download and Extract Stage3

```bash
cd /mnt/gentoo

# Download the latest stage3 (OpenRC, amd64)
# Browse: https://www.gentoo.org/downloads/
# Or use links to navigate:
links https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/

# Download the .tar.xz file (not .asc or .DIGESTS)
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc-YYYYMMDDTHHMMSSZ.tar.xz

# Extract
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

# Verify — should see standard Linux directory tree
ls /mnt/gentoo
```

### 4.2 Clone This Repository

```bash
# Clone into the new system (will be available inside chroot)
git clone https://github.com/YOUR_USER/gentoo-machines.git /mnt/gentoo/root/gentoo-machines
```

Or if git isn't available on the live USB, download the ZIP from GitHub and extract it.

### 4.3 Copy Machine-Specific Configuration

```bash
# Set your target machine
MACHINE=nuc11   # Change to your machine directory name

# Portage build settings (machine-specific compiler flags)
cp /mnt/gentoo/root/gentoo-machines/machines/${MACHINE}/make.conf /mnt/gentoo/etc/portage/make.conf

# Shared portage files (same across all machines)
cp /mnt/gentoo/root/gentoo-machines/shared/package.use /mnt/gentoo/etc/portage/package.use
cp /mnt/gentoo/root/gentoo-machines/shared/package.accept_keywords /mnt/gentoo/etc/portage/package.accept_keywords
cp /mnt/gentoo/root/gentoo-machines/shared/package.license /mnt/gentoo/etc/portage/package.license

# Portage environment overrides
mkdir -p /mnt/gentoo/etc/portage/env
cp /mnt/gentoo/root/gentoo-machines/shared/portage-env /mnt/gentoo/etc/portage/env/low-memory.conf
```

---

## Part 5: Enter the New System (Chroot)

### 5.1 Prepare for Chroot

```bash
cp -L /etc/resolv.conf /mnt/gentoo/etc/

mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run
```

### 5.2 Enter Chroot

```bash
chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(chroot) $PS1"
```

You're now inside your new Gentoo system.

---

## Part 6: Configure Portage and Update System

```bash
# Sync package database
emerge-webrsync
emerge --sync

# Select profile
eselect profile list
eselect profile set default/linux/amd64/23.0

# Update system to match our USE flags (30-60 minutes)
emerge --ask --verbose --update --deep --newuse @world
```

---

## Part 7: Build the Kernel

This is where the machine-specific `.config` from this repo saves you hours.

### 7.1 Install Kernel Sources and Firmware

```bash
# Core kernel packages
emerge --ask sys-kernel/gentoo-sources sys-kernel/linux-firmware

# Only install dracut if you need an initramfs (most machines in this repo don't —
# root-path drivers like NVMe, AHCI, ext4 are built-in =y)
# emerge --ask sys-kernel/dracut

# Intel machines also need:
emerge --ask sys-firmware/intel-microcode

# If your machine uses SOF audio (check HARDWARE.md):
emerge --ask sys-firmware/sof-firmware
```

### 7.2 Select and Configure Kernel

```bash
# Select kernel source
eselect kernel list
eselect kernel set 1

# Verify symlink
ls -l /usr/src/linux

# Copy the pre-built config for your machine
MACHINE=nuc11   # Change to your machine
cp /root/gentoo-machines/machines/${MACHINE}/.config /usr/src/linux/

cd /usr/src/linux

# Update config for kernel version differences
# Press Enter to accept defaults for any new options
make oldconfig

# Optional: review in menuconfig if you want to tweak anything
# make menuconfig
```

### 7.3 Build and Install

```bash
cd /usr/src/linux

# Build (adjust -j to your CPU thread count)
make -j$(nproc)

# Install modules and kernel
make modules_install
make install

# Note the kernel version for the next step
KVER=$(cat include/config/kernel.release)
echo "Kernel version: ${KVER}"
```

### 7.4 Generate Initramfs (if needed)

Most production machines in this repo build root-path drivers (AHCI, NVMe, ext4) as built-in and do not need an initramfs. Check your machine's `kernel_config.sh` — if storage and filesystem drivers are `--enable` (=y), skip this step.

```bash
# Only needed if root-path drivers are modules (=m)
dracut --kver ${KVER}

# Verify boot files exist
ls /boot/vmlinuz-* /boot/initramfs-*
```

### 7.5 Alternative: Cross-Compile on a Build Host

If you have a more powerful machine available (especially useful for laptops/NUCs):

```bash
# On the build host (must have gentoo-sources and build deps installed):
tools/build-kernel-remote.sh MACHINE all

# This pulls source from target, builds locally, deploys to target
# Then SSH to target and run the install commands it prints
```

---

## Part 8: System Configuration

### 8.1 Configure fstab

```bash
# Get your partition UUIDs
blkid

# Edit fstab
nano /etc/fstab
```

Add entries for your partitions (replace UUIDs with values from `blkid`):

```
# Root
UUID=your-root-uuid    /           ext4    defaults,noatime    0 1

# EFI
UUID=your-efi-uuid     /boot/efi   vfat    defaults,noatime    0 2

# Swap
UUID=your-swap-uuid    none        swap    sw                  0 0

# Portage tmpdir
UUID=your-vartmp-uuid  /var/tmp    xfs     defaults,noatime    0 2

# Home
UUID=your-home-uuid    /home       xfs     defaults,noatime    0 2
```

### 8.2 Install and Configure GRUB

```bash
emerge --ask sys-boot/grub

# Install to EFI partition
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo

# If your machine has a GRUB config in the repo, use it:
MACHINE=nuc11
if [ -f /root/gentoo-machines/machines/${MACHINE}/grub ]; then
    cp /root/gentoo-machines/machines/${MACHINE}/grub /etc/default/grub
fi

# Generate GRUB config
grub-mkconfig -o /boot/grub/grub.cfg
```

### 8.3 Set Timezone and Locale

```bash
# Timezone (change to yours)
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

# Locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update && source /etc/profile
```

### 8.4 Set Hostname and Root Password

```bash
echo "HOSTNAME" > /etc/hostname
passwd
```

---

## Part 9: Install Desktop and Enable Services

### 9.1 Install All Packages

```bash
# Copy the shared world file (common package list)
cp /root/gentoo-machines/shared/world /var/lib/portage/world

# Install everything (1-2 hours depending on hardware)
emerge --ask --update --deep --newuse @world
```

### 9.2 Enable Services

```bash
# Essential services
rc-update add dbus default
rc-update add elogind default
rc-update add NetworkManager default
rc-update add acpid default
rc-update add sshd default
rc-update add display-manager default

# Power management (for laptops/NUCs)
rc-update add thermald default
rc-update add tlp default

# Audio
rc-update add alsasound boot

# See shared/openrc-services for the complete list
```

### 9.3 Configure LightDM

```bash
nano /etc/lightdm/lightdm.conf

# In the [Seat:*] section, set:
# greeter-session=lightdm-gtk-greeter
# user-session=xfce
```

---

## Part 10: Create User and Finalize

```bash
# Create user with proper groups
useradd -m -G wheel,audio,video,usb,input -s /bin/bash USERNAME

# Set password
passwd USERNAME

# Enable sudo for wheel group
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
```

---

## Part 11: Reboot

```bash
# Exit chroot
exit

# Unmount everything
cd /
umount -R /mnt/gentoo

# Reboot (remove USB when system restarts)
reboot
```

---

## Part 12: Post-Install Verification

After booting into your new Gentoo system:

### 12.1 Verify All Hardware

```bash
# Clone the repo to your home directory
cd ~
git clone https://github.com/YOUR_USER/gentoo-machines.git gentoo-machines
cd gentoo-machines

# Run hardware verification
sudo tools/harvest.sh
sudo -E tools/deep_harvest.sh

# Check that all PCI devices have drivers bound
lspci -k | grep -E "(Kernel driver|Kernel modules)"

# Check for errors
dmesg | grep -i -E "(error|fail|missing|firmware)"

# Capture exact firmware filenames for documentation
dmesg | grep firmware
```

### 12.2 Restore Desktop Configuration

```bash
# Restore all XFCE settings (keybindings, panels, display profiles, xhost)
bash ~/gentoo-machines/shared/restore-desktop.sh

# Restore system configs (elogind, ACPI lid toggle, LightDM) — requires root
sudo bash ~/gentoo-machines/shared/restore-system.sh
```

### 12.3 Connect to WiFi

```bash
nmtui
# Select "Activate a connection" → choose your network
```

### 12.4 Verify Audio

```bash
# Check if audio devices are detected
aplay -l

# Test playback (speaker test)
speaker-test -c 2
```

---

## Troubleshooting

### No WiFi After Boot

```bash
lsmod | grep iwlwifi     # Intel WiFi
lsmod | grep iwlmvm      # Should also be loaded

# If missing:
modprobe iwlwifi
dmesg | grep iwlwifi     # Check for firmware errors

# Common fix: firmware not installed
emerge sys-kernel/linux-firmware
```

### No Ethernet

```bash
lsmod | grep igc          # Intel I225/I226 (NUC11, etc.)
lsmod | grep e1000e       # Intel older GbE
ip link                   # Check if interface exists but is down
dhcpcd INTERFACE          # Try getting an IP
```

### No Audio

```bash
dmesg | grep -i sof       # SOF firmware issues
dmesg | grep -i hda       # HDA codec issues
ls /lib/firmware/intel/sof/ # Verify SOF firmware exists

# Make sure user is in audio group
groups USERNAME
```

### Boot Fails — Can't Find Root

Usually a missing driver in the kernel config or initramfs issue:

1. Boot from USB again
2. Mount partitions (see Part 3.5)
3. Chroot in (see Part 5)
4. Regenerate initramfs: `dracut --force --kver KVER`
5. Regenerate GRUB: `grub-mkconfig -o /boot/grub/grub.cfg`

### Build Fails — Out of Memory

```bash
# Check memory
free -h

# Reduce parallelism for specific packages
mkdir -p /etc/portage/package.env
echo "category/package low-memory.conf" >> /etc/portage/package.env/low-memory

# Or reduce globally in /etc/portage/make.conf
# MAKEOPTS="-j4"
```

### Missing Kernel Driver for Hardware

```bash
# Find the device
lspci -nn | grep -i "device description"

# Check if a driver exists but isn't loaded
lspci -k

# If "Kernel modules" is listed but "Kernel driver in use" is not:
modprobe module_name

# If no module listed, you need to enable it in the kernel config:
cd /usr/src/linux
make menuconfig   # Find and enable the driver
make -j$(nproc) && make modules_install && make install
dracut --force --kver KVER
reboot
```

---

## Adding a New Machine

To add support for a machine not yet in the repository, the repo ships three generators that bootstrap most of the boilerplate from harvest data:

| Step | Tool | Produces |
|------|------|----------|
| 1 | `tools/harvest.sh` + `tools/deep_harvest.sh` | `hardware_inventory.log`, `deep_harvest.log` |
| 2 | `tools/kernel-config-template.sh` | 26-phase `kernel_config.sh` skeleton (auto-lints output) |
| 3 | `tools/generate-config.sh` | `.config`, `make.conf`, `HARDWARE.md` (uses Claude CLI) |
| 4 | `tools/generate-install.sh` | `gentoo_install_part{1,2,3_chroot}.sh` — feature-gated from `machine-profile.sh` |

See `shared/machine-checklist.md` for the full onboarding checklist.

### Step 1: Harvest

Boot the target machine in its current OS (any Linux distro works) and run:

```bash
git clone https://github.com/YOUR_USER/gentoo-machines.git
cd gentoo-machines
sudo tools/harvest.sh
sudo -E tools/deep_harvest.sh
```

Copy both logs to your build host.

### Step 2: Generate the kernel config skeleton

```bash
tools/kernel-config-template.sh <new-machine> /path/to/hardware_inventory.log
```

This produces `machines/<new-machine>/kernel_config.sh` and automatically runs `kconfig-lint.sh` on the result. Review the output for FAIL/WARN entries and hand-edit as needed.

### Step 3: Generate .config, make.conf, and HARDWARE.md

```bash
tools/generate-config.sh <new-machine> <closest-base> /path/to/harvest-dir/
```

`<closest-base>` should be an existing machine with similar hardware class (same CPU family and GPU topology). The tool uses Claude CLI to analyze harvest data against the base and emit `.config`, `make.conf` (with correct `-march=`), and a HARDWARE.md drafted from the harvest.

### Step 4: Generate the 3-phase install scripts

```bash
tools/generate-install.sh <new-machine> <closest-base> /path/to/harvest-dir/
```

Emits `gentoo_install_part{1,2,3_chroot}.sh` wired to the machine's feature profile:

- **part1** — disk partitioning. Header includes all detected block devices (sizes from harvest section 8) so you can verify the target before running. Partition prefix (`p` for NVMe, bare for SATA) is selected automatically.
- **part2** — stage3 + chroot prep. Copies only config files that actually exist in the machine directory (via a `copy_if_exists` helper), so it degrades gracefully while the machine directory is still being filled in.
- **part3_chroot** — 13-phase chroot install. NVIDIA modprobe, Apple mbpfan, Surface HiDPI, Dell EFI fallback, laptop TLP, and desktop always-on blocks are gated on feature flags. Phase 11 (hardware-specific) is the most likely section to need hand-editing — TODO comments point at the relevant machines for reference.

### Step 5: Review, build, and validate

- Review each generated file. Address TODO comments — especially machine-unique quirks like Dell `i915.enable_guc=3`, Apple `applesmc` verification, or Surface IPTSD config that the generator can't infer.
- Follow this installation guide (or the generated 3-phase scripts) to build on the target.
- After first boot, run `sudo tools/verify-install.sh` — it auto-detects the machine from DMI and runs 8 verification sections.
- Re-harvest on Gentoo and diff against the original harvest to confirm all hardware is driven.

---

## Quick Reference

| Task | Command |
|------|---------|
| Update system | `emerge --sync && emerge -avuDN @world` |
| Install package | `emerge --ask category/package` |
| Search packages | `emerge --search name` |
| Remove package | `emerge --deselect category/package && emerge --depclean` |
| Config file updates | `dispatch-conf` |
| Gentoo news | `eselect news read` |
| Rebuild kernel | `cd /usr/src/linux && make oldconfig && make -j$(nproc) && make modules_install install` |
| Update GRUB | `grub-mkconfig -o /boot/grub/grub.cfg` |
| Update system (tool) | `tools/update-system.sh fetch` then `world` / `config-update` / `check` / `prepare` / `build` / `install` / `verify` / `clean` |

---

## Kernel Updates

For production machines already running Gentoo. Use `tools/update-system.sh` for a guided workflow, or follow the manual steps below.

### When to Update

- **LTS point releases** (e.g., 6.18.12 → 6.18.16): Security fixes, driver fixes. Safe — Kconfig rarely changes within a series.
- **Security advisories**: Check [kernel.org](https://www.kernel.org/) or Gentoo GLSAs.
- **Cross-series migration** (e.g., 6.12 → 6.18): Major update. Many Kconfig symbols change. Use `kernel_config.sh` to regenerate config.

### Kernel Strategy

This repository uses `gentoo-sources` with manual configuration via `kernel_config.sh`, not distribution kernels (`gentoo-kernel`/`gentoo-kernel-bin`). No initramfs is generated — root-path drivers (NVMe, AHCI, ext4) are built-in (=y). `sys-kernel/installkernel` with the `grub` USE flag handles GRUB updates automatically on `make install`. Old kernels are cleaned up with `eclean-kernel -n 3` (keep current + 2 rollback).

### Quick Reference — Minor Updates (Same Series)

```bash
# 1. Sync and update system packages
sudo tools/update-system.sh fetch          # emerge --sync + gentoo-sources + eselect kernel + news
sudo tools/update-system.sh world          # emerge @world + preserved-rebuild + depclean
sudo tools/update-system.sh config-update  # merge updated /etc config files via dispatch-conf

# 2. Build and install kernel
tools/update-system.sh check               # pre-flight report
tools/update-system.sh prepare             # backup + config migrate + patches
tools/update-system.sh build               # compile
sudo tools/update-system.sh install        # install + NVIDIA rebuild
# reboot
tools/update-system.sh verify              # post-reboot checks

# 3. Clean up old kernels
sudo tools/update-system.sh clean          # eclean-kernel -n 3
```

### Cross-Series Migration

Cross-series updates (different major.minor) use `kernel_config.sh` to regenerate the config from scratch, since Kconfig options change significantly between series.

```bash
# Same workflow — the tool auto-detects cross-series and uses kernel_config.sh
sudo tools/update-system.sh fetch          # sync + install new sources + news
sudo tools/update-system.sh world          # update @world (may pull new deps for new kernel)
sudo tools/update-system.sh config-update  # merge any updated /etc configs
tools/update-system.sh check               # shows "cross-series" strategy
tools/update-system.sh prepare             # defconfig → kernel_config.sh → olddefconfig
tools/update-system.sh build
sudo tools/update-system.sh install
# reboot
tools/update-system.sh verify
sudo tools/update-system.sh clean          # remove old kernels
```

### Rollback

If the new kernel has issues:

1. Reboot and select the old kernel from the GRUB menu (hold Shift during boot)
2. Old kernel and modules are still on disk — nothing was deleted
3. Fix the issue, rebuild, and try again

### Manual Steps (Without the Tool)

```bash
cd /usr/src/linux
zcat /proc/config.gz > .config         # copy running config
make olddefconfig                       # update for new version
make -j$(nproc)                         # build
make modules_install                    # install modules
make install                            # install kernel + update GRUB
# NVIDIA machines: emerge @module-rebuild
reboot
```
