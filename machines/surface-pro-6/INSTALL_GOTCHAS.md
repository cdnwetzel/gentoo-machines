# Gentoo Install Gotchas — Lessons Learned Across All Machines
# Persist this on the Ventoy USB so we never repeat these mistakes

## 1. WiFi During Install (wpa_supplicant)
**Problem (MBP 2015)**: Forgot to emerge wpa_supplicant before rebooting into Gentoo.
No WiFi = no emerge = stuck.
**Fix**: In the chroot (part2), BEFORE rebooting:
```bash
emerge --ask net-wireless/wpa_supplicant
# Also need for mwifiex on Surface Pro 6:
emerge --ask net-wireless/wireless-tools
# Then on first boot, before NetworkManager is running:
wpa_passphrase "SSID" "password" > /etc/wpa_supplicant.conf
wpa_supplicant -B -i wlp1s0 -c /etc/wpa_supplicant.conf
dhcpcd wlp1s0
```
**Surface Pro 6 note**: Interface will be `wlp1s0` (mwifiex_pcie at 01:00.0).
After NetworkManager is emerged and running, use `nmtui` instead.

## 2. LightDM / XFCE Black Screen Login Loop
**Problem**: After entering password at LightDM greeter, screen goes black with cursor,
then loops back to login screen. No error visible.
**Root causes** (any of these):
1. Wrong session-wrapper path — must be `/etc/lightdm/Xsession` (file must exist)
2. Wrong user-session — must be `xfce` (not `xfce4`, not `Xfce`, not `XFCE`)
3. Missing `/usr/share/xsessions/xfce.desktop` — needs `xfce4-session` emerged
4. Missing dbus/elogind — session can't start without them
5. Xauthority permissions — home dir owned by wrong user

**Fix checklist**:
```bash
# Verify the session file exists and has the right name
ls /usr/share/xsessions/
# Should show: xfce.desktop

# Check what the desktop file calls itself
grep Exec /usr/share/xsessions/xfce.desktop
# Should show: Exec=startxfce4

# LightDM config must have:
# [Seat:*]
# user-session=xfce
# session-wrapper=/etc/lightdm/Xsession

# Xsession wrapper must exist
ls -la /etc/lightdm/Xsession
# If missing, emerge lightdm should create it

# Services must be running
rc-service dbus status
rc-service elogind status

# Check lightdm log for the actual error
cat /var/log/lightdm/lightdm.log
cat /var/log/lightdm/seat0-greeter.log
cat /var/log/lightdm/x-0.log
```

## 3. Kernel vmlinuz Symlinks and Naming
**Problem**: GRUB can't find kernel, or `make install` puts it in wrong place,
or `installkernel` doesn't match expected naming.
**Key facts**:
- `make install` copies `arch/x86/boot/bzImage` to `/boot/vmlinuz-<version>`
- `eselect kernel set 1` creates `/usr/src/linux` symlink (needed for module builds)
- `sys-kernel/installkernel` with `grub` USE flag auto-runs `grub-mkconfig`
- Without `installkernel`, must manually: `grub-mkconfig -o /boot/grub/grub.cfg`
- Version string comes from kernel `EXTRAVERSION` or Gentoo ebuild

**Fix**: Always verify after kernel install:
```bash
# Check /usr/src/linux symlink points to right source
ls -l /usr/src/linux

# Check /boot has the right files
ls /boot/vmlinuz-* /boot/System.map-* /boot/config-*

# Check GRUB sees the kernel
grub-mkconfig -o /boot/grub/grub.cfg
grep menuentry /boot/grub/grub.cfg
```

## 4. i915 Built-in vs Module (XPS 9510 disaster)
**Problem**: `DRM_I915=y` (built-in) can't load firmware from `/lib/firmware/` before
root is mounted when there's no initramfs. GPU declared wedged, no display.
**Fix**: `DRM_I915=m` (module) — firmware loads after root mount.
**Rule**: If firmware comes from `/lib/firmware/` (not embedded), the driver MUST be a module.
**Surface Pro 6**: i915 needs `kbl_dmc_ver1_04.bin` → must be `=m` (module).

## 5. zram Backend Mismatch (XPS 9510)
**Problem**: zram-init config requested `zstd` but kernel only had `lzo-rle` compiled.
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

## 6. installkernel Module-Rebuild Source Symlink (XPS 9510 NVIDIA)
**Problem**: `make modules_install` creates `/lib/modules/<ver>/build` symlink but NOT
`/lib/modules/<ver>/source`. nvidia-drivers needs `source` symlink. Without it,
`KERNEL_DIR` resolves to empty → `/Kbuild not found`.
**Fix**: `99-module-rebuild.install` hook must set `KERNEL_DIR=/usr/src/linux` explicitly.
**Surface Pro 6**: No NVIDIA, but same pattern applies if any out-of-tree modules are used
(e.g., linux-surface DKMS modules, if not patching the kernel directly).

## 7. Audio Codec Identification
**Problem**: Module name doesn't match actual codec. `snd_hda_codec_alc269` handles
ALC269, ALC271, ALC282, ALC286, ALC298, etc. Must check actual codec.
**How to verify**:
```bash
cat /proc/asound/card*/codec* | grep -E "Codec|Subsystem Id"
```
**Results per machine**:
- MBP 2015: Cirrus CS4208, subsystem 0x106b7b00 (needs `model=mbp11`)
- XPS 9510: Intel HDA (check subsystem ID)
- Surface Pro 6: **Realtek ALC298**, subsystem **0x10ec10cc**, HDMI: Intel Kabylake 0x80860101

## 8. Portage tmpfs Overflow
**Problem**: Large packages (Chromium, LLVM, Rust, GCC, Firefox) exceed RAM tmpfs.
Build fails with "No space left on device".
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
```
# /etc/portage/env/notmpfs.conf
PORTAGE_TMPDIR="/var/tmp/portage-disk"
```
**Surface Pro 6**: Only 8GB RAM — use 4-6G tmpfs, may need MORE packages in this list.
Consider adding: `dev-lang/spidermonkey`, `sys-devel/clang`.

## 9. Firmware File Inventory (Surface Pro 6 Specific)
Exact filenames confirmed from this live session:
```
# WiFi (mwifiex_pcie)
mrvl/pcie8897_uapsta.bin

# Bluetooth (Marvell USB combo, btusb driver)
mrvl/usb8897_uapsta.bin

# GPU (i915 Kaby Lake)
i915/kbl_dmc_ver1_04.bin

# Camera (IPU3)
intel/ipu/irci_irci_ecr-master_20161208_0213_20170112_1500.bin
# also referenced as:
intel/irci_irci_ecr-master_20161208_0213_20170112_1500.bin
```
All ship with `sys-kernel/linux-firmware`. No manual extraction needed (unlike MBP Broadcom).

## 10. Surface Pro 6: Touchscreen Does NOT Work
**Confirmed**: The built-in touchscreen on this specific unit is non-functional.
IPTS hardware is present (MEI iTouch [8086:9d3e]) but no touch input is detected
even with linux-surface patches on Fedora 43.
**Decision**: Treat as a normal laptop — no IPTS/iptsd config needed.
**Note**: Surface Pro 9 DOES have working touchscreen + pen — that machine will need
the full linux-surface IPTS + iptsd setup.

## 11. Suspend: s2idle Only, No S3 Deep Sleep
**Applies to**: Surface Pro 6, XPS 9315, XPS 9510
**Fact**: Modern Intel laptops (8th gen+) use s2idle (Modern Standby / S0ix),
not S3 deep sleep. `/sys/power/mem_sleep` shows `[s2idle]`.
Don't waste time trying to enable S3 — it's not in the firmware.

## 12. GRUB EFI Installation
**Common gotcha**: Installing GRUB to wrong EFI partition or wrong target.
```bash
# Always specify the target and EFI directory
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo

# Surface Pro 6: EFI partition will be nvme0n1p1, mounted at /boot/efi
# May need to disable Secure Boot in Surface UEFI first
# (hold Volume Up + Power on boot to enter Surface UEFI)
```

## 13. OpenRC Service Checklist
Services to `rc-update add ... default` BEFORE first reboot:
```bash
# Essential (all machines)
rc-update add dbus default
rc-update add elogind boot
rc-update add NetworkManager default
rc-update add acpid default
rc-update add sshd default

# Thermal (Intel laptops)
rc-update add thermald default

# Display manager
rc-update add display-manager default  # configure via /etc/conf.d/display-manager

# Machine-specific
# Surface Pro 6: no mbpfan, no tlp needed (SAM handles thermal)
# XPS 9510: add tlp default
# MBP 2015: add mbpfan default
```

## 14. env -i for Module-Rebuild Hooks
**Problem (XPS 9510)**: `99-module-rebuild.install` hook inherits environment from
`make install`, which sets `ARCH=x86` and other kernel build vars that confuse
the nvidia-drivers ebuild (or any emerge called from the hook).
**Fix**: Use `env -i` to isolate:
```bash
env -i HOME=/root PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
    TERM=linux KERNEL_DIR=/usr/src/linux \
    emerge --oneshot @module-rebuild
```

## 15. PipeWire vs PulseAudio Conflict
**Problem (XPS 9510)**: PipeWire replaces pulseaudio-daemon. If both are emerged,
they fight over the audio socket. Also, xfce4-pulseaudio-plugin handles volume
keys natively — adding custom XFCE keyboard shortcuts for volume UP/DOWN will
cause double-firing and conflicts.
**Fix**:
```bash
# Emerge PipeWire with sound-server USE flag (replaces pulseaudio-daemon)
# In package.use:
media-video/pipewire sound-server
media-sound/pulseaudio -daemon

# Install the full stack:
emerge media-video/pipewire media-video/wireplumber \
       xfce4-extra/xfce4-pulseaudio-plugin media-sound/pavucontrol

# Autostart PipeWire (add to restore-desktop.sh or .xinitrc):
gentoo-pipewire-launcher &

# DO NOT add XFCE keyboard shortcuts for XF86AudioRaiseVolume / XF86AudioLowerVolume
# The pulseaudio plugin handles those natively
# DO add shortcuts for: XF86AudioMute, XF86AudioMicMute (amixer commands)
```

## 16. Brightness Hotkeys (acpilight, NOT brightnessctl)
**Problem**: `brightnessctl` is NOT in Gentoo main repos.
**Fix**: Use `sys-power/acpilight` which provides `xbacklight` using sysfs ACPI:
```bash
emerge sys-power/acpilight
rc-update add acpilight boot  # saves/restores brightness across reboot
usermod -aG video <username>  # allow non-root brightness control
```
Then bind Fn brightness keys in XFCE:
```
XF86MonBrightnessUp   → xbacklight -inc 10
XF86MonBrightnessDown → xbacklight -dec 10
```
**Surface Pro 6**: Backlight is `intel_backlight` (raw type), max 7500.
Should work with acpilight. Surface Type Cover may have different Fn key codes.

## 17. Firefox Binary & Google Chrome
**Lesson**: Compiling Firefox from source takes hours. Use the binary package:
```bash
# Firefox binary (fast, works immediately)
emerge www-client/firefox-bin

# Google Chrome (already in shared/world, uses gn-chrome overlay or AUR-style)
emerge www-client/google-chrome

# If you want source Firefox later, add to package.env for disk builds:
# www-client/firefox notmpfs.conf
```
**google-chrome** is already in the shared `world` file. Both are pre-built binaries —
no compilation needed, instant browser access after install.

## 18. CPU_FLAGS_X86 — Run cpuid2cpuflags, Don't Guess
```bash
emerge --ask app-portage/cpuid2cpuflags
cpuid2cpuflags
# Copy output directly into make.conf
```
**Surface Pro 6 (i5-8250U Kaby Lake-R)**:
`CPU_FLAGS_X86: aes avx avx2 f16c fma3 mmx mmxext pclmul popcnt rdrand sse sse2 sse3 sse4_1 sse4_2 ssse3`
(No AVX-512 on consumer Kaby Lake)

## 19. GCC -march= Value for Kaby Lake
**Problem**: `-march=kabylake` is NOT a valid GCC target. GCC does not have a
dedicated Kaby Lake target because it's architecturally identical to Skylake.
**Fix**: Use `-march=skylake` in make.conf for Kaby Lake and Kaby Lake-R CPUs.
Valid GCC targets near this range: `haswell`, `broadwell`, `skylake`, `skylake-avx512`.

## 20. ccache in FEATURES Before ccache Is Installed
**Problem**: make.conf has `FEATURES="ccache"` but ccache isn't emerged yet.
The compiler wrapper fails — every `econf` dies with "C compiler cannot create executables".
**Fix**: Remove `ccache` from FEATURES until after `dev-util/ccache` is installed.
Re-enable it after Phase 6 (world install) completes.
