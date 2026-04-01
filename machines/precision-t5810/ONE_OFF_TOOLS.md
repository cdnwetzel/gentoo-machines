# Precision T5810 — Manual Commands & Tooling Reference

Machine: Dell Precision Tower T5810 (Xeon E5-2699 v4)

## Manual Commands

Commands run outside the prebuilt scripts during T5810 bring-up. Each is a candidate for
inclusion in harvest.sh, deep_harvest.sh, or new tooling.

### DMI / BIOS Details (candidates for harvest.sh)
```bash
# Full BIOS info (version, date, capabilities)
sudo dmidecode -t bios
# System info (product name, serial, UUID, SKU)
sudo dmidecode -t system
# Baseboard (board model, serial, chassis type)
sudo dmidecode -t baseboard
# Memory (ECC type, DIMM slots, speed, manufacturer, part numbers)
sudo dmidecode -t memory
# Processor (socket, max speed, cache handles, voltage)
sudo dmidecode -t processor
```
**Current gap**: harvest.sh Section 3 only captures Vendor/Version/Release Date/Product Name.
It misses:
- ECC type (Multi-bit ECC vs None)
- DIMM layout (populated slots, speeds, manufacturers)
- Socket type (LGA2011-3, LGA1700, etc.)
- Max CPU speed / turbo
- Chassis type name (Tower vs Laptop vs Notebook)
- Serial numbers (useful for Dell support / warranty lookup)
- Board model / revision

### BIOS Power & Performance Settings
```bash
# C-state status (if accessible)
cat /sys/devices/system/cpu/cpu0/cpuidle/state*/name
cat /sys/devices/system/cpu/cpu0/cpuidle/state*/disable
# CPU frequency scaling governor
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
# Intel pstate status
cat /sys/devices/system/cpu/intel_pstate/status
```
**Current gap**: harvest.sh doesn't capture CPU power management state.
Workstations often have C-states disabled in BIOS for performance.

## Tooling Improvements (from T5810 bring-up)

### harvest.sh
1. **Fixed GCC -march for Broadwell-EP**: Added model 79 (Xeon E5 v4), model 86 (Xeon D)
2. **Fixed GCC -march for Haswell-EP**: Added model 63 (Xeon E5 v3)
3. **Fixed GCC -march for Skylake-SP**: Added model 85 (Xeon SP)
4. **Fixed GCC -march for Ice Lake-SP**: Added model 106 (Xeon SP)

### kernel-config-template.sh
1. **Xeon CPU thread detection**: Added `/proc/cpuinfo` thread count for Xeon CPUs
2. **Desktop/workstation detection**: Added chassis_type parsing (types 3-7,17 = desktop)
3. **EDAC/ECC detection**: Added sb_edac/skx_edac/amd64_edac module detection
4. **NUMA detection**: Added for Xeon E5/E7/W and EPYC CPUs
5. **Optical drive detection**: DVD/Blu-ray → BLK_DEV_SR, ISO9660_FS, UDF_FS
6. **Conditional WiFi**: No WiFi HW → disable wireless subsystem entirely
7. **Conditional laptop features**: Battery, backlight, AC only for laptops
8. **EHCI USB 2.0**: Added USB_EHCI_HCD/PCI (older workstations have EHCI)
9. **LPSS/Pinctrl conditional**: C610/X99 doesn't use LPSS → skip LPSS/DesignWare/Pinctrl
10. **NUMA regex fix**: "Xeon(R) CPU E5" pattern matching

## Part 1/2 Known Issues

### Stage3 Auto-Discovery (part2)
Stage3 filename is hardcoded. Auto-discover latest from mirror directory listing:
```bash
LATEST=$(curl -sL "${MIRROR}/${STAGE3_DIR}/" | grep -oP 'stage3-amd64-desktop-openrc-\d{8}T\d{6}Z\.tar\.xz' | sort -u | tail -1)
```

### Scripts Assume Root (part1/part2)
Scripts use bare commands (`parted`, `mkfs`, `mount`) assuming root. Fedora live USB runs as `liveuser` with passwordless sudo. Fix: add root check at script top or prefix privileged commands with `sudo`.

### lsblk Stale Cache (part1)
After `mkfs.ext4`, `lsblk` may show old filesystem type from kernel cache. `blkid` shows the correct type. Fix: run `udevadm settle` after format, use `blkid` for verification.

### Mirror Speed (part2)
OSUOSL mirror can throttle to ~2-3 MB/s. Fix: try multiple mirrors in order or auto-select via `mirrorselect`.

### MAKEOPTS `$(nproc)` in Portage
`MAKEOPTS="-j$(nproc)"` in make.conf causes `$: bad substitution` — Portage does NOT evaluate shell commands in make.conf. Hardcode the thread count instead. `$(nproc)` in kernel_config.sh is fine (runs in bash).

## Install Script Architecture

### Pattern: Machine Config at Top, Universal Logic Below
All three install scripts (part1/part2/part3) use a **config header** pattern:
- Machine-specific values (device paths, hostname, partition sizes, tmpfs, services) at the top
- Universal logic below that references only the variables
- Conditional blocks gated by feature flags: `HAS_WIFI`, `HAS_BLUETOOTH`, `HAS_NVIDIA`, `IS_LAPTOP`, `HAS_INTEL_GPU`

### Machine-Specific vs Universal (from 9-script analysis)
**~70% universal** across all machines:
- Tool verification, GPT creation, stage3 download/verify/extract
- Pseudo-fs mounts, DNS copy, UUID extraction, fstab generation
- All 13 phases of part3 (with Phase 5, 8, 11 as main divergence points)

**~30% machine-specific** (config vars):
- Device paths, partition layout (single vs dual NVMe, EFI+boot+root vs EFI+root)
- Hostname, kernel -j count, tmpfs size
- Phase 5: WiFi (wpa_supplicant, wireless-regdb) vs wired-only
- Phase 8: laptop services (thermald, tlp, bluetooth) vs desktop
- Phase 11: GPU (NVIDIA modprobe: desktop vs Optimus), WiFi workarounds, firmware verification
- Phase 13: service check list matches Phase 8 enables

### Issues Found & Fixed
1. **Phase 13 missing service checks**: metalog, local, netmount (default), alsasound (boot) were enabled in Phase 8 but not verified in Phase 13. Fixed.
2. **No machine-specific world file**: Shared world includes WiFi/BT/laptop packages. Created T5810-specific world (no wpa_supplicant, bluez, thermald, tlp, acpilight, xfce4-power-manager).
3. **No package.accept_keywords for 6.18 LTS**: Without `=sys-kernel/gentoo-sources-6.18* ~amd64`, Portage installs whatever stable kernel is available. Created T5810-specific file.
4. **No package.use for installkernel grub**: Without `sys-kernel/installkernel grub`, future kernel updates via `make install` don't auto-run grub-mkconfig. Created T5810-specific file.
5. **NetworkManager -wifi -bluetooth USE**: Desktop workstation doesn't need WiFi/BT support compiled into NM.

## Part 3 Known Issues

### NetworkManager -wext REQUIRED_USE (Phase 5)
`net-misc/networkmanager` has `wext` USE flag enabled by default. `wext` depends on `wifi` (`wext? ( wifi )`). Disabling wifi without also disabling wext causes REQUIRED_USE failure. Fix: always use `-wifi -wext -bluetooth` together.

### ccache Warning (Phase 3 — GRUB)
`Warning: ccache requested but no masquerade dir can be found in /usr/lib*/ccache/bin` during GRUB build. Harmless — ccache symlinks not yet populated in fresh chroot.

### GRUB root= Uses Device Path Not UUID
`grub-mkconfig` uses `root=/dev/nvme0n1p3` instead of `root=UUID=...`. Works correctly — fstab uses UUID for mount.

### Passwords via chpasswd (Phase 4)
`passwd` requires interactive TTY. Use `echo "user:pass" | chpasswd` for non-interactive execution. Change default passwords on first boot.

### libwlembed gtk USE (Phase 6)
xfce4-screensaver requires `gui-libs/libwlembed[gtk]`. Add to package.use.

### Build Performance (T5810 Xeon E5-2699v4)
- **Kernel 6.18.16**: ~5 minutes at -j44
- **@world (250 packages)**: ~90 minutes with --jobs=6 --load-average=44
- **Peak load**: 42+ during LLVM and Node.js
- **Peak RAM**: ~48 GB during Node.js V8 compile; typical 6-20 GB
- **Bottleneck**: serial merge phase (portage merges one at a time)

### depclean After @world
41 packages depcleaned — mostly LLVM/clang build deps, Qt5/Qt6 libs, KDE frameworks pulled in transitively.

### dispatch-conf on First Boot
After @world, emerge warns about config files needing updates. Run `dispatch-conf` on first boot to merge cleanly.

## First Boot Checklist
1. Change passwords: `passwd root`, `passwd chris` (both default "gentoo")
2. `dispatch-conf` — merge `/etc/sudoers` and other config updates
3. `eselect news read`
4. `nvidia-smi` — verify both GTX 1050 Ti GPUs
5. `ip addr` — verify Intel I217-LM Ethernet (e1000e)
6. `xrandr` — verify display output
7. `pactl info | grep "Server Name"` — verify PipeWire
8. `swapon --show` — verify 16GB zram
9. `edac-util -s` — verify ECC memory reporting (sb_edac)
10. `cpuid2cpuflags` — verify CPU_FLAGS_X86 in make.conf
11. `bash ~/gentoo-machines/shared/restore-desktop.sh` — XFCE keybindings, panels, displays
12. `tools/update-system.sh verify` — comprehensive post-boot validation

## NVIDIA Driver Issues (First Boot)

### kernel-open vs Proprietary
nvidia-drivers built with `kernel-open` USE flag failed: Pascal GPUs "not included". `kernel-open` only supports Turing (RTX 2000+) and newer. Fix: `-kernel-open` in machine-specific package.use.

### NVIDIA 590+ Drops Pascal
Driver 590.x dropped Pascal (GTX 10xx), Maxwell (GTX 900), and Volta entirely. The **580.xx series** is the last branch supporting Pascal (security patches through October 2028). Fix: mask `>=x11-drivers/nvidia-drivers-581`.

### Portage package.use File Ordering
Portage processes `/etc/portage/package.use/*` files in **alphabetical order**. `shared` sorts after `precision-t5810`, so shared overrides machine-specific flags. **Rule**: never put USE flags that vary between machines in the shared file.

### ccache Permissions
`/var/cache/ccache/tmp/` was mode `2755` (not group-writable). Portage sandbox runs as `portage` user. Fix: `chmod 2775 /var/cache/ccache/tmp`.

## GPU Upgrade Plan
- **Current**: 2x GTX 1050 Ti (4 GB each, compute 6.1, Pascal GP107) — PCIe 3.0 x16
- **Planned**: 1x RTX A1000 8GB (Ampere GA107, compute 8.6, ~70W) — hand-me-down from Precision 7960
  - 7960 upgrade: RTX 5080 16GB (Blackwell) replaces the A1000 alongside RTX PRO 6000 96GB
  - A1000 moves to T5810 as sole GPU for dev/test inference
- **Power budget**: 825W PSU — Xeon ~145W + A1000 ~70W + system ~80W = ~295W (abundant headroom)
- **Future options** (after A1000 proves out):
  - 1-2 more RTX A1000 8GB for multi-GPU inference via PCIe
  - Ideal: 2x RTX A4500 20GB (Ampere) with NVLink bridge — 40GB unified VRAM, ~400W total (fits 825W PSU)
- **Driver migration**: 580.xx legacy (Pascal) → 595.x+ current branch (Ampere)
  - Removes: `=x11-drivers/nvidia-drivers-580* ~amd64` keyword, `>=581` mask
  - Adds: current nvidia-drivers (~amd64), `kernel-open` USE flag (Turing+ support)
  - Cannot mix Pascal + Ampere — GTX 1050 Ti cards must be removed before driver upgrade
- **Previous candidates** (superseded): RTX 3060 12GB, RTX 3060 Ti 8GB, RTX 4060 Ti 16GB, RTX 5060 Ti 16GB, RTX 5080 16GB
