#!/bin/bash
# ============================================================================
# gentoo_install_part1.sh - Wipe & Partition SK hynix BC501 NVMe
# Microsoft Surface Pro 6 - Run from Fedora 43 Live USB (Ventoy)
# ============================================================================
# Uses: parted, mkfs.vfat, mkfs.ext4 (all available on Fedora live)
#
# Target layout on /dev/nvme0n1 (238.5GB):
#   nvme0n1p1  512MB   EFI System Partition  (FAT32)   -> /boot/efi
#   nvme0n1p2  1GB     Boot partition        (ext4)    -> /boot
#   nvme0n1p3  ~237GB  Root partition        (ext4)    -> /
#   No swap partition - using zram (4GB compressed zstd in RAM)
#
# PRE-REQUISITES:
#   - Secure Boot DISABLED in Surface UEFI (hold Volume Up + Power)
#   - Booted from Fedora 43 live USB
#   - WiFi connected (NetworkManager)
# ============================================================================

set -euo pipefail

TARGET="/dev/nvme0n1"
PART_PREFIX="${TARGET}p"

# ============================================================================
# PRE-FLIGHT: Verify tools exist
# ============================================================================
echo "=== Gentoo Install Part 1: Disk Wipe & Partition ==="
echo "    Target: Surface Pro 6 / SK hynix BC501 NVMe 238.5GB"
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
# PRE-FLIGHT: Verify target disk is NVMe
# ============================================================================
if [[ ! -b "$TARGET" ]]; then
    echo "ERROR: $TARGET does not exist. Check lsblk output:"
    lsblk
    exit 1
fi

echo "[PRE-FLIGHT] Current disk layout:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL "$TARGET"
echo ""

# Check nothing on the target is mounted
MOUNTED=$(mount | grep "^${PART_PREFIX}" || true)
if [[ -n "$MOUNTED" ]]; then
    echo "WARNING: Partitions on $TARGET are currently mounted:"
    echo "$MOUNTED"
    echo ""
    read -p "Unmount them automatically? (y/N): " umount_confirm
    if [[ "$umount_confirm" == "y" || "$umount_confirm" == "Y" ]]; then
        for part in "${PART_PREFIX}"*; do
            umount "$part" 2>/dev/null || true
        done
        # Also unmount if mounted from previous Fedora session
        umount /mnt/fedora/boot 2>/dev/null || true
        umount /mnt/fedora 2>/dev/null || true
        echo "  Unmounted."
    else
        echo "Unmount manually and re-run."
        exit 1
    fi
    echo ""
fi

MODEL=$(cat /sys/block/nvme0n1/device/model 2>/dev/null || echo 'unknown')
echo "*** THIS WILL DESTROY ALL DATA ON $TARGET ***"
echo "    Model: $MODEL"
echo "    This will erase Fedora 43 + linux-surface and all data."
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

parted -s "$TARGET" mklabel gpt

echo "  GPT table created."
echo ""

# ============================================================================
# STEP 2: CREATE PARTITIONS
# ============================================================================
echo "[STEP 2] Creating partitions..."

# nvme0n1p1: 512MB EFI System Partition
parted -s "$TARGET" mkpart "EFI" fat32 1MiB 513MiB
parted -s "$TARGET" set 1 esp on
echo "  nvme0n1p1: 512MB EFI System Partition (esp flag set)"

# nvme0n1p2: 1GB Boot partition
parted -s "$TARGET" mkpart "BOOT" ext4 513MiB 1537MiB
echo "  nvme0n1p2: 1GB Boot partition"

# nvme0n1p3: Remaining space for root
parted -s "$TARGET" mkpart "ROOT" ext4 1537MiB 100%
echo "  nvme0n1p3: ~237GB Root partition"

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

echo "  Formatting ${PART_PREFIX}1 as FAT32 (EFI)..."
mkfs.vfat -F 32 -n EFI "${PART_PREFIX}1"

echo "  Formatting ${PART_PREFIX}2 as ext4 (boot)..."
mkfs.ext4 -L BOOT -q "${PART_PREFIX}2"

echo "  Formatting ${PART_PREFIX}3 as ext4 (root)..."
mkfs.ext4 -L ROOT -q "${PART_PREFIX}3"

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
echo "  EFI  (nvme0n1p1): $(blkid -s UUID -o value "${PART_PREFIX}1")"
echo "  BOOT (nvme0n1p2): $(blkid -s UUID -o value "${PART_PREFIX}2")"
echo "  ROOT (nvme0n1p3): $(blkid -s UUID -o value "${PART_PREFIX}3")"
echo ""

# ============================================================================
# STEP 6: MOUNT FOR GENTOO INSTALL
# ============================================================================
echo "[STEP 6] Mounting for Gentoo installation..."

mkdir -p /mnt/gentoo
mount "${PART_PREFIX}3" /mnt/gentoo
echo "  ${PART_PREFIX}3 -> /mnt/gentoo"

mkdir -p /mnt/gentoo/boot
mount "${PART_PREFIX}2" /mnt/gentoo/boot
echo "  ${PART_PREFIX}2 -> /mnt/gentoo/boot"

mkdir -p /mnt/gentoo/boot/efi
mount "${PART_PREFIX}1" /mnt/gentoo/boot/efi
echo "  ${PART_PREFIX}1 -> /mnt/gentoo/boot/efi"

echo ""
echo "=== Disk ready for Gentoo installation ==="
echo ""
df -h /mnt/gentoo /mnt/gentoo/boot /mnt/gentoo/boot/efi
echo ""
echo "Next: run gentoo_install_part2.sh"
