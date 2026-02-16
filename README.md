# gentoo_dell_xps9315

A production-ready Gentoo Linux kernel configuration for the Dell XPS 13 9315 laptop.

## Kernel Version

- **Linux**: 6.12.58-gentoo
- **Architecture**: x86_64
- **Compiler**: GCC 15.2.1

## Hardware Support

### Processor
- Intel 12th Gen Alder Lake CPU
- Intel P-State frequency scaling
- Intel idle driver

### Graphics
- Intel Iris Xe (i915 module)
- AGP Intel support
- ACPI video/backlight control

### Networking
- Intel WiFi (iwlwifi module)
- Intel Bluetooth

### Storage
- NVMe SSD support (native)

### Audio
- Intel HDA audio (snd_hda_intel module)

### Power Management
- ACPI battery support
- Power supply hardware monitoring
- Intel thermal management (PCH, TCC, HFI)

### Connectivity
- USB4/Thunderbolt 4 support
- Intel MEI (Management Engine Interface)
- Intel LPSS (Low Power Subsystem)

### Camera
- Intel IPU6 camera support (module)
- Intel VSC (Visual Sensing Controller)

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
