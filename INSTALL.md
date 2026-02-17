# Gentoo Linux Installation Guide

General-purpose installation guide for deploying Gentoo on any supported machine in this repository. Each machine has a pre-built kernel `.config` and `make.conf` that eliminates the hardest part of a Gentoo install — hardware-specific kernel configuration.

## Supported Machines

Before starting, confirm your target machine has a config ready:

| Machine | Directory | Config Status |
|---------|-----------|---------------|
| Dell XPS 13 9315 | `machines/xps-9315/` | Production |
| Intel NUC11TNBi5 | `machines/nuc11/` | Ready to build |
| Dell XPS 15 9510 | `machines/xps-9510/` | Planned |
| ASRock B550 / Ryzen 9 5950X | `machines/asrock-b550/` | Planned |
| Dell Precision T5810 | `machines/precision-t5810/` | Planned |
| Dell Precision 7960 | `machines/precision-7960/` | Planned |
| Surface Pro 6 | `machines/surface-pro-6/` | Planned |
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
| `KVER` | `6.12.58-gentoo` | Kernel version from `ls /usr/src/` |

---

## Part 1: Preparation

### 1.1 Harvest Hardware Info (Optional but Recommended)

If the target machine is running another Linux distro, capture hardware info first. This validates the kernel config covers all your hardware:

```bash
# Clone this repo on the target machine (while still running current OS)
git clone https://github.com/cdnwetzel/gentoo_dell_xps9315.git
cd gentoo_dell_xps9315

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
git clone https://github.com/cdnwetzel/gentoo_dell_xps9315.git /mnt/gentoo/root/gentoo_config
```

Or if git isn't available on the live USB, download the ZIP from GitHub and extract it.

### 4.3 Copy Machine-Specific Configuration

```bash
# Set your target machine
MACHINE=nuc11   # Change to your machine directory name

# Portage build settings (machine-specific compiler flags)
cp /mnt/gentoo/root/gentoo_config/machines/${MACHINE}/make.conf /mnt/gentoo/etc/portage/make.conf

# Shared portage files (same across all machines)
cp /mnt/gentoo/root/gentoo_config/shared/package.use /mnt/gentoo/etc/portage/package.use
cp /mnt/gentoo/root/gentoo_config/shared/package.accept_keywords /mnt/gentoo/etc/portage/package.accept_keywords
cp /mnt/gentoo/root/gentoo_config/shared/package.license /mnt/gentoo/etc/portage/package.license

# Portage environment overrides
mkdir -p /mnt/gentoo/etc/portage/env
cp /mnt/gentoo/root/gentoo_config/shared/portage-env /mnt/gentoo/etc/portage/env/low-memory.conf
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
emerge --ask sys-kernel/gentoo-sources sys-kernel/linux-firmware sys-kernel/dracut

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
cp /root/gentoo_config/machines/${MACHINE}/.config /usr/src/linux/

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

### 7.4 Generate Initramfs

```bash
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
if [ -f /root/gentoo_config/machines/${MACHINE}/grub ]; then
    cp /root/gentoo_config/machines/${MACHINE}/grub /etc/default/grub
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
cp /root/gentoo_config/shared/world /var/lib/portage/world

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
git clone https://github.com/cdnwetzel/gentoo_dell_xps9315.git gentoo_config
cd gentoo_config

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
# Restore XFCE keyboard shortcuts (Super+Arrow tiling, app launchers, etc.)
bash ~/gentoo_config/shared/xfce4-keybindings.sh

# Restore XFCE panel layout (top bar + autohide bottom dock)
bash ~/gentoo_config/shared/xfce4-panel.sh
xfce4-panel --restart
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

To add support for a machine not yet in the repository:

### Step 1: Harvest

Boot the target machine in its current OS (any Linux distro works) and run:

```bash
git clone https://github.com/cdnwetzel/gentoo_dell_xps9315.git
cd gentoo_dell_xps9315
sudo tools/harvest.sh
sudo -E tools/deep_harvest.sh
```

Save the output logs.

### Step 2: Generate Config

Copy the closest existing `.config` as a starting point:

```bash
mkdir -p machines/new-machine
cp machines/closest-match/.config machines/new-machine/.config
```

Then modify the config based on harvest data:
- **Enable** drivers for hardware found in the harvest (PCI devices, modules)
- **Disable** drivers specific to the source machine that aren't present
- Check `HARDWARE.md` files for examples of what to change

### Step 3: Create make.conf

Copy and adjust compiler flags for the new CPU:

```bash
cp machines/closest-match/make.conf machines/new-machine/make.conf
# Edit: change -march= to match CPU microarchitecture
# Common values: tigerlake, alderlake, znver3, broadwell, sapphirerapids
```

### Step 4: Document

Create `machines/new-machine/HARDWARE.md` from the harvest data. See existing HARDWARE.md files for the format.

### Step 5: Build and Validate

Follow this installation guide using your new machine directory. After first boot, run the harvest scripts again on Gentoo and compare against the original harvest to verify all hardware is supported.

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
