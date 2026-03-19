#!/bin/bash
# ============================================================================
# Machine Feature Profile — Shared Hardware Detection Library
# ============================================================================
# Parses harvest.sh output and sets feature flags for use by other tools.
# Source this file, don't execute it directly.
#
# Usage:
#   HARVEST="/path/to/hardware_inventory.log"
#   source tools/machine-profile.sh
#
# After sourcing, these variables are set:
#   CPU:      CPU_VENDOR, CPU_MODEL_NAME, NR_CPUS, GCC_MARCH, CPU_FLAGS
#   GPU:      HAS_INTEL_GPU, INTEL_GPU_GEN, HAS_NVIDIA_GPU, NVIDIA_GPU_COUNT, HAS_AMD_GPU
#   WiFi:     WIFI_DRIVER (iwlwifi|brcmfmac|mwifiex|ath11k|ath12k|mt76|rtw89|rtw88|"")
#   BT:       BT_DRIVER (intel|broadcom|marvell|generic)
#   Audio:    AUDIO_TYPE (sof|hda), AUDIO_CODEC (realtek|cirrus|"")
#   Storage:  HAS_NVME, HAS_SATA, BOOT_DRIVE_TYPE (nvme|sata|unknown)
#   Network:  ETH_DRIVERS (space-separated list)
#   Platform: PLATFORM (dell|apple|lenovo|hp|surface|asus|generic)
#   Boot:     BOOT_EFI (1|0)
#   Suspend:  SUSPEND_S3 (1|0)
#   Chassis:  CHASSIS_TYPE, IS_LAPTOP (1|0)
#   Features: HAS_TB, HAS_ISH, HAS_RTSX, HAS_IPU3, HAS_IPU6, HAS_SAM,
#             HAS_EDAC, HAS_NUMA, HAS_OPTICAL
# ============================================================================

if [[ -z "${HARVEST:-}" ]]; then
    echo "ERROR: Set HARVEST=/path/to/hardware_inventory.log before sourcing machine-profile.sh" >&2
    return 1 2>/dev/null || exit 1
fi

if [[ ! -f "$HARVEST" ]]; then
    echo "ERROR: Harvest file not found: $HARVEST" >&2
    return 1 2>/dev/null || exit 1
fi

# ============================================================================
# CPU
# ============================================================================
CPU_VENDOR=$(grep -m1 'Vendor ID:' "$HARVEST" | awk '{print $NF}')
CPU_MODEL_NAME=$(grep -m1 'Model name:' "$HARVEST" | sed 's/.*Model name:[[:space:]]*//')
NR_CPUS=$(grep -m1 'CPU threads (nproc):' "$HARVEST" | awk '{print $NF}')
[[ -z "$NR_CPUS" || "$NR_CPUS" == "unknown" ]] && NR_CPUS=8

# Xeon detection — may have more threads than nproc reports
if echo "$CPU_MODEL_NAME" | grep -qiE 'Xeon|EPYC'; then
    LSCPU_CPUS=$(grep -m1 'CPU(s):' "$HARVEST" | awk '{print $NF}')
    [[ -n "$LSCPU_CPUS" ]] && [[ "$LSCPU_CPUS" =~ ^[0-9]+$ ]] && NR_CPUS="$LSCPU_CPUS"
fi

GCC_MARCH=$(grep 'Suggested:.*-march=' "$HARVEST" | head -1 | grep -oP '(?<=-march=)\S+' || echo "")
CPU_FLAGS=$(grep 'CPU_FLAGS_X86' "$HARVEST" | head -1 | sed 's/.*CPU_FLAGS_X86[^:]*:[[:space:]]*//' || echo "")

# ============================================================================
# GPU
# ============================================================================
HAS_INTEL_GPU=0
HAS_NVIDIA_GPU=0
HAS_AMD_GPU=0
INTEL_GPU_GEN=""
NVIDIA_GPU_COUNT=0

if grep -q 'i915' "$HARVEST"; then
    HAS_INTEL_GPU=1
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

if grep -qiE 'nvidia|nouveau' "$HARVEST"; then
    HAS_NVIDIA_GPU=1
    NVIDIA_GPU_COUNT=$(grep -c 'VGA compatible controller.*NVIDIA\|3D controller.*NVIDIA' "$HARVEST" 2>/dev/null || echo "1")
    [ "$NVIDIA_GPU_COUNT" -eq 0 ] && NVIDIA_GPU_COUNT=1
fi

grep -qiE 'amdgpu|radeon' "$HARVEST" && HAS_AMD_GPU=1

# ============================================================================
# WiFi
# ============================================================================
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

# ============================================================================
# Bluetooth
# ============================================================================
BT_DRIVER=""
if grep -q 'btintel\|btusb.*Intel' "$HARVEST"; then BT_DRIVER="intel"
elif grep -q 'btbcm' "$HARVEST"; then BT_DRIVER="broadcom"
elif grep -q 'btmrvl\|btmtksdio' "$HARVEST"; then BT_DRIVER="marvell"
else BT_DRIVER="generic"
fi

# ============================================================================
# Audio
# ============================================================================
AUDIO_TYPE="hda"
if grep -q 'Type: SOF' "$HARVEST" || grep -q 'snd_sof' "$HARVEST"; then
    AUDIO_TYPE="sof"
elif grep -q 'Type: HDA' "$HARVEST" || grep -q 'snd_hda_intel' "$HARVEST"; then
    AUDIO_TYPE="hda"
fi

AUDIO_CODEC=""
if grep -qi 'realtek\|ALC[0-9]' "$HARVEST"; then AUDIO_CODEC="realtek"
elif grep -qi 'cs420[0-9]\|Cirrus' "$HARVEST"; then AUDIO_CODEC="cirrus"
fi

# ============================================================================
# Storage
# ============================================================================
HAS_NVME=0
HAS_SATA=0
grep -q 'nvme' "$HARVEST" && HAS_NVME=1
grep -qiE 'ahci|sata' "$HARVEST" && HAS_SATA=1

BOOT_DRIVE_TYPE="unknown"
if grep -qE 'nvme[0-9].*/$' "$HARVEST" 2>/dev/null || grep -qE 'nvme.*[[:space:]]/[[:space:]]' "$HARVEST" 2>/dev/null; then
    BOOT_DRIVE_TYPE="nvme"
elif grep -qE 'sd[a-z].*/$' "$HARVEST" 2>/dev/null || grep -qE 'sd[a-z].*[[:space:]]/[[:space:]]' "$HARVEST" 2>/dev/null; then
    BOOT_DRIVE_TYPE="sata"
elif [ $HAS_NVME -eq 1 ] && [ $HAS_SATA -eq 0 ]; then
    BOOT_DRIVE_TYPE="nvme"
elif [ $HAS_SATA -eq 1 ] && [ $HAS_NVME -eq 0 ]; then
    BOOT_DRIVE_TYPE="sata"
elif [ $HAS_NVME -eq 1 ]; then
    BOOT_DRIVE_TYPE="nvme"
fi

# ============================================================================
# Network (Ethernet)
# ============================================================================
ETH_DRIVERS=""
for drv in igc e1000e r8169 r8152 igb ixgbe mlx5_core atlantic ax88179 cdc_ether; do
    grep -q "$drv" "$HARVEST" && ETH_DRIVERS="$ETH_DRIVERS $drv"
done
ETH_DRIVERS="${ETH_DRIVERS# }"  # trim leading space

# ============================================================================
# Platform
# ============================================================================
PLATFORM="generic"
if grep -q 'Platform: DELL' "$HARVEST"; then PLATFORM="dell"
elif grep -q 'Platform: APPLE' "$HARVEST"; then PLATFORM="apple"
elif grep -q 'Platform: LENOVO' "$HARVEST"; then PLATFORM="lenovo"
elif grep -q 'Platform: HP' "$HARVEST"; then PLATFORM="hp"
elif grep -q 'Platform: SURFACE' "$HARVEST"; then PLATFORM="surface"
elif grep -q 'Platform: ASUS' "$HARVEST"; then PLATFORM="asus"
fi

# ============================================================================
# Boot & Suspend
# ============================================================================
BOOT_EFI=1
grep -q 'Boot: BIOS' "$HARVEST" && BOOT_EFI=0

SUSPEND_S3=0
grep -q 'S3 deep: supported' "$HARVEST" && SUSPEND_S3=1

# ============================================================================
# Chassis & Form Factor
# ============================================================================
CHASSIS_TYPE=$(grep -m1 'chassis_type:' "$HARVEST" | awk '{print $NF}' || echo "")
IS_LAPTOP=1  # default: assume laptop (safer for power config)
case "$CHASSIS_TYPE" in
    3|4|5|6|7|15|16|17|24) IS_LAPTOP=0 ;;  # desktop/tower/server
esac

# ============================================================================
# Hardware Features
# ============================================================================
HAS_TB=0;    grep -qi 'thunderbolt' "$HARVEST" && HAS_TB=1
HAS_ISH=0;   grep -qi 'intel_ish\|ISH' "$HARVEST" && HAS_ISH=1
HAS_RTSX=0;  grep -qi 'rtsx\|RTS[0-9]' "$HARVEST" && HAS_RTSX=1
HAS_IPU3=0;  grep -qi 'ipu3\|IPU3' "$HARVEST" && HAS_IPU3=1
HAS_IPU6=0;  grep -qi 'ipu6\|IPU6\|intel_ipu6' "$HARVEST" && HAS_IPU6=1
HAS_SAM=0;   grep -qi 'surface_aggregator\|SURFACE_AGGREGATOR' "$HARVEST" && HAS_SAM=1
HAS_EDAC=0;  grep -qi 'sb_edac\|skx_edac\|i10nm_edac\|amd64_edac\|edac' "$HARVEST" && HAS_EDAC=1
HAS_OPTICAL=0; grep -qi 'DVD\|Blu-ray\|CD-ROM\|sr0\|HL-DT-ST' "$HARVEST" && HAS_OPTICAL=1

HAS_NUMA=0
if echo "$CPU_MODEL_NAME" | grep -qiE 'Xeon.*E[57]|Xeon W|EPYC'; then
    HAS_NUMA=1
fi

# ============================================================================
# Convenience: summary (only printed if MP_SUMMARY=1)
# ============================================================================
if [[ "${MP_SUMMARY:-0}" == "1" ]]; then
    echo "Machine Profile: $HARVEST"
    echo "  CPU:      $CPU_MODEL_NAME ($CPU_VENDOR, ${NR_CPUS}T, -march=$GCC_MARCH)"
    echo "  GPU:      Intel=$HAS_INTEL_GPU($INTEL_GPU_GEN) NVIDIA=$HAS_NVIDIA_GPU(x$NVIDIA_GPU_COUNT) AMD=$HAS_AMD_GPU"
    echo "  WiFi:     ${WIFI_DRIVER:-none}"
    echo "  BT:       ${BT_DRIVER}"
    echo "  Audio:    $AUDIO_TYPE${AUDIO_CODEC:+ ($AUDIO_CODEC)}"
    echo "  Storage:  NVMe=$HAS_NVME SATA=$HAS_SATA Boot=$BOOT_DRIVE_TYPE"
    echo "  Ethernet: ${ETH_DRIVERS:-none}"
    echo "  Platform: $PLATFORM"
    echo "  Chassis:  $([ $IS_LAPTOP -eq 1 ] && echo 'Laptop' || echo 'Desktop/Tower') (type=$CHASSIS_TYPE)"
    echo "  Boot:     $([ $BOOT_EFI -eq 1 ] && echo 'EFI' || echo 'BIOS') Suspend=$([ $SUSPEND_S3 -eq 1 ] && echo 'S3' || echo 's2idle')"
    echo "  Features: TB=$HAS_TB ISH=$HAS_ISH RTSX=$HAS_RTSX SAM=$HAS_SAM EDAC=$HAS_EDAC NUMA=$HAS_NUMA"
fi
