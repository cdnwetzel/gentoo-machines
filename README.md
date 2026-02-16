# gentoo_dell_xps9315

A production-ready Gentoo Linux kernel configuration for the Dell XPS 13 9315 laptop.

## Kernel Version

- **Linux**: 6.12.58-gentoo
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

## Hardware Support

### Graphics
- **Device**: Intel Alder Lake-UP4 GT2 [Iris Xe Graphics] `[8086:46aa]`
- **Driver**: i915
- **Features**: AGP support, ACPI video/backlight control

### Networking
- **WiFi**: Intel Alder Lake-P PCH CNVi WiFi (AX211 160MHz 2x2) `[8086:51f0]`
- **Driver**: iwlwifi
- **Bluetooth**: Intel AX211 (btusb driver)

### Storage
- **Controller**: Phison PS5019-E19 PCIe4 NVMe (DRAM-less) `[1987:5019]`
- **Driver**: nvme
- **Layout**:
  - `/boot/efi` - 512M (vfat)
  - `[SWAP]` - 24G
  - `/` - 50G (ext4)
  - `/var/tmp` - 40G (xfs)
  - `/home` - 124G (xfs)

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
| Serial IO I2C #0 | `[8086:51e8]` | intel-lpss |
| Serial IO I2C #1 | `[8086:51e9]` | intel-lpss |
| SMBus Controller | `[8086:51a3]` | i801_smbus |
| SPI Controller | `[8086:51a4]` | intel-lpss |

### Camera
- **ISP**: Intel Alder Lake Imaging Signal Processor `[8086:465d]`
- **Driver**: intel_ipu6
- **Sensor**: OV01A10 (via intel_skl_int3472)
- **VSC**: Intel Visual Sensing Controller (mei_vsc_hw)

### Input Devices
- **Touchpad**: VEN_0488:00 `[0488:102D]` (HID over I2C)
- **Bus**: i2c-1 via Intel LPSS I2C Controller #1 `[8086:51e9]`

### Connectivity
- **Thunderbolt 4**: Dual USB-C ports with DisplayPort Alt Mode
- **USB 3.2**: Intel Alder Lake PCH xHCI `[8086:51ed]`

## Features

- SELinux enabled
- Cgroup v2 with memory, blkio, and CPU controllers
- Full namespace support (containers)
- EXT4 and XFS filesystem support
- GZIP kernel compression
- Debug kernel enabled for development

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
| Chipset | Intel Chipset Device Software | Chipset |
| Sensors | Intel Integrated Sensor Solution Driver | Chipset |
| Audio Enhancement | Waves MaxxAudio Pro Application | Audio |
| Serial I/O | Intel Serial IO Driver | Chipset |
| Power Management | Intel Processor Power Management Utility | Systems Management |
| Dynamic Tuning | Intel Dynamic Tuning Driver | Chipset |
| Platform Framework | Intel Innovation Platform Framework Driver | Chipset |
| PPM | Intel PPM Provisioning Package | Chipset |

## Gentoo Profile

```
Profile: default/linux/amd64/23.0
Kernel:  linux-6.12.58-gentoo
```

## Portage Configuration

### Files Included

| File | Purpose |
|------|---------|
| `make.conf` | Global build settings, USE flags, compiler optimization |
| `package.use` | Per-package USE flags |
| `package.accept_keywords` | Testing (~amd64) packages |
| `world` | Installed package list |
| `fstab` | Filesystem mount configuration (template) |

### make.conf

The included `make.conf` is optimized for the XPS 13 9315:

```bash
# Compiler flags - Alder Lake optimized
COMMON_FLAGS="-march=alderlake -O2 -pipe"

# 8GB RAM constraint - safe parallelism
MAKEOPTS="-j8"
EMERGE_DEFAULT_OPTS="--jobs=2 --load-average=8"

# Video Drivers
VIDEO_CARDS="intel iris"

# USE flags optimized for XPS 13 9315
USE="X gtk dbus elogind udisks vaapi gallium dri proprietary-codecs \
     python ssl readline sqlite ncurses zlib lzma \
     -systemd -pulseaudio -bluetooth -cups -doc -nls -gnome -kde"
```

Key settings:
- `-march=alderlake` for native CPU optimization
- Intel Iris Xe graphics with VAAPI hardware acceleration
- elogind (no systemd)
- Python 3.12/3.13 targets
- GRUB EFI-64 platform

## Firmware Configuration

The Dell XPS 9315 (Alder Lake) only needs a specific subset of firmware. Set this in `make menuconfig`:

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

## Usage

### Hardware Inventory

Two scripts are provided for capturing hardware details:

**harvest.sh** - Comprehensive hardware inventory:
```bash
sudo ./harvest.sh
```
Generates `hardware_inventory.log` with PCI devices, CPU info, loaded modules, and storage layout.

**deep_harvest.sh** - Focused XPS 9315 harvest:
```bash
sudo -E ./deep_harvest.sh
```
Generates `xps_harvest.log` with modprobed-db update, I2C/touchpad detection, and actual firmware in use.

### Module Tracking

Store currently loaded modules for future kernel builds using modprobed-db:

```bash
# Force the user identity for modprobed-db
USER=$SUDO_USER modprobed-db store
```

### Kernel Build

```bash
# Copy to kernel source
cp .config /usr/src/linux/

# Build
cd /usr/src/linux
make oldconfig
make -j$(nproc)

# Install (as root)
make modules_install
make install
grub-mkconfig -o /boot/grub/grub.cfg
```
