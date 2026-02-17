# Dell XPS 13 9315 Gentoo Installation Guide

Complete beginner-friendly installation guide from scratch for the Dell XPS 13 9315.

## What is Gentoo?

Gentoo is a source-based Linux distribution where you compile packages optimized for your specific hardware. This guide provides a pre-configured kernel and settings specifically tuned for the Dell XPS 13 9315, saving you hours of configuration.

## Prerequisites

- A USB drive (4GB minimum)
- Internet connection (WiFi works, or USB Ethernet adapter)
- 2-4 hours for installation (compiling takes time)
- Basic comfort with the command line

---

## Part 1: Preparation

### 1.1 Create a Bootable USB

On any Linux/Mac/Windows system, download a live Linux ISO:

- **Recommended**: [SystemRescue](https://www.system-rescue.org/Download/) - includes all tools needed
- **Alternative**: [Gentoo Minimal Install](https://www.gentoo.org/downloads/)

Create the bootable USB:

```bash
# On Linux/Mac (replace sdX with your USB device)
# WARNING: This will erase the USB drive!
# Use 'lsblk' to identify your USB drive

dd if=systemrescue-x.xx-amd64.iso of=/dev/sdX bs=4M status=progress
sync
```

On Windows, use [Rufus](https://rufus.ie/) or [Etcher](https://etcher.io/).

### 1.2 Configure BIOS

Restart your XPS 9315 and press **F2** repeatedly to enter BIOS Setup.

**Required changes:**
1. **Secure Boot** → Disabled (or configure later with your own keys)
2. **SATA Operation** → AHCI (should be default)
3. **Boot Sequence** → Enable USB boot

Press **F10** to save and exit.

### 1.3 Boot from USB

1. Insert your USB drive
2. Restart and press **F12** repeatedly for boot menu
3. Select your USB drive
4. Choose default boot option

---

## Part 2: Network Setup

### 2.1 Find Your Network Interface

```bash
# List all network interfaces
ip link

# You'll see something like:
# 1: lo: <LOOPBACK>
# 2: wlp0s20f3: <BROADCAST>  <-- This is your WiFi
```

Note your WiFi interface name (probably `wlp0s20f3` on XPS 9315, NOT `wlan0`).

### 2.2 Connect to WiFi

```bash
# Replace INTERFACE with your actual interface name
# Replace SSID and PASSWORD with your network details

wpa_passphrase "YourNetworkName" "YourPassword" > /etc/wpa_supplicant.conf
wpa_supplicant -B -i wlp0s20f3 -c /etc/wpa_supplicant.conf
dhcpcd wlp0s20f3

# Verify connectivity
ping -c 3 gentoo.org
```

If using SystemRescue, you can also use `nmtui` for an easier graphical WiFi setup.

---

## Part 3: Disk Setup

### 3.1 Understand the Partition Layout

The XPS 9315 has a 256GB NVMe drive. We'll create 5 partitions:

| Partition | Size | Filesystem | Mount | Why? |
|-----------|------|------------|-------|------|
| nvme0n1p1 | 512M | FAT32 | /boot/efi | Required for UEFI boot |
| nvme0n1p2 | 24G | swap | [SWAP] | 3x RAM helps with compiling |
| nvme0n1p3 | 50G | ext4 | / | Root filesystem, stable & reliable |
| nvme0n1p4 | 40G | XFS | /var/tmp | Portage compiles here - XFS is faster |
| nvme0n1p5 | ~124G | XFS | /home | Your files, XFS handles large files well |

### 3.2 Partition the Drive

**WARNING: This erases everything on the drive!**

```bash
# Start fdisk
fdisk /dev/nvme0n1
```

Inside fdisk, enter these commands one at a time:

```
g                    # Create new GPT partition table

n                    # New partition (EFI)
1                    # Partition number 1
[Enter]              # Default first sector
+512M                # Size 512MB
t                    # Change type
1                    # Type 1 = EFI System

n                    # New partition (Swap)
2                    # Partition number 2
[Enter]              # Default first sector
+24G                 # Size 24GB
t                    # Change type
2                    # Select partition 2
19                   # Type 19 = Linux swap

n                    # New partition (Root)
3                    # Partition number 3
[Enter]              # Default first sector
+50G                 # Size 50GB

n                    # New partition (Portage tmpdir)
4                    # Partition number 4
[Enter]              # Default first sector
+40G                 # Size 40GB

n                    # New partition (Home)
5                    # Partition number 5
[Enter]              # Default first sector
[Enter]              # Use remaining space

p                    # Print partition table to verify
w                    # Write changes and exit
```

### 3.3 Format the Partitions

```bash
# EFI partition (must be FAT32)
mkfs.vfat -F 32 /dev/nvme0n1p1

# Swap
mkswap /dev/nvme0n1p2
swapon /dev/nvme0n1p2

# Root (ext4 - stable, well-tested)
mkfs.ext4 /dev/nvme0n1p3

# Portage tmpdir (XFS - fast for many small files during compilation)
mkfs.xfs /dev/nvme0n1p4

# Home (XFS - fast for large files)
mkfs.xfs /dev/nvme0n1p5
```

### 3.4 Mount the Filesystems

```bash
# Mount root first
mount /dev/nvme0n1p3 /mnt/gentoo

# Create mount points
mkdir -p /mnt/gentoo/boot/efi
mkdir -p /mnt/gentoo/home
mkdir -p /mnt/gentoo/var/tmp

# Mount remaining partitions
mount /dev/nvme0n1p1 /mnt/gentoo/boot/efi
mount /dev/nvme0n1p4 /mnt/gentoo/var/tmp
mount /dev/nvme0n1p5 /mnt/gentoo/home

# Verify mounts
df -h
```

---

## Part 4: Install Gentoo Base System

### 4.1 Download Stage3 Tarball

```bash
cd /mnt/gentoo

# Open the Gentoo downloads page to get the current stage3 URL
# Go to: https://www.gentoo.org/downloads/
# Click "Stage 3" under "amd64"
# Right-click "Stage 3 OpenRC" and copy the link

# Download using the URL you copied (example - URL will be different!)
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc-YYYYMMDDTHHMMSSZ.tar.xz

# Or browse and download directly
links https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/
```

### 4.2 Extract Stage3

```bash
# Extract (this takes a few minutes)
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

# Verify extraction
ls /mnt/gentoo
# Should see: bin, boot, dev, etc, home, lib, lib64, media, mnt, opt, proc, root, run, sbin, sys, tmp, usr, var
```

### 4.3 Download This Repository

```bash
cd /mnt/gentoo/root

# Install git if needed
emerge-webrsync  # Only if git not available

# Clone this repo
git clone https://github.com/cdnwetzel/gentoo_dell_xps9315.git
cd gentoo_dell_xps9315
```

Or download as ZIP from GitHub and extract.

### 4.4 Copy Configuration Files

```bash
# From inside /mnt/gentoo/root/gentoo_dell_xps9315/

# Portage configuration
cp make.conf /mnt/gentoo/etc/portage/make.conf
cp package.use /mnt/gentoo/etc/portage/package.use
cp package.accept_keywords /mnt/gentoo/etc/portage/package.accept_keywords
cp package.license /mnt/gentoo/etc/portage/package.license

# Portage environment overrides (low-memory build settings)
mkdir -p /mnt/gentoo/etc/portage/env
cp portage-env /mnt/gentoo/etc/portage/env/low-memory.conf
```

---

## Part 5: Enter the New System (Chroot)

### 5.1 Prepare for Chroot

```bash
# Copy DNS configuration so internet works inside chroot
cp -L /etc/resolv.conf /mnt/gentoo/etc/

# Mount necessary filesystems
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
# Enter the new system
chroot /mnt/gentoo /bin/bash

# Load environment
source /etc/profile
export PS1="(chroot) $PS1"

# You're now "inside" your new Gentoo system!
```

---

## Part 6: Configure Portage

### 6.1 Sync Package Database

```bash
# Initial sync (faster)
emerge-webrsync

# Full sync
emerge --sync
```

### 6.2 Select Profile

```bash
# List available profiles
eselect profile list

# Select the base amd64 profile (find the number for default/linux/amd64/23.0)
eselect profile set default/linux/amd64/23.0

# Verify
eselect profile show
```

### 6.3 Update System

```bash
# Update everything to match our USE flags
# This may take 30-60 minutes
emerge --ask --verbose --update --deep --newuse @world
```

---

## Part 7: Install Kernel and Firmware

### 7.1 Install Kernel Sources and Firmware

```bash
emerge --ask sys-kernel/gentoo-sources \
    sys-kernel/linux-firmware \
    sys-firmware/intel-microcode \
    sys-firmware/sof-firmware \
    sys-kernel/dracut
```

### 7.2 Select Kernel

```bash
# List available kernels
eselect kernel list

# Select the kernel (usually just 1)
eselect kernel set 1

# Verify - should show symlink to linux-6.x.x-gentoo
ls -l /usr/src/linux
```

### 7.3 Copy and Build Kernel

```bash
# Copy our pre-configured kernel config
cp /root/gentoo_dell_xps9315/.config /usr/src/linux/

# Enter kernel directory
cd /usr/src/linux

# Update config for any kernel version differences
make oldconfig
# Press Enter to accept defaults for any new options

# Build kernel (takes 15-30 minutes)
make -j8

# Install modules
make modules_install

# Install kernel
make install
```

### 7.4 Generate Initramfs

```bash
# Find your kernel version
ls /lib/modules/
# Example output: 6.12.58-gentoo

# Generate initramfs with that version
dracut --kver 6.12.58-gentoo

# Verify
ls /boot/
# Should see: vmlinuz-6.12.58-gentoo, initramfs-6.12.58-gentoo.img
```

---

## Part 8: System Configuration

### 8.1 Configure fstab

```bash
# Get your partition UUIDs
blkid

# You'll see output like:
# /dev/nvme0n1p1: UUID="XXXX-XXXX" TYPE="vfat"
# /dev/nvme0n1p2: UUID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" TYPE="swap"
# etc.

# Edit fstab
nano /etc/fstab
```

Add these lines (replace UUIDs with YOUR values from blkid):

```
# /etc/fstab - Dell XPS 9315 Gentoo

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

Save with Ctrl+O, Enter, Ctrl+X.

### 8.2 Install and Configure GRUB

```bash
# Install GRUB package
emerge --ask sys-boot/grub

# Install GRUB to EFI partition
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo

# Copy our GRUB config (has XPS 9315 specific settings)
cp /root/gentoo_dell_xps9315/grub /etc/default/grub

# Generate GRUB configuration
grub-mkconfig -o /boot/grub/grub.cfg
```

### 8.3 Set Timezone and Locale

```bash
# Set timezone (change to your timezone)
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

# Configure locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8

# Reload environment
env-update && source /etc/profile
```

### 8.4 Set Hostname and Root Password

```bash
# Set hostname
echo "xps9315" > /etc/hostname

# Set root password (you'll type it twice)
passwd
```

---

## Part 9: Install Desktop and Packages

### 9.1 Install All Packages

```bash
# Copy world file (list of all packages to install)
cp /root/gentoo_dell_xps9315/world /var/lib/portage/world

# Install everything (this takes 1-2 hours)
emerge --ask --update --deep --newuse @world
```

### 9.2 Enable Services

```bash
# Essential services
rc-update add dbus default
rc-update add elogind default
rc-update add NetworkManager default
rc-update add acpid default
rc-update add thermald default
rc-update add tlp default
rc-update add alsasound boot

# Display manager (login screen)
rc-update add display-manager default

# Optional: SSH server
rc-update add sshd default
```

### 9.3 Configure LightDM (Login Screen)

```bash
# Edit LightDM config
nano /etc/lightdm/lightdm.conf

# Find the [Seat:*] section and set:
greeter-session=lightdm-gtk-greeter
user-session=xfce
```

---

## Part 10: Create Your User

```bash
# Create user (replace 'yourusername' with your desired username)
useradd -m -G wheel,audio,video,usb,input -s /bin/bash yourusername

# Set password
passwd yourusername

# Enable sudo for wheel group
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
```

---

## Part 11: Reboot into Your New System

### 11.1 Exit and Unmount

```bash
# Exit chroot
exit

# Go back to root
cd /

# Unmount everything
umount -R /mnt/gentoo
```

### 11.2 Reboot

```bash
reboot
```

Remove the USB drive when the system restarts.

---

## Part 12: First Boot

### 12.1 Login

- At the login screen, select your username
- Enter your password
- XFCE desktop should start

### 12.2 Restore Desktop Configuration

```bash
# Restore all XFCE settings (keybindings, panels, display profiles, xhost)
bash ~/gentoo_dell_xps9315/shared/restore-desktop.sh

# Restore system configs (elogind, ACPI lid toggle, LightDM) — requires root
sudo bash ~/gentoo_dell_xps9315/shared/restore-system.sh
```

### 12.3 Connect to WiFi

```bash
# Open a terminal and use NetworkManager TUI
nmtui

# Select "Activate a connection"
# Choose your WiFi network
# Enter password
```

Or click the network icon in the system tray.

### 12.4 Verify Hardware

```bash
# Clone the repo to your home directory
cd ~
git clone https://github.com/cdnwetzel/gentoo_dell_xps9315.git
cd gentoo_dell_xps9315

# Run hardware verification
sudo ./harvest.sh

# Check the output
cat hardware_inventory.log
```

---

## Troubleshooting

### No WiFi After Reboot

```bash
# Check if driver loaded
lsmod | grep iwlwifi

# If not, load it
sudo modprobe iwlwifi

# Check for errors
dmesg | grep iwlwifi
```

### No Audio

```bash
# Check SOF firmware
dmesg | grep sof

# Verify firmware exists
ls /lib/firmware/intel/sof/

# Make sure user is in audio group
groups yourusername
```

### Screen Flickering

The GRUB config includes `i915.enable_psr=0` which should prevent this. If still occurring:

```bash
# Verify kernel parameter is set
cat /proc/cmdline | grep psr
```

### Boot Issues

If system won't boot:
1. Boot from USB again
2. Mount partitions (see Part 3.4)
3. Chroot in (see Part 5)
4. Check GRUB config and regenerate: `grub-mkconfig -o /boot/grub/grub.cfg`

### Package Compilation Fails

```bash
# Check available memory
free -h

# If low on memory, use the included low-memory portage env override
# (already copied to /etc/portage/env/low-memory.conf if you followed Part 4.4)
# Assign it to a specific package:
echo "category/package low-memory.conf" >> /etc/portage/package.env/low-memory

# Or reduce parallel jobs globally in /etc/portage/make.conf
MAKEOPTS="-j4"  # Instead of -j8
```

---

## Congratulations!

You now have a fully functional Gentoo Linux system optimized for the Dell XPS 13 9315.

**Next steps:**
- Customize XFCE to your liking
- Install additional software with `emerge --ask packagename`
- Keep system updated with `emerge --sync && emerge -avuDN @world`

**Useful commands:**
- `emerge --search name` - Search for packages
- `emerge --ask package` - Install a package
- `emerge --unmerge package` - Remove a package
- `dispatch-conf` - Manage config file updates
- `eselect news read` - Read Gentoo news

Welcome to Gentoo!
