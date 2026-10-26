# Kernel Config Cross-Reference: Key Decisions for Dell XPS 15 9510

## Base Config Decision
Start from defconfig and apply kernel_config.sh (26-phase programmatic config).
Alternatively, start from MBP 2015 or Surface Pro 6 .config as a base.

## Must Be Built-In (=y) — No Initramfs
- CONFIG_BLK_DEV_NVME=y (boot drive — dual Samsung 990 PRO)
- CONFIG_NVME_CORE=y
- CONFIG_EXT4_FS=y (root filesystem)
- CONFIG_VFAT_FS=y (EFI partition)
- CONFIG_NLS_CODEPAGE_437=y (VFAT dep)
- CONFIG_NLS_ISO8859_1=y (VFAT dep)
- CONFIG_EFI=y, CONFIG_EFI_STUB=y
- CONFIG_ZRAM=y (swap, no initramfs to load module)
- CONFIG_INTEL_IDLE=y

## Must Be Module (=m) — Firmware from /lib/firmware/
- CONFIG_DRM_I915=m (needs i915/tgl_dmc_ver2_12.bin, tgl_guc_70.1.1.bin)
- CONFIG_IWLWIFI=m, CONFIG_IWLMVM=m (needs iwlwifi-QuZ-a0-hr-b0-77.ucode)
- CONFIG_SND_HDA_INTEL=m
- CONFIG_BT_HCIBTUSB=m (needs intel/ibt-20-*.sfi + .ddc)

## NVIDIA Dependency Chain (CRITICAL)
nvidia-drivers builds out-of-tree. Since kernel 6.11+, it needs DRM_TTM_HELPER
which is pulled in by enabling DRM_QXL=m. This is the "QXL trick".

```
DRM_QXL=m  →  selects DRM_TTM=y  →  provides DRM_TTM_HELPER
                                      └→ nvidia-drivers links against this
```

- CONFIG_DRM_QXL=m (pulls in TTM helper)
- CONFIG_DRM_NOUVEAU=n (conflicts with proprietary nvidia)
- CONFIG_DRM_KMS_HELPER=y

## NVIDIA Runtime Power Management
Boot params in /etc/default/grub:
```
i915.enable_guc=3                          # Intel GuC + HuC
nvidia.NVreg_DynamicPowerManagement=0x02   # Runtime PM (Optimus)
```

Modprobe config /etc/modprobe.d/nvidia.conf:
```
options nvidia-drm modeset=1
options nvidia NVreg_DynamicPowerManagement=0x02
```

## Performance Tuning
- CONFIG_NR_CPUS=16 (8C/16T Tiger Lake-H)
- CONFIG_PREEMPT=y + CONFIG_PREEMPT_DYNAMIC=y (upgrade from PREEMPT_VOLUNTARY)
- CONFIG_HZ_1000=y (low-latency desktop)
- CONFIG_NO_HZ_IDLE=y
- CONFIG_TRANSPARENT_HUGEPAGE=y + ALWAYS=y (critical for ML workloads)
- CONFIG_LRU_GEN=y + ENABLED=y (MGLRU)
- CONFIG_KSM=y (dedup ML model memory)
- CONFIG_SCHED_AUTOGROUP=y
- CONFIG_ZRAM_BACKEND_ZSTD=y + CONFIG_CRYPTO_ZSTD=y
- CONFIG_ZRAM_DEF_COMP="zstd"

## Audio (HDA, NOT SOF)
- CONFIG_SND_HDA_INTEL=m
- CONFIG_SND_HDA_CODEC_REALTEK=m
- CONFIG_SND_HDA_CODEC_HDMI=m
- CONFIG_SND_HDA_I915=y (HDMI audio link)
- CONFIG_SND_SOC_SOF_TOPLEVEL=n (Tiger Lake-H uses HDA natively)

## WiFi (Intel, NOT Marvell)
- CONFIG_IWLWIFI=m
- CONFIG_IWLMVM=m
- CONFIG_CFG80211=m + WEXT=y
- CONFIG_MAC80211=m

## Thunderbolt 4
- CONFIG_THUNDERBOLT=m
- CONFIG_INTEL_WMI_THUNDERBOLT=m
- Dual USB-C ports with DisplayPort Alt Mode

## USB-C Hub (Anker 7-in-1 tested)
- CONFIG_USB_RTL8152=m (RTL8153 USB Ethernet)
- CONFIG_USB_NET_AX88179_178A=m (ASIX USB Ethernet)
- CONFIG_USB_NET_CDCETHER=m (generic USB Ethernet)

## Dell Platform
- CONFIG_DELL_LAPTOP=m
- CONFIG_DELL_WMI=m
- CONFIG_DELL_SMBIOS=m + WMI + SMM

## VPN (SSTP)
- CONFIG_PPP=y + BSDCOMP=y + DEFLATE=y + MPPE=y + ASYNC=y + FILTER=y
- CONFIG_TUN=m

## Firmware Loading
- CONFIG_EXTRA_FIRMWARE="" (empty — all from /lib/firmware/)
- CONFIG_FW_LOADER=y
- CONFIG_FW_LOADER_USER_HELPER=y

## Firmware Files Required
| File | Purpose |
|------|---------|
| i915/tgl_dmc_ver2_12.bin | Tiger Lake Display Microcontroller |
| i915/tgl_guc_70.1.1.bin | Tiger Lake GuC |
| iwlwifi-QuZ-a0-hr-b0-77.ucode | Intel AX203 WiFi |
| intel/ibt-20-*.sfi + .ddc | Intel Bluetooth |

## Microcode
- CPU: Family 6, Model 141, Stepping 1
- Signature: 0x000806d1
- make.conf: MICROCODE_SIGNATURES="-s 0x000806d1"
