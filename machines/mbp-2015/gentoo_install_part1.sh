#!/bin/bash
# ============================================================================
# gentoo_install_part1.sh - Wipe & Partition APPLE SSD SM0256G
# MacBook Pro 12,1 - Run from Fedora 43 Live USB
# ============================================================================
# Uses: parted, mkfs.vfat, mkfs.ext4 (all available on Fedora live)
#
# Target layout on /dev/sda (233.8GB):
#   sda1  512MB   EFI System Partition  (FAT32)   -> /boot/efi
#   sda2  1GB     Boot partition        (ext4)    -> /boot
#   sda3  ~232GB  Root partition        (ext4)    -> /
#   No swap partition - using zram (8GB compressed in RAM)
# ============================================================================

set -euo pipefail

TARGET="/dev/sda"

# ============================================================================
# PRE-FLIGHT: Verify tools exist
# ============================================================================
echo "=== Gentoo Install Part 1: Disk Wipe & Partition ==="
echo ""

MISSING=()
for tool in parted mkfs.ext4 blkid mount lsblk partprobe; do
    command -v "$tool" &>/dev/null || MISSING+=("$tool")
done

# mkfs.vfat is in dosfstools - not guaranteed on all live images
if ! command -v mkfs.vfat &>/dev/null; then
    echo "mkfs.vfat not found. Installing dosfstools..."
    dnf install -y dosfstools 2>/dev/null || MISSING+=("mkfs.vfat (dosfstools)")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "ERROR: Missing tools: ${MISSING[*]}"
    echo "Try: sudo dnf install ${MISSING[*]}"
    exit 1
fi
echo "[OK] All required tools found."
echo ""

# ============================================================================
# PRE-FLIGHT: Verify target disk
# ============================================================================
echo "[PRE-FLIGHT] Current disk layout:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL "$TARGET"
echo ""

# Check nothing on the target is mounted
MOUNTED=$(mount | grep "^${TARGET}" || true)
if [[ -n "$MOUNTED" ]]; then
    echo "WARNING: Partitions on $TARGET are currently mounted:"
    echo "$MOUNTED"
    echo ""
    read -p "Unmount them automatically? (y/N): " umount_confirm
    if [[ "$umount_confirm" == "y" || "$umount_confirm" == "Y" ]]; then
        for part in "${TARGET}"*; do
            umount "$part" 2>/dev/null || true
        done
        echo "  Unmounted."
    else
        echo "Unmount manually and re-run."
        exit 1
    fi
    echo ""
fi

echo "*** THIS WILL DESTROY ALL DATA ON $TARGET ***"
echo "    Model: $(cat /sys/block/sda/device/model 2>/dev/null || echo 'unknown')"
echo ""
read -p "Type 'YES' to proceed: " confirm
if [[ "$confirm" != "YES" ]]; then
    echo "Aborted."
    exit 0
fi

# ============================================================================
# STEP 1: WIPE & CREATE NEW GPT TABLE
# ============================================================================
echo ""
echo "[STEP 1] Creating fresh GPT partition table on $TARGET..."

# mklabel wipes existing table and creates new GPT
parted -s "$TARGET" mklabel gpt

echo "  GPT table created."
echo ""

# ============================================================================
# STEP 2: CREATE PARTITIONS
# ============================================================================
echo "[STEP 2] Creating partitions..."

# sda1: 512MB EFI System Partition
parted -s "$TARGET" mkpart "EFI" fat32 1MiB 513MiB
parted -s "$TARGET" set 1 esp on
echo "  sda1: 512MB EFI System Partition (esp flag set)"

# sda2: 1GB Boot partition
parted -s "$TARGET" mkpart "BOOT" ext4 513MiB 1537MiB
echo "  sda2: 1GB Boot partition"

# sda3: Remaining space for root
parted -s "$TARGET" mkpart "ROOT" ext4 1537MiB 100%
echo "  sda3: ~232GB Root partition"

echo ""

# Let kernel pick up the new table
partprobe "$TARGET" 2>/dev/null || true
sleep 2

# ============================================================================
# STEP 3: VERIFY LAYOUT
# ============================================================================
echo "[STEP 3] Verifying partition layout..."
parted -s "$TARGET" print
echo ""
lsblk -o NAME,SIZE,TYPE,PARTLABEL "$TARGET"
echo ""

read -p "Layout look correct? (y/N): " layout_ok
if [[ "$layout_ok" != "y" && "$layout_ok" != "Y" ]]; then
    echo "Aborted. Partitions created but not formatted."
    echo "Wipe and start over with: parted -s $TARGET mklabel gpt"
    exit 1
fi

# ============================================================================
# STEP 4: FORMAT PARTITIONS
# ============================================================================
echo "[STEP 4] Formatting partitions..."

echo "  Formatting ${TARGET}1 as FAT32 (EFI)..."
mkfs.vfat -F 32 -n EFI "${TARGET}1"

echo "  Formatting ${TARGET}2 as ext4 (boot)..."
mkfs.ext4 -L BOOT -q "${TARGET}2"

echo "  Formatting ${TARGET}3 as ext4 (root)..."
mkfs.ext4 -L ROOT -q "${TARGET}3"

echo ""
echo "  All partitions formatted."
echo ""

# ============================================================================
# STEP 5: FINAL LAYOUT
# ============================================================================
echo "[STEP 5] Final disk layout:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTLABEL,LABEL "$TARGET"
echo ""

echo "UUIDs (save these for fstab):"
echo "  EFI  (sda1): $(blkid -s UUID -o value "${TARGET}1")"
echo "  BOOT (sda2): $(blkid -s UUID -o value "${TARGET}2")"
echo "  ROOT (sda3): $(blkid -s UUID -o value "${TARGET}3")"
echo ""

# ============================================================================
# STEP 6: MOUNT FOR GENTOO INSTALL
# ============================================================================
echo "[STEP 6] Mounting for Gentoo installation..."

mkdir -p /mnt/gentoo
mount "${TARGET}3" /mnt/gentoo
echo "  ${TARGET}3 -> /mnt/gentoo"

mkdir -p /mnt/gentoo/boot
mount "${TARGET}2" /mnt/gentoo/boot
echo "  ${TARGET}2 -> /mnt/gentoo/boot"

mkdir -p /mnt/gentoo/boot/efi
mount "${TARGET}1" /mnt/gentoo/boot/efi
echo "  ${TARGET}1 -> /mnt/gentoo/boot/efi"

echo ""
echo "=== Disk ready for Gentoo installation ==="
echo ""
df -h /mnt/gentoo /mnt/gentoo/boot /mnt/gentoo/boot/efi
echo ""
echo "Next: download and extract the stage3 tarball to /mnt/gentoo"
