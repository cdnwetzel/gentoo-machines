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

## Usage

### Hardware Inventory

Use the included `harvest.sh` script to capture hardware details for kernel configuration:

```bash
sudo ./harvest.sh
```

This generates `hardware_inventory.log` with PCI devices, CPU info, loaded modules, and storage layout.

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
