# Dell OptiPlex 3090 SFF - Hardware Reference

**Current OS**: Windows (factory) → being replaced by Gentoo
**Harvested**: 2026-04-27 (Fedora 43 live USB via Ventoy)

## System Overview

| Field | Value |
|-------|-------|
| **Product** | Dell OptiPlex 3090 (SFF — chassis type 3) |
| **Board** | Dell 0CVN63 (rev A01) |
| **Chipset** | Intel Q470 (Comet Lake PCH-H) |
| **BIOS** | 2.28.0 (11/30/2025) |
| **CPU** | Intel Core i5-10505 @ 3.20GHz (Comet Lake) |
| **Cores** | 6C/12T (single socket, turbo 4.60GHz) |
| **RAM** | 16GB DDR4-2666 (1x16GB Samsung, single channel) |
| **Architecture** | x86_64 |
| **Form Factor** | Small Form Factor (SFF) |

## CPU Features

Key flags: `vmx avx avx2 aes fma f16c bmi1 bmi2 adx smap rdseed rdrand`

Notable: **No AVX-512** (Comet Lake, Skylake-derived). Full VT-x/VT-d. Hyperthreading enabled. **Family 6, Model 165 (0xA5), Stepping 5**.

`CPU_FLAGS_X86="aes avx avx2 f16c fma3 mmx mmxext pclmul popcnt rdrand sse sse2 sse3 sse4_1 sse4_2 ssse3"`

**GCC**: `-march=skylake` (no `-march=cometlake` in stable GCC; Skylake covers same ISA)

## PCI Devices

| BDF | Device | PCI ID | Driver |
|-----|--------|--------|--------|
| 00:00.0 | Comet Lake-S 6c Host Bridge | `[8086:9b53]` | skl_uncore |
| 00:01.0 | PCIe Controller (x16) | `[8086:1901]` | pcieport |
| 00:02.0 | UHD Graphics 630 (CometLake-S GT2) | `[8086:9bc8]` | i915 |
| 00:08.0 | Gaussian Mixture Model | `[8086:1911]` | - |
| 00:12.0 | PCH Thermal Controller | `[8086:06f9]` | intel_pch_thermal |
| 00:14.0 | USB 3.1 xHCI Host Controller | `[8086:06ed]` | xhci_hcd |
| 00:14.2 | PCH Shared SRAM | `[8086:06ef]` | - |
| 00:15.0 | Serial IO I2C Controller #0 | `[8086:06e8]` | intel-lpss |
| 00:16.0 | HECI (ME) Controller | `[8086:06e0]` | mei_me |
| 00:17.0 | PCH-H RAID/SATA Controller | `[8086:06d6]` | ahci |
| 00:1c.0 | PCIe Root Port | `[8086:06bc]` | pcieport |
| 00:1f.0 | Q470 Chipset LPC/eSPI Controller | `[8086:0687]` | - |
| 00:1f.3 | Comet Lake PCH cAVS (audio) | `[8086:06c8]` | snd_hda_intel |
| 00:1f.4 | PCH SMBus Controller | `[8086:06a3]` | i801_smbus |
| 00:1f.5 | PCH SPI Controller | `[8086:06a4]` | intel-spi |
| 01:00.0 | **NVIDIA RTX A1000 (GA107GL)** | `[10de:25b0]` | nouveau→nvidia |
| 01:00.1 | GA107 HDMI Audio | `[10de:2291]` | snd_hda_intel |
| 02:00.0 | Realtek RTL8111/8168/8211/8411 GbE | `[10ec:8168]` | r8169 |

## GPU Details (Hybrid)

| # | GPU | PCI ID | Driver | Notes |
|---|-----|--------|--------|-------|
| 1 | Intel UHD Graphics 630 | `[8086:9bc8]` | i915 | iGPU, KBL DMC firmware family |
| 2 | NVIDIA RTX A1000 | `[10de:25b0]` | nvidia (proprietary, kernel-open) | GA107 Ampere, 8GB GDDR6 |

**Driver**: `nvidia-drivers` (proprietary). Nouveau blacklisted at runtime.
**HDMI Audio**: GA107 HD Audio `[10de:2291]` via snd_hda_intel
**kernel-open**: GA107 is Ampere — supports kernel-open modules (Turing+).

### NVIDIA A1000 Capabilities

- **VRAM**: 8GB GDDR6
- **Compute Capability**: 8.6 (Ampere)
- **CUDA**: Latest CUDA toolkit fully supported
- **Workloads**: ML inference (8GB fits Llama-7B int8, larger models with offload), CAD, CUDA dev

## Storage

| Device | Type | Size | Filesystem | Notes |
|--------|------|------|-----------|-------|
| nvme0n1 | M.2 2230 NVMe | 256GB | — | Gentoo install target (after BIOS AHCI flip) |
| **sda** | **Ventoy USB** | **57.8GB** | **exfat+vfat** | **DO NOT TOUCH — boot media** |

**CRITICAL — Intel RST/RAID trap**: Out of the box, the Q470 SATA controller is in **RAID mode**. Linux installers cannot see the internal NVMe until BIOS is changed:

1. Reboot, F2 at Dell splash → BIOS
2. Storage → SATA Operation → change **"RAID On"** to **"AHCI"**
3. Save and reboot to live USB
4. `lsblk` should now show `/dev/nvme0n1`

Switching to AHCI will break any existing Windows boot on this disk unless prepped first (Safe Boot registry trick). Since plan is wipe-and-install Gentoo, this isn't a concern.

## Audio

| Component | Details |
|-----------|---------|
| **Chipset** | Comet Lake PCH cAVS `[8086:06c8]` |
| **Codec** | Realtek ALC3246 (Address 0) — analog out + headset jack |
| **NVIDIA HDMI** | GA107 HD Audio `[10de:2291]` (Address 0) |
| **Type** | SOF (Sound Open Firmware) + legacy HDA |
| **Driver** | snd_hda_intel + snd_sof_pci_intel_cnl + snd_soc_avs |

PipeWire + WirePlumber recommended (replaces PulseAudio).

## Networking

| Interface | Device | PCI ID | Driver | Speed |
|-----------|--------|--------|--------|-------|
| Ethernet | Realtek RTL8111/8168/8211/8411 | `[10ec:8168]` | r8169 | 1GbE |

**No WiFi** — Dell SFF, wired only. No internal M.2 WiFi card.
**No Bluetooth** — no internal BT module.

## USB

| Controller | Type | PCI ID | Driver |
|-----------|------|--------|--------|
| Comet Lake xHCI | USB 3.1 | `[8086:06ed]` | xhci_hcd |

Front: USB-A 3.x x2, USB-C 3.x. Rear: USB-A 3.x x2, USB-A 2.0 x2.

## Platform Drivers

| Module | Purpose |
|--------|---------|
| dell_smbios | Dell SMBIOS interface |
| dell_smm_hwmon | Dell SMM fan/thermal |
| dell_wmi | Dell WMI hotkeys/buttons |
| dell_wmi_sysman | Dell BIOS/firmware attributes |
| dcdbas | Dell Systems Management Base driver |
| dell_wmi_descriptor | Dell WMI descriptors |
| intel_pmc_core | PCH power management telemetry |
| pinctrl_cannonlake | Comet Lake pin controller |
| intel_uncore | Comet Lake uncore performance counters |
| intel_rapl_msr | Intel RAPL power monitoring |
| coretemp | CPU core temperature |
| x86_pkg_temp_thermal | Package thermal management |
| intel_powerclamp | Intel idle injection thermal management |
| mei_me / mei_hdcp / mei_pxp / mei_wdt | Intel ME interfaces (HDCP, PXP, watchdog) |
| iTCO_wdt | Intel TCO watchdog timer |
| i2c_i801 | Intel 801 SMBus |
| spi_intel_pci | Intel SPI / SPI-NOR (firmware flash) |
| kvm_intel | KVM virtualization |

## ECC Memory

Not supported — non-ECC consumer DDR4. (OptiPlex 3000-series is consumer tier; ECC is on Precision/PowerEdge.)

## Boot Configuration

| Setting | Value |
|---------|-------|
| Boot mode | EFI (64-bit) |
| Secure Boot | Disabled |
| Suspend | S3 deep + s2idle (active mode: deep) |
| Hibernate | platform, shutdown, reboot, suspend, test_resume |

## Power & Thermal

- **CPU governor**: `intel_pstate` (active), default `powersave` — switch to `performance` for desktop workloads
- **Frequency range**: 800 MHz – 4600 MHz (turbo)
- **Turbo**: enabled
- **Chassis**: type 3 (desktop/SFF) — no battery
- **Fan**: dell_smm_hwmon, no mbpfan equivalent needed (Dell BIOS handles fans)

## Performance Notes

- SFF form factor: thermals are tighter than tower; sustained turbo may downclock under heavy load
- Single-channel RAM is the biggest perf bottleneck — adding a 2nd 16GB DIMM doubles memory bandwidth
- 16GB is workable but tight for chromium/llvm/rust builds → use disk fallback via `package.env`
- 256GB NVMe leaves ~200GB usable after EFI/boot/portage — fine for desktop, may be tight if heavy ML datasets stored locally
- NVIDIA A1000 8GB makes this a credible workstation for inference / light training

## Firmware Requirements

| Firmware | Package | Notes |
|----------|---------|-------|
| i915/kbl_dmc_*.bin | sys-kernel/linux-firmware | Comet Lake i915 DMC (KBL family) |
| nvidia/ga107/* | sys-kernel/linux-firmware | RTX A1000 GA107 firmware |
| intel-microcode | sys-firmware/intel-microcode | Comet Lake-S microcode (sig 0x000a0655) |

**No WiFi firmware needed** — wired only.

## Install Sequence (TL;DR)

1. **BIOS**: Disable Secure Boot (already off). Change SATA Operation to AHCI.
2. **Boot**: Ventoy USB → Gentoo or Fedora live.
3. **Harvest** (already done): `sudo tools/harvest.sh` (re-run after AHCI flip if needed).
4. **Partition**: `sudo bash machines/optiplex-3090/gentoo_install_part1.sh`
5. **Stage3 + chroot prep**: `sudo bash machines/optiplex-3090/gentoo_install_part2.sh`
6. **Inside chroot**: `bash /root/gentoo_install_part3_chroot.sh`
7. **Reboot**, run `sudo tools/verify-install.sh`.
