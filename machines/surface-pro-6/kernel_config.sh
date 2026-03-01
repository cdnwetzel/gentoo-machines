#!/bin/bash
# ============================================================================
# Gentoo Kernel Config - Microsoft Surface Pro 6
# ============================================================================
# ALL settings verified against:
#   - 5 rounds of live USB hardware harvesting (harvest.sh + deep_harvest.sh)
#   - Fedora 43 linux-surface kernel 6.18.8-1.surface.fc43.x86_64 config
#   - Cross-reference with MBP 2015, XPS 9315, XPS 9510 production configs
#   - Live dmesg, sysfs, /proc verification on actual hardware
#   - KERNEL_CONFIG_CROSSREF.md, FEDORA_REFERENCE.md, INSTALL_GOTCHAS.md
#
# BASE CONFIG: Start from MBP 2015 .config (kernel 6.18.x era, MGLRU+zstd)
# NOT XPS 9315 (older 6.12, missing MGLRU, missing CRYPTO_ZSTD)
#
# USAGE:
#   cd /usr/src/linux
#   cp /path/to/mbp-2015/.config .config    # start from MBP base
#   bash /path/to/kernel_config_surface_pro6.sh
#   make olddefconfig     # resolve all dependencies
#   make menuconfig       # review
#   make -j9 && make modules_install && make install
#
# BOOT STRATEGY: No initramfs — all root-path drivers built-in (=y)
# ============================================================================

set -euo pipefail

SC="./scripts/config"

if [[ ! -x "$SC" ]]; then
    echo "ERROR: Run this from /usr/src/linux (scripts/config not found)"
    exit 1
fi

echo "=== Applying Surface Pro 6 kernel config ==="
echo ""

# ==========================================================================
# PHASE 1: REMOVE APPLE-SPECIFIC CONFIGS (from MBP base)
# ==========================================================================
echo "[Phase 1] Removing Apple-specific hardware..."

$SC --disable APPLE_PROPERTIES
$SC --disable SENSORS_APPLESMC
$SC --disable APPLE_MFI_FASTCHARGE
$SC --disable APPLE_GMUX
$SC --disable HID_APPLE
$SC --disable BACKLIGHT_APPLE
$SC --disable MOUSE_BCM5974
$SC --disable KEYBOARD_APPLESPI
$SC --disable SPI_PXA2XX
$SC --disable SPI_PXA2XX_PCI
$SC --disable SPI_PXA2XX_PLATFORM
$SC --disable MOUSE_APPLETOUCH

# Remove Broadcom WiFi (MBP uses BCM43602)
$SC --disable BRCMUTIL
$SC --disable BRCMFMAC
$SC --disable BRCMFMAC_PCIE

# Remove Broadcom Bluetooth
$SC --disable BT_BCM

# Remove CS4208 audio codec (Apple)
$SC --disable SND_HDA_CODEC_CS420X

# Remove SATA AHCI as built-in (Surface uses NVMe)
# Keep AHCI as module for USB docks if needed
$SC --module SATA_AHCI

# Remove Thunderbolt (Surface Pro 6 has no Thunderbolt)
$SC --disable THUNDERBOLT
$SC --disable INTEL_WMI_THUNDERBOLT

# Remove I2C I801 (MBP SMBus, not on Surface)
$SC --disable I2C_I801

# Remove Macintosh drivers subsystem (MBP base has MACINTOSH_DRIVERS=y)
$SC --disable MACINTOSH_DRIVERS

echo "  [OK] Apple hardware removed"

# ==========================================================================
# PHASE 2: GENERAL / GENTOO
# ==========================================================================
echo "[Phase 2] General settings..."

$SC --enable IKCONFIG
$SC --enable IKCONFIG_PROC
$SC --set-str DEFAULT_HOSTNAME "surface-pro-6"

# Gentoo-specific (confirmed in all production configs)
$SC --enable GENTOO_LINUX
$SC --enable GENTOO_LINUX_INIT_SCRIPT
$SC --enable GENTOO_LINUX_PORTAGE
$SC --enable GENTOO_LINUX_UDEV

echo "  [OK] General"

# ==========================================================================
# PHASE 3: PROCESSOR - Intel Core i5-8250U (Kaby Lake-R, 4C/8T)
# ==========================================================================
echo "[Phase 3] Processor configuration..."

$SC --enable SMP
$SC --set-val NR_CPUS 8
$SC --enable MCORE2

$SC --enable SCHED_MC
$SC --enable SCHED_SMT
$SC --enable SCHED_AUTOGROUP
$SC --enable X86_INTEL_PSTATE
$SC --enable CPU_FREQ_DEFAULT_GOV_POWERSAVE
$SC --enable INTEL_IDLE
$SC --enable MICROCODE
$SC --enable X86_X2APIC

# Kaby Lake-R thermal/power (confirmed via /sys/class/thermal)
$SC --enable INTEL_RAPL
$SC --enable X86_PKG_TEMP_THERMAL
$SC --enable INTEL_POWERCLAMP
$SC --enable CORETEMP

# DPTF thermal framework (confirmed: INT3400, INT3403 thermal zones active)
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
# PHASE 4: PERFORMANCE TUNING
# ==========================================================================
echo "[Phase 4] Performance tuning..."

# Preempt (confirmed in Fedora surface kernel: PREEMPT_DYNAMIC + HZ=1000)
$SC --enable PREEMPT
$SC --enable PREEMPT_DYNAMIC
$SC --enable HZ_1000
$SC --enable NO_HZ_IDLE

# Transparent Huge Pages
$SC --enable TRANSPARENT_HUGEPAGE
$SC --enable TRANSPARENT_HUGEPAGE_ALWAYS

# MGLRU (Multi-Gen LRU — confirmed working on MBP 2015 production)
$SC --enable LRU_GEN
$SC --enable LRU_GEN_ENABLED

# KSM (Kernel Same-page Merging)
$SC --enable KSM

echo "  [OK] Performance"

# ==========================================================================
# PHASE 5: MEMORY / SWAP - 8GB RAM + zram
# ==========================================================================
echo "[Phase 5] Memory and zram..."

# zram MUST be built-in (no initramfs to load module)
# zram-init: load_on_start=no, unload_on_stop=no (can't rmmod built-in)
$SC --enable ZRAM
$SC --enable ZRAM_BACKEND_ZSTD
$SC --enable CRYPTO_ZSTD
$SC --enable ZSTD_COMPRESS
$SC --enable ZSTD_DECOMPRESS
$SC --set-str ZRAM_DEF_COMP "zstd"

$SC --enable SWAP
$SC --enable ZSWAP

# LZ4 still useful for other compression
$SC --enable LZ4_COMPRESS
$SC --enable LZ4HC_COMPRESS

echo "  [OK] Memory"

# ==========================================================================
# PHASE 6: STORAGE - SK hynix BC501 NVMe [1c5c:1327]
# ==========================================================================
echo "[Phase 6] NVMe storage (boot drive, must be built-in)..."

# CRITICAL: NVMe MUST be =y (built-in) — boot drive, no initramfs
$SC --enable BLK_DEV_NVME
$SC --enable NVME_CORE

# I/O scheduler
$SC --enable BLK_DEV_THROTTLING
$SC --enable IOSCHED_BFQ
$SC --enable BFQ_GROUP_IOSCHED

# USB storage for external drives
$SC --module USB_STORAGE
$SC --module USB_UAS

echo "  [OK] NVMe"

# ==========================================================================
# PHASE 7: FILESYSTEMS (boot-critical must be built-in)
# ==========================================================================
echo "[Phase 7] Filesystems..."

# CRITICAL: Root filesystem must be built-in (no initramfs)
$SC --enable EXT4_FS

# CRITICAL: EFI partition must be built-in
$SC --enable VFAT_FS
$SC --enable NLS_CODEPAGE_437
$SC --enable NLS_ISO8859_1
$SC --enable FAT_FS
$SC --enable MSDOS_FS

# Other filesystems
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

# ==========================================================================
# PHASE 8: GPU - Intel UHD 620 [8086:5917] (Kaby Lake GT2)
# ==========================================================================
echo "[Phase 8] i915 GPU..."

# i915 MUST be module — needs firmware from /lib/firmware/
# Firmware: i915/kbl_dmc_ver1_04.bin (DMC v1.4)
$SC --enable DRM
$SC --module DRM_I915
$SC --enable DRM_I915_CAPTURE_ERROR
$SC --enable DRM_I915_COMPRESS_ERROR
$SC --enable DRM_I915_USERPTR
$SC --enable DRM_I915_PXP

# No GVT (not needed, saves compile time)
$SC --disable DRM_I915_GVT

# Framebuffer - EFI for early boot console
$SC --enable FB
$SC --enable FB_EFI
$SC --enable FRAMEBUFFER_CONSOLE
$SC --enable DRM_FBDEV_EMULATION

# Backlight - intel_backlight (raw type, max 7500)
$SC --enable BACKLIGHT_CLASS_DEVICE

# HDA-i915 audio link (HDMI audio needs i915)
$SC --enable SND_HDA_I915

echo "  [OK] GPU"

# ==========================================================================
# PHASE 9: AUDIO - Realtek ALC298 (subsystem 0x10ec10cc, snd_hda_intel)
# ==========================================================================
echo "[Phase 9] Audio (ALC298 + HDMI)..."

# HDA Intel driver — module (loads firmware from /lib/firmware/)
$SC --module SND_HDA_INTEL

# ALC298 codec (handled by snd_hda_codec_realtek, NOT alc269 module)
$SC --module SND_HDA_CODEC_REALTEK
$SC --module SND_HDA_CODEC_HDMI
$SC --module SND_HDA_GENERIC

# HDA features (confirmed from Fedora surface config)
$SC --enable SND_HDA_HWDEP
$SC --enable SND_HDA_RECONFIG
$SC --enable SND_HDA_INPUT_BEEP
$SC --set-val SND_HDA_INPUT_BEEP_MODE 0
$SC --enable SND_HDA_PATCH_LOADER
$SC --enable SND_HDA_POWER_SAVE
$SC --set-val SND_HDA_POWER_SAVE_DEFAULT 1

# ALSA core
$SC --enable SOUND
$SC --module SND
$SC --module SND_PCM
$SC --module SND_HWDEP
$SC --module SND_SEQ
$SC --module SND_TIMER
$SC --module SND_HRTIMER

# DSP driver: Use HDA legacy, NOT SOF
# Confirmed: dsp_driver=0 (auto selects HDA on this hardware)
# Disable SOF to avoid confusion
$SC --disable SND_SOC_SOF_TOPLEVEL

echo "  [OK] Audio"

# ==========================================================================
# PHASE 10: WIFI - Marvell 88W8897 AVASTAR [11ab:2b38]
# ==========================================================================
echo "[Phase 10] WiFi (Marvell mwifiex)..."

# Marvell mwifiex_pcie — mainline, firmware from linux-firmware
# Firmware: mrvl/pcie8897_uapsta.bin
$SC --module CFG80211
$SC --enable CFG80211_WEXT
$SC --module MAC80211
$SC --module MWIFIEX
$SC --module MWIFIEX_PCIE

# Disable Intel WiFi (not present on Surface Pro 6)
$SC --disable IWLWIFI
$SC --disable IWLMVM
$SC --disable IWLDVM

echo "  [OK] WiFi"

# ==========================================================================
# PHASE 11: BLUETOOTH - Marvell [1286:204c]
# ==========================================================================
echo "[Phase 11] Bluetooth..."

# btusb driver with Marvell firmware: mrvl/usb8897_uapsta.bin
$SC --module BT
$SC --module BT_RFCOMM
$SC --module BT_BNEP
$SC --module BT_HIDP
$SC --module BT_HCIBTUSB
$SC --enable BT_HCIBTUSB_AUTOSUSPEND

echo "  [OK] Bluetooth"

# ==========================================================================
# PHASE 12: SURFACE PLATFORM MODULES
# ==========================================================================
echo "[Phase 12] Surface platform (SAM + peripherals)..."

# Surface Platform base
$SC --enable SURFACE_PLATFORMS

# Surface Aggregator Module (SAM) — the main Surface hub
# BUS must be built-in, rest as modules (from KERNEL_CONFIG_CROSSREF.md)
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

# Surface HID (improved Type Cover support)
$SC --module SURFACE_HID_CORE
$SC --module SURFACE_HID
$SC --module SURFACE_KBD

# Surface buttons (volume/power)
$SC --module SURFACE_PRO3_BUTTON

# Surface DTX (clipboard detach — N/A for Pro 6, but harmless)
$SC --module SURFACE_DTX

# Surface battery/charger
$SC --module BATTERY_SURFACE
$SC --module CHARGER_SURFACE

# Surface fan/temp sensors
$SC --module SENSORS_SURFACE_FAN
$SC --module SENSORS_SURFACE_TEMP

# IPTS touchscreen (hardware broken on this unit, but enable for completeness)
# Needs linux-surface kernel patches to compile
$SC --module HID_IPTS 2>/dev/null || echo "  [INFO] HID_IPTS not available (needs linux-surface patches)"

echo "  [OK] Surface platform"

# ==========================================================================
# PHASE 13: HID SENSORS (via Intel ISH)
# ==========================================================================
echo "[Phase 13] HID sensors (ISH)..."

# Intel Sensor Hub [8086:9d35] Sunrise Point-LP
$SC --module INTEL_ISH_HID
$SC --module INTEL_ISH_FIRMWARE_DOWNLOADER

# HID Sensor Hub framework
$SC --module HID_SENSOR_HUB

# Individual sensors (confirmed via lsmod on live hardware + Fedora reference)
$SC --module HID_SENSOR_ACCEL_3D
$SC --module HID_SENSOR_GYRO_3D
$SC --module HID_SENSOR_ALS
$SC --module HID_SENSOR_DEVICE_ROTATION
$SC --module HID_SENSOR_MAGNETOMETER_3D
$SC --module HID_SENSOR_INCLINOMETER_3D
$SC --module HID_SENSOR_HUMIDITY
$SC --module HID_SENSOR_TEMP
$SC --module HID_SENSOR_CUSTOM_INTEL_HINGE

# IIO subsystem (required by HID sensors)
$SC --module HID_SENSOR_IIO_COMMON
$SC --module HID_SENSOR_IIO_TRIGGER
$SC --module IIO

echo "  [OK] Sensors"

# ==========================================================================
# PHASE 14: CAMERAS (IPU3 — staging, WIP per linux-surface)
# ==========================================================================
echo "[Phase 14] Camera pipeline (IPU3, staging)..."

# Staging drivers
$SC --enable STAGING
$SC --enable STAGING_MEDIA

# IPU3 CIO2 (CSI-2 host) [8086:9d32]
$SC --module VIDEO_IPU3_CIO2

# IPU3 ImgU (image processing) [8086:1919]
$SC --module VIDEO_IPU3_IMGU

# IPU Bridge
$SC --module IPU_BRIDGE

# Camera PMIC (TPS68470 via INT3472)
$SC --module INTEL_SKL_INT3472

# Camera sensors
$SC --module VIDEO_OV5693     # rear 5MP
$SC --module VIDEO_OV8865     # front 8MP
$SC --module VIDEO_OV7251     # IR camera
$SC --module VIDEO_DW9719     # VCM autofocus

# Media/V4L2 framework
$SC --enable MEDIA_SUPPORT
$SC --enable MEDIA_CAMERA_SUPPORT
$SC --enable VIDEO_DEV

echo "  [OK] Cameras"

# ==========================================================================
# PHASE 15: I2C / SERIAL IO
# ==========================================================================
echo "[Phase 15] I2C and Serial IO..."

# Intel LPSS (Low Power Sub-System) — confirmed: pinctrl_sunrisepoint
$SC --enable MFD_INTEL_LPSS
$SC --enable MFD_INTEL_LPSS_ACPI
$SC --enable MFD_INTEL_LPSS_PCI

# DesignWare I2C (i2c-0..3 confirmed via sysfs)
$SC --enable I2C_DESIGNWARE_CORE
$SC --enable I2C_DESIGNWARE_PLATFORM
$SC --enable I2C_DESIGNWARE_PCI

# Pinctrl — Sunrise Point-LP (NOT Cannon Lake, confirmed via lsmod)
$SC --enable PINCTRL
$SC --enable PINCTRL_INTEL
$SC --enable PINCTRL_SUNRISEPOINT

# SOC button array (power/volume buttons)
$SC --module INPUT_SOC_BUTTON_ARRAY

echo "  [OK] I2C/Serial IO"

# ==========================================================================
# PHASE 16: USB
# ==========================================================================
echo "[Phase 16] USB..."

$SC --enable USB
$SC --enable USB_XHCI_HCD
$SC --enable USB_XHCI_PCI

# HID (Type Cover, Surface peripherals)
$SC --enable HID
$SC --enable USB_HID
$SC --module HID_MULTITOUCH
$SC --enable INPUT_MOUSEDEV
$SC --enable INPUT_EVDEV
$SC --enable INPUT_UINPUT

echo "  [OK] USB"

# ==========================================================================
# PHASE 17: ETHERNET (USB dongles only, no onboard)
# ==========================================================================
echo "[Phase 17] USB Ethernet..."

$SC --enable USB_NET_DRIVERS
$SC --module USB_RTL8152
$SC --module USB_NET_CDCETHER
$SC --module USB_NET_AX88179_178A

echo "  [OK] Ethernet"

# ==========================================================================
# PHASE 18: ACPI / PLATFORM
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

# WMI
$SC --module ACPI_WMI

# MEI (Management Engine) — confirmed: [8086:9d3a] + [8086:9d3e] iTouch
$SC --module INTEL_MEI
$SC --module INTEL_MEI_ME
$SC --module INTEL_MEI_HDCP
$SC --module INTEL_MEI_PXP

# Watchdog
$SC --module ITCO_WDT
$SC --enable ITCO_VENDOR_SUPPORT

echo "  [OK] ACPI"

# ==========================================================================
# PHASE 19: SUSPEND / POWER
# ==========================================================================
echo "[Phase 19] Suspend and power..."

# s2idle only (Modern Standby), no S3 deep
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

# PPP for SSTP VPN (confirmed needed across all machines)
# MBP base has PPP disabled, so all must be explicitly set
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

# All firmware from /lib/firmware/ at runtime (no embedded firmware)
$SC --enable FW_LOADER
$SC --enable FW_LOADER_USER_HELPER
$SC --set-str EXTRA_FIRMWARE ""

echo "  [OK] Firmware"

# ==========================================================================
# PHASE 22: EFI BOOT
# ==========================================================================
echo "[Phase 22] EFI boot..."

# 64-bit UEFI, Secure Boot must be disabled for unsigned kernel
$SC --enable EFI
$SC --enable EFI_STUB
$SC --enable EFI_MIXED

echo "  [OK] EFI"

# ==========================================================================
# PHASE 23: CRYPTO
# ==========================================================================
echo "[Phase 23] Hardware crypto..."

# AES-NI + PCLMUL (confirmed in CPU flags)
$SC --module CRYPTO_AES_NI_INTEL
$SC --module CRYPTO_GHASH_CLMUL_NI_INTEL
$SC --module CRYPTO_POLYVAL_CLMUL_NI

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
# MICROCODE_AMD removed in kernel 6.6 — controlled by CPU_SUP_AMD
$SC --disable INFINIBAND
$SC --disable SOUND_OSS_CORE
$SC --disable PCMCIA
$SC --disable PARPORT

# iSCSI initiators (not needed)
$SC --disable BE2ISCSI
$SC --disable BNX2I
$SC --disable CXGB4I
$SC --disable CXGB3I
$SC --disable QLA4XXX
$SC --disable SCSI_CXGB3_ISCSI
$SC --disable SCSI_CXGB4_ISCSI

# Intel WiFi (not present — Marvell WiFi on Surface Pro 6)
$SC --disable IWLWIFI
$SC --disable IWLMVM
$SC --disable IWLDVM

# SOF audio (not needed — HDA legacy driver works)
$SC --disable SND_SOC_SOF_TOPLEVEL

echo "  [OK] Disabled"

# ==========================================================================
# DONE
# ==========================================================================
echo ""
echo "=== Surface Pro 6 kernel config applied successfully ==="
echo ""
echo "Next steps:"
echo "  1. make olddefconfig              # resolve dependencies"
echo "  2. make menuconfig                # review"
echo "  3. make -j9                       # build (4C/8T)"
echo "  4. make modules_install"
echo "  5. make install"
echo ""
echo "Required firmware (from sys-kernel/linux-firmware):"
echo "  mrvl/pcie8897_uapsta.bin          # WiFi"
echo "  mrvl/usb8897_uapsta.bin           # Bluetooth"
echo "  i915/kbl_dmc_ver1_04.bin          # GPU DMC"
echo ""
echo "No special kernel boot parameters needed."
echo "No audio model quirk needed (ALC298 autoconfig works)."
echo "Disable Secure Boot in Surface UEFI (Vol Up + Power)."
