#!/bin/bash
# ============================================================================
# gentoo_install_part3_chroot.sh - ONE-SHOT chroot install
# Beelink MINI S (N5095A) - Run INSIDE the chroot
# ============================================================================
# Cloned from surface-pro-6 minus all Surface/IPTS/HiDPI/idle-bridge bits.
# Desktop mini-PC: no battery handling, no TLP, no HiDPI lightdm.
#
# USAGE:
#   sudo chroot /mnt/gentoo /bin/bash
#   source /etc/profile
#   export PS1="(chroot) $PS1"
#   bash /root/gentoo_install_part3_chroot.sh
# ============================================================================

# NOTE: no `-u` (nounset) — /etc/profile.d/debuginfod.sh and others reference
# unbound vars, which would abort the script the instant we source /etc/profile.
set -eo pipefail

MACHINE="beelink-minis-n5095"
HOSTNAME_SHORT="beelink-minis"
CONFIGS="/root/${MACHINE}-configs"
TIMEZONE="America/New_York"
USERNAME="chris"

echo "============================================================"
echo "=== Beelink MINI S (N5095A) One-Shot Chroot Install ==="
echo "============================================================"
echo ""

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

echo "[1.2] Setting profile..."
eselect profile list
eselect profile set default/linux/amd64/23.0

echo "[1.3] Updating @world with USE flags..."
echo "  This may take 10-30 minutes on this CPU..."
emerge --verbose --update --deep --newuse @world

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
ls -l /usr/src/linux

echo "[2.3] Configuring kernel..."
cd /usr/src/linux

# Start from SP6 base (closest machine profile in repo)
if [[ -f "$CONFIGS/base.config" ]]; then
    cp "$CONFIGS/base.config" .config
    echo "  [OK] Base config copied from surface-pro-6"
else
    echo "  [WARN] No base config — using defconfig"
    make defconfig
fi

bash "$CONFIGS/kernel_config.sh"

echo "[2.4] Running kconfig-lint on our script (now that /usr/src/linux exists)..."
REPO=""
for candidate in /home/liveuser/ai/gentoo-machines /home/liveuser/gentoo-machines; do
    [[ -d "$candidate" ]] && REPO="$candidate" && break
done
if [[ -n "$REPO" && -x "$REPO/tools/kconfig-lint.sh" ]]; then
    "$REPO/tools/kconfig-lint.sh" "$REPO/machines/$MACHINE/kernel_config.sh" /usr/src/linux || \
        echo "  [WARN] kconfig-lint reported issues — review above"
else
    echo "  [INFO] kconfig-lint.sh not available, skipping"
fi

echo "[2.5] Resolving kernel config dependencies..."
make olddefconfig

echo ""
read -p "Open menuconfig for review? (y/N): " do_menuconfig
if [[ "$do_menuconfig" == "y" || "$do_menuconfig" == "Y" ]]; then
    make menuconfig
fi

echo "[2.6] Building kernel (make -j2)..."
echo "  This will take 30-60 minutes on Tremont 4C/4T..."
make -j2

echo "[2.7] Installing kernel modules..."
make modules_install

echo "[2.8] Installing kernel..."
make install

echo "[2.9] Verifying kernel installation..."
ls -la /boot/vmlinuz-* /boot/config-* /boot/System.map-*

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

# UEFI fallback path — AMI BIOS on this Beelink may only boot EFI/Boot/bootx64.efi
echo "[3.2.1] Copying GRUB to EFI fallback path..."
mkdir -p /boot/efi/EFI/Boot
cp /boot/efi/EFI/Gentoo/grubx64.efi /boot/efi/EFI/Boot/bootx64.efi

echo "[3.3] Installing GRUB defaults..."
if [[ -f "$CONFIGS/grub" ]]; then
    cp "$CONFIGS/grub" /etc/default/grub
    echo "  [OK] /etc/default/grub installed"
else
    echo "  [WARN] No grub defaults found"
fi

echo "[3.4] Generating GRUB config..."
grub-mkconfig -o /boot/grub/grub.cfg

echo "[3.5] Verifying GRUB sees kernel..."
grep menuentry /boot/grub/grub.cfg

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
echo "$HOSTNAME_SHORT" > /etc/hostname

cat > /etc/hosts << EOF
127.0.0.1       localhost
::1             localhost
127.0.1.1       ${HOSTNAME_SHORT}.localdomain ${HOSTNAME_SHORT}
EOF

echo ""
echo "[4.4] Set root password:"
passwd

groupadd -f plugdev

echo "[4.5] Creating user '${USERNAME}'..."
useradd -m -G wheel,audio,video,usb,input,plugdev -s /bin/bash "$USERNAME"
echo ""
echo "Set password for user '${USERNAME}':"
passwd "$USERNAME"

echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

echo "[4.6] Relaxing pam_faillock (home machine: 10 attempts, 5 min lockout)..."
sed -i 's/pam_faillock.so preauth/pam_faillock.so preauth deny=10 unlock_time=300/' /etc/pam.d/system-auth
sed -i 's/pam_faillock.so authfail/pam_faillock.so authfail deny=10 unlock_time=300/' /etc/pam.d/system-auth
echo "  [OK] pam_faillock: deny=10, unlock_time=300"

echo "[OK] Phase 4 complete."
echo ""

# ============================================================================
# PHASE 5: NETWORKING (CRITICAL)
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

echo "[5.2] Verifying wpa_supplicant dbus support..."
emerge -pv net-wireless/wpa_supplicant | grep dbus || echo "  WARNING: Check dbus USE flag!"

echo "[5.3] Enabling NetworkManager..."
rc-update add NetworkManager default

echo "[OK] Phase 5 complete — WiFi + Ethernet will work on first boot."
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
echo "  This will take 2-4 hours on Tremont. Includes XFCE, browsers, dev tools..."
echo "  (Large packages use disk fallback via package.env to avoid tmpfs OOM)"
echo ""
emerge --verbose --update --deep --newuse @world

echo ""
echo "--- Merging updated config files ---"
dispatch-conf || echo "  [WARN] dispatch-conf failed — run manually after install"
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

echo "[7.2] Verifying package.env..."
cat /etc/portage/package.env 2>/dev/null || echo "  [WARN] package.env not found!"
echo ""
cat /etc/portage/env/notmpfs.conf 2>/dev/null || echo "  [WARN] notmpfs.conf not found!"

echo "[OK] Phase 7 complete."
echo ""

# ============================================================================
# PHASE 8: OPENRC SERVICES (desktop mini-PC — no TLP, no low-battery)
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
rc-update add display-manager default
rc-update add sshd default

echo "[8.2] Enabling SSH pubkey authentication..."
sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
echo "  [OK] PubkeyAuthentication enabled"
rc-update add metalog default
rc-update add local default
rc-update add netmount default
rc-update add zram-init boot
rc-update add alsasound boot
rc-update add chronyd default
rc-update add cronie default

echo ""
echo "[8.3] Current runlevels:"
echo "  Default:"
rc-update show default
echo "  Boot:"
rc-update show boot

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
grep -E "^Exec=|^DesktopNames=" /usr/share/xsessions/xfce.desktop 2>/dev/null || \
    echo "  WARNING: xfce.desktop not found!"

echo "[9.2] Installing LightDM config..."
if [[ -f "$CONFIGS/lightdm.conf" ]]; then
    cp "$CONFIGS/lightdm.conf" /etc/lightdm/lightdm.conf
    echo "  [OK] shared lightdm.conf installed"
else
    sed -i 's/^#user-session=.*/user-session=xfce/' /etc/lightdm/lightdm.conf 2>/dev/null || true
    sed -i 's|^#session-wrapper=.*|session-wrapper=/etc/lightdm/Xsession|' /etc/lightdm/lightdm.conf 2>/dev/null || true
fi

echo "[9.3] Verifying LightDM..."
grep -q "user-session=xfce" /etc/lightdm/lightdm.conf && echo "  [OK] user-session=xfce" || echo "  [FAIL] Check user-session!"
grep -q "session-wrapper=/etc/lightdm/Xsession" /etc/lightdm/lightdm.conf && echo "  [OK] session-wrapper" || echo "  [WARN] Check session-wrapper"
ls -la /etc/lightdm/Xsession 2>/dev/null && echo "  [OK] Xsession exists" || echo "  [FAIL] Xsession missing!"

echo "[9.4] Setting display manager..."
sed -i 's/DISPLAYMANAGER=".*"/DISPLAYMANAGER="lightdm"/' /etc/conf.d/display-manager 2>/dev/null || \
    echo 'DISPLAYMANAGER="lightdm"' > /etc/conf.d/display-manager

echo "[OK] Phase 9 complete."
echo ""

# ============================================================================
# PHASE 10: AUDIO (PipeWire)
# ============================================================================
echo "=========================================="
echo "=== PHASE 10: PipeWire Audio ==="
echo "=========================================="

echo "[10.1] Verifying PipeWire installation..."
qlist -I media-video/pipewire && echo "  [OK] PipeWire" || echo "  [FAIL] PipeWire!"
qlist -I media-video/wireplumber && echo "  [OK] WirePlumber" || echo "  [FAIL] WirePlumber!"
qlist -I xfce-extra/xfce4-pulseaudio-plugin && echo "  [OK] xfce4-pulseaudio-plugin" || echo "  [WARN] Volume plugin missing"

echo "[10.2] PipeWire autostart via gentoo-pipewire-launcher (configured by restore-desktop.sh)"

echo "[OK] Phase 10 complete."
echo ""

# ============================================================================
# PHASE 11: MACHINE-SPECIFIC HARDWARE
# ============================================================================
echo "=========================================="
echo "=== PHASE 11: Beelink Hardware ==="
echo "=========================================="

echo "[11.1] Configuring always-on (no sleep/suspend)..."
mkdir -p /etc/elogind/logind.conf.d
cat > /etc/elogind/logind.conf.d/always-on.conf << 'ALWAYSON'
[Login]
HandleSuspendKey=ignore
HandleSuspendKeyLongPress=ignore
HandleHibernateKey=ignore
HandleHibernateKeyLongPress=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
ALWAYSON
echo "  [OK] elogind always-on drop-in installed"

echo "[11.2] Configuring zram-init..."
cp "$CONFIGS/zram-init.conf" /etc/conf.d/zram-init
echo "  [OK] zram-init configured (4GB zstd swap)"

echo "[11.3] Installing weekly fstrim cron job..."
mkdir -p /etc/cron.weekly
cp "$SHARED/fstrim-weekly" /etc/cron.weekly/fstrim
chmod 755 /etc/cron.weekly/fstrim
echo "  [OK] fstrim weekly cron job installed"

echo "[11.4] Installing sysctl tuning..."
if [[ -f /etc/sysctl.d/99-beelink-minis-performance.conf ]]; then
    echo "  [OK] Already installed by part2"
else
    cp "$CONFIGS/sysctl-performance.conf" /etc/sysctl.d/99-beelink-minis-performance.conf 2>/dev/null || \
        echo "  [WARN] sysctl-performance.conf not found"
fi

echo "[11.5] Verifying firmware files..."
FW_FAIL=0
ls /lib/firmware/iwlwifi-7265D-*.ucode 2>/dev/null | head -1 \
    && echo "  [OK] iwlwifi 7265D firmware (for 3165 card)" \
    || { echo "  [FAIL] iwlwifi-7265D firmware missing!"; FW_FAIL=$((FW_FAIL+1)); }
ls /lib/firmware/i915/icl_dmc_ver1_*.bin 2>/dev/null | head -1 \
    && echo "  [OK] i915 ICL DMC firmware (JSL uses ICL binary)" \
    || { echo "  [FAIL] i915 ICL DMC firmware missing!"; FW_FAIL=$((FW_FAIL+1)); }
ls /lib/firmware/regulatory.db 2>/dev/null \
    && echo "  [OK] regulatory.db" \
    || echo "  [WARN] regulatory.db missing (wireless-regdb not installed?)"
echo "  [INFO] Intel BT (8087:0a2a) has ROM firmware — no file needed"

echo "[11.6] Installing emoji fontconfig..."
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

echo "[11.7] Identifying HDA audio codec (informational)..."
cat /proc/asound/card0/codec#0 2>/dev/null | head -3 || \
    echo "  [INFO] No audio codec info yet — check on first boot"

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
echo "  [OK] fstab was generated by part2 with actual UUIDs."

echo "[OK] Phase 12 complete."
echo ""

# ============================================================================
# PHASE 13: PRE-REBOOT VERIFICATION
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
ls /boot/efi/EFI/Boot/bootx64.efi &>/dev/null && echo "[OK] EFI fallback copied" || echo "[WARN] No EFI fallback"

# fstab
UUID_COUNT=$(grep -c UUID /etc/fstab || true)
echo "[INFO] $UUID_COUNT UUID entries in fstab"
[[ $UUID_COUNT -ge 3 ]] || { echo "[FAIL] fstab missing entries!"; FAIL=$((FAIL+1)); }

# Networking
qlist -I net-wireless/wpa_supplicant &>/dev/null && echo "[OK] wpa_supplicant" || { echo "[FAIL] wpa_supplicant!"; FAIL=$((FAIL+1)); }
qlist -I net-misc/networkmanager &>/dev/null && echo "[OK] NetworkManager" || { echo "[FAIL] NetworkManager!"; FAIL=$((FAIL+1)); }

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
qlist -I www-client/firefox-bin &>/dev/null && echo "[OK] Firefox" || echo "[WARN] No Firefox"
qlist -I www-client/google-chrome &>/dev/null && echo "[OK] Chrome" || echo "[WARN] No Chrome"

# PipeWire
qlist -I media-video/pipewire &>/dev/null && echo "[OK] PipeWire" || { echo "[FAIL] PipeWire!"; FAIL=$((FAIL+1)); }

# TPM tools
qlist -I app-crypt/tpm2-tools &>/dev/null && echo "[OK] tpm2-tools" || echo "[WARN] No tpm2-tools"

# User
id "$USERNAME" &>/dev/null && echo "[OK] User $USERNAME exists" || { echo "[FAIL] No user!"; FAIL=$((FAIL+1)); }
groups "$USERNAME" 2>/dev/null | grep -q video && echo "[OK] $USERNAME in video group" || { echo "[FAIL] $USERNAME not in video!"; FAIL=$((FAIL+1)); }

# Sudo
grep -q "^%wheel" /etc/sudoers 2>/dev/null && echo "[OK] sudo for wheel group" || { echo "[FAIL] sudo!"; FAIL=$((FAIL+1)); }

# Display manager conf
grep -q 'DISPLAYMANAGER="lightdm"' /etc/conf.d/display-manager 2>/dev/null && echo "[OK] display-manager=lightdm" || { echo "[FAIL] DISPLAYMANAGER!"; FAIL=$((FAIL+1)); }

# Firmware (from earlier check)
[[ $FW_FAIL -eq 0 ]] && echo "[OK] Required firmware present" || { echo "[FAIL] $FW_FAIL firmware file(s) missing!"; FAIL=$((FAIL+FW_FAIL)); }

# Microcode (CPU needs newer microcode — SRBDS flagged on live env)
qlist -I sys-firmware/intel-microcode &>/dev/null && echo "[OK] intel-microcode installed" || { echo "[FAIL] intel-microcode!"; FAIL=$((FAIL+1)); }

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
    echo "  1. Connect WiFi if needed: nmtui"
    echo "  2. Verify audio: pactl info | grep 'Server Name'"
    echo "  3. Verify HDA codec: cat /proc/asound/card0/codec#0 | head"
    echo "  4. Verify zram: swapon --show"
    echo "  5. Verify IOMMU: dmesg | grep -i 'DMAR\|IOMMU'"
    echo "  6. Verify TPM2: tpm2_getcap properties-fixed | head"
    echo "  7. Check microcode: dmesg | grep -i 'microcode updated'"
    echo "  8. Restore desktop: bash ~/gentoo-machines/shared/restore-desktop.sh"
    echo "  9. Run tools/verify-install.sh for full verification"
else
    echo "=== $FAIL CHECKS FAILED ==="
    echo "=========================================="
    echo ""
    echo "FIX THE FAILURES ABOVE BEFORE REBOOTING!"
    echo "Do NOT exit the chroot until all checks pass."
fi
