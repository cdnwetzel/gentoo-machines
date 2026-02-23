# Checkpoint - 2026-02-22

## Session Summary

Brought the Dell XPS 15 9510 to full production status on Gentoo Linux, including kernel tuning, desktop restore, USB-C hub support, ML/AI workstation optimizations, PipeWire audio, Dell Fn hotkeys, and kernel patches. Multiple sessions fixed kernel config issues, added audio/brightness support, and created a from-zero reproducible config set.

## What Was Done

### Phase 1: XPS 9510 First Boot Setup
- Confirmed machine identity (XPS 15 9510, Tiger Lake-H i7-11800H, 32GB RAM, dual Samsung 990 PRO NVMe)
- Verified XFCE/LightDM session running, services active (elogind, dbus, NetworkManager, acpid, bluetooth)
- Display outputs confirmed: eDP-1, DP-1/2/3 on Intel i915 (same naming as XPS 9315)

### Phase 2: SSH & Git Setup
- Generated ED25519 SSH key for GitHub (`~/.ssh/id_ed25519`)
- Configured git identity on both `/data` and `~/` repos
- Switched remotes from HTTPS to SSH (`git@github.com:cdnwetzel/gentoo_dell_xps9315.git`)
- Pushed 2 pending commits (XPS 9510 production config + POST-REBOOT.md)
- Synced both repo clones (`~/gentoo_dell_xps9315` and `/data/gentoo_dell_xps9315`)

### Phase 3: Bug Fixes & Missing Packages
- **Fixed `acpi-lid.sh`**: hardcoded `/home/chris/.Xauthority` → dynamic user detection via `who`
- **Installed missing packages**: x11-apps/xrandr, x11-apps/xhost, gentoolkit, dmidecode, i2c-tools, usbutils, alsa-utils
- **Updated `shared/world`**: added xrandr, xfce4-power-manager, xfce4-taskmanager, nvidia-drivers
- **Updated `shared/openrc-services`**: moved elogind to boot runlevel, added thermald/tlp/zram-init
- **Enabled alsasound** at boot runlevel

### Phase 4: USB-C Hub Support
- Enabled kernel drivers for USB-C hub peripherals:
  - `CONFIG_USB_RTL8152=m` (Realtek RTL8153 Ethernet)
  - `CONFIG_USB_USBNET=m` + CDC_ETHER, CDC_NCM, AX8817X, AX88179_178A
  - `CONFIG_MISC_RTSX_USB=m` (USB SD card reader)
- Rebuilt kernel, verified modules load (`modprobe r8152`, `modprobe usbnet`)
- Documented Anker 7-in-1 USB-C hub support in HARDWARE.md

### Phase 5: Documentation & Config Backup
- Saved XPS 9510 `fstab` and `grub` defaults to repo
- Documented full software environment in HARDWARE.md:
  - Python 3.13, PyTorch 2.10+CUDA 13.1, transformers, langchain, chromadb, faiss, jupyter
  - MSSQL ODBC 18, pyodbc, unixODBC
  - VS Code, Geany, Node.js 24 + nvm
- Updated CLAUDE.md with dev stack summary

### Phase 6: Performance Tuning (ML Workstation)
- **Kernel config optimizations**:
  - `NR_CPUS=16` (match actual 8C/16T, saves memory)
  - Transparent Huge Pages (always) — reduces TLB misses for large ML tensors
  - MGLRU (`LRU_GEN`) — better page reclaim under memory pressure
  - KSM — memory deduplication across model instances
  - zram with zstd compression backend
- **System tuning**:
  - `sysctl-performance.conf`: vm.swappiness=10, dirty_ratio=40, TCP buffer tuning
  - `zram-init.conf`: 8GB zstd-compressed swap (safety net for large models)
  - Installed & enabled thermald (Intel thermal management)
  - Installed & enabled tlp (laptop power profiles)
  - Installed & enabled zram-init at boot

### Phase 7: Post-Reboot Fixes (Second Session)
Diagnosed three issues after first reboot on the optimized kernel:

1. **i915 firmware failure** — `DRM_I915=y` (built-in) couldn't load firmware from `/lib/firmware/` before root mount (no initramfs). GuC/DMC failed, GPU declared wedged. **Fix**: changed `DRM_I915=m` (module).

2. **nvidia-drivers module rebuild failure** — `emerge @module-rebuild` failed: `CONFIG_DRM_TTM_HELPER` not set, required by nvidia-drivers on kernel 6.11+ when `DRM_FBDEV_EMULATION` is enabled. **Fix**: enabled `CONFIG_DRM_QXL=m` which pulls in `DRM_TTM_HELPER=m`.

3. **zram swap not activating** — zram-init config requested `zstd` but kernel only had `lzo-rle` backend compiled. **Fix**: enabled `CONFIG_ZRAM_BACKEND_ZSTD=y` and `CONFIG_CRYPTO_ZSTD=y`.

Additional work:
- Installed `sys-kernel/installkernel` with `grub` USE flag (auto grub-mkconfig on `make install`)
- Added `sys-kernel/installkernel grub` to `/etc/portage/package.use/xps9510`
- Rebuilt kernel with all three fixes, installed via `make modules_install && make install`
- Installed `prime-run` script for NVIDIA GPU offloading

### Phase 8: Post-Reboot Verification & Final Tweaks (Third Session)
Verified all kernel fixes after reboot:
- **THP**: `[always]` — confirmed
- **MGLRU**: `0x0007` (all features) — confirmed
- **KSM**: was `0` (disabled) — enabled via `/etc/local.d/ksm.start`, confirmed `1`
- **i915**: DMC v2.12, GuC 70.1.1, HuC 7.9.3 loaded, no errors — confirmed
- **zram**: 8GB zstd swap active — confirmed
- **nvidia-smi**: working (emerge @module-rebuild done before this session)

Additional work:
- Added `ksm.start` to `shared/` and `machines/xps-9510/`, wired into `restore-system.sh`
- Added **Super+Enter** → maximize to keybindings script
- Added **Super+Space** → app finder search to keybindings script
- Ran `restore-desktop.sh` and `restore-system.sh` on XPS 9510

### Phase 9: Hardware-Specific Kernel Optimizations (Third Session cont.)
Tuned kernel and fstab for i7-11800H 8C/16T, 32GB RAM, dual Samsung 990 PRO NVMe:

- **NR_CPUS=16** (was 64) — match actual core count, saves per-CPU memory
- **NUMA disabled** (was enabled) — single-socket laptop, removes overhead
- **INTEL_IDLE=y** (was disabled) — proper Tiger Lake C-state management
- **PREEMPT=y** (was VOLUNTARY) — better desktop responsiveness under ML loads
- **ZSWAP compressor → zstd** (was lzo) — matches zram config, ~30% better compression
- **BFQ I/O scheduler enabled** — fairer I/O when ML jobs saturate NVMe
- **fstab: commit=60** on both ext4 mounts — batch journal commits on fast NVMe
- **fstab: /tmp tmpfs → 16G** (was 8G) — more headroom for ML temp files
- **Auto module-rebuild hook** — `/etc/kernel/postinst.d/99-module-rebuild.install`

Kernel rebuilding — requires reboot + verify after.

### Phase 10: PipeWire Audio, Dell Hotkeys & Housekeeping (2026-02-22)

1. **intel_idle Tiger Lake patch** — Created `patches/intel_idle-add-tiger-lake.patch` to add Tiger Lake (0x8D) and Tiger Lake-L (0x8C) to `intel_idle` CPU ID table. Maps to `idle_cpu_skl`/`skl_cstates` for proper C-state management instead of BIOS-limited ACPI fallback. Affects XPS 9510 and NUC11. Patch applied to source tree and kernel rebuilt.

2. **zram-init.conf fix** — Set `load_on_start=no` and `unload_on_stop=no` for built-in CONFIG_ZRAM=y. Was causing service stop failures trying to unload a built-in module. Deployed to `/etc/conf.d/zram-init`.

3. **PipeWire audio stack** — Installed PipeWire (with `sound-server` USE flag), WirePlumber, xfce4-pulseaudio-plugin, pavucontrol. PipeWire replaces pulseaudio-daemon (auto-uninstalled on USE flag rebuild). Added gentoo-pipewire-launcher autostart to `restore-desktop.sh`. Added pulseaudio plugin (plugin-19) to panel between systray and clock. Deployed `shared/package.use` to `/etc/portage/package.use/shared`.

4. **Dell Fn hotkey bindings** — Added XF86AudioMute/LowerVolume/RaiseVolume/MicMute (amixer fallback, overridden by xfce4-pulseaudio-plugin once installed) and XF86MonBrightnessDown/Up (xbacklight via acpilight) to `xfce4-keybindings.sh`. Ran `restore-desktop.sh` to apply.

5. **acpilight** — Installed `sys-power/acpilight` for F6/F7 brightness keys (provides `xbacklight` using sysfs ACPI). Added to boot runlevel for brightness save/restore. User added to `video` group. Note: `brightnessctl` is NOT in Gentoo main repos — acpilight is the correct package.

6. **Kernel rebuilt** — Rebuilt with intel_idle patch, `make install` triggered auto grub-mkconfig and nvidia-drivers module-rebuild via postinst hook. Rebooting to apply.

7. **Repo housekeeping** — Created `backlog.md` with prioritized open items. Updated `checkpoint.md`, `CLAUDE.md`, `patches/README.md`.

## Current State

### Machine Status
| Machine | Status | Next Step |
|---------|--------|-----------|
| Dell XPS 13 9315 | Production (Gentoo) | Maintenance only |
| Intel NUC11TNBi5 | Config ready | Boot live USB, follow INSTALL.md |
| Dell XPS 15 9510 | **Production (Gentoo)** | Verify post-reboot (PipeWire, intel_idle, hotkeys) |
| ASRock B550 / Ryzen 9 5950X | Placeholder | Harvest on Fedora 42 |
| Dell Precision T5810 | Placeholder | Harvest on Fedora 42 |
| Dell Precision 7960 | Placeholder | Harvest on RHEL 10.1 |
| Surface Pro 6 | Placeholder | Harvest on Fedora 43 |
| Surface Pro 9 | Placeholder | Harvest on Windows 11 Pro |

### XPS 9510 Post-Reboot Verification
```bash
# PipeWire sound server (should show "PipeWire")
pactl info | grep "Server Name"

# intel_idle with Tiger Lake C-states (should show skl_cstates loading)
dmesg | grep intel_idle

# zram swap active (should show /dev/zram0, zstd, 8G)
swapon --show

# Brightness control (should return a percentage)
xbacklight -get

# Preempt mode (should show "preempt")
cat /sys/kernel/debug/sched/preempt

# BFQ I/O scheduler available
cat /sys/block/nvme0n1/queue/scheduler

# fstab commit=60 applied
mount | grep commit

# /tmp tmpfs 16G
df -h /tmp

# Volume hotkeys: press Fn+F1/F2/F3, check panel plugin responds
# Brightness hotkeys: press Fn+F6/F7, check screen brightness changes
```

If PipeWire isn't running after reboot, logout/login (autostart via `gentoo-pipewire-launcher`).

## Reproducibility — From-Zero Install Checklist

All config is in the repo. To rebuild this machine from scratch:

1. Follow `INSTALL.md` (base Gentoo install)
2. `cp machines/xps-9510/make.conf /etc/portage/make.conf`
3. `cp shared/package.use /etc/portage/package.use/shared`
4. `emerge --ask $(cat shared/world | grep -v '^#' | grep -v '^$')`
5. `cp machines/xps-9510/.config /usr/src/linux/.config`
6. Apply patches: `cd /usr/src/linux && patch -p1 < ~/gentoo_dell_xps9315/patches/intel_idle-add-tiger-lake.patch`
7. `make olddefconfig && make -j$(nproc) && make modules_install && make install`
8. `cp machines/xps-9510/fstab /etc/fstab`
9. `cp machines/xps-9510/grub /etc/default/grub && grub-mkconfig -o /boot/grub/grub.cfg`
10. `cp machines/xps-9510/sysctl-performance.conf /etc/sysctl.d/`
11. `cp machines/xps-9510/zram-init.conf /etc/conf.d/zram-init`
12. `sudo bash shared/restore-system.sh`
13. `bash shared/restore-desktop.sh` (as user)
14. `rc-update add acpilight boot`
15. Reboot and verify

## Next Steps (Priority Order)

1. **Verify post-reboot** — run checks above (PipeWire, intel_idle, zram, brightness, hotkeys)
2. **Test USB-C hub** — plug in Anker 7-in-1, verify Ethernet/HDMI/SD
3. **Test clamshell mode** — connect AOC 34" external, close lid
4. **Install Gentoo on NUC11** — follow INSTALL.md
5. **Harvest remaining machines** — run harvest scripts
6. **Consider renaming GitHub repo** — `gentoo_dell_xps9315` doesn't reflect multi-machine scope
