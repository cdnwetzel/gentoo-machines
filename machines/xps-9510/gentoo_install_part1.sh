#!/bin/bash
# ============================================================================
# gentoo_install_part1.sh - Wipe & Partition Dual Samsung 990 PRO NVMe
# Dell XPS 15 9510 - Run from Live USB (Fedora/Gentoo minimal)
# ============================================================================
# Uses: parted, mkfs.vfat, mkfs.ext4 (all available on live images)
#
# Target layout:
#   nvme0n1 (Samsung 990 PRO 1TB) — Gentoo OS
#     nvme0n1p1  512MB   EFI System Partition  (FAT32)   -> /boot/efi
#     nvme0n1p2  ~930GB  Root partition        (ext4)    -> /
#     No swap partition — using zram (8GB compressed zstd in RAM)
#
#   nvme1n1 (Samsung 990 PRO 1TB) — Data
#     nvme1n1p1  ~931GB  Data partition        (ext4)    -> /data
#
# PRE-REQUISITES:
#   - Booted from Live USB
#   - WiFi connected (NetworkManager)
# ============================================================================

set -euo pipefail

OS_DISK="/dev/nvme0n1"
DATA_DISK="/dev/nvme1n1"
OS_PREFIX="${OS_DISK}p"
DATA_PREFIX="${DATA_DISK}p"

# ============================================================================
# PRE-FLIGHT: Verify tools exist
# ============================================================================
echo "=== Gentoo Install Part 1: Disk Wipe & Partition ==="
echo "    Target: Dell XPS 15 9510 / Dual Samsung 990 PRO NVMe"
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
    exit 1
fi
echo "[OK] All required tools found."
echo ""

# ============================================================================
# PRE-FLIGHT: Verify both NVMe disks exist
# ============================================================================
for disk in "$OS_DISK" "$DATA_DISK"; do
    if [[ ! -b "$disk" ]]; then
        echo "ERROR: $disk does not exist. Check lsblk output:"
        lsblk
        exit 1
    fi
done

echo "[PRE-FLIGHT] Current disk layout:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL "$OS_DISK" "$DATA_DISK"
echo ""

# Check nothing is mounted from target disks
for prefix in "$OS_PREFIX" "$DATA_PREFIX"; do
    MOUNTED=$(mount | grep "^${prefix}" || true)
    if [[ -n "$MOUNTED" ]]; then
        echo "WARNING: Partitions on ${prefix%p} are currently mounted:"
        echo "$MOUNTED"
        echo ""
        read -p "Unmount them automatically? (y/N): " umount_confirm
        if [[ "$umount_confirm" == "y" || "$umount_confirm" == "Y" ]]; then
            for part in "${prefix}"*; do
                [[ -b "$part" ]] && umount "$part" 2>/dev/null || true
            done
            echo "  Unmounted."
        else
            echo "Unmount manually and re-run."
            exit 1
        fi
        echo ""
    fi
done

echo "*** THIS WILL DESTROY ALL DATA ON BOTH NVMe DRIVES ***"
echo "    OS disk:   $OS_DISK"
echo "    Data disk: $DATA_DISK"
echo ""
read -p "Type 'YES' to proceed: " confirm
if [[ "$confirm" != "YES" ]]; then
    echo "Aborted."
    exit 0
fi

# ============================================================================
# STEP 1: WIPE & CREATE GPT TABLES
# ============================================================================
echo ""
echo "[STEP 1] Creating fresh GPT partition tables..."

parted -s "$OS_DISK" mklabel gpt
echo "  $OS_DISK: GPT table created."

parted -s "$DATA_DISK" mklabel gpt
echo "  $DATA_DISK: GPT table created."
echo ""

# ============================================================================
# STEP 2: CREATE PARTITIONS — OS DISK
# ============================================================================
echo "[STEP 2a] Creating partitions on $OS_DISK (Gentoo root)..."

# nvme0n1p1: 512MB EFI System Partition
parted -s "$OS_DISK" mkpart "EFI" fat32 1MiB 513MiB
parted -s "$OS_DISK" set 1 esp on
echo "  nvme0n1p1: 512MB EFI System Partition (esp flag set)"

# nvme0n1p2: Remaining space for root
parted -s "$OS_DISK" mkpart "ROOT" ext4 513MiB 100%
echo "  nvme0n1p2: ~930GB Root partition"

echo ""

# ============================================================================
# STEP 2b: CREATE PARTITIONS — DATA DISK
# ============================================================================
echo "[STEP 2b] Creating partitions on $DATA_DISK (data)..."

# nvme1n1p1: Full disk for data
parted -s "$DATA_DISK" mkpart "DATA" ext4 1MiB 100%
echo "  nvme1n1p1: ~931GB Data partition"

echo ""

# Let kernel pick up the new tables
partprobe "$OS_DISK" 2>/dev/null || true
partprobe "$DATA_DISK" 2>/dev/null || true
sleep 2

# ============================================================================
# STEP 3: VERIFY LAYOUT
# ============================================================================
echo "[STEP 3] Verifying partition layout..."
echo "--- OS Disk ---"
parted -s "$OS_DISK" print
echo ""
echo "--- Data Disk ---"
parted -s "$DATA_DISK" print
echo ""
lsblk -o NAME,SIZE,TYPE,PARTLABEL "$OS_DISK" "$DATA_DISK"
echo ""

read -p "Layout look correct? (y/N): " layout_ok
if [[ "$layout_ok" != "y" && "$layout_ok" != "Y" ]]; then
    echo "Aborted. Partitions created but not formatted."
    exit 1
fi

# ============================================================================
# STEP 4: FORMAT PARTITIONS
# ============================================================================
echo "[STEP 4] Formatting partitions..."

echo "  Formatting ${OS_PREFIX}1 as FAT32 (EFI)..."
mkfs.vfat -F 32 -n EFI "${OS_PREFIX}1"

echo "  Formatting ${OS_PREFIX}2 as ext4 (root)..."
mkfs.ext4 -L GENTOO -q "${OS_PREFIX}2"

echo "  Formatting ${DATA_PREFIX}1 as ext4 (data)..."
mkfs.ext4 -L DATA -q "${DATA_PREFIX}1"

echo ""
echo "  All partitions formatted."
echo ""

# ============================================================================
# STEP 5: FINAL LAYOUT
# ============================================================================
echo "[STEP 5] Final disk layout:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTLABEL,LABEL "$OS_DISK" "$DATA_DISK"
echo ""

echo "UUIDs (save these for fstab):"
echo "  EFI    (nvme0n1p1): $(blkid -s UUID -o value "${OS_PREFIX}1")"
echo "  ROOT   (nvme0n1p2): $(blkid -s UUID -o value "${OS_PREFIX}2")"
echo "  DATA   (nvme1n1p1): $(blkid -s UUID -o value "${DATA_PREFIX}1")"
echo ""

# ============================================================================
# STEP 6: MOUNT FOR GENTOO INSTALL
# ============================================================================
echo "[STEP 6] Mounting for Gentoo installation..."

mkdir -p /mnt/gentoo
mount "${OS_PREFIX}2" /mnt/gentoo
echo "  ${OS_PREFIX}2 -> /mnt/gentoo"

mkdir -p /mnt/gentoo/boot/efi
mount "${OS_PREFIX}1" /mnt/gentoo/boot/efi
echo "  ${OS_PREFIX}1 -> /mnt/gentoo/boot/efi"

mkdir -p /mnt/gentoo/data
mount "${DATA_PREFIX}1" /mnt/gentoo/data
echo "  ${DATA_PREFIX}1 -> /mnt/gentoo/data"

echo ""
echo "=== Disks ready for Gentoo installation ==="
echo ""
df -h /mnt/gentoo /mnt/gentoo/boot/efi /mnt/gentoo/data
echo ""
echo "Next: run gentoo_install_part2.sh"
