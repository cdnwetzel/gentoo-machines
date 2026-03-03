# Gentoo Install Gotchas — Universal Lessons Learned
# Consolidated from MBP 2015, XPS 9510, XPS 9315, Surface Pro 6
# Persist this on the Ventoy USB so we never repeat these mistakes

## 1. WiFi During Install (wpa_supplicant)
**Problem (MBP 2015)**: Forgot to emerge wpa_supplicant before rebooting.
No WiFi = no emerge = stuck.
**Fix**: In the chroot, BEFORE rebooting:
```bash
emerge net-wireless/wpa_supplicant net-misc/networkmanager net-misc/dhcpcd
rc-update add NetworkManager default
```
On first boot (before NetworkManager starts):
```bash
wpa_passphrase "SSID" "password" > /etc/wpa_supplicant.conf
wpa_supplicant -B -i <interface> -c /etc/wpa_supplicant.conf
dhcpcd <interface>
```
After NetworkManager is running, use `nmtui` instead.

## 2. LightDM / XFCE Black Screen Login Loop
**Problem**: Password accepted, screen goes black, loops back to login.
**Root causes** (any of these):
1. Wrong session-wrapper — must be `/etc/lightdm/Xsession` (file must exist)
2. Wrong user-session — must be `xfce` (NOT `xfce4`, NOT `Xfce`)
3. Missing `/usr/share/xsessions/xfce.desktop` — needs xfce4-session
4. Missing dbus/elogind
5. Xauthority permissions

**Fix checklist**:
```bash
ls /usr/share/xsessions/                    # must show xfce.desktop
grep Exec /usr/share/xsessions/xfce.desktop # must show: Exec=startxfce4
# lightdm.conf [Seat:*] must have:
#   user-session=xfce
#   session-wrapper=/etc/lightdm/Xsession
ls -la /etc/lightdm/Xsession               # must exist
rc-service dbus status                      # must be started
rc-service elogind status                   # must be started
cat /var/log/lightdm/lightdm.log            # for actual error
```

## 3. Kernel vmlinuz Naming and GRUB
**Key facts**:
- `make install` copies bzImage to `/boot/vmlinuz-<version>`
- `eselect kernel set 1` creates `/usr/src/linux` symlink (needed for module builds)
- `sys-kernel/installkernel` with `grub` USE flag auto-runs grub-mkconfig
- Without installkernel, must manually: `grub-mkconfig -o /boot/grub/grub.cfg`

**Always verify after kernel install**:
```bash
ls -l /usr/src/linux                        # symlink correct?
ls /boot/vmlinuz-* /boot/config-*           # files present?
grep menuentry /boot/grub/grub.cfg          # GRUB sees kernel?
```

## 4. i915 Built-in vs Module
**Problem**: `DRM_I915=y` (built-in) can't load firmware from `/lib/firmware/` before
root is mounted when there's no initramfs. GPU declared wedged, no display.
**Rule**: If firmware comes from `/lib/firmware/` (not embedded), driver MUST be a module.
**Fix**: `DRM_I915=m` — firmware loads after root mount.

## 5. zram Backend Mismatch
**Problem**: zram-init config requested `zstd` but kernel only had `lzo-rle`.
**Fix**: Enable in kernel config:
```
CONFIG_ZRAM=y
CONFIG_ZRAM_BACKEND_ZSTD=y
CONFIG_CRYPTO_ZSTD=y
CONFIG_ZSTD_COMPRESS=y
CONFIG_ZSTD_DECOMPRESS=y
```
Also: if `CONFIG_ZRAM=y` (built-in), set `load_on_start=no` and `unload_on_stop=no`
in `/etc/conf.d/zram-init` — can't rmmod a built-in module.

## 6. Module-Rebuild Source Symlink
**Problem**: `make modules_install` creates `/lib/modules/<ver>/build` but NOT `source`.
Out-of-tree modules (nvidia-drivers, etc.) need `source` symlink.
**Fix**: `99-module-rebuild.install` hook or manually:
```bash
ln -s "$(readlink /lib/modules/<ver>/build)" /lib/modules/<ver>/source
```

## 7. Audio Codec Identification
**Problem**: Module name doesn't match codec. `snd_hda_codec_realtek` handles ALC269,
ALC271, ALC282, ALC286, ALC298, etc.
**How to verify**:
```bash
cat /proc/asound/card*/codec* | grep -E "Codec|Subsystem Id"
```
**Results per machine**:
- MBP 2015: Cirrus CS4208, subsystem 0x106b7b00 (needs `model=mbp11`)
- XPS 9510: Intel HDA (Realtek codec)
- XPS 9315: SOF audio (NOT HDA — Alder Lake uses sof-audio-pci-intel-tgl)
- Surface Pro 6: Realtek ALC298, subsystem 0x10ec10cc (autoconfig works)

## 8. Portage tmpfs Overflow
**Problem**: Large packages exceed RAM tmpfs. Build fails with "No space left".
**Fix**: Use `package.env` to redirect large builds to disk:
```
# /etc/portage/package.env
www-client/chromium notmpfs.conf
www-client/firefox notmpfs.conf
sys-devel/llvm notmpfs.conf
dev-lang/rust notmpfs.conf
dev-qt/qtwebengine notmpfs.conf
sys-devel/gcc notmpfs.conf
```
**tmpfs sizing by RAM**:
| RAM | tmpfs | Notes |
|-----|-------|-------|
| 8GB | 4GB | Surface Pro 6 |
| 16GB | 12GB | MBP 2015, XPS 9315 |
| 32GB | 24GB | XPS 9510 |

## 9. Firmware File Inventory
All ship with `sys-kernel/linux-firmware`. No manual extraction needed.

**Per machine**:
- MBP 2015: `brcm/brcmfmac43602-pcie.*` (WiFi), `regulatory.db`
- XPS 9510: `i915/tgl_dmc_ver2_12.bin`, `i915/tgl_guc_70.1.1.bin`, `iwlwifi-QuZ-*`
- XPS 9315: `i915/adlp_*`, `iwlwifi-so-a0-gf-a0-*`, `intel/ibt-0040-0041.*`
- Surface Pro 6: `mrvl/pcie8897_uapsta.bin`, `mrvl/usb8897_uapsta.bin`, `i915/kbl_dmc_ver1_04.bin`

## 10. Suspend: s2idle vs S3
Modern Intel laptops (8th gen+) use s2idle (Modern Standby/S0ix), not S3 deep.
`/sys/power/mem_sleep` shows `[s2idle]`. Don't waste time trying to enable S3.
**Exception**: MBP 2015 supports S3 deep sleep natively.

## 11. GRUB EFI Installation
```bash
# Always specify target and EFI directory
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo
```
Surface Pro 6: Disable Secure Boot first (Volume Up + Power to enter UEFI).

## 12. OpenRC Service Checklist (All Machines)
```bash
# Essential
rc-update add dbus default
rc-update add elogind boot
rc-update add NetworkManager default
rc-update add acpid default
rc-update add sshd default
rc-update add display-manager default
rc-update add metalog default
rc-update add zram-init boot
rc-update add alsasound boot

# Thermal (all Intel laptops)
rc-update add thermald default

# Power (laptops)
rc-update add tlp default

# Machine-conditional (see shared/openrc-services for full list)
```

## 13. env -i for Module-Rebuild Hooks
**Problem**: `99-module-rebuild.install` inherits `make install` environment
(ARCH=x86, MAKEFLAGS, KBUILD_*) which breaks emerge.
**Fix**: Use `env -i` to isolate:
```bash
env -i HOME=/root PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
    TERM=linux emerge @module-rebuild
```

## 14. PipeWire vs PulseAudio
PipeWire replaces pulseaudio-daemon. Don't emerge both.
```bash
# package.use:
media-video/pipewire sound-server dbus elogind bluetooth pipewire-alsa extra

# DO NOT add XFCE shortcuts for volume keys
# xfce4-pulseaudio-plugin handles them natively
```

## 15. Brightness Hotkeys (acpilight)
`brightnessctl` is NOT in Gentoo repos. Use `sys-power/acpilight`:
```bash
emerge sys-power/acpilight
rc-update add acpilight boot
usermod -aG video <username>
```
XFCE bindings: `xbacklight -inc 10` / `xbacklight -dec 10`

## 16. Firefox Binary
Compiling Firefox takes hours. Use `www-client/firefox-bin` for instant access.

## 17. CPU_FLAGS_X86 — Always Run cpuid2cpuflags
```bash
emerge app-portage/cpuid2cpuflags
cpuid2cpuflags  # copy output to make.conf
```
The XPS 9510 ran for months with only `mmx mmxext sse sse2` — every package
was missing AVX/AVX-512/AES-NI hardware acceleration. **Always set this.**

## 18. GCC -march= Values
Some CPU names don't have GCC targets:
- Kaby Lake/Kaby Lake-R: use `-march=skylake` (architecturally identical)
- Tiger Lake-H: use `-march=tigerlake`
- Alder Lake: use `-march=alderlake`
- Broadwell: use `-march=broadwell`

## 19. ccache in FEATURES Before ccache Is Installed
**Problem**: make.conf has `FEATURES="ccache"` but ccache isn't emerged yet.
Every `econf` fails with "C compiler cannot create executables".
**Fix**: Comment out ccache in FEATURES until after `dev-util/ccache` is installed.

## 20. zram-init num_devices
**Problem**: zram-init service starts but creates no devices. Swap is missing.
**Fix**: Must have `num_devices="1"` in `/etc/conf.d/zram-init`. Without it,
the service silently does nothing.

## 21. Portage tmpfs Sizing by RAM
| Machine | RAM | tmpfs | ccache | zram | Notes |
|---------|-----|-------|--------|------|-------|
| MBP 2015 | 16GB | 12G | 5G /var/cache | 4G | SSD wear protection |
| XPS 9315 | 8GB | 4G | 5G /var/cache | 4G | Conservative for low RAM |
| Surface Pro 6 | 8GB | 4G | 5G /var/cache | 4G | Same as XPS 9315 |
| XPS 9510 | 32GB | 24G | 10G /data | 8G | Aggressive, ccache on 2nd NVMe |

## 22. NVIDIA Dual-GPU Gotchas
**Applies to**: XPS 9510, ASRock B550, Precision 7960
- DRM_QXL=m trick: pulls in DRM_TTM_HELPER (nvidia build dep since kernel 6.11+)
- DRM_NOUVEAU=n: conflicts with proprietary nvidia-drivers
- prime-run wrapper: sets env vars for PRIME Render Offload
- 99-module-rebuild.install: auto-rebuild nvidia on kernel update
- Boot params: `i915.enable_guc=3 nvidia.NVreg_DynamicPowerManagement=0x02`
- TLP: `RUNTIME_PM_DRIVER_DENYLIST="nvidia"` (let NVIDIA manage its own PM)

## 23. AMD CPU/GPU Notes
**Applies to**: ASRock B550 (Ryzen 9 5950X + RTX 3060 Ti)
- CPU_SUP_AMD=y, AMD_IOMMU=y (not on Intel machines)
- `-march=znver3` for Zen 3
- AMDGPU for AMD GPUs (not on this machine — uses NVIDIA)
- CPU_FLAGS_X86 will differ: no AVX-512, has different AMD-specific flags
- No INTEL_PSTATE, no INTEL_IDLE — use ACPI_CPUFREQ instead

## 24. Xeon/ECC Notes
**Applies to**: Precision T5810 (Xeon E5-2699v4), Precision 7960 (Xeon W5-3433)
- EDAC=y for ECC memory error reporting
- NR_CPUS: set to actual thread count (T5810: 44T, 7960: 32T)
- NUMA=y for multi-socket (T5810 is single-socket, but NUMA topology exists)
- Large RAM sysctl: adjust dirty_ratio, vfs_cache_pressure for 128GB+
- `-march=broadwell` for E5-2699v4, `-march=sapphirerapids` for W5-3433

## 25. CPU_FLAGS_X86 Must Always Be Set
Without it, Portage defaults to the bare minimum (mmx, sse, sse2).
Packages like openssl, ffmpeg, numpy, and hundreds of others have USE flags
gated on CPU_FLAGS_X86 (e.g., `aes`, `avx2`, `avx512f`).
Missing flags = missing hardware acceleration = slower everything.

**Prevention**: The generate-config.sh tool and all machine make.conf templates
include CPU_FLAGS_X86. Every new machine checklist includes running cpuid2cpuflags.
