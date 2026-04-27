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

# --- Emit part2 ---------------------------------------------------------------
emit_part2() {
    local out="$1"

    cat > "$out" <<HEADER
#!/bin/bash
# ============================================================================
# gentoo_install_part2.sh - Stage3 + chroot prep
# ${PLATFORM_LABEL} / ${NEW_MACHINE} - Run from live USB after part1
# ============================================================================
# Prerequisites: part1 completed, /mnt/gentoo mounted
# After this: enter chroot and run gentoo_install_part3_chroot.sh
# ============================================================================
# Generated by tools/generate-install.sh from base '${BASE_MACHINE}'.
# Config file copies are conditional — only files present in the machine's
# directory (machines/${NEW_MACHINE}/) are copied. Hand-edit the fstab tmpfs
# sizing and any dual-storage entries before running.
# ============================================================================

set -euo pipefail
[[ \$EUID -ne 0 ]] && echo "ERROR: Must run as root (sudo)" && exit 1

GENTOO="/mnt/gentoo"
MIRROR="https://gentoo.osuosl.org"
STAGE3_DIR="releases/amd64/autobuilds/current-stage3-amd64-desktop-openrc"
STAGE3_FALLBACK="stage3-amd64-desktop-openrc-20260222T170100Z.tar.xz"
MACHINE="${NEW_MACHINE}"
CONFIG_STAGE="/root/\${MACHINE}-configs"

# Target disk (must match part1). PART_PREFIX handles nvme "p" vs sata bare.
TARGET="${DEFAULT_TARGET}"
PART_PREFIX="\${TARGET}${PART_PREFIX_SUFFIX}"

HEADER

    cat >> "$out" <<'BODY'
# ============================================================================
# Auto-discover latest stage3 (fallback to hardcoded on offline)
# ============================================================================
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

# Locate gentoo-machines repo on the live USB
REPO=""
for candidate in \
    /home/liveuser/ai/gentoo-machines \
    /home/liveuser/gentoo-machines \
    /home/chris/ai/gentoo-machines \
    /run/media/liveuser/VTOYEFI/gentoo-machines; do
    [[ -d "$candidate" ]] && REPO="$candidate" && break
done
if [[ -z "$REPO" ]]; then
    echo "ERROR: gentoo-machines repo not found. Clone or mount it first."
    exit 1
fi
CONFIGS="$REPO/machines/$MACHINE"

echo "=== Gentoo Install Part 2: Stage3 + Chroot Prep ==="
echo "    Machine: $MACHINE"
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

[[ -d "$CONFIGS" ]] || { echo "ERROR: $CONFIGS not found in repo."; exit 1; }
echo "[OK] Config files found at $CONFIGS."
echo ""

# ============================================================================
# STEP 1: DOWNLOAD STAGE3
# ============================================================================
echo "[STEP 1] Downloading stage3 tarball..."
echo "  URL: $STAGE3_URL"
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
    echo "  WARNING: Could not extract SHA512 — proceeding without verification."
fi
echo ""

# ============================================================================
# STEP 3: EXTRACT STAGE3
# ============================================================================
echo "[STEP 3] Extracting stage3 to $GENTOO..."
tar xpf "$STAGE3_FILE" --xattrs-include='*.*' --numeric-owner -C "$GENTOO"
echo "  [OK] Stage3 extracted."
rm -f "$STAGE3_FILE" "${STAGE3_FILE}.DIGESTS"
echo ""

# ============================================================================
# STEP 4: COPY CONFIGURATION FILES
# ============================================================================
echo "[STEP 4] Installing configuration files..."
mkdir -p "$GENTOO$CONFIG_STAGE"

# Copy a file from $CONFIGS to a target path if it exists.
copy_if_exists() {
    local src="$1" dst="$2" label="${3:-$(basename "$1")}"
    if [[ -f "$src" ]]; then
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        echo "  [OK] $label"
    fi
}

# --- Portage config (make.conf + env) ---
copy_if_exists "$CONFIGS/make.conf"                 "$GENTOO/etc/portage/make.conf"               "make.conf"
copy_if_exists "$CONFIGS/package.env"               "$GENTOO/etc/portage/package.env"             "package.env"
copy_if_exists "$CONFIGS/portage_env_notmpfs.conf"  "$GENTOO/etc/portage/env/notmpfs.conf"        "env/notmpfs.conf"
copy_if_exists "$CONFIGS/package.use"               "$GENTOO/etc/portage/package.use/$MACHINE"    "package.use -> $MACHINE"
copy_if_exists "$CONFIGS/package.accept_keywords"   "$GENTOO/etc/portage/package.accept_keywords/$MACHINE" "package.accept_keywords -> $MACHINE"

# --- Kernel config + world + grub staged for chroot ---
copy_if_exists "$CONFIGS/kernel_config.sh"          "$GENTOO$CONFIG_STAGE/kernel_config.sh"       "kernel_config.sh"
[[ -f "$GENTOO$CONFIG_STAGE/kernel_config.sh" ]] && chmod +x "$GENTOO$CONFIG_STAGE/kernel_config.sh"

# Stage kconfig-lint.sh so phase 2 can validate kernel_config.sh against the running kernel source
if [[ -f "$REPO/tools/kconfig-lint.sh" ]]; then
    cp "$REPO/tools/kconfig-lint.sh" "$GENTOO$CONFIG_STAGE/kconfig-lint.sh"
    chmod +x "$GENTOO$CONFIG_STAGE/kconfig-lint.sh"
    echo "  [OK] kconfig-lint.sh"
fi
copy_if_exists "$CONFIGS/world"                     "$GENTOO$CONFIG_STAGE/world"                  "world"
copy_if_exists "$CONFIGS/grub"                      "$GENTOO$CONFIG_STAGE/grub"                   "grub"
copy_if_exists "$CONFIGS/zram-init.conf"            "$GENTOO$CONFIG_STAGE/zram-init.conf"         "zram-init.conf"

# --- sysctl tuning (name varies per machine; check both forms) ---
if [[ -f "$CONFIGS/sysctl-performance.conf" ]]; then
    mkdir -p "$GENTOO/etc/sysctl.d"
    cp "$CONFIGS/sysctl-performance.conf" "$GENTOO/etc/sysctl.d/99-$MACHINE-performance.conf"
    echo "  [OK] sysctl-performance.conf -> /etc/sysctl.d/"
fi

BODY

    # Platform-gated config copies
    if [[ "$PLATFORM" == "apple" ]]; then
        cat >> "$out" <<'APPLE'
# --- Apple-specific config ---
copy_if_exists "$CONFIGS/mbpfan.conf"               "$GENTOO/etc/mbpfan.conf"                     "mbpfan.conf"
copy_if_exists "$CONFIGS/wifi_firmware_fix.sh"      "$GENTOO$CONFIG_STAGE/wifi_firmware_fix.sh"   "wifi_firmware_fix.sh"
[[ -f "$GENTOO$CONFIG_STAGE/wifi_firmware_fix.sh" ]] && chmod +x "$GENTOO$CONFIG_STAGE/wifi_firmware_fix.sh"

APPLE
    fi

    if [[ "$PLATFORM" == "surface" ]]; then
        cat >> "$out" <<'SURFACE'
# --- Surface-specific config (HiDPI, touch/pen, WiFi reload) ---
for f in hidpi-setup.sh Xresources xrandr-dpi.desktop lightdm-gtk-greeter.conf \
         lightdm-display-setup.sh lightdm.conf iptsd.conf iptsd-device.conf \
         50-iptsd.rules mwifiex.conf wifi-powersave.conf wifi-reload.sh; do
    copy_if_exists "$CONFIGS/$f" "$GENTOO$CONFIG_STAGE/$f" "$f"
done

SURFACE
    fi

    if [[ "$HAS_NVIDIA_GPU" == "1" ]]; then
        cat >> "$out" <<'NVIDIA'
# --- NVIDIA-specific config ---
copy_if_exists "$CONFIGS/prime-run"                 "$GENTOO$CONFIG_STAGE/prime-run"              "prime-run (NVIDIA PRIME wrapper)"
copy_if_exists "$CONFIGS/99-module-rebuild.install" "$GENTOO$CONFIG_STAGE/99-module-rebuild.install" "99-module-rebuild.install"

NVIDIA
    fi

    if [[ "$IS_LAPTOP" == "1" ]]; then
        cat >> "$out" <<'LAPTOP'
# --- Laptop-specific config ---
copy_if_exists "$CONFIGS/tlp.conf"                  "$GENTOO/etc/tlp.conf"                        "tlp.conf"
copy_if_exists "$CONFIGS/30-touchpad.conf"          "$GENTOO/etc/X11/xorg.conf.d/30-touchpad.conf" "30-touchpad.conf"

LAPTOP
    fi

    # Shared files + chroot script + DNS/mount phases (universal tail)
    cat >> "$out" <<'TAIL'
# --- Shared portage files ---
for f in package.use package.accept_keywords package.license; do
    copy_if_exists "$REPO/shared/$f" "$GENTOO/etc/portage/$f/shared" "shared/$f"
done

# --- Shared desktop restore scripts ---
for f in restore-desktop.sh restore-system.sh xfce4-keybindings.sh xfce4-panel.sh openrc-services; do
    copy_if_exists "$REPO/shared/$f" "$GENTOO$CONFIG_STAGE/$f" "shared/$f"
done

# --- Shared startup hooks ---
if [[ -f "$REPO/shared/ksm.start" ]]; then
    mkdir -p "$GENTOO/etc/local.d"
    cp "$REPO/shared/ksm.start" "$GENTOO/etc/local.d/ksm.start"
    chmod +x "$GENTOO/etc/local.d/ksm.start"
    echo "  [OK] ksm.start -> /etc/local.d/"
fi
if [[ -f "$REPO/shared/fstrim-weekly" ]]; then
    mkdir -p "$GENTOO/etc/local.d"
    cp "$REPO/shared/fstrim-weekly" "$GENTOO/etc/local.d/fstrim-weekly.start"
    chmod +x "$GENTOO/etc/local.d/fstrim-weekly.start"
    echo "  [OK] fstrim-weekly -> /etc/local.d/"
fi
if [[ -f "$REPO/shared/35-intel-microcode.install" ]]; then
    mkdir -p "$GENTOO/etc/kernel/preinst.d"
    cp "$REPO/shared/35-intel-microcode.install" "$GENTOO/etc/kernel/preinst.d/35-intel-microcode.install"
    chmod +x "$GENTOO/etc/kernel/preinst.d/35-intel-microcode.install"
    echo "  [OK] 35-intel-microcode.install -> /etc/kernel/preinst.d/"
fi

# --- LightDM config (shared) ---
copy_if_exists "$REPO/shared/lightdm.conf"          "$GENTOO$CONFIG_STAGE/lightdm.conf"           "shared lightdm.conf"
copy_if_exists "$REPO/shared/logind.conf"           "$GENTOO$CONFIG_STAGE/logind.conf"            "shared logind.conf"

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
mount --rbind /sys "$GENTOO/sys";  mount --make-rslave "$GENTOO/sys"
mount --rbind /dev "$GENTOO/dev";  mount --make-rslave "$GENTOO/dev"
mount --bind  /run "$GENTOO/run";  mount --make-slave  "$GENTOO/run"
echo "  [OK] proc, sys, dev, run mounted."
echo ""

# ============================================================================
# STEP 7: PORTAGE BUILD DIRECTORIES
# ============================================================================
echo "[STEP 7] Creating portage build directories..."
mkdir -p "$GENTOO/var/tmp/portage" "$GENTOO/var/tmp/portage-disk"
echo "  [OK] /var/tmp/portage and /var/tmp/portage-disk created."
echo ""

# ============================================================================
# STEP 8: GRAB UUIDs
# ============================================================================
echo "[STEP 8] Partition UUIDs for fstab:"
UUID_EFI=$(blkid -s UUID -o value "${PART_PREFIX}1" 2>/dev/null || echo 'UNKNOWN')
UUID_BOOT=$(blkid -s UUID -o value "${PART_PREFIX}2" 2>/dev/null || echo 'UNKNOWN')
UUID_ROOT=$(blkid -s UUID -o value "${PART_PREFIX}3" 2>/dev/null || echo 'UNKNOWN')
echo "  EFI  (${PART_PREFIX}1): $UUID_EFI"
echo "  BOOT (${PART_PREFIX}2): $UUID_BOOT"
echo "  ROOT (${PART_PREFIX}3): $UUID_ROOT"
echo ""

cat > "$GENTOO$CONFIG_STAGE/disk-uuids.txt" <<EOF
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
# NOTE: Hand-edit tmpfs size below to fit the machine's RAM. 4G is safe for
# 8GB-RAM boxes; larger machines can afford 8-46GB.
cat > "$GENTOO/etc/fstab" <<FSTAB
# /etc/fstab - $MACHINE Gentoo
# Generated by gentoo_install_part2.sh

# <device>              <mount>          <fs>   <opts>                                                          <dump> <pass>
UUID=$UUID_ROOT         /                ext4   defaults,noatime                                                 0      1
UUID=$UUID_BOOT         /boot            ext4   defaults,noatime                                                 0      2
UUID=$UUID_EFI          /boot/efi        vfat   defaults,noatime,umask=0077                                      0      0

# Portage tmpfs — adjust size= to half of system RAM minimum
tmpfs                   /var/tmp/portage tmpfs  size=4G,uid=portage,gid=portage,mode=775,nosuid,noatime,nodev   0 0
# TODO: if this machine has a secondary data disk, add a UUID entry for it here.
FSTAB
echo "  [OK] /etc/fstab generated (review tmpfs size)."
echo ""

# ============================================================================
# DONE
# ============================================================================
echo "============================================================"
echo "=== Ready to chroot into Gentoo! ==="
echo "============================================================"
echo ""
echo "Enter the chroot:"
echo "  sudo chroot $GENTOO /bin/bash"
echo "  source /etc/profile"
echo '  export PS1="(chroot) \[\033[0;31m\]\u@\h \[\033[0;36m\]\w \$ \[\033[0m\]"'
echo ""
echo "Then run: bash /root/gentoo_install_part3_chroot.sh"
TAIL

    chmod +x "$out"
}

# --- Emit part3 ---------------------------------------------------------------
emit_part3() {
    local out="$1"

    # Derived values for conditionals
    local is_intel=0
    [[ "$CPU_VENDOR" == "GenuineIntel" ]] && is_intel=1
    local has_bluetooth=0
    [[ -n "$BT_DRIVER" && "$BT_DRIVER" != "generic" ]] && has_bluetooth=1
    local hostname_short="${NEW_MACHINE%%-*}"  # first segment e.g. "asrock" from "asrock-b550"

    cat > "$out" <<HEADER
#!/bin/bash
# ============================================================================
# gentoo_install_part3_chroot.sh - ONE-SHOT chroot install
# ${PLATFORM_LABEL} / ${NEW_MACHINE} - Run INSIDE the chroot
# ============================================================================
# USAGE:
#   sudo chroot /mnt/gentoo /bin/bash
#   source /etc/profile
#   export PS1="(chroot) \$PS1"
#   bash /root/gentoo_install_part3_chroot.sh
# ============================================================================
# Generated by tools/generate-install.sh from base '${BASE_MACHINE}'.
# Review all phases before running. This is a skeleton — machine-specific
# hardware quirks (NVIDIA kernel params, applesmc, HiDPI, Surface IPTS) may
# need hand-editing in Phase 11.
# ============================================================================

# NOTE: no \`-u\` (nounset) — /etc/profile.d files reference unbound vars.
set -eo pipefail

MACHINE="${NEW_MACHINE}"
HOSTNAME_SHORT="${NEW_MACHINE}"
CONFIGS="/root/\${MACHINE}-configs"
TIMEZONE="America/New_York"
read -rp "Username for desktop user [chris]: " USERNAME
USERNAME="\${USERNAME:-chris}"
NPROC=\$(nproc)

echo "============================================================"
echo "=== ${PLATFORM_LABEL} / ${NEW_MACHINE} — One-Shot Chroot Install ==="
echo "============================================================"

if [[ ! -f "\$CONFIGS/kernel_config.sh" ]]; then
    echo "ERROR: Config files not found at \$CONFIGS"
    echo "Are you inside the chroot? Did part2 run?"
    exit 1
fi

HEADER

    # ====== Phase 1: Bootstrap (universal) ======
    cat >> "$out" <<'P1'

# ============================================================================
# PHASE 1: Bootstrap
# ============================================================================
echo ""
echo "=== PHASE 1: Bootstrap ==="

source /etc/profile
export PS1="(chroot) ${PS1:-}"

echo "[1.1] Syncing portage tree..."
emerge-webrsync
emerge --sync

echo "[1.2] Setting profile..."
eselect profile list
eselect profile set default/linux/amd64/23.0

echo "[1.3] Updating @world with USE flags..."
emerge --verbose --update --deep --newuse @world

echo "[OK] Phase 1 complete."
P1

    # ====== Phase 2: Kernel + firmware (gate microcode on Intel) ======
    cat >> "$out" <<'P2A'

# ============================================================================
# PHASE 2: Kernel + Firmware
# ============================================================================
echo ""
echo "=== PHASE 2: Kernel + Firmware ==="

echo "[2.1] Installing kernel sources and firmware..."
P2A

    if [[ $is_intel -eq 1 ]]; then
        cat >> "$out" <<'P2B_INTEL'
emerge --verbose sys-kernel/gentoo-sources \
    sys-kernel/linux-firmware \
    sys-firmware/intel-microcode \
    sys-kernel/installkernel
P2B_INTEL
    else
        cat >> "$out" <<'P2B_AMD'
emerge --verbose sys-kernel/gentoo-sources \
    sys-kernel/linux-firmware \
    sys-kernel/installkernel
# AMD CPU: microcode is shipped via linux-firmware (no separate amd-ucode package)
P2B_AMD
    fi

    cat >> "$out" <<'P2C'

echo "[2.2] Selecting kernel..."
eselect kernel list
eselect kernel set 1
ls -l /usr/src/linux

echo "[2.3] Configuring kernel..."
cd /usr/src/linux
if [[ -f "$CONFIGS/base.config" ]]; then
    cp "$CONFIGS/base.config" .config
    echo "  [OK] Base config copied"
else
    echo "  [INFO] No base.config — starting from defconfig"
    make defconfig
fi

bash "$CONFIGS/kernel_config.sh"

if [[ -x "$CONFIGS/kconfig-lint.sh" ]]; then
    echo ""
    echo "[2.3.5] Linting kernel_config.sh against /usr/src/linux..."
    if ! bash "$CONFIGS/kconfig-lint.sh" "$CONFIGS/kernel_config.sh" /usr/src/linux; then
        echo ""
        echo "  *** kconfig-lint reported FAIL severity issues above. ***"
        echo "  *** Common causes: bool symbol set with --module, unknown symbols, missing parents. ***"
        read -p "  Continue with kernel build anyway? (y/N): " lint_continue
        [[ "$lint_continue" == "y" || "$lint_continue" == "Y" ]] || exit 1
    fi
fi

echo "[2.4] Resolving kernel config dependencies..."
make olddefconfig

echo ""
read -p "Open menuconfig for review? (y/N): " do_menuconfig
if [[ "$do_menuconfig" == "y" || "$do_menuconfig" == "Y" ]]; then
    make menuconfig
fi

echo "[2.5] Building kernel (make -j$NPROC)..."
make -j"$NPROC"

echo "[2.6] Installing kernel modules..."
make modules_install

echo "[2.7] Installing kernel..."
make install

echo "[2.8] Verifying kernel installation..."
ls -la /boot/vmlinuz-* /boot/config-* /boot/System.map-*

echo "[OK] Phase 2 complete."
P2C

    # ====== Phase 3: Bootloader (universal + EFI fallback) ======
    cat >> "$out" <<'P3'

# ============================================================================
# PHASE 3: Bootloader (GRUB)
# ============================================================================
echo ""
echo "=== PHASE 3: Bootloader ==="

echo "[3.1] Installing GRUB..."
emerge --verbose sys-boot/grub

echo "[3.2] Installing GRUB to EFI..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo

# EFI fallback path — some firmwares only boot EFI/Boot/bootx64.efi
echo "[3.2.1] Copying GRUB to EFI fallback path..."
mkdir -p /boot/efi/EFI/Boot
cp /boot/efi/EFI/Gentoo/grubx64.efi /boot/efi/EFI/Boot/bootx64.efi

echo "[3.3] Installing GRUB defaults..."
if [[ -f "$CONFIGS/grub" ]]; then
    cp "$CONFIGS/grub" /etc/default/grub
    echo "  [OK] /etc/default/grub installed"
else
    echo "  [WARN] No grub defaults found — using distribution defaults"
fi

echo "[3.4] Generating GRUB config..."
grub-mkconfig -o /boot/grub/grub.cfg

echo "[3.5] Verifying GRUB sees kernel..."
grep menuentry /boot/grub/grub.cfg

echo "[OK] Phase 3 complete."
P3

    # ====== Phase 4: System config (universal) ======
    cat >> "$out" <<'P4'

# ============================================================================
# PHASE 4: System Configuration
# ============================================================================
echo ""
echo "=== PHASE 4: System Configuration ==="

echo "[4.1] Setting timezone to $TIMEZONE..."
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime

echo "[4.2] Configuring locale..."
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
env-update && source /etc/profile

echo "[4.3] Setting hostname..."
echo "$HOSTNAME_SHORT" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1       localhost
::1             localhost
127.0.1.1       ${HOSTNAME_SHORT}.localdomain ${HOSTNAME_SHORT}
EOF

echo ""
echo "[4.4] Set root password:"
passwd

groupadd -f plugdev

echo "[4.5] Creating user '$USERNAME'..."
useradd -m -G wheel,audio,video,usb,input,plugdev -s /bin/bash "$USERNAME"
echo "Set password for user '$USERNAME':"
passwd "$USERNAME"
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

echo "[4.6] Relaxing pam_faillock (home machine: 10 attempts, 5 min lockout)..."
sed -i 's/pam_faillock.so preauth/pam_faillock.so preauth deny=10 unlock_time=300/' /etc/pam.d/system-auth || true
sed -i 's/pam_faillock.so authfail/pam_faillock.so authfail deny=10 unlock_time=300/' /etc/pam.d/system-auth || true

echo "[OK] Phase 4 complete."
P4

    # ====== Phase 5: Networking (universal) ======
    cat >> "$out" <<'P5'

# ============================================================================
# PHASE 5: Networking
# ============================================================================
echo ""
echo "=== PHASE 5: Networking ==="

echo "[5.1] Installing networking packages..."
emerge --verbose net-wireless/wpa_supplicant \
    net-misc/networkmanager \
    net-misc/dhcpcd \
    gnome-extra/nm-applet \
    net-wireless/wireless-regdb \
    net-wireless/wireless-tools

echo "[5.2] Enabling NetworkManager..."
rc-update add NetworkManager default

echo "[OK] Phase 5 complete."
P5

    # ====== Phase 6: All packages (universal) ======
    cat >> "$out" <<'P6'

# ============================================================================
# PHASE 6: All Remaining Packages
# ============================================================================
echo ""
echo "=== PHASE 6: All Packages ==="

echo "[6.1] Installing world file..."
cp "$CONFIGS/world" /var/lib/portage/world

echo "[6.2] Installing all packages (may take 1-4 hours)..."
emerge --verbose --update --deep --newuse @world

echo ""
echo "[6.3] Merging updated config files..."
dispatch-conf || echo "  [WARN] dispatch-conf failed — run manually"

echo "[OK] Phase 6 complete."
P6

    # ====== Phase 7: Portage infra (universal) ======
    cat >> "$out" <<'P7'

# ============================================================================
# PHASE 7: Portage Infrastructure
# ============================================================================
echo ""
echo "=== PHASE 7: Portage Infrastructure ==="

mkdir -p /var/tmp/portage /var/tmp/portage-disk
chown portage:portage /var/tmp/portage /var/tmp/portage-disk

echo "[7.1] Verifying package.env..."
cat /etc/portage/package.env 2>/dev/null || echo "  [WARN] package.env not found"
cat /etc/portage/env/notmpfs.conf 2>/dev/null || echo "  [WARN] notmpfs.conf not found"

echo "[OK] Phase 7 complete."
P7

    # ====== Phase 8: Services (feature-gated) ======
    cat >> "$out" <<'P8A'

# ============================================================================
# PHASE 8: OpenRC Services
# ============================================================================
echo ""
echo "=== PHASE 8: OpenRC Services ==="

rc-update add dbus default
rc-update add elogind boot
rc-update add acpid default
rc-update add cronie default
rc-update add display-manager default
rc-update add sshd default
rc-update add metalog default
rc-update add local default
rc-update add netmount default
rc-update add zram-init boot
rc-update add alsasound boot
rc-update add chronyd default
P8A

    [[ $has_bluetooth -eq 1 ]]  && echo 'rc-update add bluetooth default' >> "$out"
    [[ $is_intel -eq 1 ]]       && echo 'rc-update add thermald default' >> "$out"
    [[ $IS_LAPTOP -eq 1 ]]      && echo 'rc-update add tlp default' >> "$out"
    [[ "$PLATFORM" == "apple" ]] && echo 'rc-update add mbpfan default' >> "$out"

    cat >> "$out" <<'P8B'

echo "[8.2] Enabling SSH pubkey authentication..."
sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

echo ""
echo "[8.3] Current runlevels:"
echo "  Default:"; rc-update show default
echo "  Boot:";    rc-update show boot

echo "[OK] Phase 8 complete."
P8B

    # ====== Phase 9: Display manager (universal) ======
    cat >> "$out" <<'P9'

# ============================================================================
# PHASE 9: Display Manager (LightDM + XFCE)
# ============================================================================
echo ""
echo "=== PHASE 9: LightDM + XFCE ==="

ls /usr/share/xsessions/ || echo "  [WARN] No xsessions!"

if [[ -f "$CONFIGS/lightdm.conf" ]]; then
    cp "$CONFIGS/lightdm.conf" /etc/lightdm/lightdm.conf
    echo "  [OK] machine lightdm.conf installed"
else
    sed -i 's/^#user-session=.*/user-session=xfce/' /etc/lightdm/lightdm.conf 2>/dev/null || true
    sed -i 's|^#session-wrapper=.*|session-wrapper=/etc/lightdm/Xsession|' /etc/lightdm/lightdm.conf 2>/dev/null || true
fi

sed -i 's/DISPLAYMANAGER=".*"/DISPLAYMANAGER="lightdm"/' /etc/conf.d/display-manager 2>/dev/null || \
    echo 'DISPLAYMANAGER="lightdm"' > /etc/conf.d/display-manager

echo "[OK] Phase 9 complete."
P9

    # ====== Phase 10: Audio (universal) ======
    cat >> "$out" <<'P10'

# ============================================================================
# PHASE 10: PipeWire Audio
# ============================================================================
echo ""
echo "=== PHASE 10: PipeWire Audio ==="

qlist -I media-video/pipewire    && echo "  [OK] PipeWire"    || echo "  [FAIL] PipeWire!"
qlist -I media-video/wireplumber && echo "  [OK] WirePlumber" || echo "  [FAIL] WirePlumber!"
echo "[10.1] PipeWire autostart configured via gentoo-pipewire-launcher (restore-desktop.sh)"

echo "[OK] Phase 10 complete."
P10

    # ====== Phase 11: Machine hardware (feature-gated) ======
    cat >> "$out" <<'P11_HEADER'

# ============================================================================
# PHASE 11: Machine-specific Hardware
# ============================================================================
echo ""
echo "=== PHASE 11: Hardware ==="
P11_HEADER

    if [[ "$HAS_NVIDIA_GPU" == "1" ]]; then
        cat >> "$out" <<'P11_NVIDIA'

echo "[11.1] Configuring NVIDIA..."
if [[ -f "$CONFIGS/99-module-rebuild.install" ]]; then
    mkdir -p /etc/kernel/postinst.d
    cp "$CONFIGS/99-module-rebuild.install" /etc/kernel/postinst.d/99-module-rebuild.install
    chmod +x /etc/kernel/postinst.d/99-module-rebuild.install
fi

cat > /etc/modprobe.d/nvidia.conf <<EOF
options nvidia-drm modeset=1
blacklist nouveau
EOF
# TODO: if this is a laptop with Intel+NVIDIA Optimus, add NVreg_DynamicPowerManagement=0x02
#       and install $CONFIGS/prime-run to /usr/local/bin/

if [[ -f "$CONFIGS/prime-run" ]]; then
    cp "$CONFIGS/prime-run" /usr/local/bin/prime-run
    chmod +x /usr/local/bin/prime-run
    echo "  [OK] prime-run (Optimus) installed"
fi
P11_NVIDIA
    fi

    cat >> "$out" <<'P11_ZRAM_SYSCTL'

echo "[11.x] Configuring zram-init..."
[[ -f "$CONFIGS/zram-init.conf" ]] && cp "$CONFIGS/zram-init.conf" /etc/conf.d/zram-init

echo "[11.x] Installing sysctl tuning..."
[[ -f "$CONFIGS/sysctl-performance.conf" ]] && \
    cp "$CONFIGS/sysctl-performance.conf" /etc/sysctl.d/99-${MACHINE}-performance.conf
P11_ZRAM_SYSCTL

    if [[ "$PLATFORM" == "apple" ]]; then
        cat >> "$out" <<'P11_APPLE'

# --- Apple-specific (mbpfan, applesmc, WiFi firmware fix) ---
echo "[11.x] Applying Apple-specific hardware config..."
[[ -f "$CONFIGS/mbpfan.conf" ]] && cp "$CONFIGS/mbpfan.conf" /etc/mbpfan.conf
if [[ -x "$CONFIGS/wifi_firmware_fix.sh" ]]; then
    bash "$CONFIGS/wifi_firmware_fix.sh" || echo "  [WARN] wifi_firmware_fix.sh non-zero exit"
fi
# TODO: verify applesmc module loads on boot (check dmesg for 'applesmc: 35 sensors found')
P11_APPLE
    fi

    if [[ "$PLATFORM" == "surface" ]]; then
        cat >> "$out" <<'P11_SURFACE'

# --- Surface-specific (HiDPI, IPTSD, WiFi reload on resume) ---
echo "[11.x] Applying Surface-specific hardware config..."
# TODO: install HiDPI setup scripts (Xresources, xrandr-dpi.desktop, lightdm-gtk-greeter.conf)
#       from $CONFIGS/ — see machines/surface-pro-6/gentoo_install_part3_chroot.sh for details.
# TODO: install iptsd.conf + 50-iptsd.rules if touch/pen needed.
# TODO: install mwifiex.conf + wifi-reload.sh for Marvell WiFi resume.
P11_SURFACE
    fi

    if [[ $IS_LAPTOP -eq 0 ]]; then
        cat >> "$out" <<'P11_DESKTOP'

# --- Desktop: no lid/suspend handling, always-on ---
echo "[11.x] Configuring always-on (no sleep/suspend)..."
mkdir -p /etc/elogind/logind.conf.d
cat > /etc/elogind/logind.conf.d/always-on.conf <<'ALWAYSON'
[Login]
HandleSuspendKey=ignore
HandleSuspendKeyLongPress=ignore
HandleHibernateKey=ignore
HandleHibernateKeyLongPress=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
ALWAYSON
P11_DESKTOP
    fi

    # Firmware verification block (driver-dependent)
    cat >> "$out" <<'P11_FW_HEAD'

echo "[11.x] Verifying firmware files..."
FW_FAIL=0
P11_FW_HEAD

    [[ "$WIFI_DRIVER" == "iwlwifi" ]] && echo 'ls /lib/firmware/iwlwifi-*.ucode 2>/dev/null | head -1 && echo "  [OK] iwlwifi firmware" || { echo "  [FAIL] iwlwifi firmware missing!"; FW_FAIL=$((FW_FAIL+1)); }' >> "$out"
    [[ "$WIFI_DRIVER" == "brcmfmac" ]] && echo 'ls /lib/firmware/brcm/brcmfmac*.bin 2>/dev/null | head -1 && echo "  [OK] brcmfmac firmware" || { echo "  [FAIL] brcmfmac firmware missing!"; FW_FAIL=$((FW_FAIL+1)); }' >> "$out"
    [[ "$WIFI_DRIVER" == "mwifiex" ]] && echo 'ls /lib/firmware/mrvl/pcie8897_*.bin 2>/dev/null | head -1 && echo "  [OK] mwifiex firmware" || { echo "  [FAIL] mwifiex firmware missing!"; FW_FAIL=$((FW_FAIL+1)); }' >> "$out"
    [[ "$BT_DRIVER" == "intel" ]] && echo 'ls /lib/firmware/intel/ibt-*.* 2>/dev/null | head -1 && echo "  [OK] Intel BT firmware" || echo "  [WARN] Intel BT firmware missing"' >> "$out"
    [[ "$HAS_INTEL_GPU" == "1" && -n "$INTEL_GPU_GEN" ]] && echo "ls /lib/firmware/i915/${INTEL_GPU_GEN}_dmc_*.bin 2>/dev/null | head -1 && echo \"  [OK] i915 ${INTEL_GPU_GEN} DMC firmware\" || echo \"  [WARN] i915 DMC firmware missing\"" >> "$out"
    [[ "$HAS_NVIDIA_GPU" == "1" ]] && echo 'ls /lib/firmware/nvidia/*/ 2>/dev/null | head -1 && echo "  [OK] NVIDIA firmware" || echo "  [WARN] NVIDIA firmware directory missing"' >> "$out"

    cat >> "$out" <<'P11_FONT'

echo "[11.x] Installing emoji fontconfig..."
cat > /etc/fonts/local.conf <<'FONTEOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <alias><family>serif</family>     <prefer><family>Noto Color Emoji</family></prefer></alias>
  <alias><family>sans-serif</family><prefer><family>Noto Color Emoji</family></prefer></alias>
  <alias><family>monospace</family> <prefer><family>Noto Color Emoji</family></prefer></alias>
</fontconfig>
FONTEOF
fc-cache -f

echo "[OK] Phase 11 complete."
P11_FONT

    # ====== Phase 12: fstab (display) ======
    cat >> "$out" <<'P12'

# ============================================================================
# PHASE 12: fstab (already generated by part2)
# ============================================================================
echo ""
echo "=== PHASE 12: fstab ==="
cat /etc/fstab
echo "[OK] Phase 12 complete."
P12

    # ====== Phase 13: Pre-reboot verification (universal) ======
    cat >> "$out" <<'P13'

# ============================================================================
# PHASE 13: Pre-reboot Verification
# ============================================================================
echo ""
echo "=== PHASE 13: Pre-reboot Verification ==="

FAIL=0; WARN=0

ls /boot/vmlinuz-* &>/dev/null && echo "[OK] Kernel installed" || { echo "[FAIL] No kernel!"; FAIL=$((FAIL+1)); }
grep -q menuentry /boot/grub/grub.cfg 2>/dev/null && echo "[OK] GRUB configured" || { echo "[FAIL] GRUB!"; FAIL=$((FAIL+1)); }
ls /boot/efi/EFI/Boot/bootx64.efi &>/dev/null && echo "[OK] EFI fallback copied" || echo "[WARN] No EFI fallback"

UUID_COUNT=$(grep -c UUID /etc/fstab || true)
[[ $UUID_COUNT -ge 3 ]] && echo "[OK] $UUID_COUNT UUID entries in fstab" || { echo "[FAIL] fstab missing entries!"; FAIL=$((FAIL+1)); }

qlist -I net-wireless/wpa_supplicant &>/dev/null && echo "[OK] wpa_supplicant" || { echo "[FAIL] wpa_supplicant!"; FAIL=$((FAIL+1)); }
qlist -I net-misc/networkmanager     &>/dev/null && echo "[OK] NetworkManager" || { echo "[FAIL] NetworkManager!"; FAIL=$((FAIL+1)); }

for svc in dbus NetworkManager display-manager acpid cronie sshd; do
    rc-update show default 2>/dev/null | grep -q "$svc" && echo "[OK] $svc enabled" || { echo "[FAIL] $svc NOT enabled!"; FAIL=$((FAIL+1)); }
done
rc-update show boot 2>/dev/null | grep -q elogind  && echo "[OK] elogind enabled"  || { echo "[FAIL] elogind!"; FAIL=$((FAIL+1)); }
rc-update show boot 2>/dev/null | grep -q zram     && echo "[OK] zram-init enabled" || { echo "[FAIL] zram-init!"; FAIL=$((FAIL+1)); }

qlist -I media-video/pipewire &>/dev/null && echo "[OK] PipeWire" || { echo "[FAIL] PipeWire!"; FAIL=$((FAIL+1)); }

id "$USERNAME" &>/dev/null && echo "[OK] User $USERNAME exists" || { echo "[FAIL] User!"; FAIL=$((FAIL+1)); }
groups "$USERNAME" 2>/dev/null | grep -q video && echo "[OK] $USERNAME in video group" || { echo "[FAIL] video group!"; FAIL=$((FAIL+1)); }
grep -q "^%wheel" /etc/sudoers 2>/dev/null && echo "[OK] sudo for wheel" || { echo "[FAIL] sudo!"; FAIL=$((FAIL+1)); }
grep -q 'DISPLAYMANAGER="lightdm"' /etc/conf.d/display-manager 2>/dev/null && echo "[OK] display-manager=lightdm" || { echo "[FAIL] DISPLAYMANAGER!"; FAIL=$((FAIL+1)); }

[[ $FW_FAIL -eq 0 ]] && echo "[OK] Required firmware present" || { echo "[FAIL] $FW_FAIL firmware file(s) missing!"; FAIL=$((FAIL+FW_FAIL)); }

echo ""
echo "============================================================"
if [[ $FAIL -eq 0 ]]; then
    echo "=== ALL CHECKS PASSED ($WARN warnings) ==="
    echo "============================================================"
    echo ""
    echo "Safe to exit chroot and reboot:"
    echo "  exit"
    echo "  umount -l /mnt/gentoo/dev{/shm,/pts,}"
    echo "  umount -R /mnt/gentoo"
    echo "  reboot"
    echo ""
    echo "Post-boot:"
    echo "  - Connect network via nmcli/nmtui"
    echo "  - Restore desktop: bash ~/gentoo-machines/shared/restore-desktop.sh"
    echo "  - Run tools/verify-install.sh for full verification"
else
    echo "=== $FAIL CHECKS FAILED ($WARN warnings) ==="
    echo "============================================================"
    echo "FIX FAILURES ABOVE BEFORE REBOOTING"
fi
P13

    chmod +x "$out"
}

# --- Drive --------------------------------------------------------------------
emit_part1  "${NEW_DIR}/gentoo_install_part1.sh"
emit_part2  "${NEW_DIR}/gentoo_install_part2.sh"
emit_part3  "${NEW_DIR}/gentoo_install_part3_chroot.sh"

info ""
info "Generated:"
info "  ${NEW_DIR}/gentoo_install_part1.sh         (ready — review TARGET/disks)"
info "  ${NEW_DIR}/gentoo_install_part2.sh         (ready — review fstab tmpfs size)"
info "  ${NEW_DIR}/gentoo_install_part3_chroot.sh  (ready — review Phase 11 TODOs)"
info ""
info "Review all TODOs before running. Phase 11 is the most likely to need"
info "hand-editing (NVIDIA kernel params, Surface HiDPI, Apple applesmc)."
