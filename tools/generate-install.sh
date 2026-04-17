#!/bin/bash
# ============================================================================
# generate-install.sh — Generate Gentoo install scripts for a new machine
# ============================================================================
# Produces a starting-point skeleton for:
#   machines/<new-machine>/gentoo_install_part1.sh        (disk partitioning)
#   machines/<new-machine>/gentoo_install_part2.sh        (stage3 + chroot prep)
#   machines/<new-machine>/gentoo_install_part3_chroot.sh (13-phase build)
#
# Feature-gates common blocks using tools/machine-profile.sh flags
# (HAS_NVIDIA_GPU, WIFI_DRIVER, BT_DRIVER, IS_LAPTOP, PLATFORM, BOOT_DRIVE_TYPE,
# HAS_SAM, etc.). Machine-unique quirks (Dell GuC, Apple applesmc, HiDPI,
# SABRENT USB exclusion) are left as TODO comments for hand-edit post-gen.
#
# Usage:
#   tools/generate-install.sh <new-machine> <base-machine> <harvest-dir>
#
# Example:
#   sudo tools/harvest.sh   # on the target, produces hardware_inventory.log
#   tools/generate-install.sh precision-7960 precision-t5810 /tmp/7960-harvest/
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

# --- Helpers ------------------------------------------------------------------
info()  { echo -e "\033[1;32m>>>\033[0m $*"; }
warn()  { echo -e "\033[1;33m>>>\033[0m $*"; }
error() { echo -e "\033[1;31m>>>\033[0m $*" >&2; exit 1; }

usage() {
    cat <<'USAGE'
Usage: tools/generate-install.sh <new-machine> <base-machine> <harvest-dir>

Arguments:
  new-machine   Directory name under machines/ (e.g., precision-7960)
  base-machine  Existing machine for hardware class reference (e.g., precision-t5810)
  harvest-dir   Directory with hardware_inventory.log and deep_harvest.log

Output:
  machines/<new-machine>/gentoo_install_part1.sh
  machines/<new-machine>/gentoo_install_part2.sh           (Phase 3 — TBD)
  machines/<new-machine>/gentoo_install_part3_chroot.sh    (Phase 4 — TBD)
USAGE
    exit 1
}

# --- Args ---------------------------------------------------------------------
[[ $# -eq 3 ]] || usage

NEW_MACHINE="$1"
BASE_MACHINE="$2"
HARVEST_DIR="$3"

BASE_DIR="${REPO_DIR}/machines/${BASE_MACHINE}"
NEW_DIR="${REPO_DIR}/machines/${NEW_MACHINE}"
HARVEST="${HARVEST_DIR%/}/hardware_inventory.log"

# --- Validate -----------------------------------------------------------------
[[ -d "$BASE_DIR" ]] || error "Base machine not found: $BASE_DIR"
[[ -f "$HARVEST" ]]  || error "Harvest log not found: $HARVEST"

# --- Load machine profile -----------------------------------------------------
# shellcheck source=./machine-profile.sh
HARVEST="$HARVEST" source "${SCRIPT_DIR}/machine-profile.sh"

mkdir -p "$NEW_DIR"

info "Generating install scripts for '$NEW_MACHINE' (base: $BASE_MACHINE)"
info "Profile: CPU=$CPU_MODEL_NAME  GPU=I:$HAS_INTEL_GPU/N:$HAS_NVIDIA_GPU/A:$HAS_AMD_GPU"
info "         WiFi=$WIFI_DRIVER  BT=$BT_DRIVER  Storage=$BOOT_DRIVE_TYPE  Platform=$PLATFORM"
info "         Laptop=$IS_LAPTOP  SAM=$HAS_SAM  EDAC=$HAS_EDAC"

# --- Derive machine-specific values -------------------------------------------
# Extract candidate block devices from harvest section 8 (lsblk output).
# This is authoritative — BOOT_DRIVE_TYPE is a heuristic that fails when harvest
# runs on a live USB (the `/` mountpoint is the live medium, not the target).
CANDIDATE_DISKS_RAW=$(awk '/^\[8\. STORAGE/,/^\[9\./' "$HARVEST" | \
    grep -E '^(sd[a-z]|nvme[0-9]+n[0-9]+)[[:space:]]' | \
    awk '{print $1, $NF}' | sort -u)

NVME_CANDIDATES=$(echo "$CANDIDATE_DISKS_RAW" | awk '$1 ~ /^nvme/ {print "/dev/"$1"  ("$2")"}')
SATA_CANDIDATES=$(echo "$CANDIDATE_DISKS_RAW" | awk '$1 ~ /^sd[a-z]/ {print "/dev/"$1"   ("$2")"}')

# Default TARGET: prefer NVMe over SATA when both exist (NVMe is almost always boot)
if [[ -n "$NVME_CANDIDATES" ]]; then
    DEFAULT_TARGET=$(echo "$NVME_CANDIDATES" | head -1 | awk '{print $1}')
    PART_PREFIX_SUFFIX="p"
elif [[ -n "$SATA_CANDIDATES" ]]; then
    DEFAULT_TARGET=$(echo "$SATA_CANDIDATES" | head -1 | awk '{print $1}')
    PART_PREFIX_SUFFIX=""
else
    # Fallback to profile heuristic if section 8 could not be parsed
    case "$BOOT_DRIVE_TYPE" in
        nvme) DEFAULT_TARGET="/dev/nvme0n1"; PART_PREFIX_SUFFIX="p" ;;
        *)    DEFAULT_TARGET="/dev/sda";     PART_PREFIX_SUFFIX=""  ;;
    esac
    warn "Could not parse disks from harvest — defaulting to $DEFAULT_TARGET. Edit TARGET in part1."
fi

HAS_DUAL_STORAGE=0
[[ -n "$NVME_CANDIDATES" && -n "$SATA_CANDIDATES" ]] && HAS_DUAL_STORAGE=1

# Machine label: human-readable platform + CPU
case "$PLATFORM" in
    dell)    PLATFORM_LABEL="Dell" ;;
    apple)   PLATFORM_LABEL="Apple" ;;
    surface) PLATFORM_LABEL="Microsoft Surface" ;;
    lenovo)  PLATFORM_LABEL="Lenovo" ;;
    hp)      PLATFORM_LABEL="HP" ;;
    asus)    PLATFORM_LABEL="ASUS" ;;
    *)       PLATFORM_LABEL="$NEW_MACHINE" ;;
esac

# --- Emit part1 ---------------------------------------------------------------
emit_part1() {
    local out="$1"

    # Header / config block (interpolates)
    cat > "$out" <<HEADER
#!/bin/bash
# ============================================================================
# gentoo_install_part1.sh - Partition ${BOOT_DRIVE_TYPE^^} disk for ${PLATFORM_LABEL} / ${NEW_MACHINE}
# Run from Gentoo or Fedora live USB
# ============================================================================
# Target layout on \${TARGET}:
#   part1  600MB   EFI System Partition  (FAT32)   -> /boot/efi
#   part2  2GB     Boot partition        (ext4)    -> /boot
#   part3  rest    Root partition        (ext4)    -> /
#   No swap partition — zram is configured in part3.
#
# PRE-REQUISITES:
#   - Secure Boot disabled in firmware
#   - Booted from a live USB (Gentoo minimal or Fedora)
#   - Network connected
# ============================================================================
# Generated by tools/generate-install.sh from base '${BASE_MACHINE}'.
# Review all TODOs before running. This is a starting skeleton, not a
# production-ready script — verify TARGET, partition sizes, and any
# machine-specific safety blocks (e.g., boot-media exclusions).
# ============================================================================

set -euo pipefail
[[ \$EUID -ne 0 ]] && echo "ERROR: Must run as root (sudo)" && exit 1

# --- Disks detected in harvest (for reference) -------------------------------
$(
    echo "# (parsed from harvest section [8. STORAGE])"
    [[ -n "$NVME_CANDIDATES" ]] && echo "$NVME_CANDIDATES" | sed 's/^/#   NVMe: /'
    [[ -n "$SATA_CANDIDATES" ]] && echo "$SATA_CANDIDATES" | sed 's/^/#   SATA: /'
    [[ $HAS_DUAL_STORAGE -eq 1 ]] && cat <<'DUAL_NOTE'
# NOTE: Both NVMe and SATA disks were detected. Defaulting TARGET to NVMe.
#       If the secondary disk is intended as storage (e.g., /data), mount it
#       manually in part2 and add an fstab entry. Do NOT partition it here.
DUAL_NOTE
)

# --- Machine-specific config (edit these) ------------------------------------
TARGET="${DEFAULT_TARGET}"
PART_PREFIX="\${TARGET}${PART_PREFIX_SUFFIX}"
EFI_END_MIB=601
BOOT_END_MIB=2649

HEADER

    # Platform-specific safety block (USB boot-media exclusion)
    if [[ "$PLATFORM" == "dell" && "$IS_LAPTOP" == "0" ]]; then
        cat >> "$out" <<'SAFETY_DELL'
# --- TODO: boot-media exclusion ----------------------------------------------
# On workstations booting from a known USB, add an explicit device-ID guard.
# Example (Precision T5810 with SABRENT Ventoy USB):
#   VENTOY_USB_ID="SABRENT_DD56419883896"
#   TARGET_DEVICE_ID=$(udevadm info --query=property --name="$TARGET" | grep ^ID_SERIAL=)
#   echo "$TARGET_DEVICE_ID" | grep -q "$VENTOY_USB_ID" && \
#       { echo "FATAL: Target is boot USB"; exit 99; }

SAFETY_DELL
    fi

    # Universal pre-flight and partition body (no interpolation needed)
    cat >> "$out" <<'BODY'
# ============================================================================
# PRE-FLIGHT: Verify tools exist
# ============================================================================
echo "=== Gentoo Install Part 1: Disk Wipe & Partition ==="
echo "    Target: $TARGET"
echo ""

MISSING=()
for tool in parted mkfs.ext4 mkfs.vfat blkid mount lsblk partprobe; do
    command -v "$tool" &>/dev/null || MISSING+=("$tool")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "ERROR: Missing tools: ${MISSING[*]}"
    echo "On Fedora: dnf install -y parted e2fsprogs dosfstools util-linux"
    exit 1
fi
echo "[OK] All required tools found."
echo ""

# ============================================================================
# SAFETY: Target must exist, not be USB, not be Ventoy
# ============================================================================
[[ -b "$TARGET" ]] || { echo "ERROR: $TARGET does not exist"; lsblk; exit 1; }

TARGET_TRAN=$(lsblk -ndo TRAN "$TARGET" 2>/dev/null || echo unknown)
if [[ "$TARGET_TRAN" == "usb" ]]; then
    echo "ERROR: $TARGET reports transport=usb — refusing to wipe install media."
    exit 1
fi

TARGET_MODEL=$(lsblk -ndo MODEL "$TARGET" 2>/dev/null || echo unknown)
if [[ "$TARGET_MODEL" == *Ventoy* ]] || [[ "$TARGET_MODEL" == *VTOY* ]]; then
    echo "ERROR: $TARGET model is '$TARGET_MODEL' — refusing to wipe install media."
    exit 1
fi

echo "[PRE-FLIGHT] Target disk identity:"
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
    read -p "Unmount them automatically? (y/N): " umount_confirm
    if [[ "$umount_confirm" == "y" || "$umount_confirm" == "Y" ]]; then
        for part in "${PART_PREFIX}"*; do
            umount "$part" 2>/dev/null || true
        done
        # Common live-USB mount points
        umount /mnt/fedora/boot /mnt/fedora /mnt/gentoo/boot/efi /mnt/gentoo/boot /mnt/gentoo 2>/dev/null || true
        echo "  Unmounted."
    else
        echo "Unmount manually and re-run."
        exit 1
    fi
    echo ""
fi

echo "*** THIS WILL DESTROY ALL DATA ON $TARGET ***"
echo "    Model: $TARGET_MODEL"
read -p "Type 'YES' to proceed: " confirm
[[ "$confirm" != "YES" ]] && { echo "Aborted."; exit 0; }

# ============================================================================
# STEP 1: Create fresh GPT partition table
# ============================================================================
echo ""
echo "[STEP 1] Creating fresh GPT partition table on $TARGET..."
parted -s "$TARGET" mklabel gpt
echo "  GPT table created."
echo ""

# ============================================================================
# STEP 2: Create partitions
# ============================================================================
echo "[STEP 2] Creating partitions..."
parted -s "$TARGET" mkpart "EFI"  fat32 1MiB ${EFI_END_MIB}MiB
parted -s "$TARGET" set 1 esp on
echo "  part1: 600MB EFI System Partition (esp flag set)"

parted -s "$TARGET" mkpart "BOOT" ext4  ${EFI_END_MIB}MiB ${BOOT_END_MIB}MiB
echo "  part2: 2GB Boot partition"

parted -s "$TARGET" mkpart "ROOT" ext4  ${BOOT_END_MIB}MiB 100%
echo "  part3: remainder for Root partition"
echo ""

partprobe "$TARGET" 2>/dev/null || true
sleep 2

# ============================================================================
# STEP 3: Verify layout
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
# STEP 4: Format partitions
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
# STEP 5: Report UUIDs
# ============================================================================
echo "[STEP 5] Final disk layout:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTLABEL,LABEL "$TARGET"
echo ""

echo "UUIDs (saved for part2 fstab generation):"
echo "  EFI  (${PART_PREFIX}1): $(blkid -s UUID -o value "${PART_PREFIX}1")"
echo "  BOOT (${PART_PREFIX}2): $(blkid -s UUID -o value "${PART_PREFIX}2")"
echo "  ROOT (${PART_PREFIX}3): $(blkid -s UUID -o value "${PART_PREFIX}3")"
echo ""

for part in "${PART_PREFIX}1" "${PART_PREFIX}2" "${PART_PREFIX}3"; do
    UUID=$(blkid -s UUID -o value "$part" 2>/dev/null || true)
    if [[ -z "$UUID" ]]; then
        echo "ERROR: $part has no UUID — format may have failed"
        exit 1
    fi
done
echo "[OK] All partitions verified."
echo ""

# ============================================================================
# STEP 6: Mount for Gentoo install
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
df -h /mnt/gentoo /mnt/gentoo/boot /mnt/gentoo/boot/efi
echo ""
echo "Next: run gentoo_install_part2.sh"
BODY

    chmod +x "$out"
}

# --- Emit stubs for part2 / part3 (TBD in later phases) -----------------------
emit_part2_stub() {
    cat > "$1" <<STUB
#!/bin/bash
# TODO: generate-install.sh Phase 3 has not been implemented yet.
# Copy machines/${BASE_MACHINE}/gentoo_install_part2.sh and edit by hand for now.
echo "part2 is not yet generated — use base machine as reference"
exit 1
STUB
    chmod +x "$1"
}

emit_part3_stub() {
    cat > "$1" <<STUB
#!/bin/bash
# TODO: generate-install.sh Phase 4 has not been implemented yet.
# Copy machines/${BASE_MACHINE}/gentoo_install_part3_chroot.sh and edit by hand for now.
echo "part3 is not yet generated — use base machine as reference"
exit 1
STUB
    chmod +x "$1"
}

# --- Drive --------------------------------------------------------------------
emit_part1       "${NEW_DIR}/gentoo_install_part1.sh"
emit_part2_stub  "${NEW_DIR}/gentoo_install_part2.sh"
emit_part3_stub  "${NEW_DIR}/gentoo_install_part3_chroot.sh"

info ""
info "Generated:"
info "  ${NEW_DIR}/gentoo_install_part1.sh         (ready — review TODOs)"
info "  ${NEW_DIR}/gentoo_install_part2.sh         (STUB — Phase 3 TBD)"
info "  ${NEW_DIR}/gentoo_install_part3_chroot.sh  (STUB — Phase 4 TBD)"
info ""
info "Review the part1 header config block (TARGET, partition sizes) before running."
