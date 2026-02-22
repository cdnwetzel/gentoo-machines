# Checkpoint - 2026-02-21

## Session Summary

Brought the Dell XPS 15 9510 to full production status on Gentoo Linux, including kernel tuning, desktop restore, USB-C hub support, and ML/AI workstation optimizations. Second session fixed three kernel config issues discovered during post-reboot verification.

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

## Current State

### Commits This Session
- `abf6dfe` Add XPS 9510 production config, fix WiFi/GPU firmware loading (pre-existing, pushed)
- `6344b3a` Add XPS 9510 post-reboot checklist (pushed)
- `41c6e28` Fix ACPI lid script user detection, update shared packages
- `ccec511` Enable USB-C hub support for XPS 9510 (Ethernet, SD/TF)
- `d00b74a` Document XPS 9510 dev stack, save fstab and grub config
- `4963252` Save final running .config after olddefconfig, add nvidia-drivers to world
- `985d54f` Add performance tuning for XPS 9510 ML workstation
- `2cfbe88` Update checkpoint, add tap-to-click touchpad config
- `8df3e54` Add prime-run script for NVIDIA GPU offloading

### Machine Status
| Machine | Status | Next Step |
|---------|--------|-----------|
| Dell XPS 13 9315 | Production (Gentoo) | Maintenance only |
| Intel NUC11TNBi5 | Config ready | Boot live USB, follow INSTALL.md |
| Dell XPS 15 9510 | **Production (Gentoo)** | Reboot, `emerge @module-rebuild`, verify |
| ASRock B550 / Ryzen 9 5950X | Placeholder | Harvest on Fedora 42 |
| Dell Precision T5810 | Placeholder | Harvest on Fedora 42 |
| Dell Precision 7960 | Placeholder | Harvest on RHEL 10.1 |
| Surface Pro 6 | Placeholder | Harvest on Fedora 43 |
| Surface Pro 9 | Placeholder | Harvest on Windows 11 Pro |

### XPS 9510 Post-Reboot Verification (After Next Reboot)
```bash
# i915 firmware loading (should show DMC + GuC loaded, no errors)
dmesg | grep i915 | head -10

# NVIDIA driver (rebuild first: sudo emerge @module-rebuild)
nvidia-smi

# zram swap (should show /dev/zram0, 8G, zstd)
cat /proc/swaps
zramctl

# Performance tuning
cat /sys/kernel/mm/transparent_hugepage/enabled    # [always]
cat /sys/kernel/mm/lru_gen/enabled                 # MGLRU active
sysctl vm.swappiness vm.dirty_ratio                # 10, 40
rc-status | grep -E "thermald|tlp|zram|acpid"     # all started

# PRIME/Optimus test
prime-run glxinfo | grep "OpenGL renderer"         # should show RTX 3050 Ti
```

## Next Steps (Priority Order)

1. **Reboot XPS 9510** — apply kernel fixes (i915 module, zram zstd, DRM_TTM_HELPER)
2. **`sudo emerge @module-rebuild`** — rebuild nvidia-drivers against new kernel
3. **Verify all three fixes** — i915 firmware, zram swap, nvidia-smi
4. **Test USB-C hub** — plug in Anker 7-in-1, verify Ethernet/HDMI/SD
5. **Test clamshell mode** — connect AOC 34" external, close lid
6. **Install Gentoo on NUC11** — follow INSTALL.md
7. **Harvest remaining machines** — run harvest scripts
8. **Consider renaming GitHub repo** — `gentoo_dell_xps9315` doesn't reflect multi-machine scope
