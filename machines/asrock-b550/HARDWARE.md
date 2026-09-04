# ASRock B550 Phantom Gaming-ITX/ax — Hardware Reference

Harvested 2026-04-05 from Fedora 43 live USB.

## System Overview

| Component | Detail |
|-----------|--------|
| Board | ASRock B550 Phantom Gaming-ITX/ax (mini-ITX) |
| BIOS | P3.90 (2025-10-01), AMI |
| CPU | AMD Ryzen 9 5950X 16C/32T (Zen 3 / Vermeer) |
| Socket | AM4 |
| Max Boost | 5.05 GHz |
| RAM | 64GB DDR4-3200 (2x32GB Corsair CMK64GX4M2E3200C16, dual-rank) |
| ECC | None |
| GPU | NVIDIA GeForce RTX 5060 Ti OC (GB206, Blackwell) 16GB GDDR7 |
| NVMe | MAXIO MAP1202 2TB (DRAM-less, PCIe 4.0) |
| SATA SSD | 1TB (unused, Windows/NTFS) |
| WiFi | Intel Wi-Fi 6 AX200 (iwlwifi) |
| Bluetooth | Intel (btusb/btintel, via AX200 module) |
| Ethernet | Intel I225-V 2.5GbE (igc) |
| Audio | Realtek ALC1220 (HDA) + NVIDIA GB206 HDMI Audio |
| USB | AMD B550 xHCI (10p) + Matisse USB 3.0 (4p) |
| Chassis | Desktop (type 3) |
| Boot | UEFI 64-bit, Secure Boot disabled |
| Suspend | S3 deep sleep (supported) |

## CPU Features

- Architecture: x86_64, Zen 3 (Family 25, Model 33)
- Threads: 32 (16C/32T, SMT)
- Freq range: 582 MHz — 5086 MHz
- Governor: amd-pstate-epp
- NUMA: 1 node
- Virtualization: AMD-V (SVM)
- ISA: AVX2, FMA, SHA, AES-NI, PCLMUL, SSE4a, VPCLMULQDQ
- No AVX-512
- `-march=znver3` (GCC 11+)

### CPU_FLAGS_X86
```
aes avx avx2 f16c fma3 mmx mmxext pclmul popcnt rdrand sha sse sse2 sse3 sse4_1 sse4_2 sse4a ssse3 vpclmulqdq
```

## PCI Device Map

| BDF | Device | Driver |
|-----|--------|--------|
| 00:14.0 | AMD FCH SMBus Controller | piix4_smbus |
| 01:00.0 | MAXIO NVMe MAP1202 2TB | nvme |
| 02:00.0 | AMD B550 USB 3.1 xHCI | xhci_hcd |
| 02:00.1 | AMD B550 SATA Controller | ahci |
| 04:00.0 | Intel I225-V 2.5GbE | igc |
| 05:00.0 | Intel Wi-Fi 6 AX200 | iwlwifi |
| 06:00.0 | NVIDIA RTX 5060 Ti (GB206) | nouveau → nvidia |
| 06:00.1 | NVIDIA GB206 HDMI Audio | snd_hda_intel |
| 08:00.1 | AMD CCP (PSP) | ccp |
| 08:00.3 | AMD Matisse USB 3.0 | xhci_hcd |
| 08:00.4 | AMD Matisse HD Audio | snd_hda_intel |

## GPU Details

- **NVIDIA GeForce RTX 5060 Ti OC 16GB GDDR7**
  - Architecture: Blackwell (GB206)
  - VRAM: 16GB GDDR7
  - TDP: 180W
  - Driver: nvidia-drivers 595.58.03 (current branch)
  - CUDA: 13.2
  - kernel-open modules REQUIRED (Blackwell does not support closed-source modules)
  - Firmware: nvidia/gb206/* (from linux-firmware)
  - No Intel iGPU — AMD CPU, discrete NVIDIA only
  - **Upgraded from**: RTX 3060 Ti LHR (GA104, Ampere, 8GB) — 2026-07-24

## Storage

| Device | Type | Size | Controller | Notes |
|--------|------|------|-----------|-------|
| nvme0n1 | NVMe PCIe 4.0 | 1.9TB | MAXIO MAP1202 (DRAM-less) | Gentoo root |
| sda | SATA SSD | 931.5GB | AMD B550 AHCI | Unused (Windows/NTFS) |

## Audio

- **Onboard**: Realtek ALC1220 via AMD Matisse HD Audio Controller (08:00.4)
  - Driver: snd_hda_intel + snd_hda_codec_realtek (alc882 variant)
  - Type: HDA (legacy HD Audio, no SOF needed)
- **GPU**: NVIDIA GB206 HDMI Audio (06:00.1)
  - Driver: snd_hda_intel + snd_hda_codec_hdmi

## Networking

- **Ethernet**: Intel I225-V 2.5GbE (igc driver)
  - PCI ID: 8086:15f3
- **WiFi**: Intel Wi-Fi 6 AX200 (iwlwifi/iwlmvm)
  - PCI ID: 8086:2723
  - Firmware: iwlwifi-cc-a0-*.ucode
- **Bluetooth**: Intel (btusb + btintel)
  - Firmware: intel/ibt-0040-0041.*

## USB Peripherals (at harvest time)

- Logitech wireless receiver (HID++, hid_logitech_hidpp + hid_logitech_dj)
- USB mass storage (live USB)
- Intel BT adapter

## Platform / Chipset

- AMD B550 (500-series) — Starship/Matisse root complex
- SMBus: piix4_smbus (i2c_piix4)
- Watchdog: sp5100_tco
- Crypto: AMD CCP/PSP (ccp driver)
- GPIO: gpio_amdpt
- I2C buses: 6 total (3x DP, 2x piix4 SMBus ports, 1x piix4 port)
- SPD EEPROMs: ee1004 (DDR4) at 3-0050, 3-0051

## Firmware Requirements

| Component | Firmware Path | Source |
|-----------|--------------|--------|
| WiFi | iwlwifi-cc-a0-*.ucode | linux-firmware |
| Bluetooth | intel/ibt-0040-0041.{sfi,ddc}.xz | linux-firmware |
| NVIDIA | nvidia/gb206/* | linux-firmware |
| AMD ucode | amd-ucode/microcode_amd_fam19h.bin | linux-firmware |

## Performance Notes

- 46GB portage tmpfs (most builds in RAM, disk fallback for chromium/llvm/rust/gcc)
- 8GB zram zstd swap (safety net + build spike buffer)
- MAKEOPTS="-j32 -l32", EMERGE --jobs=3
- ccache 20GB for iterative rebuilds
- NVMe is DRAM-less (MAP1202) — good sequential, may be slower on random writes than Samsung
