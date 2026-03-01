#!/bin/bash
# ============================================================================
# gentoo_install_part2.sh - Download stage3, extract, configure, chroot prep
# Dell XPS 15 9510 - Run from Live USB
# ============================================================================
# Prerequisites: part1 completed, /mnt/gentoo mounted
#
# After this script: enter chroot and run gentoo_install_part3_chroot.sh
# ============================================================================

set -euo pipefail

GENTOO="/mnt/gentoo"
MIRROR="https://gentoo.osuosl.org"
STAGE3_DIR="releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc"
# UPDATE THIS URL to the latest stage3 before running!
STAGE3_FILE="stage3-amd64-desktop-openrc-20260222T170100Z.tar.xz"
STAGE3_URL="${MIRROR}/${STAGE3_DIR}/${STAGE3_FILE}"
DIGESTS_URL="${STAGE3_URL}.DIGESTS"

# Where our config files live (USB or git clone)
# Adjust this path to match your USB layout
CONFIGS="/run/media/liveuser/VTOYEFI/xps9510"

echo "=== Gentoo Install Part 2: Stage3 + Chroot Prep ==="
echo "    Machine: Dell XPS 15 9510"
echo ""

# ============================================================================
# PRE-FLIGHT
# ============================================================================
if ! mountpoint -q "$GENTOO"; then
    echo "ERROR: $GENTOO is not mounted. Run part1 first."
    exit 1
fi
echo "[OK] Root filesystem mounted."

# Try to find config files
if [[ ! -d "$CONFIGS" ]]; then
    # Fallback: try git repo
    CONFIGS="/home/liveuser/gentoo-machines/machines/xps-9510"
    if [[ ! -d "$CONFIGS" ]]; then
        echo "ERROR: Config directory not found."
        echo "Tried: /run/media/liveuser/VTOYEFI/xps9510"
        echo "       /home/liveuser/gentoo-machines/machines/xps-9510"
        echo "Clone the repo or mount the USB and try again."
        exit 1
    fi
fi
echo "[OK] Config files found at $CONFIGS."
echo ""

# Shared config directory
SHARED="${CONFIGS}/../../shared"
if [[ ! -d "$SHARED" ]]; then
    SHARED="/home/liveuser/gentoo-machines/shared"
fi

# ============================================================================
# STEP 1: DOWNLOAD STAGE3
# ============================================================================
echo "[STEP 1] Downloading stage3 tarball..."
echo "  URL: $STAGE3_URL"
echo ""

cd "$GENTOO"

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
        echo "  [FAIL] SHA512 mismatch! Delete and re-download."
        exit 1
    fi
else
    echo "  WARNING: Could not extract SHA512. Proceeding without verification."
fi
echo ""

# ============================================================================
# STEP 3: EXTRACT STAGE3
# ============================================================================
echo "[STEP 3] Extracting stage3 to $GENTOO..."
echo "  This will take a few minutes..."

tar xpf "$STAGE3_FILE" --xattrs-include='*.*' --numeric-owner -C "$GENTOO"

echo "  [OK] Stage3 extracted."
rm -f "$STAGE3_FILE" "${STAGE3_FILE}.DIGESTS"
echo "  Cleaned up downloaded files."
echo ""

# ============================================================================
# STEP 4: COPY CONFIGURATION FILES
# ============================================================================
echo "[STEP 4] Installing configuration files..."

STAGING="$GENTOO/root/xps-9510-configs"
mkdir -p "$STAGING"

# --- make.conf ---
if [[ -f "$CONFIGS/make.conf" ]]; then
    cp "$CONFIGS/make.conf" "$GENTOO/etc/portage/make.conf"
    echo "  [OK] make.conf"
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
    cp "$CONFIGS/kernel_config.sh" "$STAGING/"
    chmod +x "$STAGING/kernel_config.sh"
    echo "  [OK] kernel_config.sh -> /root/xps-9510-configs/"
fi

# --- World file ---
if [[ -f "$CONFIGS/world" ]]; then
    cp "$CONFIGS/world" "$STAGING/world"
    echo "  [OK] world -> /root/xps-9510-configs/"
fi

# --- NVIDIA files ---
if [[ -f "$CONFIGS/99-module-rebuild.install" ]]; then
    cp "$CONFIGS/99-module-rebuild.install" "$STAGING/"
    echo "  [OK] 99-module-rebuild.install"
fi
if [[ -f "$CONFIGS/prime-run" ]]; then
    cp "$CONFIGS/prime-run" "$STAGING/"
    echo "  [OK] prime-run"
fi

# --- tlp.conf ---
if [[ -f "$CONFIGS/tlp.conf" ]]; then
    cp "$CONFIGS/tlp.conf" "$STAGING/"
    echo "  [OK] tlp.conf"
fi

# --- sysctl-performance.conf ---
if [[ -f "$CONFIGS/sysctl-performance.conf" ]]; then
    cp "$CONFIGS/sysctl-performance.conf" "$STAGING/"
    echo "  [OK] sysctl-performance.conf"
fi

# --- GRUB config ---
if [[ -f "$CONFIGS/grub" ]]; then
    cp "$CONFIGS/grub" "$STAGING/grub"
    echo "  [OK] grub defaults"
fi

# --- zram-init config ---
if [[ -f "$CONFIGS/zram-init.conf" ]]; then
    cp "$CONFIGS/zram-init.conf" "$STAGING/"
    echo "  [OK] zram-init.conf"
fi

# --- Shared portage files ---
if [[ -d "$SHARED" ]]; then
    mkdir -p "$GENTOO/etc/portage/package.use"
    if [[ -f "$SHARED/package.use" ]]; then
        cp "$SHARED/package.use" "$GENTOO/etc/portage/package.use/shared"
        echo "  [OK] shared/package.use -> package.use/shared"
    fi

    # Machine-specific package.use
    if [[ -f "$CONFIGS/package.use" ]]; then
        cp "$CONFIGS/package.use" "$GENTOO/etc/portage/package.use/xps-9510"
        echo "  [OK] xps-9510 package.use -> package.use/xps-9510"
    fi

    # package.accept_keywords
    mkdir -p "$GENTOO/etc/portage/package.accept_keywords"
    if [[ -f "$CONFIGS/package.accept_keywords" ]]; then
        cp "$CONFIGS/package.accept_keywords" "$GENTOO/etc/portage/package.accept_keywords/xps-9510"
        echo "  [OK] package.accept_keywords"
    fi

    # package.license
    if [[ -f "$SHARED/package.license" ]]; then
        mkdir -p "$GENTOO/etc/portage/package.license"
        cp "$SHARED/package.license" "$GENTOO/etc/portage/package.license/shared"
        echo "  [OK] shared/package.license"
    fi

    # Touchpad config
    if [[ -f "$SHARED/30-touchpad.conf" ]]; then
        mkdir -p "$GENTOO/etc/X11/xorg.conf.d"
        cp "$SHARED/30-touchpad.conf" "$GENTOO/etc/X11/xorg.conf.d/"
        echo "  [OK] 30-touchpad.conf -> /etc/X11/xorg.conf.d/"
    fi

    # KSM startup script
    if [[ -f "$SHARED/ksm.start" ]]; then
        mkdir -p "$GENTOO/etc/local.d"
        cp "$SHARED/ksm.start" "$GENTOO/etc/local.d/ksm.start"
        chmod +x "$GENTOO/etc/local.d/ksm.start"
        echo "  [OK] ksm.start -> /etc/local.d/"
    fi

    # Desktop restore scripts
    for script in restore-desktop.sh restore-system.sh xfce4-keybindings.sh xfce4-panel.sh lightdm.conf openrc-services; do
        if [[ -f "$SHARED/$script" ]]; then
            cp "$SHARED/$script" "$STAGING/"
            echo "  [OK] $script -> /root/xps-9510-configs/"
        fi
    done
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
# STEP 7: CREATE BUILD DIRECTORIES
# ============================================================================
echo "[STEP 7] Creating portage build directories..."
mkdir -p "$GENTOO/var/tmp/portage"
mkdir -p "$GENTOO/var/tmp/portage-disk"
mkdir -p "$GENTOO/data/build-cache/ccache"
echo "  [OK] Build directories created."
echo ""

# ============================================================================
# STEP 8: GRAB UUIDs
# ============================================================================
echo "[STEP 8] Partition UUIDs for fstab:"
UUID_EFI=$(blkid -s UUID -o value /dev/nvme0n1p1 2>/dev/null || echo 'UNKNOWN')
UUID_ROOT=$(blkid -s UUID -o value /dev/nvme0n1p2 2>/dev/null || echo 'UNKNOWN')
UUID_DATA=$(blkid -s UUID -o value /dev/nvme1n1p1 2>/dev/null || echo 'UNKNOWN')
echo "  EFI  (nvme0n1p1): $UUID_EFI"
echo "  ROOT (nvme0n1p2): $UUID_ROOT"
echo "  DATA (nvme1n1p1): $UUID_DATA"
echo ""

# Save UUIDs for use inside chroot
cat > "$STAGING/disk-uuids.txt" << EOF
UUID_EFI=$UUID_EFI
UUID_ROOT=$UUID_ROOT
UUID_DATA=$UUID_DATA
EOF
echo "  [OK] UUIDs saved to /root/xps-9510-configs/disk-uuids.txt"
echo ""

# ============================================================================
# STEP 9: GENERATE FSTAB
# ============================================================================
echo "[STEP 9] Generating /etc/fstab..."

cat > "$GENTOO/etc/fstab" << FSTAB
# /etc/fstab - Dell XPS 15 9510 Gentoo
# Generated by gentoo_install_part2.sh

# <device>                                <mount>          <fs>   <opts>                                                 <dump> <pass>
UUID=$UUID_ROOT                            /                ext4   noatime,discard,commit=60                               0      1
UUID=$UUID_EFI                             /boot/efi        vfat   noauto,umask=0077                                       0      2
UUID=$UUID_DATA                            /data            ext4   noatime,discard,commit=60                               0      2

# Ramdisks
tmpfs                                      /tmp             tmpfs  size=16G,nosuid,nodev                                   0      0
tmpfs                                      /var/tmp/portage tmpfs  size=24G,uid=portage,gid=portage,mode=775,nosuid,noatime,nodev 0 0
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
echo "Config files staged at /root/xps-9510-configs/:"
ls -la "$STAGING/" 2>/dev/null || true
echo ""
echo "Once inside the chroot, run:"
echo "  bash /root/gentoo_install_part3_chroot.sh"
