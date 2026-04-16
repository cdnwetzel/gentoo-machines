#!/bin/bash
# ============================================================================
# gentoo_install_part2.sh - Stage3 + chroot prep
# Beelink MINI S (N5095A) - Run from Fedora 43 Live USB (Ventoy)
# ============================================================================
# Prerequisites: part1 completed, /mnt/gentoo mounted
# After this script: enter chroot and run gentoo_install_part3_chroot.sh
# ============================================================================

set -euo pipefail
[[ $EUID -ne 0 ]] && echo "ERROR: Must run as root (sudo)" && exit 1

GENTOO="/mnt/gentoo"
MIRROR="https://gentoo.osuosl.org"
STAGE3_DIR="releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc"
STAGE3_FALLBACK="stage3-amd64-desktop-openrc-20260222T170100Z.tar.xz"
MACHINE="beelink-minis-n5095"
CONFIG_STAGE="/root/${MACHINE}-configs"

# Auto-discover latest stage3
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

# Config files location — prefer git repo on live USB home, fall back to VTOYEFI
REPO=""
for candidate in \
    /home/liveuser/ai/gentoo-machines \
    /home/liveuser/gentoo-machines \
    /run/media/liveuser/VTOYEFI/gentoo-machines; do
    [[ -d "$candidate" ]] && REPO="$candidate" && break
done
if [[ -z "$REPO" ]]; then
    echo "ERROR: gentoo-machines repo not found. Clone or mount it first."
    echo "  Tried: /home/liveuser/ai/gentoo-machines, /home/liveuser/gentoo-machines, Ventoy"
    exit 1
fi
CONFIGS="$REPO/machines/$MACHINE"

echo "=== Gentoo Install Part 2: Stage3 + Chroot Prep ==="
echo "    Machine: Beelink MINI S (N5095A)"
echo "    Repo:    $REPO"
echo "    Configs: $CONFIGS"
echo ""

# ============================================================================
# PRE-FLIGHT
# ============================================================================
for mp in "$GENTOO" "$GENTOO/boot" "$GENTOO/boot/efi"; do
    if ! mountpoint -q "$mp"; then
        echo "ERROR: $mp is not mounted. Run part1 first."
        exit 1
    fi
done
echo "[OK] Filesystems mounted."

if [[ ! -d "$CONFIGS" ]]; then
    echo "ERROR: Config directory $CONFIGS not found in repo."
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
tar xpf "$STAGE3_FILE" --xattrs-include='*.*' --numeric-owner -C "$GENTOO"
echo "  [OK] Stage3 extracted."

rm -f "$STAGE3_FILE" "${STAGE3_FILE}.DIGESTS"
echo "  Cleaned up downloaded files."
echo ""

# ============================================================================
# STEP 4: COPY CONFIGURATION FILES
# ============================================================================
echo "[STEP 4] Installing configuration files..."

mkdir -p "$GENTOO$CONFIG_STAGE"

# --- make.conf ---
cp "$CONFIGS/make.conf" "$GENTOO/etc/portage/make.conf"
echo "  [OK] make.conf"

# --- package.env + env directory ---
cp "$CONFIGS/package.env" "$GENTOO/etc/portage/package.env"
echo "  [OK] package.env"
mkdir -p "$GENTOO/etc/portage/env"
cp "$CONFIGS/portage_env_notmpfs.conf" "$GENTOO/etc/portage/env/notmpfs.conf"
echo "  [OK] env/notmpfs.conf"

# --- Kernel config script ---
cp "$CONFIGS/kernel_config.sh" "$GENTOO$CONFIG_STAGE/"
chmod +x "$GENTOO$CONFIG_STAGE/kernel_config.sh"
echo "  [OK] kernel_config.sh -> $CONFIG_STAGE/"

# --- Surface Pro 6 .config as base (no direct Beelink predecessor) ---
SP6_CONFIG="$REPO/machines/surface-pro-6/.config"
if [[ -f "$SP6_CONFIG" ]]; then
    cp "$SP6_CONFIG" "$GENTOO$CONFIG_STAGE/base.config"
    echo "  [OK] SP6 .config -> $CONFIG_STAGE/base.config (base for kernel_config.sh)"
else
    echo "  [WARN] SP6 base .config not found — will need defconfig or manual copy"
fi

# --- World file ---
cp "$CONFIGS/world" "$GENTOO$CONFIG_STAGE/world"
echo "  [OK] world -> $CONFIG_STAGE/"

# --- GRUB defaults ---
cp "$CONFIGS/grub" "$GENTOO$CONFIG_STAGE/grub"
echo "  [OK] grub -> $CONFIG_STAGE/"

# --- sysctl tuning ---
mkdir -p "$GENTOO/etc/sysctl.d"
cp "$CONFIGS/sysctl-performance.conf" "$GENTOO/etc/sysctl.d/99-beelink-minis-performance.conf"
echo "  [OK] sysctl-performance.conf -> /etc/sysctl.d/"

# --- zram-init config ---
cp "$CONFIGS/zram-init.conf" "$GENTOO$CONFIG_STAGE/zram-init.conf"
echo "  [OK] zram-init.conf -> $CONFIG_STAGE/"

# --- machine package.use ---
mkdir -p "$GENTOO/etc/portage/package.use"
cp "$CONFIGS/package.use" "$GENTOO/etc/portage/package.use/$MACHINE"
echo "  [OK] package.use -> package.use/$MACHINE"

# --- machine package.accept_keywords ---
mkdir -p "$GENTOO/etc/portage/package.accept_keywords"
cp "$CONFIGS/package.accept_keywords" "$GENTOO/etc/portage/package.accept_keywords/$MACHINE"
echo "  [OK] package.accept_keywords -> package.accept_keywords/$MACHINE"

# --- Shared portage files ---
if [[ -f "$REPO/shared/package.use" ]]; then
    cp "$REPO/shared/package.use" "$GENTOO/etc/portage/package.use/shared"
    echo "  [OK] shared/package.use"
fi
if [[ -f "$REPO/shared/package.accept_keywords" ]]; then
    cp "$REPO/shared/package.accept_keywords" "$GENTOO/etc/portage/package.accept_keywords/shared"
    echo "  [OK] shared/package.accept_keywords"
fi
if [[ -f "$REPO/shared/package.license" ]]; then
    mkdir -p "$GENTOO/etc/portage/package.license"
    cp "$REPO/shared/package.license" "$GENTOO/etc/portage/package.license/shared"
    echo "  [OK] shared/package.license"
fi

# --- Shared desktop restore scripts ---
for script in restore-desktop.sh restore-system.sh xfce4-keybindings.sh xfce4-panel.sh; do
    if [[ -f "$REPO/shared/$script" ]]; then
        cp "$REPO/shared/$script" "$GENTOO$CONFIG_STAGE/"
        echo "  [OK] $script -> $CONFIG_STAGE/"
    fi
done

# --- OpenRC services reference ---
if [[ -f "$REPO/shared/openrc-services" ]]; then
    cp "$REPO/shared/openrc-services" "$GENTOO$CONFIG_STAGE/"
    echo "  [OK] openrc-services -> $CONFIG_STAGE/"
fi

# --- KSM startup script ---
if [[ -f "$REPO/shared/ksm.start" ]]; then
    mkdir -p "$GENTOO/etc/local.d"
    cp "$REPO/shared/ksm.start" "$GENTOO/etc/local.d/ksm.start"
    chmod +x "$GENTOO/etc/local.d/ksm.start"
    echo "  [OK] ksm.start -> /etc/local.d/"
fi

# --- fstrim weekly (SATA SSD TRIM) ---
if [[ -f "$REPO/shared/fstrim-weekly" ]]; then
    mkdir -p "$GENTOO/etc/local.d"
    cp "$REPO/shared/fstrim-weekly" "$GENTOO/etc/local.d/fstrim-weekly.start"
    chmod +x "$GENTOO/etc/local.d/fstrim-weekly.start"
    echo "  [OK] fstrim-weekly -> /etc/local.d/"
fi

# --- LightDM config (shared, no HiDPI on this box) ---
if [[ -f "$REPO/shared/lightdm.conf" ]]; then
    cp "$REPO/shared/lightdm.conf" "$GENTOO$CONFIG_STAGE/lightdm.conf"
    echo "  [OK] shared lightdm.conf -> $CONFIG_STAGE/"
fi

# --- Chroot install script ---
cp "$CONFIGS/gentoo_install_part3_chroot.sh" "$GENTOO/root/"
chmod +x "$GENTOO/root/gentoo_install_part3_chroot.sh"
echo "  [OK] gentoo_install_part3_chroot.sh -> /root/"

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
UUID_EFI=$(blkid -s UUID -o value /dev/sda1 2>/dev/null || echo 'UNKNOWN')
UUID_BOOT=$(blkid -s UUID -o value /dev/sda2 2>/dev/null || echo 'UNKNOWN')
UUID_ROOT=$(blkid -s UUID -o value /dev/sda3 2>/dev/null || echo 'UNKNOWN')
echo "  EFI  (sda1): $UUID_EFI"
echo "  BOOT (sda2): $UUID_BOOT"
echo "  ROOT (sda3): $UUID_ROOT"
echo ""

cat > "$GENTOO$CONFIG_STAGE/disk-uuids.txt" << EOF
UUID_EFI=$UUID_EFI
UUID_BOOT=$UUID_BOOT
UUID_ROOT=$UUID_ROOT
EOF
echo "  [OK] UUIDs saved to $CONFIG_STAGE/disk-uuids.txt"
echo ""

# ============================================================================
# STEP 9: GENERATE FSTAB
# ============================================================================
echo "[STEP 9] Generating /etc/fstab..."

cat > "$GENTOO/etc/fstab" << FSTAB
# /etc/fstab - Beelink MINI S (N5095A) Gentoo
# Generated by gentoo_install_part2.sh

# <device>                                <mount>          <fs>   <opts>                                                 <dump> <pass>
UUID=$UUID_ROOT                            /                ext4   defaults,noatime                                        0      1
UUID=$UUID_BOOT                            /boot            ext4   defaults,noatime                                        0      2
UUID=$UUID_EFI                             /boot/efi        vfat   defaults,noatime,umask=0077                             0      0

# Portage tmpfs — 4GB (8GB RAM machine, keep half for system)
# Large packages redirected to disk via package.env
tmpfs                                      /var/tmp/portage tmpfs  size=4G,uid=portage,gid=portage,mode=775,nosuid,noatime,nodev 0 0
FSTAB

echo "  [OK] /etc/fstab generated with UUIDs (use fstrim for SATA SSD TRIM)."
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
echo "Config files staged at $CONFIG_STAGE/:"
ls -la "$GENTOO$CONFIG_STAGE/" 2>/dev/null || true
echo ""
echo "Once inside the chroot, run:"
echo "  bash /root/gentoo_install_part3_chroot.sh"
