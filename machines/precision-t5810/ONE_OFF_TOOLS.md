# Precision T5810 - One-Off Commands & Tooling Candidates

Session date: 2026-03-11
Machine: Dell Precision Tower T5810 (Xeon E5-2699 v4, Fedora 43 live USB)

## Manual Commands Run (outside prebuilt scripts)

These commands were run manually during this session. Each is a candidate for
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

## Tooling Improvements Made This Session

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

## Tooling Candidates for Future Work

### harvest.sh Enhancements
- [ ] **Section 3 expansion**: Full `dmidecode -t bios/system/baseboard/processor/memory`
  - ECC type, DIMM layout, socket type, max turbo speed
  - Board model/revision for Dell support
  - SMBIOS version
- [ ] **Section 16: BIOS Power Config**: C-state status, CPU governor, pstate mode
  - Critical for workstation vs laptop distinction
- [ ] **Section 17: CPU Topology**: NUMA nodes, cache hierarchy, socket count
  - `lscpu --extended` output
  - `/sys/devices/system/node/` enumeration
- [ ] **Boot media exclusion**: Detect and flag Ventoy/live USB drives
  - By device ID, by VTOYEFI label, by lack of Linux partition
  - Add `# BOOT MEDIA — EXCLUDE FROM INSTALL` annotation in storage section

### deep_harvest.sh Enhancements
- [ ] **NVIDIA GPU details**: `nvidia-smi -q` if proprietary driver loaded, or parse PCI subsystem vendor
- [ ] **Firmware loading from sysfs**: When dmesg rotates, try `/sys/class/firmware/` and
  `find /sys -name 'loading' 2>/dev/null` to identify firmware in use

### kernel-config-template.sh Enhancements
- [ ] **Power profile**: Detect workstation (no battery, chassis tower) → default GOV_PERFORMANCE
  Currently requires manual edit. Template should auto-detect.
- [ ] **Multi-GPU**: Detect count of NVIDIA GPUs, note in kernel_config.sh header
- [ ] **SATA vs NVMe boot**: Auto-determine which is the boot drive from harvest data

### New Tool Candidates
- [ ] **bios-harvest.sh**: Dedicated BIOS/UEFI settings dump (dmidecode all types)
  - More detail than harvest.sh section 3 can hold
  - Could include `efivar --list` on EFI systems
  - Power/thermal settings, virtualization features, boot order
- [x] **install-part1 safety**: Ventoy/boot media auto-exclusion in all `gentoo_install_part1.sh`
  - Match by device unique ID or VTOYEFI label
  - Hard-fail if target device has VTOYEFI partition
  - **Implemented in T5810 part1**: 3-layer protection (udevadm ID check, lsblk model scan, NVMe-only gate)

## Part 1/2 Execution Learnings (2026-03-11)

Issues encountered running part1 and part2 on the T5810:

### Stage3 Auto-Discovery (part2)
- **Problem**: Stage3 filename is hardcoded (`stage3-amd64-desktop-openrc-20260222T170100Z.tar.xz`). We had to manually `curl` the mirror listing to find the latest (20260308).
- **Fix candidate**: Auto-discover latest stage3 from mirror directory listing:
  ```bash
  LATEST=$(curl -sL "${MIRROR}/${STAGE3_DIR}/" | grep -oP 'stage3-amd64-desktop-openrc-\d{8}T\d{6}Z\.tar\.xz' | sort -u | tail -1)
  ```
- [ ] **TODO**: Add auto-discovery to all part2 scripts (or create shared function)

### Scripts Assume Root (part1/part2)
- **Problem**: Scripts use bare commands (`parted`, `mkfs`, `mount`) assuming they run as root. Fedora live USB runs as `liveuser` with passwordless sudo, so every command needs `sudo` prefix.
- **Problem**: `read -p` interactive prompts don't work through automation tools — had to run steps manually.
- **Fix candidate**: Add `sudo` prefix to all privileged commands, or add a root check at the top:
  ```bash
  [[ $EUID -ne 0 ]] && { echo "Run with sudo or as root."; exit 1; }
  ```
- **Fix candidate**: Add `--yes` or `--non-interactive` flag to skip `read -p` prompts when running via automation.
- [ ] **TODO**: Standardize root handling across all install scripts

### lsblk Stale Cache (part1)
- **Problem**: After `mkfs.ext4`, `lsblk` still shows old `btrfs`/`fedora` from kernel cache. `blkid` shows the correct `ext4`. Confusing but harmless.
- **Fix candidate**: Run `sudo blockdev --rereadpt /dev/nvme0n1` or `udevadm settle` after format, then use `blkid` for verification instead of `lsblk -o FSTYPE`.
- [ ] **TODO**: Add post-format `blkid` verification to part1 scripts

### Mirror Speed (part2)
- **Problem**: OSUOSL mirror throttled to ~2-3 MB/s for 703MB stage3 download.
- **Fix candidate**: Try multiple mirrors in order, or auto-select fastest via `mirrorselect`:
  ```bash
  MIRRORS=("https://gentoo.osuosl.org" "https://mirrors.rit.edu/gentoo" "https://mirror.leaseweb.com/gentoo")
  ```
- [ ] **TODO**: Add mirror fallback or speed test to part2 scripts

### Sudo ls on /root (part2)
- **Problem**: Final `ls -la "$STAGING/"` fails because `/root` is mode 700. Need `sudo ls`.
- [ ] **TODO**: Add `sudo` to verification `ls` commands in part2

### MAKEOPTS `$(nproc)` Broken in Portage (part3 / make.conf)
- **Problem**: `MAKEOPTS="-j$(nproc) -l44"` in make.conf causes portage error: `$: bad substitution`. Portage does NOT evaluate shell commands in make.conf — only `bash` does.
- **Fix**: Hardcode thread count: `MAKEOPTS="-j44 -l44"`. Fixed in make.conf and on VTOYEFI.
- **Impact**: All make.conf files in the repo should be checked. The kernel_config.sh `$(nproc)` is fine because that runs in bash.
- [ ] **TODO**: Audit all machines' make.conf for `$(nproc)` usage. Add validation to generate-config.sh.

### Claude Code Auto-Backgrounding Long Commands (part3)
- **Problem**: Claude Code auto-backgrounds commands that take >2 minutes with a 10-minute timeout. `emerge @world` can take 20-60+ minutes — auto-background kills it silently.
- **Workaround**: Run emerge in a background shell with output redirected to a log file, then poll the log:
  ```bash
  sudo chroot /mnt/gentoo /bin/bash -c 'emerge ... > /tmp/emerge.log 2>&1' &
  # Monitor: sudo tail -f /mnt/gentoo/tmp/emerge.log
  ```
- **Problem**: Multiple retries spawned **3 concurrent emerge processes** competing for portage locks. Had to `kill -9` duplicates.
- **Log buffering**: emerge output to file has ~16-second buffer delay. The log mtime is accurate but `tail` shows stale content. Use `sudo find ... -newer` or `stat --format=%Y` to verify liveness.
- **Lesson**: For long-running chroot commands, ALWAYS use the redirect-to-logfile pattern from the start. Never retry without checking if the previous process is still running first.
- [ ] **TODO**: Add process-check helper to part3 that verifies no existing emerge is running before starting a new one

## Install Script Generalization Learnings

Session: 2026-03-11 (install scripts)

### Pattern: Machine Config at Top, Universal Logic Below
All three install scripts (part1/part2/part3) now use a **config header** pattern:
- Machine-specific values (device paths, hostname, partition sizes, tmpfs, services) at the top
- Universal logic below that references only the variables
- Conditional blocks gated by feature flags: `HAS_WIFI`, `HAS_BLUETOOTH`, `HAS_NVIDIA`, `IS_LAPTOP`, `HAS_INTEL_GPU`

### What's Machine-Specific vs Universal (from 9-script analysis)
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

### Issues Found & Fixed During Review
1. **Phase 13 missing service checks**: metalog, local, netmount (default), alsasound (boot) were enabled in Phase 8 but not verified in Phase 13. Fixed.
2. **No machine-specific world file**: Shared world includes WiFi/BT/laptop packages. Created T5810-specific world (no wpa_supplicant, bluez, thermald, tlp, acpilight, xfce4-power-manager).
3. **No package.accept_keywords for 6.18 LTS**: Without `=sys-kernel/gentoo-sources-6.18* ~amd64`, Portage installs whatever stable kernel is available. Created T5810-specific file.
4. **No package.use for installkernel grub**: Without `sys-kernel/installkernel grub`, future kernel updates via `make install` don't auto-run grub-mkconfig. Created T5810-specific file.
5. **NetworkManager -wifi -bluetooth USE**: Desktop workstation doesn't need WiFi/BT support compiled into NM.

## Part 3 Execution Learnings (2026-03-11)

Issues encountered running part3 phases inside the chroot:

### NetworkManager -wext REQUIRED_USE (Phase 5)
- **Problem**: `net-misc/networkmanager` has `wext` USE flag enabled by default. `wext` depends on `wifi` (`wext? ( wifi )`). Our package.use had `-wifi -bluetooth` but not `-wext`, causing REQUIRED_USE failure.
- **Fix**: Add `-wext` to NetworkManager package.use line: `net-misc/networkmanager -wifi -wext -bluetooth`
- **Impact**: All wired-only machines need `-wext` when disabling wifi. Updated package.use in repo, chroot, and VTOYEFI.
- [ ] **TODO**: Update part2 script template to always include `-wext` with `-wifi` for NetworkManager

### ccache Warning (Phase 3 - GRUB)
- **Observation**: `Warning: ccache requested but no masquerade dir can be found in /usr/lib*/ccache/bin` during GRUB build. Harmless — ccache symlinks not yet populated in fresh chroot. ccache works once more packages are built.

### GRUB root= Uses Device Path Not UUID
- **Observation**: `grub-mkconfig` uses `root=/dev/nvme0n1p3` instead of `root=UUID=...` in the boot entry. This is because the chroot's `/etc/fstab` has the UUID but GRUB's os-prober detects the device path. Works fine — fstab uses UUID for mount so root mounts correctly.
- **Fix candidate**: Could add `GRUB_DEVICE_UUID=true` or manually set `GRUB_CMDLINE_LINUX="root=UUID=..."` but not necessary.

### Passwords via chpasswd (Phase 4)
- **Observation**: `passwd` requires interactive TTY input which doesn't work through automation. Used `echo "user:pass" | chpasswd` instead. Shows "Weak password" warning but works. Both root and chris set to "gentoo" — must change on first boot.
- **Fix candidate**: Part3 should use `chpasswd` instead of `passwd` for non-interactive execution, or detect non-interactive mode and switch automatically.

### libwlembed gtk USE (Phase 6)
- **Problem**: xfce4-screensaver requires `gui-libs/libwlembed[gtk]` for Wayland support. Not in shared or machine-specific package.use.
- **Fix**: Added `gui-libs/libwlembed gtk` to package.use. Updated repo, chroot, and VTOYEFI.
- [ ] **TODO**: Add this to shared/package.use if other XFCE machines hit the same dep

### LLVM Compile Time & CPU Saturation
- **Observation**: LLVM 21.1.8 is the single biggest bottleneck in @world — ~10-15 minutes at -j44. All 44 cores at 100% during compile, ~20 GB RAM. The 86+ merge queue built up behind it, then drained rapidly when LLVM finished.
- **Node.js** was the second bottleneck — ~10 minutes, peaked at 48 GB RAM compiling V8.
- **Total @world**: 250 packages in ~90 minutes on 22C/44T Xeon with --jobs=6. Load hit 42+ during LLVM/Node.js.
- **Merge queue pattern**: compile burst → merge drain → compile burst. Portage merges are serial (one at a time) but compiles run 6-wide.

### depclean After @world (Phase 6 follow-up)
- **Observation**: 41 packages depcleaned after @world — mostly LLVM/clang build deps, Qt5/Qt6 libs, and KDE frameworks that were pulled in transitively but not needed by any world package.
- **Fix candidate**: Part3 should include `emerge --depclean` after Phase 6 and `emerge @preserved-rebuild` verification.

### Deep Sanity Check (Phase 13 enhancement)
- **Observation**: Phase 13 basic checks passed, but a deeper 13-section check caught a false positive on preserved libs (grep for "Nothing to merge" vs "Total: 0 packages"). Real result: 0 failures, 0 warnings.
- **Sections checked**: kernel+boot, filesystem+UUIDs, 18 critical packages, 11 services, user+auth, display+desktop, NVIDIA (5 checks), networking (3 checks), portage+build (6 checks), local.d scripts, sysctl, timezone+locale, preserved libs.
- [ ] **TODO**: Integrate deep sanity check into part3 as a replacement for the simpler Phase 13

### Build Performance Notes (T5810 Xeon E5-2699v4)
- **Kernel 6.18.16**: ~5 minutes at -j44 (defconfig + 26-phase kernel_config.sh + olddefconfig)
- **@world (250 packages)**: ~90 minutes with --jobs=6 --load-average=44
- **Peak load**: 42+ (all 44 threads at 100%) during LLVM and Node.js
- **Peak RAM**: ~48 GB during Node.js V8 compile; typical 6-20 GB for most packages
- **128 GB tmpfs**: never stressed — biggest single package (LLVM) uses ~20 GB tmpfs
- **256 GB RAM**: 213+ GB free even at peak. Machine has massive headroom for --jobs=8 or --jobs=10.
- **Bottleneck**: serial merge phase (portage can only merge one package at a time). Compile parallelism is excellent.

### GPU Upgrade Considerations
- **Current**: 2x GTX 1050 Ti (4 GB each, compute 6.1, Pascal) — PCIe 3.0 x16
- **T5810 PSU**: 825W, 225W per PCIe slot
- **Candidates evaluated**:
  - RTX 3060 12GB ($449 each, 2-slot, 170W) — good VRAM, older arch
  - RTX 3060 Ti 8GB ($400 each, 2-slot, 200W) — better compute, less VRAM
  - RTX 4060 Ti 16GB ($539-599, 2-slot, 160W) — best $/VRAM, Ada arch
  - RTX 5060 Ti 16GB ($476-579, 2.5-slot, ~150W) — newest arch but 2.5-slot clearance issue
- **2.5-slot cards**: may not fit dual in T5810 — need to measure physical slot spacing
- **Single 4060 Ti 16GB** at $539-599 may be the best single-card upgrade path

### dispatch-conf Needed on First Boot
- **Problem**: After @world, emerge warned: `IMPORTANT: config file '/etc/sudoers' needs updating`. We did NOT run `dispatch-conf` in the chroot.
- **Risk**: Our Phase 4 appended `%wheel ALL=(ALL) ALL` via `echo >>`. The emerge-installed sudoers update might conflict or duplicate. On first boot, run `dispatch-conf` to merge config updates cleanly.
- **Also**: 27 news items unread (`eselect news read`).
- [ ] **TODO**: Add `dispatch-conf --auto` or `etc-update` step to part3 after Phase 6

### Services Already in Default Runlevel from Stage3
- **Observation**: Phase 8 reported `local` and `netmount` as "already installed in runlevel default" — stage3 or early emerge added them. Not a problem (rc-update is idempotent) but shows that part3 Phase 8 has redundant `rc-update add` calls for these.
- **Implication**: The phase is safe to re-run (idempotent) but could be cleaner.

### Final Package Counts
- **Installed**: 796 packages (after depclean removed 41)
- **World**: 57 packages (from 87-line world file, some are meta-packages)
- **System**: 50 packages
- **Kernel**: 6.18.16-gentoo (modules at `/lib/modules/6.18.16-gentoo/`)
- **NVIDIA modules**: found at standard video/ path (confirmed by deep sanity check)

### Post-Boot Checklist (First Boot)
1. Change passwords: `passwd root`, `passwd chris` (both currently "gentoo")
2. `dispatch-conf` — merge `/etc/sudoers` and any other config updates
3. `eselect news read` — 27 unread items
4. `nvidia-smi` — verify both GTX 1050 Ti GPUs detected
5. `ip addr` — verify Intel I217-LM Ethernet (e1000e)
6. `xrandr` — verify display output
7. `pactl info | grep "Server Name"` — verify PipeWire
8. `swapon --show` — verify 16GB zram
9. `edac-util -s` — verify ECC memory reporting (sb_edac)
10. `cpuid2cpuflags` — verify CPU_FLAGS_X86 in make.conf
11. `bash ~/gentoo-machines/shared/restore-desktop.sh` — XFCE keybindings, panels, displays
12. Consider running `tools/update-system.sh verify` for comprehensive post-boot validation

### Future Generalization Candidates
- [ ] **Unified install script generator**: `tools/generate-install.sh <machine> <base-machine>` that creates all 3 part scripts from harvest data + feature detection (like kernel-config-template.sh does for kernel configs)
- [ ] **Machine feature profile**: Auto-detect HAS_WIFI, HAS_BLUETOOTH, IS_LAPTOP, HAS_NVIDIA from harvest data and emit the correct service list, packages, and Phase 11 config
- [ ] **Per-machine world file generator**: Start from shared world, subtract packages not applicable to the machine (no WiFi → remove wpa_supplicant, etc.)
- [ ] **Phase 13 auto-generation**: Verify list should be generated from Phase 8 service list, not manually maintained (drift risk)
- [ ] **Part3 non-interactive mode**: Use `chpasswd` instead of `passwd`, skip `read -p` prompts, add `--yes`/`--non-interactive` flag
- [ ] **Part3 depclean phase**: Add Phase 6.5 for `emerge --depclean` + `@preserved-rebuild` after @world
