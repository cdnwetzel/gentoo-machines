#!/bin/bash
# hibernate-setup.sh — One-time swap file + GRUB resume configuration
# Enables hibernate-to-disk on machines with zram-only swap (no swap partition).
# Uses swap file on ext4 (kernel 5.0+), avoids repartitioning.
#
# Usage: sudo bash shared/hibernate-setup.sh
#
# What it does:
#   Phase 1: Detect RAM, confirm swap file size
#   Phase 2: Create /var/swapfile, mkswap, swapon
#   Phase 3: Add swap entry to /etc/fstab
#   Phase 4: Get resume device UUID + resume_offset
#   Phase 5: Update GRUB_CMDLINE_LINUX_DEFAULT with resume params
#   Phase 6: Regenerate GRUB config
#   Phase 7: Install low-battery-hibernate monitor (laptops)
#   Phase 8: Dry-run hibernate check
#
# Safe to re-run — each phase checks if already configured.

set -euo pipefail

SWAPFILE="/var/swapfile"
GRUB_DEFAULT="/etc/default/grub"
MONITOR_SRC="$(dirname "$0")/low-battery-hibernate.sh"
MONITOR_DST="/usr/local/bin/low-battery-hibernate.sh"

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

die() { echo "FATAL: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }
info() { echo "==> $*"; }
ask_yes_no() {
    local prompt="$1"
    local reply
    read -rp "$prompt [Y/n] " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

# --------------------------------------------------------------------------
# Preflight
# --------------------------------------------------------------------------

[[ $EUID -eq 0 ]] || die "Must run as root"
[[ -f "$GRUB_DEFAULT" ]] || die "$GRUB_DEFAULT not found — is GRUB installed?"

# Verify kernel supports hibernation
if [[ -f /sys/power/state ]]; then
    grep -q disk /sys/power/state || die "Kernel does not support hibernation (no 'disk' in /sys/power/state)"
else
    warn "/sys/power/state not found — cannot verify hibernate support (running in chroot?)"
fi

# Verify root filesystem is ext4 (swap file hibernate requires ext4 or btrfs with special handling)
ROOT_FSTYPE=$(findmnt -no FSTYPE /)
if [[ "$ROOT_FSTYPE" != "ext4" ]]; then
    die "Root filesystem is $ROOT_FSTYPE — this script supports ext4 only"
fi

# ==========================================================================
# Phase 1: Detect RAM size, confirm swap file size
# ==========================================================================

info "Phase 1: Detecting RAM size"

RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_GB=$(( (RAM_KB + 524288) / 1048576 ))  # round to nearest GB

echo "  Detected RAM: ${RAM_GB}GB"
echo "  Recommended swap file: ${RAM_GB}GB (must be >= RAM for hibernate)"

if ! ask_yes_no "  Create ${RAM_GB}GB swap file at $SWAPFILE?"; then
    read -rp "  Enter swap file size in GB: " RAM_GB
    [[ "$RAM_GB" =~ ^[0-9]+$ ]] || die "Invalid size: $RAM_GB"
fi

SWAP_SIZE="${RAM_GB}G"

# ==========================================================================
# Phase 2: Create swap file
# ==========================================================================

info "Phase 2: Creating swap file"

if [[ -f "$SWAPFILE" ]]; then
    EXISTING_SIZE=$(stat -c%s "$SWAPFILE" 2>/dev/null || echo 0)
    EXISTING_GB=$(( EXISTING_SIZE / 1073741824 ))
    echo "  $SWAPFILE already exists (${EXISTING_GB}GB)"
    if [[ "$EXISTING_GB" -ge "$RAM_GB" ]]; then
        echo "  Size is sufficient, skipping creation"
    else
        warn "Existing swap file is smaller than RAM — recreating"
        swapoff "$SWAPFILE" 2>/dev/null || true
        rm -f "$SWAPFILE"
        fallocate -l "$SWAP_SIZE" "$SWAPFILE"
        echo "  Created ${SWAP_SIZE} swap file"
    fi
else
    # Check available disk space
    AVAIL_KB=$(df --output=avail / | tail -1 | tr -d ' ')
    NEEDED_KB=$(( RAM_GB * 1048576 ))
    if [[ "$AVAIL_KB" -lt "$NEEDED_KB" ]]; then
        die "Not enough disk space: need ${RAM_GB}GB, have $(( AVAIL_KB / 1048576 ))GB"
    fi
    fallocate -l "$SWAP_SIZE" "$SWAPFILE"
    echo "  Created ${SWAP_SIZE} swap file"
fi

chmod 600 "$SWAPFILE"
mkswap "$SWAPFILE"
swapon "$SWAPFILE"
echo "  Swap file active"

# ==========================================================================
# Phase 3: Add to /etc/fstab
# ==========================================================================

info "Phase 3: Updating /etc/fstab"

if grep -q "$SWAPFILE" /etc/fstab; then
    echo "  $SWAPFILE already in fstab, skipping"
else
    echo "" >> /etc/fstab
    echo "# Hibernate swap file (zram handles daily swap, this is for hibernate)" >> /etc/fstab
    echo "$SWAPFILE    none    swap    sw,pri=-1    0 0" >> /etc/fstab
    echo "  Added $SWAPFILE to fstab (pri=-1 so zram is preferred for daily use)"
fi

# ==========================================================================
# Phase 4: Get resume device UUID and resume_offset
# ==========================================================================

info "Phase 4: Calculating resume parameters"

ROOT_UUID=$(findmnt -no UUID /)
[[ -n "$ROOT_UUID" ]] || die "Could not determine root partition UUID"
echo "  Root UUID: $ROOT_UUID"

# filefrag gives the physical offset of the first extent
RESUME_OFFSET=$(filefrag -v "$SWAPFILE" | awk '$1=="0:" {print substr($4, 1, length($4)-2)}')
[[ -n "$RESUME_OFFSET" ]] || die "Could not determine resume_offset from filefrag"
echo "  Resume offset: $RESUME_OFFSET"

RESUME_PARAM="resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET"
echo "  GRUB params: $RESUME_PARAM"

# ==========================================================================
# Phase 5: Update GRUB configuration
# ==========================================================================

info "Phase 5: Updating GRUB defaults"

# Detect which GRUB variable holds kernel params.
# Some machines use GRUB_CMDLINE_LINUX_DEFAULT, others use GRUB_CMDLINE_LINUX.
# Prefer _DEFAULT if it exists uncommented; fall back to GRUB_CMDLINE_LINUX.
if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_DEFAULT"; then
    GRUB_VAR="GRUB_CMDLINE_LINUX_DEFAULT"
elif grep -q '^GRUB_CMDLINE_LINUX=' "$GRUB_DEFAULT"; then
    GRUB_VAR="GRUB_CMDLINE_LINUX"
else
    die "Neither GRUB_CMDLINE_LINUX_DEFAULT nor GRUB_CMDLINE_LINUX found in $GRUB_DEFAULT"
fi

CURRENT_CMDLINE=$(grep "^${GRUB_VAR}=" "$GRUB_DEFAULT" | sed "s/^${GRUB_VAR}=//" | tr -d '"')
echo "  Using $GRUB_VAR"
echo "  Current: $CURRENT_CMDLINE"

# Check if resume params already present
if echo "$CURRENT_CMDLINE" | grep -q "resume="; then
    echo "  resume= already present"
    if ask_yes_no "  Replace existing resume params?"; then
        # Strip old resume params
        CURRENT_CMDLINE=$(echo "$CURRENT_CMDLINE" | sed -E 's/resume=[^ ]+//g; s/resume_offset=[^ ]+//g; s/  +/ /g; s/^ +//; s/ +$//')
        NEW_CMDLINE="$CURRENT_CMDLINE $RESUME_PARAM"
    else
        echo "  Keeping existing resume params"
        NEW_CMDLINE="$CURRENT_CMDLINE"
    fi
else
    NEW_CMDLINE="$CURRENT_CMDLINE $RESUME_PARAM"
fi

# Back up grub defaults
cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}.pre-hibernate"
echo "  Backed up to ${GRUB_DEFAULT}.pre-hibernate"

# Write updated cmdline
sed -i "s|^${GRUB_VAR}=.*|${GRUB_VAR}=\"$NEW_CMDLINE\"|" "$GRUB_DEFAULT"
echo "  Updated: ${GRUB_VAR}=\"$NEW_CMDLINE\""

# ==========================================================================
# Phase 6: Regenerate GRUB config
# ==========================================================================

info "Phase 6: Regenerating GRUB config"

grub-mkconfig -o /boot/grub/grub.cfg
echo "  GRUB config regenerated"

# ==========================================================================
# Phase 7: Install low-battery monitor (laptops only)
# ==========================================================================

info "Phase 7: Low-battery hibernate monitor"

# Detect if this is a laptop (has a battery)
# Check any power supply with type=Battery (covers BAT0, BAT1, BATT, surface-battery, etc.)
HAS_BATTERY=false
for ps in /sys/class/power_supply/*/type; do
    if [[ -f "$ps" ]] && [[ "$(cat "$ps")" == "Battery" ]]; then
        HAS_BATTERY=true
        break
    fi
done

if $HAS_BATTERY; then
    if [[ -f "$MONITOR_SRC" ]]; then
        cp "$MONITOR_SRC" "$MONITOR_DST"
        chmod 755 "$MONITOR_DST"
        echo "  Installed $MONITOR_DST"

        # Add cron job if not already present
        if crontab -l 2>/dev/null | grep -q "low-battery-hibernate"; then
            echo "  Cron job already exists, skipping"
        else
            (crontab -l 2>/dev/null || true; echo "*/2 * * * * $MONITOR_DST") | crontab -
            echo "  Added cron job: */2 * * * * $MONITOR_DST"
        fi
    else
        warn "$MONITOR_SRC not found — install low-battery-hibernate.sh manually"
    fi
else
    echo "  No battery detected — skipping (desktop/server)"
    echo "  For UPS hibernate, configure apcupsd with doshutdown override"
fi

# ==========================================================================
# Phase 8: Dry-run hibernate check
# ==========================================================================

info "Phase 8: Hibernate readiness check"

echo "  Swap devices:"
swapon --show
echo ""

echo "  Kernel hibernate support:"
cat /sys/power/state
echo ""

if [[ -f /sys/power/disk ]]; then
    echo "  Hibernate modes:"
    cat /sys/power/disk
    echo ""
fi

echo "  GRUB resume params:"
grep "^${GRUB_VAR}=" "$GRUB_DEFAULT"
echo ""

# Verify resume appears in generated grub.cfg
if grep -q "resume=" /boot/grub/grub.cfg; then
    echo "  OK: resume= found in /boot/grub/grub.cfg"
else
    warn "resume= NOT found in /boot/grub/grub.cfg — reboot may not resume correctly"
fi

# ==========================================================================
# Summary
# ==========================================================================

echo ""
echo "================================================================"
echo "  Hibernate setup complete!"
echo "================================================================"
echo ""
echo "  Swap file:      $SWAPFILE ($SWAP_SIZE)"
echo "  Resume device:  UUID=$ROOT_UUID"
echo "  Resume offset:  $RESUME_OFFSET"
echo ""
echo "  IMPORTANT: You must reboot for the GRUB resume params to take effect."
echo "  After reboot, test with:"
echo "    echo disk > /sys/power/state"
echo ""
if $HAS_BATTERY; then
    echo "  Low-battery monitor installed — will hibernate at 5% battery."
    echo "  Check with: crontab -l | grep hibernate"
fi
echo ""
echo "  To undo: remove resume params from $GRUB_DEFAULT,"
echo "  remove $SWAPFILE line from /etc/fstab, then:"
echo "    swapoff $SWAPFILE && rm $SWAPFILE && grub-mkconfig -o /boot/grub/grub.cfg"
