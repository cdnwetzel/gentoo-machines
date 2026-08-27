# Dell XPS 15 9510 - Hardware Reference

**Current OS**: Gentoo Linux (production)

## System Overview

| Field | Value |
|-------|-------|
| **Product** | Dell XPS 15 9510 |
| **Board** | Dell 0A61 |
| **BIOS** | 1.43.0 (10/27/2025) |
| **CPU** | 11th Gen Intel Core i7-11800H (Tiger Lake-H) |
| **Cores** | 8C/16T (uniform architecture, AVX-512) |
| **RAM** | 32GB DDR4-3200 (2x16GB) |
| **Architecture** | x86_64 |

## CPU Features

Key flags: `vmx avx avx2 avx512f avx512dq avx512bw avx512vl avx512_vnni aes sha_ni`

Notable: **Full AVX-512** support (Tiger Lake), ideal for ML inference workloads

## PCI Devices

| BDF | Device | PCI ID | Driver |
|-----|--------|--------|--------|
| 00:00.0 | Tiger Lake-H Host Bridge | `[8086:9a36]` | - |
| 00:01.0 | PCIe Controller #1 | `[8086:9a01]` | pcieport |
| 00:01.2 | PCIe Controller #3 | `[8086:9a07]` | pcieport |
| 00:02.0 | TigerLake-H GT1 [UHD Graphics] | `[8086:9a60]` | i915 |
| 00:04.0 | Dynamic Tuning Processor | `[8086:9a03]` | proc_thermal |
| 00:06.0 | PCIe Controller #0 | `[8086:9a0f]` | pcieport |
| 00:07.0 | TB4 PCIe Root Port #2 | `[8086:9a2f]` | pcieport |
| 00:07.3 | TB4 PCIe Root Port #3 | `[8086:9a31]` | pcieport |
| 00:0a.0 | Telemetry Aggregator | `[8086:9a0d]` | - |
| 00:0d.0 | TB4 USB Controller | `[8086:9a17]` | xhci_hcd |
| 00:0d.3 | TB4 NHI #1 | `[8086:9a21]` | thunderbolt |
| 00:12.0 | Integrated Sensor Hub | `[8086:43fc]` | intel_ish_ipc |
| 00:14.0 | USB 3.2 Gen 2x1 xHCI | `[8086:43ed]` | xhci_hcd |
| 00:14.3 | Tiger Lake PCH CNVi WiFi (AX203) | `[8086:43f0]` | iwlwifi |
| 00:15.0 | Serial IO I2C #0 | `[8086:43e8]` | intel-lpss |
| 00:15.1 | Serial IO I2C #1 | `[8086:43e9]` | intel-lpss |
| 00:16.0 | HECI/MEI Controller | `[8086:43e0]` | mei_me |
| 00:1c.0 | PCIe Root Port #7 | `[8086:43be]` | pcieport |
| 00:1f.0 | WM590 LPC/eSPI Controller | `[8086:4389]` | - |
| 00:1f.3 | Tiger Lake-H HD Audio | `[8086:43c8]` | snd_hda_intel |
| 00:1f.4 | SMBus Controller | `[8086:43a3]` | i801_smbus |
| 00:1f.5 | SPI Controller | `[8086:43a4]` | intel-lpss |
| 01:00.0 | GeForce RTX 3050 Ti Mobile | `[10de:25a0]` | nvidia |
| 02:00.0 | Samsung 990 PRO NVMe (1TB) | `[144d:a80c]` | nvme |
| 03:00.0 | Samsung 990 PRO NVMe (1TB) | `[144d:a80c]` | nvme |
| 76:00.0 | Realtek RTS5260 Card Reader | `[10ec:5260]` | rtsx_pci |

## Networking

- **WiFi**: Intel Wi-Fi 6 AX203 CNVi (`iwlwifi` driver, `QuZ-a0-hr-b0` firmware)
- **Bluetooth**: Intel AX201 (`btusb`/`btintel` drivers)
- **Wired**: None built-in (USB Ethernet adapter or TB4 dock)

## Storage

- **NVMe 0**: Samsung 990 PRO 1TB (`nvme` driver). Gentoo root
- **NVMe 1**: Samsung 990 PRO 1TB (`nvme` driver), data
- **Card Reader**: Realtek RTS5260 (`rtsx_pci` driver)
- **Layout**:
  - `/boot/efi` - 512M (vfat, nvme0n1p1)
  - `/` - 915G (ext4, nvme0n1p2, label GENTOO)
  - `/data` - 931G (ext4, nvme1n1p1, label DATA)
  - `/tmp` - 8G (tmpfs)

## Audio

- **Controller**: Tiger Lake-H HD Audio `[8086:43c8]`
- **Driver**: `snd_hda_intel` (HDA, NOT Sound Open Firmware)

## Graphics

- **iGPU**: Intel TigerLake-H GT1 UHD Graphics `[8086:9a60]`
  - **Driver**: `i915` (module)
  - **Firmware**: `i915/tgl_dmc_ver2_12.bin`, `tgl_guc_70.1.1.bin`
  - **Features**: VAAPI hardware acceleration
- **dGPU**: NVIDIA GeForce RTX 3050 Ti Mobile `[10de:25a0]` (GA107M, 4GB GDDR6)
  - **Driver**: `nvidia` 595.58.03 (proprietary)
  - **Features**: CUDA 8.6 (Ampere), PRIME/Optimus
  - **Use case**: AI/ML inference, CUDA compute

## Camera

- **Webcam**: Microdia Integrated_Webcam_HD (USB `0c45:672e`)
- **Type**: USB UVC (standard Video4Linux, no IPU6 needed)

## Biometrics

- **Fingerprint**: Goodix USB2.0 MISC (`27c6:63ac`) — Match-on-Chip, `goodixmoc`
  driver in `sys-auth/libfprint`

The identical sensor runs on the arch-machines XPS 13 9315, where fingerprint
`sudo` works, so the hardware and the PAM approach are both proven. What is not
proven here is the Gentoo package version:

| | libfprint | 27c6:63ac |
|---|---|---|
| arch-machines xps-9315 | 1.94.100 | works |
| Gentoo stable | 1.94.7 | reported broken — `Corrupted message header received` on enroll |
| Gentoo `~amd64` | 1.94.10 | untested on this PID |

The 1.94.7 failure is a goodixmoc protocol mismatch introduced when 63AC was
added to the driver's PID table. Dell's Touch OEM Driver blob does not help —
it covers only the Goodix 53xc family — so keep `USE=-tod`, which is what
`shared/package.use` sets.

`machines/xps-9510/package.accept_keywords` therefore takes `sys-auth/libfprint
~amd64` to get 1.94.10 rather than the implicated stable. If enrollment still
fails, the known-good 1.94.100 is not yet in `::gentoo` and would need a local
ebuild.

Setup, once enrolled: `sudo bash shared/fingerprint-setup.sh` — see that script
for why it touches `/etc/pam.d/sudo` only and never `system-auth`.

## Thunderbolt / USB-C

- **Thunderbolt 4**: Dual USB-C ports with DisplayPort Alt Mode
- **USB 3.2 Gen 2x1**: Intel Tiger Lake-H PCH xHCI `[8086:43ed]`

### USB-C Hub Support

Tested with Anker 7-in-1 USB-C Hub (4K@60Hz HDMI, 85W PD, 3xUSB-A 3.0, USB-C 3.0, SD/TF):

| Feature | Driver | Config |
|---------|--------|--------|
| HDMI (DP Alt Mode) | i915 + thunderbolt | Built-in |
| PD pass-through | ucsi_acpi | Built-in |
| USB-A/C 3.0 data | xhci_hcd | Built-in |
| SD/TF card reader | usb-storage, rtsx_usb | Module |
| USB Ethernet (RTL8153) | r8152 | Module |
| USB Ethernet (ASIX) | ax88179_178a | Module |
| USB Ethernet (CDC) | cdc_ether, cdc_ncm | Module |

## Remote Access

SSTP VPN via `sstpc` + `pppd` with NetworkManager (`networkmanager-sstp` plugin).

| Setting | Value |
|---------|-------|
| **Kernel deps** | `CONFIG_PPP=m`, `PPP_MPPE=m`, `PPP_ASYNC=m` (+ related PPP modules) |
| **Device node** | `/dev/ppp`, auto-created by udev from `ppp_generic` module alias |

Connection profiles (server, credentials, DNS) are stored in NetworkManager and not committed to this repo.

## Platform-Specific

- **Integrated Sensor Hub**: Intel ISH `[8086:43fc]` (`intel_ish_ipc`)
- **Dell Platform Drivers**: DELL_LAPTOP, DELL_WMI, DELL_SMBIOS, DELL_WMI_SYSMAN, DELL_WMI_DDV, DELL_PC
- **Thermal**: Intel Dynamic Tuning `[8086:9a03]`

### BIOS Settings from Linux (`dell_wmi_sysman`)

Dell BIOS settings are readable and writable from the running OS. 117 attributes
under `/sys/class/firmware-attributes/dell-wmi-sysman/attributes/`, `current_value`
is root-only (0600). Most changes take effect on the next boot.

```bash
sudo grep . /sys/class/firmware-attributes/dell-wmi-sysman/attributes/{PrimaryBattChargeCfg,CustomChargeStart,CustomChargeStop,ThermalManagement}/current_value
```

| Attribute | Values | Notes |
|-----------|--------|-------|
| `PrimaryBattChargeCfg` | Adaptive / Standard / Express / PrimAcUse / Custom | default Adaptive; **Custom** in use here |
| `CustomChargeStart` | 50-95 | only writable when `PrimaryBattChargeCfg=Custom` |
| `CustomChargeStop` | 55-100 | only writable when `PrimaryBattChargeCfg=Custom` |
| `AdvBatteryChargeCfg` | Disabled / Enabled | leave Disabled, conflicts with Custom |
| `ThermalManagement` | Optimized / Cool / Quiet / UltraPerformance | default Optimized |

No BIOS password is set (`authentication/{Admin,System}/is_enabled = 0`), so writes
are accepted directly. If an admin password is ever set, it must first be written to
`authentication/Admin/current_password` in the same session or every attribute write fails.

### Battery Extensions (`dell_wmi_ddv`)

Registers two ACPI battery hooks and an hwmon node (`dell_ddv`) exposing per-zone
temps (CPU, SODIMM, Ambient x4, Video, HDD) and both fan tachometers.
`cycle_count` reads 0 — Dell does not report cycle count through this path.

## Firmware (loaded from /lib/firmware/)

| File | Purpose |
|------|---------|
| `i915/tgl_dmc_ver2_12.bin` | Tiger Lake Display Microcontroller |
| `i915/tgl_guc_70.1.1.bin` | Tiger Lake GuC |
| `iwlwifi-QuZ-a0-hr-b0-77.ucode` | Intel AX203 WiFi firmware |
| `intel/ibt-20-*.sfi` | Intel Bluetooth firmware |
| `intel/ibt-20-*.ddc` | Intel Bluetooth DDC configuration |

## Software Environment

### Development Tools

| Tool | Version | Notes |
|------|---------|-------|
| VS Code | 1.109.4 | Primary IDE |
| Geany | 2.1 | Lightweight editor |
| Git | System | SSH key auth to GitHub |
| Node.js | 24.11.1 | System package |
| nvm | Installed | `~/.nvm`, manages Node versions |
| npm | 11.6.2 | Via system Node |

### Python / AI / ML / NLP

| Package | Version | Notes |
|---------|---------|-------|
| Python | 3.13.11 | System (`PYTHON_SINGLE_TARGET`) |
| pip | 25.3 | System |
| Virtual env | `~/venvs/ml/` | All ML packages here |
| PyTorch | 2.10.0+cu126 | CUDA-enabled |
| transformers | 5.2.0 | Hugging Face |
| sentence-transformers | 5.2.3 | Embeddings |
| langchain | 1.2.10 | + community, core |
| chromadb | 0.3.11 | Vector store |
| faiss-cpu | 1.13.2 | Similarity search |
| openai | 2.21.0 | API client |
| pandas | 3.0.1 | Data processing |
| numpy | 2.4.2 | Numerical computing |
| scikit-learn | 1.8.0 | ML toolkit |
| jupyter / jupyterlab | 4.5.4 | Notebooks |

### Database / ODBC

| Component | Version | Notes |
|-----------|---------|-------|
| unixODBC | 2.3.12 | ODBC driver manager |
| MSSQL ODBC Driver | 18 | `/opt/microsoft/msodbcsql*` |
| pyodbc | 5.3.0 | Python ODBC (in ML venv) |

### NVIDIA / CUDA

| Component | Version |
|-----------|---------|
| nvidia-drivers | 595.71.05 |
| CUDA Version | 13.1 |
| GPU | RTX 3050 Ti Mobile (GA107M, 4GB GDDR6) |

### AI/ML Verifier Role

The XPS 9510 runs an always-on Ollama HTTP service serving verifier models.
Bigger AI nodes call into it for cheap, independent second-opinion checks
(LLM-as-judge, schema validation, grounding/citation checks). Docked
clamshell, lid-close-docked=ignore keeps it reachable around the clock.

| Component | Value |
|-----------|-------|
| Runtime | Ollama (upstream binary at `/usr/local/bin/ollama`) |
| Default verifier model | `qwen2.5:7b-instruct-q4_K_M` (~4.7 GB), used by `tools/verify-panel.py` per the v2 calibration; closes semantic-recall gaps the 3B couldn't (see `tools/verify-panel-fixtures/CALIBRATION.md`) |
| Fallback / speed model | `qwen2.5:3b-instruct-q4_K_M` (~1.9 GB), fits VRAM entirely, ~7× faster, lower semantic recall, Set `VERIFY_MODEL=qwen2.5:3b-instruct-q4_K_M` to use. |
| Model storage | `/data/ml-models/ollama/` (second 990 PRO NVMe) |
| Listen address | `0.0.0.0:11434` (firewall-gated) |
| Allowed peers | precision-t5810 (LAN, primary), asrock-b550 (LAN), precision-7960 (VPN-only) |
| Verification harness | `tools/verify-panel.py`, 4-check panel (entity_fidelity, pii_leak hybrid regex+LLM, citation_format pure-regex, claim_grounding decomposed), Calibration fixtures + decision history in `tools/verify-panel-fixtures/CALIBRATION.md`. |
| Service config | `ollama.confd` + `ollama.initd` (OpenRC) |
| Firewall | `nftables-ollama.nft` → `/etc/nftables/ollama.nft` |
| Power envelope | RAPL PL1=35W / PL2=60W (`powercap-profile.sh`) |
| Verifier client | `tools/verify-llm.sh` (callable from any peer) |
| Baseline numbers | `INFERENCE_BASELINE.md` |

Quick health check from any peer (after adding `10.0.1.51 xps9510` to `/etc/hosts`):
```bash
curl -s http://xps9510:11434/api/tags | jq '.models[].name'
```

Quick verifier round-trip:
```bash
echo "1+1 = 3" | tools/verify-llm.sh --task fact-check
# expect: exit 1, verdict "fail"
```

## Performance Tuning

### Kernel Optimizations
- **NR_CPUS=16**, matches actual 8C/16T (reduced from default 64, saves memory)
- **Transparent Huge Pages**, enabled (always), reduces TLB misses for large ML workloads
- **MGLRU (LRU_GEN)**, multi-gen LRU for better page reclaim under memory pressure
- **KSM**. Kernel Same-page Merging, deduplicates memory across ML model instances
- **HZ=1000**, low-latency timer for responsive desktop
- **PREEMPT_VOLUNTARY**, good balance of throughput and interactivity
- **zram with zstd**, compressed swap backend (better ratio than lzo-rle)

### VM / Sysctl Tuning (`sysctl-performance.conf`)
- **vm.swappiness=10**, prefer RAM over swap (32GB is plenty)
- **vm.dirty_ratio=40**, batch NVMe writes for throughput
- **vm.vfs_cache_pressure=50**, keep filesystem caches longer
- **TCP tuning**, larger buffers, fast open enabled

### Power / Thermal
- **thermald**. Intel thermal daemon, prevents throttling during sustained loads
- **tlp**, automatic power profiles (performance on AC, powersave on battery)
- **zram-init**, 8GB zstd-compressed swap as safety net for large model loads

#### Battery Charge Thresholds (`tlp.conf`) — 75 / 80

```
START_CHARGE_THRESH_BAT0=75
STOP_CHARGE_THRESH_BAT0=80
```

Charging stops at 80% and does **not** resume until the pack drops below 75%.
Verify live state (no root needed):

```bash
cat /sys/class/power_supply/BAT0/charge_control_{start,end}_threshold   # 75, 80
cat /sys/class/power_supply/BAT0/charge_types                           # ... [Custom]
```

**TLP owns this setting, not BIOS.** `tlp` writes the thresholds through
`dell_laptop` -> `dell_smbios` -> EC, which is the same knob as BIOS
*Battery Configuration = Custom*. TLP re-asserts on every run and every AC
transition, so a value set by hand in BIOS gets silently overwritten. Edit
`/etc/tlp.conf` and run `sudo tlp start`; do not edit it in BIOS.

**Expected behaviour, not a fault:** on AC at any charge level between the two
thresholds the battery reads `Discharging` / not charging. This is the hysteresis
band doing its job. Previously configured 50/80, which meant the pack could idle
near 50% indefinitely.

Why 75/80 rather than the usual 50/80: this is an always-on AC node, and the pack
is worn (see below), so a 50% floor left only ~25 Wh of real runtime on a power
cut. At an 80% ceiling the longevity benefit is already banked; the extra top-up
cycles inside a 5% band are negligible.

Alternative if EC-level enforcement is wanted independent of whether TLP is
running: set `PrimaryBattChargeCfg=PrimAcUse` via `dell_wmi_sysman` **and** remove
both `*_CHARGE_THRESH_BAT0` lines from `tlp.conf`. Do not do both — they fight.

#### Battery Health

| Metric | Value (2026-08-25) |
|--------|--------------------|
| Model | SMP DELL 70N2F95, Li-poly, mfg 2021-06 |
| `energy-full` | 57.10 Wh |
| `energy-full-design` | 84.29 Wh |
| Health | **67.7%** |
| Usable ceiling at 80% cap | ~45.7 Wh (~54% of design) |

A third of design capacity is gone. Combined with the 80% cap, plan runtime
against ~45 Wh, not the 84 Wh nameplate. Re-check with `upower -i /org/freedesktop/UPower/devices/battery_BAT0`.

### Storage
- **I/O scheduler**: `none` (direct NVMe, no software scheduling overhead)
- **Dual 990 PRO**: root on nvme0n1, data on nvme1n1, parallel I/O for builds + data

## Key Differences from XPS 9315

| Feature | XPS 9510 | XPS 9315 |
|---------|----------|----------|
| CPU | i7-11800H (Tiger Lake-H, 8C/16T) | i5-1230U (Alder Lake, 2P+8E/12T) |
| GPU | Intel UHD + NVIDIA RTX 3050 Ti | Intel Iris Xe only |
| WiFi | AX203 (`8086:43f0`, QuZ firmware) | AX211 (`8086:51f0`, so firmware) |
| Audio | HDA (`snd_hda_intel`) | SOF (`sof-audio-pci-intel-tgl`) |
| RAM | 32GB DDR4-3200 | 8GB |
| Storage | 2x Samsung 990 PRO 1TB | 1x Phison PS5019 |
| AVX-512 | Yes (full support) | No (fused off on Alder Lake) |
| Camera | USB UVC (no IPU6) | IPU6 ISP |
