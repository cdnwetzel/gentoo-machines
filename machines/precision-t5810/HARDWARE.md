# Dell Precision Tower T5810 - Hardware Reference

**Current OS**: Fedora 43 (live USB via Ventoy)

## System Overview

| Field | Value |
|-------|-------|
| **Product** | Dell Precision Tower 5810 |
| **Board** | Dell 0HHV7N |
| **BIOS** | A34 (10/19/2020) |
| **CPU** | Intel Xeon E5-2699 v4 @ 2.20GHz (Broadwell-EP) |
| **Cores** | 22C/44T (single socket, turbo 3.60GHz) |
| **RAM** | 256GB DDR4 ECC (8x32GB) |
| **Architecture** | x86_64 |
| **Chassis** | Tower (type 7) |

## CPU Features

Key flags: `vmx avx avx2 aes fma f16c bmi1 bmi2 hle rtm adx smap rdseed`

Notable: **No AVX-512** (Broadwell-EP, pre-Skylake). Full VT-x/VT-d. ECC support via sb_edac.

`CPU_FLAGS_X86="aes avx avx2 f16c fma3 mmx mmxext pclmul popcnt rdrand sse sse2 sse3 sse4_1 sse4_2 ssse3"`

**GCC**: `-march=broadwell`

## PCI Devices

| BDF | Device | PCI ID | Driver |
|-----|--------|--------|--------|
| 00:00.0 | Xeon E7 v4/E5 v4 DMI2 Host Bridge | `[8086:6f00]` | - |
| 00:01.0 | PCIe Root Port 1 (slot 0) | `[8086:6f02]` | pcieport |
| 00:01.1 | PCIe Root Port 1 (slot 1) | `[8086:6f03]` | pcieport |
| 00:02.0 | PCIe Root Port 2 | `[8086:6f04]` | pcieport |
| 00:03.0 | PCIe Root Port 3 | `[8086:6f08]` | pcieport |
| 00:05.0 | Map/VTd/System Management | `[8086:6f28]` | - |
| 00:05.4 | I/O APIC | `[8086:6f2c]` | - |
| 00:11.0 | C610/X99 SPSR | `[8086:8d7c]` | - |
| 00:11.4 | C610/X99 sSATA (AHCI) | `[8086:8d62]` | ahci |
| 00:14.0 | C610/X99 USB xHCI | `[8086:8d31]` | xhci_hcd |
| 00:16.0 | C610/X99 MEI Controller | `[8086:8d3a]` | mei_me |
| 00:19.0 | Ethernet Connection I217-LM | `[8086:153a]` | e1000e |
| 00:1a.0 | C610/X99 USB EHCI #2 | `[8086:8d2d]` | ehci-pci |
| 00:1b.0 | C610/X99 HD Audio | `[8086:8d20]` | snd_hda_intel |
| 00:1c.0 | C610/X99 PCIe Root Port #1 | `[8086:8d10]` | pcieport |
| 00:1c.1 | C610/X99 PCIe Root Port #2 | `[8086:8d12]` | pcieport |
| 00:1d.0 | C610/X99 USB EHCI #1 | `[8086:8d26]` | ehci-pci |
| 00:1f.0 | C610/X99 LPC Controller | `[8086:8d44]` | lpc_ich |
| 00:1f.3 | C610/X99 SMBus Controller | `[8086:8d22]` | i801_smbus |
| 01:00.0 | Samsung 990 PRO 2TB NVMe | `[144d:a80c]` | nvme |
| 03:00.0 | **NVIDIA RTX A4500 (GA102GL)** | `[10de:2232]` | nouveau→nvidia |
| 03:00.1 | GA102 HD Audio | `[10de:1aef]` | snd_hda_intel |
| 04:00.0 | **NVIDIA RTX A4500 (GA102GL)** | `[10de:2232]` | nouveau→nvidia |
| 04:00.1 | GA102 HD Audio | `[10de:1aef]` | snd_hda_intel |
| 06:00.0 | TI XIO2001 PCIe-to-PCI Bridge | `[104c:8240]` | - |

Plus ~50 Xeon uncore system peripherals at `ff:xx.x` (memory controllers, caching agents, QPI links, power control units).

## GPU Details

| # | GPU | PCI ID | Subsystem | PCI Slot | VRAM | TDP |
|---|-----|--------|-----------|----------|------|-----|
| 1 | NVIDIA RTX A4500 (GA102GL, Ampere) | `[10de:2232]` | NVIDIA `[10de:163c]` | 03:00.0 | 20 GB GDDR6 ECC | 200W |
| 2 | NVIDIA RTX A4500 (GA102GL, Ampere) | `[10de:2232]` | NVIDIA `[10de:163c]` | 04:00.0 | 20 GB GDDR6 ECC | 200W |

**Driver**: nvidia-drivers 580.142 (proprietary, current branch — Ampere supports `kernel-open` modules if desired). Nouveau blacklisted.
**HDMI/DP Audio**: 2x GA102 HD Audio `[10de:1aef]` via snd_hda_intel
**ECC**: Enabled on both cards (workstation-grade GDDR6 ECC)
**PCIe link**: Gen3 x16 each (board cap; A4500 supports Gen4)
**NVLink**: 4-link bridge installed and active between GPU0↔GPU1 (~56 GB/s per direction, 112 GB/s aggregate). Topology: `NV4`.
**Compute capability**: 8.6 (Ampere — supports BF16, TF32, structured sparsity, 3rd-gen Tensor Cores)
**No Intel iGPU** — Xeon E5 has no integrated graphics.

*Previous configuration: 2x GTX 1050 Ti (GP107 Pascal, 4GB each) — replaced with dual A4500 + NVLink for AI/ML workloads.*

## Storage

| Device | Type | Size | Filesystem | Notes |
|--------|------|------|-----------|-------|
| nvme0n1 | Samsung 990 PRO NVMe | 2TB | — | Gentoo install target |
| nvme0n1p1 | EFI System (current) | 600M | vfat | Keep as-is for Gentoo /boot/efi |
| nvme0n1p2 | Boot (current) | 1G | ext4 | Keep or reformat for Gentoo /boot |
| nvme0n1p3 | Fedora root (current) | 1.8T | btrfs (Fedora) | **Reformat to ext4 for Gentoo /** |
| sr0 | HL-DT-ST DVD-ROM | - | - | Optical drive |
| **sda** | **SABRENT 466GB** | **466GB** | **exfat+vfat** | **VENTOY BOOT USB — DO NOT TOUCH** |

**CRITICAL**: `sda` is the SABRENT Ventoy multi-boot live USB (`usb-SABRENT_SABRENT_DD56419883896-0:0`). All install scripts MUST exclude it.

## Audio

| Component | Details |
|-----------|---------|
| **Chipset** | C610/X99 HD Audio Controller `[8086:8d20]` |
| **Codec** | Realtek ALC3220 (Address 0) |
| **NVIDIA 1** | GA102 HDMI/DP `[10de:1aef]` (RTX A4500, Address 0) |
| **NVIDIA 2** | GA102 HDMI/DP `[10de:1aef]` (RTX A4500, Address 0) |
| **Type** | HDA (legacy HD Audio, no SOF) |
| **Driver** | snd_hda_intel (all 3 controllers) |

## Networking

| Interface | Device | PCI ID | Driver | Speed |
|-----------|--------|--------|--------|-------|
| Ethernet | Intel Connection I217-LM | `[8086:153a]` | e1000e | 1GbE |

**No WiFi** — desktop workstation, wired only.

## USB

| Controller | Type | PCI ID | Driver |
|-----------|------|--------|--------|
| C610/X99 xHCI | USB 3.0 | `[8086:8d31]` | xhci_hcd |
| C610/X99 EHCI #1 | USB 2.0 | `[8086:8d26]` | ehci-pci |
| C610/X99 EHCI #2 | USB 2.0 | `[8086:8d2d]` | ehci-pci |

Connected: Logitech wireless receiver (USB HID), hub.

## Platform Drivers

| Module | Purpose |
|--------|---------|
| dell_smbios | Dell SMBIOS interface |
| dell_smm_hwmon | Dell SMM fan/thermal |
| dcdbas | Dell Systems Management Base driver |
| dell_wmi_descriptor | Dell WMI descriptors |
| intel_wmi_thunderbolt | Intel WMI Thunderbolt (PCI bridge) |
| sb_edac | Sandy Bridge through Broadwell-EP EDAC (ECC) |
| intel_uncore | Broadwell-EP uncore performance counters |
| intel_rapl_msr | Intel RAPL power monitoring |
| coretemp | CPU core temperature |
| x86_pkg_temp_thermal | Package thermal management |
| intel_powerclamp | Intel idle injection thermal management |
| mei_me | Intel Management Engine Interface |
| iTCO_wdt | Intel TCO watchdog timer |
| lpc_ich | LPC/ICH interface |
| i2c_i801 | Intel 801 SMBus |
| kvm_intel | KVM virtualization |

## ECC Memory

- **EDAC driver**: sb_edac (loaded automatically)
- **RAM**: 256GB DDR4 ECC (8x32GB)
- **Error reporting**: `/sys/devices/system/edac/mc/`
- Kernel config: `CONFIG_EDAC=y`, `CONFIG_EDAC_SBRIDGE=m`

## Boot Configuration

| Setting | Value |
|---------|-------|
| Boot mode | EFI (64-bit) |
| Secure Boot | Disabled |
| Suspend | s2idle (usually always-on) |
| Hibernate | platform, shutdown, reboot modes available |

## Performance Notes

- This workstation was originally configured for **maximum performance**: C-states disabled in BIOS, no CPU throttling, always-on operation
- Previously housed an NVIDIA RTX Pro 6000 96GB Blackwell GPU before upgrade to Precision 7960
- With 256GB ECC RAM, portage tmpfs can be set to 64GB+ easily
- 22C/44T Xeon allows `make -j44` parallel compilation
- Dual NVMe could be considered for `/data` partition (currently single 2TB)

## Firmware Requirements

| Firmware | Package | Notes |
|----------|---------|-------|
| nvidia/ga102/* | sys-kernel/linux-firmware | RTX A4500 GPU firmware (GSP) |
| intel-microcode | sys-firmware/intel-microcode | Broadwell-EP Xeon microcode |

**Note**: No i915 firmware needed (no Intel iGPU). No WiFi firmware needed.
dmesg firmware loading was not captured (live USB rotated buffer). Firmware paths confirmed from `/lib/firmware/` on Fedora.

## GPU AI/ML Reference (Dual RTX A4500 + NVLink)

**Driver**: nvidia 580.142 (current branch — full Ampere support; `kernel-open` modules supported on Turing+ if preferred).
**CUDA**: 13.0, Compute Capability 8.6
**VRAM**: 20 GB GDDR6 ECC per GPU, **40 GB total** (NVLink-pooled for tensor parallelism)
**Tensor Cores**: 3rd-gen — FP16, BF16, TF32, INT8, structured 2:4 sparsity

### Interconnect

| Link | Bandwidth (per direction) | Notes |
|------|---------------------------|-------|
| NVLink (4-link bridge) | ~56 GB/s GPU0↔GPU1 | Active. Verify via `nvidia-smi topo -m` → `NV4` |
| PCIe Gen3 x16 (per card) | ~16 GB/s GPU↔CPU | Board cap; A4500 itself supports Gen4 |
| ECC | Enabled both cards | ~6% VRAM overhead, integrity for long runs |

NVLink eliminates the PCIe bottleneck for inter-GPU transfers, making **tensor parallelism practical** — single layers can be sharded across both cards with low overhead.

### Capability Envelope

| Workload | Fits? |
|----------|-------|
| 7B model FP16 inference | Single card (~14 GB) |
| 13B model FP16 inference | Won't fit on one card (~26 GB); tensor-parallel across both via NVLink works |
| 30B model 4-bit quantized | ~16 GB, single card; FP16 (~60 GB) exceeds 40 GB pool |
| LoRA fine-tune 7B | Single card; full FT viable across both |
| LoRA fine-tune 13B (BF16) | Tensor-parallel across both cards |
| BF16/TF32 mixed precision | Full hardware acceleration (Ampere TC) |

### Recommended Strategies

**1. Tensor parallelism (NVLink-enabled — the differentiator over PCIe-only setups)**
Shard layers across both GPUs; NVLink bandwidth is high enough that crossing the bridge isn't the bottleneck.
```python
# vLLM
from vllm import LLM
llm = LLM(model="meta-llama/Llama-2-13b-hf", tensor_parallel_size=2, dtype="bfloat16")

# HuggingFace accelerate (auto device map honors NVLink topology)
from accelerate import dispatch_model, infer_auto_device_map
device_map = infer_auto_device_map(model, max_memory={0: "19GiB", 1: "19GiB"})
```

**2. Pipeline parallelism** — for models that fit but want better throughput
Layer-stage split via `accelerate` or DeepSpeed. Less interconnect-sensitive than TP.

**3. Data parallelism** — when the model fits in 20 GB
Prefer DDP over `DataParallel`. NVLink accelerates the gradient all-reduce.
```python
import torch.nn.parallel as tp
model = tp.DistributedDataParallel(model.cuda(), device_ids=[local_rank])
```

**4. Independent workloads** — separate jobs per GPU
Hyperparameter sweeps, or one card training while the other serves.
```bash
CUDA_VISIBLE_DEVICES=0 python train.py
CUDA_VISIBLE_DEVICES=1 python serve.py
```

### Recommendation by Goal

| Goal | Approach |
|------|----------|
| Serve a 7B–13B LLM | vLLM, `tensor_parallel_size=2`, BF16 |
| Fine-tune a 7B model | LoRA on 1 GPU; full BF16 FT across both |
| Train a custom model | DDP across both with NVLink-accelerated all-reduce |
| Mixed experiments | `CUDA_VISIBLE_DEVICES` per process |
| Quantized inference (30B+) | bitsandbytes/AWQ 4-bit on a single card |

### Power & Thermal Envelope

- 2 × 200W = **400W sustained GPU draw under load** (plus 145W TDP CPU + system)
- Verify PSU headroom before adding further discrete cards (T5810 ships with 685W-class PSU)
- Monitor live: `nvidia-smi dmon -s pucvmet`
