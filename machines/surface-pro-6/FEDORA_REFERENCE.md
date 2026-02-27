# Surface Pro 6 — Data Mined from Installed Fedora 43 + linux-surface
# Extracted: 2026-02-27 before Gentoo install

## Fedora linux-surface Kernel
- **Version**: 6.18.8-1.surface.fc43.x86_64
- **Packages**: kernel-surface, kernel-surface-core, kernel-surface-modules, kernel-surface-modules-core
- **Config**: Saved as fedora_surface_kernel_6.18.8.config (12,172 lines)
- **Preempt**: PREEMPT_DYNAMIC, PREEMPT_LAZY, HZ=1000, NO_HZ_FULL
- **NR_CPUS**: 8192 (Fedora distro default, we'll use 8 for Gentoo)
- **Initramfs**: BLK_DEV_INITRD=y, EXTRA_FIRMWARE="" (all from /lib/firmware/)

## Critical Kernel Config Values for Surface Pro 6

### Surface Platform Modules
```
CONFIG_SURFACE_PLATFORMS=y
CONFIG_SURFACE_AGGREGATOR=m
CONFIG_SURFACE_AGGREGATOR_BUS=y
CONFIG_SURFACE_AGGREGATOR_REGISTRY=m
CONFIG_SURFACE_AGGREGATOR_CDEV=m
CONFIG_SURFACE_AGGREGATOR_HUB=m
CONFIG_SURFACE_AGGREGATOR_TABLET_SWITCH=m
CONFIG_SURFACE_ACPI_NOTIFY=m
CONFIG_SURFACE_DTX=m
CONFIG_SURFACE_GPE=m
CONFIG_SURFACE_HID_CORE=m
CONFIG_SURFACE_HID=m
CONFIG_SURFACE_HOTPLUG=m
CONFIG_SURFACE_KBD=m
CONFIG_SURFACE_PLATFORM_PROFILE=m
CONFIG_SURFACE_PRO3_BUTTON=m
CONFIG_SURFACE_BOOK1_DGPU_SWITCH=m  (not needed for Pro 6, but harmless)
CONFIG_SURFACE3_WMI=m
CONFIG_SURFACE_3_POWER_OPREGION=m
```

### IPTS Touchscreen (linux-surface patch)
```
CONFIG_HID_IPTS=m
```
- **iptsd version**: 3.1.0-1.fc43
- **Device config**: /usr/share/iptsd/surface-pro-6.conf
  - Vendor=0x045E, Product=0x001F
  - InvertX=true, InvertY=true
  - Width=25.98cm, Height=17.32cm
- **udev**: 50-iptsd.rules (systemd auto-start on hidraw device add)
- **NOTE**: Touchscreen not working on this specific unit despite driver loaded
  - linux-surface wiki says SP6 touchscreen should work (✓¹)
  - Suspect hardware issue (ribbon cable, digitizer, or MEI)

### WiFi (Marvell mwifiex)
```
CONFIG_MWIFIEX=m
CONFIG_MWIFIEX_PCIE=m
CONFIG_MWIFIEX_SDIO=m  (not needed, but harmless)
CONFIG_MWIFIEX_USB=m   (not needed, but harmless)
```

### Bluetooth
```
CONFIG_BT_HCIBTUSB=m
CONFIG_BT_HCIBTUSB_AUTOSUSPEND=y
CONFIG_BT_HCIBTUSB_BCM=y   (not needed for Marvell, but part of btusb)
CONFIG_BT_HCIBTUSB_MTK=y
CONFIG_BT_HCIBTUSB_POLL_SYNC=y
CONFIG_BT_HCIBTUSB_RTL=y
```

### i915 GPU
```
CONFIG_DRM_I915=m
CONFIG_DRM_I915_CAPTURE_ERROR=y
CONFIG_DRM_I915_COMPRESS_ERROR=y
CONFIG_DRM_I915_DP_TUNNEL=y
CONFIG_DRM_I915_GVT=y         (can disable for Gentoo, not needed)
CONFIG_DRM_I915_GVT_KVMGT=m   (can disable)
CONFIG_DRM_I915_PXP=y
CONFIG_DRM_I915_USERPTR=y
CONFIG_SND_HDA_I915=y
```

### Audio (HDA Intel + ALC298)
```
CONFIG_SND_HDA_INTEL=m
CONFIG_SND_HDA_CODEC_REALTEK=m    (handles ALC298)
CONFIG_SND_HDA_CODEC_HDMI=m
CONFIG_SND_HDA_CODEC_HDMI_INTEL=m
CONFIG_SND_HDA_GENERIC=m
CONFIG_SND_HDA_PATCH_LOADER=y     (allows firmware-based pin patching)
CONFIG_SND_HDA_RECONFIG=y
CONFIG_SND_HDA_HWDEP=y
CONFIG_SND_HDA_POWER_SAVE_DEFAULT=1
CONFIG_SND_HDA_INPUT_BEEP=y
CONFIG_SND_HDA_INPUT_BEEP_MODE=0
```
- **Codec**: Realtek ALC298 (Vendor 0x10ec0298, Subsystem 0x10ec10cc)
- **HDMI**: Intel Kabylake (Vendor 0x8086280b, Subsystem 0x80860101)
- **Audio outputs**: Speaker (0x14), Headphone (0x21), HDMI x3
- **Audio inputs**: Internal Mic (0x12), External Mic (0x18)
- **No model quirk needed** — autoconfig worked in Fedora (no modprobe.d override)

### HID Sensors (via ISH)
```
CONFIG_INTEL_ISH_HID=m
CONFIG_INTEL_ISH_FIRMWARE_DOWNLOADER=m
CONFIG_HID_SENSOR_HUB=m
CONFIG_HID_SENSOR_ACCEL_3D=m
CONFIG_HID_SENSOR_GYRO_3D=m
CONFIG_HID_SENSOR_ALS=m
CONFIG_HID_SENSOR_DEVICE_ROTATION=m
CONFIG_HID_SENSOR_MAGNETOMETER_3D=m
CONFIG_HID_SENSOR_INCLINOMETER_3D=m
CONFIG_HID_SENSOR_HUMIDITY=m
CONFIG_HID_SENSOR_TEMP=m
CONFIG_HID_SENSOR_IIO_COMMON=m
CONFIG_HID_SENSOR_IIO_TRIGGER=m
CONFIG_HID_SENSOR_CUSTOM_INTEL_HINGE=m
```

### Camera (IPU3 + sensors)
```
CONFIG_STAGING=y
CONFIG_STAGING_MEDIA=y
CONFIG_IPU_BRIDGE=m
CONFIG_INTEL_SKL_INT3472=m
CONFIG_VIDEO_OV5693=m   (rear 5MP)
CONFIG_VIDEO_OV8865=m   (front 8MP)
CONFIG_VIDEO_OV7251=m   (IR camera)
CONFIG_VIDEO_DW9719=m   (VCM autofocus)
```
- **Status**: linux-surface wiki says cameras are ❌ (Work in Progress)
- IPU3 is in staging — `ipu3_imgu: module is from the staging directory`

### I2C / Serial IO
```
CONFIG_MFD_INTEL_LPSS=y
CONFIG_MFD_INTEL_LPSS_ACPI=y
CONFIG_MFD_INTEL_LPSS_PCI=y
CONFIG_I2C_DESIGNWARE_CORE=y
CONFIG_I2C_DESIGNWARE_PLATFORM=y
CONFIG_I2C_DESIGNWARE_PCI=y
CONFIG_I2C_DESIGNWARE_BAYTRAIL=y
CONFIG_I2C_DESIGNWARE_SLAVE=y
CONFIG_INPUT_SOC_BUTTON_ARRAY=m
```

### Power Management
```
CONFIG_INTEL_IDLE=y
# C-states confirmed working: POLL, C1, C1E, C3, C6, C7s, C8, C9, C10
# cpufreq: intel_pstate, powersave governor
# CPU range: 400 MHz - 3400 MHz
```

## Hardware Data Confirmed

### CPU Microcode
- **Family**: 6, **Model**: 142, **Stepping**: 10
- **Signature**: 0x000806ea (family 6, model 0x8e=142, stepping 0xa=10)
- **Current microcode revision**: 0xf6
- **make.conf**: `MICROCODE_SIGNATURES="-s 0x000806ea"`

### NVMe Health
- **Model**: Skhynix BC501 NVMe 256GB
- **Firmware**: 80000C00
- **TRIM**: Supported (discard_granularity=512, discard_max=2TB)
- **Block size**: 512/512 (logical/physical)
- **Health**: 24% used, 100% spare, 891 power-on hours, 707 power cycles
- **SMART**: No critical warnings

### Thermal (current readings, idle)
- PCH (Sunrise Point): 34°C
- Core 0: 41°C, Core 1: 40°C, Core 2: 38°C
- **hwmon devices**: ADP1 (AC), nvme, BAT1, pch_skylake, coretemp

### Suspend
- **Modes**: freeze (s2idle), mem, disk
- **Default**: s2idle (Modern Standby, no S3)

### Secure Boot
- **Status**: ENABLED (must disable in Surface UEFI for unsigned Gentoo kernel)
- **EFI**: 64-bit
- **Surface UEFI access**: Hold Volume Up + Power

### EFI Boot Entries
- Boot0005: Fedora (shimx64.efi — Secure Boot signed)
- Boot0001: Internal Storage
- Boot0002: USB Storage
- Boot0003: PXE Network
- Boot0000: MsTemp (current Ventoy USB)

### GRUB (Fedora)
- **Boot params**: `rhgb quiet` (nothing Surface-specific needed!)
- No special i915 params, no acpi_osi override, no libata.force

### Modprobe
- **No Surface-specific modprobe.d overrides** in Fedora install
- No audio model quirk needed (ALC298 autoconfig works)

### dmesg Errors (benign)
- `surface_serial_hub: rx: parser: invalid payload CRC` — SAM communication noise, benign
- `dw-apb-uart: failed to request DMA` — UART DMA fallback, benign
- `ipu3_imgu: module is from the staging directory` — expected staging warning

## ACPI Devices (Surface-specific)
```
MSHW0005  MSHW0006  MSHW0008  MSHW0036  MSHW0040
MSHW0045  MSHW0048  MSHW0084  MSHW0091  MSHW0102
MSHW0111  MSHW0125  MSHW0131
```
- MSHW0125: Status 15 (present+functional), likely touchscreen digitizer

## linux-surface Feature Support (from wiki)
| Feature | Status | Notes |
|---------|--------|-------|
| Touchscreen | ✓¹ | Needs linux-surface kernel (HID_IPTS) |
| Pen/Stylus | ✓¹ | Needs linux-surface kernel |
| WiFi | ✓ | Mainline mwifiex_pcie |
| Bluetooth | ✓¹⁵ | BLE power-saving limitations |
| Speakers | ✓ | ALC298, no quirk needed |
| Cameras | ❌ | Work in Progress (IPU3 staging) |
| Buttons | ✓ | surfacepro3_button |
| Battery | ✓⁸ | BAT1 via ACPI |
| Suspend | ✓ | s2idle |
| Performance | ✓⁹ | surface_platform_profile |
| Keyboard | ✓ | USB HID Type Cover |
| Touchpad | ✓ | USB HID Type Cover |

## Files Saved from Fedora Install
- fedora_surface_kernel_6.18.8.config — complete kernel .config (12,172 lines)
- iptsd.conf — touchscreen daemon config
- iptsd-surface-pro-6.conf — device-specific touchscreen params
- 50-iptsd.rules — udev rules for iptsd auto-start
