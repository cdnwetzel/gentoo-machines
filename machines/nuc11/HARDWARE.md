# Intel NUC11TNBi5 - Hardware Reference

**Current OS**: Ubuntu (harvested for Gentoo migration)

## System Overview

| Field | Value |
|-------|-------|
| **Product** | Intel NUC11TNBi5 |
| **Board** | NUC11TNBi5 M11904-404 |
| **BIOS** | TNTGL357.0064.2022.0217.1550 |
| **CPU** | 11th Gen Intel Core i5-1135G7 @ 2.40GHz (Tiger Lake) |
| **Cores** | 4C/8T |
| **Architecture** | x86_64 (no hybrid P/E-cores) |

## CPU Features

Key flags: `vmx avx avx2 avx512f avx512dq avx512cd avx512bw avx512vl avx512_vnni sha_ni aes gfni vaes vpclmulqdq`

Notable: **AVX-512** support (not available on Alder Lake consumer)

## PCI Devices

| BDF | Device | PCI ID | Driver | Module |
|-----|--------|--------|--------|--------|
| 00:00.0 | Host Bridge / DRAM Registers | `[8086:9a14]` | - | igen6_edac |
| 00:02.0 | TigerLake-LP GT2 [Iris Xe] | `[8086:9a49]` | i915 | i915, xe |
| 00:06.0 | PCIe Controller | `[8086:9a09]` | pcieport | - |
| 00:07.0 | TB4 PCIe Root Port #1 | `[8086:9a25]` | pcieport | - |
| 00:07.2 | TB4 PCIe Root Port #2 | `[8086:9a27]` | pcieport | - |
| 00:08.0 | GNA Scoring Accelerator | `[8086:9a11]` | - | - |
| 00:0d.0 | TB4 USB Controller | `[8086:9a13]` | xhci_hcd | - |
| 00:0d.2 | TB4 NHI #0 | `[8086:9a1b]` | thunderbolt | thunderbolt |
| 00:0d.3 | TB4 NHI #1 | `[8086:9a1d]` | thunderbolt | thunderbolt |
| 00:14.0 | USB 3.2 Gen 2x1 xHCI | `[8086:a0ed]` | xhci_hcd | - |
| 00:14.2 | Shared SRAM | `[8086:a0ef]` | - | - |
| 00:14.3 | Wi-Fi 6 AX201 | `[8086:a0f0]` | iwlwifi | iwlwifi |
| 00:15.0 | Serial IO I2C #0 | `[8086:a0e8]` | intel-lpss | intel_lpss_pci |
| 00:15.1 | Serial IO I2C #1 | `[8086:a0e9]` | intel-lpss | intel_lpss_pci |
| 00:16.0 | MEI Controller | `[8086:a0e0]` | mei_me | mei_me |
| 00:17.0 | SATA Controller | `[8086:a0d3]` | ahci | ahci |
| 00:1d.0 | PCIe Root Port #10 | `[8086:a0b1]` | pcieport | - |
| 00:1d.3 | PCIe Root Port #12 | `[8086:a0b3]` | pcieport | - |
| 00:1f.0 | LPC Controller | `[8086:a082]` | - | - |
| 00:1f.3 | Smart Sound Audio | `[8086:a0c8]` | snd_hda_intel | snd_hda_intel, snd_sof_pci_intel_tgl |
| 00:1f.4 | SMBus Controller | `[8086:a0a3]` | i801_smbus | i2c_i801 |
| 00:1f.5 | SPI Controller | `[8086:a0a4]` | intel-spi | spi_intel_pci |
| 01:00.0 | Samsung NVMe PM9A1/980PRO | `[144d:a80a]` | nvme | nvme |
| 58:00.0 | Intel I225-LM 2.5GbE #1 | `[8086:15f2]` | igc | igc |
| 59:00.0 | Intel I225-LM 2.5GbE #2 | `[8086:15f2]` | igc | igc |

## Networking

- **Wired**: Dual Intel I225-LM 2.5 Gigabit Ethernet (`igc` driver)
- **WiFi**: Intel Wi-Fi 6 AX201 CNVi (`iwlwifi` driver)
- **Bluetooth**: Intel AX201 (`btusb`/`btintel` drivers)

## Storage

- **NVMe**: Samsung 980 PRO (PM9A1) PCIe 4.0 (`nvme` driver)
- **SATA**: Tiger Lake-LP SATA Controller (`ahci` driver)

## Audio

- **Controller**: Tiger Lake-LP Smart Sound Technology `[8086:a0c8]`
- **Primary Driver**: `snd_hda_intel` (HDA audio)
- **SOF Driver**: `snd_sof_pci_intel_tgl` (Sound Open Firmware, Tiger Lake)

## Graphics

- **GPU**: Intel TigerLake-LP GT2 Iris Xe Graphics `[8086:9a49]`
- **Driver**: `i915` (also supports `xe`)
- **Features**: VAAPI hardware acceleration

## Thunderbolt / USB-C

- **Thunderbolt 4**: Dual ports via Tiger Lake-LP NHI
- **USB-C PD**: TPS6598x USB Power Delivery controller (`tps6598x` driver)

## I2C Buses

| Bus | Type | Adapter |
|-----|------|---------|
| i2c-0 | i2c | Synopsys DesignWare I2C |
| i2c-1 | i2c | Synopsys DesignWare I2C |
| i2c-2 | smbus | SMBus I801 at 00:1f.4 |
| i2c-3..11 | i2c | i915 gmbus (display) |
| i2c-12..15 | i2c | AUX USBC/DDI (DP aux) |

**SPD EEPROM**: ee1004 at i2c-2 (DDR4 memory SPD data)

## SPI Flash

- **Controller**: Tiger Lake-LP SPI `[8086:a0a4]`
- **Driver**: `spi_intel_pci` / `spi_intel`
- **Flash**: SPI NOR (`spi_nor` + `mtd` subsystem)

## Platform Drivers

| Module | Purpose |
|--------|---------|
| `igen6_edac` | Tiger Lake memory error detection |
| `intel_powerclamp` | CPU power clamping |
| `intel_pmc_core` | Platform Management Controller |
| `intel_rapl_msr` | Running Average Power Limit |
| `coretemp` | CPU temperature monitoring |
| `x86_pkg_temp_thermal` | Package thermal |
| `pinctrl_tigerlake` | Tiger Lake pin control |
| `acpi_tad` | ACPI Time and Alarm Device |
| `serial_multi_instantiate` | Serial bus multi-device |

## Firmware (loaded from /lib/firmware/)

| File Pattern | Purpose |
|--------------|---------|
| `i915/tgl_dmc*.bin` | Tiger Lake Display Microcontroller |
| `i915/tgl_guc_70.bin` | Tiger Lake GuC |
| `i915/tgl_huc.bin` | Tiger Lake HuC |
| `iwlwifi-QuZ-a0-hr-b0-*.ucode` | AX201 WiFi firmware |
| `intel/ibt-20-*` | AX201 Bluetooth firmware |

**Note**: Exact firmware filenames will be confirmed at first Gentoo boot via `dmesg | grep firmware`.

## Key Differences from XPS 9315

| Feature | NUC11 (Tiger Lake) | XPS 9315 (Alder Lake) |
|---------|-------------------|----------------------|
| CPU arch | `-march=tigerlake` | `-march=alderlake` |
| AVX-512 | Yes | No (fused off) |
| Hybrid cores | No (4C/8T uniform) | Yes (P+E cores) |
| Ethernet | Dual I225-LM 2.5GbE (`igc`) | None (WiFi only) |
| SATA | Yes (`ahci`) | No (NVMe only) |
| Camera/ISP | None | Intel IPU6 + OV01A10 |
| Sensor Hub | None | Intel ISH |
| USB-C PD | TPS6598x | Integrated |
| Audio | HDA + SOF TGL | SOF ADL (SoundWire) |
| SPI Flash | Yes (mtd/spi_nor) | No |
| EDAC | igen6_edac | Not used |
| Platform | Intel NUC | Dell XPS |
