# Surface Pro 6 - Hardware Harvest Summary
# Collected: 2026-02-27 from Fedora 43 Live USB (Ventoy)
# Kernel: 6.17.1-300.fc43.x86_64 (stock Fedora, NOT linux-surface)

## System Identity
- **Product**: Microsoft Surface Pro 6
- **Board**: Surface Pro 6
- **BIOS**: 239.779.768 (dated 08/11/2015 in DMI, likely placeholder)
- **SAM firmware**: 241.304.139 (Surface Aggregator Module)

## CPU - Intel Core i5-8250U (Kaby Lake-R, 8th Gen)
- **Architecture**: x86_64, 4 cores / 8 threads
- **Base clock**: 1.60 GHz, turbo ~3.40 GHz
- **Observed MHz**: ~2600 (live)
- **Microarch**: Kaby Lake (no P/E core split, uniform cores)
- **Gentoo march**: `-march=skylake` (Kaby Lake = Skylake ISA; see gotcha #19)
- **MAKEOPTS**: `-j9 -l8`
- **CPU_FLAGS_X86**: `aes avx avx2 f16c fma3 mmx mmxext pclmul popcnt rdrand sse sse2 sse3 sse4_1 sse4_2 ssse3`
- **Notable**: NO AVX-512 (consumer Kaby Lake), has VMX (KVM capable)
- **NR_CPUS**: 8
- **Intel generation context**: 8th gen, between MBP 2015 (5th gen Broadwell) and XPS 9510/NUC11 (11th gen Tiger Lake) / XPS 9315 (12th gen Alder Lake)

## GPU - Intel UHD Graphics 620 [8086:5917]
- **Driver**: i915 (Kaby Lake GT2)
- **DMC firmware**: i915/kbl_dmc_ver1_04.bin (v1.4)
- **Display**: 2736x1824 PixelSense (267 PPI, 3:2 aspect)
- **Backlight**: intel_backlight (raw type), max_brightness=7500
- **i915 notes**: Same driver family as all our machines (Broadwell->Alder Lake), well understood
- **GuC/HuC**: Available but not loaded by default on Kaby Lake

## Memory
- **Total**: 8 GB LPDDR3 @ 1867 MT/s
- **Layout**: 4x slots reported by DMI, but soldered (not upgradeable)
- **Manufacturer**: SK Hynix
- **ECC**: None
- **Portage tmpfs**: Use 4G-6G max (half of 8GB), push large builds to disk

## Storage - SK hynix BC501 NVMe [1c5c:1327]
- **Size**: 238.5 GB
- **Interface**: NVMe (PCIe)
- **Driver**: nvme
- **Current partitions** (Windows/Fedora):
  - nvme0n1p1: 600MB vfat (EFI)
  - nvme0n1p2: 2GB ext4
  - nvme0n1p3: 235.9GB btrfs
- **Gentoo plan**: Wipe and repartition (EFI + boot + root, no swap, zram only)

## WiFi - Marvell 88W8897 AVASTAR [11ab:2b38]
- **Driver**: mwifiex_pcie (mainline)
- **Standard**: 802.11ac
- **Firmware**: `mrvl/pcie8897_uapsta.bin` (ships with linux-firmware)
- **Interface**: wlp1s0
- **FW version**: mwifiex 1.0 (15.68.19.p21)
- **NOTE**: NOT Intel WiFi, NOT Broadcom - Marvell/NXP, fully mainline, no firmware pain

## Bluetooth - Marvell [1286:204c]
- **Driver**: btusb (via USB bus)
- **Interface**: USB 1-5 (480M)
- **Firmware**: `mrvl/usb8897_uapsta.bin` (ships with linux-firmware)
- **Working**: rfcomm, bnep loaded

## Audio - Intel Sunrise Point-LP HD Audio [8086:9d71]
- **Driver**: snd_hda_intel
- **Codec**: Realtek ALC298, subsystem ID 0x10ec10cc (module snd_hda_codec_alc269 handles ALC298)
- **HDMI codec**: Intel Kabylake HDMI [8086:280b], subsystem 0x80860101
- **SOF**: snd_sof_pci_intel_skl also loaded (alternative driver path, not needed)
- **Gentoo plan**: snd_hda_intel as primary, PipeWire + WirePlumber userspace
- **NOTE**: May need `options snd-hda-intel model=...` if audio quirky — check after install

## Cameras - IPU3 Pipeline
- **CSI-2 Host**: ipu3-cio2 [8086:9d32]
- **Image Processing**: ipu3-imgu [8086:1919]
- **Sensors**:
  - ov5693 (rear camera, 5MP)
  - ov8865 (front camera, 8MP)
  - ov7251 (IR camera, for Windows Hello)
  - dw9719 (VCM autofocus motor)
- **PMIC**: TPS68470 (intel_skl_int3472_tps68470)
- **Firmware**: ipu3-imgu loads irci_ecr-master firmware
- **Bridge**: ipu_bridge module
- **NOTE**: IPU3 cameras need special userspace (libcamera), not v4l2 direct

## Touchscreen - NOT WORKING (hardware issue on this unit)
- **Status**: Touchscreen does not work on this specific Surface Pro 6 unit
- **Decision**: Treat as a normal laptop — no IPTS/iptsd config needed
- **MEI iTouch**: [8086:9d3e] detected at 00:16.4 (hardware is present but non-functional)
- **NOTE**: Surface Pro 9 has working touchscreen + pen — save IPTS work for that machine

## Type Cover - Microsoft Surface Type Cover [045e:09c0]
- **Connection**: USB HID (port 7, 12M)
- **Driver**: hid-multitouch (0003:045E:09C0)
- **Inputs detected**:
  - Keyboard
  - Mouse
  - Touchpad (event4, mouse1)
- **Status**: WORKING on stock kernel

## Surface-Specific Modules (mainline, loaded)
- surface_aggregator (SAM bus driver)
- surface_aggregator_registry
- surface_acpi_notify
- surface_platform_profile (performance profiles)
- surface_gpe (GPE events)
- surfacepro3_button (volume/power buttons)
- **NOT loaded** (needs linux-surface): surface_hid, surface_dtx, iptsd

## Intel Sensor Hub (ISH)
- **Device**: [8086:9d35] Sunrise Point-LP ISH
- **Driver**: intel_ish_ipc + intel_ishtp + intel_ishtp_hid
- **HID Sensors via ISH**:
  - hid_sensor_accel_3d (accelerometer)
  - hid_sensor_gyro_3d (gyroscope)
  - hid_sensor_als (ambient light sensor)
  - hid_sensor_rotation (screen rotation)
- **Uses**: industrialio (IIO) subsystem

## Thermal Management
- **Thermal zones**: GEN1, INT3400, GEN2, GEN5, GEN7, pch_skylake, B0D4, x86_pkg_temp
- **Drivers**: processor_thermal_device_pci_legacy, int3400_thermal, int3403_thermal, intel_pch_thermal
- **DPTF**: Full Intel DPTF stack (platform_temperature_control, processor_thermal_rfim, etc.)
- **Fan**: Controlled by SAM (surface_aggregator), no direct fan sysfs
- **Gentoo plan**: thermald for userspace thermal management

## Intel Management Engine
- **CSME HECI #1**: [8086:9d3a] - mei_me driver
- **iTouch Controller**: [8086:9d3e] - mei_me driver (used for IPTS touchscreen)
- **Subsystems**: mei_hdcp, mei_pxp

## Power / Suspend
- **Battery**: BAT1, Li-ion, 45Wh design, 37.75Wh full (84% health), 160 cycles
- **AC adapter**: ADP1 (Surface Connect charger)
- **Suspend modes**: freeze (s2idle), mem, disk
- **Default mem_sleep**: s2idle (modern standby, no S3)
- **NOTE**: S3 deep sleep not available - s2idle only

## I2C Buses
- i2c-0..3: Synopsys DesignWare I2C adapters (Serial IO)
- i2c-4..6: i915 gmbus (dpc, dpb, dpd)
- i2c-7..9: i915 AUX (DDI A/B/C)
- i2c-INT33BE:00: Camera PMIC
- i2c-INT347A:00 + VCM: OV5693 camera + dw9719 autofocus
- i2c-INT347E:00: OV8865 camera
- i2c-MSHW0125:00: Surface-specific device (touchscreen digitizer?)

## EFI / Boot
- **Mode**: UEFI
- **Secure Boot**: Will need to disable or sign kernel

## Key Differences from Our Other Machines

| Feature | Surface Pro 6 | MBP 2015 | XPS 9315 | XPS 9510 |
|---------|--------------|----------|----------|----------|
| CPU gen | 8th (Kaby Lake-R) | 5th (Broadwell) | 12th (Alder Lake) | 11th (Tiger Lake-H) |
| march | skylake | broadwell | alderlake | tigerlake |
| GPU | UHD 620 | Iris 6100 | Iris Xe | UHD + RTX 3050 Ti |
| WiFi | Marvell mwifiex | Broadcom brcmfmac | Intel iwlwifi | Intel iwlwifi |
| Audio codec | Realtek ALC298 | Cirrus CS4208 | SOF (sof-audio) | HDA Intel |
| Storage | NVMe | SATA (AHCI) | NVMe | NVMe |
| Touch | IPTS (needs patches) | N/A | N/A | N/A |
| Sensors | ISH (accel/gyro/ALS/rotation) | applesmc | ISH | N/A |
| Fan control | SAM | applesmc/mbpfan | DPTF | DPTF/thermald |
| Suspend | s2idle only | S3 deep | s2idle | s2idle |
| Special | linux-surface patches | Apple quirks | Dell WMI | NVIDIA hybrid |

## What linux-surface Patches Add
1. **IPTS touchscreen + pen** (the big one - touchscreen doesn't work without it)
2. **Surface HID** (improved Type Cover support, esp. detach/reattach)
3. **Surface DTX** (clipboard detach on Surface Book, N/A for Pro 6)
4. **Battery/performance profile** improvements
5. **Suspend/resume** reliability fixes

## Gentoo Kernel Strategy
- Use `sys-kernel/gentoo-sources` as base
- Apply linux-surface patches from github.com/linux-surface/linux-surface
- Key configs: SURFACE_AGGREGATOR=m, SURFACE_AGGREGATOR_BUS=y, SURFACE_AGGREGATOR_REGISTRY=m, HID sensors, IPU3, mwifiex
- All firmware from /lib/firmware/ (no embedded firmware needed since drivers will be modules)
- i915 as module (consistent with XPS 9510 pattern)

## Files Saved to This Directory
- hardware_inventory.log - harvest.sh output
- deep_harvest.log - deep_harvest.sh output
- dmesg_full.log - complete dmesg
- i915_dmesg.log - GPU-specific dmesg
- surface_dmesg.log - Surface/SAM/mwifiex/camera dmesg
- input_devices.log - /proc/bus/input/devices
- lspci_verbose.log - lspci -nnkvv
- lsusb_verbose.log - lsusb -v
- dmidecode_full.log - full SMBIOS/DMI dump
- lsmod.log - all loaded modules
- gentoo_install_part1_REFERENCE.sh - MBP install script (adapt for NVMe)
- gentoo_install_part2_REFERENCE.sh - MBP chroot setup (adapt paths)
- package.env - large package -> disk build (reuse as-is)
- portage_env_notmpfs.conf - portage disk fallback (reuse as-is)
