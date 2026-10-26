# Beelink MINI S (N5095A) — Hardware Reference

Harvested 2026-04-14 from Fedora 43 live USB; updated 2026-04-16 from running Gentoo 6.18.22.
Sources: `tools/harvest.sh`, `tools/deep_harvest.sh`, `dmidecode`, `lspci`, `lsusb`, `smartctl`, `dmesg`, `/proc/cpuinfo`.

## Identity

| | |
|---|---|
| Vendor / Product | AZW (Beelink) / **MINI S** |
| Board | AZW MINI S (motherboard) |
| BIOS | AMI JTKT001 rev 5.19, 2022-04-13, 8 MB SPI (socketed, upgradeable) |
| SMBIOS | 3.3.0 |
| TPM | **TPM 2.0** (AMI, ACPI TPM2 table) |
| UEFI | 64-bit, Secure Boot **disabled** |
| DMI quirk | Vendor strings are mostly `Default string` (typical cheap Beelink); product detection relies on `sys_vendor=AZW` + `product_name=MINI S` |

## CPU — Intel Celeron N5095A (Jasper Lake / Tremont)

| | |
|---|---|
| Family/Model/Stepping | 6 / 156 / 0 (0x9c) — Jasper Lake |
| Microarch | **Tremont** (Atom-class, Gen11 Atom cores) |
| Cores / Threads | **4 / 4** (no Hyper-Threading) |
| Base / Turbo | 2.0 / 2.9 GHz (Max 2900 MHz per DMI) |
| L2 cache | 4 MB (no L3) |
| TDP | ~10 W PL1, 15 W PL2 |
| Microcode (live env) | 0x24000026 → **needs `sys-firmware/intel-microcode`** (SRBDS marked "Vulnerable: No microcode") |
| Virtualization | VT-x **and** VT-d present; x2apic + IRQ remapping enabled; KVM ready |
| HWP | Full HWP support (`hwp`, `hwp_notify`, `hwp_act_window`, `hwp_epp`, `hwp_pkg_req`) → `intel_pstate=active` |

### CPU flags that matter for Gentoo

**Present** (Tremont subset):
```
aes mmx pclmulqdq popcnt rdrand rdseed sha_ni
sse sse2 ssse3 sse4_1 sse4_2
clflushopt clwb xsave xsavec xsaveopt xgetbv1 xsaves
gfni movbe movdiri movdir64b waitpkg umip vnmi
```

**Missing — and it changes compiler choices**:
- ❌ **No AVX, AVX2, FMA, F16C, BMI1, BMI2**
- ❌ No AVX-512 (obviously)

### `-march=` decision

- **Chosen: `-march=tremont`** (GCC 10+, native Tremont tuning)
- **NOT `x86-64-v3`** — v3 requires AVX2 which this CPU lacks; harvest.sh's suggestion is wrong for this model.
- Fallback: `-march=x86-64-v2` if any package miscompiles under `tremont`.

### `CPU_FLAGS_X86`

```
aes mmx pclmul popcnt rdrand sha sse sse2 sse4_1 sse4_2 ssse3
```

Verify with `emerge app-portage/cpuid2cpuflags && cpuid2cpuflags` after first boot.

## Memory

| | |
|---|---|
| Total | **8 GB** DDR4-2666 SODIMM |
| Channels populated | **1 of 2** (Channel B only; Channel A DIMM0 empty) |
| Part | `DDR4 NB 8G 2666` (unbranded) |
| Max (per DMI) | 32 GB (2×16) |
| ECC | None |
| Voltage | 1.2 V |

**Performance note**: single-channel is the biggest bottleneck on this platform — roughly 40% less iGPU memory bandwidth than dual-channel. Adding a matching 8 GB SODIMM (~$15) would meaningfully improve desktop responsiveness.

## Storage

| | |
|---|---|
| Device | `NGFF 2280 256GB SSD` (unbranded, M.2 SATA) |
| Interface | **SATA 3.2 @ 6 Gb/s via AHCI** — no NVMe on this board |
| Firmware | V0601A0 |
| Size | 238.47 GiB (256 GB) |
| TRIM | Supported |
| SMART health | PASSED (0 reallocated, 0 pending, 0 errors) |
| Power-on hours | **19,608 (~2.2 years continuous)** |
| Power cycles | 406 |
| Temp (idle) | 40 °C |
| LBAs written | ~251 GB lifetime (low write wear) |

**Key implication**: **no NVMe slot on this SKU.** The M.2 socket is SATA-only, wired through the Jasper Lake AHCI controller (`00:17.0`). Kernel storage stack is AHCI, not NVMe. Partitioning targets `/dev/sda`.

The drive has seen substantial runtime — plan to take SMART snapshots periodically (`smartctl -a` + `smartctl -t short`).

## Graphics

| | |
|---|---|
| iGPU | Intel **UHD Graphics** (Jasper Lake, Gen11 LP, device `8086:4e55` rev 01, stepping B0) |
| Driver | `i915` (module — **must not be built-in**, DMC firmware loaded from disk) |
| DMC firmware | `i915/icl_dmc_ver1_09.bin` (v1.9) — ICL/JSL share DMC binary |
| Video accel | VA-API via `intel-media-driver` (iHD): H.264/HEVC/VP9/AV1 **decode**; no AV1 encode |
| Displays | HDMI + USB-C DP-alt-mode (front) via ANX7447 retimer on I2C |
| HDCP | Working (`mei_hdcp` binds to i915) |

## Networking

### WiFi — Intel Wireless-AC 3165

| | |
|---|---|
| PCI ID | `8086:3165` rev 81 |
| Subsystem | `8086:8010` |
| Standard | **Wi-Fi 5 (802.11ac), 1×1 stream, 433 Mbps max** |
| Driver | `iwlwifi` + `iwlmvm` |
| Firmware | `iwlwifi-7265D-29.ucode` (3165 shares 7265D firmware) |
| MAC | `dc:21:5c:fd:65:4c` |

**Note**: the 3165 is an M.2-E card — replaceable with an AX200/AX201 (~$15) if Wi-Fi throughput becomes a problem. Firmware bump would be `iwlwifi-cc-a0-*` at that point.

### Bluetooth — Intel (same package as 3165)

| | |
|---|---|
| USB ID | `8087:0a2a` |
| dmesg line | `Bluetooth: hci0: Legacy ROM 2.5 revision 1.0 build 3 week 17 2014` |
| Driver | `btusb` + `btintel` |
| Firmware | **None needed** — ROM firmware already patched (`patch num: 32`) |

### Ethernet — Realtek RTL8168h/8111h Gigabit

| | |
|---|---|
| PCI ID | `10ec:8168` rev 15 |
| Driver | `r8169` |
| PHY | Generic FE-GE Realtek PHY (`realtek` module) |
| MAC | `7c:83:34:b4:1d:4c` |
| Features | Jumbo frames up to 9194, no TX checksum offload |

## Audio

| | |
|---|---|
| Controller | Intel Jasper Lake HD Audio `8086:4dc8` (`00:1f.3`) |
| Driver choice | **Legacy HDA** (`snd_hda_intel`) — simpler than SOF, no firmware blobs |
| SOF availability | `snd_sof_pci_intel_icl` / `cnl` loadable but we disable it |
| NHLT ACPI table | Present (SOF topology, unused by our config) |
| Codec | **Intel Jasperlake HDMI** (HDMI audio only — no analog codec detected on this board) |
| HDMI audio | via `snd_hda_codec_hdmi` + `SND_HDA_I915` bridge |

## Peripheral buses

| | |
|---|---|
| USB | xHCI `00:14.0` — USB 3.1 Gen 2 (10 Gbps on bus 2, 480 Mbps on bus 1) |
| SATA | AHCI `00:17.0` — 2/2 ports implemented |
| I2C (LPSS) | **6 controllers** (`00:15.0-3`, `00:19.0-1`) via `intel-lpss` + `i2c_designware_pci` |
| SMBus (i801) | `00:1f.4`, `i2c_i801` |
| UART (LPSS) | `00:1e.0` (DesignWare) |
| SPI (LPSS) | `00:1e.3` (DesignWare) |
| SPI flash | `00:1f.5` (`intel-spi` / `spi_intel_pci`) |
| eSPI | `00:1f.0` |
| PCIe root ports | `00:1c.0` (WiFi), `00:1c.5` (Ethernet) |
| Pinctrl | `pinctrl_jasperlake` |
| Management Engine | `00:16.0` (`mei_me`) |
| Thermal | `00:04.0` Dynamic Tuning (`processor_thermal_device_pci_legacy`) |
| USB-C DP alt-mode | ANX7447 retimer on I2C (handled by i915 via drm connectors) |

## What's **not** on this board

- No NVMe / M.2 NVMe slot
- No SD / MMC card reader
- No Thunderbolt / USB4
- No WWAN / cellular
- No discrete GPU
- No SPI-attached sensors (no accelerometer/gyro — it's a desktop)
- No battery / PMIC
- No touchscreen / digitizer

## Power / suspend / thermal

| | |
|---|---|
| ACPI sleep states | `S0 S3 S4 S5` — full S3 deep sleep **and** hibernate (unlike SP6 which is s2idle-only) |
| Wake-up type | `PCI PME#` (Wake-on-LAN likely available) |
| Thermal zones | `processor_thermal_device`, `x86_pkg_temp_thermal`, 5× ACPI fan power resources (`FN00`–`FN04`) |
| Fan control | BIOS/ACPI-managed (not exposed as hwmon) |
| Governor | `intel_pstate` active, HWP with EPP |
| Chassis type | 3 (desktop/tower/server) |

## dmesg ACPI noise (benign)

- `_PLD`/`_UPC` errors on `HS03/HS04/SS01/SS02` USB ports — BIOS describes phantom ports that don't physically exist. Cosmetic. Cannot be fixed without a BIOS update. Do not treat as a verify failure.

## Partition layout (Gentoo production)

```
/dev/sda                       238.5G
├─sda1  vfat   /boot/efi        600M   (EFI)
├─sda2  ext4   /boot              2G
└─sda3  ext4   /              235.9G
```

No swap partition — 4 GB zram+zstd in RAM. Weekly fstrim for SSD TRIM (no `discard` mount option — `discard=async` is btrfs-only, invalid for ext4).

## Currently-connected peripherals (harvest context only)

- Dell KB216 wired USB keyboard (`413c:2113`)
- Dell MS116 wired USB mouse (`413c:301a`)
- KTMicro USB audio device (`31b2:0010`) — incidental, not part of the machine


## Previous OS

Fedora 43 Workstation (replaced by Gentoo, first boot 2026-04-15). Fedora confirmed all core hardware works under mainline Linux.

## Firmware summary (from linux-firmware package)

Required at runtime:

| File | For |
|---|---|
| `i915/icl_dmc_ver1_09.bin` | i915 Display Microcontroller |
| `iwlwifi-7265D-*.ucode` | WiFi (keep range 26–29 for fallback) |
| `regulatory.db` + `.p7s` | CRDA regulatory domain |

Not needed (ROM-resident):

- Intel BT (`8087:0a2a`) — has ROM firmware

## Reference links

- [Intel Celeron N5095A specs (Ark)](https://www.intel.com/content/www/us/en/products/sku/212329/)
- [Jasper Lake platform overview](https://en.wikipedia.org/wiki/Jasper_Lake)
- [iwlwifi firmware matrix](https://wireless.wiki.kernel.org/en/users/drivers/iwlwifi)
