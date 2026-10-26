#!/bin/bash
# ============================================================================
# gentoo_install_part3_chroot.sh - ONE-SHOT chroot install (with resume)
# ASRock B550 Phantom Gaming-ITX/ax - Run INSIDE the chroot
# ============================================================================
# This script runs all 13 phases in sequence. If interrupted, re-run it —
# completed phases are automatically skipped via /root/install-progress.
#
# USAGE:
#   sudo chroot /mnt/gentoo /bin/bash
#   source /etc/profile
#   export PS1="(chroot) $PS1"
#   bash /root/gentoo_install_part3_chroot.sh
#
# RESUME: Just re-run the same command. Completed phases are skipped.
# RESET:  rm /root/install-progress && re-run to start from scratch.
#
# INTERACTIVE PAUSES:
#   - Phase 2: kernel menuconfig review (y/N)
#   - Phase 4: root password, user password
#   - Phase 6: dispatch-conf (press 'u' to accept)
# ============================================================================
# MACHINE CONFIG — B550-specific values at top, universal logic below
# ============================================================================
MACHINE_NAME="asrock-b550"
MACHINE_LABEL="ASRock B550 Phantom Gaming-ITX/ax"
HOSTNAME_VALUE="asrock-b550"
TIMEZONE="America/New_York"
CONFIGS="/root/${MACHINE_NAME}-configs"
read -rp "Username for desktop user [chris]: " USERNAME
USERNAME="${USERNAME:-chris}"

# CPU / Build
KERNEL_JOBS="-j$(nproc)"       # 32 threads on 16C/32T Ryzen
KERNEL_TIME_EST="5-10 minutes on 16C/32T Ryzen 9 5950X"

# Network type: WiFi + wired
HAS_WIFI=1
HAS_BLUETOOTH=1

# Laptop features (0 = desktop)
IS_LAPTOP=0

# GPU: NVIDIA RTX 3060 Ti (GA104, Ampere) — proprietary nvidia-drivers
HAS_NVIDIA=1
HAS_INTEL_GPU=0   # AMD CPU, no iGPU
NVIDIA_DESC="GeForce RTX 3060 Ti (GA104, Ampere)"
NVIDIA_FW_DIR="nvidia/ga104"

# ============================================================================
# RESUME SUPPORT — track completed phases in a progress file
# ============================================================================
PROGRESS_FILE="/root/install-progress"

phase_done() {
    [[ -f "$PROGRESS_FILE" ]] && grep -qx "$1" "$PROGRESS_FILE" 2>/dev/null
}

mark_done() {
    echo "$1" >> "$PROGRESS_FILE"
}

# Run a phase: skip if already done, execute function, mark complete
# Usage: run_phase <phase_name> <description> <function_name>
run_phase() {
    local phase="$1" desc="$2" func="$3"

    if phase_done "$phase"; then
        echo "[SKIP] $desc (already completed)"
        return 0
    fi

    echo "=========================================="
    echo "=== $desc ==="
    echo "=========================================="

    "$func"

    mark_done "$phase"
    echo ""
    echo "[OK] $desc complete."
    echo ""
}
# ============================================================================

set -eo pipefail

echo "============================================================"
echo "=== $MACHINE_LABEL One-Shot Chroot Install ==="
echo "============================================================"
echo ""
echo "  CPU:  Ryzen 9 5950X (16C/32T, Zen 3)"
echo "  RAM:  64GB DDR4-3200"
echo "  GPU:  $NVIDIA_DESC"
echo "  Net:  Intel I225-V 2.5GbE + AX200 WiFi + BT"
echo ""

if [[ -f "$PROGRESS_FILE" ]]; then
    COMPLETED=$(wc -l < "$PROGRESS_FILE")
    echo "  Resuming: $COMPLETED phase(s) already completed."
    echo "  (Reset with: rm $PROGRESS_FILE)"
    echo ""
fi

# Verify we're in a chroot
if [[ ! -f "$CONFIGS/kernel_config.sh" ]]; then
    echo "ERROR: Config files not found at $CONFIGS"
    echo "Are you inside the chroot? Did part2 run?"
    exit 1
fi

# ============================================================================
# PHASE FUNCTIONS
# ============================================================================

do_phase1_bootstrap() {
    set +u
    source /etc/profile
    set -u
    export PS1="(chroot) ${PS1:-}"

    echo "[1.1] Syncing portage tree..."
    emerge-webrsync
    emerge --sync

    echo "[1.2] Setting profile (desktop for XFCE/LightDM)..."
    eselect profile set default/linux/amd64/23.0/desktop

    echo "[1.3] Updating @world with USE flags..."
    echo "  This may take 10-20 minutes..."
    emerge --verbose --update --deep --newuse @world
}

do_phase2_kernel() {
    echo "[2.1] Installing kernel sources and firmware..."
    emerge --verbose sys-kernel/gentoo-sources \
        sys-kernel/linux-firmware \
        sys-kernel/installkernel

    echo "[2.2] Selecting kernel..."
    eselect kernel list
    eselect kernel set 1
    echo "  Kernel symlink:"
    ls -l /usr/src/linux

    echo "[2.3] Configuring kernel..."
    cd /usr/src/linux

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
}

do_phase3_bootloader() {
    echo "[3.1] Installing GRUB..."
    emerge --verbose sys-boot/grub

    echo "[3.2] Installing GRUB to EFI..."
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo

    echo "[3.2.1] Copying GRUB to EFI fallback path..."
    mkdir -p /boot/efi/EFI/Boot
    cp /boot/efi/EFI/Gentoo/grubx64.efi /boot/efi/EFI/Boot/bootx64.efi

    echo "[3.3] Configuring GRUB defaults..."
    cat > /etc/default/grub << 'EOF'
# GRUB defaults - ASRock B550

GRUB_DISTRIBUTOR="Gentoo"
GRUB_DEFAULT=0
GRUB_TIMEOUT=5

GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep

# nvidia-drm.modeset=1: enable KMS for NVIDIA
GRUB_CMDLINE_LINUX_DEFAULT="nvidia-drm.modeset=1"
GRUB_CMDLINE_LINUX=""

GRUB_TERMINAL_INPUT="console"
GRUB_TERMINAL_OUTPUT="gfxterm"
EOF
    echo "  [OK] /etc/default/grub installed"

    echo "[3.4] Generating GRUB config..."
    grub-mkconfig -o /boot/grub/grub.cfg

    echo "[3.5] Verifying GRUB sees kernel..."
    grep menuentry /boot/grub/grub.cfg || echo "  [WARN] No menuentry found in grub.cfg!"
}

do_phase4_sysconfig() {
    echo "[4.1] Setting timezone to ${TIMEZONE}..."
    ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime

    echo "[4.2] Configuring locale..."
    sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    eselect locale set en_US.utf8
    set +u
    env-update && source /etc/profile
    set -u

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
}

do_phase5_networking() {
    echo "[5.1] Installing networking packages (WiFi + BT + wired)..."
    emerge --verbose net-wireless/wpa_supplicant \
        net-misc/networkmanager \
        net-misc/dhcpcd \
        gnome-extra/nm-applet \
        net-wireless/wireless-regdb \
        net-wireless/bluez

    echo "[5.2] Verifying wpa_supplicant dbus support..."
    emerge -pv net-wireless/wpa_supplicant 2>/dev/null | grep dbus || echo "  WARNING: Check dbus USE flag!"

    echo "[5.3] Enabling NetworkManager..."
    rc-update add NetworkManager default

    echo "  Ethernet: Intel I225-V 2.5GbE (igc) — works immediately."
    echo "  WiFi: Intel AX200 (iwlwifi) — needs linux-firmware."
}

do_phase6_world() {
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
    echo "--- Merging updated config files ---"
    echo "  If dispatch-conf shows diffs, press 'u' to use the new version"
    echo "  or 'z' to zap (keep current). Most should be auto-merged."
    dispatch-conf || echo "  [WARN] dispatch-conf failed or not available — run manually after install"
}

do_phase7_portage() {
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
}

do_phase8_services() {
    echo "[8.1] Enabling services..."

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
    rc-update add bluetooth default
    rc-update add chronyd default

    echo ""
    echo "[8.2] Verifying critical services..."
    echo "  Default runlevel:"
    rc-update show default
    echo "  Boot runlevel:"
    rc-update show boot
}

do_phase9_display() {
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
}

do_phase10_audio() {
    echo "[10.1] Verifying PipeWire installation..."
    qlist -I media-video/pipewire && echo "  [OK] PipeWire installed" || echo "  [FAIL] PipeWire missing!"
    qlist -I media-video/wireplumber && echo "  [OK] WirePlumber installed" || echo "  [FAIL] WirePlumber missing!"

    echo "[10.2] PipeWire autostart configured via gentoo-pipewire-launcher"
    echo "  Audio: Realtek ALC1220 (HDA) + NVIDIA GA104 HDMI"
}

do_phase11_hardware() {
    # --- NVIDIA ---
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

    # --- zram ---
    echo "[11.2] Configuring zram-init..."
    if [[ -f "$CONFIGS/zram-init.conf" ]]; then
        cp "$CONFIGS/zram-init.conf" /etc/conf.d/zram-init
        echo "  [OK] zram-init configured (8GB zstd, 16 streams)"
    fi

    # --- sysctl ---
    echo "[11.3] Installing sysctl tuning..."
    if [[ -f "$CONFIGS/sysctl-performance.conf" ]]; then
        cp "$CONFIGS/sysctl-performance.conf" /etc/sysctl.d/99-${MACHINE_NAME}-performance.conf
        echo "  [OK] /etc/sysctl.d/99-${MACHINE_NAME}-performance.conf"
    fi

    # --- Firmware verification ---
    echo "[11.4] Verifying firmware files..."
    ls /lib/firmware/$NVIDIA_FW_DIR/ 2>/dev/null && echo "  [OK] NVIDIA GA104 firmware directory" || echo "  [FAIL] NVIDIA GA104 firmware!"
    ls /lib/firmware/iwlwifi-cc-a0-*.ucode 2>/dev/null && echo "  [OK] iwlwifi firmware" || echo "  [WARN] iwlwifi firmware — check after linux-firmware install"
    ls /lib/firmware/intel/ibt-0040-0041.* 2>/dev/null && echo "  [OK] Intel BT firmware" || echo "  [WARN] Intel BT firmware"
    ls /lib/firmware/amd-ucode/ 2>/dev/null && echo "  [OK] AMD microcode directory" || echo "  [WARN] AMD microcode"

    # --- Emoji fontconfig ---
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
}

do_phase12_fstab() {
    echo "[12.1] Current fstab:"
    cat /etc/fstab
    echo ""
    echo "  [OK] fstab was generated by part2 with actual UUIDs."
    echo "  Note: 46GB tmpfs for portage + disk fallback for large packages."
}

do_phase13_verify() {
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
    grep -q "tmpfs.*portage.*46G" /etc/fstab && echo "[OK] 46GB portage tmpfs in fstab" || { echo "[WARN] Check portage tmpfs size"; WARN=$((WARN+1)); }

    # --- Networking ---
    qlist -I net-wireless/wpa_supplicant &>/dev/null && echo "[OK] wpa_supplicant installed" || { echo "[FAIL] wpa_supplicant!"; FAIL=$((FAIL+1)); }
    qlist -I net-misc/networkmanager &>/dev/null && echo "[OK] NetworkManager installed" || { echo "[FAIL] NetworkManager!"; FAIL=$((FAIL+1)); }

    # --- NVIDIA ---
    qlist -I x11-drivers/nvidia-drivers &>/dev/null && echo "[OK] nvidia-drivers installed" || { echo "[FAIL] nvidia-drivers!"; FAIL=$((FAIL+1)); }
    [[ -f /etc/modprobe.d/nvidia.conf ]] && echo "[OK] nvidia modprobe config" || { echo "[WARN] nvidia.conf missing"; WARN=$((WARN+1)); }

    # --- LightDM ---
    grep -q "user-session=xfce" /etc/lightdm/lightdm.conf 2>/dev/null && echo "[OK] LightDM session=xfce" || { echo "[FAIL] LightDM session!"; FAIL=$((FAIL+1)); }
    ls /usr/share/xsessions/xfce.desktop &>/dev/null && echo "[OK] xfce.desktop exists" || { echo "[FAIL] xfce.desktop!"; FAIL=$((FAIL+1)); }

    # --- Services ---
    REQUIRED_SVCS="dbus NetworkManager display-manager acpid sshd metalog local netmount chronyd"
    for svc in $REQUIRED_SVCS; do
        rc-update show default 2>/dev/null | grep -q "$svc" && echo "[OK] $svc enabled" || { echo "[FAIL] $svc NOT enabled!"; FAIL=$((FAIL+1)); }
    done
    rc-update show boot 2>/dev/null | grep -q elogind && echo "[OK] elogind enabled" || { echo "[FAIL] elogind NOT enabled!"; FAIL=$((FAIL+1)); }
    rc-update show default 2>/dev/null | grep -q zram && echo "[OK] zram-init enabled" || { echo "[FAIL] zram-init NOT enabled!"; FAIL=$((FAIL+1)); }
    rc-update show boot 2>/dev/null | grep -q alsasound && echo "[OK] alsasound enabled" || { echo "[FAIL] alsasound NOT enabled!"; FAIL=$((FAIL+1)); }

    # Bluetooth
    rc-update show default 2>/dev/null | grep -q bluetooth && echo "[OK] bluetooth enabled" || { echo "[FAIL] bluetooth NOT enabled!"; FAIL=$((FAIL+1)); }

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
    ls /lib/firmware/$NVIDIA_FW_DIR/ &>/dev/null && echo "[OK] NVIDIA GA104 firmware" || { echo "[FAIL] NVIDIA firmware!"; FAIL=$((FAIL+1)); }

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
}

# ============================================================================
# EXECUTE ALL PHASES (with automatic resume)
# ============================================================================

run_phase "phase1"  "PHASE 1: Bootstrap"              do_phase1_bootstrap
run_phase "phase2"  "PHASE 2: Kernel + Firmware"       do_phase2_kernel
run_phase "phase3"  "PHASE 3: Bootloader"              do_phase3_bootloader
run_phase "phase4"  "PHASE 4: System Configuration"    do_phase4_sysconfig
run_phase "phase5"  "PHASE 5: Networking"              do_phase5_networking
run_phase "phase6"  "PHASE 6: All Packages + NVIDIA"   do_phase6_world
run_phase "phase7"  "PHASE 7: Portage Infrastructure"  do_phase7_portage
run_phase "phase8"  "PHASE 8: OpenRC Services"         do_phase8_services
run_phase "phase9"  "PHASE 9: LightDM + XFCE"         do_phase9_display
run_phase "phase10" "PHASE 10: PipeWire Audio"         do_phase10_audio
run_phase "phase11" "PHASE 11: NVIDIA + Hardware"      do_phase11_hardware
run_phase "phase12" "PHASE 12: fstab"                  do_phase12_fstab
run_phase "phase13" "PHASE 13: PRE-REBOOT VERIFICATION" do_phase13_verify
