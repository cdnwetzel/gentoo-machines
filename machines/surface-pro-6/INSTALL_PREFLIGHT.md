# Surface Pro 6 — One-Shot Install Pre-Flight Checklist
# Goal: ONE chroot session. Everything works on first boot. No re-entry.
#
# Lessons from: MBP 2015 (6+ re-entries), XPS 9510 (3 re-entries), XPS 9315 (clean)

## Pre-Chroot (Part 1 — from Fedora live)

### Disk Layout (NVMe — /dev/nvme0n1)
Simpler layout than XPS 9315 (8GB RAM, 238GB disk, no swap partition — zram only):

| Partition    | Size  | FS    | Mount      | Purpose                       |
|-------------|-------|-------|------------|-------------------------------|
| nvme0n1p1   | 512M  | FAT32 | /boot/efi  | EFI System Partition          |
| nvme0n1p2   | 1G    | ext4  | /boot      | Kernel + config + System.map  |
| nvme0n1p3   | rest  | ext4  | /          | Root (ext4 for reliability)   |

No swap partition — zram-init handles swap (4-6GB compressed, zstd).
No separate /home — 238GB is too small to split.
No /var/tmp partition — use tmpfs from fstab (4G, small because 8GB RAM).

### Pre-Chroot Checklist
- [ ] Disable Secure Boot in Surface UEFI (hold Volume Up + Power)
- [ ] Boot Fedora 43 live USB (Ventoy)
- [ ] Verify NVMe: `lsblk` shows nvme0n1
- [ ] Verify WiFi: connected via NetworkManager
- [ ] Run part1 script (partition + format + mount)
- [ ] Verify mounts: `df -h` shows /mnt/gentoo, /mnt/gentoo/boot, /mnt/gentoo/boot/efi
- [ ] Run part2 script (stage3 + config copy + pseudo-fs mount + chroot prep)

## In-Chroot — The One-Shot Session

### Phase 1: Bootstrap (order matters)
```bash
source /etc/profile
export PS1="(chroot) $PS1"

# 1. Sync portage tree
emerge-webrsync
emerge --sync

# 2. Set profile
eselect profile list
eselect profile set default/linux/amd64/23.0

# 3. Update world with our USE flags (make.conf already copied by part2)
emerge --ask --verbose --update --deep --newuse @world
```

### Phase 2: Kernel + Firmware (before ANY packages)
```bash
# Install kernel sources and ALL firmware first
emerge --ask sys-kernel/gentoo-sources \
    sys-kernel/linux-firmware \
    sys-firmware/intel-microcode \
    sys-kernel/installkernel

# Set up installkernel for auto grub-mkconfig
# (package.use should already have: sys-kernel/installkernel grub)

# Select kernel source
eselect kernel list
eselect kernel set 1
ls -l /usr/src/linux  # verify symlink

# Copy our kernel config
cp /root/surface-pro-6-configs/.config /usr/src/linux/

# Build kernel
cd /usr/src/linux
make olddefconfig  # resolve deps for new kernel version
make -j9           # 4C/8T

# Install
make modules_install
make install

# Verify /boot has files
ls /boot/vmlinuz-* /boot/config-* /boot/System.map-*
```

### Phase 3: Bootloader (before any packages that might fail)
```bash
# Install GRUB
emerge --ask sys-boot/grub

# Install to EFI
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo

# Generate config
grub-mkconfig -o /boot/grub/grub.cfg

# Verify GRUB sees our kernel
grep menuentry /boot/grub/grub.cfg
```

### Phase 4: System Configuration (locale, timezone, hostname, fstab, user)
```bash
# Timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

# Locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update && source /etc/profile

# Hostname
echo "surface-pro-6" > /etc/hostname

# Root password
passwd

# Create user
groupadd -f plugdev  # create if not in stage3
useradd -m -G wheel,audio,video,usb,input,plugdev -s /bin/bash chris
passwd chris

# Sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# fstab — use blkid to get UUIDs
blkid /dev/nvme0n1p1 /dev/nvme0n1p2 /dev/nvme0n1p3
# Then write /etc/fstab with UUIDs (template in configs dir)
```

### Phase 5: Networking (CRITICAL — this is what got missed on MBP)
```bash
# Must install BEFORE reboot or you have no internet
emerge --ask net-wireless/wpa_supplicant \
    net-misc/networkmanager \
    net-misc/dhcpcd \
    gnome-extra/nm-applet

# wpa_supplicant needs dbus USE flag (should be in package.use)
# Verify:
emerge -pv net-wireless/wpa_supplicant | grep dbus
# Must show [dbus] enabled

# Enable services NOW
rc-update add NetworkManager default
```

### Phase 6: ALL Remaining Packages (one big emerge)
```bash
# Copy world file
cp /root/surface-pro-6-configs/world /var/lib/portage/world

# Copy package.use, package.accept_keywords, package.license
cp /root/surface-pro-6-configs/package.use /etc/portage/package.use/surface-pro-6
# (shared/package.use should already be at /etc/portage/package.use/shared)

# Install everything at once
emerge --ask --update --deep --newuse @world

# This will take 1-2 hours. It includes:
# - XFCE desktop (xfce4-meta)
# - LightDM
# - PipeWire + WirePlumber + xfce4-pulseaudio-plugin + pavucontrol
# - Bluetooth (bluez, blueman)
# - Browsers (firefox-bin, google-chrome)
# - Power management (acpilight, thermald, tlp, zram-init)
# - Dev tools (git, geany, vscode, tmux, htop, btop)
# - System tools (dmidecode, i2c-tools, pciutils, usbutils, lm-sensors)
# - VPN (networkmanager-sstp)
# - Remote desktop (remmina)
# - SSH server (openssh)
```

### Phase 7: Portage Infrastructure (disk fallback for big packages)
```bash
# Create portage tmpfs and disk dirs
mkdir -p /var/tmp/portage
chown portage:portage /var/tmp/portage
mkdir -p /var/tmp/portage-disk
chown portage:portage /var/tmp/portage-disk

# Verify package.env and env/notmpfs.conf are in place
cat /etc/portage/package.env     # should list chromium, llvm, rust, gcc, etc.
cat /etc/portage/env/notmpfs.conf  # should show PORTAGE_TMPDIR="/var/tmp/portage-disk"
```

### Phase 8: Services (ALL of them, before reboot)
```bash
# Default runlevel
rc-update add dbus default
rc-update add elogind boot
rc-update add NetworkManager default
rc-update add acpid default
rc-update add bluetooth default
rc-update add thermald default
rc-update add tlp default
rc-update add display-manager default
rc-update add sshd default
rc-update add metalog default
rc-update add local default
rc-update add netmount default

# Boot runlevel
rc-update add alsasound boot
rc-update add zram-init boot
# Note: most boot-level services are already enabled by OpenRC default

# Verify critical services
rc-update show default | grep -E "NetworkManager|dbus|elogind|display-manager|bluetooth"
```

### Phase 9: Display Manager Configuration (LightDM + XFCE)
```bash
# CRITICAL: Get the session name RIGHT
# This is what caused the black screen login loop

# Check what xfce4-session installed
ls /usr/share/xsessions/
# Should show: xfce.desktop
# The session name is "xfce" — NOT "xfce4", NOT "Xfce", NOT "XFCE"

# Check what the .desktop file calls
grep -E "^Exec=|^DesktopNames=" /usr/share/xsessions/xfce.desktop

# Configure LightDM (copy our shared config or edit manually)
cp /root/surface-pro-6-configs/lightdm.conf /etc/lightdm/lightdm.conf

# Or edit manually — the critical lines in [Seat:*]:
#   user-session=xfce
#   session-wrapper=/etc/lightdm/Xsession
#   greeter-session=lightdm-gtk-greeter

# Verify Xsession wrapper exists
ls -la /etc/lightdm/Xsession
# If missing, lightdm should have installed it

# Set display manager
sed -i 's/DISPLAYMANAGER=".*"/DISPLAYMANAGER="lightdm"/' /etc/conf.d/display-manager
```

### Phase 10: Audio (PipeWire — get it right the first time)
```bash
# PipeWire should already be emerged from Phase 6
# Verify it installed correctly
emerge -pv media-video/pipewire | grep "sound-server"
# Must show sound-server USE flag enabled

# WirePlumber is the session manager
emerge -pv media-video/wireplumber

# The autostart happens in user session via gentoo-pipewire-launcher
# This gets added to restore-desktop.sh or ~/.config/autostart/

# DO NOT install pulseaudio-daemon — PipeWire replaces it
# The xfce4-pulseaudio-plugin talks to PipeWire's PulseAudio interface
```

### Phase 11: Hardware-Specific (Surface Pro 6)
```bash
# Backlight control
# acpilight already in world — provides xbacklight via sysfs
# Backlight path: /sys/class/backlight/intel_backlight (max 7500)
# User must be in video group (done in Phase 4)

# zram-init config
cat > /etc/conf.d/zram-init << 'EOF'
# Surface Pro 6: 8GB RAM, use 4GB compressed swap (zstd)
# ZRAM is built-in (=y), so load_on_start=no
load_on_start="no"
unload_on_stop="no"

# Number of zram devices — REQUIRED or service silently does nothing
num_devices="1"

# Device 0: compressed swap
type0="swap"
size0="4096"
algo0="zstd"
labl0="zram_swap"
EOF

# Battery plugin for XFCE panel
# xfce4-battery-plugin should be in world file
# (MBP has it, Surface Pro 6 needs it too)

# Surface thermal: thermald + tlp handle everything
# No mbpfan needed (that's Apple-only)
# No custom fan config (SAM handles it)
```

### Phase 12: fstab (with portage tmpfs)
```bash
# Write final fstab with actual UUIDs from blkid
# Template:
cat > /etc/fstab << 'FSTAB'
# /etc/fstab - Surface Pro 6 Gentoo
# <uuid>                                 <mount>      <fs>   <opts>                                              <dump> <pass>
UUID=<efi-uuid>                          /boot/efi    vfat   defaults,noatime,umask=0077                         0      0
UUID=<boot-uuid>                         /boot        ext4   defaults,noatime                                    0      2
UUID=<root-uuid>                         /            ext4   defaults,noatime                                    0      1

# Portage tmpfs — 4GB (8GB RAM machine, keep half for system)
tmpfs                                    /var/tmp/portage tmpfs size=4G,uid=portage,gid=portage,mode=775,nosuid,noatime,nodev 0 0
FSTAB
# THEN replace <xxx-uuid> with actual UUIDs from blkid
```

### Phase 13: Final Verification (BEFORE exiting chroot)
```bash
echo "=== PRE-REBOOT VERIFICATION ==="

# Kernel installed?
ls /boot/vmlinuz-* && echo "[OK] Kernel" || echo "[FAIL] No kernel!"

# GRUB configured?
grep -q menuentry /boot/grub/grub.cfg && echo "[OK] GRUB" || echo "[FAIL] GRUB!"

# fstab has all mounts?
grep -c UUID /etc/fstab | xargs -I{} echo "[INFO] {} UUID entries in fstab"

# WiFi packages installed?
qlist -I net-wireless/wpa_supplicant && echo "[OK] wpa_supplicant" || echo "[FAIL] wpa_supplicant!"
qlist -I net-misc/networkmanager && echo "[OK] NetworkManager" || echo "[FAIL] NetworkManager!"

# Display manager configured?
grep -q "user-session=xfce" /etc/lightdm/lightdm.conf && echo "[OK] LightDM session=xfce" || echo "[FAIL] LightDM!"
ls /usr/share/xsessions/xfce.desktop && echo "[OK] xfce.desktop exists" || echo "[FAIL] xfce.desktop!"

# Services enabled?
for svc in dbus NetworkManager display-manager; do
    rc-update show default | grep -q "$svc" && echo "[OK] $svc enabled" || echo "[FAIL] $svc NOT enabled!"
done
rc-update show boot | grep -q elogind && echo "[OK] elogind enabled" || echo "[FAIL] elogind NOT enabled!"

# Browsers installed?
qlist -I www-client/firefox-bin && echo "[OK] Firefox" || echo "[WARN] No Firefox"
qlist -I www-client/google-chrome && echo "[OK] Chrome" || echo "[WARN] No Chrome"

# PipeWire installed?
qlist -I media-video/pipewire && echo "[OK] PipeWire" || echo "[FAIL] PipeWire!"

# User exists?
id chris && echo "[OK] User chris" || echo "[FAIL] No user!"
groups chris | grep -q video && echo "[OK] video group" || echo "[FAIL] Not in video group!"

# Root password set?
grep -q '!' /etc/shadow | head -1 || echo "[OK] Root password set"

# Firmware present?
ls /lib/firmware/mrvl/pcie8897_uapsta.bin* && echo "[OK] WiFi firmware" || echo "[FAIL] WiFi firmware!"
ls /lib/firmware/i915/kbl_dmc_ver1_04.bin* && echo "[OK] i915 firmware" || echo "[FAIL] i915 firmware!"

echo "=== END VERIFICATION ==="
echo "If all OK, exit chroot and reboot."
echo "If ANY [FAIL], fix it NOW. Do NOT reboot."
```

## Post-First-Boot

### Immediate Verification
```bash
# WiFi
nmtui  # connect to WiFi
ping -c3 gentoo.org

# Display
xrandr  # should show 2736x1824

# Audio
pactl info | grep "Server Name"  # should show PipeWire
speaker-test -c 2 -t wav

# Brightness
xbacklight -get

# zram
swapon --show  # should show zram0, 4G, zstd

# Thermal
cat /sys/devices/system/cpu/cpuidle/current_driver
sensors  # should show coretemp values
```

### Restore Desktop
```bash
# Clone repo to home
cd ~
git clone https://github.com/cdnwetzel/gentoo-machines.git
cd gentoo-machines

# Restore XFCE settings
bash shared/restore-desktop.sh
sudo bash shared/restore-system.sh
```

## Package Inventory — What Goes in the Surface Pro 6 World File

### From shared/world (reuse as-is):
All packages EXCEPT:
- x11-drivers/nvidia-drivers (no NVIDIA on Surface Pro 6)
- sys-process/nvtop (no GPU to monitor)

### Additional for Surface Pro 6:
- xfce-extra/xfce4-battery-plugin (it's a laptop)
- www-client/firefox-bin (binary, instant browser)
- sys-kernel/dracut (if using initramfs)
- dev-util/ccache (speed up rebuilds)
- app-portage/cpuid2cpuflags (verify CPU flags)

### From MBP world (also needed):
- xfce-extra/xfce4-battery-plugin
- www-client/firefox-bin
- sys-kernel/dracut

### NOT needed (MBP-specific):
- app-laptop/mbpfan (no applesmc)
- media-libs/libva-intel-driver (use iHD on 8th gen+)

## Known Good Configuration Decisions

| Decision | Value | Why |
|----------|-------|-----|
| DRM_I915 | =m (module) | Firmware loads from /lib/firmware after root mount |
| CONFIG_ZRAM | =y (built-in) | Then zram-init: load_on_start=no |
| ZRAM backend | zstd | Better compression than lz4, CPU can handle it |
| Swap | zram only, 4GB | 8GB RAM, no disk swap partition |
| tmpfs | 4GB | Half of RAM; large builds go to /var/tmp/portage-disk |
| Firmware | /lib/firmware/ | All drivers as modules, no CONFIG_EXTRA_FIRMWARE |
| WiFi | mwifiex_pcie =m | Mainline, firmware from linux-firmware |
| Audio | snd_hda_intel =m | ALC298 codec, subsystem 0x10ec10cc |
| Backlight | intel_backlight | sysfs raw, max 7500, acpilight for control |
| LightDM session | xfce | NOT xfce4, NOT Xfce, NOT XFCE |
| Initramfs | optional | Can boot without if all root-path drivers built-in |
