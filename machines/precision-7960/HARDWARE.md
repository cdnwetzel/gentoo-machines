# Dell Precision 7960 Tower - Hardware Reference

**Current OS**: RHEL 10.1 (production AI/ML workstation, no Gentoo install planned)

**Status**: Reference only. This machine stays on RHEL for production workloads. Hardware inventory collected for fleet documentation.

## System Overview

| Field | Value |
|-------|-------|
| **Product** | Dell Precision 7960 Tower |
| **Board** | Dell 006CX9 (A03) |
| **BIOS** | 2.13.1 (08/08/2025) |
| **CPU** | Intel Xeon W5-3433 @ 2.0GHz / 4.2GHz turbo (Sapphire Rapids) |
| **Cores/Threads** | 16C/32T (single socket) |
| **RAM** | 128GB DDR5-5600 ECC RDIMM (2x64GB / 16 slots, 4TB max) |
| **Architecture** | x86_64 |
| **Chassis** | Tower (type 3) |
| **Kernel** | 6.12.0-124.31.1.el10_1.x86_64 |

## CPU Features

Key flags: `vmx avx avx2 avx512f avx512bw avx512cd avx512dq avx512vl avx512_bf16 avx512_fp16 avx512_vnni avx512_vbmi avx512_vbmi2 avx512_bitalg avx512_vpopcntdq avx512ifma amx_bf16 amx_tile amx_int8 avx_vnni sha_ni la57 enqcmd serialize`

Notable: **Full AVX-512 + AMX** (Sapphire Rapids). AMX enables hardware-accelerated matrix operations for AI/ML inference. Intel 5-level paging (la57). VT-x/VT-d. ECC support via i10nm_edac.

**Cache**: L1d 768 KiB (16 instances), L1i 512 KiB (16 instances), L2 32 MiB (16 instances), L3 45 MiB (shared).
**NUMA**: Single node (node0: CPUs 0-31).
**Frequency**: 800 MHz min, 4200 MHz max turbo, HWP enabled.

`CPU_FLAGS_X86="aes avx avx2 avx512bw avx512cd avx512dq avx512f avx512vbmi avx512vl avx512_vnni avx_vnni f16c fma3 mmx pclmul popcnt sha sse sse2 sse4_1 sse4_2 ssse3 vpclmulqdq"`

**GCC**: `-march=sapphirerapids` (harvest suggests x86-64-v3, but Sapphire Rapids is the correct microarch)

## PCI Devices

| BDF | Device | PCI ID | Driver |
|-----|--------|--------|--------|
| 00:00.0 | Ice Lake Memory Map/VT-d | `[8086:09a2]` | - |
| 00:14.0 | Alder Lake-S PCH USB 3.2 Gen 2x2 xHCI | `[8086:7ae0]` | xhci_hcd |
| 00:16.0 | Alder Lake-S PCH HECI Controller | `[8086:7ae8]` | mei_me |
| 00:17.0 | SATA Controller [RAID Mode] | `[8086:2826]` | ahci |
| 00:1f.0 | Alder Lake-S PCH ISA Bridge | `[8086:7a8a]` | - |
| 00:1f.3 | Alder Lake-S HD Audio Controller | `[8086:7ad0]` | snd_hda_intel |
| 00:1f.4 | Alder Lake-S PCH SMBus Controller | `[8086:7aa3]` | i801_smbus |
| 00:1f.5 | Alder Lake-S PCH SPI Controller | `[8086:7aa4]` | - |
| 00:1f.6 | Ethernet Connection (17) I219-LM | `[8086:1a1c]` | e1000e |
| 01:00.0 | AQtion AQC113 10G Ethernet | `[1d6a:04c0]` | atlantic |
| 02:00.0 | Realtek RTS525A Card Reader | `[10ec:525a]` | rtsx_pci |
| 16:00.0 | **NVIDIA RTX A1000 (GA107GL)** | `[10de:25b0]` | nvidia |
| 16:00.1 | GA107 HD Audio Controller | `[10de:2291]` | snd_hda_intel |
| 34:00.0 | SK hynix PC811 NVMe 476.9GB | `[1c5c:1969]` | nvme |
| 51:00.5 | Intel VMD NVMe RAID Controller | `[8086:28c0]` | vmd |
| 6f:00.5 | Intel VMD NVMe RAID Controller | `[8086:28c0]` | vmd |
| ac:00.0 | **NVIDIA RTX PRO 6000 Blackwell (GB202GL)** | `[10de:2bb1]` | nvidia |
| ac:00.1 | GB202 HD Audio Controller | `[10de:22e8]` | snd_hda_intel |
| c9:00.5 | Intel VMD NVMe RAID Controller | `[8086:28c0]` | vmd |
| e7:01.0 | Intel IDXD (Data Accelerator) | `[8086:0b25]` | idxd |
| e7:03.1 | Intel Ice Lake PMON MSM | `[8086:09a7]` | intel_vsec |
| fe:00.1 | Intel ISST (Speed Select) | `[8086:3251]` | isst_if_pci |

Plus ~100 Sapphire Rapids uncore system peripherals (memory controllers, CHA registers, DDRIO, performance counters).

VMD-managed NVMe at domains 10000, 10001, 10002:

| BDF | Device | PCI ID | Driver |
|-----|--------|--------|--------|
| 10002:0a:00.0 | Samsung PM9C1a NVMe 1.8TB | `[144d:a80d]` | nvme |
| 10002:0b:00.0 | Samsung PM9C1a NVMe 1.8TB | `[144d:a80d]` | nvme |
| 10002:0c:00.0 | Samsung PM9C1a NVMe 1.8TB | `[144d:a80d]` | nvme |
| 10002:0d:00.0 | Samsung PM9C1a NVMe 1.8TB | `[144d:a80d]` | nvme |

## GPU Details

| # | GPU | PCI ID | Subsystem | VRAM | PCI Slot |
|---|-----|--------|-----------|------|----------|
| 1 | RTX PRO 6000 Blackwell Workstation Edition (GB202GL) | `[10de:2bb1]` | NVIDIA `[10de:204b]` | 96 GB GDDR7 (97887 MiB) | ac:00.0 |
| 2 | RTX A1000 (GA107GL) | `[10de:25b0]` | Dell `[1028:1878]` | 8 GB GDDR6 (8188 MiB) | 16:00.0 |

**Driver**: nvidia-drivers 590.48.01 (proprietary, open kernel module). CUDA 13.1. Nouveau blacklisted.
**HDMI Audio**: GB202 HD Audio `[10de:22e8]` + GA107 HD Audio `[10de:2291]` via snd_hda_intel.
**No Intel iGPU** -- Xeon W5 has no integrated graphics.
**Persistence Mode**: On (both GPUs).

### RTX PRO 6000 Blackwell (Primary AI/ML GPU)

- **Architecture**: Blackwell (GB202GL)
- **VRAM**: 96 GB GDDR7 (single largest GPU memory in fleet)
- **Compute Capability**: 12.0
- **Key features**: FP8/FP4, 5th-gen Tensor Cores, PCIe Gen5 x16
- **TDP**: 600W max
- **Role**: Primary AI/ML training and inference (LLM fine-tuning, large model hosting)

### RTX A1000 (Secondary/Display GPU)

- **Architecture**: Ampere (GA107GL)
- **VRAM**: 8 GB GDDR6
- **Compute Capability**: 8.6
- **TDP**: 50W max
- **Role**: Display output, light compute offload (Python process active at harvest time)

## Storage

| Device | Type | Size | Filesystem | Mount | Notes |
|--------|------|------|-----------|-------|-------|
| nvme0n1 | SK hynix PC811 NVMe | 476.9GB | LVM | - | Boot/OS drive |
| nvme0n1p1 | EFI System | 600M | vfat | /boot/efi | |
| nvme0n1p2 | Boot | 1G | xfs | /boot | |
| nvme0n1p3 | LVM PV | 475.4G | LVM2_member | - | |
| rhel-root | LV | 70G | xfs | / | |
| rhel-swap | LV | 32G | swap | [SWAP] | |
| rhel-home | LV | 373.4G | xfs | /home | |
| sda | SATA HDD | 1.8T | - | - | Backup drive |
| sda1 | Partition | 1.8T | xfs | /backup | |
| nvme1-4n1 | 4x Samsung PM9C1a NVMe | 1.8TB each | linux_raid_member | - | Via VMD domain 10002 |
| md127 | RAID10 (4x NVMe) | 3.6TB | xfs | /data | AI/ML dataset storage |

**NVMe RAID**: 4x Samsung PM9C1a 1.8TB drives managed by 3x Intel VMD controllers in RAID10 configuration. Provides ~3.6TB usable with redundancy and high sequential throughput.

## Audio

| Component | Details |
|-----------|---------|
| **Chipset** | Alder Lake-S PCH HD Audio Controller `[8086:7ad0]` |
| **Codec** | Realtek ALC3246 (Address 0) |
| **NVIDIA 1** | GB202 HDMI/DP `[10de:22e8]` (RTX PRO 6000, Address 0) |
| **NVIDIA 2** | GA107 HDMI/DP `[10de:2291]` (RTX A1000, Address 0) |
| **Type** | SOF (Sound Open Firmware) + HDA |
| **Drivers** | snd_hda_intel, snd_sof_pci_intel_tgl, snd_hda_codec_realtek, snd_hda_codec_hdmi |

## Networking

| Interface | Device | PCI ID | Driver | Speed |
|-----------|--------|--------|--------|-------|
| Ethernet (mgmt) | Intel Connection (17) I219-LM | `[8086:1a1c]` | e1000e | 1GbE |
| Ethernet (data) | Aquantia AQC113 (Antigua 10G) | `[1d6a:04c0]` | atlantic | 10GbE |

**No WiFi** -- enterprise tower workstation, wired only.

## USB

| Controller | Type | PCI ID | Driver |
|-----------|------|--------|--------|
| Alder Lake-S PCH xHCI | USB 3.2 Gen 2x2 | `[8086:7ae0]` | xhci_hcd |

## Platform Drivers

| Module | Purpose |
|--------|---------|
| dell_smbios | Dell SMBIOS interface |
| dell_smm_hwmon | Dell SMM fan/thermal |
| dell_pc | Dell platform profile |
| dcdbas | Dell Systems Management Base driver |
| dell_wmi | Dell WMI events |
| dell_wmi_descriptor | Dell WMI descriptors |
| dell_wmi_sysman | Dell WMI system management |
| dell_wmi_ddv | Dell WMI DDV (diagnostics) |
| i10nm_edac | Ice Lake/Sapphire Rapids EDAC (ECC) |
| intel_uncore | Sapphire Rapids uncore performance counters |
| intel_rapl_msr | Intel RAPL power monitoring |
| intel_ifs | Intel In-Field Scan (CPU health) |
| coretemp | CPU core temperature |
| x86_pkg_temp_thermal | Package thermal management |
| intel_powerclamp | Intel idle injection thermal management |
| intel_cstate | Intel C-state residency counters |
| intel_sdsi | Intel Software Defined Silicon |
| intel_vsec | Intel Vendor Specific Extended Capabilities |
| mei_me | Intel Management Engine Interface |
| iTCO_wdt | Intel TCO watchdog timer |
| i2c_i801 | Intel 801 SMBus |
| kvm_intel | KVM virtualization |
| pinctrl_alderlake | Alder Lake PCH pin control |
| platform_profile | Platform power/performance profiles |
| pmt_telemetry | Intel Platform Monitoring Technology |

## Advanced Platform Features

| Feature | Module/Driver | Notes |
|---------|--------------|-------|
| **Intel VMD** | vmd | Volume Management Device for NVMe RAID (3 controllers) |
| **Intel IDXD** | idxd | Data Accelerator with IAA crypto offload |
| **Intel ISST** | isst_if_mmio, isst_if_mbox_pci | Speed Select Technology (per-core frequency control) |
| **CXL** | cxl_core, cxl_port, cxl_acpi | Compute Express Link (memory expansion capable) |
| **NVDIMM/NFIT** | nfit, libnvdimm | ACPI NFIT (NVDIMM Firmware Interface Table) |
| **DAX** | dax_hmem | Direct Access for heterogeneous memory |
| **EINJ** | einj | Error Injection (RAS testing) |
| **Intel IFS** | intel_ifs | In-Field Scan (CPU silicon health monitoring) |
| **Intel SDSI** | intel_sdsi | Software Defined Silicon (feature licensing) |

## ECC Memory

- **EDAC driver**: i10nm_edac (loaded automatically, with skx_edac_common)
- **RAM**: 128GB DDR5 ECC (2x64GB RDIMMs in DIMM1 + DIMM2)
- **Module**: Samsung M321R8GA0EB0-CWMXH, dual-rank, 80-bit (64 data + 16 ECC)
- **Speed**: DDR5-5600 rated, running at 4400 MT/s (BIOS-configured)
- **Voltage**: 1.1V
- **Slots**: 16 total, 2 populated, 14 empty
- **Max capacity**: 4 TB (per SMBIOS)
- **Error reporting**: `/sys/devices/system/edac/mc/`

## Enterprise/Server Software Stack

| Feature | Details |
|---------|---------|
| **CIFS/SMB** | cifs module loaded, 11 active mounts (network file shares) |
| **Docker/Containers** | overlay (4 active), veth, bridge networking |
| **Firewall** | nftables + nft_compat (iptables compatibility) |
| **KVM** | kvm_intel loaded (virtualization ready) |
| **iSCSI** | be2iscsi, bnx2i, cxgb4i, iscsi_tcp (SAN connectivity) |
| **Device Mapper** | dm_mod, dm_multipath, dm_mirror (LVM + multipath) |
| **RDMA** | rdma_cm, ib_core (InfiniBand/RDMA over Converged Ethernet) |
| **MD RAID** | raid10 (4x NVMe RAID10 active) |
| **NVMe-oF** | nvme_tcp, nvme_fabrics (NVMe over Fabrics/TCP) |

## Boot Configuration

| Setting | Value |
|---------|-------|
| Boot mode | EFI (64-bit) |
| Secure Boot | Enabled |
| Suspend | S3 deep sleep (supported, typically always-on) |
| Hibernate | Disabled |

## I2C Buses

| Bus | Adapter |
|-----|---------|
| i2c-0 | SMBus I801 adapter at 2000 |
| i2c-1 to i2c-4 | NVIDIA i2c adapters at 16:00.0 (RTX A1000) |
| i2c-5 to i2c-10 | NVIDIA i2c adapters at ac:00.0 (RTX PRO 6000) |

## Firmware Requirements

| Firmware | Notes |
|----------|-------|
| nvidia (embedded) | GPU firmware embedded in proprietary driver |
| intel-microcode | Sapphire Rapids Xeon microcode |

**Note**: No i915 firmware needed (no Intel iGPU). No WiFi firmware needed. dmesg buffer had rotated at harvest time; firmware paths confirmed from loaded modules.

## Fleet Comparison

| Feature | Precision 7960 | Precision T5810 | XPS 9510 | MBP 2015 | Surface Pro 6 |
|---------|----------------|-----------------|----------|----------|---------------|
| **CPU** | Xeon W5-3433 (SPR) | Xeon E5-2699v4 (BDW-EP) | i7-11800H (TGL-H) | i7-5557U (BDW) | i5-8250U (KBL-R) |
| **Threads** | 32 | 44 | 16 | 4 | 8 |
| **RAM** | 128GB DDR5 ECC | 256GB DDR4 ECC | 32GB DDR4 | 8GB DDR3 | 8GB LPDDR3 |
| **GPU** | RTX PRO 6000 96GB + RTX A1000 8GB | 2x GTX 1050 Ti 4GB | RTX 3050 Ti + Intel UHD | Intel Iris 6100 | Intel UHD 620 |
| **GPU VRAM** | 104 GB total | 8 GB total | 4 GB (dGPU) | shared | shared |
| **Storage** | 477GB NVMe + 4x1.8TB RAID10 + 1.8TB HDD | 2TB NVMe | 2x NVMe | 256GB SSD | 238GB NVMe |
| **Network** | 1GbE + 10GbE | 1GbE | WiFi + USB Ethernet | WiFi | WiFi |
| **AVX-512** | Yes + AMX | No | Yes | No | No |
| **ECC** | Yes (i10nm_edac) | Yes (sb_edac) | No | No | No |
| **VMD RAID** | Yes (3 controllers) | No | No | No | No |
| **CXL** | Yes | No | No | No | No |
| **OS** | RHEL 10.1 | Gentoo | Gentoo | Gentoo | Gentoo |
| **GCC -march** | sapphirerapids | broadwell | tigerlake | broadwell | skylake |
| **Role** | Production AI/ML | Build server | Daily driver | Travel laptop | Tablet/portable |
