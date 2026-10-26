# Dell OptiPlex 3080 - Hardware Reference

**Current OS**: Gentoo Linux (installed 2026-10-16, verified). Harvested from a Ventoy live USB for the Gentoo migration; re-harvested post-install (see `harvest/*2026-10-16.log`). Sections below marked "harvest" reflect the original pre-install state — see STATUS.md for current.

## System Overview

| Field | Value |
|-------|-------|
| **Product** | Dell OptiPlex 3080 |
| **Family** | OptiPlex |
| **Chassis** | Desktop (type 3) |
| **Board** | Dell 0HMF7C A01 |
| **Chipset** | Intel B460 (Comet Lake PCH-V) |
| **BIOS** | Dell 2.33.0 (07/31/2025) |
| **CPU** | Intel Core i3-10105 @ 3.70GHz (Comet Lake-S, family 6 model 165) |
| **Cores** | 4C/8T (single socket, single NUMA node) |
| **Clocks** | 800 MHz – 4400 MHz (turbo enabled) |
| **Architecture** | x86_64 (no hybrid P/E-cores) |
| **RAM** | 16GB DDR4 (15752MB usable), non-ECC, **dual-channel** (2 of 2 slots populated; at harvest: 8GB single-channel) |
| **Max RAM** | 64GB (2 slots) |
| **Boot** | UEFI 64-bit, **Secure Boot ENABLED** |
| **Suggested flags** | `-march=skylake -O2 -pipe` |

## CPU Features

Key flags: `vmx ept avx avx2 fma f16c bmi1 bmi2 aes pclmulqdq movbe popcnt rdrand rdseed adx sse4_1 sse4_2 ssse3 clflushopt xsavec xsaves intel_pt hwp hwp_epp ibrs_enhanced md_clear`

Notable: **No AVX-512**, no SHA-NI, no GFNI/VAES. Comet Lake is a Skylake derivative, so GCC has no `-march=cometlake` and `-march=skylake` is the right target.

CPU_FLAGS_X86 (approximate, from /proc/cpuinfo): `aes avx avx2 f16c fma3 mmx pclmul popcnt sse sse2 sse4_1 sse4_2 ssse3`. Confirm with `cpuid2cpuflags` once the system is installed.

## PCI Devices

| BDF | Device | PCI ID | Driver | Module |
|-----|--------|--------|--------|--------|
| 00:00.0 | 10th Gen Core Host Bridge / DRAM Registers | `[8086:9b63]` | skl_uncore | - |
| 00:02.0 | CometLake-S GT2 [UHD Graphics 630] | `[8086:9bc8]` | i915 | i915 |
| 00:08.0 | Gaussian Mixture Model (GNA) | `[8086:1911]` | - | - |
| 00:14.0 | Comet Lake PCH-V USB xHCI | `[8086:a3af]` | xhci_hcd | xhci_pci |
| 00:14.2 | Comet Lake PCH-V Thermal Subsystem | `[8086:a3b1]` | - | - |
| 00:16.0 | Comet Lake PCH-V HECI (MEI) | `[8086:a3ba]` | mei_me | mei_me |
| 00:17.0 | SATA Controller (**RAID mode**) | `[8086:a386]` | ahci | ahci |
| 00:1c.0 | Comet Lake PCIe Root Port #05 | `[8086:a394]` | pcieport | shpchp |
| 00:1f.0 | B460 Chipset LPC/eSPI Controller | `[8086:a3c8]` | - | - |
| 00:1f.2 | Cannon Lake PCH Power Management Controller | `[8086:a3a1]` | - | - |
| 00:1f.3 | Comet Lake PCH-V cAVS Audio | `[8086:a3f0]` | snd_hda_intel | snd_soc_avs, snd_sof_pci_intel_cnl, snd_hda_intel |
| 00:1f.4 | Comet Lake PCH-V SMBus | `[8086:a3a3]` | i801_smbus | i2c_i801 |
| 01:00.0 | Realtek RTL8111/8168 GbE (rev 15, RTL8168h) | `[10ec:8168]` | r8169 | r8169 |

All onboard devices have Dell subsystem ID `[1028:09a8]`.

## Networking

- **Wired**: Realtek RTL8168h Gigabit Ethernet (`r8169` driver, `realtek` PHY driver)
- **WiFi**: None. No wireless adapter was detected.
- **Bluetooth**: None

## Storage

- **SATA**: Intel Comet Lake PCH-V SATA controller `[8086:a386]`, handled by the `ahci` driver
  - `sda`: 223.6GB SATA SSD. It currently holds Windows (EFI 150M vfat, MSR 128M, 218.9G NTFS, plus 1.8G and 2.6G NTFS recovery partitions)
- **NVMe**: None detected. `nvme_core` is loaded only as a dependency of `nvme_tcp`, and no NVMe device is on the PCIe bus.
- **Optical**: `sr0` (1024M), a SATA optical drive
- **Live media**: `sdb` is a 28.6GB Ventoy USB. **Do not format it.**

> **BIOS RAID warning**: the SATA controller enumerates with the RAID-mode device ID `[8086:a386]` (PCI class 0104), which is Intel RST. This is the same trap as the OptiPlex 3090. Here `ahci` still binds and `sda` is visible. Switch the BIOS to **AHCI** before installing anyway: it gives the stable device ID and avoids RST remapping if an NVMe is added later. Switching breaks the existing Windows boot unless Windows is prepared first (Safe Boot trick). That doesn't matter if Windows is being wiped.

## Audio

- **Controller**: Comet Lake PCH-V cAVS `[8086:a3f0]`
- **Primary driver**: `snd_hda_intel` (bound and in use)
- **SOF driver**: `snd_sof_pci_intel_cnl` is loaded but **not bound**, because legacy HDA wins on this platform
- **AVS driver**: `snd_soc_avs` is loaded but unused
- **Codecs**:
  - Realtek ALC3246 (Dell rebrand) at address 0, via `snd_hda_codec_alc269` / `snd_hda_codec_realtek_lib`
  - Intel Kabylake HDMI at address 2, via `snd_hda_codec_intelhdmi` / `snd_hda_codec_hdmi`
- **Kernel config**: HDA alone is enough (`SND_HDA_INTEL`, `SND_HDA_CODEC_REALTEK`, `SND_HDA_CODEC_HDMI`). SOF and SoundWire can be left out.

## Graphics

- **GPU**: Intel CometLake-S GT2 UHD Graphics 630 `[8086:9bc8]`
- **Driver**: `i915` (build as a module, `=m`, because there is no initramfs and it needs firmware)
- **Discrete GPU**: None. No NVIDIA GPU was detected.
- **Display outputs**: DP-B, DP-C and DP-D (gmbus `dpb`/`dpc`/`dpd`, AUX C/D)
- **Features**: VAAPI hardware acceleration (`VIDEO_CARDS="intel"`)

## USB

| Bus | Speed | Ports | Devices |
|-----|-------|-------|---------|
| 001 | USB 2.0 (480M) | 12 | Logitech Unifying receiver on port 8 (`hid_logitech_dj` / `hid_logitech_hidpp`) |
| 002 | USB 3.x (5000M) | 8 | Ventoy USB stick (`usb-storage` / `uas`) |

- **Controller**: Comet Lake PCH-V xHCI (`xhci_pci`)
- **Thunderbolt**: None

## I2C Buses

| Bus | Type | Adapter |
|-----|------|---------|
| i2c-0 | i2c | i915 gmbus dpc |
| i2c-1 | i2c | i915 gmbus dpb |
| i2c-2 | i2c | i915 gmbus dpd |
| i2c-3 | i2c | AUX C/DDI C/PHY C (DP aux) |
| i2c-4 | i2c | AUX D/DDI D/PHY D (DP aux) |
| i2c-5 | smbus | SMBus I801 at 00:1f.4 |

**SPD EEPROM**: `ee1004` at 5-0050, with DDR4 SPD page-select dummies at 5-0036 and 5-0037. There is only one SPD at 0x50, which confirms a single DIMM.

No LPSS/DesignWare I2C controllers and no I2C HID input devices are present (this is a desktop).

## Memory

| Slot | Size | Type | Speed | Part | Manufacturer |
|------|------|------|-------|------|--------------|
| DIMM1 | 8GB | DDR4 UDIMM, 1 rank | rated 3200 MT/s, **running 2666 MT/s** | HMAA1GU6CJR6N-XN | SK hynix (80AD) |
| DIMM2 | 8GB | DDR4 UDIMM, 1 rank | rated 2666 MT/s, running 2666 MT/s | HMA81GU6JJR8N-VK | SK hynix (80AD) |

- **Post-install (2026-10-16)**: DIMM2 holds a *borrowed* stick pending delivery of the ordered HMAA1GU6CJR6N-XN twin — swap it in when it arrives.
- The speed is capped at 2666 MT/s by the i3-10105 memory controller, not by the DIMMs.
- ~~Running single-channel halves memory bandwidth~~ — resolved: dual-channel since 2026-10-16.
- **Harvest parser note**: section 3c reported "5 populated / 2 total" and section 2b reported "2x 8 GB". Neither is right. The single ee1004 SPD and 7673MB total both point to 1x 8GB.

## Build Profile

- **RAM class**: CONSTRAINED (16GB since 2026-10-16; MINIMAL/8GB at harvest)
- **tmpfs**: 4GB at most, or no tmpfs, with disk fallback for large packages (chromium, llvm, rust, gcc, firefox, qtwebengine)
- **emerge --jobs**: 1
- **MAKEOPTS**: `-j4` to `-j6` is recommended over `-j8` to avoid OOM on C++-heavy builds
- **zram**: 4GB zstd swap is recommended (the live environment ran 7.5GB lz4)

## Power / Suspend

- **CPU frequency**: `intel_pstate` active, `powersave` governor, HWP/EPP available
- **Suspend**: `s2idle` and `deep`, with **S3 deep active**
- **Hibernate**: disabled in the live environment. It needs a swap file plus a `resume=` setup (`shared/hibernate-setup.sh`)
- **Battery**: none (desktop)
- **RAPL**: `intel_rapl_msr` / `intel_rapl_common`

## Platform Drivers

| Module | Purpose |
|--------|---------|
| `dell_wmi` | Dell WMI hotkeys/events |
| `dell_smbios` | Dell SMBIOS interface |
| `dell_wmi_descriptor` | Dell WMI descriptor (dell_wmi/dell_smbios dependency) |
| `dell_wmi_sysman` | Dell BIOS settings via sysfs (firmware-attributes) |
| `dell_smm_hwmon` | Dell SMM fan/temperature sensors |
| `dcdbas` | Dell Systems Management Base Driver |
| `wmi` / `wmi_bmof` | ACPI WMI core / binary MOF |
| `sparse_keymap` | Keymap helper for dell_wmi |
| `intel_pmc_core` | Platform Management Controller (S0ix/residency) |
| `intel_pmc_bxt` | PMC IPC (provides the iTCO_wdt platform device) |
| `pmt_telemetry` / `pmt_discovery` / `pmt_class` / `intel_vsec` | Intel Platform Monitoring Technology |
| `intel_pmc_ssram_telemetry` | PMC SSRAM telemetry |
| `pinctrl_sunrisepoint` | PCH pin control (Comet Lake PCH-V uses the SPT/CNL-H family) |
| `iTCO_wdt` / `iTCO_vendor_support` | Intel TCO watchdog |
| `intel_oc_wdt` | Intel overclocking watchdog |
| `mei_me` / `mei_hdcp` / `mei_pxp` | Management Engine interface, HDCP, PXP |
| `coretemp` | CPU core temperature |
| `x86_pkg_temp_thermal` | Package thermal |
| `intel_tcc_cooling` | TCC offset cooling |
| `intel_powerclamp` | CPU idle injection |
| `intel_rapl_msr` / `rapl` | Running Average Power Limit / perf RAPL |
| `intel_cstate` / `intel_uncore` | C-state and uncore perf counters |
| `intel_uncore_frequency` | Uncore frequency control |
| `acpi_pad` | ACPI processor aggregator |
| `platform_profile` | ACPI platform profile |
| `ee1004` | DDR4 SPD EEPROM |
| `i2c_i801` / `i2c_smbus` | PCH SMBus |
| `pcspkr` | PC speaker |
| `kvm_intel` | VT-x virtualization (EPT, VPID) |
| `video` | ACPI video (i915/dell_wmi dependency) |

Platform: **DELL**, which needs `X86_PLATFORM_DRIVERS_DELL=y` before the Dell drivers.

## Firmware (loaded from /lib/firmware/)

| File Pattern | Purpose |
|--------------|---------|
| `i915/kbl_dmc_ver1_04.bin` | Display Microcontroller (Comet Lake uses KBL DMC) |
| `i915/kbl_guc_*.bin` | GuC (Comet Lake shares KBL GuC) |
| `i915/cml_huc_*.bin` | Comet Lake HuC |
| `rtl_nic/rtl8168h-2.fw` | RTL8168h (rev 15) Ethernet PHY firmware |
| `intel-ucode/06-a5-0x` | CPU microcode (family 6 model 165; confirm the stepping at boot) |
| `regulatory.db` | Not required (no WiFi) |

**Note**: no firmware loads showed up in dmesg (the buffer had rotated). Confirm exact filenames at first Gentoo boot with `dmesg | grep -i firmware`. All firmware-dependent drivers (`i915`, `r8169`) must be modules (`=m`) because there is no initramfs.

## Pre-Install Checklist

1. **Disable Secure Boot**, or set up signing. A custom gentoo-sources kernel will not boot with Secure Boot enabled.
2. **Switch SATA from RAID to AHCI** in the BIOS (see the Storage warning).
3. The Windows install on `sda` will be overwritten. Back up anything needed first.
4. **Never touch `sdb`** (Ventoy).

## Key Differences from OptiPlex 3090

| Feature | OptiPlex 3080 | OptiPlex 3090 |
|---------|---------------|---------------|
| CPU | i3-10105 (4C/8T) | i5-10505 (6C/12T) |
| CPU arch | Comet Lake-S, `-march=skylake` | Comet Lake-S, `-march=skylake` |
| Chipset | B460 (PCH-V) | Q470 |
| RAM | 16GB DDR4-2666 dual-channel | 16GB DDR4-2666 single-channel |
| Build profile | MINIMAL (4GB tmpfs or none) | CONSTRAINED (7GB tmpfs) |
| iGPU | UHD 630 (`i915`) | UHD 630 (`i915`) |
| Discrete GPU | None | NVIDIA RTX A1000 (kernel-open) |
| Storage | 256GB M.2 NVMe (fanxiang S500 Pro, `nvme`); dying SATA SSD disconnected | 256GB M.2 2230 NVMe |
| Optical | Yes (`sr0`) | No |
| SATA mode | RAID `[8086:a386]` (flip to AHCI) | RAID (flip to AHCI, required for NVMe) |
| Ethernet | RTL8168h (`r8169`) | RTL8168 (`r8169`) |
| WiFi/BT | None | None |
| Audio | ALC3246 + Intel HDMI (`snd_hda_intel`) | ALC3246 + NVIDIA HDMI (`snd_hda_intel`) |
| Dell platform | dell_wmi, dell_smbios, dell_smm_hwmon, dell_wmi_sysman | dell_smbios, dell_wmi |
| Suspend | S3 deep | S3 deep + hibernate |
| Secure Boot | Enabled (must disable) | - |
