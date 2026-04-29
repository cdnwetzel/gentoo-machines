#!/bin/bash
# ============================================================================
# gentoo_install_part3_chroot.sh - ONE-SHOT chroot install
# Dell Precision T5810 - Run INSIDE the chroot
# ============================================================================
# This script runs all 13 phases in sequence.
# Goal: ONE chroot session. Everything works on first boot.
#
# Lessons from: MBP 2015 (6+ re-entries), XPS 9510 (3 re-entries),
#               Surface Pro 6 (1 re-entry target)
#
# USAGE:
#   sudo chroot /mnt/gentoo /bin/bash
#   source /etc/profile
#   export PS1="(chroot) $PS1"
#   bash /root/gentoo_install_part3_chroot.sh
#
# The script pauses at key decision points:
#   - Root password
#   - User password
#   - Kernel menuconfig review
# ============================================================================
# MACHINE CONFIG — T5810-specific values at top, universal logic below
# ============================================================================
MACHINE_NAME="precision-t5810"
MACHINE_LABEL="Dell Precision T5810"
HOSTNAME_VALUE="precision-t5810"
TIMEZONE="America/New_York"
CONFIGS="/root/${MACHINE_NAME}-configs"
read -rp "Username for desktop user [chris]: " USERNAME
USERNAME="${USERNAME:-chris}"

# CPU / Build
KERNEL_JOBS="-j$(nproc)"       # 44 threads on 22C/44T Xeon
KERNEL_TIME_EST="5-10 minutes on 22C/44T Xeon"

# Network type: wired-only (no WiFi)
HAS_WIFI=0
HAS_BLUETOOTH=0  # No BT hardware detected

# Laptop features (0 = desktop/tower)
IS_LAPTOP=0

# GPU: 2x NVIDIA GTX 1050 Ti (GP107) — proprietary nvidia-drivers
HAS_NVIDIA=1
HAS_INTEL_GPU=0   # Xeon E5 has no iGPU
NVIDIA_DESC="2x GeForce GTX 1050 Ti (GP107)"

# Services profile: workstation (no thermald/tlp/bluetooth)
# thermald is for laptops; T5810 has BIOS-level fan control via dell_smm_hwmon
# tlp is for battery power management — not applicable to desktop
# ============================================================================

set -euo pipefail

echo "============================================================"
echo "=== $MACHINE_LABEL One-Shot Chroot Install ==="
echo "============================================================"
echo ""
echo "  CPU:  Xeon E5-2699 v4 (22C/44T)"
echo "  RAM:  256GB DDR4 ECC"
echo "  GPU:  $NVIDIA_DESC"
echo "  Net:  Intel I217-LM (wired only)"
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

echo "[1.1] Syncing portage tree..."
emerge-webrsync
emerge --sync

echo "[1.2] Setting profile (desktop for XFCE/LightDM)..."
eselect profile set default/linux/amd64/23.0/desktop

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

echo "[2.2] Selecting kernel..."
eselect kernel list
eselect kernel set 1
echo "  Kernel symlink:"
ls -l /usr/src/linux

echo "[2.3] Configuring kernel..."
cd /usr/src/linux

# Start from defconfig, then apply machine customizations
make defconfig
bash "$CONFIGS/kernel_config.sh"

echo "[2.4] Resolving kernel config dependencies..."
make olddefconfig

echo ""
echo "=== Kernel config applied. Review with menuconfig? ==="
read -p "Open menuconfig? (y/N): " do_menuconfig
if [[ "$do_menuconfig" == "y" || "$do_menuconfig" == "Y" ]]; then
    make menuconfig
fi

echo "[2.5] Building kernel (make $KERNEL_JOBS)..."
echo "  Estimated: $KERNEL_TIME_EST"
make $KERNEL_JOBS

echo "[2.6] Installing kernel modules..."
make modules_install

echo "[2.7] Installing kernel..."
make install

echo "[2.8] Verifying kernel installation..."
ls -la /boot/vmlinuz-* /boot/config-* /boot/System.map-* 2>/dev/null || echo "  [WARN] Some boot files may be missing — check /boot/"

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

# Dell UEFI quirk: many Dell BIOSes only boot from the fallback path
# EFI/Boot/bootx64.efi, ignoring custom bootloader-id entries.
echo "[3.2.1] Copying GRUB to EFI fallback path (Dell UEFI quirk)..."
mkdir -p /boot/efi/EFI/Boot
cp /boot/efi/EFI/Gentoo/grubx64.efi /boot/efi/EFI/Boot/bootx64.efi

echo "[3.3] Configuring GRUB defaults..."
# T5810: standard GRUB, no special boot params needed
# (no i915, no laptop stuff, NVIDIA doesn't need kernel params for desktop)
cat > /etc/default/grub << 'EOF'
# GRUB defaults - Dell Precision T5810

GRUB_DISTRIBUTOR="Gentoo"
GRUB_DEFAULT=0
GRUB_TIMEOUT=5

# Console: standard resolution (no HiDPI)
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep

# Kernel command line
# nvidia-drm.modeset=1: enable KMS for NVIDIA (required for Wayland/compositing)
GRUB_CMDLINE_LINUX_DEFAULT="nvidia-drm.modeset=1"
GRUB_CMDLINE_LINUX=""

# Terminal
GRUB_TERMINAL_INPUT="console"
GRUB_TERMINAL_OUTPUT="gfxterm"
EOF
echo "  [OK] /etc/default/grub installed"

echo "[3.4] Generating GRUB config..."
grub-mkconfig -o /boot/grub/grub.cfg

echo "[3.5] Verifying GRUB sees kernel..."
grep menuentry /boot/grub/grub.cfg || echo "  [WARN] No menuentry found in grub.cfg!"

echo ""
echo "[OK] Phase 3 complete."
echo ""

# ============================================================================
# PHASE 4: SYSTEM CONFIGURATION
# ============================================================================
echo "=========================================="
echo "=== PHASE 4: System Configuration ==="
echo "=========================================="

echo "[4.1] Setting timezone to ${TIMEZONE}..."
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime

echo "[4.2] Configuring locale..."
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update && source /etc/profile

echo "[4.3] Setting hostname..."
echo "$HOSTNAME_VALUE" > /etc/hostname
# Also set in conf.d/hostname to override DHCP-assigned hostname (OpenRC)
sed -i "s/^hostname=.*/hostname=\"${HOSTNAME_VALUE}\"/" /etc/conf.d/hostname

cat > /etc/hosts << EOF
127.0.0.1       localhost
::1             localhost
127.0.1.1       ${HOSTNAME_VALUE}.localdomain ${HOSTNAME_VALUE}
EOF

echo ""
echo "[4.4] Set root password:"
passwd

groupadd -f plugdev

echo "[4.5] Creating user '$USERNAME'..."
useradd -m -G wheel,audio,video,usb,input,plugdev -s /bin/bash "$USERNAME"
echo ""
echo "Set password for user '$USERNAME':"
passwd "$USERNAME"

echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

echo ""
echo "[OK] Phase 4 complete."
echo ""

# ============================================================================
# PHASE 5: NETWORKING
# ============================================================================
echo "=========================================="
echo "=== PHASE 5: Networking ==="
echo "=========================================="

if [[ $HAS_WIFI -eq 1 ]]; then
    echo "[5.1] Installing networking packages (WiFi + wired)..."
    emerge --verbose net-wireless/wpa_supplicant \
        net-misc/networkmanager \
        net-misc/dhcpcd \
        gnome-extra/nm-applet \
        net-wireless/wireless-regdb

    echo "[5.2] Verifying wpa_supplicant dbus support..."
    emerge -pv net-wireless/wpa_supplicant 2>/dev/null | grep dbus || echo "  WARNING: Check dbus USE flag!"
else
    echo "[5.1] Installing networking packages (wired only — no WiFi on this machine)..."
    emerge --verbose net-misc/networkmanager \
        net-misc/dhcpcd \
        gnome-extra/nm-applet
fi

echo "[5.3] Enabling NetworkManager..."
rc-update add NetworkManager default

echo ""
echo "[OK] Phase 5 complete — Ethernet will work on first boot (Intel I217-LM / e1000e)."
echo ""

# ============================================================================
# PHASE 6: ALL REMAINING PACKAGES + NVIDIA
# ============================================================================
echo "=========================================="
echo "=== PHASE 6: All Packages + NVIDIA ==="
echo "=========================================="

echo "[6.1] Installing world file..."
if [[ -f "$CONFIGS/world" ]]; then
    cp "$CONFIGS/world" /var/lib/portage/world
    echo "  [OK] World file installed."
else
    echo "  [WARN] No world file found — using stage3 default."
fi

echo "[6.2] Installing all packages (includes nvidia-drivers)..."
echo "  This will take 1-3 hours on 22C/44T. Includes:"
echo "    XFCE, LightDM, PipeWire, NVIDIA, browsers, dev tools, etc."
echo ""
emerge --verbose --update --deep --newuse @world

echo ""
echo "[OK] Phase 6 complete."
echo ""
echo "--- Merging updated config files ---"
echo "  If dispatch-conf shows diffs, press 'u' to use the new version"
echo "  or 'z' to zap (keep current). Most should be auto-merged."
dispatch-conf || echo "  [WARN] dispatch-conf failed or not available — run manually after install"
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
echo "  [OK] /var/tmp/portage (128GB tmpfs on boot)"

echo "[7.2] Setting up ccache..."
mkdir -p /var/cache/ccache
chown root:portage /var/cache/ccache
chmod 2775 /var/cache/ccache

echo "[7.3] No package.env/notmpfs needed — 128GB tmpfs handles any package."

echo ""
echo "[OK] Phase 7 complete."
echo ""

# ============================================================================
# PHASE 8: OPENRC SERVICES
# ============================================================================
echo "=========================================="
echo "=== PHASE 8: OpenRC Services ==="
echo "=========================================="

echo "[8.1] Enabling services..."

# Core services (all machines)
rc-update add dbus default
rc-update add elogind boot
rc-update add acpid default
rc-update add cronie default
rc-update add display-manager default
rc-update add sshd default
rc-update add metalog default
rc-update add local default
rc-update add netmount default
rc-update add zram-init default
rc-update add alsasound boot

# Conditional services
if [[ $HAS_BLUETOOTH -eq 1 ]]; then
    rc-update add bluetooth default
fi
rc-update add chronyd default

if [[ $IS_LAPTOP -eq 1 ]]; then
    # Laptop-only services
    rc-update add thermald default 2>/dev/null || echo "  [INFO] thermald not installed (desktop)"
    rc-update add tlp default 2>/dev/null || echo "  [INFO] tlp not installed (desktop)"
fi

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
ls /usr/share/xsessions/ 2>/dev/null || echo "  [WARN] No xsessions directory!"
grep -E "^Exec=|^DesktopNames=" /usr/share/xsessions/xfce.desktop 2>/dev/null || echo "  WARNING: xfce.desktop not found!"

echo "[9.2] Installing LightDM config..."
if [[ -f "$CONFIGS/lightdm.conf" ]]; then
    cp "$CONFIGS/lightdm.conf" /etc/lightdm/lightdm.conf
    echo "  [OK] lightdm.conf installed"
else
    # Standard config — no HiDPI on T5810 (standard monitors)
    sed -i 's/^#user-session=.*/user-session=xfce/' /etc/lightdm/lightdm.conf 2>/dev/null || true
    sed -i 's/^#session-wrapper=.*/session-wrapper=\/etc\/lightdm\/Xsession/' /etc/lightdm/lightdm.conf 2>/dev/null || true
    echo "  [OK] LightDM configured (standard DPI)"
fi

echo "[9.3] Setting display manager..."
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

echo "[10.2] PipeWire autostart configured via gentoo-pipewire-launcher"
echo "  Will be set up by restore-desktop.sh after first login"
echo "  Audio: C610/X99 HDA (Realtek ALC3220) + 2x NVIDIA GP107 HDMI"

echo ""
echo "[OK] Phase 10 complete."
echo ""

# ============================================================================
# PHASE 11: NVIDIA + MACHINE-SPECIFIC HARDWARE
# ============================================================================
echo "=========================================="
echo "=== PHASE 11: NVIDIA + Hardware ($MACHINE_LABEL) ==="
echo "=========================================="

# --- 11.1: NVIDIA Configuration ---
if [[ $HAS_NVIDIA -eq 1 ]]; then
    echo "[11.1] Configuring NVIDIA ($NVIDIA_DESC)..."

    # Module rebuild hook — auto emerge @module-rebuild on kernel update
    if [[ -f "$CONFIGS/99-module-rebuild.install" ]]; then
        mkdir -p /etc/kernel/postinst.d
        cp "$CONFIGS/99-module-rebuild.install" /etc/kernel/postinst.d/99-module-rebuild.install
        chmod +x /etc/kernel/postinst.d/99-module-rebuild.install
        echo "  [OK] 99-module-rebuild.install -> /etc/kernel/postinst.d/"
    fi

    # NVIDIA modprobe config — desktop workstation (no Optimus/PRIME)
    cat > /etc/modprobe.d/nvidia.conf << 'EOF'
# NVIDIA dual GTX 1050 Ti (GP107) — desktop workstation
# Enable DRM KMS for NVIDIA (needed for compositing, Wayland compatibility)
options nvidia-drm modeset=1
# Blacklist nouveau (proprietary nvidia-drivers used)
blacklist nouveau
EOF
    echo "  [OK] /etc/modprobe.d/nvidia.conf (desktop, no Optimus)"

    # No prime-run needed — desktop with discrete NVIDIA only (no iGPU)
    echo "  [INFO] No prime-run (desktop, no Intel iGPU, both GPUs are NVIDIA)"
fi

# --- 11.2: zram Configuration ---
echo "[11.2] Configuring zram-init..."
if [[ -f "$CONFIGS/zram-init.conf" ]]; then
    cp "$CONFIGS/zram-init.conf" /etc/conf.d/zram-init
    echo "  [OK] zram-init configured (16GB zstd, 22 streams)"
else
    cat > /etc/conf.d/zram-init << 'EOF'
# Precision T5810: 256GB RAM, zram is safety net only
load_on_start="no"
unload_on_stop="no"
num_devices="1"
type0="swap"
size0="16384"
algo0="zstd"
maxs0="22"
labl0="zram_swap"
EOF
    echo "  [OK] zram-init configured (inline)"
fi

# --- 11.3: Sysctl Performance Tuning ---
echo "[11.3] Installing sysctl tuning..."
if [[ -f "$CONFIGS/sysctl-performance.conf" ]]; then
    cp "$CONFIGS/sysctl-performance.conf" /etc/sysctl.d/99-${MACHINE_NAME}-performance.conf
    echo "  [OK] /etc/sysctl.d/99-${MACHINE_NAME}-performance.conf"
    echo "       vm.swappiness=5, pid_max=131072, 128GB tmpfs, inotify tuning"
fi

# --- 11.4: Verify Firmware ---
echo "[11.4] Verifying firmware files..."
# NVIDIA GP107 firmware (both GPUs use the same firmware)
ls /lib/firmware/nvidia/gp107/ 2>/dev/null && echo "  [OK] NVIDIA GP107 firmware directory" || echo "  [FAIL] NVIDIA GP107 firmware!"
# Intel microcode (Broadwell-EP)
ls /lib/firmware/intel-ucode/ 2>/dev/null && echo "  [OK] Intel microcode directory" || echo "  [WARN] Intel microcode dir"
# No i915 firmware needed (no iGPU)
# No WiFi firmware needed (wired only)

echo "[11.5] Installing emoji fontconfig..."
cat > /etc/fonts/local.conf << 'FONTEOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <!-- Use Noto Color Emoji for emoji glyphs -->
  <alias>
    <family>serif</family>
    <prefer><family>Noto Color Emoji</family></prefer>
  </alias>
  <alias>
    <family>sans-serif</family>
    <prefer><family>Noto Color Emoji</family></prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer><family>Noto Color Emoji</family></prefer>
  </alias>
</fontconfig>
FONTEOF
fc-cache -f
echo "  [OK] Noto Color Emoji fontconfig installed"

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
echo "  Note: 128GB tmpfs for portage — no disk fallback needed."

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
WARN=0

# --- Kernel ---
ls /boot/vmlinuz-* &>/dev/null && echo "[OK] Kernel installed" || { echo "[FAIL] No kernel!"; FAIL=$((FAIL+1)); }

# --- GRUB ---
grep -q menuentry /boot/grub/grub.cfg 2>/dev/null && echo "[OK] GRUB configured" || { echo "[FAIL] GRUB!"; FAIL=$((FAIL+1)); }
grep -q "nvidia-drm.modeset=1" /boot/grub/grub.cfg 2>/dev/null && echo "[OK] NVIDIA KMS boot param" || { echo "[WARN] Missing nvidia-drm.modeset=1"; WARN=$((WARN+1)); }

# --- fstab ---
UUID_COUNT=$(grep -c UUID /etc/fstab || true)
echo "[INFO] $UUID_COUNT UUID entries in fstab"
[[ $UUID_COUNT -ge 3 ]] || { echo "[FAIL] fstab missing entries!"; FAIL=$((FAIL+1)); }
grep -q "tmpfs.*portage.*128G" /etc/fstab && echo "[OK] 128GB portage tmpfs in fstab" || { echo "[WARN] Check portage tmpfs size"; WARN=$((WARN+1)); }

# --- Networking ---
if [[ $HAS_WIFI -eq 1 ]]; then
    qlist -I net-wireless/wpa_supplicant &>/dev/null && echo "[OK] wpa_supplicant installed" || { echo "[FAIL] wpa_supplicant!"; FAIL=$((FAIL+1)); }
fi
qlist -I net-misc/networkmanager &>/dev/null && echo "[OK] NetworkManager installed" || { echo "[FAIL] NetworkManager!"; FAIL=$((FAIL+1)); }

# --- NVIDIA ---
if [[ $HAS_NVIDIA -eq 1 ]]; then
    qlist -I x11-drivers/nvidia-drivers &>/dev/null && echo "[OK] nvidia-drivers installed" || { echo "[FAIL] nvidia-drivers!"; FAIL=$((FAIL+1)); }
    [[ -f /etc/modprobe.d/nvidia.conf ]] && echo "[OK] nvidia modprobe config" || { echo "[WARN] nvidia.conf missing"; WARN=$((WARN+1)); }
fi

# --- LightDM ---
grep -q "user-session=xfce" /etc/lightdm/lightdm.conf 2>/dev/null && echo "[OK] LightDM session=xfce" || { echo "[FAIL] LightDM session!"; FAIL=$((FAIL+1)); }
ls /usr/share/xsessions/xfce.desktop &>/dev/null && echo "[OK] xfce.desktop exists" || { echo "[FAIL] xfce.desktop!"; FAIL=$((FAIL+1)); }

# --- Services ---
REQUIRED_SVCS="dbus NetworkManager display-manager acpid sshd metalog local netmount"
for svc in $REQUIRED_SVCS; do
    rc-update show default 2>/dev/null | grep -q "$svc" && echo "[OK] $svc enabled" || { echo "[FAIL] $svc NOT enabled!"; FAIL=$((FAIL+1)); }
done
rc-update show boot 2>/dev/null | grep -q elogind && echo "[OK] elogind enabled" || { echo "[FAIL] elogind NOT enabled!"; FAIL=$((FAIL+1)); }
rc-update show default 2>/dev/null | grep -q zram && echo "[OK] zram-init enabled" || { echo "[FAIL] zram-init NOT enabled!"; FAIL=$((FAIL+1)); }
rc-update show boot 2>/dev/null | grep -q alsasound && echo "[OK] alsasound enabled" || { echo "[FAIL] alsasound NOT enabled!"; FAIL=$((FAIL+1)); }

# Conditional service checks
if [[ $HAS_BLUETOOTH -eq 1 ]]; then
    rc-update show default 2>/dev/null | grep -q bluetooth && echo "[OK] bluetooth enabled" || { echo "[FAIL] bluetooth NOT enabled!"; FAIL=$((FAIL+1)); }
fi

# --- PipeWire ---
qlist -I media-video/pipewire &>/dev/null && echo "[OK] PipeWire" || { echo "[FAIL] PipeWire!"; FAIL=$((FAIL+1)); }

# --- User ---
id "$USERNAME" &>/dev/null && echo "[OK] User $USERNAME exists" || { echo "[FAIL] No user $USERNAME!"; FAIL=$((FAIL+1)); }
groups "$USERNAME" 2>/dev/null | grep -q video && echo "[OK] $USERNAME in video group" || { echo "[FAIL] $USERNAME not in video group!"; FAIL=$((FAIL+1)); }

# --- Sudo ---
grep -q "^%wheel" /etc/sudoers 2>/dev/null && echo "[OK] sudo for wheel group" || { echo "[FAIL] sudo not configured!"; FAIL=$((FAIL+1)); }

# --- Display manager conf ---
grep -q 'DISPLAYMANAGER="lightdm"' /etc/conf.d/display-manager 2>/dev/null && echo "[OK] display-manager=lightdm" || { echo "[FAIL] DISPLAYMANAGER not set!"; FAIL=$((FAIL+1)); }

# --- Firmware ---
if [[ $HAS_NVIDIA -eq 1 ]]; then
    ls /lib/firmware/nvidia/gp107/ &>/dev/null && echo "[OK] NVIDIA GP107 firmware" || { echo "[FAIL] NVIDIA firmware!"; FAIL=$((FAIL+1)); }
fi

# --- ccache ---
[[ -d /var/cache/ccache ]] && echo "[OK] ccache directory" || { echo "[WARN] ccache directory missing"; WARN=$((WARN+1)); }

# --- Hostname ---
[[ "$(cat /etc/hostname)" == "$HOSTNAME_VALUE" ]] && echo "[OK] hostname=$HOSTNAME_VALUE" || { echo "[WARN] hostname mismatch"; WARN=$((WARN+1)); }

echo ""
echo "=========================================="
if [[ $FAIL -eq 0 ]]; then
    echo "=== ALL CHECKS PASSED ($WARN warnings) ==="
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
    echo "  1. Verify Ethernet: ip addr (should show Intel I217-LM)"
    echo "  2. nvidia-smi (verify both GTX 1050 Ti GPUs)"
    echo "  3. xrandr (verify display)"
    echo "  4. pactl info | grep 'Server Name' (PipeWire)"
    echo "  5. swapon --show (verify 16GB zram)"
    echo "  6. edac-util -s (verify ECC memory reporting)"
    echo "  7. Restore desktop: bash ~/gentoo-machines/shared/restore-desktop.sh"
else
    echo "=== $FAIL CHECKS FAILED ($WARN warnings) ==="
    echo "=========================================="
    echo ""
    echo "FIX THE FAILURES ABOVE BEFORE REBOOTING!"
    echo "Do NOT exit the chroot until all checks pass."
fi
