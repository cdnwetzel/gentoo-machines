#!/bin/bash
# ============================================================================
# Gentoo Kernel Config - Dell XPS 13 9315
# ============================================================================
# WARNING: Best-effort — not verified on live system (returned to Windows)
#
# Derived from:
#   - XPS 9315 HARDWARE.md (PCI IDs, drivers, firmware from live harvest)
#   - XPS 9315 production .config (kernel 6.12.58-gentoo)
#   - Surface Pro 6 kernel_config.sh template (25-phase structure)
#   - XPS 9510 kernel_config.sh (sibling Intel platform)
#
# ALDER LAKE SPECIFICS:
#   - Hybrid P-Core/E-Core: X86_HYBRID_CPUS=y
#   - HFI thermal scheduling: INTEL_HFI_THERMAL=y
#   - SOF audio (NOT HDA): sof-audio-pci-intel-tgl
#   - IPU6 camera: intel_ipu6 ISP
#   - Firmware originally embedded in kernel (CONFIG_EXTRA_FIRMWARE)
#     Consider switching to module-based loading for consistency
#   - No AVX-512 (fused off on consumer Alder Lake)
#
# USAGE:
#   cd /usr/src/linux
#   make defconfig
#   bash /path/to/kernel_config.sh
#   make olddefconfig
#   make -j13 && make modules_install && make install
#
# BOOT STRATEGY: No initramfs — all root-path drivers built-in (=y)
# ============================================================================

set -euo pipefail

SC="./scripts/config"

if [[ ! -x "$SC" ]]; then
    echo "ERROR: Run this from /usr/src/linux (scripts/config not found)"
    exit 1
fi

echo "=== Applying Dell XPS 13 9315 kernel config ==="
echo "WARNING: Best-effort — verify all settings on live hardware"
echo ""

# ==========================================================================
# PHASE 1: GENERAL / GENTOO
# ==========================================================================
echo "[Phase 1] General settings..."

$SC --enable IKCONFIG
$SC --enable IKCONFIG_PROC
$SC --set-str DEFAULT_HOSTNAME "xps-9315"

$SC --enable GENTOO_LINUX
$SC --enable GENTOO_LINUX_INIT_SCRIPT
$SC --enable GENTOO_LINUX_PORTAGE
$SC --enable GENTOO_LINUX_UDEV

echo "  [OK] General"

# ==========================================================================
# PHASE 2: PROCESSOR - Intel Core i5-1230U (Alder Lake, 2P+8E/12T)
# ==========================================================================
echo "[Phase 2] Processor configuration (Alder Lake hybrid)..."

$SC --enable SMP
$SC --set-val NR_CPUS 12
$SC --enable MCORE2

# Hybrid scheduling (Alder Lake P-Core/E-Core)
$SC --enable X86_HYBRID_CPUS 2>/dev/null || echo "  [INFO] X86_HYBRID_CPUS not available in this kernel"
$SC --enable INTEL_HFI_THERMAL 2>/dev/null || echo "  [INFO] INTEL_HFI_THERMAL not available in this kernel"

$SC --enable SCHED_MC
$SC --enable SCHED_SMT
$SC --enable SCHED_AUTOGROUP
$SC --enable X86_INTEL_PSTATE
$SC --enable CPU_FREQ_GOV_POWERSAVE
$SC --enable CPU_FREQ_DEFAULT_GOV_POWERSAVE
$SC --enable INTEL_IDLE
$SC --enable MICROCODE
$SC --enable X86_X2APIC

# Alder Lake thermal/power
$SC --enable INTEL_RAPL
$SC --enable X86_PKG_TEMP_THERMAL
$SC --enable INTEL_POWERCLAMP
$SC --enable CORETEMP

# DPTF thermal framework (Innovation Platform [8086:461d])
$SC --enable ACPI_DPTF
$SC --module INT340X_THERMAL
$SC --module ACPI_THERMAL_REL
$SC --module INTEL_PCH_THERMAL
$SC --module PROC_THERMAL_MMIO_RAPL

# KVM (CPU supports VMX)
$SC --module KVM
$SC --module KVM_INTEL

echo "  [OK] Processor"

# ==========================================================================
# PHASE 3: PERFORMANCE TUNING
# ==========================================================================
echo "[Phase 3] Performance tuning..."

# Upgrade from PREEMPT_VOLUNTARY (production config) to full PREEMPT
$SC --enable PREEMPT
$SC --enable PREEMPT_DYNAMIC
$SC --enable HZ_1000
$SC --enable NO_HZ_IDLE

# Transparent Huge Pages
$SC --enable TRANSPARENT_HUGEPAGE
$SC --enable TRANSPARENT_HUGEPAGE_ALWAYS

# MGLRU (was disabled in production — enable now)
$SC --enable LRU_GEN
$SC --enable LRU_GEN_ENABLED

# KSM (was disabled in production — enable now)
$SC --enable KSM

echo "  [OK] Performance"

# ==========================================================================
# PHASE 4: MEMORY / SWAP - 8GB RAM + zram
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

# ==========================================================================
# PHASE 5: STORAGE - Phison PS5019-E19 NVMe [1987:5019]
# ==========================================================================
echo "[Phase 5] NVMe storage (boot drive, must be built-in)..."

$SC --enable BLK_DEV_NVME
$SC --enable NVME_CORE

$SC --enable BLK_DEV_THROTTLING
$SC --enable IOSCHED_BFQ
$SC --enable BFQ_GROUP_IOSCHED

$SC --module USB_STORAGE
$SC --module USB_UAS

echo "  [OK] NVMe"

# ==========================================================================
# PHASE 6: FILESYSTEMS
# ==========================================================================
echo "[Phase 6] Filesystems..."

$SC --enable EXT4_FS
$SC --enable VFAT_FS
$SC --enable NLS_CODEPAGE_437
$SC --enable NLS_ISO8859_1
$SC --enable FAT_FS
$SC --enable MSDOS_FS

$SC --module BTRFS_FS
$SC --module XFS_FS
$SC --module EXFAT_FS
$SC --module FUSE_FS

$SC --enable TMPFS
$SC --enable PROC_FS
$SC --enable SYSFS

$SC --enable EFI_PARTITION
$SC --enable EFIVAR_FS

echo "  [OK] Filesystems"

# ==========================================================================
# PHASE 7: GPU - Intel Alder Lake-UP4 GT2 Iris Xe [8086:46aa]
# ==========================================================================
echo "[Phase 7] Intel i915 GPU..."

$SC --enable DRM
$SC --module DRM_I915
$SC --enable DRM_I915_CAPTURE_ERROR
$SC --enable DRM_I915_COMPRESS_ERROR
$SC --enable DRM_I915_USERPTR
$SC --enable DRM_I915_PXP

$SC --disable DRM_I915_GVT

$SC --enable FB
$SC --enable FB_EFI
$SC --enable FRAMEBUFFER_CONSOLE
$SC --enable DRM_FBDEV_EMULATION

$SC --enable BACKLIGHT_CLASS_DEVICE

echo "  [OK] GPU"

# ==========================================================================
# PHASE 8: AUDIO - Alder Lake Smart Sound [8086:51cc] (SOF)
# ==========================================================================
echo "[Phase 8] Audio (SOF — Sound Open Firmware)..."

# SOF audio — Alder Lake uses SOF, NOT classic HDA
$SC --enable SOUND
$SC --module SND
$SC --module SND_PCM
$SC --module SND_HWDEP
$SC --module SND_SEQ
$SC --module SND_TIMER
$SC --module SND_HRTIMER

# SOF driver stack
$SC --enable SND_SOC_SOF_TOPLEVEL
$SC --module SND_SOC_SOF_PCI_INTEL_TGL
$SC --module SND_SOC
$SC --module SND_SOC_SOF
$SC --enable SND_SOC_SOF_INTEL_TOPLEVEL
$SC --module SND_SOC_SOF_INTEL_PCI

# SoundWire (RT715 SDCA + RT1316 SDW codecs)
$SC --enable SOUNDWIRE 2>/dev/null || true
$SC --module SOUNDWIRE_INTEL 2>/dev/null || true

# HDA link (SOF still needs HDA for HDMI)
$SC --module SND_HDA_INTEL
$SC --module SND_HDA_CODEC_HDMI
$SC --enable SND_HDA_I915

echo "  [OK] Audio (SOF)"

# ==========================================================================
# PHASE 9: WIFI - Intel AX211 CNVi [8086:51f0]
# ==========================================================================
echo "[Phase 9] WiFi (Intel iwlwifi)..."

$SC --module CFG80211
$SC --enable CFG80211_WEXT
$SC --module MAC80211
$SC --module IWLWIFI
$SC --module IWLMVM

echo "  [OK] WiFi"

# ==========================================================================
# PHASE 10: BLUETOOTH - Intel AX211 [8087:0033]
# ==========================================================================
echo "[Phase 10] Bluetooth..."

$SC --module BT
$SC --module BT_RFCOMM
$SC --module BT_BNEP
$SC --module BT_HIDP
$SC --module BT_HCIBTUSB
$SC --enable BT_HCIBTUSB_AUTOSUSPEND
$SC --module BT_INTEL

echo "  [OK] Bluetooth"

# ==========================================================================
# PHASE 11: THUNDERBOLT 4 (Alder Lake)
# ==========================================================================
echo "[Phase 11] Thunderbolt 4..."

$SC --module THUNDERBOLT
$SC --module INTEL_WMI_THUNDERBOLT

echo "  [OK] Thunderbolt"

# ==========================================================================
# PHASE 12: CAMERA - Intel IPU6 [8086:465d]
# ==========================================================================
echo "[Phase 12] Camera (IPU6)..."

# IPU6 ISP
$SC --module IPU_BRIDGE 2>/dev/null || true
$SC --module VIDEO_INTEL_IPU6 2>/dev/null || echo "  [INFO] IPU6 may need out-of-tree driver"

# Camera PMIC (INT3472)
$SC --module INTEL_SKL_INT3472 2>/dev/null || true

# OV01A10 sensor
$SC --module VIDEO_OV01A10 2>/dev/null || true

# Visual Sensing Controller
$SC --module INTEL_MEI_VSC_HW 2>/dev/null || true

# Media/V4L2 framework
$SC --enable MEDIA_SUPPORT
$SC --enable MEDIA_CAMERA_SUPPORT
$SC --enable VIDEO_DEV

echo "  [OK] Camera (IPU6)"

# ==========================================================================
# PHASE 13: DELL PLATFORM
# ==========================================================================
echo "[Phase 13] Dell platform drivers..."

$SC --enable X86_PLATFORM_DRIVERS_DELL
$SC --module DELL_LAPTOP
$SC --module DELL_WMI
$SC --module DELL_SMBIOS
$SC --enable DELL_SMBIOS_WMI
$SC --enable DELL_SMBIOS_SMM
$SC --module DELL_SMO8800 2>/dev/null || true

echo "  [OK] Dell platform"

# ==========================================================================
# PHASE 14: INTEL ISH SENSORS [8086:51fc]
# ==========================================================================
echo "[Phase 14] Intel Sensor Hub..."

$SC --module INTEL_ISH_HID
$SC --module INTEL_ISH_FIRMWARE_DOWNLOADER

$SC --module HID_SENSOR_HUB
$SC --module HID_SENSOR_ACCEL_3D
$SC --module HID_SENSOR_GYRO_3D
$SC --module HID_SENSOR_ALS

$SC --module HID_SENSOR_IIO_COMMON
$SC --module HID_SENSOR_IIO_TRIGGER
$SC --module IIO

echo "  [OK] ISH Sensors"

# ==========================================================================
# PHASE 15: USB / HID
# ==========================================================================
echo "[Phase 15] USB and HID..."

$SC --enable USB
$SC --enable USB_XHCI_HCD
$SC --enable USB_XHCI_PCI

$SC --enable HID
$SC --enable USB_HID
$SC --module HID_MULTITOUCH
$SC --enable INPUT_MOUSEDEV
$SC --enable INPUT_EVDEV
$SC --enable INPUT_UINPUT

# HID-over-I2C touchpad [0488:102D]
$SC --module I2C_HID_ACPI 2>/dev/null || true

echo "  [OK] USB/HID"

# ==========================================================================
# PHASE 16: USB-C HUB / ETHERNET
# ==========================================================================
echo "[Phase 16] USB Ethernet..."

$SC --module USB_RTL8152
$SC --module USB_NET_CDCETHER
$SC --module USB_NET_AX88179_178A

echo "  [OK] USB Ethernet"

# ==========================================================================
# PHASE 17: I2C / SERIAL IO
# ==========================================================================
echo "[Phase 17] I2C and Serial IO..."

$SC --enable MFD_INTEL_LPSS
$SC --enable MFD_INTEL_LPSS_ACPI
$SC --enable MFD_INTEL_LPSS_PCI

$SC --enable I2C_DESIGNWARE_CORE
$SC --enable I2C_DESIGNWARE_PLATFORM
$SC --enable I2C_DESIGNWARE_PCI

$SC --module I2C_I801

# Pinctrl — Alder Lake
$SC --enable PINCTRL
$SC --enable PINCTRL_INTEL
$SC --enable PINCTRL_ALDERLAKE 2>/dev/null || true

echo "  [OK] I2C/Serial IO"

# ==========================================================================
# PHASE 18: ACPI / POWER
# ==========================================================================
echo "[Phase 18] ACPI platform..."

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

$SC --module INTEL_MEI
$SC --module INTEL_MEI_ME
$SC --module INTEL_MEI_HDCP
$SC --module INTEL_MEI_PXP

$SC --module ITCO_WDT
$SC --enable ITCO_VENDOR_SUPPORT

echo "  [OK] ACPI"

# ==========================================================================
# PHASE 19: SUSPEND / POWER
# ==========================================================================
echo "[Phase 19] Suspend and power..."

$SC --enable SUSPEND
$SC --enable HIBERNATE_CALLBACKS
$SC --enable HIBERNATION

echo "  [OK] Suspend"

# ==========================================================================
# PHASE 20: NETWORKING / VPN
# ==========================================================================
echo "[Phase 20] Networking and VPN..."

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
# PHASE 21: FIRMWARE LOADING
# ==========================================================================
echo "[Phase 21] Firmware..."

# Production 9315 embedded firmware in kernel (CONFIG_EXTRA_FIRMWARE)
# For consistency with other machines, switch to module-based loading:
$SC --enable FW_LOADER
$SC --enable FW_LOADER_USER_HELPER
$SC --set-str EXTRA_FIRMWARE ""

echo "  [OK] Firmware (module-based loading)"
echo "  NOTE: Production config embedded firmware. If issues arise,"
echo "  re-enable EXTRA_FIRMWARE with i915/adlp_*, iwlwifi-so-*, intel/ibt-0040-*"

# ==========================================================================
# PHASE 22: EFI BOOT
# ==========================================================================
echo "[Phase 22] EFI boot..."

$SC --enable EFI
$SC --enable EFI_STUB
$SC --enable EFI_MIXED

echo "  [OK] EFI"

# ==========================================================================
# PHASE 23: CRYPTO
# ==========================================================================
echo "[Phase 23] Hardware crypto..."

$SC --module CRYPTO_AES_NI_INTEL
$SC --module CRYPTO_GHASH_CLMUL_NI_INTEL
$SC --module CRYPTO_POLYVAL_CLMUL_NI
$SC --module CRYPTO_SHA256_SSSE3
$SC --module CRYPTO_SHA512_SSSE3

echo "  [OK] Crypto"

# ==========================================================================
# PHASE 24: SECURITY
# ==========================================================================
echo "[Phase 24] Security..."

$SC --enable SECURITY
$SC --enable SECCOMP
$SC --enable SECURITY_YAMA
$SC --enable MITIGATION_PAGE_TABLE_ISOLATION
$SC --enable MITIGATION_RETPOLINE

echo "  [OK] Security"

# ==========================================================================
# PHASE 25: DISABLE UNNECESSARY HARDWARE
# ==========================================================================
echo "[Phase 25] Disabling unnecessary hardware..."

$SC --disable CPU_SUP_AMD
$SC --disable DRM_AMDGPU
$SC --disable DRM_RADEON
$SC --disable DRM_NOUVEAU

$SC --disable HID_APPLE
$SC --disable SENSORS_APPLESMC
$SC --disable APPLE_PROPERTIES
$SC --disable MACINTOSH_DRIVERS 2>/dev/null || true

$SC --disable INFINIBAND
$SC --disable SOUND_OSS_CORE
$SC --disable PCMCIA
$SC --disable PARPORT

# No NVIDIA on this machine
$SC --disable DRM_QXL

# Broadcom/Marvell WiFi (not present)
$SC --disable BRCMUTIL
$SC --disable BRCMFMAC
$SC --disable MWIFIEX
$SC --disable MWIFIEX_PCIE

# Surface platform (not present)
$SC --disable SURFACE_PLATFORMS 2>/dev/null || true

echo "  [OK] Disabled"

# ==========================================================================
# DONE
# ==========================================================================
echo ""
echo "=== Dell XPS 13 9315 kernel config applied ==="
echo "WARNING: NOT verified on live hardware — review carefully"
echo ""
echo "Next steps:"
echo "  1. make olddefconfig              # resolve dependencies"
echo "  2. make menuconfig                # REVIEW CAREFULLY"
echo "  3. make -j13                      # build (2P+8E/12T)"
echo "  4. make modules_install"
echo "  5. make install"
echo ""
echo "Required firmware (from sys-kernel/linux-firmware):"
echo "  i915/adlp_dmc_ver2_16.bin         # GPU DMC"
echo "  i915/adlp_guc_70.bin              # GPU GuC"
echo "  i915/adlp_huc.bin                 # GPU HuC"
echo "  iwlwifi-so-a0-gf-a0-89.ucode     # WiFi"
echo "  intel/ibt-0040-0041.sfi + .ddc    # Bluetooth"
echo ""
echo "NOTE: Previous config embedded firmware in kernel."
echo "If module-based loading fails, add firmware paths to EXTRA_FIRMWARE."
