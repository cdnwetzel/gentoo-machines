#!/bin/bash
# ============================================================================
# post_install_setup.sh - MacBook Pro 12,1 post-kernel Gentoo setup
# Run AFTER kernel is built and system is bootable
# ============================================================================
# NOTICE: This script is SUPERSEDED by gentoo_install_part3_chroot.sh
# which automates all steps below. Kept as a manual reference.
# ============================================================================

set -euo pipefail

echo "=== MacBook Pro 12,1 Post-Install Setup ==="

# --------------------------------------------------------------------------
echo "[1] Creating portage tmpfs infrastructure..."
# --------------------------------------------------------------------------
mkdir -p /var/tmp/portage
mkdir -p /var/tmp/portage-disk
chown portage:portage /var/tmp/portage-disk

# Copy portage env files
mkdir -p /etc/portage/env
echo 'Ensure /etc/portage/env/notmpfs.conf contains:'
echo '  PORTAGE_TMPDIR="/var/tmp/portage-disk"'
echo 'Ensure /etc/portage/package.env lists large packages.'
echo ""

# --------------------------------------------------------------------------
echo "[2] Installing critical packages..."
# --------------------------------------------------------------------------
echo "Run these emerges:"
echo "  emerge sys-kernel/linux-firmware"
echo "  emerge sys-firmware/intel-microcode"
echo "  emerge sys-kernel/installkernel  # auto grub-mkconfig on make install"
echo "  emerge app-laptop/mbpfan"
echo "  emerge sys-block/zram-init"
echo "  emerge sys-apps/util-linux    # for fstrim"
echo ""

# --------------------------------------------------------------------------
echo "[3] Kernel boot parameters..."
# --------------------------------------------------------------------------
echo "Add to your bootloader (rEFInd or GRUB):"
echo ""
echo '  acpi_osi="!Darwin" i915.enable_fbc=1 i915.enable_psr=2'
echo ""
echo "What each does:"
echo '  acpi_osi="!Darwin"   - Suppresses Apple ACPI _OSI(Darwin) quirk'
echo "  i915.enable_fbc=1    - Framebuffer compression (power saving)"
echo "  i915.enable_psr=2    - Panel Self Refresh for eDP (power saving)"
echo ""
echo "For rEFInd, add to /boot/efi/EFI/refind/refind.conf:"
echo '  "Boot with standard options" "root=/dev/sdaX acpi_osi=!Darwin i915.enable_fbc=1 i915.enable_psr=2"'
echo ""

# --------------------------------------------------------------------------
echo "[4] mbpfan configuration..."
# --------------------------------------------------------------------------
echo "Copy mbpfan.conf to /etc/mbpfan.conf"
echo "Fan profile based on confirmed hardware:"
echo "  Min RPM:  1300 (confirmed min: 1299)"
echo "  Max RPM:  6199 (confirmed max: 6199)"
echo "  Low temp:  55°C (idle is ~52-56°C)"
echo "  High temp: 80°C (ramp to max)"
echo "  Max temp:  86°C (emergency)"
echo ""
echo "Enable: rc-update add mbpfan default"
echo ""

# --------------------------------------------------------------------------
echo "[5] SSD TRIM setup..."
# --------------------------------------------------------------------------
echo "APPLE SSD SM0256G: TRIM limit 8 blocks"
echo "Use periodic fstrim, NOT continuous discard."
echo ""
echo "For OpenRC:"
echo "  Add to /etc/local.d/fstrim.start:"
echo '    #!/bin/sh'
echo '    /sbin/fstrim -a'
echo "  Or use cron: 0 2 * * 0 /sbin/fstrim -a"
echo ""

# --------------------------------------------------------------------------
echo "[6] zram swap setup..."
# --------------------------------------------------------------------------
echo "emerge sys-block/zram-init"
echo "Edit /etc/conf.d/zram-init:"
echo '  zram_size="8192"'
echo '  zram_comp_algorithm="lz4"'
echo "rc-update add zram-init boot"
echo ""

# --------------------------------------------------------------------------
echo "[7] Audio troubleshooting reference..."
# --------------------------------------------------------------------------
echo "CS4208 Apple variant (subsystem 0x106b7b00):"
echo "  Card 0 [HDMI]: Intel Broadwell HDMI at 0xc1810000"
echo "  Card 1 [PCH]:  Intel PCH (CS4208) at 0xc1814000"
echo ""
echo "Confirmed pin configuration:"
echo "  HP Out:    0x002b4020 (headphone jack, combo connector)"
echo "  Speaker L: 0x90100110 (fixed internal)"
echo "  Speaker R: 0x90100112 (fixed internal)"
echo ""
echo "If headphone/speaker auto-switching fails, try adding to"
echo "/etc/modprobe.d/snd-hda-intel.conf:"
echo '  options snd-hda-intel model=mbp11'
echo ""
echo "If that doesn't work, use the patch loader:"
echo '  options snd-hda-intel patch=cs4208_mbp_patch'
echo "and create the patch file in /lib/firmware with pin overrides."
echo ""

# --------------------------------------------------------------------------
echo "[8] Bluetooth setup..."
# --------------------------------------------------------------------------
echo "BCM20703A1 Apple 20MHz variant"
echo "Should work out of box with btusb + btbcm modules."
echo "If pairing issues occur, try:"
echo "  echo 'options btusb enable_autosuspend=0' > /etc/modprobe.d/btusb.conf"
echo ""

# --------------------------------------------------------------------------
echo "[9] Backlight control..."
# --------------------------------------------------------------------------
echo "Display: intel_backlight (raw, max=1388)"
echo "Keyboard: smc::kbd_backlight (max=255)"
echo ""
echo "Test display brightness:"
echo "  echo 700 > /sys/class/backlight/intel_backlight/brightness"
echo ""
echo "Test keyboard backlight:"
echo "  echo 128 > /sys/class/leds/smc::kbd_backlight/brightness"
echo ""

# --------------------------------------------------------------------------
echo "[10] Suspend verification..."
# --------------------------------------------------------------------------
echo "S3 deep sleep confirmed working and is the default."
echo "Verify after install:"
echo "  cat /sys/power/mem_sleep    # should show: s2idle [deep]"
echo "  systemctl suspend           # or: echo mem > /sys/power/state"
echo ""

echo "=== Setup reference complete ==="
