#!/bin/bash
# ============================================================================
# gentoo_install_part2.sh - Download stage3, extract, configure, chroot
# MacBook Pro 12,1 - Run from Fedora 43 Live USB
# ============================================================================
# Prerequisites: part1 completed, /mnt/gentoo mounted
#
# Uses: wget (confirmed available), tar, mount, chroot
# ============================================================================

set -euo pipefail

GENTOO="/mnt/gentoo"
MIRROR="https://gentoo.osuosl.org"
STAGE3_DIR="releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc"
STAGE3_FILE="stage3-amd64-desktop-openrc-20260222T170100Z.tar.xz"
STAGE3_URL="${MIRROR}/${STAGE3_DIR}/${STAGE3_FILE}"
DIGESTS_URL="${STAGE3_URL}.DIGESTS"

# Where our config files live (on the Ventoy USB)
CONFIGS="/run/media/liveuser/VTOYEFI/mbp2015"

echo "=== Gentoo Install Part 2: Stage3 + Chroot ==="
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
echo "[OK] Filesystems mounted."

# Verify config files exist
if [[ ! -d "$CONFIGS" ]]; then
    echo "WARNING: Config directory $CONFIGS not found."
    echo "Config files will need to be copied manually."
    CONFIGS=""
fi
echo ""

# ============================================================================
# STEP 1: DOWNLOAD STAGE3
# ============================================================================
echo "[STEP 1] Downloading stage3 tarball..."
echo "  URL: $STAGE3_URL"
echo "  Size: ~703MB"
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

# Extract expected SHA512 from DIGESTS file and verify
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

if [[ -n "$CONFIGS" ]]; then
    # make.conf
    if [[ -f "$CONFIGS/make.conf" ]]; then
        cp "$CONFIGS/make.conf" "$GENTOO/etc/portage/make.conf"
        echo "  [OK] make.conf"
    fi

    # package.env + env directory
    if [[ -f "$CONFIGS/package.env" ]]; then
        cp "$CONFIGS/package.env" "$GENTOO/etc/portage/package.env"
        echo "  [OK] package.env"
    fi
    if [[ -f "$CONFIGS/portage_env_notmpfs.conf" ]]; then
        mkdir -p "$GENTOO/etc/portage/env"
        cp "$CONFIGS/portage_env_notmpfs.conf" "$GENTOO/etc/portage/env/notmpfs.conf"
        echo "  [OK] env/notmpfs.conf"
    fi

    # mbpfan config
    if [[ -f "$CONFIGS/mbpfan.conf" ]]; then
        cp "$CONFIGS/mbpfan.conf" "$GENTOO/etc/mbpfan.conf"
        echo "  [OK] mbpfan.conf"
    fi

    # Kernel config script
    if [[ -f "$CONFIGS/kernel_config_mbp121.sh" ]]; then
        cp "$CONFIGS/kernel_config_mbp121.sh" "$GENTOO/root/kernel_config_mbp121.sh"
        chmod +x "$GENTOO/root/kernel_config_mbp121.sh"
        echo "  [OK] kernel_config_mbp121.sh -> /root/"
    fi

    # WiFi firmware fix
    if [[ -f "$CONFIGS/wifi_firmware_fix.sh" ]]; then
        cp "$CONFIGS/wifi_firmware_fix.sh" "$GENTOO/root/wifi_firmware_fix.sh"
        chmod +x "$GENTOO/root/wifi_firmware_fix.sh"
        echo "  [OK] wifi_firmware_fix.sh -> /root/"
    fi

    # Post-install reference
    if [[ -f "$CONFIGS/post_install_setup.sh" ]]; then
        cp "$CONFIGS/post_install_setup.sh" "$GENTOO/root/post_install_setup.sh"
        chmod +x "$GENTOO/root/post_install_setup.sh"
        echo "  [OK] post_install_setup.sh -> /root/"
    fi
else
    echo "  WARNING: No config directory found. Copy files manually."
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
# STEP 7: CREATE PORTAGE TMPFS DIRECTORIES
# ============================================================================
echo "[STEP 7] Creating portage build directories..."
mkdir -p "$GENTOO/var/tmp/portage"
mkdir -p "$GENTOO/var/tmp/portage-disk"
echo "  [OK] /var/tmp/portage and /var/tmp/portage-disk created."
echo ""

# ============================================================================
# STEP 8: GRAB UUIDs (retry now that disk has settled)
# ============================================================================
echo "[STEP 8] Partition UUIDs for fstab:"
echo "  EFI  (sda1): $(blkid -s UUID -o value /dev/sda1 2>/dev/null || echo 'run blkid manually')"
echo "  BOOT (sda2): $(blkid -s UUID -o value /dev/sda2 2>/dev/null || echo 'run blkid manually')"
echo "  ROOT (sda3): $(blkid -s UUID -o value /dev/sda3 2>/dev/null || echo 'run blkid manually')"
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
echo "  export PS1='(chroot) \[\033[0;31m\]\u@\h \[\033[0;36m\]\w \$ \[\033[0m\]'"
echo ""
echo "Once inside the chroot, the next steps are:"
echo "  1. emerge-webrsync              # sync portage tree"
echo "  2. eselect profile list         # verify desktop/openrc profile"
echo "  3. emerge --ask --verbose --update --deep --newuse @world"
echo "  4. Set timezone, locale, fstab"
echo "  5. emerge gentoo-sources        # kernel source"
echo "  6. cd /usr/src/linux && make defconfig"
echo "  7. bash /root/kernel_config_mbp121.sh"
echo "  8. make menuconfig && make -j5"
echo "  9. Install bootloader (rEFInd or GRUB)"
echo ""
