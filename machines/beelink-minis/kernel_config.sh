#!/bin/bash
# ============================================================================
# Gentoo Kernel Config - Beelink MINI S (Intel Celeron N5095A / Jasper Lake)
# ============================================================================
# ALL settings verified against:
#   - Live Fedora 43 hardware harvest (2026-04-14): harvest.sh + deep_harvest.sh
#   - dmidecode, lspci -nnvvv, lsusb -v, smartctl, dmesg, /proc/cpuinfo
#   - Cross-reference with surface-pro-6 (closest desktop profile in repo)
#   - See HARDWARE.md for full inventory
#
# BASE CONFIG: Copy from surface-pro-6/.config (kernel 6.18.x, MGLRU+zstd)
# then apply this script on top of it.
#
# USAGE:
#   cd /usr/src/linux
#   cp /path/to/surface-pro-6/.config .config    # start from SP6 base
#   bash /path/to/beelink-minis-n5095/kernel_config.sh
#   make olddefconfig     # resolve all dependencies
#   make menuconfig       # optional review
#   make -j2 && make modules_install && make install
#
# BOOT STRATEGY: No initramfs.
#   - Root-path drivers (AHCI, ext4) built-in (=y)
#   - Firmware-dependent drivers (i915, iwlwifi) MUST be modules (=m)
#
# KEY DIFFERENCES FROM SP6:
#   - SATA AHCI is primary boot path (not NVMe)
#   - WiFi: Intel iwlwifi (not Marvell mwifiex)
#   - Pinctrl: Jasper Lake (not Sunrise Point)
#   - No Surface platform modules
#   - No IPTS / touchscreen / pen
#   - No HID sensors / ISH
#   - No cameras
#   - No laptop-specific bits (battery, backlight, lid switch)
#   - CPU is Tremont (Atom) not Kaby Lake — no AVX, simpler scheduler needs
#   - Has S3 deep sleep + full hibernate (SP6 is s2idle only)
# ============================================================================

set -euo pipefail

SC="./scripts/config"

if [[ ! -x "$SC" ]]; then
    echo "ERROR: Run this from /usr/src/linux (scripts/config not found)"
    exit 1
fi

echo "=== Applying Beelink MINI S (N5095A) kernel config ==="
echo ""

# ==========================================================================
# PHASE 1: REMOVE SURFACE-SPECIFIC CONFIGS (from SP6 base)
# ==========================================================================
echo "[Phase 1] Removing Surface-specific hardware..."

# Surface Aggregator Module (SAM) and all children
$SC --disable SURFACE_PLATFORMS
$SC --disable SURFACE_AGGREGATOR
$SC --disable SURFACE_AGGREGATOR_BUS
$SC --disable SURFACE_AGGREGATOR_REGISTRY
$SC --disable SURFACE_AGGREGATOR_CDEV
$SC --disable SURFACE_AGGREGATOR_HUB
$SC --disable SURFACE_AGGREGATOR_TABLET_SWITCH
$SC --disable SURFACE_ACPI_NOTIFY
$SC --disable SURFACE_GPE
$SC --disable SURFACE_PLATFORM_PROFILE
$SC --disable SURFACE_HOTPLUG
$SC --disable SURFACE_HID_CORE
$SC --disable SURFACE_HID
$SC --disable SURFACE_KBD
$SC --disable SURFACE_PRO3_BUTTON
$SC --disable SURFACE_DTX
$SC --disable BATTERY_SURFACE
$SC --disable CHARGER_SURFACE
$SC --disable SENSORS_SURFACE_FAN
$SC --disable SENSORS_SURFACE_TEMP
$SC --disable HID_IPTS

# Marvell WiFi and BT (SP6 uses these; Beelink uses Intel)
$SC --disable MWIFIEX
$SC --disable MWIFIEX_PCIE
$SC --disable BT_MRVL
$SC --disable BT_MRVL_SDIO

# HID sensors / ISH (SP6 has Intel Sensor Hub, Beelink does not)
$SC --disable INTEL_ISH_HID
$SC --disable INTEL_ISH_FIRMWARE_DOWNLOADER
$SC --disable HID_SENSOR_HUB
$SC --disable HID_SENSOR_ACCEL_3D
$SC --disable HID_SENSOR_GYRO_3D
$SC --disable HID_SENSOR_ALS
$SC --disable HID_SENSOR_DEVICE_ROTATION
$SC --disable HID_SENSOR_MAGNETOMETER_3D
$SC --disable HID_SENSOR_INCLINOMETER_3D
$SC --disable HID_SENSOR_HUMIDITY
$SC --disable HID_SENSOR_TEMP
$SC --disable HID_SENSOR_CUSTOM_INTEL_HINGE

# IPU3 cameras (SP6 has front+rear+IR cameras; Beelink has none)
$SC --disable VIDEO_IPU3_CIO2
$SC --disable VIDEO_IPU3_IMGU
$SC --disable IPU_BRIDGE
$SC --disable INTEL_SKL_INT3472
$SC --disable VIDEO_OV5693
$SC --disable VIDEO_OV8865
$SC --disable VIDEO_OV7251
$SC --disable VIDEO_DW9719

# Pinctrl: Sunrise Point (SP6 KBL) -> Jasper Lake (Beelink JSL)
$SC --disable PINCTRL_SUNRISEPOINT

# Laptop-only bits
$SC --disable ACPI_BATTERY  # desktop, no battery
# ACPI_BUTTON still wanted (power button)

echo "  [OK] Surface / laptop / sensor hardware removed"

# ==========================================================================
# PHASE 2: GENERAL / GENTOO
# ==========================================================================
echo "[Phase 2] General settings..."

$SC --enable IKCONFIG
$SC --enable IKCONFIG_PROC
$SC --set-str DEFAULT_HOSTNAME "beelink-minis"

$SC --enable GENTOO_LINUX
$SC --enable GENTOO_LINUX_INIT_SCRIPT
$SC --enable GENTOO_LINUX_PORTAGE
$SC --enable GENTOO_LINUX_UDEV

echo "  [OK] General"

# ==========================================================================
# PHASE 3: PROCESSOR - Intel Celeron N5095A (Jasper Lake, Tremont, 4C/4T)
# ==========================================================================
echo "[Phase 3] Processor configuration..."

$SC --enable SMP
$SC --set-val NR_CPUS 4      # 4 cores, NO hyperthreading
# CPU tuning via -march=tremont in make.conf CFLAGS

$SC --enable SCHED_MC
$SC --disable SCHED_SMT       # no HT on N5095A
$SC --enable SCHED_AUTOGROUP
$SC --enable X86_INTEL_PSTATE
$SC --enable CPU_FREQ_GOV_PERFORMANCE
$SC --enable CPU_FREQ_DEFAULT_GOV_PERFORMANCE
$SC --enable CPU_FREQ_STAT
$SC --enable INTEL_IDLE
$SC --enable X86_X2APIC

# CPU family support: Intel only (explicit to save size)
$SC --enable CPU_SUP_INTEL
$SC --disable CPU_SUP_AMD

# Thermal / power monitoring (confirmed loaded modules from dmesg)
$SC --enable PERF_EVENTS
$SC --enable INTEL_RAPL
$SC --module PERF_EVENTS_INTEL_RAPL
$SC --enable X86_PKG_TEMP_THERMAL
$SC --enable INTEL_POWERCLAMP
$SC --module SENSORS_CORETEMP
$SC --enable THERMAL_HWMON

# DPTF thermal framework (processor_thermal_device_pci_legacy confirmed)
$SC --enable ACPI_DPTF
$SC --module INT340X_THERMAL
$SC --module ACPI_THERMAL_REL
$SC --module INTEL_PCH_THERMAL
$SC --module PROC_THERMAL_MMIO_RAPL

# Intel OC watchdog (intel_oc_wdt loaded on live env)
$SC --module INTEL_OC_WDT

# Intel PMC core / VSEC telemetry (intel_pmc_core, pmt_telemetry loaded)
$SC --module INTEL_PMC_CORE
$SC --module INTEL_VSEC
$SC --module PMT_TELEMETRY
$SC --module PMT_CLASS

# KVM (VMX + VT-d confirmed present)
$SC --enable KVM
$SC --module KVM_INTEL

echo "  [OK] Processor"

# ==========================================================================
# PHASE 4: PERFORMANCE TUNING
# ==========================================================================
echo "[Phase 4] Performance tuning..."

$SC --enable PREEMPT
$SC --enable PREEMPT_DYNAMIC
$SC --enable HZ_1000
$SC --enable NO_HZ_IDLE

# Transparent Huge Pages
$SC --enable TRANSPARENT_HUGEPAGE
$SC --enable TRANSPARENT_HUGEPAGE_ALWAYS

# MGLRU
$SC --enable LRU_GEN
$SC --enable LRU_GEN_ENABLED

# KSM
$SC --enable KSM

echo "  [OK] Performance"

# ==========================================================================
# PHASE 5: MEMORY / SWAP - 8GB RAM + zram
# ==========================================================================
echo "[Phase 5] Memory and zram..."

# zram must be built-in (no initramfs)
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
# PHASE 6: STORAGE - SATA AHCI (primary boot path, NOT NVMe)
# ==========================================================================
echo "[Phase 6] SATA AHCI storage (boot drive, must be built-in)..."

# CRITICAL: AHCI MUST be =y (built-in) — boot drive, no initramfs
$SC --enable ATA
$SC --enable ATA_ACPI
$SC --enable SATA_PMP
$SC --enable SATA_AHCI
$SC --enable ATA_PIIX

# NVMe not present on this board, but keep module for USB-NVMe enclosures
$SC --module BLK_DEV_NVME
$SC --module NVME_CORE

# SCSI core (SATA drives appear as /dev/sdX via libata)
$SC --enable SCSI
$SC --enable BLK_DEV_SD
$SC --enable SCSI_LOWLEVEL

# I/O schedulers
$SC --enable BLK_DEV_THROTTLING
$SC --enable IOSCHED_BFQ
$SC --enable BFQ_GROUP_IOSCHED

# USB storage for external drives
$SC --module USB_STORAGE
$SC --module USB_UAS

echo "  [OK] SATA AHCI"

# ==========================================================================
# PHASE 7: FILESYSTEMS (boot-critical must be built-in)
# ==========================================================================
echo "[Phase 7] Filesystems..."

# CRITICAL: root filesystem must be built-in (no initramfs)
$SC --enable EXT4_FS

# CRITICAL: EFI partition must be built-in
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

# EFI partition / variables
$SC --enable EFI_PARTITION
$SC --enable EFIVAR_FS

echo "  [OK] Filesystems"

# ==========================================================================
# PHASE 8: GPU - Intel UHD Graphics (Jasper Lake Gen11, [8086:4e55])
# ==========================================================================
echo "[Phase 8] i915 GPU..."

# i915 MUST be module — DMC firmware from /lib/firmware/ (icl_dmc_ver1_09.bin)
$SC --enable DRM
$SC --module DRM_I915
$SC --enable DRM_I915_CAPTURE_ERROR
$SC --enable DRM_I915_COMPRESS_ERROR
$SC --enable DRM_I915_USERPTR
$SC --enable DRM_I915_PXP
$SC --disable DRM_I915_GVT

# Framebuffer - EFI for early boot console
$SC --enable FB
$SC --enable FB_EFI
$SC --enable FRAMEBUFFER_CONSOLE
$SC --enable DRM_CLIENT_SELECTION
$SC --enable DRM_FBDEV_EMULATION

# Backlight class (HDMI-attached displays may still want generic backlight class)
$SC --enable BACKLIGHT_CLASS_DEVICE

# HDA-i915 audio link (HDMI audio needs i915)
$SC --enable SND_HDA_I915

echo "  [OK] GPU"

# ==========================================================================
# PHASE 9: AUDIO - Jasper Lake HDA + codec (TBD on first boot)
# ==========================================================================
echo "[Phase 9] Audio (HDA legacy, no SOF)..."

# HDA Intel driver - module (loads firmware from /lib/firmware/)
$SC --module SND_HDA_INTEL

# Include both Realtek and generic codec to cover the unknown codec
$SC --module SND_HDA_CODEC_REALTEK
$SC --module SND_HDA_CODEC_HDMI
$SC --module SND_HDA_GENERIC

# HDA features
$SC --enable SND_HDA_HWDEP
$SC --enable SND_HDA_RECONFIG
$SC --enable SND_HDA_INPUT_BEEP
$SC --set-val SND_HDA_INPUT_BEEP_MODE 0
$SC --enable SND_HDA_PATCH_LOADER
$SC --set-val SND_HDA_POWER_SAVE_DEFAULT 1

# ALSA core
$SC --enable SOUND
$SC --module SND
$SC --module SND_PCM
$SC --module SND_HWDEP
$SC --module SND_SEQUENCER
$SC --module SND_TIMER
$SC --module SND_HRTIMER

# Disable SOF entirely — legacy HDA path is simpler and sufficient here
$SC --disable SND_SOC_SOF_TOPLEVEL
$SC --disable SND_SOC_SOF_INTEL_TOPLEVEL
$SC --disable SND_SOC_SOF_JASPERLAKE
$SC --disable SND_SOC_SOF_HDA_COMMON

echo "  [OK] Audio"

# ==========================================================================
# PHASE 10: WIFI - Intel Wireless-AC 3165 [8086:3165]
# ==========================================================================
echo "[Phase 10] WiFi (Intel iwlwifi / iwlmvm)..."

# 3165 uses iwlwifi + iwlmvm, firmware iwlwifi-7265D-29.ucode
$SC --module CFG80211
$SC --enable CFG80211_WEXT
$SC --module MAC80211
$SC --module IWLWIFI
$SC --module IWLMVM
$SC --enable IWLWIFI_LEDS

# Disable Marvell (SP6-only)
$SC --disable MWIFIEX
$SC --disable MWIFIEX_PCIE

echo "  [OK] WiFi"

# ==========================================================================
# PHASE 11: BLUETOOTH - Intel [8087:0a2a] (ROM firmware, no download)
# ==========================================================================
echo "[Phase 11] Bluetooth..."

$SC --module BT
$SC --module BT_RFCOMM
$SC --module BT_BNEP
$SC --module BT_HIDP
$SC --module BT_HCIBTUSB
$SC --enable BT_HCIBTUSB_AUTOSUSPEND
$SC --enable BT_HCIBTUSB_BCM     # harmless even for Intel BT
$SC --enable BT_HCIBTUSB_MTK     # harmless fallback
$SC --module BT_INTEL

# Marvell BT disabled (from Phase 1)

echo "  [OK] Bluetooth"

# ==========================================================================
# PHASE 12: ETHERNET - Realtek RTL8168h/8111h [10ec:8168]
# ==========================================================================
echo "[Phase 12] Ethernet (r8169)..."

$SC --enable NETDEVICES
$SC --enable ETHERNET
$SC --enable NET_VENDOR_REALTEK
$SC --module R8169
$SC --module REALTEK_PHY

# USB Ethernet (for dongles / hubs)
$SC --enable USB_NET_DRIVERS
$SC --module USB_RTL8152
$SC --module USB_NET_CDCETHER
$SC --module USB_NET_AX88179_178A

echo "  [OK] Ethernet"

# ==========================================================================
# PHASE 13: I2C / SERIAL IO (Jasper Lake LPSS)
# ==========================================================================
echo "[Phase 13] I2C and Serial IO..."

# Intel LPSS (Low Power Sub-System) — 6x I2C controllers on JSL
$SC --enable MFD_INTEL_LPSS
$SC --enable MFD_INTEL_LPSS_ACPI
$SC --enable MFD_INTEL_LPSS_PCI

# DesignWare 8250 UART
$SC --enable SERIAL_8250
$SC --enable SERIAL_8250_DW

# DesignWare I2C
$SC --enable I2C_DESIGNWARE_CORE
$SC --enable I2C_DESIGNWARE_PLATFORM
$SC --enable I2C_DESIGNWARE_PCI

# i801 SMBus (00:1f.4, i2c_i801 loaded)
$SC --module I2C_I801
$SC --enable I2C_SMBUS

# Pinctrl — Jasper Lake (pinctrl_jasperlake loaded)
$SC --enable PINCTRL
$SC --enable PINCTRL_INTEL
$SC --module PINCTRL_JASPERLAKE

# SPI (spi_intel_pci, spi_nor loaded)
$SC --module SPI_INTEL_PCI
$SC --module MTD
$SC --module MTD_SPI_NOR

# Power button / SoC button array
$SC --enable INPUT_KEYBOARD
$SC --module INPUT_SOC_BUTTON_ARRAY

echo "  [OK] I2C/Serial IO"

# ==========================================================================
# PHASE 14: USB
# ==========================================================================
echo "[Phase 14] USB..."

$SC --enable USB
$SC --enable USB_XHCI_HCD
$SC --enable USB_XHCI_PCI

# HID
$SC --enable HID
$SC --enable USB_HID
$SC --module HID_MULTITOUCH
$SC --enable INPUT_MOUSEDEV
$SC --enable INPUT_EVDEV
$SC --enable INPUT_UINPUT

# USB audio (incidental — may plug a USB headset/DAC)
$SC --module SND_USB_AUDIO

echo "  [OK] USB"

# ==========================================================================
# PHASE 15: ACPI / PLATFORM
# ==========================================================================
echo "[Phase 15] ACPI platform..."

$SC --enable PCI
$SC --enable PCIEPORTBUS
$SC --enable ACPI
$SC --enable ACPI_AC
# ACPI_BATTERY disabled in Phase 1 (desktop)
$SC --enable ACPI_BUTTON
$SC --enable ACPI_FAN
$SC --enable ACPI_PROCESSOR
$SC --enable ACPI_THERMAL
$SC --enable ACPI_VIDEO
$SC --enable ACPI_TAD        # acpi_tad loaded on live env

# WMI
$SC --module ACPI_WMI
$SC --module WMI_BMOF        # wmi_bmof loaded

# MEI (Management Engine)
$SC --module INTEL_MEI
$SC --module INTEL_MEI_ME
$SC --module INTEL_MEI_HDCP
$SC --module INTEL_MEI_PXP

# iTCO watchdog (iTCO_wdt loaded)
$SC --module ITCO_WDT
$SC --enable ITCO_VENDOR_SUPPORT

# Intel PMC (already set in Phase 3 but re-assert for clarity)
$SC --enable MFD_INTEL_PMC_BXT   # intel_pmc_bxt loaded

echo "  [OK] ACPI"

# ==========================================================================
# PHASE 16: TPM 2.0 (AMI TPM2 ACPI table present)
# ==========================================================================
echo "[Phase 16] TPM 2.0..."

$SC --module TCG_TPM
$SC --module TCG_TIS
$SC --module TCG_CRB

echo "  [OK] TPM"

# ==========================================================================
# PHASE 17: SUSPEND / POWER
# ==========================================================================
echo "[Phase 17] Suspend and power..."

# Full S3 deep + hibernate (confirmed ACPI: S0 S3 S4 S5)
$SC --enable SUSPEND
$SC --enable HIBERNATE_CALLBACKS
$SC --enable HIBERNATION
$SC --enable PM_SLEEP

echo "  [OK] Suspend"

# ==========================================================================
# PHASE 18: NETWORKING / VPN
# ==========================================================================
echo "[Phase 18] Networking and VPN..."

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

# PPP for SSTP VPN (same as SP6 — networkmanager-sstp works)
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
# PHASE 19: FIRMWARE LOADING
# ==========================================================================
echo "[Phase 19] Firmware..."

$SC --enable FW_LOADER
$SC --enable FW_LOADER_USER_HELPER
$SC --set-str EXTRA_FIRMWARE ""

echo "  [OK] Firmware"

# ==========================================================================
# PHASE 20: EFI BOOT
# ==========================================================================
echo "[Phase 20] EFI boot..."

$SC --enable EFI
$SC --enable EFI_STUB
$SC --enable EFI_MIXED

echo "  [OK] EFI"

# ==========================================================================
# PHASE 21: CRYPTO (AES-NI, PCLMUL, SHA-NI present)
# ==========================================================================
echo "[Phase 21] Hardware crypto..."

$SC --module CRYPTO_AES_NI_INTEL
$SC --module CRYPTO_GHASH_CLMUL_NI_INTEL
$SC --module CRYPTO_POLYVAL_CLMUL_NI
$SC --module CRYPTO_SHA1_SSSE3
$SC --module CRYPTO_SHA256_SSSE3
$SC --module CRYPTO_SHA512_SSSE3

echo "  [OK] Crypto"

# ==========================================================================
# PHASE 22: SECURITY
# ==========================================================================
echo "[Phase 22] Security..."

$SC --enable SECURITY
$SC --enable SECCOMP
$SC --enable SECURITY_YAMA
$SC --enable MITIGATION_PAGE_TABLE_ISOLATION
$SC --enable MITIGATION_RETPOLINE

echo "  [OK] Security"

# ==========================================================================
# PHASE 23: IOMMU / DMAR (VT-d present on this CPU)
# ==========================================================================
echo "[Phase 23] IOMMU..."

$SC --enable IOMMU_SUPPORT
$SC --enable INTEL_IOMMU
$SC --enable INTEL_IOMMU_DEFAULT_ON
$SC --enable IRQ_REMAP

echo "  [OK] IOMMU"

# ==========================================================================
# PHASE 24: DISABLE UNNECESSARY HARDWARE
# ==========================================================================
echo "[Phase 24] Disabling unnecessary hardware..."

$SC --disable DRM_AMDGPU
$SC --disable DRM_RADEON
$SC --disable DRM_NOUVEAU
$SC --disable INFINIBAND
$SC --disable SOUND_OSS_CORE
$SC --disable PCMCIA
$SC --disable PARPORT

# iSCSI initiators (still disabled as in SP6 base)
$SC --disable BE2ISCSI
$SC --disable SCSI_CXGB3_ISCSI
$SC --disable SCSI_CXGB4_ISCSI

# Thunderbolt / USB4 (not present)
$SC --disable USB4
$SC --disable INTEL_WMI_THUNDERBOLT

# Apple bits (just in case the chosen base accidentally carries them)
$SC --disable APPLE_PROPERTIES
$SC --disable SENSORS_APPLESMC
$SC --disable APPLE_GMUX
$SC --disable HID_APPLE
$SC --disable MOUSE_BCM5974

echo "  [OK] Disabled"

# ==========================================================================
# PHASE 25: CONSOLE FONTS (no HiDPI — plain 1080p HDMI)
# ==========================================================================
echo "[Phase 25] Console fonts..."

# Keep standard fonts; no TER16x32 (SP6 needed it for 2736x1824, we don't)
$SC --enable FONT_SUPPORT
$SC --enable FONTS
$SC --enable FONT_8x16
$SC --enable FONT_8x8

echo "  [OK] Console fonts"

# ==========================================================================
# DONE
# ==========================================================================
echo ""
echo "=== Beelink MINI S (N5095A) kernel config applied successfully ==="
echo ""
echo "Next steps:"
echo "  1. make olddefconfig              # resolve dependencies"
echo "  2. make menuconfig                # optional review"
echo "  3. make -j2                       # build (4C/4T, 8GB RAM — -j2 is safest)"
echo "  4. make modules_install"
echo "  5. make install"
echo ""
echo "Required firmware (from sys-kernel/linux-firmware):"
echo "  iwlwifi-7265D-29.ucode            # WiFi (3165 uses 7265D firmware)"
echo "  i915/icl_dmc_ver1_09.bin          # GPU DMC (ICL/JSL share)"
echo "  regulatory.db + regulatory.db.p7s # CRDA"
echo ""
echo "NO firmware file needed for Intel BT (8087:0a2a — ROM firmware)."
echo "NO special kernel boot parameters needed."
echo "On first boot, identify HDA codec: cat /proc/asound/card0/codec#0 | head"
