#!/bin/bash
# ============================================================================
# gentoo_install_part1.sh - Wipe & Partition SATA SSD on /dev/sda
# Beelink MINI S (N5095A) - Run from Fedora 43 Live USB (Ventoy)
# ============================================================================
# Target layout on /dev/sda (238.5 GiB M.2 SATA SSD):
#   sda1  600MB   EFI System Partition  (FAT32)   -> /boot/efi
#   sda2  2GB     Boot partition        (ext4)    -> /boot
#   sda3  ~235GB  Root partition        (ext4)    -> /
#   No swap partition — using zram (4 GB compressed zstd in RAM)
#
# PRE-REQUISITES:
#   - Secure Boot already disabled (verified in AMI JTKT001 BIOS)
#   - Booted from Fedora 43 live USB via Ventoy
#   - Ethernet or WiFi connected
#
# CRITICAL: Board has TWO block devices — /dev/sda (internal SATA SSD) and
#           /dev/sdb (Ventoy USB). DO NOT TOUCH sdb. Script guards against it.
# ============================================================================

set -euo pipefail
[[ $EUID -ne 0 ]] && echo "ERROR: Must run as root (sudo)" && exit 1

TARGET="/dev/sda"
PART_PREFIX="${TARGET}"      # SATA: /dev/sda1, /dev/sda2, /dev/sda3

# ============================================================================
# PRE-FLIGHT: Verify tools exist
# ============================================================================
echo "=== Gentoo Install Part 1: Disk Wipe & Partition ==="
echo "    Target: Beelink MINI S / M.2 SATA SSD 238.5GB (/dev/sda)"
echo ""

MISSING=()
for tool in parted mkfs.ext4 blkid mount lsblk partprobe; do
    command -v "$tool" &>/dev/null || MISSING+=("$tool")
done

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
# PRE-FLIGHT: Guard against nuking the Ventoy USB
# ============================================================================
if [[ ! -b "$TARGET" ]]; then
    echo "ERROR: $TARGET does not exist. Check lsblk output:"
    lsblk
    exit 1
fi

# Refuse to run if /dev/sda looks like a USB stick (safety guard)
TARGET_TRAN=$(lsblk -ndo TRAN "$TARGET" 2>/dev/null || echo unknown)
if [[ "$TARGET_TRAN" == "usb" ]]; then
    echo "ERROR: $TARGET reports transport=usb — this looks like the Ventoy stick."
    echo "       Refusing to wipe. Verify with: lsblk -o NAME,TRAN,MODEL,SIZE"
    exit 1
fi

# Refuse if model contains "Ventoy" or "VTOY"
TARGET_MODEL=$(lsblk -ndo MODEL "$TARGET" 2>/dev/null || echo unknown)
if [[ "$TARGET_MODEL" == *Ventoy* ]] || [[ "$TARGET_MODEL" == *VTOY* ]]; then
    echo "ERROR: $TARGET model is '$TARGET_MODEL' — refusing to wipe install media."
    exit 1
fi

echo "[PRE-FLIGHT] Target disk identity check:"
echo "  Device:    $TARGET"
echo "  Model:     $TARGET_MODEL"
echo "  Transport: $TARGET_TRAN"
echo ""
echo "[PRE-FLIGHT] Current disk layout:"
lsblk -o NAME,SIZE,TYPE,TRAN,FSTYPE,MOUNTPOINT,MODEL "$TARGET"
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
        umount /mnt/fedora/boot 2>/dev/null || true
        umount /mnt/fedora 2>/dev/null || true
        echo "  Unmounted."
    else
        echo "Unmount manually and re-run."
        exit 1
    fi
    echo ""
fi

echo "*** THIS WILL DESTROY ALL DATA ON $TARGET ***"
echo "    Model: $TARGET_MODEL"
echo "    This will erase Fedora 43 and all data on the internal SSD."
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

# sda1: 600 MB EFI System Partition
parted -s "$TARGET" mkpart "EFI" fat32 1MiB 601MiB
parted -s "$TARGET" set 1 esp on
echo "  sda1: 600MB EFI System Partition (esp flag set)"

# sda2: 2 GB boot partition
parted -s "$TARGET" mkpart "BOOT" ext4 601MiB 2649MiB
echo "  sda2: 2GB Boot partition"

# sda3: remaining space for root
parted -s "$TARGET" mkpart "ROOT" ext4 2649MiB 100%
echo "  sda3: ~235GB Root partition"

echo ""

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
echo "  EFI  (sda1): $(blkid -s UUID -o value "${PART_PREFIX}1")"
echo "  BOOT (sda2): $(blkid -s UUID -o value "${PART_PREFIX}2")"
echo "  ROOT (sda3): $(blkid -s UUID -o value "${PART_PREFIX}3")"
echo ""

for part in "${PART_PREFIX}1" "${PART_PREFIX}2" "${PART_PREFIX}3"; do
    UUID=$(blkid -s UUID -o value "$part" 2>/dev/null || true)
    if [[ -z "$UUID" ]]; then
        echo "ERROR: $part has no UUID — format may have failed"
        echo "  Try: partprobe && blkid $part"
        exit 1
    fi
done
echo "[OK] All partitions verified."
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
