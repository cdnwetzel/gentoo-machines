# XPS 13 9315 Gentoo Runbook (P1–P6)

Companion to `HANDOFF.md` (governing plan) — read it first. Operating rules
(HANDOFF §0) apply: verify every hardware claim on the live system, show
verification output, never pass a gate without evidence. Facts not confirmable
at writing time are marked **UNVERIFIED** with the command to check on the live
system. All referenced standalone files live in `configs/` next to this file —
copy paths are given verbatim in each phase.

Decisions already locked (HANDOFF verification log): Gentoo + OpenRC + glibc,
no-multilib, **dual-boot with Windows 11 kept** (not the original full wipe),
Sway + swaybar/i3status + foot, firefox-bin, distcc to T5810 (192.0.2.125),
RRAS auth = PAP (Duo MFA).

**As-built status (2026-10-16):** P1.0–P1.7 are done on the NVMe, and P1.8's
config deployment is done from the chroot (sway/foot configs, `~/.bash_profile`,
udev rules, EPP + mic-LED scripts, system-wide Firefox prefs). What is left
needs the booted laptop: `~/first-boot.sh` (copy of `first-boot.sh` here) (Wi-Fi, P1 gate evidence, camera
probe, optional suspend cycles). Hardware facts below were
re-checked on the live machine (HANDOFF "Live hardware audit"; full inventory in
`gentoo-machines/machines/xps-9315/HARDWARE.md`). The canonical build spec
(make.conf, package.*, env, world, fstab, grub) is
`gentoo-machines/machines/xps-9315/`; `configs/` here mirrors the portage files.

## P0 — go/no-go (reference only, already specified in HANDOFF §4/§9)

Boot a current Fedora Workstation live USB on the 9315 and verify:
camera (`cam --list`, still capture, Firefox WebRTC gum_test), audio
(speakers + mic — SoundWire "Dummy Output" failures exist on this model),
hotkeys spot check, BIOS storage mode. **P0 is not optional** — a subset of
9315 units (VSC on SPI1, intel/ipu6-drivers#458) have a camera that works on
no distro — **this unit is not one of them**: its VSC sits behind the LJCA USB
bridge (`8086:0b63`) and its firmware loads (live audit 2026-10-16). If the camera fails on Fedora, boot Ubuntu 24.04 live with
`ppa:oem-solutions-group/intel-ipu6` (`libcamhal0 libcamhal-ipu6ep0
gstreamer1.0-icamera v4l2-relayd`) and retest; if it only works there, the OS
choice changes to Ubuntu OEM and this runbook does not apply.

**Do not proceed to P1 without P0 output pasted into HANDOFF.md.**

While the Fedora USB is booted, capture ground truth for later phases:

```
uname -r                                  # kernel that made the camera work
zcat /proc/config.gz > fedora-kernel.config   # reference for the P5 kernel trim
rpm -ql intel-vsc-firmware                # exact firmware file paths for P3
lsusb; lspci -nnk                         # confirm Goodix 27c6:63ac, AX211, IPU6 8086:465d
```

## P1 — Base install: OS + kernel + Wi-Fi + audio + Sway

### P1.0 BIOS prerequisites (physical, before booting the installer)

1. F2 at boot → **Storage → SATA/NVMe Operation: RAID On → AHCI/NVMe**.
   MANDATORY: with RAID On the 9315 never reaches low-power S0ix — warm laptop,
   overnight battery drain. **Done** (NVMe enumerates at `01:00.0`, no VMD).
2. Secure Boot: Gentoo dist kernel is unsigned → disable Secure Boot, or plan
   for self-signing (out of scope; disable). **Done** (Secure Boot disabled).
3. Update BIOS via fwupd later in P6. BIOS at install: **1.39.0 (05/27/2026)**.

### P1.1 Boot media + network

Write the current Gentoo minimal install ISO (or LiveGUI) to USB. Boot it.
(As built: Gentoo LiveGUI from a Ventoy USB, SanDisk Ultra Fit.)

No ethernet port on this machine (2× TB4 only). Wi-Fi on the live ISO:

```
wpa_supplicant -B -i wlan0 -c <(wpa_passphrase "SSID" "passphrase")
dhcpcd wlan0
ping -c3 gentoo.org
```

Expected: `ping` succeeds. Fallback: phone USB-C tethering (rndis) if the ISO
lacks working iwlwifi firmware.

### P1.2 Disk layout (as built — dual-boot, 256 GB NVMe shared with Windows 11)

The full-wipe plan was dropped; Windows stays. Layout on disk:

```
# nvme0n1p1  500 MiB   vfat "ESP"     shared EFI System Partition (Windows Boot Manager + GRUB) — do NOT format
# nvme0n1p2  128 MiB   MSR            Windows reserved
# nvme0n1p3  157.9 GiB NTFS "OS"      Windows 11
# nvme0n1p4  80 GiB    ext4 "gentoo"  Gentoo /  (no separate /home)
mkfs.ext4 -L gentoo /dev/nvme0n1p4
mount /dev/nvme0n1p4 /mnt/gentoo
mkdir -p /mnt/gentoo/efi
# 8 GiB swapfile for llvm/clang-class builds (not in fstab; swapon by hand before big emerges)
fallocate -l 8G /mnt/gentoo/swap.install && chmod 600 /mnt/gentoo/swap.install
mkswap /mnt/gentoo/swap.install && swapon /mnt/gentoo/swap.install
```

### P1.3 Stage3 + Portage base config

```
cd /mnt/gentoo
# fetch stage3-amd64-nomultilib-openrc-*.tar.xz from a mirror (links/ wget), verify digest, then:
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc && mount --rbind /sys /mnt/gentoo/sys \
  && mount --make-rslave /mnt/gentoo/sys && mount --rbind /dev /mnt/gentoo/dev \
  && mount --make-rslave /mnt/gentoo/dev && mount --bind /run /mnt/gentoo/run \
  && mount --make-slave /mnt/gentoo/run
chroot /mnt/gentoo /bin/bash
source /etc/profile
emerge-webrsync
eselect profile list | grep no-multilib
eselect profile set default/linux/amd64/23.0/no-multilib   # must match the nomultilib stage3
```

**no-multilib, not desktop.** Nothing here needs 32-bit libraries (firefox-bin
is 64-bit; no Steam/Wine), and skipping the 32-bit ABI cuts build time on 8 GB.
Gentoo has no `no-multilib/desktop` profile, so the USE flags the desktop
profile would have turned on are set explicitly in make.conf instead — Wayland-
only, OpenRC, PipeWire:

```
USE="-X wayland dbus elogind -systemd udev"
USE="${USE} pipewire alsa -pulseaudio screencast"
USE="${USE} vaapi -vulkan"
USE="${USE} zstd lz4 -nls -doc -gtk-doc -examples"
USE="${USE} -cups -bluetooth -gnome -kde -qt5 -qt6 -gpm -ldap -kerberos -wifi"
```

Do not switch profiles between multilib and no-multilib on an installed system;
that needs a reinstall from the matching stage3. `configs/make.conf.snippet`
is the deployed `/etc/portage/make.conf` verbatim (CPU_FLAGS_X86 from
cpuid2cpuflags, `MICROCODE_SIGNATURES="-s 0x000906a4"`, `VIDEO_CARDS="intel"`,
distcc + gcc-16 pin — see P1.6). Then:

```
cp configs/make.conf.snippet /etc/portage/make.conf
mkdir -p /etc/portage/package.use /etc/portage/package.accept_keywords /etc/portage/package.env /etc/portage/env
cp configs/package.use/xps9315 /etc/portage/package.use/
cp configs/package.accept_keywords/xps9315 /etc/portage/package.accept_keywords/
cp configs/portage/package.env /etc/portage/package.env/00-notmpfs   # fleet name, tracked by deploy-portage.sh
cp configs/portage/env/*.conf /etc/portage/env/                      # j4, llvm, clang, notmpfs
mkdir -p /var/tmp/portage-disk
```

`/etc/fstab` (as deployed; real UUIDs from `blkid`):

```
UUID=<p4>   /                 ext4   noatime                     0 1
UUID=<esp>  /efi              vfat   noauto,noatime,umask=0077   0 2
tmpfs       /tmp              tmpfs  size=2G,nosuid,nodev,noatime 0 0
tmpfs       /var/tmp/portage  tmpfs  size=4G,uid=portage,gid=portage,mode=775,nosuid,nodev,noatime 0 0
```

(`/efi` is `noauto` deliberately — mounted only for kernel/bootloader updates.)

### P1.4 Kernel, firmware, bootloader

gentoo-kernel-bin first (binary dist kernel — bootable in minutes, stays
installed forever as the rescue kernel; the trimmed custom kernel is P5):

```
emerge --ask sys-kernel/installkernel sys-kernel/gentoo-kernel-bin sys-kernel/linux-firmware \
    sys-firmware/sof-firmware sys-firmware/intel-microcode     # installkernel[grub,dracut]
mount /efi
emerge --ask sys-boot/grub sys-boot/efibootmgr sys-boot/os-prober
# /etc/default/grub: GRUB_CMDLINE_LINUX_DEFAULT="quiet i915.enable_psr=0", GRUB_DISABLE_OS_PROBER=false
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=gentoo
grub-mkconfig -o /boot/grub/grub.cfg    # adds "Windows Boot Manager (on /dev/nvme0n1p1)"
```

As built: `gentoo-kernel-bin` 6.18.54, UEFI entry `gentoo` →
`\EFI\gentoo\grubx64.efi` on the shared ESP, dracut initramfs plus
`intel-uc.img`.

Kernel floor for the camera: **>= 6.12.19 LTS or >= 6.13.4** (9315 iVSC
ETIMEDOUT fix, RHBZ #2316918). Current gentoo-kernel-bin is far past this —
verify anyway: `emerge --info gentoo-kernel-bin | head -3`, and after reboot
`uname -r`.

### P1.5 Core userspace, services, user

```
emerge --ask net-wireless/iwd net-misc/dhcpcd net-dns/openresolv \
    sys-apps/dbus sys-auth/elogind app-admin/sysklogd net-misc/chrony \
    app-admin/sudo app-portage/gentoolkit sys-apps/earlyoom sys-power/thermald
# as built: all installed (openresolv 3.16.5 — P4's ip-up DNS hook needs it)
cp configs/iwd/main.conf /etc/iwd/main.conf
rc-update add dbus default
rc-update add iwd default
rc-update add dhcpcd default
rc-update add elogind boot
rc-update add sysklogd default
rc-update add chronyd default
rc-update add earlyoom default
rc-update add thermald default
rc-update add local default        # runs /etc/local.d/*.start (zram.start deployed; EPP in P5)
passwd                              # root — done
useradd -m -G wheel,audio,video,usb,input,portage user && passwd user   # done
mkdir -p /etc/sudoers.d && echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel && chmod 440 /etc/sudoers.d/wheel   # done (visudo -c OK)
```

Seat management: **elogind**, not seatd. Justification: Gentoo's Sway and
PipeWire documentation assumes logind semantics (XDG_RUNTIME_DIR setup, PAM
session hooks, `uaccess` device ACLs, OpenRC user-service session tracking);
seatd is lighter but leaves all of that to manual wiring. `sys-auth/seatd`
remains the fallback if elogind causes trouble ([Gentoo Sway
wiki](https://wiki.gentoo.org/wiki/Sway) "No backend was able to open a seat").

### P1.6 distcc (do this BEFORE the desktop emerge — it compiles llvm/mesa)

As built: working — 16–18 concurrent jobs to the T5810 during the clang build.

On the T5810 (192.0.2.125; distro-agnostic, Gentoo OpenRC variant shown):

```
emerge --ask sys-devel/distcc
echo 'DISTCCD_OPTS="--port 3632 --listen 192.0.2.125 --allow 192.0.2.0/24 --user distcc"' \
    >> /etc/conf.d/distccd
rc-update add distccd default && rc-service distccd start
gcc -dumpversion    # T5810 default is 15, laptop is 16 — the laptop pins CC/CXX to gcc-16 (below)
```

On the laptop:

```
emerge --ask sys-devel/distcc
cp configs/distcc/hosts /etc/distcc/hosts
# smoke test BEFORE enabling globally:
echo 'int main(){return 0;}' > /tmp/t.c
DISTCC_VERBOSE=1 distcc gcc -c /tmp/t.c -o /tmp/t.o 2>&1 | grep -i 192.0.2.125
```

Expected: verbose log shows the job going to 192.0.2.125. The deployed make.conf
then has `FEATURES="parallel-fetch distcc"`, `MAKEOPTS="-j24 -l10"`, and
`CC="x86_64-pc-linux-gnu-gcc-16"` / `CXX="x86_64-pc-linux-gnu-g++-16"` so remote
jobs use the laptop's gcc major (so the T5810 needs gcc-16 installed alongside
its default 15 — the clang build's remote jobs ran there, but confirm with
`ssh chris@192.0.2.125 ls /usr/bin/x86_64-pc-linux-gnu-gcc-16`). `/etc/distcc/hosts` is `192.0.2.125/40,lzo localhost/2`. llvm gets
`-j12`, clang `-j20` (env/llvm.conf, env/clang.conf), both on disk
(notmpfs.conf) — every link is local and 8 GB is tight, so `swapon
/swap.install` before them. `dev-lang/rust` compiles with rustc locally and
keeps `j4.conf`.

### P1.7 Desktop stack

As built (all merged 2026-10-16 except firefox-bin):

```
emerge --ask gui-wm/sway gui-apps/foot gui-apps/wmenu x11-misc/i3status \
    gui-apps/swaylock gui-apps/swayidle gui-apps/grim gui-apps/slurp gui-apps/wl-clipboard \
    media-video/pipewire media-video/wireplumber media-libs/libcamera \
    sys-apps/xdg-desktop-portal gui-libs/xdg-desktop-portal-wlr \
    media-libs/libva-intel-media-driver media-video/libva-utils \
    sys-power/acpilight media-fonts/dejavu media-fonts/noto-emoji
emerge --ask www-client/firefox-bin      # done (158.0)
```

Choices made during the build: bar = built-in swaybar + `i3status`
(`x11-misc/i3status[pulseaudio]`), not waybar (configs/waybar kept, not
deployed); brightness = `sys-power/acpilight` (`xbacklight`, ::gentoo) instead
of brightnessctl (::guru) — acpilight's `90-backlight.rules` makes
`intel_backlight` writable by group video; no Xwayland (`sway -X`, `wlroots -X`).
This set pulls llvm + clang + mesa: ~1 h with distcc and the swapfile on
(llvm 33 min, clang 20 min).

firefox-bin is a binary package — no compile. **Never** `emerge
www-client/firefox` (source) on this box; llvm-class source builds go through
distcc or `j4.conf`, Firefox doesn't get built at all.

### P1.8 First boot + session bootstrap

Reboot into the installed system. Log in as the user on tty1.

PipeWire/WirePlumber/pipewire-pulse start from the sway config via
`exec gentoo-pipewire-launcher restart` (as built). Reason: `~/.bash_profile`
starts sway under `dbus-run-session`, and the launcher runs PipeWire on that same
session bus, which the portals need. OpenRC 0.63's user services
(`rc-update -U add pipewire default`, from `/etc/user/init.d/`) would run on
the separate OpenRC user D-Bus instead. Revisit only if moving the whole session
to OpenRC user services, `dbus` included.

User configs:

```
mkdir -p ~/.config/sway ~/.config/foot
cp configs/sway/config ~/.config/sway/config      # swaybar + i3status, xbacklight bindings
cp configs/foot/foot.ini ~/.config/foot/foot.ini
```

`~/.bash_profile` additions:

```
export LIBVA_DRIVER_NAME=iHD        # intel-media-driver, NOT i965
export MOZ_ENABLE_WAYLAND=1         # belt-and-braces; modern FF auto-detects
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$WAYLAND_DISPLAY" ]; then
    exec dbus-run-session sway
fi
```

### GATE P1 — all must pass, paste outputs into HANDOFF.md

```
uname -r                                    # >= 6.12.19 (camera fix floor)
rc-update -v show | grep -E 'dbus|iwd|dhcpcd|elogind'   # all in expected runlevels
iwctl station wlan0 show                    # State: connected
dhcpcd -U wlan0 | head                      # lease with DNS
swaymsg -t get_outputs                      # eDP-1 1920x1200 current mode
wpctl status                                # Sink/Source from SOF SoundWire card, NOT "Dummy Output"
pw-play /usr/share/sounds/alsa/Front_Center.wav   # audible (emerge media-video/pipewire[extra] for pw-play)
aplay -l                                    # sof-soundwire card present
# suspend/resume x3:
grep . /sys/power/mem_sleep                 # expected: [s2idle]  (s2idle-only hardware)
loginctl suspend ; (wake) ; loginctl suspend ; (wake) ; loginctl suspend
dmesg | grep -iE 'PM: suspend|s2idle' | tail -5         # 3 clean cycles, no errors
# deep-sleep proof (AHCI fix working): needs debugfs + intel_pmc_core
mount -t debugfs none /sys/kernel/debug
a=$(cat /sys/kernel/debug/pmc_core/slp_s0_residency_usec); loginctl suspend; sleep 60; (wake)
b=$(cat /sys/kernel/debug/pmc_core/slp_s0_residency_usec); echo $((b-a))   # >> 0 = S0ix reached
# boot time: stopwatch GRUB->sway, cross-check last dmesg timestamp; target < 15 s
free -m                                     # record idle baseline for P5 comparison
```

## P2 — Hotkeys

Bindings already in `~/.config/sway/config` (copied in P1.8). Now prove every
Fn key emits what the config expects:

```
sudo libinput debug-events | grep -E 'KEY_'   # press each Fn key, one at a time
```

Expected keycodes (9315 physical Fn row, dell-wmi/atkbd; from Dell's keyboard
docs — no airplane-mode key on this model):

| Key | Expected |
|---|---|
| F1 | KEY_MUTE → XF86AudioMute |
| F2/F3 | KEY_VOLUMEDOWN/UP → XF86AudioLowerVolume/RaiseVolume |
| F4 | KEY_MICMUTE → XF86AudioMicMute |
| F6/F7 | KEY_BRIGHTNESSDOWN/UP → XF86MonBrightnessDown/Up |

Functional test of each binding inside sway (volume OSD = watch
`wpctl get-volume @DEFAULT_AUDIO_SINK@` change; brightness = watch
`xbacklight -get` / `cat /sys/class/backlight/intel_backlight/brightness`). Report any key that
emits nothing — none expected on the standard row.

**F4 mic-LED quirk** (LED stuck on regardless of state). On the live 7.2.5
kernel `/sys/class/sound/ctl-led/mic/mode` is already `follow-mute`, so check
the LED on the installed kernel first; the fix is a harmless safety net —

```
sudo cp configs/bin/mic-led-follow-mute /usr/local/bin/ && sudo chmod +x /usr/local/bin/mic-led-follow-mute
sudo cp configs/udev/91-mic-led.rules /etc/udev/rules.d/
sudo udevadm control --reload && sudo udevadm trigger --subsystem-match=sound
cat /sys/class/sound/ctl-led/mic/mode    # expected: follow-mute
```

**I2C spurious wake** (suspends, wakes ~4 s later): verify the device exists,
then install the rule —

```
ls /sys/bus/i2c/devices/ | grep VEN_0488   # confirmed 2026-10-16: i2c-VEN_0488:00 (the touchpad), wakeup=enabled
sudo cp configs/udev/90-i2c-wakeup.rules /etc/udev/rules.d/
sudo udevadm control --reload
cat /sys/bus/i2c/devices/i2c-VEN_0488:00/power/wakeup   # expected: disabled (after replug/reboot)
```

If the udev ATTR write doesn't stick (**UNVERIFIED** on this exact device —
test with `udevadm test /sys/bus/i2c/devices/i2c-VEN_0488:00`), fallback is an
`/etc/local.d/i2c-wakeup.start` script with the same `echo disabled` line.

**Fingerprint (optional, do not block P2):** `lsusb | grep 27c6` — confirmed
`27c6:63ac` on this unit (supported by libfprint goodixmoc). If instead `27c6:6382`:
unsupported, stop. Otherwise `emerge --ask sys-auth/fprintd`,
`rc-update add fprintd default`? — fprintd is dbus-activated, no service needed
(**UNVERIFIED** on OpenRC: check `equery f fprintd | grep -E 'init.d|dbus'`).
Enroll: `fprintd-enroll`. PAM wiring for swaylock/sudo is out of scope here.

### GATE P2

- `libinput debug-events` log showing every Fn-row key emitting its expected
  keycode, plus a screenshot/log of each binding doing its job.
- `cat /sys/class/sound/ctl-led/mic/mode` = `follow-mute`.
- Suspend for 10 min on battery: stays asleep (no 4-second wake), resume clean.

## P3 — Camera stack (IPU6 / OV01A10)

The chain: kernel (IPU6 staging + iVSC + ov01a10) → iVSC firmware → libcamera
"simple" pipeline + SoftISP → PipeWire libcamera plugin → xdg camera portal →
Firefox. Gentoo's ::gentoo `media-libs/libcamera` ebuild compiles the `simple`
pipeline unconditionally (verified in the 0.7.0-r1 ebuild:
`-Dpipelines=imx8-isi,ipu3,mali-c55,rkisp1,rpi/vc4,simple,uvcvideo,vimc`) — no
extra USE flag needed for the pipeline itself.

### P3.1 Kernel evidence first

```
uname -r                                                    # >= 6.12.19 floor
dmesg | grep -iE 'ipu6|ivsc|intel_vsc|vsc|ov01a10'
```

Expected: intel-ipu6 PCI probe (8086:465d at 00:05.0), iVSC device(s)
registering, ov01a10 sensor probe. Observed on the live 7.2.5 kernel
(2026-10-16): IPU6 "Found supported sensor OVTI01A0:00 / Connected 1 cameras",
iVSC firmware loaded, but `i2c-OVTI01AB:00` stuck in deferred probe ("ov01a10:
waiting for fwnode graph endpoint") and `ivsc_csi: mei-csi probed without
device fwnode` — check `cat /sys/kernel/debug/devices_deferred` for the same
signature on 6.18.54. **Failure signatures:** `ETIMEDOUT` (needs the 6.12.19/6.13.4 fix
— should not happen on current gentoo-kernel-bin; if it does, the kernel is too
old) or `EINVAL` / total absence of iVSC messages (see STOP condition, P3.4).

### P3.2 iVSC firmware

**Resolved:** `sys-kernel/linux-firmware` already ships it —
`/lib/firmware/intel/vsc/ivsc_fw.bin`, `ivsc_pkg_ovti01a0_0.bin`,
`ivsc_skucfg_ovti01a0_0_1.bin` are on the installed system and load on this
unit. The manual route below is only for a firmware-missing error.

Fedora ships this as `intel-vsc-firmware`; on Gentoo:

```
emerge --search vsc-firmware ; eix vsc   # check ::gentoo and overlays first
```

If nothing: manual install from Intel's repo —

```
git clone https://github.com/intel/ivsc-firmware /tmp/ivsc-firmware
ls /tmp/ivsc-firmware/firmware/    # identify the *.bin set (ivsc_fw.bin etc.)
sudo cp /tmp/ivsc-firmware/firmware/*.bin /lib/firmware/vsc/   # create dir if needed
```

Cross-check exact filenames/destination against the Fedora live USB ground
truth captured in P0 (`rpm -ql intel-vsc-firmware`). Reboot, re-run the P3.1
dmesg check — firmware load errors disappear.

### P3.3 libcamera + PipeWire + portal

```
sudo cp configs/udev/99-udmabuf.rules /etc/udev/rules.d/   # SoftISP needs udmabuf access
zgrep -E 'UDMABUF|DMABUF_HEAPS' /proc/config.gz            # expect =y/=m
sudo udevadm control --reload
cam --list
```

Expected: a camera entry naming ov01a10 / IPU6. Then:

```
cam -c 1 --capture=5 --file=/tmp/cam-test-    # writes 5 frames
ls -la /tmp/cam-test-*                         # non-zero-size frames = SoftISP capturing
wpctl status                                   # "Video" section lists the libcamera device
ps aux | grep -E 'xdg-desktop-portal'          # portal + -wlr both running (dbus-activated)
firefox &   # about:support -> "Window Protocol: wayland"; then open
            # https://mozilla.github.io/webrtc-landing/gum_test.html -> Start Camera
```

Expected: live preview in gum_test. Screenshot it for the gate.

### P3.4 Fallback ladder (in order — stop at the first rung that works)

1. **Kernel too old / firmware missing** — re-check P3.1/P3.2. An `ETIMEDOUT`
   on iVSC with a kernel >= 6.13.4 means firmware, not kernel.
2. **`cam --list` empty but iVSC probed fine** — the ::gentoo `simple` pipeline
   isn't binding the OV01A10. Patch sources, in order:
   - nagmat84's Gentoo overlay (IPU6 ebuilds, "nearly working" Jun 2025 on an
     X1 Carbon): `eselect repository add mhnnet git
     https://github.com/nagmat84/mhnnet-ebuild-repository` (**UNVERIFIED**
     current state — read its libcamera ebuild before emerging).
   - Arch AUR `libcamera-ipu6` (kervel fork, explicit OV01A10 support): fetch
     the PKGBUILD, extract its patches, drop them into
     `/etc/portage/patches/media-libs/libcamera/` and re-emerge libcamera.
3. **STOP condition** — iVSC never instantiates at all: `dmesg` shows the IPU6
   PCI device but no iVSC/SPI probe whatsoever (the unit declares VSC on the
   native SPI1 controller; intel/ipu6-drivers#458). **Does not apply to this
   unit** — its VSC is on the LJCA USB bridge and probes. Kept for reference:
   such a unit's camera works on NO distro's FOSS stack. Do not burn more time: the project's OS becomes
   **Ubuntu 24.04 + `ppa:oem-solutions-group/intel-ipu6`** (libcamhal0
   libcamhal-ipu6ep0 gstreamer1.0-icamera v4l2-relayd) — per the P0 fallback
   test, that's what the Ubuntu live USB already proved. Fallback ladder for the
   OS overall (HANDOFF verification log): Fedora Sway spin > Ubuntu 24.04+OEM >
   Void.
4. Cosmetic note: the dell-privacy WMI bug (WQBC) means camera privacy toggles
   don't work via WMI on the 9315 — a black image is NOT the privacy shutter;
   don't chase it in software.

### GATE P3

- `dmesg` iVSC/ipu6/ov01a10 excerpt with no probe errors.
- `cam --list` output showing the OV01A10.
- Captured still frames on disk (`file /tmp/cam-test-*` shows image data).
- Firefox gum_test screenshot with live video (or the documented STOP
  condition with dmesg evidence and the OS-change recommendation).

## P4 — SSTP VPN (RRAS, PAP auth)

**Prereqs to collect from the firm before starting (HANDOFF §10):** RRAS
server cert or issuing CA in PEM, cert CN/SAN, TLS floor (TLS 1.2-only? then
the SECLEVEL wrapper is likely unnecessary), Duo mode (auto-push vs
append `password,push`).

Security posture (HANDOFF §6, settled): PAP means **no MPPE is possible**
(session keys need MS-CHAPv2 material) — `nomppe` is correct, not a downgrade;
the TLS tunnel carries the encryption and **server-cert pinning is the security
boundary**. No `--cert-warn` in steady state. No NetworkManager anywhere in
this path (CVE-2026-91838 was filed against Ubuntu's NM plugin; irrelevant
here but reinforces the choice).

### P4.1 Install + configure

```
emerge --ask net-dialup/ppp net-misc/sstp-client   # sstp-client 1.0.18-r2 in ::gentoo (stable amd64)
type -a sstpc                                       # confirm wrapper exec target (expected /usr/sbin/sstpc)
ls /usr/lib*/pppd/*/sstp-pppd-plugin.so             # confirm plugin path
sudo cp configs/ppp/peers/rras /etc/ppp/peers/rras  # preset: user vpnuser, vpn.example.com; CA path
sudo cp configs/ppp/openssl-sstp.cnf /etc/ppp/
sudo cp configs/bin/sstpc-rras /usr/local/sbin/ && sudo chmod +x /usr/local/sbin/sstpc-rras
sudo cp configs/ppp/ip-up.d/00-rras-dns /etc/ppp/ip-up.d/ && sudo chmod +x /etc/ppp/ip-up.d/00-rras-dns
sudo cp configs/ppp/ip-down.d/00-rras-dns /etc/ppp/ip-down.d/ && sudo chmod +x /etc/ppp/ip-down.d/00-rras-dns
sudo cp configs/ppp/pap-secrets.example /etc/ppp/pap-secrets  # then EDIT real credentials
sudo chmod 600 /etc/ppp/pap-secrets
sudo cp <firm-provided>.pem /etc/ppp/rras-ca.pem
```

If the pppd plugin isn't found by bare name, change `plugin
sstp-pppd-plugin.so` to the absolute path from the `ls` above.

### P4.2 Debug-first connect (TLS handshake visible)

```
sudo sstpc --log-level 4 --log-stderr --ca-cert /etc/ppp/rras-ca.pem \
    --tls-ext vpn.example.com --user 'vpnuser' --password 'xxx' --nolaunchpppd
```

Expected: TLS handshake completes, cert verifies (NO --cert-warn), PPP starts
speaking. Failure decoding:

- `certificate verify failed` with a modern-looking cert → wrong CA/CN; fix the
  PEM or add `--host` when dialing by IP.
- handshake alert / `ssl fatal alert` with an old cert (SHA-1/RSA-1024) → this
  is the case the `sstpc-rras` OPENSSL_CONF SECLEVEL=1 wrapper exists for; the
  peers file already routes through it. Confirm the wrapper is the fix by
  retesting via the wrapper.
- connects then drops within seconds → check MTU: the peers file already sets
  `mtu 1400 mru 1400`; large-packet blackholing over tunnels is a classic RRAS
  issue. Do NOT raise MTU; lower to 1380 if needed.

### P4.3 Normal operation

```
sudo pon rras && sleep 5
ip addr show ppp0                    # inet addr from firm range
ip route | grep ppp0                 # firm subnets routed
cat /etc/ppp/resolv.conf ; resolve: ping -c3 <firm-internal-host>
tail -30 /var/log/messages           # pppd/sstpc log lines (sysklogd from P1)
sudo poff rras
```

Auto-reconnect is in the peers file (`persist maxfail 0`) — test it:
`sudo pon rras`, then `sudo pkill sstpc`, watch `/var/log/messages` for the
reconnect cycle.

No dedicated OpenRC service: `pon/poff` on demand is the design. If boot-time
auto-connect is wanted later, a 5-line `/etc/local.d/rras.start` (`pon rras`)
suffices — decide in P6.

### GATE P4

- `ip addr show ppp0` with firm-range address, routes present, firm DNS working.
- **10-minute soak**: `ping -i 30 -c 20 <firm-host>` with 0% loss and the
  session still up at the end (`ip addr show ppp0` again).
- Kill-and-reconnect test logged from `/var/log/messages`.
- Paste the cert-verification line from the `--log-level 4` run proving
  `--cert-warn` is NOT in use.

## P5 — Performance pass (HANDOFF §7, in gain order)

Record all "before" numbers first (from P1 gate): idle `free -m`, boot
stopwatch, `s-tui` sustained clocks. Every change below gets an "after"
number.

### P5.1 Memory: zram vs zswap — DECISION POINT

8 GB soldered RAM is the wall. Both configs are ready; pick with measurement,
not doctrine:

- **zram** (HANDOFF default; zero NVMe wear):
  `sudo cp configs/local.d/zram.start /etc/local.d/ && sudo chmod +x /etc/local.d/zram.start`
  then uncomment Variant A in `/etc/sysctl.d/90-memory.conf`
  (`vm.swappiness=180`, watermark tweaks). 4 GiB zstd zram, swap priority 100.
  (Packaged alternative: `sys-block/zram-init` — cleaner OpenRC integration,
  **UNVERIFIED** conf path: `equery f zram-init | grep conf.d`.)
- **zswap** (Chris Down Mar-2026 guidance: degrades better under sustained
  pressure; needs a backing device): the existing 8 GiB `/swap.install`
  (rename to `/swapfile` and add an fstab line, or shrink it — there is no
  separate /home on this install),
  kernel args `zswap.enabled=1 zswap.compressor=zstd zswap.max_pool_percent=25
  zswap.zpool=zsmalloc` in `GRUB_CMDLINE_LINUX_DEFAULT` + `grub-mkconfig`, and
  Variant B sysctl (`vm.swappiness=120`).

```
sudo cp configs/sysctl.d/90-memory.conf /etc/sysctl.d/   # edit: uncomment ONE variant
sudo sysctl --system
```

Measurement protocol: open the real Firefox workload + a compile (`emerge
--oneshot llvm-core/llvm` with distcc is a good stressor), watch `vmstat 1`
si/so columns, `zramctl` or `grep . /sys/kernel/debug/zswap/*`. The variant
with less thrash and no earlyoom kills wins. Keep the loser's config file for
reversal.

### P5.2 earlyoom (no systemd-oomd on OpenRC)

```
emerge --ask sys-apps/earlyoom        # ~amd64 at writing time — accept_keywords file from P1.3
sudo cp configs/conf.d/earlyoom /etc/conf.d/earlyoom
rc-update add earlyoom default && rc-service earlyoom start
rc-service earlyoom status            # running
pgrep -a earlyoom                     # shows the -m 5 -s 20 args
```

### P5.3 thermald

```
emerge --ask sys-power/thermald       # ~amd64 at writing time
rc-update add thermald default && rc-service thermald start
rc-service thermald status            # running
dmesg | grep -i thermal               # no errors
```

### P5.4 EPP AC/battery toggle (intel_pstate)

```
sudo cp configs/bin/epp-toggle /usr/local/bin/ && sudo chmod +x /usr/local/bin/epp-toggle
sudo cp configs/udev/90-epp-power.rules /etc/udev/rules.d/
sudo cp configs/local.d/epp-toggle.start /etc/local.d/ && sudo chmod +x /etc/local.d/epp-toggle.start
sudo udevadm control --reload && sudo /usr/local/bin/epp-toggle
cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
```

Expected: `balance_performance` on AC. Unplug → same command →
`balance_power`. Re-plug → back. Do NOT set `performance` — on a 12 W-chassis
machine the governor difference is noise and the thermals are real.

### P5.5 Firefox

```
# as built: system-wide defaults, so no profile needs to exist first
sudo install -m 644 configs/firefox/xps9315-prefs.js /opt/firefox/defaults/pref/
# per-profile alternative: cp configs/firefox/user.js ~/.mozilla/firefox/<profile>/user.js
```

Verify in-browser: `about:support` → Compositing `WebRender`, Window Protocol
`wayland`; `about:config` → `dom.ipc.processCount` = 4 (range 2–4 per the
HANDOFF amendment — default 8 wastes RAM at 8 GB). VA-API proof: play a 1080p
VP9/AV1 YouTube video, `sudo intel_gpu_top` shows the Video engine busy while
CPU stays low. `about:memory` before/after the processCount change → paste both
numbers.

### P5.6 distcc final check + heavy-package policy

If the P1.6 smoke test passed, confirm `FEATURES="distcc"` active and run one
real offload: `emerge --oneshot --verbose dev-libs/boost` (or any mid-size C++
package) while `distccmon-text 2` shows jobs on 192.0.2.125. If T5810 is
unreachable on a given day, distcc falls back to local compile automatically —
slower, not broken. `dev-lang/rust` never offloads (rustc); it stays on
`j4.conf`.

### P5.7 Kernel trim (optional substep; gentoo-kernel-bin stays installed as rescue)

Goal: only this hardware compiled in → smaller kernel, faster boot, less RAM.
Approach: seed from the proven dist config, trim by checklist.

```
emerge --ask sys-kernel/gentoo-sources
zcat /proc/config.gz > /usr/src/linux/.config   # current dist kernel config as seed
cd /usr/src/linux && make olddefconfig && make menuconfig
```

KEEP (checklist — grep the Fedora P0 config for ground truth on uncertain
names; several marked **UNVERIFIED** below):

- CPU/power: `CONFIG_X86_INTEL_PSTATE`, `CONFIG_INTEL_PMC_CORE` (S0ix residency
  debug), `CONFIG_SUSPEND`, `CONFIG_PM_SLEEP`, `CONFIG_INTEL_RAPL` (measurement
  only — do not use it to raise limits).
- GPU: `CONFIG_DRM_I915` (+ its display/HDA subdeps via olddefconfig).
- Camera: `CONFIG_MEDIA_PCI_SUPPORT`, `CONFIG_VIDEO_INTEL_IPU6`, `CONFIG_IPU_BRIDGE`,
  `CONFIG_INTEL_VSC` (ivsc-csi/ace) **and** `CONFIG_INTEL_MEI_VSC_HW`,
  `CONFIG_USB_LJCA` (+GPIO/I2C/SPI_LJCA — this unit's VSC is behind the LJCA
  USB bridge), `CONFIG_INTEL_SKL_INT3472`, `CONFIG_PINCTRL_TIGERLAKE`,
  `CONFIG_VIDEO_OV01A10`, `CONFIG_UDMABUF`, `CONFIG_DMABUF_HEAPS`(+`_SYSTEM`).
  All present in the dist config; see gentoo-machines INSTALL_GOTCHAS #34.
- Audio: `CONFIG_SND_SOC_SOF_INTEL_TOPLEVEL` chain incl. `SND_SOC_SOF_ALDERLAKE`,
  `SND_SOC_SOF_INTEL_SOUNDWIRE`, machine driver
  `SND_SOC_INTEL_SOUNDWIRE_SOF_MACH`, codecs `CONFIG_SND_SOC_RT1316_SDW` (amp,
  sdw 025d:1316) and `CONFIG_SND_SOC_RT715_SDCA_SDW` (binds the RT714, sdw
  025d:0714). Verified against the hardware and the 6.18.54 dist config
  2026-10-16; already in `gentoo-machines/machines/xps-9315/kernel_config.sh`.
- Wi-Fi/BT: `CONFIG_IWLWIFI`, `CONFIG_IWLMVM`, `CONFIG_BT_INTEL`.
- Storage: `CONFIG_BLK_DEV_NVME`, `CONFIG_EXT4_FS`, `CONFIG_VFAT_FS`.
- Thunderbolt/USB4: `CONFIG_USB4`, `CONFIG_THUNDERBOLT` (only 2 ports on this
  box; keep for docks/charging).
- Platform/hotkeys: `CONFIG_DELL_LAPTOP`, `CONFIG_DELL_WMI`,
  `CONFIG_DELL_SMBIOS`, `CONFIG_INTEL_HID_EVENT`, `CONFIG_I2C_HID_ACPI`
  (touchpad), `CONFIG_HID_MULTITOUCH`.
- Memory: `CONFIG_ZRAM`, `CONFIG_ZSWAP`, `CONFIG_CRYPTO_ZSTD`,
  `CONFIG_ZSMALLOC`.
- USB tethering fallback: `CONFIG_USB_USBNET`, `CONFIG_USB_NET_RNDIS_HOST`.

DROP:

- Other NIC vendors entirely (no ethernet port): all `CONFIG_ETHERNET`
  vendor submenus; other Wi-Fi (ath9k/ath10k/ath11k, rtlwifi, brcmfmac,
  mt76...).
- Other GPU drivers: amdgpu, radeon, nouveau, all ARM SoC DRM drivers.
- Other sound: HD-audio legacy codecs not used, AMD/ARM SoC sound, all
  non-Intel SoundWire machine drivers.
- Other media: all DVB, analog TV, every camera sensor except OV01A10, other
  ISP drivers.
- Filesystems: btrfs, xfs, f2fs, reiserfs, jfs, nfs server, etc. (keep only
  ext4/vfat + pseudo-fs).
- Debug: `CONFIG_DEBUG_KERNEL` family, KGDB, FTRACE/KPROBES, scheduler debug,
  `CONFIG_DEBUG_INFO*`.
- **NOT** `mitigations=off` (cmdline) — security regression for single-digit %
  at most on Alder Lake; rejected as a default (HANDOFF §7/§11). Same for RAPL
  power-limit raises: measurement-gated experiments only, never defaults.

Build and install alongside, never instead of, the dist kernel:

```
make -j10 && sudo make modules_install && sudo make install
mount /efi && sudo grub-mkconfig -o /boot/grub/grub.cfg   # both kernels get entries
```

Boot the custom kernel, re-run P1 gate's smoke subset (wifi/audio/suspend/
`wpctl status`) and P3's `cam --list`. If anything regresses, boot the dist
kernel from the GRUB menu and fix the config.

### P5.8 Service audit

```
rc-update -v show                 # everything listed must justify itself
ps aux --sort=-rss | head -20     # idle desktop: target < 400 MB total used
free -m                           # 'used' column at idle sway+swaybar+i3status+pipewire
```

Expected idle composition: sway+swaybar+i3status+foot-server+pipewire+wireplumber+elogind
+dbus+sysklogd ≈ 250–380 MB. Anything outside that set over ~20 MB RSS needs a
reason.

### GATE P5 — before/after table in HANDOFF.md

| Metric | Before (P1 gate) | After | Target |
|---|---|---|---|
| Boot GRUB→sway (s) | | | < 15 |
| Idle RAM used (MB) | | | < 400 |
| s-tui sustained all-core clock / package W | | | record, no target — chassis-capped ~12 W PL1 |
| Firefox about:memory (10-tab workload) | | | processCount effect visible |
| Powertop idle discharge estimate (battery) | | | supports >= 6 h light use |

`emerge --ask sys-power/s-tui sys-power/powertop` for the measurement tools.

## P6 — Hardening, backups, docs

1. **Configs in git**: `configs/` in this project directory already holds the
   canonical copies; add `/etc/portage/{make.conf,package.use,package.accept_keywords,package.env}`
   and `/etc/ppp/peers/rras` (NO secrets — pap-secrets never enters git) to the
   same repo. `git init` here if not already done.
2. **Backup**: rsync to HOME storage, weekly via cron (`emerge --ask
   sys-process/cronie`, `rc-update add cronie default`):

   ```
   # /etc/cron.weekly/backup-home (chmod +x)
   rsync -aAXH --delete /home/ /mnt/backup/xps9315/home/
   rsync -aAXH /etc/ /mnt/backup/xps9315/etc/
   ```
3. **Rollback plan**: gentoo-kernel-bin stays installed (GRUB fallback entry);
   before any `@world` major upgrade or kernel trim, `tar` snapshot of `/etc`
   and `/var/db/pkg` into the backup target; quick-emergeable binary packages
   (`FEATURES="buildpkg"` or getbinpkg for the big ones) so a broken @world can
   be reverted without a 10-hour rebuild.
4. **Firmware maintenance**: `emerge --ask sys-apps/fwupd`, `fwupdmgr
   refresh && fwupdmgr update` — Dell pushes 9315 BIOS/Thunderbolt firmware
   via LVFS.
5. **Final state dump** — paste into HANDOFF.md as the closing entry:
   `lsblk -f`, `rc-update -v show`, `uname -a`, `free -m`, the P5 gate table,
   and a one-line confirmation per phase gate.

### GATE P6

- `git log` in the project repo shows configs tracked; no secrets committed
  (`git grep -l password` empty outside *.example files).
- One full backup cycle completed and a test-restore of one file shown
  (`rsync` dry-run diff or actual restore of a scratch file).
- Rollback demonstrated: boot the gentoo-kernel-bin GRUB entry once, confirm
  desktop comes up, boot back.

## Appendix — UNVERIFIED items collected (check each on the live system)

| Item | Check command |
|---|---|
| ~~brightnessctl repo~~ — moot: acpilight (::gentoo) used instead | — |
| ~~intel-vsc-firmware packaged on Gentoo~~ — RESOLVED: in linux-firmware (`intel/vsc/`) | — |
| ~~Exact iVSC sub-symbols + SoundWire codec symbol names~~ — RESOLVED 2026-10-16 (P5.7 list) | — |
| zram-init conf file path | `equery f zram-init \| grep conf.d` |
| sstpc binary path (/usr/sbin assumed in wrapper) | `type -a sstpc` |
| sstp-pppd-plugin.so resolved by bare name | `ls /usr/lib*/pppd/*/` |
| ~~thermald/earlyoom still ~amd64~~ — RESOLVED: both merged stable (thermald 2.5.11, earlyoom 1.7-r1), no keywords needed | — |
| fprintd activation model on OpenRC (dbus vs service) | `equery f fprintd \| grep -E 'init.d\|dbus'` |
| I2C wakeup udev ATTR write sticks for i2c-VEN_0488:00 | `udevadm test /sys/bus/i2c/devices/i2c-VEN_0488:00` |
| ~~VIDEO_CARDS tokens for mesa~~ — RESOLVED: mesa 26.1.8 takes `intel` (no `iris` token) | — |
| RRAS facts still owed by firm (HANDOFF §10): TLS floor, cert CN/SAN, Duo append-vs-push | ask before P4 |

## Known plan/research tensions (resolved in this runbook)

- HANDOFF §7 says zram + swappiness 180; the verification log (Chris Down,
  Mar 2026) favors zswap. → P5.1 decision point, both configs shipped.
- HANDOFF §7 says Firefox processCount 4–6; amendment says 2–4 at 8 GB. →
  user.js sets 4, range documented.
- HANDOFF §4 rejects X11 as a camera blocker; verification finding 8 shows the
  camera portal is display-server-agnostic. Sway/Wayland kept anyway (scaling,
  screen sharing, modern stack) — no action.
- SSTP research report's generic recipe uses MS-CHAPv2 + require-mppe +
  chap-secrets; superseded by user-confirmed PAP → nomppe + pap-secrets +
  cert pinning (HANDOFF §6 rewrite governs).
- Distro research agent recommended Ubuntu/KDE; user explicitly chose Gentoo +
  Sway. This runbook implements the user's choice; Ubuntu 24.04 OEM remains
  the documented fallback OS if P0/P3 hits the STOP condition.
