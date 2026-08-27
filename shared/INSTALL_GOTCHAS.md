# Gentoo Install — Known Issues & Considerations
# Consolidated from MBP 2015, XPS 9510, XPS 9315, Surface Pro 6, Precision T5810

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
rc-update add zram-init default
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

## 20a. zram-init Must Run in `default`, Not `boot` Runlevel
**Problem**: With `rc-update add zram-init boot`, the service runs too early —
something in early boot races and `zramctl` fails to initialize the device.
The init script's `start()` ends with `:` so OpenRC always reports "started"
even when the device is left at `disksize=0`. `swapon --show` shows no zram.
**Symptom**: `cat /sys/block/zram0/disksize` returns `0`, manual restart fixes it.
**Fix**: `rc-update del zram-init boot && rc-update add zram-init default`.
Confirmed on SP6 2026-04-29 — moved to `default`, zram came up cleanly at boot.

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

## 26. Hibernate Requires a Swap File (zram Alone Can't Hibernate)
**Problem**: All machines use zram-only swap (compressed RAM). Hibernate writes
RAM contents to disk, but zram IS RAM — there's nowhere to write.
**Fix**: Create a swap file on the root ext4 partition alongside zram:
```bash
# One-time setup (interactive, idempotent)
sudo bash shared/hibernate-setup.sh
```
The setup script creates `/var/swapfile` (size = RAM), adds GRUB `resume=` and
`resume_offset=` params, and installs a low-battery cron monitor for laptops.
zram stays active for daily swap pressure; the swap file (pri=-1) is only used
for hibernate. Kernel 5.0+ supports hibernate-to-swap-file on ext4 natively.
**Verification**:
```bash
swapon --show                          # should show zram0 AND /var/swapfile
grep resume /etc/default/grub          # resume=UUID=... resume_offset=...
cat /sys/power/disk                    # should show [platform]
```

## 27. fstab Mount Order for Nested Filesystems
**Problem**: `/boot/efi` listed before `/boot` in fstab. OpenRC's `localmount`
processes entries top-to-bottom. If `/boot` isn't mounted when `/boot/efi` is
attempted, the EFI partition silently fails or mounts on the wrong path.
**Symptom**: After fresh reboot, `/boot/efi` not mounted. `mount /boot/efi` works manually.
**Fix**: Order fstab by mount hierarchy — parent directories first:
```
/            ...   0  1
/boot        ...   0  2
/boot/efi    ...   0  0
```
**Alternative**: Use `noauto` for `/boot/efi` (XPS 9510 pattern) — only mount when
updating GRUB. EFI partition isn't needed at runtime.

## 28. PORTAGE_TMPDIR Must Be `/var/tmp`, Not `/var/tmp/portage`
**Problem**: Setting `PORTAGE_TMPDIR="/var/tmp/portage"` in make.conf. Portage
automatically appends `/portage/` to PORTAGE_TMPDIR, so builds go to
`/var/tmp/portage/portage/` — bypassing the tmpfs mount at `/var/tmp/portage`.
Builds run on disk instead of RAM, and build logs vanish from the expected path.
**Fix**: Use the default value:
```
PORTAGE_TMPDIR="/var/tmp"
```
Portage creates `/var/tmp/portage/` itself, which is where fstab mounts the tmpfs.
The disk fallback (`notmpfs.conf`) correctly uses `/var/tmp/portage-disk` — portage
builds large packages in `/var/tmp/portage-disk/portage/`, entirely separate from tmpfs.

## 29. Portage package.use File Ordering — Last Alphabetical File Wins
**Problem (Precision T5810)**: Machine-specific file `precision-t5810` had
`x11-drivers/nvidia-drivers -kernel-open modules tools`, but `shared` had
`x11-drivers/nvidia-drivers kernel-open modules tools`. Because `shared` sorts
after `precision-t5810` alphabetically, the `kernel-open` from shared overrode
the `-kernel-open` from the machine file. The emerge output showed `kernel-open`
still active despite the machine-specific override.
**Root cause**: When the same package appears in multiple files under
`/etc/portage/package.use/`, Portage processes them in alphabetical order.
For conflicting USE flags, the **last file wins**.
**Fix**: Don't put machine-varying USE flags in shared. Keep nvidia-drivers
USE flags in machine-specific files only. Each machine knows its GPU generation.
**Prevention**: Never put USE flags that differ between machines in the shared
file. Shared should only contain flags that are truly universal across all machines.

## 30. ccache `/var/cache/ccache/tmp` Permissions (portage sandbox)
**Problem (Precision T5810)**: nvidia-drivers build failed with:
```
ccache: error: failed to create temporary file for /var/cache/ccache/tmp/cpp_stdout.tmp.*.i: Permission denied
```
**Root cause**: `/var/cache/ccache/` was mode `2775` (group-writable for portage)
but the `tmp/` subdirectory was mode `2755` (not group-writable). Portage's sandbox
runs compiles as the `portage` user, which has group `portage` — but `2755` only
gives the group `r-x`, not write. ccache needs to write temp files there.
**Fix**:
```bash
sudo chmod 2775 /var/cache/ccache/tmp
```
**Prevention**: After `mkdir -p /var/cache/ccache && chown root:portage && chmod 2775`,
also verify subdirectories inherit the group-writable permission. The `setgid` bit (2)
ensures new files get the `portage` group, but doesn't guarantee write permission on
subdirectories created by ccache itself.

## 31. NVIDIA 590+ Drops Pascal (GTX 10xx) — Use 580.xx Legacy Branch
**Problem (Precision T5810)**: After fixing kernel-open AND ccache, nvidia-drivers
590.48.01 installed successfully but `nvidia-smi` still failed. Emerge printed:
```
***WARNING*** You are installing a version known not to work with a GPU of the current system.
```
**Root cause**: NVIDIA 590.x dropped support for Maxwell, Pascal, and Volta GPUs
entirely. The GTX 1050 Ti (Pascal, GP107) is not recognized by 590+ drivers at all —
neither kernel-open nor proprietary modules. The **580.xx series** is the last driver
branch supporting Pascal.
**Timeline**: 580.xx gets quarterly security patches until October 2028, then EOL.
**Fix**:
```bash
# Mask 581+ to stay on legacy branch
echo '>=x11-drivers/nvidia-drivers-581' > /etc/portage/package.mask/nvidia-drivers
# Downgrade
emerge -1v x11-drivers/nvidia-drivers
```
**Affected GPUs**: All GeForce GTX 900 series (Maxwell), GTX 10xx series (Pascal),
Titan X/Xp (Pascal), Quadro P-series, Tesla P-series.
**Safe GPUs** (590+ works): GeForce RTX 2000+ (Turing), RTX 3000+ (Ampere),
RTX 4000+ (Ada), RTX 5000+ (Blackwell).

## 32. NVIDIA `kernel-open` Only Supports Turing+ (RTX 2000+)
**Problem (Precision T5810)**: nvidia-drivers built with `kernel-open` USE flag. On first
boot, both GTX 1050 Ti GPUs fail to probe:
```
NVRM: The NVIDIA GPU 0000:03:00.0 (PCI ID: 10de:1c82)
NVRM: nvidia.ko because it does not include the required GPU
nvidia probe with driver nvidia failed with error -1
```
No Xorg log created. LightDM reports "started" but X never launches — boots to CLI only.
`nvidia-smi` also fails (no GPU initialized).
**Root cause**: The `kernel-open` USE flag builds NVIDIA's open-source kernel modules,
which only support Turing (RTX 2000) and newer architectures. Pascal (GTX 10xx),
Maxwell, Kepler, and older GPUs require the proprietary closed-source modules.
**Fix**:
```bash
# In /etc/portage/package.use/<machine>:
x11-drivers/nvidia-drivers -kernel-open modules tools

# Rebuild
emerge -1 x11-drivers/nvidia-drivers
rc-service display-manager restart
```
**Impact**: Any machine with pre-Turing NVIDIA GPUs (GTX 1080, 1070, 1060, 1050,
Titan X Pascal, Quadro P-series, etc.) MUST use `-kernel-open`.
**Prevention**: kernel-config-template.sh and generate-config.sh should detect GPU
architecture from PCI ID and auto-set the correct USE flag.

## 29. Hostname Overridden by DHCP (OpenRC)
**Problem (ASRock B550)**: `/etc/hostname` was set correctly but DHCP client
overwrote hostname on boot, causing update-system.sh machine detection to fail.
**Fix**: Set hostname in BOTH locations:
```bash
echo "asrock-b550" > /etc/hostname
sed -i 's/^hostname=.*/hostname="asrock-b550"/' /etc/conf.d/hostname
```
**Impact**: update-system.sh and verify-install.sh rely on hostname for machine
detection. Boards with generic DMI (e.g. ASRock "To Be Filled By O.E.M.") cannot
fall back to DMI matching.
**Prevention**: Install scripts now set both files.

## 30. Desktop Profile Not Set in Headless Install
**Problem (ASRock B550)**: Part3 chroot install builds headless. After first boot,
no desktop environment — need to manually set desktop profile and emerge XFCE.
**Fix**: Post-install steps:
```bash
eselect profile set 3    # desktop profile
emerge --sync && emerge --update --deep --newuse @world
emerge xfce-base/xfce4-meta
echo "exec startxfce4" > ~/.xinitrc
gpasswd -a chris video
```
**Prevention**: Part3 scripts now use `default/linux/amd64/23.0/desktop` profile.

## 31. Stale EFI Boot Entries from Previous OS
**Problem (ASRock B550)**: After installing Gentoo over Fedora + Windows, old EFI
boot entries remained (Fedora, Windows Boot Manager, duplicates).
**Fix**: Clean up manually after install:
```bash
efibootmgr                    # list entries
efibootmgr -b 0000 -B        # delete by number
```
**Impact**: Cosmetic — old entries may appear in BIOS boot menu but won't boot.
**Prevention**: Varies by machine. Not scriptable since entry numbers differ.

## 32. set -euo pipefail Kills Install Scripts on Benign Failures
**Problem (ASRock B550)**: Part1 and part3 scripts die on commands that return
non-zero in normal operation (grep with no match, ls with missing globs, blkid
before kernel picks up new partitions).
**Fix**: Guard all commands that can legitimately return non-zero:
```bash
grep pattern file || true                              # grep no-match
ls /boot/vmlinuz-* 2>/dev/null || echo "[WARN] ..."    # glob no-match
$(blkid ... 2>/dev/null || echo 'NOT FOUND')           # blkid timing
```
**Prevention**: Audit all scripts with pipefail in mind. Any bare grep, ls with
globs, or command substitution that can fail needs a guard.

## 33. Fingerprint (fprintd): USE=pam, and never touch system-auth
**Problem (XPS 9510, Goodix `27c6:63ac`)**: three separate traps, in the order
you hit them.

**1. `USE=pam` is not implied.** `emerge sys-auth/fprintd` without it gives you
a package that installs, enrolls fingers, and verifies them from the command
line — while PAM has no `pam_fprintd.so` to load. Everything looks correct and
nothing ever prompts for a finger:
```
sys-auth/fprintd pam -systemd
```
Already installed without the flag? The re-emerge is not optional; nothing else
signals the difference.

**2. Do not add `pam_fprintd.so` to `/etc/pam.d/system-auth`.** It is included
by sudo, su, login, sshd and the display manager alike, so the reader gets
wired into *every* authentication including remote ones — and pam_fprintd on a
session with no physical console prompts for a finger nobody can provide, so an
ssh login hangs until it times out. On Gentoo there is a second reason:
system-auth is generated by `sys-auth/pambase`, so a hand-edit becomes a
dispatch-conf conflict you re-resolve forever, and losing that merge silently
disables the fingerprint — or silently re-enables it on ssh. Edit
`/etc/pam.d/sudo` instead, `sufficient` and *above* the include line. Below the
include, the password prompt has already run and the fingerprint is never
reached.

**3. `/etc/pam.d/sudo` is CONFIG_PROTECTed.** Every `app-admin/sudo` upgrade
leaves `._cfg0000_sudo` beside it, and accepting the new file wholesale in
dispatch-conf drops your fingerprint line without a word.

**Version trap specific to this sensor**: Gentoo stable `sys-auth/libfprint` is
1.94.7, the exact version reported broken for PID 63AC — enrollment fails with
`Corrupted message header received` after 63AC was added to goodixmoc's PID
table. Dell's TOD blob covers only the Goodix 53xc family, so `USE=tod` cannot
rescue it; keep `-tod`. The known-good version on identical hardware is
1.94.100, which is not in `::gentoo`, so `~amd64` (1.94.10) is the best
available starting point.

**Fix**: `sudo bash shared/fingerprint-setup.sh`, which checks all of the above
before editing anything and reverts with `REVERT=1`.
**Prevention**: keep fingerprint on `sudo` only. The XFCE screen locker is a
trap of its own — see the header of that script; on the sibling Arch machine
adding pam_fprintd there made the *password* stop working.
