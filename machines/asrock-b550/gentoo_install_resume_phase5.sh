#!/bin/bash
# ============================================================================
# Resume script — Phases 5-13 (Phase 4 completed manually)
# ASRock B550 Phantom Gaming-ITX/ax - Run INSIDE the chroot
# ============================================================================
set -eo pipefail

MACHINE_NAME="asrock-b550"
MACHINE_LABEL="ASRock B550 Phantom Gaming-ITX/ax"
CONFIGS="/root/${MACHINE_NAME}-configs"
NVIDIA_DESC="GeForce RTX 3060 Ti (GA104, Ampere)"
NVIDIA_FW_DIR="nvidia/ga104"
HOSTNAME_VALUE="asrock-b550"
HAS_NVIDIA=1

echo "=== Resuming from Phase 5 ==="
echo ""

# ============================================================================
# PHASE 5: NETWORKING
# ============================================================================
echo "=========================================="
echo "=== PHASE 5: Networking ==="
echo "=========================================="

echo "[5.1] Installing networking packages (WiFi + BT + wired)..."
emerge --verbose net-wireless/wpa_supplicant \
    net-misc/networkmanager \
    net-misc/dhcpcd \
    gnome-extra/nm-applet \
    net-wireless/wireless-regdb \
    net-wireless/bluez

echo "[5.2] Verifying wpa_supplicant dbus support..."
emerge -pv net-wireless/wpa_supplicant | grep dbus || echo "  WARNING: Check dbus USE flag!"

echo "[5.3] Enabling NetworkManager..."
rc-update add NetworkManager default

echo ""
echo "[OK] Phase 5 complete."
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
echo "  This will take 1-3 hours on 16C/32T. Includes:"
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
mkdir -p /var/tmp/portage-disk
chown portage:portage /var/tmp/portage-disk
echo "  [OK] /var/tmp/portage (46GB tmpfs on boot)"
echo "  [OK] /var/tmp/portage-disk (disk fallback for large packages)"

echo "[7.2] Setting up ccache..."
mkdir -p /var/cache/ccache
chown root:portage /var/cache/ccache
chmod 2775 /var/cache/ccache

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

rc-update add dbus default
rc-update add elogind boot
rc-update add acpid default
rc-update add display-manager default
rc-update add sshd default
rc-update add metalog default
rc-update add local default
rc-update add netmount default
rc-update add zram-init default
rc-update add alsasound boot
rc-update add bluetooth default

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

echo "[9.2] Configuring LightDM..."
sed -i 's/^#user-session=.*/user-session=xfce/' /etc/lightdm/lightdm.conf 2>/dev/null || true
sed -i 's/^#session-wrapper=.*/session-wrapper=\/etc\/lightdm\/Xsession/' /etc/lightdm/lightdm.conf 2>/dev/null || true
echo "  [OK] LightDM configured (standard DPI)"

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
echo "  Audio: Realtek ALC1220 (HDA) + NVIDIA GA104 HDMI"

echo ""
echo "[OK] Phase 10 complete."
echo ""

# ============================================================================
# PHASE 11: NVIDIA + MACHINE-SPECIFIC HARDWARE
# ============================================================================
echo "=========================================="
echo "=== PHASE 11: NVIDIA + Hardware ($MACHINE_LABEL) ==="
echo "=========================================="

echo "[11.1] Configuring NVIDIA ($NVIDIA_DESC)..."

if [[ -f "$CONFIGS/99-module-rebuild.install" ]]; then
    mkdir -p /etc/kernel/postinst.d
    cp "$CONFIGS/99-module-rebuild.install" /etc/kernel/postinst.d/99-module-rebuild.install
    chmod +x /etc/kernel/postinst.d/99-module-rebuild.install
    echo "  [OK] 99-module-rebuild.install -> /etc/kernel/postinst.d/"
fi

cat > /etc/modprobe.d/nvidia.conf << 'EOF'
# NVIDIA RTX 3060 Ti (GA104, Ampere) — desktop, no iGPU
options nvidia-drm modeset=1
blacklist nouveau
EOF
echo "  [OK] /etc/modprobe.d/nvidia.conf (desktop, no Optimus)"
echo "  [INFO] No prime-run (desktop, AMD CPU = no iGPU)"

echo "[11.2] Configuring zram-init..."
if [[ -f "$CONFIGS/zram-init.conf" ]]; then
    cp "$CONFIGS/zram-init.conf" /etc/conf.d/zram-init
    echo "  [OK] zram-init configured (8GB zstd, 16 streams)"
fi

echo "[11.3] Installing sysctl tuning..."
if [[ -f "$CONFIGS/sysctl-performance.conf" ]]; then
    cp "$CONFIGS/sysctl-performance.conf" /etc/sysctl.d/99-${MACHINE_NAME}-performance.conf
    echo "  [OK] /etc/sysctl.d/99-${MACHINE_NAME}-performance.conf"
fi

echo "[11.4] Verifying firmware files..."
ls /lib/firmware/$NVIDIA_FW_DIR/ 2>/dev/null && echo "  [OK] NVIDIA GA104 firmware directory" || echo "  [FAIL] NVIDIA GA104 firmware!"
ls /lib/firmware/iwlwifi-cc-a0-*.ucode 2>/dev/null && echo "  [OK] iwlwifi firmware" || echo "  [WARN] iwlwifi firmware — check after linux-firmware install"
ls /lib/firmware/intel/ibt-0040-0041.* 2>/dev/null && echo "  [OK] Intel BT firmware" || echo "  [WARN] Intel BT firmware"
ls /lib/firmware/amd-ucode/ 2>/dev/null && echo "  [OK] AMD microcode directory" || echo "  [WARN] AMD microcode"

echo "[11.5] Installing emoji fontconfig..."
cat > /etc/fonts/local.conf << 'FONTEOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
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
# PHASE 12: FSTAB
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
# PHASE 13: VERIFICATION
# ============================================================================
echo "=========================================="
echo "=== PHASE 13: PRE-REBOOT VERIFICATION ==="
echo "=========================================="
echo ""

FAIL=0
WARN=0

ls /boot/vmlinuz-* &>/dev/null && echo "[OK] Kernel installed" || { echo "[FAIL] No kernel!"; FAIL=$((FAIL+1)); }
grep -q menuentry /boot/grub/grub.cfg 2>/dev/null && echo "[OK] GRUB configured" || { echo "[FAIL] GRUB!"; FAIL=$((FAIL+1)); }
grep -q "nvidia-drm.modeset=1" /boot/grub/grub.cfg 2>/dev/null && echo "[OK] NVIDIA KMS boot param" || { echo "[WARN] Missing nvidia-drm.modeset=1"; WARN=$((WARN+1)); }

UUID_COUNT=$(grep -c UUID /etc/fstab || true)
echo "[INFO] $UUID_COUNT UUID entries in fstab"
[[ $UUID_COUNT -ge 3 ]] || { echo "[FAIL] fstab missing entries!"; FAIL=$((FAIL+1)); }
grep -q "tmpfs.*portage.*46G" /etc/fstab && echo "[OK] 46GB portage tmpfs in fstab" || { echo "[WARN] Check portage tmpfs size"; WARN=$((WARN+1)); }

qlist -I net-wireless/wpa_supplicant &>/dev/null && echo "[OK] wpa_supplicant installed" || { echo "[FAIL] wpa_supplicant!"; FAIL=$((FAIL+1)); }
qlist -I net-misc/networkmanager &>/dev/null && echo "[OK] NetworkManager installed" || { echo "[FAIL] NetworkManager!"; FAIL=$((FAIL+1)); }

qlist -I x11-drivers/nvidia-drivers &>/dev/null && echo "[OK] nvidia-drivers installed" || { echo "[FAIL] nvidia-drivers!"; FAIL=$((FAIL+1)); }
[[ -f /etc/modprobe.d/nvidia.conf ]] && echo "[OK] nvidia modprobe config" || { echo "[WARN] nvidia.conf missing"; WARN=$((WARN+1)); }

grep -q "user-session=xfce" /etc/lightdm/lightdm.conf 2>/dev/null && echo "[OK] LightDM session=xfce" || { echo "[FAIL] LightDM session!"; FAIL=$((FAIL+1)); }
ls /usr/share/xsessions/xfce.desktop &>/dev/null && echo "[OK] xfce.desktop exists" || { echo "[FAIL] xfce.desktop!"; FAIL=$((FAIL+1)); }

REQUIRED_SVCS="dbus NetworkManager display-manager acpid sshd metalog local netmount"
for svc in $REQUIRED_SVCS; do
    rc-update show default 2>/dev/null | grep -q "$svc" && echo "[OK] $svc enabled" || { echo "[FAIL] $svc NOT enabled!"; FAIL=$((FAIL+1)); }
done
rc-update show boot 2>/dev/null | grep -q elogind && echo "[OK] elogind enabled" || { echo "[FAIL] elogind NOT enabled!"; FAIL=$((FAIL+1)); }
rc-update show default 2>/dev/null | grep -q zram && echo "[OK] zram-init enabled" || { echo "[FAIL] zram-init NOT enabled!"; FAIL=$((FAIL+1)); }
rc-update show boot 2>/dev/null | grep -q alsasound && echo "[OK] alsasound enabled" || { echo "[FAIL] alsasound NOT enabled!"; FAIL=$((FAIL+1)); }
rc-update show default 2>/dev/null | grep -q bluetooth && echo "[OK] bluetooth enabled" || { echo "[FAIL] bluetooth NOT enabled!"; FAIL=$((FAIL+1)); }

qlist -I media-video/pipewire &>/dev/null && echo "[OK] PipeWire" || { echo "[FAIL] PipeWire!"; FAIL=$((FAIL+1)); }

id chris &>/dev/null && echo "[OK] User chris exists" || { echo "[FAIL] No user chris!"; FAIL=$((FAIL+1)); }
groups chris 2>/dev/null | grep -q video && echo "[OK] chris in video group" || { echo "[FAIL] chris not in video group!"; FAIL=$((FAIL+1)); }
grep -q "^%wheel" /etc/sudoers 2>/dev/null && echo "[OK] sudo for wheel group" || { echo "[FAIL] sudo not configured!"; FAIL=$((FAIL+1)); }
grep -q 'DISPLAYMANAGER="lightdm"' /etc/conf.d/display-manager 2>/dev/null && echo "[OK] display-manager=lightdm" || { echo "[FAIL] DISPLAYMANAGER not set!"; FAIL=$((FAIL+1)); }
ls /lib/firmware/$NVIDIA_FW_DIR/ &>/dev/null && echo "[OK] NVIDIA GA104 firmware" || { echo "[FAIL] NVIDIA firmware!"; FAIL=$((FAIL+1)); }
[[ -d /var/cache/ccache ]] && echo "[OK] ccache directory" || { echo "[WARN] ccache directory missing"; WARN=$((WARN+1)); }
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
    echo "  1. Verify Ethernet: ip addr (should show Intel I225-V / igc)"
    echo "  2. nmcli device wifi list (verify AX200 sees networks)"
    echo "  3. nvidia-smi (verify RTX 3060 Ti)"
    echo "  4. xrandr (verify display)"
    echo "  5. pactl info | grep 'Server Name' (PipeWire)"
    echo "  6. swapon --show (verify 8GB zram)"
    echo "  7. Restore desktop: bash ~/gentoo-machines/shared/restore-desktop.sh"
else
    echo "=== $FAIL CHECKS FAILED ($WARN warnings) ==="
    echo "=========================================="
    echo ""
    echo "FIX THE FAILURES ABOVE BEFORE REBOOTING!"
    echo "Do NOT exit the chroot until all checks pass."
fi
