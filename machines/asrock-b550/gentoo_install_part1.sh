#!/bin/bash
# ============================================================================
# gentoo_install_part1.sh - Partition MAXIO MAP1202 2TB NVMe
# ASRock B550 Phantom Gaming-ITX/ax - Run from Fedora 43 Live USB
# ============================================================================
# Uses: parted, mkfs.vfat, mkfs.ext4 (all available on Fedora live)
#
# Target layout on /dev/nvme0n1 (MAXIO MAP1202 2TB):
#   nvme0n1p1  600MB   EFI System Partition  (FAT32)   -> /boot/efi
#   nvme0n1p2  1GB     Boot partition         (ext4)    -> /boot
#   nvme0n1p3  ~1.8TB  Root partition         (ext4)    -> /
#   No swap partition — using zram (8GB compressed zstd in 64GB RAM)
#
# The 1TB SATA SSD (sda) is intentionally LEFT ALONE.
#
# PRE-REQUISITES:
#   - Booted from Fedora 43 live USB
#   - Network connected (Ethernet or WiFi)
#
# ============================================================================
# MACHINE CONFIG — B550-specific values at top, universal logic below
# ============================================================================
TARGET="/dev/nvme0n1"
PART_PREFIX="${TARGET}p"
MACHINE_NAME="ASRock B550"
DISK_MODEL="MAXIO MAP1202 2TB NVMe"
EFI_SIZE_MIB=600       # 600MB EFI
BOOT_SIZE_MIB=1024     # 1GB boot
# Root uses remaining space (~1.8TB)

# SATA SSD — not touched during install
SATA_DEVICE="/dev/sda"
# ============================================================================

set -euo pipefail
[[ $EUID -ne 0 ]] && echo "ERROR: Must run as root (sudo)" && exit 1

echo "=== Gentoo Install Part 1: Disk Wipe & Partition ==="
echo "    Target: $MACHINE_NAME / $DISK_MODEL"
echo ""

# ============================================================================
# SAFETY: Verify we're targeting the NVMe, not the SATA or USB
# ============================================================================
echo "[SAFETY] Target validation..."
if [[ "$TARGET" != /dev/nvme* ]]; then
    echo "FATAL: Target $TARGET is not an NVMe device."
    exit 99
fi

# Verify SATA SSD won't be touched
if [[ -b "$SATA_DEVICE" ]]; then
    echo "  [OK] SATA SSD at $SATA_DEVICE detected — will NOT be touched."
else
    echo "  [INFO] SATA SSD not detected at $SATA_DEVICE."
fi

# Find and protect USB boot media
USB_DEV=$(lsblk -no NAME,TRAN 2>/dev/null | grep 'usb' | awk '{print $1}' | head -1 || true)
if [[ -n "$USB_DEV" ]]; then
    echo "  [OK] USB device at /dev/$USB_DEV — will NOT be touched."
fi
echo "  [OK] Target $TARGET is safe (NVMe)."
echo ""

# ============================================================================
# PRE-FLIGHT: Verify tools exist
# ============================================================================
MISSING=()
for tool in parted mkfs.ext4 blkid mount lsblk partprobe udevadm; do
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
# PRE-FLIGHT: Verify target disk exists
# ============================================================================
if [[ ! -b "$TARGET" ]]; then
    echo "ERROR: $TARGET does not exist. Check lsblk output:"
    lsblk
    exit 1
fi

echo "[PRE-FLIGHT] Current disk layout:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL "$TARGET"
echo ""

# Show what we're about to destroy
echo "[PRE-FLIGHT] Current partition table on $TARGET:"
parted -s "$TARGET" print 2>/dev/null || echo "  (no partition table)"
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
            [[ -b "$part" ]] && umount "$part" 2>/dev/null || true
        done
        echo "  Unmounted."
    else
        echo "Unmount manually and re-run."
        exit 1
    fi
    echo ""
fi

MODEL=$(cat /sys/block/"$(basename "$TARGET")"/device/model 2>/dev/null | tr -s ' ' || echo 'unknown')
echo "*** THIS WILL DESTROY ALL DATA ON $TARGET ***"
echo "    Model: $MODEL"
echo "    Size:  $(lsblk -no SIZE "$TARGET" | head -1)"
echo "    This will erase Fedora + Windows + all data on the NVMe."
echo "    SATA SSD ($SATA_DEVICE) will NOT be touched."
echo ""
echo "    New layout:"
echo "      ${PART_PREFIX}1  ${EFI_SIZE_MIB}MB  EFI (FAT32)  -> /boot/efi"
echo "      ${PART_PREFIX}2  ${BOOT_SIZE_MIB}MB  Boot (ext4)  -> /boot"
echo "      ${PART_PREFIX}3  rest    Root (ext4)  -> /"
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

BOOT_START=$((EFI_SIZE_MIB + 1))
ROOT_START=$((BOOT_START + BOOT_SIZE_MIB))

# nvme0n1p1: EFI System Partition
parted -s "$TARGET" mkpart "EFI" fat32 1MiB "${BOOT_START}MiB"
parted -s "$TARGET" set 1 esp on
echo "  ${PART_PREFIX}1: ${EFI_SIZE_MIB}MB EFI System Partition (esp flag set)"

# nvme0n1p2: Boot partition
parted -s "$TARGET" mkpart "BOOT" ext4 "${BOOT_START}MiB" "${ROOT_START}MiB"
echo "  ${PART_PREFIX}2: ${BOOT_SIZE_MIB}MB Boot partition"

# nvme0n1p3: Remaining space for root
parted -s "$TARGET" mkpart "ROOT" ext4 "${ROOT_START}MiB" 100%
echo "  ${PART_PREFIX}3: ~1.8TB Root partition"

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
echo "  EFI  (${PART_PREFIX}1): $(blkid -s UUID -o value "${PART_PREFIX}1" 2>/dev/null || echo 'NOT FOUND')"
echo "  BOOT (${PART_PREFIX}2): $(blkid -s UUID -o value "${PART_PREFIX}2" 2>/dev/null || echo 'NOT FOUND')"
echo "  ROOT (${PART_PREFIX}3): $(blkid -s UUID -o value "${PART_PREFIX}3" 2>/dev/null || echo 'NOT FOUND')"
echo ""

# Validate partitions have valid UUIDs
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
