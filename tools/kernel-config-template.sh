#!/bin/bash
# ============================================================================
# kernel-config-template.sh — Skeleton Kernel Config Generator
# ============================================================================
# Generates a machine-specific kernel_config.sh from harvest data.
#
# 1. Parses harvest output → detects CPU, GPU, WiFi, audio, storage, vendor
# 2. Maps PCI "Kernel modules:" lines → CONFIG_ symbols via lookup table
# 3. Generates 25-phase kernel_config.sh with correct drivers pre-filled
# 4. Marks uncertain sections with # TODO: verify on live hardware
# 5. Auto-runs kconfig-lint on the generated script (if kernel source available)
#
# USAGE:
#   tools/kernel-config-template.sh <machine-name> <harvest-log>
#
# EXAMPLE:
#   tools/kernel-config-template.sh precision-t5810 /tmp/t5810-harvest/hardware_inventory.log
#
# DEPENDENCIES: awk, grep, sed (all in stage 3 base)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# --- Usage ---
usage() {
    echo "Usage: $0 <machine-name> <harvest-log>"
    echo ""
    echo "  machine-name   Name for the new machine (e.g., precision-t5810)"
    echo "  harvest-log    Path to hardware_inventory.log from harvest.sh"
    echo ""
    echo "Output: machines/<machine-name>/kernel_config.sh"
    exit 1
}

[[ $# -lt 2 ]] && usage
MACHINE="$1"
HARVEST="$2"

if [[ ! -f "$HARVEST" ]]; then
    echo "ERROR: Harvest log not found: $HARVEST"
    exit 1
fi

OUTPUT_DIR="$REPO_DIR/machines/$MACHINE"
OUTPUT="$OUTPUT_DIR/kernel_config.sh"

mkdir -p "$OUTPUT_DIR"

# ============================================================================
# PHASE 1: Parse harvest data
# ============================================================================

echo "Parsing harvest data from: $HARVEST"

# --- CPU detection ---
CPU_VENDOR=$(grep -m1 'Vendor ID:' "$HARVEST" | awk '{print $NF}' || echo "")
CPU_MODEL_NAME=$(grep -m1 'Model name:' "$HARVEST" | sed 's/.*Model name:[[:space:]]*//' || echo "")
CPU_FAMILY=$(grep -m1 'CPU family:' "$HARVEST" | awk '{print $NF}' || echo "")
CPU_MODEL_NUM=$(grep -m1 'Model:' "$HARVEST" | awk '{print $NF}' || echo "")

# Detect CPU core count from model name
NR_CPUS=4  # safe default
if echo "$CPU_MODEL_NAME" | grep -qiE 'i[3579]-[0-9]{4,5}'; then
    # Try to derive from known suffixes
    case "$CPU_MODEL_NAME" in
        *i9-14900*|*i9-13900*)  NR_CPUS=32 ;;
        *i7-14700*|*i7-13700*)  NR_CPUS=24 ;;
        *i7-12700*|*i5-12600*)  NR_CPUS=20 ;;
        *i7-11800*|*i9-11900*)  NR_CPUS=16 ;;
        *i5-1[12]30U*|*i5-1[23]40P*) NR_CPUS=12 ;;
        *i7-1[01]65*|*i5-1135*|*i7-8[56]50*|*i5-8[23]50*|*i5-8250*) NR_CPUS=8 ;;
        *i7-5557*|*i5-5257*)    NR_CPUS=4 ;;
        *)                      NR_CPUS=8 ;;
    esac
fi
# Also try from lscpu if available in harvest
LSCPU_CPUS=$(grep -m1 'CPU(s):' "$HARVEST" | awk '{print $NF}' || echo "")
[[ -n "$LSCPU_CPUS" ]] && [[ "$LSCPU_CPUS" =~ ^[0-9]+$ ]] && NR_CPUS="$LSCPU_CPUS"

# GCC -march from section 15
GCC_MARCH=$(grep 'Suggested:.*-march=' "$HARVEST" | head -1 | grep -oP '(?<=-march=)\S+' || echo "")

# CPU flags from section 9
CPU_FLAGS=$(grep 'CPU_FLAGS_X86' "$HARVEST" | head -1 | sed 's/.*CPU_FLAGS_X86[^:]*:[[:space:]]*//' || echo "")

# --- GPU detection ---
HAS_INTEL_GPU=0
HAS_NVIDIA_GPU=0
HAS_AMD_GPU=0
INTEL_GPU_GEN=""

if grep -q 'i915' "$HARVEST"; then
    HAS_INTEL_GPU=1
    # Detect generation from PCI device
    if grep -qi 'Alder Lake' "$HARVEST"; then INTEL_GPU_GEN="adlp"
    elif grep -qi 'Tiger Lake' "$HARVEST"; then INTEL_GPU_GEN="tgl"
    elif grep -qi 'Kaby Lake\|Coffee Lake\|Whiskey Lake\|Comet Lake' "$HARVEST"; then INTEL_GPU_GEN="kbl"
    elif grep -qi 'Broadwell' "$HARVEST"; then INTEL_GPU_GEN="bdw"
    elif grep -qi 'Skylake' "$HARVEST"; then INTEL_GPU_GEN="skl"
    elif grep -qi 'Ice Lake' "$HARVEST"; then INTEL_GPU_GEN="icl"
    elif grep -qi 'Raptor Lake' "$HARVEST"; then INTEL_GPU_GEN="rpl"
    elif grep -qi 'Meteor Lake' "$HARVEST"; then INTEL_GPU_GEN="mtl"
    fi
fi
grep -qiE 'nvidia|nouveau' "$HARVEST" && HAS_NVIDIA_GPU=1
grep -qiE 'amdgpu|radeon' "$HARVEST" && HAS_AMD_GPU=1

# --- WiFi detection ---
WIFI_DRIVER=""
if grep -q 'iwlwifi' "$HARVEST"; then WIFI_DRIVER="iwlwifi"
elif grep -q 'brcmfmac' "$HARVEST"; then WIFI_DRIVER="brcmfmac"
elif grep -q 'mwifiex' "$HARVEST"; then WIFI_DRIVER="mwifiex"
elif grep -q 'ath11k' "$HARVEST"; then WIFI_DRIVER="ath11k"
elif grep -q 'ath12k' "$HARVEST"; then WIFI_DRIVER="ath12k"
elif grep -q 'mt76' "$HARVEST"; then WIFI_DRIVER="mt76"
elif grep -q 'rtw89' "$HARVEST"; then WIFI_DRIVER="rtw89"
elif grep -q 'rtw88' "$HARVEST"; then WIFI_DRIVER="rtw88"
fi

# --- Bluetooth detection ---
BT_DRIVER=""
if grep -q 'btintel\|btusb.*Intel' "$HARVEST"; then BT_DRIVER="intel"
elif grep -q 'btbcm' "$HARVEST"; then BT_DRIVER="broadcom"
elif grep -q 'btmrvl\|btmtksdio' "$HARVEST"; then BT_DRIVER="marvell"
else BT_DRIVER="generic"
fi

# --- Audio detection ---
AUDIO_TYPE="hda"  # default
if grep -q 'Type: SOF' "$HARVEST" || grep -q 'snd_sof' "$HARVEST"; then
    AUDIO_TYPE="sof"
elif grep -q 'Type: HDA' "$HARVEST" || grep -q 'snd_hda_intel' "$HARVEST"; then
    AUDIO_TYPE="hda"
fi

AUDIO_CODEC=""
if grep -qi 'realtek\|ALC[0-9]' "$HARVEST"; then AUDIO_CODEC="realtek"
elif grep -qi 'cs420[0-9]\|Cirrus' "$HARVEST"; then AUDIO_CODEC="cirrus"
fi

# --- Storage detection ---
HAS_NVME=0
HAS_SATA=0
grep -q 'nvme' "$HARVEST" && HAS_NVME=1
grep -qiE 'ahci|sata' "$HARVEST" && HAS_SATA=1

# --- Platform vendor ---
PLATFORM="generic"
if grep -q 'Platform: DELL' "$HARVEST"; then PLATFORM="dell"
elif grep -q 'Platform: APPLE' "$HARVEST"; then PLATFORM="apple"
elif grep -q 'Platform: LENOVO' "$HARVEST"; then PLATFORM="lenovo"
elif grep -q 'Platform: HP' "$HARVEST"; then PLATFORM="hp"
elif grep -q 'Platform: SURFACE' "$HARVEST"; then PLATFORM="surface"
elif grep -q 'Platform: ASUS' "$HARVEST"; then PLATFORM="asus"
fi

# --- Boot type ---
BOOT_EFI=1  # assume EFI
grep -q 'Boot: BIOS' "$HARVEST" && BOOT_EFI=0

# --- Suspend ---
SUSPEND_S3=0
grep -q 'S3 deep: supported' "$HARVEST" && SUSPEND_S3=1

# --- Ethernet detection ---
ETH_DRIVERS=""
for drv in igc e1000e r8169 r8152 igb ixgbe mlx5_core ax88179 cdc_ether; do
    if grep -q "$drv" "$HARVEST"; then
        ETH_DRIVERS="$ETH_DRIVERS $drv"
    fi
done

# --- Thunderbolt ---
HAS_TB=0
grep -qi 'thunderbolt' "$HARVEST" && HAS_TB=1

# --- ISH (Intel Sensor Hub) ---
HAS_ISH=0
grep -qi 'intel_ish\|ISH' "$HARVEST" && HAS_ISH=1

# --- Card reader ---
HAS_RTSX=0
grep -qi 'rtsx\|RTS[0-9]' "$HARVEST" && HAS_RTSX=1

# --- IPU camera ---
HAS_IPU3=0
HAS_IPU6=0
grep -qi 'ipu3\|IPU3' "$HARVEST" && HAS_IPU3=1
grep -qi 'ipu6\|IPU6\|intel_ipu6' "$HARVEST" && HAS_IPU6=1

# --- Surface SAM ---
HAS_SAM=0
grep -qi 'surface_aggregator\|SURFACE_AGGREGATOR' "$HARVEST" && HAS_SAM=1

# --- Summary ---
echo "  CPU: $CPU_MODEL_NAME ($CPU_VENDOR, NR_CPUS=$NR_CPUS)"
echo "  GPU: Intel=$HAS_INTEL_GPU($INTEL_GPU_GEN) NVIDIA=$HAS_NVIDIA_GPU AMD=$HAS_AMD_GPU"
echo "  WiFi: $WIFI_DRIVER"
echo "  Audio: $AUDIO_TYPE ($AUDIO_CODEC)"
echo "  Storage: NVMe=$HAS_NVME SATA=$HAS_SATA"
echo "  Platform: $PLATFORM"
echo "  Boot: $([ $BOOT_EFI -eq 1 ] && echo 'EFI' || echo 'BIOS')"
echo "  -march: ${GCC_MARCH:-unknown}"
echo ""

# ============================================================================
# PHASE 2: Generate kernel_config.sh
# ============================================================================

echo "Generating: $OUTPUT"

# Build job count = NR_CPUS + 1
BUILD_JOBS=$((NR_CPUS + 1))

# Pretty machine name
MACHINE_PRETTY=$(echo "$MACHINE" | tr '-' ' ' | sed 's/\b\(.\)/\u\1/g')

cat > "$OUTPUT" << 'HEADER'
#!/bin/bash
# ============================================================================
HEADER

cat >> "$OUTPUT" << EOF
# Gentoo Kernel Config - $MACHINE_PRETTY
# ============================================================================
# Generated by kernel-config-template.sh from harvest data
# Date: $(date +%Y-%m-%d)
#
# CPU: $CPU_MODEL_NAME
# GPU: $([ $HAS_INTEL_GPU -eq 1 ] && echo "Intel i915 ($INTEL_GPU_GEN)")$([ $HAS_NVIDIA_GPU -eq 1 ] && echo " + NVIDIA (proprietary)")$([ $HAS_AMD_GPU -eq 1 ] && echo " AMD (amdgpu)")
# WiFi: $WIFI_DRIVER
# Audio: $AUDIO_TYPE$([ -n "$AUDIO_CODEC" ] && echo " ($AUDIO_CODEC)")
# Storage: $([ $HAS_NVME -eq 1 ] && echo "NVMe")$([ $HAS_SATA -eq 1 ] && echo " + SATA")
# Platform: $PLATFORM
#
# USAGE:
#   cd /usr/src/linux
#   make defconfig
#   bash /path/to/kernel_config.sh
#   make olddefconfig
#   make -j$BUILD_JOBS && make modules_install && make install
#
# BOOT STRATEGY: No initramfs — all root-path drivers built-in (=y)
# TODO: Review and verify all settings on live hardware
# ============================================================================

set -euo pipefail

SC="./scripts/config"

if [[ ! -x "\$SC" ]]; then
    echo "ERROR: Run this from /usr/src/linux (scripts/config not found)"
    exit 1
fi

echo "=== Applying $MACHINE_PRETTY kernel config ==="
echo ""

# ==========================================================================
# PHASE 1: GENERAL / GENTOO
# ==========================================================================
echo "[Phase 1] General settings..."

\$SC --enable IKCONFIG
\$SC --enable IKCONFIG_PROC
\$SC --set-str DEFAULT_HOSTNAME "$MACHINE"

\$SC --enable GENTOO_LINUX
\$SC --enable GENTOO_LINUX_INIT_SCRIPT
\$SC --enable GENTOO_LINUX_PORTAGE
\$SC --enable GENTOO_LINUX_UDEV

echo "  [OK] General"

# ==========================================================================
# PHASE 2: PROCESSOR - $CPU_MODEL_NAME
# ==========================================================================
echo "[Phase 2] Processor configuration..."

\$SC --enable SMP
\$SC --set-val NR_CPUS $NR_CPUS
EOF

# CPU type selection
if [ "$CPU_VENDOR" = "GenuineIntel" ]; then
    echo '$SC --enable MCORE2' >> "$OUTPUT"
    echo "" >> "$OUTPUT"
elif [ "$CPU_VENDOR" = "AuthenticAMD" ]; then
    cat >> "$OUTPUT" << 'EOF'
# TODO: verify correct AMD CPU type for your processor
$SC --enable MZEN3  # Zen 3+ (Ryzen 5000+)
EOF
fi

cat >> "$OUTPUT" << 'EOF'

$SC --enable SCHED_MC
$SC --enable SCHED_SMT
$SC --enable SCHED_AUTOGROUP
EOF

if [ "$CPU_VENDOR" = "GenuineIntel" ]; then
    cat >> "$OUTPUT" << 'EOF'
$SC --enable X86_INTEL_PSTATE
$SC --enable CPU_FREQ_GOV_POWERSAVE
$SC --enable CPU_FREQ_DEFAULT_GOV_POWERSAVE
$SC --enable INTEL_IDLE
$SC --enable MICROCODE
$SC --enable X86_X2APIC

# Thermal/power
$SC --enable INTEL_RAPL
$SC --enable X86_PKG_TEMP_THERMAL
$SC --enable INTEL_POWERCLAMP
$SC --enable CORETEMP

# DPTF thermal framework
# TODO: verify DPTF INT340X device present in ACPI tables
$SC --enable ACPI_DPTF
$SC --module INT340X_THERMAL
$SC --module ACPI_THERMAL_REL
$SC --module INTEL_PCH_THERMAL
$SC --module PROC_THERMAL_MMIO_RAPL
EOF
elif [ "$CPU_VENDOR" = "AuthenticAMD" ]; then
    cat >> "$OUTPUT" << 'EOF'
$SC --enable X86_AMD_PSTATE
$SC --enable CPU_FREQ_GOV_POWERSAVE
$SC --enable CPU_FREQ_DEFAULT_GOV_POWERSAVE
$SC --enable MICROCODE
$SC --enable X86_X2APIC
$SC --enable AMD_IOMMU

# AMD thermal/power
$SC --enable K10TEMP
EOF
fi

# Hybrid CPU check (Alder Lake+)
if echo "$CPU_MODEL_NAME" | grep -qiE 'i[579]-1[23][0-9]{2}|Alder|Raptor|Meteor'; then
    cat >> "$OUTPUT" << 'EOF'

# Hybrid P-Core/E-Core scheduling
$SC --enable X86_HYBRID_CPUS 2>/dev/null || echo "  [INFO] X86_HYBRID_CPUS not available in this kernel"
$SC --enable INTEL_HFI_THERMAL 2>/dev/null || echo "  [INFO] INTEL_HFI_THERMAL not available in this kernel"
EOF
fi

cat >> "$OUTPUT" << 'EOF'

# KVM
$SC --module KVM
EOF

if [ "$CPU_VENDOR" = "GenuineIntel" ]; then
    echo '$SC --module KVM_INTEL' >> "$OUTPUT"
elif [ "$CPU_VENDOR" = "AuthenticAMD" ]; then
    echo '$SC --module KVM_AMD' >> "$OUTPUT"
fi

cat >> "$OUTPUT" << 'EOF'

echo "  [OK] Processor"

# ==========================================================================
# PHASE 3: PERFORMANCE TUNING
# ==========================================================================
echo "[Phase 3] Performance tuning..."

$SC --enable PREEMPT
$SC --enable PREEMPT_DYNAMIC
$SC --enable HZ_1000
$SC --enable NO_HZ_IDLE

# Transparent Huge Pages
$SC --enable TRANSPARENT_HUGEPAGE
$SC --enable TRANSPARENT_HUGEPAGE_ALWAYS

# MGLRU (Multi-Gen LRU)
$SC --enable LRU_GEN
$SC --enable LRU_GEN_ENABLED

# KSM (Kernel Same-page Merging)
$SC --enable KSM

echo "  [OK] Performance"

# ==========================================================================
# PHASE 4: MEMORY / SWAP - zram
# ==========================================================================
echo "[Phase 4] Memory and zram..."

$SC --enable ZRAM
$SC --enable ZRAM_BACKEND_ZSTD
$SC --enable CRYPTO_ZSTD
$SC --enable ZSTD_COMPRESS
$SC --enable ZSTD_DECOMPRESS
$SC --set-str ZRAM_DEF_COMP "zstd"

$SC --enable SWAP
$SC --enable ZSWAP

$SC --enable LZ4_COMPRESS
$SC --enable LZ4HC_COMPRESS

echo "  [OK] Memory"

EOF

# ==========================================================================
# PHASE 5: STORAGE
# ==========================================================================
cat >> "$OUTPUT" << 'EOF'
# ==========================================================================
# PHASE 5: STORAGE
# ==========================================================================
echo "[Phase 5] Storage..."

EOF

if [ $HAS_NVME -eq 1 ]; then
    cat >> "$OUTPUT" << 'EOF'
# NVMe MUST be =y (built-in) — boot drive, no initramfs
$SC --enable BLK_DEV_NVME
$SC --enable NVME_CORE

EOF
fi

if [ $HAS_SATA -eq 1 ]; then
    cat >> "$OUTPUT" << 'EOF'
# SATA AHCI — built-in if boot drive, module if secondary
# TODO: verify if SATA is boot drive or secondary
$SC --enable ATA
$SC --enable SATA_AHCI
$SC --enable BLK_DEV_SD

EOF
fi

cat >> "$OUTPUT" << 'EOF'
# I/O scheduler
$SC --enable BLK_DEV_THROTTLING
$SC --enable IOSCHED_BFQ
$SC --enable BFQ_GROUP_IOSCHED

# USB storage
$SC --module USB_STORAGE
$SC --module USB_UAS

echo "  [OK] Storage"

# ==========================================================================
# PHASE 6: FILESYSTEMS
# ==========================================================================
echo "[Phase 6] Filesystems..."

# Root filesystem must be built-in (no initramfs)
$SC --enable EXT4_FS

# EFI partition must be built-in
$SC --enable VFAT_FS
$SC --enable NLS_CODEPAGE_437
$SC --enable NLS_ISO8859_1
$SC --enable FAT_FS
$SC --enable MSDOS_FS

# Other filesystems as modules
$SC --module BTRFS_FS
$SC --module XFS_FS
$SC --module EXFAT_FS
$SC --module FUSE_FS

$SC --enable TMPFS
$SC --enable PROC_FS
$SC --enable SYSFS

# EFI variables
$SC --enable EFI_PARTITION
$SC --enable EFIVAR_FS

echo "  [OK] Filesystems"

EOF

# ==========================================================================
# PHASE 7: GPU
# ==========================================================================
cat >> "$OUTPUT" << 'EOF'
# ==========================================================================
# PHASE 7: GPU
# ==========================================================================
echo "[Phase 7] GPU..."

$SC --enable DRM
EOF

if [ $HAS_INTEL_GPU -eq 1 ]; then
    cat >> "$OUTPUT" << 'EOF'

# Intel i915 MUST be module — needs firmware from /lib/firmware/
$SC --module DRM_I915
$SC --enable DRM_I915_CAPTURE_ERROR
$SC --enable DRM_I915_COMPRESS_ERROR
$SC --enable DRM_I915_USERPTR
$SC --enable DRM_I915_PXP
$SC --disable DRM_I915_GVT

# HDA-i915 audio link (HDMI audio needs i915)
$SC --enable SND_HDA_I915
EOF
fi

if [ $HAS_AMD_GPU -eq 1 ]; then
    cat >> "$OUTPUT" << 'EOF'

# AMD GPU — module (needs firmware from /lib/firmware/amdgpu/)
$SC --module DRM_AMDGPU
# TODO: verify which AMDGPU features needed
$SC --enable DRM_AMDGPU_SI 2>/dev/null || true
$SC --enable DRM_AMDGPU_CIK 2>/dev/null || true
EOF
fi

if [ $HAS_NVIDIA_GPU -eq 1 ]; then
    cat >> "$OUTPUT" << 'EOF'

# NVIDIA: out-of-tree proprietary driver (nvidia-drivers ebuild)
# DRM_QXL=m pulls in DRM_TTM_HELPER (nvidia build dep since kernel 6.11+)
$SC --module DRM_QXL
$SC --disable DRM_NOUVEAU
$SC --enable DRM_KMS_HELPER
EOF
fi

cat >> "$OUTPUT" << 'EOF'

# Framebuffer
$SC --enable FB
$SC --enable FB_EFI
$SC --enable FRAMEBUFFER_CONSOLE
$SC --enable DRM_FBDEV_EMULATION

# Backlight
$SC --enable BACKLIGHT_CLASS_DEVICE

echo "  [OK] GPU"

EOF

# ==========================================================================
# PHASE 8: AUDIO
# ==========================================================================
cat >> "$OUTPUT" << 'EOF'
# ==========================================================================
# PHASE 8: AUDIO
# ==========================================================================
echo "[Phase 8] Audio..."

$SC --enable SOUND
$SC --module SND
$SC --module SND_PCM
$SC --module SND_HWDEP
$SC --module SND_SEQ
$SC --module SND_TIMER
$SC --module SND_HRTIMER

EOF

if [ "$AUDIO_TYPE" = "sof" ]; then
    cat >> "$OUTPUT" << 'EOF'
# SOF (Sound Open Firmware) driver stack
$SC --enable SND_SOC_SOF_TOPLEVEL
$SC --module SND_SOC_SOF_PCI_INTEL_TGL
$SC --module SND_SOC
$SC --module SND_SOC_SOF
$SC --module SND_SOC_SOF_INTEL_TOPLEVEL
$SC --module SND_SOC_SOF_INTEL_PCI

# SoundWire (if present)
$SC --enable SOUNDWIRE 2>/dev/null || true
$SC --module SOUNDWIRE_INTEL 2>/dev/null || true

# HDA link (SOF still needs HDA for HDMI)
$SC --module SND_HDA_INTEL
$SC --module SND_HDA_CODEC_HDMI
EOF
elif [ "$AUDIO_TYPE" = "hda" ]; then
    cat >> "$OUTPUT" << 'EOF'
# HDA Intel driver — module
$SC --module SND_HDA_INTEL

# Codecs
EOF
    if [ "$AUDIO_CODEC" = "realtek" ]; then
        echo '$SC --module SND_HDA_CODEC_REALTEK' >> "$OUTPUT"
    elif [ "$AUDIO_CODEC" = "cirrus" ]; then
        echo '$SC --module SND_HDA_CODEC_CS420X' >> "$OUTPUT"
    else
        echo '# TODO: identify correct codec from harvest data' >> "$OUTPUT"
        echo '$SC --module SND_HDA_CODEC_REALTEK' >> "$OUTPUT"
    fi

    cat >> "$OUTPUT" << 'EOF'
$SC --module SND_HDA_CODEC_HDMI
$SC --module SND_HDA_GENERIC

# HDA features
$SC --enable SND_HDA_HWDEP
$SC --enable SND_HDA_RECONFIG
$SC --enable SND_HDA_INPUT_BEEP
$SC --set-val SND_HDA_INPUT_BEEP_MODE 0
$SC --enable SND_HDA_PATCH_LOADER
$SC --enable SND_HDA_POWER_SAVE
$SC --set-val SND_HDA_POWER_SAVE_DEFAULT 1

# Disable SOF (HDA works natively)
$SC --disable SND_SOC_SOF_TOPLEVEL
EOF
fi

cat >> "$OUTPUT" << 'EOF'

echo "  [OK] Audio"

EOF

# ==========================================================================
# PHASE 9: WIFI
# ==========================================================================
cat >> "$OUTPUT" << 'EOF'
# ==========================================================================
# PHASE 9: WIFI
# ==========================================================================
echo "[Phase 9] WiFi..."

$SC --module CFG80211
$SC --enable CFG80211_WEXT
$SC --module MAC80211

EOF

case "$WIFI_DRIVER" in
    iwlwifi)
        cat >> "$OUTPUT" << 'EOF'
# Intel WiFi (iwlwifi) — module, firmware from linux-firmware
$SC --module IWLWIFI
$SC --module IWLMVM
EOF
        ;;
    brcmfmac)
        cat >> "$OUTPUT" << 'EOF'
# Broadcom WiFi (brcmfmac) — module, firmware from linux-firmware
$SC --module BRCMUTIL
$SC --module BRCMFMAC
$SC --enable BRCMFMAC_PCIE
EOF
        ;;
    mwifiex)
        cat >> "$OUTPUT" << 'EOF'
# Marvell WiFi (mwifiex) — module, firmware: mrvl/pcie8897_uapsta.bin
$SC --module MWIFIEX
$SC --module MWIFIEX_PCIE
EOF
        ;;
    ath11k)
        cat >> "$OUTPUT" << 'EOF'
# Qualcomm Atheros WiFi 6 (ath11k) — module
$SC --module ATH11K
$SC --module ATH11K_PCI
EOF
        ;;
    ath12k)
        cat >> "$OUTPUT" << 'EOF'
# Qualcomm Atheros WiFi 7 (ath12k) — module
$SC --module ATH12K
$SC --module ATH12K_PCI
EOF
        ;;
    mt76)
        cat >> "$OUTPUT" << 'EOF'
# MediaTek WiFi (mt76) — module
$SC --module MT76_CORE
$SC --module MT7921_COMMON
$SC --module MT7921E
EOF
        ;;
    rtw89)
        cat >> "$OUTPUT" << 'EOF'
# Realtek WiFi (rtw89) — module
$SC --module RTW89_CORE
$SC --module RTW89_PCI
EOF
        ;;
    rtw88)
        cat >> "$OUTPUT" << 'EOF'
# Realtek WiFi (rtw88) — module
$SC --module RTW88_CORE
$SC --module RTW88_PCI
EOF
        ;;
    *)
        cat >> "$OUTPUT" << 'EOF'
# TODO: WiFi driver not detected — add manually from harvest PCI data
# Common options: IWLWIFI, BRCMFMAC, MWIFIEX, ATH11K, ATH12K, MT76, RTW89
EOF
        ;;
esac

cat >> "$OUTPUT" << 'EOF'

echo "  [OK] WiFi"

# ==========================================================================
# PHASE 10: BLUETOOTH
# ==========================================================================
echo "[Phase 10] Bluetooth..."

$SC --module BT
$SC --module BT_RFCOMM
$SC --module BT_BNEP
$SC --module BT_HIDP
$SC --module BT_HCIBTUSB
$SC --enable BT_HCIBTUSB_AUTOSUSPEND

EOF

case "$BT_DRIVER" in
    intel)    echo '$SC --module BT_INTEL' >> "$OUTPUT" ;;
    broadcom) echo '$SC --module BT_BCM' >> "$OUTPUT" ;;
    marvell)  echo '# Marvell BT uses btusb (no separate module)' >> "$OUTPUT" ;;
    *)        echo '# TODO: verify Bluetooth sub-driver from harvest data' >> "$OUTPUT" ;;
esac

cat >> "$OUTPUT" << 'EOF'

echo "  [OK] Bluetooth"

EOF

# ==========================================================================
# PHASE 11: THUNDERBOLT (conditional)
# ==========================================================================
if [ $HAS_TB -eq 1 ]; then
    cat >> "$OUTPUT" << 'EOF'
# ==========================================================================
# PHASE 11: THUNDERBOLT
# ==========================================================================
echo "[Phase 11] Thunderbolt..."

$SC --module THUNDERBOLT
$SC --module INTEL_WMI_THUNDERBOLT

echo "  [OK] Thunderbolt"

EOF
fi

# ==========================================================================
# PHASE 12: PLATFORM-SPECIFIC
# ==========================================================================
cat >> "$OUTPUT" << 'EOF'
# ==========================================================================
# PHASE 12: PLATFORM-SPECIFIC
# ==========================================================================
echo "[Phase 12] Platform drivers..."

EOF

case "$PLATFORM" in
    dell)
        cat >> "$OUTPUT" << 'EOF'
# Dell platform — parent toggle required
$SC --enable X86_PLATFORM_DRIVERS_DELL
$SC --module DELL_LAPTOP
$SC --module DELL_WMI
$SC --module DELL_SMBIOS
$SC --enable DELL_SMBIOS_WMI
$SC --enable DELL_SMBIOS_SMM
EOF
        ;;
    apple)
        cat >> "$OUTPUT" << 'EOF'
$SC --enable APPLE_PROPERTIES
$SC --module SENSORS_APPLESMC
$SC --module APPLE_MFI_FASTCHARGE
$SC --module APPLE_GMUX
$SC --module HID_APPLE
$SC --module BACKLIGHT_APPLE
$SC --module MOUSE_BCM5974
EOF
        ;;
    lenovo)
        cat >> "$OUTPUT" << 'EOF'
# TODO: verify ThinkPad vs IdeaPad
$SC --module THINKPAD_ACPI 2>/dev/null || true
# $SC --module IDEAPAD_LAPTOP 2>/dev/null || true
EOF
        ;;
    hp)
        cat >> "$OUTPUT" << 'EOF'
$SC --module HP_WMI
EOF
        ;;
    surface)
        cat >> "$OUTPUT" << 'EOF'
$SC --enable SURFACE_PLATFORMS

# Surface Aggregator Module (SAM)
$SC --module SURFACE_AGGREGATOR
$SC --enable SURFACE_AGGREGATOR_BUS
$SC --module SURFACE_AGGREGATOR_REGISTRY
$SC --module SURFACE_AGGREGATOR_CDEV
$SC --module SURFACE_AGGREGATOR_HUB
$SC --module SURFACE_AGGREGATOR_TABLET_SWITCH

# Surface ACPI and power
$SC --module SURFACE_ACPI_NOTIFY
$SC --module SURFACE_GPE
$SC --module SURFACE_PLATFORM_PROFILE
$SC --module SURFACE_HOTPLUG

# Surface HID
$SC --module SURFACE_HID_CORE
$SC --module SURFACE_HID
$SC --module SURFACE_KBD

# Surface buttons/battery
$SC --module SURFACE_PRO3_BUTTON
$SC --module BATTERY_SURFACE
$SC --module CHARGER_SURFACE
$SC --module SENSORS_SURFACE_FAN
$SC --module SENSORS_SURFACE_TEMP
EOF
        ;;
    asus)
        cat >> "$OUTPUT" << 'EOF'
$SC --module ASUS_WMI
$SC --module ASUS_NB_WMI 2>/dev/null || true
EOF
        ;;
    *)
        echo '# No vendor-specific platform drivers detected' >> "$OUTPUT"
        ;;
esac

cat >> "$OUTPUT" << 'EOF'

echo "  [OK] Platform"

EOF

# ==========================================================================
# PHASE 13: ISH Sensors (conditional)
# ==========================================================================
if [ $HAS_ISH -eq 1 ]; then
    cat >> "$OUTPUT" << 'EOF'
# ==========================================================================
# PHASE 13: INTEL SENSOR HUB (ISH)
# ==========================================================================
echo "[Phase 13] Intel Sensor Hub..."

$SC --module INTEL_ISH_HID
$SC --module INTEL_ISH_FIRMWARE_DOWNLOADER
$SC --module HID_SENSOR_HUB
$SC --module HID_SENSOR_ACCEL_3D
$SC --module HID_SENSOR_GYRO_3D
$SC --module HID_SENSOR_ALS

$SC --module HID_SENSOR_IIO_COMMON
$SC --module HID_SENSOR_IIO_TRIGGER
$SC --module IIO

echo "  [OK] Sensors"

EOF
fi

# ==========================================================================
# PHASE 14: Camera (conditional)
# ==========================================================================
if [ $HAS_IPU3 -eq 1 ] || [ $HAS_IPU6 -eq 1 ]; then
    cat >> "$OUTPUT" << 'EOF'
# ==========================================================================
# PHASE 14: CAMERA
# ==========================================================================
echo "[Phase 14] Camera..."

$SC --enable STAGING
$SC --enable STAGING_MEDIA
$SC --enable MEDIA_SUPPORT
$SC --enable MEDIA_CAMERA_SUPPORT
$SC --enable VIDEO_DEV

EOF
    if [ $HAS_IPU3 -eq 1 ]; then
        cat >> "$OUTPUT" << 'EOF'
# IPU3 camera pipeline
$SC --module VIDEO_IPU3_CIO2
$SC --module VIDEO_IPU3_IMGU
$SC --module IPU_BRIDGE
$SC --module INTEL_SKL_INT3472
# TODO: identify camera sensors from harvest (OV5693, OV8865, OV7251, etc.)
EOF
    fi
    if [ $HAS_IPU6 -eq 1 ]; then
        cat >> "$OUTPUT" << 'EOF'
# IPU6 camera pipeline
$SC --module IPU_BRIDGE 2>/dev/null || true
$SC --module VIDEO_INTEL_IPU6 2>/dev/null || echo "  [INFO] IPU6 may need out-of-tree driver"
$SC --module INTEL_SKL_INT3472 2>/dev/null || true
# TODO: identify camera sensors from harvest
EOF
    fi
    cat >> "$OUTPUT" << 'EOF'

echo "  [OK] Camera"

EOF
fi

# ==========================================================================
# PHASE 15: Card Reader (conditional)
# ==========================================================================
if [ $HAS_RTSX -eq 1 ]; then
    cat >> "$OUTPUT" << 'EOF'
# ==========================================================================
# PHASE 15: CARD READER
# ==========================================================================
echo "[Phase 15] Card reader..."

$SC --module MISC_RTSX_PCI
$SC --module MMC_REALTEK_PCI

echo "  [OK] Card reader"

EOF
fi

# ==========================================================================
# PHASES 16-25: Standard sections (same for all machines)
# ==========================================================================
cat >> "$OUTPUT" << 'EOF'
# ==========================================================================
# PHASE 16: USB / HID
# ==========================================================================
echo "[Phase 16] USB and HID..."

$SC --enable USB
$SC --enable USB_XHCI_HCD
$SC --enable USB_XHCI_PCI

$SC --enable HID
$SC --enable USB_HID
$SC --module HID_MULTITOUCH
$SC --enable INPUT_MOUSEDEV
$SC --enable INPUT_EVDEV
$SC --enable INPUT_UINPUT

echo "  [OK] USB/HID"

# ==========================================================================
# PHASE 17: USB ETHERNET
# ==========================================================================
echo "[Phase 17] USB Ethernet..."

EOF

# Onboard Ethernet
for drv in $ETH_DRIVERS; do
    case "$drv" in
        igc)       echo '$SC --module IGC' >> "$OUTPUT" ;;
        e1000e)    echo '$SC --module E1000E' >> "$OUTPUT" ;;
        r8169)     echo '$SC --module R8169' >> "$OUTPUT" ;;
        igb)       echo '$SC --module IGB' >> "$OUTPUT" ;;
        ixgbe)     echo '$SC --module IXGBE' >> "$OUTPUT" ;;
        mlx5_core) echo '$SC --module MLX5_CORE' >> "$OUTPUT" ;;
    esac
done

cat >> "$OUTPUT" << 'EOF'
# USB Ethernet (for USB-C hubs/dongles)
$SC --module USB_RTL8152
$SC --module USB_NET_CDCETHER
$SC --module USB_NET_AX88179_178A

echo "  [OK] Ethernet"

# ==========================================================================
# PHASE 18: I2C / SERIAL IO
# ==========================================================================
echo "[Phase 18] I2C and Serial IO..."

$SC --enable MFD_INTEL_LPSS
$SC --enable MFD_INTEL_LPSS_ACPI
$SC --enable MFD_INTEL_LPSS_PCI

$SC --enable I2C_DESIGNWARE_CORE
$SC --enable I2C_DESIGNWARE_PLATFORM
$SC --enable I2C_DESIGNWARE_PCI

$SC --module I2C_I801

# Pinctrl
$SC --enable PINCTRL
$SC --enable PINCTRL_INTEL
EOF

# Add platform-specific pinctrl
case "$INTEL_GPU_GEN" in
    tgl)  echo '$SC --enable PINCTRL_TIGERLAKE' >> "$OUTPUT" ;;
    adlp) echo '$SC --enable PINCTRL_ALDERLAKE 2>/dev/null || true' >> "$OUTPUT" ;;
    kbl)  echo '$SC --enable PINCTRL_SUNRISEPOINT' >> "$OUTPUT" ;;
    skl)  echo '$SC --enable PINCTRL_SUNRISEPOINT' >> "$OUTPUT" ;;
    icl)  echo '$SC --enable PINCTRL_ICELAKE' >> "$OUTPUT" ;;
    *)    echo '# TODO: add correct PINCTRL for your platform' >> "$OUTPUT" ;;
esac

cat >> "$OUTPUT" << 'EOF'

echo "  [OK] I2C"

# ==========================================================================
# PHASE 19: ACPI / POWER
# ==========================================================================
echo "[Phase 19] ACPI platform..."

$SC --enable PCI
$SC --enable PCIEPORTBUS
$SC --enable ACPI
$SC --enable ACPI_AC
$SC --enable ACPI_BATTERY
$SC --enable ACPI_BUTTON
$SC --enable ACPI_FAN
$SC --enable ACPI_PROCESSOR
$SC --enable ACPI_THERMAL
$SC --enable ACPI_VIDEO

$SC --module ACPI_WMI

# MEI (Management Engine)
$SC --module INTEL_MEI
$SC --module INTEL_MEI_ME
$SC --module INTEL_MEI_HDCP
$SC --module INTEL_MEI_PXP

# Watchdog
$SC --module ITCO_WDT
$SC --enable ITCO_VENDOR_SUPPORT

echo "  [OK] ACPI"

# ==========================================================================
# PHASE 20: SUSPEND / POWER
# ==========================================================================
echo "[Phase 20] Suspend and power..."

$SC --enable SUSPEND
$SC --enable HIBERNATE_CALLBACKS
$SC --enable HIBERNATION

echo "  [OK] Suspend"

# ==========================================================================
# PHASE 21: NETWORKING / VPN
# ==========================================================================
echo "[Phase 21] Networking and VPN..."

$SC --enable NET
$SC --enable INET
$SC --enable IPV6
$SC --enable NETFILTER
$SC --enable NF_TABLES
$SC --module NF_CONNTRACK
$SC --module NF_NAT
$SC --module NFT_CT
$SC --module NFT_FIB
$SC --module NFT_REJECT

$SC --module TUN

# PPP for SSTP VPN
$SC --enable PPP
$SC --enable PPP_BSDCOMP
$SC --enable PPP_DEFLATE
$SC --enable PPP_MPPE
$SC --enable PPP_ASYNC
$SC --enable PPP_SYNC_TTY
$SC --enable PPP_MULTILINK
$SC --enable PPP_FILTER

echo "  [OK] Networking"

# ==========================================================================
# PHASE 22: FIRMWARE LOADING
# ==========================================================================
echo "[Phase 22] Firmware..."

$SC --enable FW_LOADER
$SC --enable FW_LOADER_USER_HELPER
$SC --set-str EXTRA_FIRMWARE ""

echo "  [OK] Firmware"

# ==========================================================================
# PHASE 23: EFI BOOT
# ==========================================================================
echo "[Phase 23] EFI boot..."

$SC --enable EFI
$SC --enable EFI_STUB
$SC --enable EFI_MIXED

echo "  [OK] EFI"

# ==========================================================================
# PHASE 24: CRYPTO
# ==========================================================================
echo "[Phase 24] Hardware crypto..."

$SC --module CRYPTO_AES_NI_INTEL
$SC --module CRYPTO_GHASH_CLMUL_NI_INTEL
$SC --module CRYPTO_POLYVAL_CLMUL_NI
$SC --module CRYPTO_SHA256_SSSE3
$SC --module CRYPTO_SHA512_SSSE3

echo "  [OK] Crypto"

# ==========================================================================
# PHASE 25: SECURITY
# ==========================================================================
echo "[Phase 25] Security..."

$SC --enable SECURITY
$SC --enable SECCOMP
$SC --enable SECURITY_YAMA
$SC --enable MITIGATION_PAGE_TABLE_ISOLATION
$SC --enable MITIGATION_RETPOLINE

echo "  [OK] Security"

# ==========================================================================
# PHASE 26: DISABLE UNNECESSARY HARDWARE
# ==========================================================================
echo "[Phase 26] Disabling unnecessary hardware..."

EOF

# Disable CPUs not present
if [ "$CPU_VENDOR" = "GenuineIntel" ]; then
    echo '$SC --disable CPU_SUP_AMD' >> "$OUTPUT"
    echo '$SC --disable DRM_AMDGPU' >> "$OUTPUT"
    echo '$SC --disable DRM_RADEON' >> "$OUTPUT"
elif [ "$CPU_VENDOR" = "AuthenticAMD" ]; then
    echo '$SC --disable CPU_SUP_INTEL' >> "$OUTPUT"
fi

# Disable GPUs not present
if [ $HAS_NVIDIA_GPU -eq 0 ]; then
    echo '$SC --disable DRM_NOUVEAU' >> "$OUTPUT"
fi
if [ $HAS_INTEL_GPU -eq 0 ] && [ $HAS_AMD_GPU -eq 0 ]; then
    echo '# TODO: review GPU disables' >> "$OUTPUT"
fi

cat >> "$OUTPUT" << 'EOF'

# Legacy / enterprise (not needed on desktop/laptop)
$SC --disable INFINIBAND
$SC --disable SOUND_OSS_CORE
$SC --disable PCMCIA
$SC --disable PARPORT

# iSCSI (not needed)
$SC --disable BE2ISCSI
$SC --disable BNX2I
$SC --disable CXGB4I
$SC --disable CXGB3I
$SC --disable QLA4XXX
$SC --disable SCSI_CXGB3_ISCSI
$SC --disable SCSI_CXGB4_ISCSI

EOF

# Disable WiFi drivers not used
case "$WIFI_DRIVER" in
    iwlwifi)
        cat >> "$OUTPUT" << 'EOF'
# WiFi drivers not present
$SC --disable BRCMUTIL
$SC --disable BRCMFMAC
$SC --disable MWIFIEX
$SC --disable MWIFIEX_PCIE
EOF
        ;;
    brcmfmac)
        cat >> "$OUTPUT" << 'EOF'
$SC --disable IWLWIFI
$SC --disable IWLMVM
$SC --disable MWIFIEX
$SC --disable MWIFIEX_PCIE
EOF
        ;;
    mwifiex)
        cat >> "$OUTPUT" << 'EOF'
$SC --disable IWLWIFI
$SC --disable IWLMVM
$SC --disable BRCMUTIL
$SC --disable BRCMFMAC
EOF
        ;;
    *)
        echo '# TODO: disable unused WiFi drivers' >> "$OUTPUT"
        ;;
esac

# Disable platform drivers not used
if [ "$PLATFORM" != "apple" ]; then
    cat >> "$OUTPUT" << 'EOF'

# Apple (not present)
$SC --disable HID_APPLE
$SC --disable SENSORS_APPLESMC
$SC --disable APPLE_PROPERTIES
$SC --disable MACINTOSH_DRIVERS 2>/dev/null || true
EOF
fi

if [ "$PLATFORM" != "surface" ]; then
    echo '$SC --disable SURFACE_PLATFORMS 2>/dev/null || true' >> "$OUTPUT"
fi

cat >> "$OUTPUT" << 'EOF'

echo "  [OK] Disabled"

# ==========================================================================
# DONE
# ==========================================================================
echo ""
EOF

cat >> "$OUTPUT" << EOF
echo "=== $MACHINE_PRETTY kernel config applied ==="
echo "TODO: Review all settings and verify on live hardware"
echo ""
echo "Next steps:"
echo "  1. make olddefconfig              # resolve dependencies"
echo "  2. make menuconfig                # REVIEW CAREFULLY"
echo "  3. make -j$BUILD_JOBS"
echo "  4. make modules_install"
echo "  5. make install"
echo ""
echo "Required firmware (check harvest section 7 + 14):"
echo "  Install sys-kernel/linux-firmware for all module-loaded drivers"
EOF

chmod +x "$OUTPUT"

echo ""
echo "Generated: $OUTPUT"
echo "  $(wc -l < "$OUTPUT") lines"
echo ""

# ============================================================================
# PHASE 3: Auto-run kconfig-lint (if kernel source available)
# ============================================================================
LINT="$SCRIPT_DIR/kconfig-lint.sh"
if [[ -x "$LINT" ]] && [[ -d /usr/src/linux/kernel ]]; then
    echo "Running kconfig-lint on generated config..."
    echo ""
    "$LINT" "$OUTPUT" /usr/src/linux || true
else
    echo "Skipping kconfig-lint (kernel source not at /usr/src/linux or lint not found)"
    echo "  Run manually: tools/kconfig-lint.sh $OUTPUT /path/to/linux"
fi
