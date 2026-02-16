# Dell XPS 13 9315 - Hardware Reference

**Current OS**: Gentoo Linux (production)

## System Overview

| Field | Value |
|-------|-------|
| **Product** | Dell XPS 13 9315 |
| **Board** | Dell 0WWXF6 (A02) |
| **BIOS** | 1.35.0 (11/26/2025) |
| **CPU** | 12th Gen Intel Core i5-1230U (Alder Lake) |
| **Cores** | 2P+8E / 12T (hybrid architecture) |
| **RAM** | 8GB |
| **Architecture** | x86_64 (hybrid P-Core/E-Core) |

## CPU Features

Key flags: `vmx avx avx2 avx_vnni aes sha_ni`

Notable: **No AVX-512** (fused off on Alder Lake consumer), **HFI thermal** for hybrid scheduling

## PCI Devices

| BDF | Device | PCI ID | Driver |
|-----|--------|--------|--------|
| 00:00.0 | Host Bridge | `[8086:4602]` | - |
| 00:02.0 | Alder Lake-UP4 GT2 [Iris Xe] | `[8086:46aa]` | i915 |
| 00:04.0 | Innovation Platform Framework | `[8086:461d]` | proc_thermal_pci |
| 00:06.0 | Imaging Signal Processor | `[8086:465d]` | intel_ipu6 |
| 00:07.0 | TB4 PCI Express Root Port | `[8086:466e]` | pcieport |
| 00:0d.0 | TB4 USB Controller | `[8086:461e]` | xhci_hcd |
| 00:0d.2 | TB4 NHI | `[8086:463e]` | thunderbolt |
| 00:12.0 | Integrated Sensor Hub | `[8086:51fc]` | intel_ish_ipc |
| 00:14.0 | USB 3.2 xHCI | `[8086:51ed]` | xhci_hcd |
| 00:14.3 | CNVi WiFi (AX211) | `[8086:51f0]` | iwlwifi |
| 00:15.0 | Serial IO I2C #0 | `[8086:51e8]` | intel-lpss |
| 00:15.1 | Serial IO I2C #1 | `[8086:51e9]` | intel-lpss |
| 00:16.0 | HECI/MEI Controller | `[8086:51e0]` | mei_me |
| 00:1f.0 | LPC/eSPI Controller | `[8086:5182]` | - |
| 00:1f.3 | Smart Sound Audio | `[8086:51cc]` | sof-audio-pci-intel-tgl |
| 00:1f.4 | SMBus Controller | `[8086:51a3]` | i801_smbus |
| 00:1f.5 | SPI Controller | `[8086:51a4]` | intel-lpss |
| 01:00.0 | Phison PS5019-E19 NVMe | `[1987:5019]` | nvme |

## Networking

- **WiFi**: Intel AX211 160MHz 2x2 CNVi (`iwlwifi` driver)
- **Bluetooth**: Intel AX211 (`btusb`/`btintel` drivers)
- **Wired**: None built-in (USB Ethernet adapter supported)

## Storage

- **NVMe**: Phison PS5019-E19 PCIe4 NVMe (DRAM-less) (`nvme` driver)
- **Layout**:
  - `/boot/efi` - 512M (vfat)
  - `[SWAP]` - 24G
  - `/` - 50G (ext4)
  - `/var/tmp` - 40G (xfs)
  - `/home` - 124G (xfs)

## Audio

- **Controller**: Alder Lake Smart Sound Technology `[8086:51cc]`
- **Driver**: `sof-audio-pci-intel-tgl` (Sound Open Firmware)
- **Codec**: Realtek RT715 SDCA, RT1316 SDW (SoundWire)

## Graphics

- **GPU**: Intel Alder Lake-UP4 GT2 Iris Xe Graphics `[8086:46aa]`
- **Driver**: `i915`
- **Features**: VAAPI hardware acceleration, backlight control

## Camera

- **ISP**: Intel Alder Lake Imaging Signal Processor `[8086:465d]`
- **Driver**: `intel_ipu6`
- **Sensor**: OV01A10 (via `intel_skl_int3472` power control)
- **VSC**: Intel Visual Sensing Controller (`mei_vsc_hw`)

## Input Devices

- **Touchpad**: VEN_0488:00 `[0488:102D]` (HID over I2C)
- **Bus**: i2c-1 via Intel LPSS I2C Controller #1 `[8086:51e9]`

## Thunderbolt / USB-C

- **Thunderbolt 4**: Dual USB-C ports with DisplayPort Alt Mode
- **USB 3.2**: Intel Alder Lake PCH xHCI `[8086:51ed]`

## Platform-Specific

- **Integrated Sensor Hub**: Intel ISH `[8086:51fc]` (`intel_ish_ipc`)
- **Dell Platform Drivers**: DELL_LAPTOP, DELL_WMI, DELL_SMBIOS, DELL_SMO8800
- **HFI Thermal**: Intel Hardware Feedback Interface (hybrid core scheduling)
- **Innovation Platform Framework**: `proc_thermal_pci`

## Firmware (embedded in kernel)

| File | Purpose |
|------|---------|
| `i915/adlp_dmc_ver2_16.bin` | Alder Lake-P Display Microcontroller |
| `i915/adlp_guc_70.bin` | Alder Lake-P GuC |
| `i915/adlp_huc.bin` | Alder Lake-P HuC |
| `iwlwifi-so-a0-gf-a0-89.ucode` | Intel AX211 WiFi firmware |
| `iwlwifi-so-a0-gf-a0.pnvm` | Intel AX211 WiFi PNVM data |
| `intel/ibt-0040-0041.sfi` | Intel Bluetooth firmware |
| `intel/ibt-0040-0041.ddc` | Intel Bluetooth DDC configuration |
