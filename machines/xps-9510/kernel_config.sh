#!/bin/bash
# ============================================================================
# Gentoo Kernel Config - Dell XPS 15 9510
# ============================================================================
# ALL settings verified against:
#   - Live Gentoo system (kernel 6.12.58-gentoo, production since Feb 2026)
#   - deep_harvest.sh hardware inventory
#   - XPS 9510 HARDWARE.md (PCI IDs, drivers, firmware)
#   - Cross-reference with Surface Pro 6, MBP 2015, NUC11 production configs
#   - NVIDIA driver 590.48.01 build requirements
#
# BASE CONFIG: Start from any existing .config (e.g., defconfig or MBP base)
#
# USAGE:
#   cd /usr/src/linux
#   make defconfig                    # or copy another .config as starting point
#   bash /path/to/kernel_config.sh
#   make olddefconfig                 # resolve all dependencies
#   make menuconfig                   # review
#   make -j17 && make modules_install && make install
#
# BOOT STRATEGY: No initramfs — all root-path drivers built-in (=y)
# NVIDIA STRATEGY: nvidia-drivers built out-of-tree; kernel needs DRM_QXL=m
#   for DRM_TTM_HELPER (nvidia build dep since kernel 6.11+)
# ============================================================================

set -euo pipefail

SC="./scripts/config"

if [[ ! -x "$SC" ]]; then
    echo "ERROR: Run this from /usr/src/linux (scripts/config not found)"
    exit 1
fi

echo "=== Applying Dell XPS 15 9510 kernel config ==="
echo ""

# ==========================================================================
# PHASE 1: GENERAL / GENTOO
# ==========================================================================
echo "[Phase 1] General settings..."

$SC --enable IKCONFIG
$SC --enable IKCONFIG_PROC
$SC --set-str DEFAULT_HOSTNAME "xps-9510"

# Gentoo-specific
$SC --enable GENTOO_LINUX
$SC --enable GENTOO_LINUX_INIT_SCRIPT
$SC --enable GENTOO_LINUX_PORTAGE
$SC --enable GENTOO_LINUX_UDEV

echo "  [OK] General"

# ==========================================================================
# PHASE 2: PROCESSOR - Intel Core i7-11800H (Tiger Lake-H, 8C/16T)
# ==========================================================================
echo "[Phase 2] Processor configuration..."

$SC --enable SMP
$SC --set-val NR_CPUS 16
$SC --enable MCORE2

$SC --enable SCHED_MC
$SC --enable SCHED_SMT
$SC --enable SCHED_AUTOGROUP
$SC --enable X86_INTEL_PSTATE
$SC --enable CPU_FREQ_GOV_POWERSAVE
$SC --enable CPU_FREQ_DEFAULT_GOV_POWERSAVE
$SC --enable INTEL_IDLE
$SC --enable MICROCODE
$SC --enable X86_X2APIC

# Tiger Lake-H thermal/power
$SC --enable INTEL_RAPL
$SC --enable X86_PKG_TEMP_THERMAL
$SC --enable INTEL_POWERCLAMP
$SC --enable CORETEMP

# DPTF thermal framework (Intel Dynamic Tuning [8086:9a03])
# ACPI_DPTF is the parent toggle — must be enabled first
$SC --enable ACPI_DPTF
$SC --module INT340X_THERMAL
$SC --module ACPI_THERMAL_REL
$SC --module INTEL_PCH_THERMAL
$SC --module PROC_THERMAL_MMIO_RAPL

# KVM (CPU supports VMX)
$SC --module KVM
$SC --module KVM_INTEL
$SC --module VHOST_NET
$SC --module VHOST

echo "  [OK] Processor"

# ==========================================================================
# PHASE 3: PERFORMANCE TUNING
# ==========================================================================
echo "[Phase 3] Performance tuning..."

# Preemption model — upgrade from PREEMPT_VOLUNTARY to full PREEMPT
$SC --enable PREEMPT
$SC --enable PREEMPT_DYNAMIC
$SC --enable HZ_1000
$SC --enable NO_HZ_IDLE

# Transparent Huge Pages (critical for ML workloads on 32GB RAM)
$SC --enable TRANSPARENT_HUGEPAGE
$SC --enable TRANSPARENT_HUGEPAGE_ALWAYS

# MGLRU (Multi-Gen LRU — better page reclaim under memory pressure)
$SC --enable LRU_GEN
$SC --enable LRU_GEN_ENABLED

# KSM (Kernel Same-page Merging — deduplicates ML model memory)
$SC --enable KSM

echo "  [OK] Performance"

# ==========================================================================
# PHASE 4: MEMORY / SWAP - 32GB RAM + zram
# ==========================================================================
echo "[Phase 4] Memory and zram..."

# zram built-in (no initramfs)
$SC --enable ZRAM
$SC --enable ZRAM_BACKEND_ZSTD
$SC --enable CRYPTO_ZSTD
$SC --enable ZSTD_COMPRESS
$SC --enable ZSTD_DECOMPRESS
$SC --set-str ZRAM_DEF_COMP "zstd"

$SC --enable SWAP
$SC --enable ZSWAP

# LZ4 for other compression uses
$SC --enable LZ4_COMPRESS
$SC --enable LZ4HC_COMPRESS

echo "  [OK] Memory"

# ==========================================================================
# PHASE 5: STORAGE - Dual Samsung 990 PRO NVMe [144d:a80c]
# ==========================================================================
echo "[Phase 5] NVMe storage (boot drive, must be built-in)..."

# CRITICAL: NVMe MUST be =y (built-in) — boot drive, no initramfs
$SC --enable BLK_DEV_NVME
$SC --enable NVME_CORE

# I/O scheduler (BFQ for latency-sensitive desktop workloads)
$SC --enable BLK_DEV_THROTTLING
$SC --enable IOSCHED_BFQ
$SC --enable BFQ_GROUP_IOSCHED

# USB storage for external drives
$SC --module USB_STORAGE
$SC --module USB_UAS

echo "  [OK] NVMe"

# ==========================================================================
# PHASE 6: FILESYSTEMS (boot-critical must be built-in)
# ==========================================================================
echo "[Phase 6] Filesystems..."

# CRITICAL: Root filesystem must be built-in (no initramfs)
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

# EFI variables
$SC --enable EFI_PARTITION
$SC --enable EFIVAR_FS

echo "  [OK] Filesystems"

# ==========================================================================
# PHASE 7: GPU - Intel TigerLake-H GT1 UHD [8086:9a60]
# ==========================================================================
echo "[Phase 7] Intel i915 GPU..."

# i915 MUST be module — needs firmware from /lib/firmware/
# Firmware: i915/tgl_dmc_ver2_12.bin, tgl_guc_70.1.1.bin
$SC --enable DRM
$SC --module DRM_I915
$SC --enable DRM_I915_CAPTURE_ERROR
$SC --enable DRM_I915_COMPRESS_ERROR
$SC --enable DRM_I915_USERPTR
$SC --enable DRM_I915_PXP

# No GVT (saves compile time)
$SC --disable DRM_I915_GVT

# Framebuffer — EFI for early boot console
$SC --enable FB
$SC --enable FB_EFI
$SC --enable FRAMEBUFFER_CONSOLE
$SC --enable DRM_FBDEV_EMULATION

# Backlight — intel_backlight (OLED panel)
$SC --enable BACKLIGHT_CLASS_DEVICE

# HDA-i915 audio link (HDMI audio needs i915)
$SC --enable SND_HDA_I915

echo "  [OK] Intel GPU"

# ==========================================================================
# PHASE 8: GPU - NVIDIA RTX 3050 Ti [10de:25a0] build dependencies
# ==========================================================================
echo "[Phase 8] NVIDIA kernel dependencies..."

# DRM_QXL=m pulls in DRM_TTM_HELPER which nvidia-drivers needs since 6.11+
# Without this, nvidia build fails with missing drm_gem_ttm_* symbols
$SC --module DRM_QXL

# Disable nouveau (conflicts with proprietary nvidia-drivers)
$SC --disable DRM_NOUVEAU

# NVIDIA needs these DRM helpers
$SC --enable DRM_KMS_HELPER

echo "  [OK] NVIDIA deps"

# ==========================================================================
# PHASE 9: AUDIO - Tiger Lake-H HD Audio [8086:43c8]
# ==========================================================================
echo "[Phase 9] Audio (HDA + HDMI)..."

# HDA Intel driver — module (Tiger Lake-H uses HDA, NOT SOF)
$SC --module SND_HDA_INTEL

# Codecs
$SC --module SND_HDA_CODEC_REALTEK
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

# ALSA core
$SC --enable SOUND
$SC --module SND
$SC --module SND_PCM
$SC --module SND_HWDEP
$SC --module SND_SEQ
$SC --module SND_TIMER
$SC --module SND_HRTIMER

# Disable SOF (not needed — HDA works natively on Tiger Lake-H)
$SC --disable SND_SOC_SOF_TOPLEVEL

echo "  [OK] Audio"

# ==========================================================================
# PHASE 10: WIFI - Intel AX203 CNVi [8086:43f0]
# ==========================================================================
echo "[Phase 10] WiFi (Intel iwlwifi)..."

# Intel iwlwifi — module, firmware: iwlwifi-QuZ-a0-hr-b0-77.ucode
$SC --module CFG80211
$SC --enable CFG80211_WEXT
$SC --module MAC80211
$SC --module IWLWIFI
$SC --module IWLMVM

echo "  [OK] WiFi"

# ==========================================================================
# PHASE 11: BLUETOOTH - Intel AX201 [8087:0026]
# ==========================================================================
echo "[Phase 11] Bluetooth..."

# btusb + btintel, firmware: intel/ibt-20-*.sfi + .ddc
$SC --module BT
$SC --module BT_RFCOMM
$SC --module BT_BNEP
$SC --module BT_HIDP
$SC --module BT_HCIBTUSB
$SC --enable BT_HCIBTUSB_AUTOSUSPEND
$SC --module BT_INTEL

echo "  [OK] Bluetooth"

# ==========================================================================
# PHASE 12: THUNDERBOLT 4 (Tiger Lake PCH)
# ==========================================================================
echo "[Phase 12] Thunderbolt 4..."

# TB4 NHI [8086:9a21], USB Controller [8086:9a17]
$SC --module THUNDERBOLT
$SC --module INTEL_WMI_THUNDERBOLT

echo "  [OK] Thunderbolt"

# ==========================================================================
# PHASE 13: USB-C HUB - Anker 7-in-1 (tested)
# ==========================================================================
echo "[Phase 13] USB-C hub Ethernet drivers..."

# RTL8153 USB Ethernet (Anker hub)
$SC --module USB_RTL8152

# ASIX AX88179 (alternate USB Ethernet)
$SC --module USB_NET_AX88179_178A

# CDC Ethernet (generic USB Ethernet)
$SC --module USB_NET_CDCETHER
$SC --module USB_NET_CDC_NCM

echo "  [OK] USB-C hub"

# ==========================================================================
# PHASE 14: DELL PLATFORM
# ==========================================================================
echo "[Phase 14] Dell platform drivers..."

# Parent toggle — without this, all Dell drivers are hidden
$SC --enable X86_PLATFORM_DRIVERS_DELL
$SC --module DELL_LAPTOP
$SC --module DELL_WMI
$SC --module DELL_SMBIOS
$SC --enable DELL_SMBIOS_WMI
$SC --enable DELL_SMBIOS_SMM

echo "  [OK] Dell platform"

# ==========================================================================
# PHASE 15: INTEL ISH SENSORS [8086:43fc]
# ==========================================================================
echo "[Phase 15] Intel Sensor Hub..."

$SC --module INTEL_ISH_HID
$SC --module INTEL_ISH_FIRMWARE_DOWNLOADER

# HID Sensor Hub framework
$SC --module HID_SENSOR_HUB
$SC --module HID_SENSOR_ACCEL_3D
$SC --module HID_SENSOR_GYRO_3D
$SC --module HID_SENSOR_ALS

# IIO subsystem
$SC --module HID_SENSOR_IIO_COMMON
$SC --module HID_SENSOR_IIO_TRIGGER
$SC --module IIO

echo "  [OK] ISH Sensors"

# ==========================================================================
# PHASE 16: USB / HID
# ==========================================================================
echo "[Phase 16] USB and HID..."

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

# Synaptics touchpad — RMI4 over HID-I2C for multitouch + palm rejection
$SC --enable RMI4_CORE
$SC --enable RMI4_I2C
$SC --enable RMI4_SMB
$SC --enable RMI4_F11
$SC --enable RMI4_F12
$SC --enable RMI4_F30
$SC --enable HID_RMI

echo "  [OK] USB/HID"

# ==========================================================================
# PHASE 17: CARD READER - Realtek RTS5260 [10ec:5260]
# ==========================================================================
echo "[Phase 17] Card reader..."

$SC --module MISC_RTSX_PCI
$SC --module MMC_REALTEK_PCI

echo "  [OK] Card reader"

# ==========================================================================
# PHASE 18: I2C / SERIAL IO
# ==========================================================================
echo "[Phase 18] I2C and Serial IO..."

# Intel LPSS (confirmed: intel-lpss driver on I2C #0, #1, SPI)
$SC --enable MFD_INTEL_LPSS
$SC --enable MFD_INTEL_LPSS_ACPI
$SC --enable MFD_INTEL_LPSS_PCI

# DesignWare I2C
$SC --enable I2C_DESIGNWARE_CORE
$SC --enable I2C_DESIGNWARE_PLATFORM
$SC --enable I2C_DESIGNWARE_PCI

# I2C I801 SMBus [8086:43a3]
$SC --module I2C_I801

# Pinctrl — Tiger Lake
$SC --enable PINCTRL
$SC --enable PINCTRL_INTEL
$SC --enable PINCTRL_TIGERLAKE

echo "  [OK] I2C/Serial IO"

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

# WMI
$SC --module ACPI_WMI

# MEI (Management Engine) [8086:43e0]
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

# S0ix (s2idle) + S3 deep supported
$SC --enable SUSPEND
$SC --enable HIBERNATE_CALLBACKS
$SC --enable HIBERNATION
# LZO compression for hibernate image
$SC --enable CRYPTO_LZO

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
$SC --module BRIDGE

# PPP for SSTP VPN (confirmed needed — NetworkManager SSTP)
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

# All firmware from /lib/firmware/ at runtime (no embedded firmware)
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
# PHASE 24: CRYPTO (AES-NI + hardware acceleration)
# ==========================================================================
echo "[Phase 24] Hardware crypto..."

# AES-NI + PCLMUL (confirmed in CPU flags: aes pclmul sha_ni)
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

# AMD (not present)
$SC --disable CPU_SUP_AMD
$SC --disable DRM_AMDGPU
$SC --disable DRM_RADEON

# Apple (not present)
$SC --disable HID_APPLE
$SC --disable SENSORS_APPLESMC
$SC --disable APPLE_PROPERTIES
$SC --disable APPLE_GMUX
$SC --disable MOUSE_BCM5974

# SOF audio (Tiger Lake-H uses HDA, not SOF)
$SC --disable SND_SOC_SOF_TOPLEVEL

# Legacy / enterprise (not needed)
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

# Broadcom WiFi (not present — Intel WiFi on XPS 9510)
$SC --disable BRCMUTIL
$SC --disable BRCMFMAC

# Marvell WiFi (not present — that's Surface Pro 6)
$SC --disable MWIFIEX
$SC --disable MWIFIEX_PCIE

# Surface platform (not present)
$SC --disable SURFACE_PLATFORMS 2>/dev/null || true

# Macintosh drivers (not present)
$SC --disable MACINTOSH_DRIVERS 2>/dev/null || true

echo "  [OK] Disabled"

# ==========================================================================
# DONE
# ==========================================================================
echo ""
echo "=== Dell XPS 15 9510 kernel config applied successfully ==="
echo ""
echo "Next steps:"
echo "  1. make olddefconfig              # resolve dependencies"
echo "  2. make menuconfig                # review (optional)"
echo "  3. make -j17                      # build (8C/16T)"
echo "  4. make modules_install"
echo "  5. make install                   # installkernel triggers grub-mkconfig"
echo ""
echo "Required firmware (from sys-kernel/linux-firmware):"
echo "  i915/tgl_dmc_ver2_12.bin          # GPU Display Microcontroller"
echo "  i915/tgl_guc_70.1.1.bin           # GPU GuC"
echo "  iwlwifi-QuZ-a0-hr-b0-77.ucode    # WiFi"
echo "  intel/ibt-20-*.sfi + .ddc         # Bluetooth"
echo ""
echo "NVIDIA (out-of-tree, built by nvidia-drivers ebuild):"
echo "  emerge x11-drivers/nvidia-drivers  # after kernel install"
echo "  99-module-rebuild.install handles this automatically"
echo ""
echo "Boot parameters (in /etc/default/grub):"
echo "  i915.enable_guc=3                 # Enable GuC + HuC"
echo "  nvidia.NVreg_DynamicPowerManagement=0x02  # NVIDIA runtime PM"
