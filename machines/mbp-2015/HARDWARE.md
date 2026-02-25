# MacBook Pro 12,1 (Early 2015) — Hardware Reference

## System Overview

| Field | Value |
|-------|-------|
| Model | MacBookPro12,1 (Mac-E43C1C25D4880AD6) |
| CPU | Intel Core i7-5557U @ 3.10GHz (Broadwell, 2C/4T) |
| GPU | Intel Iris Graphics 6100 (Broadwell GT3, i915) |
| RAM | 16GB DDR3 (soldered) |
| Storage | Apple SSD SM0256G (Samsung OEM, 256GB, AHCI) |
| Display | 13.3" 2560x1600 Retina (eDP-1), 227 PPI |
| WiFi | Broadcom BCM43602 (brcmfmac, 802.11ac, 3x3 MIMO VHT) |
| Bluetooth | Broadcom BCM20703A1 (btusb + btbcm) |
| Audio | Cirrus Logic CS4208 (HDA Intel PCH) + Intel Broadwell HDMI |
| Camera | Broadcom 720p FaceTime HD (PCI, no driver — needs out-of-tree facetimehd) |
| Trackpad | bcm5974 Force Touch clickpad |
| Keyboard | Apple Internal (hid_apple, fnmode=3) |
| Kbd backlight | smc::kbd_backlight (0-255, via applesmc) |
| Thunderbolt | Intel Falcon Ridge DSL5520 (Thunderbolt 2, 2 ports) |
| Thermal | applesmc (35 sensors, 1 fan 1299-6199 RPM) |
| Battery | Li-ion, ~82% health @ 304 cycles |
| Sleep | S3 deep (supported and default) |
| EFI | Apple EFI v1.1, 64-bit, no Secure Boot |
| Board BIOS | 489.0.0.0.0 |

## Kernel

- **Version**: Linux 6.18.12-gentoo
- **Compiler**: `-march=broadwell -O2 -pipe`
- **Preempt**: PREEMPT (full, via PREEMPT_DYNAMIC)
- **NR_CPUS**: 4
- **THP**: always
- **MGLRU**: enabled
- **Initramfs**: dracut

## PCI Devices

```
00:00.0 Host bridge: Intel Broadwell-U Host Bridge
00:02.0 VGA: Intel Iris Graphics 6100
00:03.0 Audio: Intel Broadwell-U Audio Controller (HDMI)
00:14.0 USB: Intel Wildcat Point-LP xHCI
00:15.0 DMA: Wildcat Point-LP Serial IO DMA
00:15.4 SPI: Wildcat Point-LP Serial IO GSPI
00:16.0 MEI: Wildcat Point-LP MEI Controller
00:1b.0 Audio: Wildcat Point-LP HD Audio (CS4208)
00:1c.x PCI bridges (5 root ports)
00:1f.0 ISA: Wildcat Point-LP LPC Controller
00:1f.3 SMBus: Wildcat Point-LP SMBus Controller
00:1f.6 Thermal: Wildcat Point-LP Thermal Management
02:00.0 Camera: Broadcom 720p FaceTime HD
03:00.0 WiFi: Broadcom BCM43602 802.11ac
04:00.0 SATA: Samsung S4LN058A01 AHCI (Apple slot)
05-07:  Intel DSL5520 Thunderbolt 2 (Falcon Ridge)
```

## Key Drivers & Modules

| Device | Driver | Mode | Notes |
|--------|--------|------|-------|
| GPU | i915 | module | Broadwell GT3 Iris 6100 |
| WiFi | brcmfmac | module | Firmware: brcmfmac43602-pcie.bin |
| Bluetooth | btusb + btbcm | module | BCM20703A1 |
| Audio (analog) | snd_hda_intel + snd_hda_codec_cs420x | module | Cirrus Logic CS4208 (Apple variant) |
| Audio (HDMI) | snd_hda_codec_intelhdmi | module | Intel Broadwell HDMI |
| Trackpad | bcm5974 | module | Force Touch clickpad |
| Keyboard | hid_apple | built-in | fnmode=3 (auto) |
| Fan/thermal | applesmc + coretemp | module | 35 sensors, 1 fan |
| SSD | ahci | built-in | Samsung OEM, TRIM supported |
| Thunderbolt | thunderbolt | module | Falcon Ridge, ~2W idle |
| Backlight | apple_gmux + intel_backlight | module | 0-1388 range |
| Kbd backlight | applesmc | module | smc::kbd_backlight, 0-255 |
| Battery | ACPI battery + ACPI SBS | built-in/module | Apple Smart Battery System |

## Firmware

Loaded from `/lib/firmware/`:
- `brcm/brcmfmac43602-pcie.Apple Inc.-MacBookPro12,1.bin` — WiFi
- `brcm/brcmfmac43602-pcie.txt` — WiFi NVRAM (optional, missing — limits some 5GHz channels)
- `brcm/brcmfmac43602-pcie.clm_blob` — WiFi CLM (optional, missing)
- `regulatory.db` / `regulatory.db.p7s` — Wireless regulatory database
- Intel microcode via `sys-firmware/intel-microcode`

## Boot Parameters

```
libata.force=noncq reboot=pci fbcon=font:TER16x32 i915.enable_fbc=1 i915.enable_psr=2
```

- `libata.force=noncq` — Prevents SSD lockups on Apple SM0256G
- `reboot=pci` — Required for clean reboot on Apple EFI
- `fbcon=font:TER16x32` — Readable console font on Retina display
- `i915.enable_fbc=1` — Frame buffer compression (power saving)
- `i915.enable_psr=2` — Panel self-refresh (power saving)

## Audio

- **Sound server**: PipeWire 1.4.10 + WirePlumber (replaces PulseAudio)
- **Autostart**: `~/.config/autostart/gentoo-pipewire-launcher.desktop`
- **Codec**: Cirrus Logic CS4208, subsystem 0x106b7b00 (Apple variant)
- **Tip**: If speaker/headphone issues, try `options snd-hda-intel model=mbp11` in `/etc/modprobe.d/alsa.conf`

## Power & Thermal

- **Fan control**: mbpfan (min 1300 RPM, max 6199 RPM, polling 3s)
- **Sleep**: S3 deep (default), LID0/XHC1 wakeup disabled via `/etc/local.d/disable-wakeup.start`
- **SSD**: `libata.force=noncq` required, TRIM supported (max 2GB discard), no discard in fstab — use fstrim timer
- **Thunderbolt idle**: ~2W draw, consider blacklisting `thunderbolt` module if unused

## Swap & Memory

- **zram**: 4GB zstd compressed swap via zram-init
- **THP**: always (transparent huge pages)
- **MGLRU**: enabled (multi-gen LRU for better page reclaim)
- **Portage tmpfs**: 12GB at `/var/tmp/portage`

## Desktop Environment

- **DE**: XFCE with LightDM
- **Panel**: Top bar (appsmenu, tasklist, systray, pulseaudio, clock, actions) + bottom dock (autohide)
- **HiDPI**: Native 2560x1600 (no scaling by default; 2x scaling available via Gdk/WindowScalingFactor)

## Fn Row Hotkeys

| Key | XF86 Event | Action |
|-----|-----------|--------|
| F1 | XF86MonBrightnessDown | `xbacklight -dec 10` |
| F2 | XF86MonBrightnessUp | `xbacklight -inc 10` |
| F5 | XF86KbdBrightnessDown | smc::kbd_backlight -25 |
| F6 | XF86KbdBrightnessUp | smc::kbd_backlight +25 |
| F10 | XF86AudioMute | `amixer set Master toggle` |
| F11 | XF86AudioLowerVolume | xfce4-pulseaudio-plugin (native) |
| F12 | XF86AudioRaiseVolume | xfce4-pulseaudio-plugin (native) |

Configured via `setup-hotkeys.sh`. Brightness requires `acpilight` + `video` group membership.

## OpenRC Services

### Boot
acpilight, alsasound, elogind, modules, swap, sysctl, zram-init

### Default
NetworkManager, acpid, cronie, dbus, display-manager, mbpfan, sshd, sysklogd

## Known Issues / Not Working

- **FaceTime camera**: Requires out-of-tree [facetimehd](https://github.com/patjak/facetimehd) driver + firmware extraction
- **WiFi firmware**: `.txt` and `.clm_blob` files missing (non-fatal, may limit some 5GHz channels)
- **SD card reader**: May disappear after suspend/resume (xhci_hcd quirk needed)
- **Thunderbolt**: PCI resource warnings at boot are normal (no device connected)

## Portage

- **Profile**: `default/linux/amd64/23.0/desktop`
- **VIDEO_CARDS**: intel
- **INPUT_DEVICES**: libinput
- **CPU_FLAGS_X86**: aes avx avx2 f16c fma3 mmx mmxext pclmul popcnt rdrand sse sse2 sse3 sse4_1 sse4_2 ssse3
- **MAKEOPTS**: -j5 -l4
- **FEATURES**: parallel-fetch candy ccache
- **CCACHE**: 5GB at /var/cache/ccache
