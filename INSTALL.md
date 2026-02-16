# Dell XPS 13 9315 Gentoo Installation Guide

Complete installation guide from scratch for the Dell XPS 13 9315.

## Prerequisites

- USB drive with a live Linux distro (SystemRescue, Gentoo minimal, etc.)
- Internet connection (WiFi or USB Ethernet adapter)
- This repo cloned or downloaded

## 1. Boot Live Environment

Boot from USB and ensure you have network connectivity:

```bash
# For WiFi (if using wpa_supplicant)
wpa_passphrase "SSID" "password" > /etc/wpa_supplicant.conf
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
dhcpcd wlan0

# Verify connectivity
ping -c 3 gentoo.org
```

## 2. Partition the NVMe Drive

The XPS 9315 has a 256GB NVMe drive. Recommended partition layout:

| Partition | Size | Type | Mount | Purpose |
|-----------|------|------|-------|---------|
| nvme0n1p1 | 512M | EFI System | /boot/efi | UEFI boot |
| nvme0n1p2 | 24G | Linux swap | [SWAP] | Swap (3x RAM for 8GB system) |
| nvme0n1p3 | 50G | Linux filesystem | / | Root (ext4) |
| nvme0n1p4 | 40G | Linux filesystem | /var/tmp | Portage tmpdir (xfs) |
| nvme0n1p5 | ~124G | Linux filesystem | /home | Home (xfs) |

```bash
# Partition with fdisk or parted
fdisk /dev/nvme0n1

# Create partitions:
# g     - create new GPT partition table
# n 1   - 512M, type EFI System (1)
# n 2   - 24G, type Linux swap (19)
# n 3   - 50G, type Linux filesystem (20)
# n 4   - 40G, type Linux filesystem (20)
# n 5   - remainder, type Linux filesystem (20)
# w     - write and exit
```

## 3. Format Partitions

```bash
# EFI partition
mkfs.vfat -F 32 /dev/nvme0n1p1

# Swap
mkswap /dev/nvme0n1p2
swapon /dev/nvme0n1p2

# Root (ext4)
mkfs.ext4 /dev/nvme0n1p3

# Portage tmpdir (xfs for compile performance)
mkfs.xfs /dev/nvme0n1p4

# Home (xfs)
mkfs.xfs /dev/nvme0n1p5
```

## 4. Mount Filesystems

```bash
mount /dev/nvme0n1p3 /mnt/gentoo
mkdir -p /mnt/gentoo/{boot/efi,home,var/tmp}
mount /dev/nvme0n1p1 /mnt/gentoo/boot/efi
mount /dev/nvme0n1p4 /mnt/gentoo/var/tmp
mount /dev/nvme0n1p5 /mnt/gentoo/home
```

## 5. Download and Extract Stage3

```bash
cd /mnt/gentoo

# Download latest stage3 (amd64 openrc)
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc-*.tar.xz

# Extract
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
```

## 6. Copy Configuration Files

Copy the files from this repo:

```bash
# make.conf
cp make.conf /mnt/gentoo/etc/portage/make.conf

# package.use
cp package.use /mnt/gentoo/etc/portage/package.use

# package.accept_keywords
cp package.accept_keywords /mnt/gentoo/etc/portage/package.accept_keywords
```

## 7. Chroot into New System

```bash
# Copy DNS info
cp -L /etc/resolv.conf /mnt/gentoo/etc/

# Mount necessary filesystems
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

# Chroot
chroot /mnt/gentoo /bin/bash
source /etc/profile
export PS1="(chroot) $PS1"
```

## 8. Configure Portage and Sync

```bash
# Sync portage tree
emerge-webrsync
emerge --sync

# Select profile
eselect profile list
eselect profile set default/linux/amd64/23.0
```

## 9. Install Base System

```bash
# Update world
emerge --ask --verbose --update --deep --newuse @world

# Install essential packages
emerge --ask sys-kernel/gentoo-sources sys-kernel/linux-firmware \
    sys-firmware/intel-microcode sys-firmware/sof-firmware \
    sys-kernel/dracut sys-boot/grub sys-apps/pciutils \
    net-misc/dhcpcd net-wireless/wpa_supplicant
```

## 10. Configure and Build Kernel

```bash
# Copy kernel config from this repo
cp .config /usr/src/linux/

cd /usr/src/linux
make oldconfig
make -j8
make modules_install
make install

# Generate initramfs
dracut --kver $(ls /lib/modules/)
```

## 11. Configure fstab

Edit `/etc/fstab` with your partition UUIDs:

```bash
# Get UUIDs
blkid

# Edit fstab (use template from repo)
nano /etc/fstab
```

## 12. Install GRUB

```bash
# Install GRUB for EFI
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo

# Copy GRUB config from repo
cp grub /etc/default/grub

# Generate GRUB config
grub-mkconfig -o /boot/grub/grub.cfg
```

## 13. Configure System

```bash
# Set timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

# Set locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8

# Set hostname
echo "xps9315" > /etc/hostname

# Set root password
passwd
```

## 14. Install Remaining Packages

Install packages from world file:

```bash
# Copy world file
cp world /var/lib/portage/world

# Install all packages
emerge --ask --update --deep --newuse @world
```

## 15. Enable Services

```bash
# Core services
rc-update add dbus default
rc-update add elogind default
rc-update add NetworkManager default
rc-update add acpid default
rc-update add thermald default
rc-update add tlp default
rc-update add sshd default
rc-update add alsasound boot
rc-update add display-manager default
```

## 16. Create User

```bash
useradd -m -G wheel,audio,video,usb,input -s /bin/bash username
passwd username

# Enable sudo for wheel group
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
```

## 17. Reboot

```bash
exit
cd /
umount -R /mnt/gentoo
reboot
```

## Post-Install

After first boot:

1. Connect to WiFi via NetworkManager
2. Run `sudo ./harvest.sh` to verify hardware detection
3. Run `sudo -E ./deep_harvest.sh` to update modprobed-db
4. Configure display manager (LightDM) and XFCE

## Troubleshooting

### No WiFi
Ensure `iwlwifi` module is loaded and firmware is installed:
```bash
modprobe iwlwifi
dmesg | grep iwlwifi
```

### No Audio
Check SOF firmware:
```bash
dmesg | grep sof
ls /lib/firmware/intel/sof/
```

### Display Issues
If screen flickering, ensure `i915.enable_psr=0` is in GRUB_CMDLINE_LINUX.
