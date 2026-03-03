#!/bin/bash
# ============================================================================
# Gentoo Kernel Config - MacBook Pro 12,1 (Early 2015)
# ============================================================================
# ALL settings verified against:
#   - 3 rounds of live USB hardware harvesting
#   - Fedora 43 kernel 6.17.1-300.fc43.x86_64 running config
#   - dmesg firmware analysis
#   - Community configs (coldnew/macbook-pro-2015-gentoo)
#
# USAGE:
#   cd /usr/src/linux
#   make defconfig
#   bash /path/to/kernel_config.sh
#   make menuconfig    # review
#   make -j5 && make modules_install && make install
# ============================================================================

set -euo pipefail

SC="./scripts/config"

if [[ ! -x "$SC" ]]; then
    echo "ERROR: Run this from /usr/src/linux (scripts/config not found)"
    exit 1
fi

echo "=== Applying MacBook Pro 12,1 kernel config ==="

# --------------------------------------------------------------------------
# GENERAL
# --------------------------------------------------------------------------
$SC --enable IKCONFIG
$SC --enable IKCONFIG_PROC
$SC --set-str DEFAULT_HOSTNAME "gentoo-mbp"

# Apple platform properties (confirmed in Fedora: CONFIG_APPLE_PROPERTIES=y)
$SC --enable APPLE_PROPERTIES

# --------------------------------------------------------------------------
# PROCESSOR - Intel Core i7-5557U (Broadwell, 2C/4T, 3.1GHz)
# --------------------------------------------------------------------------
$SC --enable SMP
$SC --set-val NR_CPUS 4
$SC --enable MCORE2

$SC --enable SCHED_MC
$SC --enable SCHED_SMT
$SC --enable X86_INTEL_PSTATE
$SC --enable CPU_FREQ_DEFAULT_GOV_POWERSAVE
$SC --enable INTEL_IDLE
$SC --enable MICROCODE
$SC --enable MICROCODE_INTEL
$SC --enable X86_X2APIC

# Broadwell thermal/power
$SC --enable INTEL_RAPL
$SC --enable X86_PKG_TEMP_THERMAL
$SC --enable INTEL_POWERCLAMP
$SC --enable CORETEMP

# KVM
$SC --module KVM
$SC --module KVM_INTEL

# --------------------------------------------------------------------------
# MEMORY / SWAP - 16GB RAM + zram (4GB zstd)
# --------------------------------------------------------------------------
# zram built-in (no initramfs); zram-init: load_on_start=no
$SC --enable ZRAM
$SC --enable ZRAM_BACKEND_ZSTD
$SC --enable CRYPTO_ZSTD
$SC --enable ZSTD_COMPRESS
$SC --enable ZSTD_DECOMPRESS
$SC --set-str ZRAM_DEF_COMP "zstd"

$SC --enable SWAP
$SC --enable ZSWAP
$SC --enable KSM

# LZ4 still useful for other compression
$SC --enable LZ4_COMPRESS
$SC --enable LZ4HC_COMPRESS

# --------------------------------------------------------------------------
# ACPI / PLATFORM - Apple EFI v1.1
# --------------------------------------------------------------------------
# Confirmed: DMI detected Apple hardware, ACPI tables from APPLE/Loki
# DSDT: APPLE MacBookP, SSDT tables for SataAhci, PcieTbt, Xhci, etc.
$SC --enable PCI
$SC --enable PCIEPORTBUS
$SC --enable HOTPLUG_PCI_PCIE
$SC --enable ACPI
$SC --enable ACPI_AC
$SC --enable ACPI_BATTERY
$SC --enable ACPI_BUTTON
$SC --enable ACPI_FAN
$SC --enable ACPI_PROCESSOR
$SC --enable ACPI_THERMAL
$SC --enable ACPI_VIDEO

# applesmc - confirmed: key=670 fan=1 temp=35 index=34 acc=0 lux=2 kbd=1
# Provides: fan control, 35 temp sensors, ambient light, keyboard backlight
# Required by mbpfan
$SC --module SENSORS_APPLESMC

# Apple MFI fastcharge (confirmed loaded)
$SC --module APPLE_MFI_FASTCHARGE

# Apple GMUX (confirmed in Fedora config: CONFIG_APPLE_GMUX=m)
# Handles display muxing on dual-GPU models; harmless on single-GPU
$SC --module APPLE_GMUX

# WMI
$SC --module WMI
$SC --module ACPI_WMI

# --------------------------------------------------------------------------
# GPU - Intel Iris Graphics 6100 (Broadwell GT3)
# --------------------------------------------------------------------------
# Confirmed: No GuC/HuC/DMC firmware on Broadwell (all params = -1/auto)
# Confirmed: enable_ips=Y (Broadwell-specific Intermediate Pixel Storage)
# Outputs: eDP-1 (panel), DP-1, DP-2, HDMI-A-1, HDMI-A-2 (via TB2)
$SC --enable DRM
$SC --module DRM_I915
$SC --enable DRM_I915_CAPTURE_ERROR
$SC --enable DRM_I915_COMPRESS_ERROR
$SC --enable DRM_I915_USERPTR
$SC --enable DRM_I915_PXP

# Framebuffer - EFI for early boot console
$SC --enable FB
$SC --enable FB_EFI
$SC --enable FRAMEBUFFER_CONSOLE
$SC --enable DRM_FBDEV_EMULATION

# --------------------------------------------------------------------------
# BACKLIGHT
# --------------------------------------------------------------------------
# Confirmed: intel_backlight active (type=raw, max=1388)
# Keyboard: smc::kbd_backlight (max=255)
$SC --enable BACKLIGHT_CLASS_DEVICE
$SC --module BACKLIGHT_APPLE

# --------------------------------------------------------------------------
# INPUT - Trackpad + Keyboard
# --------------------------------------------------------------------------
$SC --enable HID
$SC --enable USB_HID
$SC --module HID_APPLE

# Confirmed HID device: 05AC:0273 "Apple Internal Keyboard / Trackpad"
$SC --enable INPUT_MOUSEDEV
$SC --enable INPUT_EVDEV

# bcm5974 trackpad - confirmed: PROP=5 (POINTER|BUTTONPAD = clickpad)
$SC --module USB_BCM5974
$SC --enable INPUT_UINPUT

# Apple SPI keyboard - confirmed: spi-APP000D:00, "USB interface already enabled"
# On 12,1 the keyboard works via USB HID; applespi is the SPI fallback
$SC --module KEYBOARD_APPLESPI
$SC --module SPI_PXA2XX
$SC --module SPI_PXA2XX_PCI
$SC --module SPI_PXA2XX_PLATFORM

# Apple trackpad alternative driver (confirmed in Fedora config)
$SC --module MOUSE_APPLETOUCH

# DMA controller for SPI
$SC --enable DMADEVICES
$SC --module DW_DMAC
$SC --module DW_DMAC_PCI

# --------------------------------------------------------------------------
# AUDIO - Cirrus Logic CS4208 (Apple variant, subsystem 0x106b7b00)
# --------------------------------------------------------------------------
# Confirmed pin config from /proc/asound/card1/codec#0:
#   Pin 0x002b4020: [Jack] HP Out at Ext (headphone jack, combo connector)
#   Pin 0x90100110: [Fixed] Speaker at Int (left speaker)
#   Pin 0x90100112: [Fixed] Speaker at Int (right speaker)
#   Multiple 0x400000f0: [N/A] unused pins
#
# ALSA cards:
#   card0 [HDMI]: HDA Intel HDMI at 0xc1810000 irq 76
#   card1 [PCH]:  HDA Intel PCH  at 0xc1814000 irq 77
$SC --module SND_HDA_INTEL
$SC --module SND_HDA_CODEC_HDMI
$SC --module SND_HDA_CODEC_CS420X
$SC --module SND_HDA_CODEC_GENERIC

# HDA features confirmed from Fedora config
$SC --enable SND_HDA_HWDEP
$SC --enable SND_HDA_RECONFIG
$SC --enable SND_HDA_INPUT_BEEP
$SC --set-val SND_HDA_INPUT_BEEP_MODE 0
$SC --enable SND_HDA_PATCH_LOADER
$SC --enable SND_HDA_POWER_SAVE
$SC --set-val SND_HDA_POWER_SAVE_DEFAULT 10
$SC --enable SND_HDA_I915

# ALSA core
$SC --enable SOUND
$SC --module SND
$SC --module SND_PCM
$SC --module SND_HWDEP
$SC --module SND_SEQ
$SC --module SND_TIMER
$SC --module SND_HRTIMER

# --------------------------------------------------------------------------
# WIFI - Broadcom BCM43602 (brcmfmac, PCIe)
# --------------------------------------------------------------------------
# Confirmed working: BCM43602/1 v7.35.177.61
# Confirmed: 802.11ac, 3x3 MIMO, VHT 80MHz, bands 2.4+5GHz
# Connected on 5GHz ch52 80MHz in testing
# 4 supplementary firmware blobs fail (non-critical) - see wifi_firmware_fix.sh
$SC --module CFG80211
$SC --module MAC80211
$SC --enable CFG80211_WEXT
$SC --module BRCMUTIL
$SC --module BRCMFMAC
$SC --enable BRCMFMAC_PCIE

# --------------------------------------------------------------------------
# BLUETOOTH - Broadcom BCM20703A1 (Apple 20MHz variant)
# --------------------------------------------------------------------------
# Confirmed from dmesg: "BCM20703A1 Generic USB UHE Apple 20Mhz fcbga_X87"
$SC --module BT
$SC --module BT_RFCOMM
$SC --module BT_BNEP
$SC --module BT_HIDP
$SC --module BT_HCIBTUSB
$SC --module BT_BCM

# --------------------------------------------------------------------------
# ETHERNET - None onboard; USB dongles
# --------------------------------------------------------------------------
$SC --module USB_NET_DRIVERS
$SC --module USB_RTL8152
$SC --module USB_NET_CDC_ETHER

# --------------------------------------------------------------------------
# STORAGE - APPLE SSD SM0256G (Samsung OEM, AHCI)
# --------------------------------------------------------------------------
# Confirmed: ATA-8, UDMA/133, NCQ depth 32
# TRIM: supported, limit 8 blocks -> use fstrim.timer, NOT mount discard
# MUST be built-in (=y) - this is the boot drive
$SC --enable ATA
$SC --enable SATA_AHCI
$SC --enable BLK_DEV_SD

# I/O scheduler - BFQ confirmed working in Fedora for this SSD
$SC --enable BLK_DEV_THROTTLING
$SC --enable IOSCHED_BFQ
$SC --enable BFQ_GROUP_IOSCHED

# USB storage (confirmed: UAS + usb-storage active, SD card reader on bus 2)
$SC --module USB_STORAGE
$SC --module USB_UAS

# NVMe over TCP (keep for network storage flexibility)
$SC --module NVME_CORE
$SC --module NVME_TCP
$SC --module NVME_FABRICS

# --------------------------------------------------------------------------
# USB - xHCI (Wildcat Point-LP)
# --------------------------------------------------------------------------
$SC --enable USB
$SC --enable USB_XHCI_HCD
$SC --enable USB_XHCI_PCI

# --------------------------------------------------------------------------
# THUNDERBOLT 2 - Intel Falcon Ridge DSL5520
# --------------------------------------------------------------------------
# Confirmed: thunderbolt module loaded, IRQ 56/57
# Note: "device link creation from 0000:06:00.0 failed" in dmesg is a
# known harmless warning for Falcon Ridge
$SC --module THUNDERBOLT

# Thunderbolt WMI (confirmed in Fedora config)
$SC --module INTEL_WMI_THUNDERBOLT

# --------------------------------------------------------------------------
# CAMERA - Broadcom 720p FaceTime HD (14e4:1570)
# --------------------------------------------------------------------------
# NOT in mainline kernel. Requires out-of-tree: github.com/patjak/facetimehd
$SC --enable MEDIA_SUPPORT
$SC --enable MEDIA_CAMERA_SUPPORT
$SC --enable VIDEO_DEV

# --------------------------------------------------------------------------
# SD CARD READER
# --------------------------------------------------------------------------
# Confirmed from dmesg: "APPLE SD Card Reader 3.00" on USB bus 2
# Handled by usb-storage (already enabled above)

# --------------------------------------------------------------------------
# I2C - 8 buses confirmed (i915 gmbus x4, AUX x3, SMBus I801)
# --------------------------------------------------------------------------
$SC --module I2C_I801
$SC --module I2C_SMBUS
$SC --module I2C_ALGO_BIT
$SC --module I2C_DEV

# --------------------------------------------------------------------------
# THERMAL / POWER MANAGEMENT
# --------------------------------------------------------------------------
# Confirmed thermal zones:
#   thermal_zone0: BAT0       (31°C at idle)
#   thermal_zone1: pch_wildcat_point (52°C at idle)
#   thermal_zone2: x86_pkg_temp     (56°C at idle)
# Confirmed hwmon: ADP1, BAT0, pch_wildcat_point, coretemp
$SC --module INTEL_PCH_THERMAL
$SC --enable THERMAL
$SC --enable THERMAL_HWMON
$SC --module INTEL_RAPL_MSR

# MEI (Management Engine Interface)
$SC --module INTEL_MEI
$SC --module INTEL_MEI_ME
$SC --module INTEL_MEI_HDCP
$SC --module INTEL_MEI_PXP

# Watchdog
$SC --module ITCO_WDT
$SC --enable ITCO_VENDOR_SUPPORT

# --------------------------------------------------------------------------
# SUSPEND / HIBERNATE
# --------------------------------------------------------------------------
# Confirmed: freeze mem disk all supported
# Confirmed: mem_sleep = s2idle [deep]  (S3 deep is default and working)
$SC --enable SUSPEND
$SC --enable HIBERNATE_CALLBACKS
$SC --enable HIBERNATION

# --------------------------------------------------------------------------
# FILESYSTEMS
# --------------------------------------------------------------------------
$SC --enable EXT4_FS
$SC --enable BTRFS_FS
$SC --enable XFS_FS
$SC --module VFAT_FS
$SC --module EXFAT_FS
$SC --enable TMPFS
$SC --enable PROC_FS
$SC --enable SYSFS

# EFI filesystem
$SC --enable EFI_PARTITION
$SC --enable EFIVAR_FS

# FUSE (for apfs-fuse to access macOS on sda2)
$SC --module FUSE_FS

# --------------------------------------------------------------------------
# NETWORKING
# --------------------------------------------------------------------------
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

# --------------------------------------------------------------------------
# FIRMWARE LOADING
# --------------------------------------------------------------------------
# No GPU firmware needed (Broadwell i915 doesn't use GuC/HuC/DMC)
# WiFi firmware loaded at runtime from /lib/firmware/brcm/
$SC --enable FW_LOADER
$SC --enable FW_LOADER_USER_HELPER
$SC --set-str EXTRA_FIRMWARE ""

# --------------------------------------------------------------------------
# EFI BOOT - Apple EFI v1.1, 64-bit
# --------------------------------------------------------------------------
# Confirmed: EFI boot YES, bitness 64, no Secure Boot
# Only Boot0080 (macOS) exists - need to add Gentoo entry
$SC --enable EFI
$SC --enable EFI_STUB
$SC --enable EFI_MIXED
$SC --enable EFI_VARS

# --------------------------------------------------------------------------
# CRYPTO - Hardware-accelerated (AES-NI + PCLMUL from Broadwell)
# --------------------------------------------------------------------------
$SC --module CRYPTO_AES_NI_INTEL
$SC --module CRYPTO_GHASH_CLMUL_NI_INTEL
$SC --module CRYPTO_POLYVAL_CLMUL_NI

# --------------------------------------------------------------------------
# DISABLE UNNECESSARY HARDWARE
# --------------------------------------------------------------------------
$SC --disable CPU_SUP_AMD
$SC --disable DRM_AMDGPU
$SC --disable DRM_RADEON
$SC --disable DRM_NOUVEAU
$SC --disable MICROCODE_AMD
$SC --disable INFINIBAND
$SC --disable SOUND_OSS_CORE
$SC --disable PCMCIA
$SC --disable PARPORT

# iSCSI initiators (all loaded on live USB, none needed)
$SC --disable BE2ISCSI
$SC --disable BNX2I
$SC --disable CXGB4I
$SC --disable CXGB3I
$SC --disable QLA4XXX
$SC --disable SCSI_CXGB3_ISCSI
$SC --disable SCSI_CXGB4_ISCSI

# --------------------------------------------------------------------------
# SECURITY
# --------------------------------------------------------------------------
$SC --enable SECURITY
$SC --enable SECCOMP
$SC --enable SECURITY_YAMA
$SC --enable PAGE_TABLE_ISOLATION
$SC --enable RETPOLINE

echo ""
echo "=== Config applied successfully ==="
echo ""
echo "Next steps:"
echo "  1. make menuconfig              # review"
echo "  2. make -j5"
echo "  3. make modules_install"
echo "  4. make install"
echo ""
echo "Required packages:"
echo "  emerge sys-kernel/linux-firmware   # brcmfmac43602 WiFi blobs"
echo "  emerge sys-firmware/intel-microcode"
echo "  emerge app-laptop/mbpfan           # fan: 1299-6199 RPM"
echo ""
echo "Kernel boot parameters (add to rEFInd or GRUB):"
echo '  acpi_osi="!Darwin" i915.enable_fbc=1 i915.enable_psr=2'
echo ""
echo "Audio troubleshooting (if headphone/speaker switching fails):"
echo "  The CS4208 Apple variant (subsystem 0x106b7b00) has known"
echo "  pin quirks. If auto-switching doesn't work, try:"
echo '    options snd-hda-intel model=mbp11 patch=cs4208_mbp11_patch'
