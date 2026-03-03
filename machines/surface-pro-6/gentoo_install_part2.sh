#!/bin/bash
# ============================================================================
# gentoo_install_part2.sh - Download stage3, extract, configure, chroot prep
# Microsoft Surface Pro 6 - Run from Fedora 43 Live USB (Ventoy)
# ============================================================================
# Prerequisites: part1 completed, /mnt/gentoo mounted
#
# Uses: wget (confirmed available), tar, mount, chroot
#
# After this script: enter chroot and run gentoo_install_part3_chroot.sh
# ============================================================================

set -euo pipefail

GENTOO="/mnt/gentoo"
MIRROR="https://gentoo.osuosl.org"
STAGE3_DIR="releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc"
# UPDATE THIS URL — check ${MIRROR}/${STAGE3_DIR}/ for latest tarball
STAGE3_FILE="stage3-amd64-desktop-openrc-20260222T170100Z.tar.xz"
STAGE3_URL="${MIRROR}/${STAGE3_DIR}/${STAGE3_FILE}"
DIGESTS_URL="${STAGE3_URL}.DIGESTS"

# Where our config files live (on the Ventoy USB)
CONFIGS="/run/media/liveuser/VTOYEFI/surfacepro6"

echo "=== Gentoo Install Part 2: Stage3 + Chroot Prep ==="
echo "    Machine: Surface Pro 6"
echo ""

# ============================================================================
# PRE-FLIGHT
# ============================================================================
# Verify mounts are in place
if ! mountpoint -q "$GENTOO"; then
    echo "ERROR: $GENTOO is not mounted. Run part1 first."
    exit 1
fi
if ! mountpoint -q "$GENTOO/boot"; then
    echo "ERROR: $GENTOO/boot is not mounted. Run part1 first."
    exit 1
fi
if ! mountpoint -q "$GENTOO/boot/efi"; then
    echo "ERROR: $GENTOO/boot/efi is not mounted. Run part1 first."
    exit 1
fi
echo "[OK] Filesystems mounted."

# Verify config files exist
if [[ ! -d "$CONFIGS" ]]; then
    echo "ERROR: Config directory $CONFIGS not found."
    echo "Mount the Ventoy USB and try again."
    exit 1
fi
echo "[OK] Config files found at $CONFIGS."
echo ""

# ============================================================================
# STEP 1: DOWNLOAD STAGE3
# ============================================================================
echo "[STEP 1] Downloading stage3 tarball..."
echo "  URL: $STAGE3_URL"
echo ""

cd "$GENTOO"

# Download stage3 and digests
if [[ ! -f "$STAGE3_FILE" ]]; then
    wget --progress=bar:force "$STAGE3_URL" -O "$STAGE3_FILE" --no-check-certificate
else
    echo "  Stage3 already downloaded, skipping."
fi

wget -q "$DIGESTS_URL" -O "${STAGE3_FILE}.DIGESTS" --no-check-certificate
echo ""

# ============================================================================
# STEP 2: VERIFY INTEGRITY
# ============================================================================
echo "[STEP 2] Verifying stage3 integrity..."

EXPECTED_SHA512=$(grep -A1 'SHA512' "${STAGE3_FILE}.DIGESTS" | grep "$STAGE3_FILE" | grep -v '.CONTENTS' | awk '{print $1}')

if [[ -n "$EXPECTED_SHA512" ]]; then
    ACTUAL_SHA512=$(sha512sum "$STAGE3_FILE" | awk '{print $1}')
    if [[ "$EXPECTED_SHA512" == "$ACTUAL_SHA512" ]]; then
        echo "  [OK] SHA512 checksum verified."
    else
        echo "  [FAIL] SHA512 mismatch!"
        echo "  Expected: $EXPECTED_SHA512"
        echo "  Got:      $ACTUAL_SHA512"
        echo "  The download may be corrupt. Delete and re-download."
        exit 1
    fi
else
    echo "  WARNING: Could not extract SHA512 from DIGESTS file."
    echo "  Proceeding without verification."
fi
echo ""

# ============================================================================
# STEP 3: EXTRACT STAGE3
# ============================================================================
echo "[STEP 3] Extracting stage3 to $GENTOO..."
echo "  This will take a few minutes..."

tar xpf "$STAGE3_FILE" --xattrs-include='*.*' --numeric-owner -C "$GENTOO"

echo "  [OK] Stage3 extracted."
echo ""

# Clean up tarball to save space
rm -f "$STAGE3_FILE" "${STAGE3_FILE}.DIGESTS"
echo "  Cleaned up downloaded files."
echo ""

# ============================================================================
# STEP 4: COPY CONFIGURATION FILES
# ============================================================================
echo "[STEP 4] Installing configuration files..."

# --- make.conf ---
if [[ -f "$CONFIGS/make.conf" ]]; then
    cp "$CONFIGS/make.conf" "$GENTOO/etc/portage/make.conf"
    echo "  [OK] make.conf"
else
    echo "  [FAIL] make.conf not found!"
fi

# --- package.env + env directory ---
if [[ -f "$CONFIGS/package.env" ]]; then
    cp "$CONFIGS/package.env" "$GENTOO/etc/portage/package.env"
    echo "  [OK] package.env"
fi
if [[ -f "$CONFIGS/portage_env_notmpfs.conf" ]]; then
    mkdir -p "$GENTOO/etc/portage/env"
    cp "$CONFIGS/portage_env_notmpfs.conf" "$GENTOO/etc/portage/env/notmpfs.conf"
    echo "  [OK] env/notmpfs.conf"
fi

# --- Kernel config script ---
if [[ -f "$CONFIGS/kernel_config.sh" ]]; then
    mkdir -p "$GENTOO/root/surface-pro-6-configs"
    cp "$CONFIGS/kernel_config.sh" "$GENTOO/root/surface-pro-6-configs/"
    chmod +x "$GENTOO/root/surface-pro-6-configs/kernel_config.sh"
    echo "  [OK] kernel_config.sh -> /root/surface-pro-6-configs/"
fi

# --- World file ---
if [[ -f "$CONFIGS/world" ]]; then
    cp "$CONFIGS/world" "$GENTOO/root/surface-pro-6-configs/world"
    echo "  [OK] world -> /root/surface-pro-6-configs/"
fi

# --- MBP 2015 kernel .config as base ---
MBP_CONFIG="/run/media/liveuser/VTOYEFI/mbp2015/.config"
if [[ ! -f "$MBP_CONFIG" ]]; then
    # Try from git repo
    MBP_CONFIG="/home/liveuser/gentoo-machines/machines/mbp-2015/.config"
fi
if [[ -f "$MBP_CONFIG" ]]; then
    cp "$MBP_CONFIG" "$GENTOO/root/surface-pro-6-configs/base.config"
    echo "  [OK] MBP 2015 .config -> /root/surface-pro-6-configs/base.config"
else
    echo "  [WARN] MBP 2015 base .config not found (will need to copy manually)"
fi

# --- Fedora surface kernel config (reference) ---
if [[ -f "$CONFIGS/fedora_surface_kernel_6.18.8.config" ]]; then
    cp "$CONFIGS/fedora_surface_kernel_6.18.8.config" "$GENTOO/root/surface-pro-6-configs/"
    echo "  [OK] Fedora reference config -> /root/surface-pro-6-configs/"
fi

# --- IPTSD configs (touchscreen — broken but save for reference) ---
if [[ -f "$CONFIGS/iptsd.conf" ]]; then
    cp "$CONFIGS/iptsd.conf" "$GENTOO/root/surface-pro-6-configs/"
    echo "  [OK] iptsd.conf (reference)"
fi
if [[ -f "$CONFIGS/iptsd-surface-pro-6.conf" ]]; then
    cp "$CONFIGS/iptsd-surface-pro-6.conf" "$GENTOO/root/surface-pro-6-configs/"
    echo "  [OK] iptsd-surface-pro-6.conf (reference)"
fi

# --- Shared portage files from git repo ---
REPO="/home/liveuser/gentoo-machines"
if [[ -d "$REPO/shared" ]]; then
    # package.use
    mkdir -p "$GENTOO/etc/portage/package.use"
    if [[ -f "$REPO/shared/package.use" ]]; then
        cp "$REPO/shared/package.use" "$GENTOO/etc/portage/package.use/shared"
        echo "  [OK] shared/package.use -> package.use/shared"
    fi

    # Surface-specific package.use
    if [[ -f "$CONFIGS/package.use" ]]; then
        cp "$CONFIGS/package.use" "$GENTOO/etc/portage/package.use/surface-pro-6"
        echo "  [OK] surface-pro-6 package.use -> package.use/surface-pro-6"
    fi

    # package.accept_keywords
    mkdir -p "$GENTOO/etc/portage/package.accept_keywords"
    if [[ -f "$REPO/shared/package.accept_keywords" ]]; then
        cp "$REPO/shared/package.accept_keywords" "$GENTOO/etc/portage/package.accept_keywords/shared"
        echo "  [OK] shared/package.accept_keywords -> package.accept_keywords/shared"
    fi

    # package.license
    if [[ -f "$REPO/shared/package.license" ]]; then
        mkdir -p "$GENTOO/etc/portage/package.license"
        cp "$REPO/shared/package.license" "$GENTOO/etc/portage/package.license/shared"
        echo "  [OK] shared/package.license"
    fi

    # LightDM config — Surface-specific (HiDPI: xserver-command=X -dpi 144)
    if [[ -f "$CONFIGS/lightdm.conf" ]]; then
        cp "$CONFIGS/lightdm.conf" "$GENTOO/root/surface-pro-6-configs/lightdm.conf"
        echo "  [OK] lightdm.conf (Surface HiDPI) -> /root/surface-pro-6-configs/"
    elif [[ -f "$REPO/shared/lightdm.conf" ]]; then
        cp "$REPO/shared/lightdm.conf" "$GENTOO/root/surface-pro-6-configs/lightdm.conf"
        echo "  [WARN] Using shared lightdm.conf (no HiDPI)"
    fi

    # LightDM display-setup and greeter config (HiDPI)
    for ldmfile in lightdm-display-setup.sh lightdm-gtk-greeter.conf; do
        if [[ -f "$CONFIGS/$ldmfile" ]]; then
            cp "$CONFIGS/$ldmfile" "$GENTOO/root/surface-pro-6-configs/"
            echo "  [OK] $ldmfile -> /root/surface-pro-6-configs/"
        fi
    done

    # Shared desktop restore scripts
    for script in restore-desktop.sh restore-system.sh xfce4-keybindings.sh xfce4-panel.sh; do
        if [[ -f "$REPO/shared/$script" ]]; then
            cp "$REPO/shared/$script" "$GENTOO/root/surface-pro-6-configs/"
            echo "  [OK] $script -> /root/surface-pro-6-configs/"
        fi
    done

    # OpenRC services reference
    if [[ -f "$REPO/shared/openrc-services" ]]; then
        cp "$REPO/shared/openrc-services" "$GENTOO/root/surface-pro-6-configs/"
        echo "  [OK] openrc-services -> /root/surface-pro-6-configs/"
    fi

    # Touchpad config
    if [[ -f "$REPO/shared/30-touchpad.conf" ]]; then
        mkdir -p "$GENTOO/etc/X11/xorg.conf.d"
        cp "$REPO/shared/30-touchpad.conf" "$GENTOO/etc/X11/xorg.conf.d/"
        echo "  [OK] 30-touchpad.conf -> /etc/X11/xorg.conf.d/"
    fi

    # KSM startup script
    if [[ -f "$REPO/shared/ksm.start" ]]; then
        mkdir -p "$GENTOO/etc/local.d"
        cp "$REPO/shared/ksm.start" "$GENTOO/etc/local.d/ksm.start"
        chmod +x "$GENTOO/etc/local.d/ksm.start"
        echo "  [OK] ksm.start -> /etc/local.d/"
    fi
fi

# --- GRUB defaults (HiDPI: GFXMODE=1024x768, console font TER16x32, i915 power) ---
if [[ -f "$CONFIGS/grub" ]]; then
    cp "$CONFIGS/grub" "$GENTOO/root/surface-pro-6-configs/grub"
    echo "  [OK] grub -> /root/surface-pro-6-configs/"
fi

# --- WiFi power save fix (Marvell 88W8897 hangs after suspend without these) ---
for wfile in mwifiex.conf wifi-powersave.conf wifi-reload.sh wifi-recover.sh; do
    if [[ -f "$CONFIGS/$wfile" ]]; then
        cp "$CONFIGS/$wfile" "$GENTOO/root/surface-pro-6-configs/"
        echo "  [OK] $wfile -> /root/surface-pro-6-configs/"
    fi
done

# --- local.d startup scripts ---
if [[ -f "$CONFIGS/disable-wakeup.start" ]]; then
    mkdir -p "$GENTOO/etc/local.d"
    cp "$CONFIGS/disable-wakeup.start" "$GENTOO/etc/local.d/disable-wakeup.start"
    chmod +x "$GENTOO/etc/local.d/disable-wakeup.start"
    echo "  [OK] disable-wakeup.start -> /etc/local.d/"
fi
if [[ -f "$CONFIGS/fstrim-weekly.start" ]]; then
    mkdir -p "$GENTOO/etc/local.d"
    cp "$CONFIGS/fstrim-weekly.start" "$GENTOO/etc/local.d/fstrim-weekly.start"
    chmod +x "$GENTOO/etc/local.d/fstrim-weekly.start"
    echo "  [OK] fstrim-weekly.start -> /etc/local.d/"
fi

# --- Chroot install script ---
if [[ -f "$CONFIGS/gentoo_install_part3_chroot.sh" ]]; then
    cp "$CONFIGS/gentoo_install_part3_chroot.sh" "$GENTOO/root/"
    chmod +x "$GENTOO/root/gentoo_install_part3_chroot.sh"
    echo "  [OK] gentoo_install_part3_chroot.sh -> /root/"
fi

echo ""

# ============================================================================
# STEP 5: CONFIGURE DNS
# ============================================================================
echo "[STEP 5] Configuring DNS for chroot..."
cp -L /etc/resolv.conf "$GENTOO/etc/resolv.conf"
echo "  [OK] resolv.conf copied."
echo ""

# ============================================================================
# STEP 6: MOUNT PSEUDO-FILESYSTEMS
# ============================================================================
echo "[STEP 6] Mounting pseudo-filesystems for chroot..."

mount --types proc /proc "$GENTOO/proc"
echo "  [OK] /proc"

mount --rbind /sys "$GENTOO/sys"
mount --make-rslave "$GENTOO/sys"
echo "  [OK] /sys"

mount --rbind /dev "$GENTOO/dev"
mount --make-rslave "$GENTOO/dev"
echo "  [OK] /dev"

mount --bind /run "$GENTOO/run"
mount --make-slave "$GENTOO/run"
echo "  [OK] /run"

echo ""

# ============================================================================
# STEP 7: CREATE PORTAGE BUILD DIRECTORIES
# ============================================================================
echo "[STEP 7] Creating portage build directories..."
mkdir -p "$GENTOO/var/tmp/portage"
mkdir -p "$GENTOO/var/tmp/portage-disk"
echo "  [OK] /var/tmp/portage and /var/tmp/portage-disk created."
echo ""

# ============================================================================
# STEP 8: GRAB UUIDs
# ============================================================================
echo "[STEP 8] Partition UUIDs for fstab:"
UUID_EFI=$(blkid -s UUID -o value /dev/nvme0n1p1 2>/dev/null || echo 'UNKNOWN')
UUID_BOOT=$(blkid -s UUID -o value /dev/nvme0n1p2 2>/dev/null || echo 'UNKNOWN')
UUID_ROOT=$(blkid -s UUID -o value /dev/nvme0n1p3 2>/dev/null || echo 'UNKNOWN')
echo "  EFI  (nvme0n1p1): $UUID_EFI"
echo "  BOOT (nvme0n1p2): $UUID_BOOT"
echo "  ROOT (nvme0n1p3): $UUID_ROOT"
echo ""

# Save UUIDs for use inside chroot
cat > "$GENTOO/root/surface-pro-6-configs/disk-uuids.txt" << EOF
UUID_EFI=$UUID_EFI
UUID_BOOT=$UUID_BOOT
UUID_ROOT=$UUID_ROOT
EOF
echo "  [OK] UUIDs saved to /root/surface-pro-6-configs/disk-uuids.txt"
echo ""

# ============================================================================
# STEP 9: GENERATE FSTAB
# ============================================================================
echo "[STEP 9] Generating /etc/fstab..."

cat > "$GENTOO/etc/fstab" << FSTAB
# /etc/fstab - Surface Pro 6 Gentoo
# Generated by gentoo_install_part2.sh

# <device>                                <mount>          <fs>   <opts>                                                 <dump> <pass>
UUID=$UUID_EFI                             /boot/efi        vfat   defaults,noatime,umask=0077                             0      0
UUID=$UUID_BOOT                            /boot            ext4   defaults,noatime                                        0      2
UUID=$UUID_ROOT                            /                ext4   defaults,noatime                                        0      1

# Portage tmpfs — 4GB (8GB RAM machine, keep half for system)
# Large packages redirected to disk via package.env
tmpfs                                      /var/tmp/portage tmpfs  size=4G,uid=portage,gid=portage,mode=775,nosuid,noatime,nodev 0 0
FSTAB

echo "  [OK] /etc/fstab generated with UUIDs."
echo ""

# ============================================================================
# DONE - READY TO CHROOT
# ============================================================================
echo "============================================================"
echo "=== Ready to chroot into Gentoo! ==="
echo "============================================================"
echo ""
echo "Enter the chroot with:"
echo "  sudo chroot /mnt/gentoo /bin/bash"
echo "  source /etc/profile"
echo '  export PS1="(chroot) \[\033[0;31m\]\u@\h \[\033[0;36m\]\w \$ \[\033[0m\]"'
echo ""
echo "Config files staged at /root/surface-pro-6-configs/:"
ls -la "$GENTOO/root/surface-pro-6-configs/" 2>/dev/null || true
echo ""
echo "Once inside the chroot, follow INSTALL_PREFLIGHT.md phases or run:"
echo "  bash /root/gentoo_install_part3_chroot.sh"
echo ""
echo "Key phases (from INSTALL_PREFLIGHT.md):"
echo "  Phase 1:  emerge-webrsync + profile"
echo "  Phase 2:  Kernel (gentoo-sources + linux-firmware + build)"
echo "  Phase 3:  GRUB bootloader"
echo "  Phase 4:  System config (locale, timezone, hostname, user)"
echo "  Phase 5:  Networking (wpa_supplicant + NetworkManager) — CRITICAL"
echo "  Phase 6:  All packages (world file)"
echo "  Phase 7:  Portage infrastructure"
echo "  Phase 8:  OpenRC services"
echo "  Phase 9:  LightDM + XFCE"
echo "  Phase 10: PipeWire audio"
echo "  Phase 11: Surface-specific hardware"
echo "  Phase 12: fstab (already generated!)"
echo "  Phase 13: VERIFICATION — check everything before reboot"
