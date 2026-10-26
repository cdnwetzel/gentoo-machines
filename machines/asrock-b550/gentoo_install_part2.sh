#!/bin/bash
# ============================================================================
# gentoo_install_part2.sh - Download stage3, extract, configure, chroot prep
# ASRock B550 Phantom Gaming-ITX/ax - Run from Fedora 43 Live USB
# ============================================================================
# Prerequisites: part1 completed, /mnt/gentoo mounted
#
# After this script: enter chroot and run gentoo_install_part3_chroot.sh
# ============================================================================
# MACHINE CONFIG — B550-specific values at top, universal logic below
# ============================================================================
MACHINE_NAME="asrock-b550"
MACHINE_LABEL="ASRock B550 Phantom Gaming-ITX/ax"
GENTOO="/mnt/gentoo"

# Stage3 — auto-discovers latest from mirror
MIRROR="https://gentoo.osuosl.org"
STAGE3_DIR="releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc"
STAGE3_FALLBACK="stage3-amd64-desktop-openrc-20260222T170100Z.tar.xz"

# Auto-discover latest stage3 from mirror
echo "Checking mirror for latest stage3..."
STAGE3_FILE=""
if command -v wget &>/dev/null; then
    LATEST=$(wget -qO- "${MIRROR}/${STAGE3_DIR}/latest-stage3-amd64-desktop-openrc.txt" 2>/dev/null \
        | grep -v '^#' | grep 'stage3' | head -1 | awk '{print $1}' | xargs basename 2>/dev/null)
    [[ -n "$LATEST" ]] && STAGE3_FILE="$LATEST"
elif command -v curl &>/dev/null; then
    LATEST=$(curl -sfL "${MIRROR}/${STAGE3_DIR}/latest-stage3-amd64-desktop-openrc.txt" 2>/dev/null \
        | grep -v '^#' | grep 'stage3' | head -1 | awk '{print $1}' | xargs basename 2>/dev/null)
    [[ -n "$LATEST" ]] && STAGE3_FILE="$LATEST"
fi
if [[ -z "$STAGE3_FILE" ]]; then
    echo "  Mirror unreachable — using fallback: $STAGE3_FALLBACK"
    STAGE3_FILE="$STAGE3_FALLBACK"
else
    echo "  Found: $STAGE3_FILE"
fi
STAGE3_URL="${MIRROR}/${STAGE3_DIR}/${STAGE3_FILE}"
DIGESTS_URL="${STAGE3_URL}.DIGESTS"

# Config sources — git repo on live USB
CONFIGS_REPO="/home/liveuser/gentoo-machines/machines/${MACHINE_NAME}"
SHARED_REPO="/home/liveuser/gentoo-machines/shared"

# Partition layout (must match part1)
TARGET="/dev/nvme0n1"
PART_PREFIX="${TARGET}p"
PART_EFI="${PART_PREFIX}1"
PART_BOOT="${PART_PREFIX}2"
PART_ROOT="${PART_PREFIX}3"

# Portage tmpfs size — 46GB (from 64GB RAM)
TMPFS_SIZE="46G"
# ============================================================================

set -euo pipefail
[[ $EUID -ne 0 ]] && echo "ERROR: Must run as root (sudo)" && exit 1

echo "=== Gentoo Install Part 2: Stage3 + Chroot Prep ==="
echo "    Machine: $MACHINE_LABEL"
echo ""

# ============================================================================
# PRE-FLIGHT: Verify mounts
# ============================================================================
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

# ============================================================================
# PRE-FLIGHT: Find config files
# ============================================================================
CONFIGS=""
if [[ -d "$CONFIGS_REPO" && -f "$CONFIGS_REPO/make.conf" ]]; then
    CONFIGS="$CONFIGS_REPO"
    echo "[OK] Config files found in git repo: $CONFIGS"
else
    echo "ERROR: Config directory not found at $CONFIGS_REPO"
    exit 1
fi

# Shared config directory
SHARED="$SHARED_REPO"
if [[ -d "$SHARED" ]]; then
    echo "[OK] Shared config files found at $SHARED"
else
    echo "[WARN] Shared config directory not found — some files may be missing."
fi
echo ""

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
rm -f "$STAGE3_FILE" "${STAGE3_FILE}.DIGESTS"
echo "  Cleaned up downloaded files."
echo ""

# ============================================================================
# STEP 4: COPY CONFIGURATION FILES
# ============================================================================
echo "[STEP 4] Installing configuration files..."

STAGING="$GENTOO/root/${MACHINE_NAME}-configs"
mkdir -p "$STAGING"

# --- make.conf ---
if [[ -f "$CONFIGS/make.conf" ]]; then
    cp "$CONFIGS/make.conf" "$GENTOO/etc/portage/make.conf"
    echo "  [OK] make.conf"
else
    echo "  [FAIL] make.conf not found!"
fi

# --- Kernel config script ---
if [[ -f "$CONFIGS/kernel_config.sh" ]]; then
    cp "$CONFIGS/kernel_config.sh" "$STAGING/"
    chmod +x "$STAGING/kernel_config.sh"
    echo "  [OK] kernel_config.sh -> /root/${MACHINE_NAME}-configs/"
fi

# --- World file ---
if [[ -f "$CONFIGS/world" ]]; then
    cp "$CONFIGS/world" "$STAGING/world"
    echo "  [OK] ${MACHINE_NAME}/world -> /root/${MACHINE_NAME}-configs/"
fi

# --- sysctl-performance.conf ---
if [[ -f "$CONFIGS/sysctl-performance.conf" ]]; then
    cp "$CONFIGS/sysctl-performance.conf" "$STAGING/"
    echo "  [OK] sysctl-performance.conf"
fi

# --- zram-init.conf ---
if [[ -f "$CONFIGS/zram-init.conf" ]]; then
    cp "$CONFIGS/zram-init.conf" "$STAGING/"
    echo "  [OK] zram-init.conf"
fi

# --- NVIDIA: module rebuild hook (borrow from XPS 9510) ---
XPS_CONFIGS="/home/liveuser/gentoo-machines/machines/xps-9510"
if [[ -f "$XPS_CONFIGS/99-module-rebuild.install" ]]; then
    cp "$XPS_CONFIGS/99-module-rebuild.install" "$STAGING/"
    echo "  [OK] 99-module-rebuild.install (from xps-9510)"
fi

# --- Shared portage files ---
if [[ -d "$SHARED" ]]; then
    # package.use (shared)
    mkdir -p "$GENTOO/etc/portage/package.use"
    if [[ -f "$SHARED/package.use" ]]; then
        cp "$SHARED/package.use" "$GENTOO/etc/portage/package.use/shared"
        echo "  [OK] shared/package.use -> package.use/shared"
    fi

    # package.accept_keywords (shared + machine-specific)
    mkdir -p "$GENTOO/etc/portage/package.accept_keywords"
    if [[ -f "$SHARED/package.accept_keywords" ]]; then
        cp "$SHARED/package.accept_keywords" "$GENTOO/etc/portage/package.accept_keywords/shared"
        echo "  [OK] shared/package.accept_keywords"
    fi
    if [[ -f "$CONFIGS/package.accept_keywords" ]]; then
        cp "$CONFIGS/package.accept_keywords" "$GENTOO/etc/portage/package.accept_keywords/${MACHINE_NAME}"
        echo "  [OK] ${MACHINE_NAME}/package.accept_keywords (6.18 LTS + NVIDIA)"
    fi

    # Machine-specific package.use
    if [[ -f "$CONFIGS/package.use" ]]; then
        cp "$CONFIGS/package.use" "$GENTOO/etc/portage/package.use/${MACHINE_NAME}"
        echo "  [OK] ${MACHINE_NAME}/package.use (installkernel grub, NVIDIA kernel-open)"
    fi

    # Machine-specific package.env + notmpfs
    if [[ -f "$CONFIGS/package.env" ]]; then
        cp "$CONFIGS/package.env" "$GENTOO/etc/portage/package.env"
        echo "  [OK] package.env (disk fallback for large packages)"
    fi
    mkdir -p "$GENTOO/etc/portage/env"
    if [[ -f "$CONFIGS/portage_env_notmpfs.conf" ]]; then
        cp "$CONFIGS/portage_env_notmpfs.conf" "$GENTOO/etc/portage/env/notmpfs.conf"
        echo "  [OK] env/notmpfs.conf"
    fi

    # package.license
    if [[ -f "$SHARED/package.license" ]]; then
        mkdir -p "$GENTOO/etc/portage/package.license"
        cp "$SHARED/package.license" "$GENTOO/etc/portage/package.license/shared"
        echo "  [OK] shared/package.license"
    fi

    # Touchpad config (for any USB touchpad/mouse)
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

    # fstrim-weekly
    if [[ -f "$SHARED/fstrim-weekly" ]]; then
        mkdir -p "$GENTOO/etc/local.d"
        cp "$SHARED/fstrim-weekly" "$GENTOO/etc/local.d/fstrim-weekly.start"
        chmod +x "$GENTOO/etc/local.d/fstrim-weekly.start"
        echo "  [OK] fstrim-weekly -> /etc/local.d/"
    fi

    # Desktop restore scripts -> staging for post-install
    for script in restore-desktop.sh restore-system.sh xfce4-keybindings.sh xfce4-panel.sh lightdm.conf openrc-services; do
        if [[ -f "$SHARED/$script" ]]; then
            cp "$SHARED/$script" "$STAGING/"
            echo "  [OK] $script -> /root/${MACHINE_NAME}-configs/"
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
mkdir -p "$GENTOO/var/cache/ccache"
echo "  [OK] Build directories created."
echo "  Note: 46GB tmpfs + disk fallback for large packages."
echo ""

# ============================================================================
# STEP 8: GRAB UUIDs
# ============================================================================
echo "[STEP 8] Partition UUIDs for fstab:"
UUID_EFI=$(blkid -s UUID -o value "$PART_EFI" 2>/dev/null || echo 'UNKNOWN')
UUID_BOOT=$(blkid -s UUID -o value "$PART_BOOT" 2>/dev/null || echo 'UNKNOWN')
UUID_ROOT=$(blkid -s UUID -o value "$PART_ROOT" 2>/dev/null || echo 'UNKNOWN')
echo "  EFI  (${PART_EFI}): $UUID_EFI"
echo "  BOOT (${PART_BOOT}): $UUID_BOOT"
echo "  ROOT (${PART_ROOT}): $UUID_ROOT"
echo ""

# Save UUIDs for use inside chroot
cat > "$STAGING/disk-uuids.txt" << EOF
UUID_EFI=$UUID_EFI
UUID_BOOT=$UUID_BOOT
UUID_ROOT=$UUID_ROOT
EOF
echo "  [OK] UUIDs saved to /root/${MACHINE_NAME}-configs/disk-uuids.txt"
echo ""

# ============================================================================
# STEP 9: GENERATE FSTAB
# ============================================================================
echo "[STEP 9] Generating /etc/fstab..."

cat > "$GENTOO/etc/fstab" << FSTAB
# /etc/fstab - ASRock B550 Gentoo
# Generated by gentoo_install_part2.sh

# <device>                                <mount>          <fs>   <opts>                                                 <dump> <pass>
UUID=$UUID_ROOT                            /                ext4   defaults,noatime                                        0      1
UUID=$UUID_BOOT                            /boot            ext4   defaults,noatime                                        0      2
UUID=$UUID_EFI                             /boot/efi        vfat   defaults,noatime,umask=0077                             0      0

# Portage tmpfs — ${TMPFS_SIZE} (from 64GB RAM)
# 46GB handles most packages; chromium/llvm/rust/gcc use disk fallback
tmpfs                                      /var/tmp/portage tmpfs  size=${TMPFS_SIZE},uid=portage,gid=portage,mode=775,nosuid,noatime,nodev 0 0
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
echo "Config files staged at /root/${MACHINE_NAME}-configs/:"
ls -la "$STAGING/" 2>/dev/null || true
echo ""
echo "Once inside the chroot, run:"
echo "  bash /root/gentoo_install_part3_chroot.sh"
