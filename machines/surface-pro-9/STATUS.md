# Surface Pro 9 (i5-1235U, Alder Lake) — STATUS

**Status**: Production — **Fedora 45** (GNOME, Wayland) on the linux-surface kernel. Not Gentoo.
Windows 11 Pro was removed; the NVMe is Linux-only.

Installed and tuned 2026-11-21/22. Everything below was checked on the running system unless
marked otherwise.

## Hardware (from the running install, 2026-11-21)

- CPU: i5-1235U (Alder Lake-U, 2P+8E, 12 threads). Microcode 0x43b (`microcode_ctl`).
- RAM: 8 GB (7.6 GiB usable). zram 7.6 GiB (zstd), no disk swap.
- Storage: 256 GB NVMe — p1 600 MB ESP (vfat), p2 2 GB `/boot` (ext4), p3 235 GB btrfs (`root` + `home` subvolumes).
- GPU: Iris Xe (i915), VA-API via `iHD` (libva-intel-media-driver 26.3.5).
- Wi-Fi/BT: Intel AX211 CNVi `8086:51f0` (iwlwifi) — no quirks needed (the SP6's Marvell workarounds don't apply).
- Touch/pen: IPTS via MEI, `045E:0C52` — needs the linux-surface kernel + `iptsd` (no touch device at all on the stock kernel).
- Surface Aggregator Module: battery, charger, fan, thermal, platform profile, tablet-mode switch, Type Cover HID
  (`045E:09AE/09AF/09B0`) — all bound on the linux-surface kernel.
- Cameras (IPU6 `465d`): front `OVTI5693` (ov5693, CSI-2 port 2), rear `OVTID858` (ov13858, CSI-2 port 1),
  IR `SMO55F0` (no driver). Power via `INT3472:00/01/02` (int3472-discrete).
- Sensors: accelerometer via iio-sensor-proxy (auto-rotate works).
- Firmware: UEFI 24.103.143, Secure Boot **on**. Surface firmware cannot be updated from Linux (fwupd shows only
  UEFI CA/dbx); a future update needs Windows (e.g. a Windows USB).
- Battery: 43.7 / 46.5 Wh (94 %), 135 cycles. No charge-limit control from Linux; use UEFI's battery limit if wanted.

## Kernel

- `kernel-surface` 7.3.4-2.surface.fc45 from `pkg.surfacelinux.com` (Fedora repo), with `iptsd` 3.1.1 and
  `libwacom-surface` (replaces Fedora's `libwacom`).
- Secure Boot: `surface-secureboot` MOK enrolled (password `surface` at the enrollment screen).
- `linux-surface-default-watchdog.path` keeps the surface kernel as GRUB default after Fedora kernel updates.
- Stock Fedora `7.3.4-300.fc45` stays in GRUB as the fallback (Shift/Esc at power-on).
- Cmdline adds `pcie_aspm.policy=powersupersave`.

## What works

| Feature | State | Notes |
|---|---|---|
| Touchscreen + pen | ✅ | iptsd; pressure/eraser via libwacom-surface |
| Type Cover keyboard/touchpad | ✅ | |
| Rear camera (ov13858) | ✅ | libcamera SoftISP, 30 fps at 4224x3136; uncalibrated tuning (`uncalibrated.yaml`) |
| Front camera (ov5693) | ❌ pending upstream | see below |
| Suspend (s2idle) | ✅ | 98 % HW S0ix residency (141/144 s), ~0.25 s each way, no spurious wakes (2026-11-22) |
| Hibernate | ✗ not used | no disk swap; Secure Boot lockdown blocks it anyway |
| Power modes | ✅ | GNOME power-saver/balanced/performance → tuned → `platform_profile` low-power/balanced/performance |
| Auto-rotate | ✅ | |
| HW video decode | ✅ | `vainfo` → iHD |

### Front camera — waiting on linux-surface

Sensor powers and configures, but IPU6 receives no CSI-2 frames (`intel_ipu6_isys … stream stop time out`). Fix is
one register write in ov5693 before stream-on (MIPI_CTRL00 `0x4800`; linux-surface PR #2171 — closed unmerged,
possibly continued as linux-surface/kernel#180). Not in kernel-surface 7.3.4-2. **Decision: wait for upstream**,
no custom module (nice-to-have). Check after kernel updates:

```sh
rpm -q --changelog kernel-surface-core | grep -iE 'MIPI_CTRL|0x4800|ov5693.*(ipu6|stream|front)'
cam -c 1 --capture=10    # real test: frame lines = fixed
```

(Plain `grep ov5693` matches two old unrelated entries — gain values, CONFIG_VIDEO_OV5693.)
Community workaround exists (`el-amin-dev/sp9-ov5693-dkms`), not used.

## Tuning applied

Scripts (in `~/ai` on the machine): `surface-optimize.sh`, `surface-from-spin.sh` (ports SlipperyWeasel choices).

- Services disabled: VM guest agents (qemu-guest-agent, vboxservice, vmtoolsd, vgauthd), livesys leftovers, iSCSI,
  stratisd, mdmonitor, lvm2-monitor, raid-check.timer, ModemManager, NetworkManager-wait-online, systemd-homed(+activate),
  systemd-userdbd.socket, mcelog, dnf-makecache.timer. Kept: auditd (work machine), cups/avahi (socket-activated, printing).
- `/etc/sysctl.d/90-surface.conf`: swappiness 180, page-cluster 0, watermark_scale_factor 125,
  watermark_boost_factor 0, nmi_watchdog 0 (same shape as SlipperyWeasel `90-slipperyweasel.conf`).
- fstab: btrfs `noatime,compress=zstd:1` (backup `/etc/fstab.bak-surface`).
- Kept as shipped: thermald, intel_lpmd, tuned + tuned-ppd. MGLRU on, THP madvise.
- Not adopted from the SP6: swappiness 10 (wrong for zram), Marvell Wi-Fi power-save off, TCP buffer sysctls, hibernate.

## Boot (`systemd-analyze`)

| | firmware | loader | kernel | initrd | userspace | total |
|---|---|---|---|---|---|---|
| stock kernel, before tuning | 2.8 s | 3.9 s | 0.9 s | 2.6 s | 7.7 s | 17.9 s |
| surface kernel, tuned | 2.9 s | 3.9 s | 0.9 s | 3.4 s | 6.3 s | 17.3 s |

Loader is GRUB + shim (menu already hidden); initrd grew 0.8 s on the surface kernel (trim possible, not done).

## Known fixes — apply only if the symptom appears (linux-surface wiki, Surface-Pro-9 page)

- Screen flicker → `i915.enable_psr=0`.
- Power/volume buttons intermittent → `/etc/dracut.conf.d/fix_hardware_buttons.conf`:
  `force_drivers+=" pinctrl_tigerlake "`, then `dracut -f --regenerate-all`.
- Erratic touch → `/etc/iptsd.d/91-calibration.conf` `[Contacts]` ActivationThreshold 24 / DeactivationThreshold 20 /
  OrientationThresholdMax 5.
- ACPI interrupt storm after lid/dock → `pci=hpiosize=0`.

## Open

- Overnight suspend drain not measured yet (SP6 baseline ~1–1.5 %/h).
- Screen-on idle power not measured (no turbostat run yet).
