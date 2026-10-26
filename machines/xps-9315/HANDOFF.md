# XPS 13 9315 — Max-Performance Linux Build: Investigation & Implementation Handoff

> Origin: drafted by Kimi (web), handed to Kimi Code CLI 2026-10-13. This is the
> governing plan. CLI-side research agents are verifying the load-bearing claims
> (camera/IPU6 status, SSTP client state, distro/package availability) and their
> findings get merged below under "Verification log".

## 0. Agent operating rules
- Verify every hardware claim against the LIVE system before relying on it
  (lspci / lsusb / dmesg / libinput debug-events). Mark anything unverified.
- Test-first: after each phase, run the phase's verification commands and SHOW
  output. Silent failure = failure. Nothing is "done" without evidence.
- State assumptions explicitly. If a config change vs behavior vs consequence
  distinction matters, label it.
- Do not proceed past a phase gate without passing its verification steps.

## 1. Goal
Squeeze the absolute maximum real-world performance out of a Dell XPS 13 9315
(i5-1230U, 8GB LPDDR5 soldered, 256GB NVMe [soldered, not upgradeable — VERIFY
but treat as fixed], Iris Xe G7 80EU) as a daily driver for:
- Firefox (primary app) + terminal (secondary)
- Firm SSL VPN: RRAS SSTP client (must work — this is non-negotiable)
- Full hardware support: hotkeys (Fn row), webcam (IPU6 — see §4), Wi-Fi 6E,
  audio over SOF, suspend/resume
- Light desktop environment, Wayland-based (camera stack requirement, §4)

Success = snappy bursty responsiveness under Firefox + terminal + VPN, correct
hotkeys, working camera in Firefox WebRTC, SSTP stable, battery ≥ 6h light use.
"Absolute maximum" is bounded by physics: 1 fan, ~12W PL1 sustained (thermal),
8GB RAM, soldered everything. Sustained all-core is capped by the chassis;
optimize responsiveness, memory headroom, and I/O — not synthetic all-core.

## 2. Hardware reference (VERIFIED on the live machine 2026-10-16)
Full inventory: `gentoo-machines/machines/xps-9315/HARDWARE.md` + `xps_harvest.log`.
- CPU: i5-1230U, 10C (2P+8E)/12T, P-core turbo 4.4 GHz / E-core 3.3 GHz, 12 MB L3
- RAM: 8 GB LPDDR5 soldered (8× 1 GiB Micron, running 5200 MT/s), 7.4 GiB usable → zram mandatory
- Storage: 256 GB Phison PS5019-E19 (`ESE2A043-256`), PCIe 4.0, DRAM-less — shared with Windows (§8)
- Display: 13.4" 1920x1200 eDP (Sharp LQ134N1), non-touch
- Camera: OV01A10 on Intel IPU6EP `8086:465d`, iVSC behind the LJCA USB bridge `8086:0b63` — the risk item, see §4
- Wi-Fi/BT: Intel AX211 160MHz CNVi (`8086:51f0`, subsys `8086:4090`) + BT `8087:0033` — iwlwifi/btintel, mature
- Audio: SOF SoundWire — RT1316 speaker amp (mono topology `sof-adl-rt1316-l2-mono-rt714-l3`) +
  RT714 codec/mic (bound by `rt715-sdca`). Dell's spec sheet calls it "ALC1319D". No 3.5mm jack.
- iGPU: Iris Xe 80EU `8086:46aa` — VA-API via iHD; firmware `adlp_dmc`, `adlp_guc_70`, `tgl_huc`
- Hotkeys: Dell WMI hotkeys + Intel HID event devices present; Fn-row keycodes still to verify (P2)
- Fingerprint: Goodix `27c6:63ac` — the libfprint-supported ID
- Battery: ~50 Wh design (4330 mAh @ 11.55 V), 96% health at audit
- TB4 ports x2 (UCSI PD), no USB-A
- Firmware: BIOS 1.39.0, Secure Boot off, storage mode AHCI/NVMe, s2idle only

## 3. Distro decision (pick ONE before Phase 1)
A) RECOMMENDED — Gentoo, OpenRC, glibc:
   - COMMON_FLAGS="-O2 -pipe -march=alderlake"; MAKEOPTS="-j10" normally,
     "-j4" for llvm/rust-class builds (8GB RAM ceiling) — or distcc offload
     to T5810 (192.0.2.125) if reachable; never touch WORK fleet.
   - Use firefox-bin (binary package) — do NOT compile Firefox on this box.
   - Custom kernel (start from gentoo-kernel-bin, then trimmed config) so only
     compiled-in hardware is shipped: smaller kernel, faster boot, less RAM.
   - Cost: initial build/setup time. Benefit: lightest possible base + full
     control — matches user's source-based workflow.
B) FALLBACK — Void Linux glibc + runit: ~80% of the benefit, zero compile time,
   current packages (kernel, libcamera, pipewire all new enough), sstp-client
   in repos. Choose if setup time matters more than tailoring.
C) REJECTED — Debian stable/Alpine musl: userspace too old or glibc friction
   (Firefox on musl is extra pain); Arch possible but adds nothing over B.
DECISION POINT: user selects A or B. Everything below is written for A; on B
the package names change, the architecture does not.

## 4. Camera stack — the binding constraint (IPU6)
Requirements (all must hold):
- Kernel ≥ 6.10 with CONFIG_VIDEO_INTEL_IPU6 (in-tree staging) + CONFIG_INTEL_VSC
- libcamera ≥ 0.3 (Gentoo: media-libs/libcamera) with ipu6 pipeline handler
- PipeWire built with libcamera support (USE libcamera on media-video/pipewire)
- xdg-desktop-portal + xdg-desktop-portal-wlr (wlroots/Sway)
- Firefox native Wayland (modern FF defaults to Wayland; VERIFY with
  about:support → "Window Protocol: wayland")
REJECT X11: Firefox on X11 uses v4l2 directly; IPU6 needs a v4l2loopback relay
(Dell's old hack). Wayland + camera portal is the native path — this is why the
session is Wayland.
PHASE-0 PROOF (before installing anything): boot a CURRENT Fedora live USB
(newest kernel/libcamera userspace). Test: `cam --list`, capture a still
(`libcamera` tools), open a WebRTC camera test in Firefox. If it works there,
hardware + stack recipe is proven and Gentoo must reproduce it. If it does NOT
work on newest Fedora, STOP and report — do not burn time installing.

## 5. Session / DE — Sway (wlroots)
- Sway: minimal compositor, low overhead, config-file hotkeys (terminal-centric).
- Alternative: labwc (even lighter wlroots) — only if Sway shows overhead issues.
- REJECT full DEs (KDE/GNOME/XFCE): compositor + daemons overhead fights the
  8GB budget; XFCE is X11 → camera shim problem.
- Status bar: swaybar + i3status (as built; waybar was the original pick and is
  not installed). Launcher: wmenu. Terminal: foot (user's choice, confirmed).
- Hotkeys in ~/.config/sway/config:
    bindsym XF86MonBrightness{Up,Down} exec xbacklight {-inc 5,-dec 5}   # sys-power/acpilight
    bindsym XF86Audio{Raise,Lower}Volume exec wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ {5%+,5%-}
    bindsym XF86AudioMute exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
  VERIFY each key emits the expected keycode first: sudo libinput debug-events
  (press each Fn key; dell-wmi should deliver XF86* keycodes — report any
  key that emits nothing; none expected on the 9315's standard Fn row).

## 6. SSTP VPN (RRAS) — requirement, plan for friction

**CONFIRMED BY USER (2026-10-14): auth is PAP, required by the firm's Duo MFA
integration with RRAS.** Consequences (config, not options):
- pppd auth flags: `require-pap refuse-chap refuse-mschap refuse-mschap-v2
  refuse-eap` (NOT the MS-CHAPv2 set). Credentials go in
  `/etc/ppp/pap-secrets`, not chap-secrets.
- **MPPE is impossible with PAP** — MPPE session keys are derived from
  MS-CHAPv2 handshake material; PAP provides none. So DO NOT use
  `require-mppe` here (that earlier note applied to MS-CHAPv2 setups); set
  `nomppe`. Encryption is provided by the SSTP TLS tunnel — this is the
  standard, accepted posture for PAP-over-SSTP.
- **Server-cert verification becomes the security boundary**: PAP sends the
  password (recoverably) inside the tunnel, so pin the cert properly —
  `--ca-cert <rras-cert-or-CA>.pem` with correct CN/SAN (`--host`/`--tls-ext`
  if dialing by IP). Avoid `--cert-warn` as a permanent setting; it exists for
  debugging only. Get the RRAS cert/CA from the firm and ship it in the config.
- Duo note: depending on the firm's Duo proxy config, the second factor is
  either auto-push or appended (`password,push`). Confirm which; it only
  affects what goes in pap-secrets / the secret prompt.
- Client: sstp-client (Gentoo: net-misc/sstp-client) via direct pppd peers
  (fits Sway/no-NetworkManager). openconnect's experimental SSTP: do not use.
- Remaining RRAS facts to confirm before P4: TLS floor (TLS 1.2-only? then no
  SECLEVEL workaround needed), cert CN/SAN, cert source (public CA or internal).
- Verification: connect, `ip addr` shows ppp iface, route to firm subnet,
  sustained 10-min session with traffic (no silent drop), auto-reconnect via
  `persist maxfail 0` in the peers file (no NetworkManager dispatcher needed).

## 7. Performance tuning plan (in order of expected real gain)
1. Memory: 8GB is the wall. zram (zstd, size=ram/2, vm.swappiness=180 per
   modern zram guidance). Firefox dom.ipc.processCount → 4-6 (default 8 wastes
   RAM at this scale). Measure with about:memory before/after.
2. Scheduler/governor: intel_pstate active; EPP=balance_performance on AC,
   balance_power on battery. udev/rules or a small AC/bat toggle script.
   VERIFY via `cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference`.
   Do NOT raise PL1/PL2 via RAPL without measurement — chassis will thermally
   throttle (1 fan, 39.6 dB max); test s-tui under load, expect little headroom.
   Undervolting: locked on Alder Lake — do not attempt.
3. Firefox: WebRender on Wayland (default; verify about:support), VA-API hw
   video decode (media.hardware-video-decoding.force-enabled if not auto-on),
   disk cache on NVMe default is fine.
4. Kernel: trim config (no unused drivers/filesystems), disable debug options,
   LZ4 compression? (no — LZ4 decompress cost vs zstd; test boot time, keep it
   simple). Do NOT use mitigations=off — security regression not worth ~single-
   digit % on Alder Lake; note it as an option user may explicitly opt into.
5. Services: audit with `rc-update` / `ps aux --sort=rss`; target < 400MB RAM
   at idle desktop (sway+swaybar+i3status+pipewire baseline).
6. thermald installed and running; VERIFY via dmesg it loads without errors.

## 8. Partition plan (256GB fixed) — AS BUILT: dual-boot, Windows kept
The original plan (full wipe; /efi 1GB, / 40GB, /home ~200GB) was superseded
when Windows 11 was kept. Actual layout:
- `nvme0n1p1` 500 MiB vfat ESP — shared with Windows, mounted `/efi` noauto
- `nvme0n1p2` 128 MiB MSR, `nvme0n1p3` 157.9 GiB NTFS (Windows 11)
- `nvme0n1p4` 80 GiB ext4 — Gentoo `/`, no separate /home
- No swap partition: zram at boot; 8 GiB `/swap.install` swapfile for big builds
  (not in fstab). PORTAGE_TMPDIR=/var/tmp with a 4 GiB tmpfs on /var/tmp/portage;
  heavy packages build in /var/tmp/portage-disk.

## 9. Phases & gates
P0 Proof: Fedora live USB — camera works? (§4). Gate: cam + Firefox WebRTC OK.
P1 Install base OS + kernel + Wi-Fi + audio + sway. Gate: boot < 15s to
   desktop, wifi connected, audio playback, suspend/resume 3x clean.
P2 Hotkeys. Gate: every Fn key mapped and functional per §5 verification.
P3 Camera stack on installed system. Gate: cam --list, still capture, Firefox
   WebRTC test page — all shown.
P4 SSTP. Gate: §6 verification incl. 10-min stability.
P5 Perf pass §7 with before/after numbers (boot time, idle RAM, s-tui sustained
   clocks, Firefox page-load spot checks, battery estimate).
P6 Hardening + docs: full-disk layout documented, rsync-based backup to HOME
   storage, all config in git, rollback plan (keep Windows? VERIFY license/
   BitLocker state before first install — user decision required BEFORE P1).

## 10. Open questions for user (answer before/while starting)
1. Gentoo (A) or Void (B)?
2. Keep the Windows install (dual-boot) or full wipe? BitLocker status?
3. Terminal emulator preference (foot default)?
4. RRAS server config facts: auth method, TLS min version, cert CN?
5. Is T5810 distcc available during setup, or fully local builds?
6. Any dock/TB4 peripherals to support?

## 11. Flags carried over from the handoff author
1. Camera is the only real risk. Everything else (AX211, ALC1319D, dell-wmi,
   SSTP) is mature. The Phase-0 Fedora live-USB test exists to kill that risk in
   20 minutes before any install time is spent. If prior experience says it
   works on current kernels, P0 is optional — but keep it.
2. "Absolute maximum" framing: sustainable all-core ceiling is fixed by ~12W
   PL1 and one fan. Real wins: memory headroom (zram + Firefox process cap),
   trimmed kernel/userspace, EPP tuning, VA-API decode. Push back on RAPL
   power-limit hacks or mitigations=off as headline items — both are
   measurable-first at best.

## Verification log (CLI side, 2026-10-13)

User decisions recorded: **Gentoo (A)**, ~~full wipe~~ **dual-boot, Windows 11 kept** (as built, §8), **foot**,
**distcc to T5810 available**, **RRAS auth = PAP (Duo MFA requirement)** —
see rewritten §6. **Stage3/profile = no-multilib** (`stage3-amd64-nomultilib-openrc`,
profile `default/linux/amd64/23.0/no-multilib`; recorded 2026-10-16): nothing in
the plan needs 32-bit (firefox-bin is 64-bit, no Steam/Wine), and dropping the
32-bit ABI shortens builds on 8 GB. There is no `no-multilib/desktop` profile, so
the desktop-profile USE defaults are set by hand in `/etc/portage/make.conf`
(see RUNBOOK P1.3). Still open: RRAS TLS floor + cert CN/SAN (needed at P4),
TB4 peripherals.

### CONFIRMED (independent research, 3 agents)

- **sstp-client is healthy**: moved to gitlab.com/sstp-project/sstp-client,
  current 1.0.20, packaged everywhere. **Gentoo: `net-misc/sstp-client` and
  `net-vpn/networkmanager-sstp` both exist in ::gentoo** (gentoobrowse). CLI
  pppd-peers path needs no NetworkManager — fits the Sway setup.
- **Kernel ≥ 6.12.19 (or 6.13.4+) is the floor for the camera**: the 9315's
  iVSC probe ETIMEDOUT fix landed there (RHBZ #2316918). OV01A10 sensor driver
  mainlined since 6.10. gentoo-kernel-bin is far past this — fine.
- **libcamera route**: mainline libcamera "simple" pipeline + SoftISP handles
  IPU6 (patchwork.libcamera.org 19965/19967, Apr 2024). Gentoo resources exist:
  nagmat84's overlay (github.com/nagmat84/mhnnet-ebuild-repository, IPU6 ebuilds,
  Jun 2025 "nearly working" on X1 Carbon) and Arch AUR `libcamera-ipu6`
  (kervel fork with explicit OV01A10 support) as patch source.
  `intel-vsc-firmware` is a Fedora package — on Gentoo it may need manual
  install from Intel's ivsc-firmware repo. UNVERIFIED — check during P3.
- **Fingerprint: Goodix 27c6:63ac, SUPPORTED** by libfprint goodixmoc
  (fprint.freedesktop.org supported list; ArchWiki 9315). Upgrade §2 from
  "uncertain" to "expected working". Watch for 27c6:6382 variant (unsupported).
- **Wi-Fi AX211**: iwlwifi since 5.14, nothing 9315-specific. Non-issue.
- **Hotkeys**: standard Fn row confirmed (no capacitive bar on 9315), dell-wmi
  delivers XF86* keycodes OOTB. No dedicated airplane-mode key on this row.
  Cosmetic quirk: F4 mic-mute LED stuck on; fix via
  `/sys/class/sound/ctl-led/mic/mode`.

### NEW FINDINGS that amend the plan

1. **BIOS: RAID On → AHCI/NVMe is MANDATORY** (add to P1 prerequisites).
   With the BIOS default "RAID On" the 9315 never reaches low-power S0ix in
   s2idle — warm laptop, overnight battery drain (detfalskested.dk, Sep 2025).
   CONFIRMED set on this unit 2026-10-16 (NVMe at 01:00.0, no VMD device).
   Also: spurious wake after ~4s from an I2C device; workaround
   `echo disabled > /sys/bus/i2c/devices/i2c-VEN_0488:00/power/wakeup`.
2. **Audio is risk #2, not a non-issue.** SoundWire (RT1316 amp + RT714 codec on
   this unit — see live audit below; the reports call it ALC1319D + rt1316/rt715)
   needs sof-firmware + alsa-ucm-conf; there are 2025 reports of total audio
   loss ("Dummy Output") on the 9315 on Fedora 42 / Mint. Add an audio gate
   to P0's live-USB test (play sound, speakers, mic). Note: this unit loads the
   *mono* topology (one RT1316 link) — "check all 4 speakers" was wrong; test
   left/right balance instead.
3. **The 9315 camera is a unit-level lottery even on the best stack.**
   Bug 2324683 (iVSC probe EINVAL) closed EOL without confirmed fix;
   intel/ipu6-drivers#458: some units declare VSC on SPI1 and it never
   instantiates — camera broken on EVERY distro for those units. Some units
   work fine (Meet screenshot evidence Feb 2025). **P0 is therefore not
   optional — it is the go/no-go gate for the entire project.**
4. **P0 amendment**: if the camera fails on Fedora live, do NOT immediately
   stop — boot Ubuntu 24.04 live, add `ppa:oem-solutions-group/intel-ipu6`,
   install `libcamhal0 libcamhal-ipu6ep0 gstreamer1.0-icamera v4l2-relayd` and
   retest. That distinguishes "FOSS stack can't do this unit" from "this unit
   is broken everywhere" (which would force the Ubuntu OEM path as the OS
   choice instead of Gentoo).
5. **Void fallback is WEAKENED**: research reports no sstp-client package and
   DIY-only IPU6 on Void (UNVERIFIED against current repos). New fallback
   ladder if Gentoo stalls on camera: **Fedora Sway spin** (best integrated
   FOSS camera stack) > Ubuntu 24.04+OEM (proprietary libcamhal, most reliable
   on this exact machine) > Void.
6. **§6 correction + rewrite**: sstpc has **no** `--tls-cipher-suites` flag
   (handoff's "force with sstp-client flags" is wrong). TLS-version/cipher
   issues go through OpenSSL config: wrapper `OPENSSL_CONF` with
   `CipherString = DEFAULT@SECLEVEL=1` for sstpc only. MPPE note superseded:
   user confirmed PAP auth (Duo MFA) → **nomppe, pap-secrets, cert pinning**
   — see rewritten §6. Security note: CVE-2026-91838 filed against Ubuntu's
   network-manager-sstp (Sep 2026) — prefer the direct pppd path anyway on
   Gentoo.
7. **§7 amendment — zswap vs zram**: current (Mar 2026) guidance from
   Chris Down favors **zswap** (degrades better under pressure) backed by a
   small swapfile on the NVMe, over zram. Either is defensible; decide in P5
   with measurements. On Gentoo/OpenRC there is no systemd-oomd → use
   **earlyoom**. Firefox `dom.ipc.processCount` 2–4 (not 4–6) at 8 GB.
   VA-API needs `intel-media-driver` (iHD, NOT i965).
8. **Camera ≠ Wayland strictly**: Firefox reaches PipeWire/libcamera cameras
   via the xdg camera portal, which is display-server-agnostic. Wayland/Sway
   stays (scaling at 169 DPI, screen sharing, modern stack) — but X11 was
   never the hard blocker the handoff implied; the old v4l2loopback hack is
   only needed for non-portal apps.

### Live hardware audit (2026-10-16, Gentoo LiveGUI 7.2.5 on this laptop)

Ground truth replacing the pasted spec. Details in HARDWARE.md / xps_harvest.log.
- Audio enumerates as RT1316 (link 2) + RT714 (link 3), card `sof-soundwire`,
  topology `sof-adl-rt1316-l2-mono-rt714-l3.tplg` — the ALC1319D/rt715 naming
  above is superseded. The RT714 is bound by `snd_soc_rt715_sdca`.
- iVSC firmware is in `sys-kernel/linux-firmware` (`intel/vsc/ivsc_*ovti01a0*`)
  and loads; the RUNBOOK P3.2 manual install is not needed.
- VSC is behind the LJCA USB bridge (`8086:0b63`), not native SPI1 — so this
  unit is NOT the intel/ipu6-drivers#458 "VSC on SPI1" case.
- Camera on live 7.2.5: IPU6 reports "Connected 1 cameras" but `ov01a10` stays in
  deferred probe ("waiting for fwnode graph endpoint"). Not working on that
  kernel; untested on the installed 6.18.54. P0 (Fedora) is still unrun.
- Mic-mute LED mode already `follow-mute` on the live kernel (the stuck-LED fix
  may be a no-op; keep it as a safety net).
- Touchpad `i2c-VEN_0488:00` exists with wakeup **enabled** — the spurious-wake
  rule (90-i2c-wakeup.rules) targets a real device.
- s2idle only, Secure Boot off, BIOS 1.39.0, AHCI/NVMe mode — all confirmed.

### Next actions

- USER (physical, on the laptop): build a current Fedora Workstation live USB,
  run P0 gate: camera (`cam --list`, still capture, Firefox WebRTC gum_test),
  audio (speakers + mic), hotkeys spot check, note BIOS storage mode. Report
  outputs here.
- CLI (me, meanwhile): write the P1–P5 Gentoo runbook (install, OpenRC
  services, trimmed kernel config for this exact hardware, Sway+foot+swaybar
  configs, sstp-client pppd peers config, distcc setup against T5810) into
  this directory, keyed off the decisions above.
- CLI: ask user for RRAS server facts (auth method, TLS floor, cert CN) before
  P4.
