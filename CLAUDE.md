# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a production-ready Linux kernel configuration (`.config`) specifically tuned for the **Dell XPS 13 9315 laptop** running **Gentoo Linux**.

- **Kernel**: Linux 6.12.58-gentoo
- **Architecture**: x86_64
- **Compiler**: GCC 15.2.1

## System Specifications

### CPU
- **Model**: 12th Gen Intel Core i5-1230U (Alder Lake)
- **Architecture**: Hybrid P-Core/E-Core
- **Features**: VMX, AVX2, AVX-VNNI, AES-NI, SHA-NI, Intel HWP

### Motherboard
- **Vendor**: Dell Inc.
- **Product**: 0WWXF6 (A02)
- **BIOS Version**: 1.35.0 (11/26/2025)

## Purpose

The `.config` file is a complete, working kernel configuration that can be used to:
- Rebuild the kernel with identical settings on a Dell XPS 9315
- Serve as a reference for similar Intel 12th-gen Alder Lake systems
- Quickly deploy Gentoo on new XPS 9315 machines

## Hardware Support

### Graphics
- **Device**: Intel Alder Lake-UP4 GT2 [Iris Xe Graphics] `[8086:46aa]`
- **Driver**: i915

### Networking
- **WiFi**: Intel Alder Lake-P PCH CNVi WiFi (AX211 160MHz 2x2) `[8086:51f0]`
- **Driver**: iwlwifi
- **Bluetooth**: Intel AX211 (btusb driver)

### Storage
- **Controller**: Phison PS5019-E19 PCIe4 NVMe (DRAM-less) `[1987:5019]`
- **Driver**: nvme

### Audio
- **Controller**: Intel Alder Lake Smart Sound Technology `[8086:51cc]`
- **Driver**: sof-audio-pci-intel-tgl (Sound Open Firmware)
- **Codec**: Realtek RT715 SDCA, RT1316 SDW

### Chipset & Platform
| Component | Device ID | Driver |
|-----------|-----------|--------|
| Host Bridge | `[8086:4602]` | - |
| Innovation Platform Framework | `[8086:461d]` | proc_thermal_pci |
| Imaging Signal Processor | `[8086:465d]` | intel_ipu6 |
| Thunderbolt 4 USB Controller | `[8086:461e]` | xhci_hcd |
| Thunderbolt 4 NHI | `[8086:463e]` | thunderbolt |
| Integrated Sensor Hub | `[8086:51fc]` | intel_ish_ipc |
| HECI Controller (MEI) | `[8086:51e0]` | mei_me |
| Serial IO I2C | `[8086:51e8]` `[8086:51e9]` | intel-lpss |
| SMBus Controller | `[8086:51a3]` | i801_smbus |

### Camera
- **ISP**: Intel Alder Lake Imaging Signal Processor `[8086:465d]`
- **Driver**: intel_ipu6
- **Sensor**: OV01A10 (via intel_skl_int3472)

### Input Devices
- **Touchpad**: VEN_0488:00 `[0488:102D]` (HID over I2C)
- **Bus**: i2c-1 via Intel LPSS I2C Controller #1 `[8086:51e9]`

### Connectivity
- **Thunderbolt 4**: Dual USB-C ports with DisplayPort Alt Mode
- **USB 3.2**: Intel Alder Lake PCH xHCI `[8086:51ed]`

## Key Configuration Characteristics

- **Virtualization**: KVM guest support with full virtio stack
- **Security**: SELinux enabled with full mandatory access control
- **Containers**: Complete namespace and cgroup v2 support
- **Debugging**: DEBUG_KERNEL and FTRACE enabled for development
- **Modules**: 157 features compiled as loadable modules
- **Filesystems**: EXT4 and XFS with full feature support
- **Compression**: GZIP kernel compression

## Dell Windows Driver Reference

This kernel configuration was built using the Dell XPS 13 9315 Windows drivers as reference for hardware support:

| Component | Driver | Category |
|-----------|--------|----------|
| BIOS | Dell XPS 9315 System BIOS | BIOS |
| Ethernet | Realtek USB GBE Ethernet Controller Driver | Docks/Stands |
| Chipset | Intel Management Engine Components Installer | Chipset |
| Storage | Intel Rapid Storage Technology Driver | Storage |
| Graphics | Intel UHD/Iris Xe Graphics Driver | Video |
| Audio | Realtek High Definition Audio Driver | Audio |
| WiFi | Intel BE201/BE200/AX211 Wi-Fi Controller Driver | Network |
| Bluetooth | Intel BE2xx/AX4xx/AX2xx/9xxx Bluetooth Driver | Network |
| Fingerprint | Goodix Fingerprint Sensor Driver | Security |
| Camera | Intel 2D Imaging/MCU/Visual Sensing Controller Driver | Camera |
| HID | Intel HID Event Filter Driver | Input Devices |
| Sensors | Intel Integrated Sensor Solution Driver | Chipset |
| Serial I/O | Intel Serial IO Driver | Chipset |
| Dynamic Tuning | Intel Dynamic Tuning Driver | Chipset |
| Platform Framework | Intel Innovation Platform Framework Driver | Chipset |

## Portage Configuration (make.conf)

Key settings for XPS 13 9315:

```bash
COMMON_FLAGS="-march=alderlake -O2 -pipe"
MAKEOPTS="-j8"
VIDEO_CARDS="intel iris"
USE="X gtk dbus elogind udisks vaapi gallium dri proprietary-codecs ..."
GRUB_PLATFORMS="efi-64"
```

- Alder Lake native CPU optimization
- Intel Iris Xe with VAAPI
- elogind (no systemd)
- Python 3.12/3.13

## Firmware Configuration

The Dell XPS 9315 (Alder Lake) only needs a specific subset of firmware:

```
CONFIG_EXTRA_FIRMWARE="i915/adlp_dmc_ver2_16.bin i915/adlp_guc_70.bin i915/adlp_huc.bin iwlwifi-so-a0-gf-a0-89.ucode iwlwifi-so-a0-gf-a0.pnvm intel/ibt-0040-0041.sfi intel/ibt-0040-0041.ddc"
CONFIG_EXTRA_FIRMWARE_DIR="/lib/firmware"
```

| Firmware | Purpose |
|----------|---------|
| `i915/adlp_dmc_ver2_16.bin` | Intel Alder Lake-P Display Microcontroller |
| `i915/adlp_guc_70.bin` | Intel Alder Lake-P Graphics microController |
| `i915/adlp_huc.bin` | Intel Alder Lake-P HEVC/H.265 microController |
| `iwlwifi-so-a0-gf-a0-89.ucode` | Intel AX211 WiFi firmware |
| `iwlwifi-so-a0-gf-a0.pnvm` | Intel AX211 WiFi PNVM data |
| `intel/ibt-0040-0041.sfi` | Intel Bluetooth firmware |
| `intel/ibt-0040-0041.ddc` | Intel Bluetooth DDC configuration |

## Tools

### harvest.sh

General-purpose hardware inventory script (works on any Linux system):

```bash
sudo ./harvest.sh
```

Generates `hardware_inventory.log` with PCI devices, CPU info, motherboard/BIOS, I2C buses, USB topology, loaded modules, firmware list, and storage layout.

### deep_harvest.sh

Deep hardware discovery script (works on any Linux system):

```bash
sudo -E ./deep_harvest.sh
```

Generates `deep_harvest.log` with modprobed-db update, I2C/touchpad detection, actual firmware in use, and full PCI/module inventory.

## Kernel Build Commands

```bash
# Copy config to kernel source directory
cp .config /usr/src/linux/.config

# Build kernel
cd /usr/src/linux
make oldconfig        # Update config for kernel version differences
make -j$(nproc)       # Compile kernel and modules

# Install (requires root)
make modules_install
make install

# Update bootloader (GRUB example)
grub-mkconfig -o /boot/grub/grub.cfg
```
