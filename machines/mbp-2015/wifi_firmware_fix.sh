#!/bin/bash
# ============================================================================
# wifi_firmware_fix.sh - Fix missing BCM43602 blobs for MacBookPro12,1
# ============================================================================
# Confirmed from dmesg (Fedora 43 / kernel 6.17.1):
#
# [OK]  brcmfmac43602-pcie.bin loads -> BCM43602/1 v7.35.177.61 (r598657)
# [ERR] brcm/brcmfmac43602-pcie.Apple Inc.-MacBookPro12,1.bin  (-2 ENOENT)
# [ERR] brcm/brcmfmac43602-pcie.txt                            (-2 ENOENT)
# [ERR] brcm/brcmfmac43602-pcie.clm_blob                       (-2 ENOENT)
# [ERR] brcm/brcmfmac43602-pcie.txcap_blob                     (-2 ENOENT)
#
# WiFi works without them. Fixing suppresses errors and may improve:
#   - clm_blob: regional TX power compliance
#   - txt: board-specific antenna tuning / NVRAM
#   - txcap_blob: per-channel TX power caps
# ============================================================================

set -euo pipefail

FW_DIR="/lib/firmware/brcm"
CHIP="brcmfmac43602-pcie"

echo "=== BCM43602 Firmware Fix for MacBookPro12,1 ==="

if [[ ! -f "$FW_DIR/$CHIP.bin" ]]; then
    echo "ERROR: $FW_DIR/$CHIP.bin not found."
    echo "Run: emerge sys-kernel/linux-firmware"
    exit 1
fi

echo "[1] Base firmware: OK (BCM43602/1 v7.35.177.61)"

# Machine-specific override -> symlink to generic (confirmed working)
MACHINE_FW="$CHIP.Apple Inc.-MacBookPro12,1.bin"
if [[ ! -f "$FW_DIR/$MACHINE_FW" ]]; then
    echo "[2] Symlinking machine-specific firmware..."
    ln -sf "$CHIP.bin" "$FW_DIR/$MACHINE_FW"
    echo "    -> $FW_DIR/$MACHINE_FW"
else
    echo "[2] Machine-specific firmware: exists"
fi

# CLM blob
if [[ ! -f "$FW_DIR/$CHIP.clm_blob" ]]; then
    echo "[3] CLM blob: MISSING (regulatory TX power limits may not apply)"
    echo "    Check newer linux-firmware, or extract from macOS:"
    echo "      /usr/share/firmware/wifi/C-4350__s-C1/ or similar"
else
    echo "[3] CLM blob: OK"
fi

# NVRAM / board config
if [[ ! -f "$FW_DIR/$CHIP.txt" ]]; then
    echo "[4] NVRAM (.txt): MISSING"

    # Try macOS extraction if mounted
    for mpath in /mnt/macos/usr/share/firmware/wifi /mnt/macos/System/Library/Firmware; do
        if [[ -d "$mpath" ]]; then
            NVRAM=$(find "$mpath" -name "*.txt" -path "*43602*" 2>/dev/null | head -1)
            if [[ -n "$NVRAM" ]]; then
                cp "$NVRAM" "$FW_DIR/$CHIP.txt"
                echo "    Extracted from macOS: $NVRAM"
                break
            fi
        fi
    done

    [[ ! -f "$FW_DIR/$CHIP.txt" ]] && echo "    Community NVRAM: https://github.com/coldnew/macbook-pro-2015-gentoo"
else
    echo "[4] NVRAM (.txt): OK"
fi

# TX cap blob
if [[ ! -f "$FW_DIR/$CHIP.txcap_blob" ]]; then
    echo "[5] TX cap blob: MISSING (non-critical)"
else
    echo "[5] TX cap blob: OK"
fi

echo ""
echo "Reload: rmmod brcmfmac && modprobe brcmfmac"
