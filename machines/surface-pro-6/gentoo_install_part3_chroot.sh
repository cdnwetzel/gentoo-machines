#!/bin/bash
# ============================================================================
# gentoo_install_part3_chroot.sh - ONE-SHOT chroot install
# Microsoft Surface Pro 6 - Run INSIDE the chroot
# ============================================================================
# This script runs all 13 phases from INSTALL_PREFLIGHT.md in sequence.
# Goal: ONE chroot session. Everything works on first boot.
#
# Lessons from: MBP 2015 (6+ re-entries), XPS 9510 (3 re-entries)
#
# USAGE:
#   sudo chroot /mnt/gentoo /bin/bash
#   source /etc/profile
#   export PS1="(chroot) $PS1"
#   bash /root/gentoo_install_part3_chroot.sh
#
# The script pauses at key decision points for manual input:
#   - Root password
#   - User password
#   - Kernel menuconfig review
# ============================================================================

set -euo pipefail

CONFIGS="/root/surface-pro-6-configs"

echo "============================================================"
echo "=== Surface Pro 6 One-Shot Chroot Install ==="
echo "============================================================"
echo ""

# Verify we're in a chroot
if [[ ! -f "$CONFIGS/kernel_config.sh" ]]; then
    echo "ERROR: Config files not found at $CONFIGS"
    echo "Are you inside the chroot? Did part2 run?"
    exit 1
fi

# ============================================================================
# PHASE 1: BOOTSTRAP
# ============================================================================
echo "=========================================="
echo "=== PHASE 1: Bootstrap ==="
echo "=========================================="

source /etc/profile
export PS1="(chroot) ${PS1:-}"

# Sync portage tree
echo "[1.1] Syncing portage tree..."
emerge-webrsync
emerge --sync

# Set profile
echo "[1.2] Setting profile..."
eselect profile list
eselect profile set default/linux/amd64/23.0

# Update world with our USE flags
echo "[1.3] Updating @world with USE flags..."
echo "  This may take 10-20 minutes..."
emerge --verbose --update --deep --newuse @world

echo ""
echo "[OK] Phase 1 complete."
echo ""

# ============================================================================
# PHASE 2: KERNEL + FIRMWARE
# ============================================================================
echo "=========================================="
echo "=== PHASE 2: Kernel + Firmware ==="
echo "=========================================="

echo "[2.1] Installing kernel sources and firmware..."
emerge --verbose sys-kernel/gentoo-sources \
    sys-kernel/linux-firmware \
    sys-firmware/intel-microcode \
    sys-kernel/installkernel

# Select kernel source
echo "[2.2] Selecting kernel..."
eselect kernel list
eselect kernel set 1
echo "  Kernel symlink:"
ls -l /usr/src/linux

# Copy base config and apply Surface Pro 6 customizations
echo "[2.3] Configuring kernel..."
cd /usr/src/linux

# Start from MBP 2015 base config
if [[ -f "$CONFIGS/base.config" ]]; then
    cp "$CONFIGS/base.config" .config
    echo "  [OK] Base config copied from MBP 2015"
else
    echo "  [WARN] No base config — using defconfig"
    make defconfig
fi

# Apply Surface Pro 6 customizations
bash "$CONFIGS/kernel_config.sh"

# Resolve dependencies
echo "[2.4] Resolving kernel config dependencies..."
make olddefconfig

# Pause for review
echo ""
echo "=== Kernel config applied. Review with menuconfig? ==="
read -p "Open menuconfig? (y/N): " do_menuconfig
if [[ "$do_menuconfig" == "y" || "$do_menuconfig" == "Y" ]]; then
    make menuconfig
fi

# Build kernel
echo "[2.5] Building kernel (make -j9)..."
echo "  This will take 15-30 minutes on 4C/8T..."
make -j9

# Install
echo "[2.6] Installing kernel modules..."
make modules_install

echo "[2.7] Installing kernel..."
make install

# Verify
echo "[2.8] Verifying kernel installation..."
ls -la /boot/vmlinuz-* /boot/config-* /boot/System.map-*

echo ""
echo "[OK] Phase 2 complete."
echo ""

# ============================================================================
# PHASE 3: BOOTLOADER (GRUB)
# ============================================================================
echo "=========================================="
echo "=== PHASE 3: Bootloader ==="
echo "=========================================="

echo "[3.1] Installing GRUB..."
emerge --verbose sys-boot/grub

echo "[3.2] Installing GRUB to EFI..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo

echo "[3.3] Generating GRUB config..."
grub-mkconfig -o /boot/grub/grub.cfg

echo "[3.4] Verifying GRUB sees kernel..."
grep menuentry /boot/grub/grub.cfg

echo ""
echo "[OK] Phase 3 complete."
echo ""

# ============================================================================
# PHASE 4: SYSTEM CONFIGURATION
# ============================================================================
echo "=========================================="
echo "=== PHASE 4: System Configuration ==="
echo "=========================================="

# Timezone
echo "[4.1] Setting timezone to America/New_York..."
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime

# Locale
echo "[4.2] Configuring locale..."
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update && source /etc/profile

# Hostname
echo "[4.3] Setting hostname..."
echo "surface-pro-6" > /etc/hostname

# Hosts file
cat > /etc/hosts << 'EOF'
127.0.0.1       localhost
::1             localhost
127.0.1.1       surface-pro-6.localdomain surface-pro-6
EOF

# Root password
echo ""
echo "[4.4] Set root password:"
passwd

# Create plugdev group if not in stage3 (needed for device hotplug)
groupadd -f plugdev

echo "[4.5] Creating user 'chris'..."
useradd -m -G wheel,audio,video,usb,input,plugdev -s /bin/bash chris
echo ""
echo "Set password for user 'chris':"
passwd chris

# Sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

echo ""
echo "[OK] Phase 4 complete."
echo ""

# ============================================================================
# PHASE 5: NETWORKING (CRITICAL — missed on MBP = no WiFi on first boot)
# ============================================================================
echo "=========================================="
echo "=== PHASE 5: Networking (CRITICAL) ==="
echo "=========================================="

echo "[5.1] Installing networking packages..."
emerge --verbose net-wireless/wpa_supplicant \
    net-misc/networkmanager \
    net-misc/dhcpcd \
    gnome-extra/nm-applet \
    net-wireless/wireless-regdb \
    net-wireless/wireless-tools

# Verify wpa_supplicant has dbus
echo "[5.2] Verifying wpa_supplicant dbus support..."
emerge -pv net-wireless/wpa_supplicant | grep dbus || echo "  WARNING: Check dbus USE flag!"

# Enable NetworkManager service NOW
echo "[5.3] Enabling NetworkManager..."
rc-update add NetworkManager default

echo ""
echo "[OK] Phase 5 complete — WiFi will work on first boot."
echo ""

# ============================================================================
# PHASE 6: ALL REMAINING PACKAGES
# ============================================================================
echo "=========================================="
echo "=== PHASE 6: All Packages ==="
echo "=========================================="

echo "[6.1] Installing world file..."
cp "$CONFIGS/world" /var/lib/portage/world

echo "[6.2] Installing all packages..."
echo "  This will take 1-2 hours. Includes:"
echo "    XFCE, LightDM, PipeWire, browsers, dev tools, etc."
echo ""
emerge --verbose --update --deep --newuse @world

echo ""
echo "[OK] Phase 6 complete."
echo ""

# ============================================================================
# PHASE 7: PORTAGE INFRASTRUCTURE
# ============================================================================
echo "=========================================="
echo "=== PHASE 7: Portage Infrastructure ==="
echo "=========================================="

echo "[7.1] Setting up portage directories..."
mkdir -p /var/tmp/portage
chown portage:portage /var/tmp/portage
mkdir -p /var/tmp/portage-disk
chown portage:portage /var/tmp/portage-disk

# Set up ccache
echo "[7.2] Setting up ccache..."
mkdir -p /var/cache/ccache
chown root:portage /var/cache/ccache
chmod 2775 /var/cache/ccache

echo "[7.3] Verifying package.env..."
cat /etc/portage/package.env 2>/dev/null || echo "  [WARN] package.env not found!"
echo ""
cat /etc/portage/env/notmpfs.conf 2>/dev/null || echo "  [WARN] notmpfs.conf not found!"

echo ""
echo "[OK] Phase 7 complete."
echo ""

# ============================================================================
# PHASE 8: OPENRC SERVICES
# ============================================================================
echo "=========================================="
echo "=== PHASE 8: OpenRC Services ==="
echo "=========================================="

echo "[8.1] Enabling default runlevel services..."
rc-update add dbus default
rc-update add elogind boot
rc-update add acpid default
rc-update add bluetooth default
rc-update add thermald default
rc-update add tlp default
rc-update add display-manager default
rc-update add sshd default
rc-update add metalog default
rc-update add local default
rc-update add netmount default
rc-update add zram-init boot
rc-update add alsasound boot

echo ""
echo "[8.2] Verifying critical services..."
echo "  Default runlevel:"
rc-update show default
echo "  Boot runlevel:"
rc-update show boot

echo ""
echo "[OK] Phase 8 complete."
echo ""

# ============================================================================
# PHASE 9: DISPLAY MANAGER (LightDM + XFCE)
# ============================================================================
echo "=========================================="
echo "=== PHASE 9: LightDM + XFCE ==="
echo "=========================================="

echo "[9.1] Checking XFCE session file..."
ls /usr/share/xsessions/
grep -E "^Exec=|^DesktopNames=" /usr/share/xsessions/xfce.desktop 2>/dev/null || echo "  WARNING: xfce.desktop not found!"

echo "[9.2] Installing LightDM config..."
if [[ -f "$CONFIGS/lightdm.conf" ]]; then
    cp "$CONFIGS/lightdm.conf" /etc/lightdm/lightdm.conf
    echo "  [OK] lightdm.conf installed"
else
    echo "  [WARN] No lightdm.conf found, configuring manually..."
    # Set the critical values
    sed -i 's/^#user-session=.*/user-session=xfce/' /etc/lightdm/lightdm.conf 2>/dev/null || true
    sed -i 's/^#session-wrapper=.*/session-wrapper=\/etc\/lightdm\/Xsession/' /etc/lightdm/lightdm.conf 2>/dev/null || true
fi

echo "[9.3] Verifying LightDM configuration..."
grep "user-session=xfce" /etc/lightdm/lightdm.conf && echo "  [OK] user-session=xfce" || echo "  [FAIL] Check user-session!"
grep "session-wrapper=/etc/lightdm/Xsession" /etc/lightdm/lightdm.conf && echo "  [OK] session-wrapper" || echo "  [WARN] Check session-wrapper"
ls -la /etc/lightdm/Xsession 2>/dev/null && echo "  [OK] Xsession exists" || echo "  [FAIL] Xsession missing!"

echo "[9.4] Setting display manager..."
sed -i 's/DISPLAYMANAGER=".*"/DISPLAYMANAGER="lightdm"/' /etc/conf.d/display-manager 2>/dev/null || \
    echo 'DISPLAYMANAGER="lightdm"' > /etc/conf.d/display-manager

echo ""
echo "[OK] Phase 9 complete."
echo ""

# ============================================================================
# PHASE 10: AUDIO (PipeWire)
# ============================================================================
echo "=========================================="
echo "=== PHASE 10: PipeWire Audio ==="
echo "=========================================="

echo "[10.1] Verifying PipeWire installation..."
qlist -I media-video/pipewire && echo "  [OK] PipeWire installed" || echo "  [FAIL] PipeWire missing!"
qlist -I media-video/wireplumber && echo "  [OK] WirePlumber installed" || echo "  [FAIL] WirePlumber missing!"
qlist -I xfce-extra/xfce4-pulseaudio-plugin && echo "  [OK] xfce4-pulseaudio-plugin installed" || echo "  [WARN] Volume plugin missing"

echo "[10.2] PipeWire autostart configured via gentoo-pipewire-launcher"
echo "  Will be set up by restore-desktop.sh after first login"

echo ""
echo "[OK] Phase 10 complete."
echo ""

# ============================================================================
# PHASE 11: SURFACE-SPECIFIC HARDWARE
# ============================================================================
echo "=========================================="
echo "=== PHASE 11: Surface Hardware ==="
echo "=========================================="

echo "[11.1] Configuring zram-init..."
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
echo "  [OK] zram-init configured (4GB zstd swap)"

echo "[11.2] No Surface-specific modprobe needed"
echo "  Audio: ALC298 autoconfig (no model quirk)"
echo "  WiFi: mwifiex_pcie (mainline)"
echo "  Touchscreen: Hardware non-functional (skipping IPTS)"

echo "[11.3] Verifying firmware files..."
ls /lib/firmware/mrvl/pcie8897_uapsta.bin* 2>/dev/null && echo "  [OK] WiFi firmware" || echo "  [FAIL] WiFi firmware!"
ls /lib/firmware/mrvl/usb8897_uapsta.bin* 2>/dev/null && echo "  [OK] BT firmware" || echo "  [FAIL] BT firmware!"
ls /lib/firmware/i915/kbl_dmc_ver1_04.bin* 2>/dev/null && echo "  [OK] i915 DMC firmware" || echo "  [FAIL] i915 firmware!"

echo ""
echo "[OK] Phase 11 complete."
echo ""

# ============================================================================
# PHASE 12: FSTAB (already generated by part2)
# ============================================================================
echo "=========================================="
echo "=== PHASE 12: fstab ==="
echo "=========================================="

echo "[12.1] Current fstab:"
cat /etc/fstab
echo ""
echo "  [OK] fstab was generated by part2 with actual UUIDs."

echo ""
echo "[OK] Phase 12 complete."
echo ""

# ============================================================================
# PHASE 13: VERIFICATION (CRITICAL — check before reboot!)
# ============================================================================
echo "=========================================="
echo "=== PHASE 13: PRE-REBOOT VERIFICATION ==="
echo "=========================================="
echo ""

FAIL=0

# Kernel
ls /boot/vmlinuz-* &>/dev/null && echo "[OK] Kernel installed" || { echo "[FAIL] No kernel!"; FAIL=$((FAIL+1)); }

# GRUB
grep -q menuentry /boot/grub/grub.cfg 2>/dev/null && echo "[OK] GRUB configured" || { echo "[FAIL] GRUB!"; FAIL=$((FAIL+1)); }

# fstab
UUID_COUNT=$(grep -c UUID /etc/fstab || true)
echo "[INFO] $UUID_COUNT UUID entries in fstab"
[[ $UUID_COUNT -ge 3 ]] || { echo "[FAIL] fstab missing entries!"; FAIL=$((FAIL+1)); }

# WiFi
qlist -I net-wireless/wpa_supplicant &>/dev/null && echo "[OK] wpa_supplicant installed" || { echo "[FAIL] wpa_supplicant!"; FAIL=$((FAIL+1)); }
qlist -I net-misc/networkmanager &>/dev/null && echo "[OK] NetworkManager installed" || { echo "[FAIL] NetworkManager!"; FAIL=$((FAIL+1)); }

# LightDM
grep -q "user-session=xfce" /etc/lightdm/lightdm.conf 2>/dev/null && echo "[OK] LightDM session=xfce" || { echo "[FAIL] LightDM session!"; FAIL=$((FAIL+1)); }
ls /usr/share/xsessions/xfce.desktop &>/dev/null && echo "[OK] xfce.desktop exists" || { echo "[FAIL] xfce.desktop!"; FAIL=$((FAIL+1)); }

# Services
for svc in dbus NetworkManager display-manager acpid bluetooth sshd; do
    rc-update show default 2>/dev/null | grep -q "$svc" && echo "[OK] $svc enabled" || { echo "[FAIL] $svc NOT enabled!"; FAIL=$((FAIL+1)); }
done
rc-update show boot 2>/dev/null | grep -q elogind && echo "[OK] elogind enabled" || { echo "[FAIL] elogind NOT enabled!"; FAIL=$((FAIL+1)); }
rc-update show boot 2>/dev/null | grep -q zram && echo "[OK] zram-init enabled" || { echo "[FAIL] zram-init NOT enabled!"; FAIL=$((FAIL+1)); }

# Browsers
qlist -I www-client/firefox-bin &>/dev/null && echo "[OK] Firefox" || echo "[WARN] No Firefox (non-critical)"
qlist -I www-client/google-chrome &>/dev/null && echo "[OK] Chrome" || echo "[WARN] No Chrome (non-critical)"

# PipeWire
qlist -I media-video/pipewire &>/dev/null && echo "[OK] PipeWire" || { echo "[FAIL] PipeWire!"; FAIL=$((FAIL+1)); }

# User
id chris &>/dev/null && echo "[OK] User chris exists" || { echo "[FAIL] No user chris!"; FAIL=$((FAIL+1)); }
groups chris 2>/dev/null | grep -q video && echo "[OK] chris in video group" || { echo "[FAIL] chris not in video group!"; FAIL=$((FAIL+1)); }

# Sudo
grep -q "^%wheel" /etc/sudoers 2>/dev/null && echo "[OK] sudo for wheel group" || { echo "[FAIL] sudo not configured!"; FAIL=$((FAIL+1)); }

# Display manager conf
grep -q 'DISPLAYMANAGER="lightdm"' /etc/conf.d/display-manager 2>/dev/null && echo "[OK] display-manager=lightdm" || { echo "[FAIL] DISPLAYMANAGER not set!"; FAIL=$((FAIL+1)); }

# Firmware
ls /lib/firmware/mrvl/pcie8897_uapsta.bin* &>/dev/null && echo "[OK] WiFi firmware" || { echo "[FAIL] WiFi firmware!"; FAIL=$((FAIL+1)); }
ls /lib/firmware/i915/kbl_dmc_ver1_04.bin* &>/dev/null && echo "[OK] i915 firmware" || { echo "[FAIL] i915 firmware!"; FAIL=$((FAIL+1)); }

echo ""
echo "=========================================="
if [[ $FAIL -eq 0 ]]; then
    echo "=== ALL CHECKS PASSED ==="
    echo "=========================================="
    echo ""
    echo "Safe to exit chroot and reboot!"
    echo ""
    echo "Exit steps:"
    echo "  exit                          # leave chroot"
    echo "  cd /"
    echo "  umount -l /mnt/gentoo/dev{/shm,/pts,}"
    echo "  umount -R /mnt/gentoo"
    echo "  reboot"
    echo ""
    echo "Post-boot:"
    echo "  1. Connect WiFi: nmtui"
    echo "  2. Verify audio: pactl info | grep 'Server Name'"
    echo "  3. Verify display: xrandr (should show 2736x1824)"
    echo "  4. Verify zram: swapon --show"
    echo "  5. Restore desktop: bash ~/gentoo-machines/shared/restore-desktop.sh"
else
    echo "=== $FAIL CHECKS FAILED ==="
    echo "=========================================="
    echo ""
    echo "FIX THE FAILURES ABOVE BEFORE REBOOTING!"
    echo "Do NOT exit the chroot until all checks pass."
fi
