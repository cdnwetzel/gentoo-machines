# Checkpoint - 2026-03-03

## Latest Session: MBP 2015 Install Scripts Gold Standard

### What Was Done
1. **kernel_config.sh**: Fixed zram compression LZ4→ZSTD (matching zram-init.conf that already specified zstd), fixed stale `kernel_config_mbp121.sh` filename in USAGE header
2. **gentoo_install_part3_chroot.sh** (new): 13-phase one-shot chroot install modeled on SP6 gold standard. MBP-specific: `--removable` for Apple EFI GRUB, `mbpfan` (not thermald/tlp), BCM43602 WiFi firmware fix, CS4208 audio quirk note, applesmc verification, `libata.force=noncq` + `reboot=pci` boot param checks
3. **gentoo_install_part2.sh** (rewrite): Added `REPO` variable, rewrote STEP 4 with staging dir `/root/mbp-2015-configs/` (all 9 previously-orphaned configs, shared portage files, restore scripts, local.d scripts, part3 script), replaced STEP 8 with UUID capture + auto-generated fstab (12GB portage tmpfs for 16GB RAM)
4. **post_install_setup.sh**: Added "SUPERSEDED by part3" notice
5. **backlog.md**: Marked MBP install scripts upgrade complete
6. **CLAUDE.md**: Added part3 to file table, updated descriptions

### Files Created/Modified
- `machines/mbp-2015/kernel_config.sh` (modified — zram ZSTD + filename fix)
- `machines/mbp-2015/gentoo_install_part3_chroot.sh` (new — 13-phase chroot install)
- `machines/mbp-2015/gentoo_install_part2.sh` (rewritten — complete staging + fstab gen)
- `machines/mbp-2015/post_install_setup.sh` (modified — superseded notice)
- `backlog.md` (modified — marked complete)
- `CLAUDE.md` (modified — file table update)

### SP6 Post-Install Verification (live on device)
All checks pass:
- Kernel 6.18.12-gentoo, WiFi (mwifiex wlp1s0), HiDPI 150% (Xft.dpi=144), PipeWire 1.4.10 (ALC298)
- i915 UHD 620, zram 4GB, intel_backlight, s2idle suspend, all services running
- Fixed: EFI partition (nvme0n1p1) was in fstab but not mounted — `mount /boot/efi` fixed, will auto-mount on reboot
- Non-critical: nxp/rgpower_WW.bin + rgpower_US.bin firmware warnings (Marvell regulatory, WiFi works without)

### Commits
- `a2bf595` MBP 2015: upgrade install scripts to gold standard — part3 chroot, staging, zram fix

---

## Previous Session: Surface Pro 6 HiDPI Scaling

### What Was Done
1. **HiDPI scaling at 150% (144 DPI)** for 2736x1824 PixelSense display (267 PPI)
2. **LightDM login screen**: `xserver-command=X -dpi 144` + display-setup script with `xrandr --dpi 144` — greeter renders at 150%
3. **XFCE desktop session**: `hidpi-setup.sh` sets `Xft/DPI=144`, cursor size 36, xrandr DPI
4. **restore-desktop.sh**: Auto-detects Surface Pro via DMI, applies HiDPI (step 6/7)
5. **Install script**: Part3 phase 9 installs display-setup.sh during chroot

### Files Created/Modified
- `machines/surface-pro-6/lightdm-display-setup.sh` (new)
- `machines/surface-pro-6/hidpi-setup.sh` (new)
- `machines/surface-pro-6/lightdm.conf` (xserver-command + display-setup-script)
- `machines/surface-pro-6/gentoo_install_part3_chroot.sh` (phase 9.3 display-setup)
- `shared/restore-desktop.sh` (HiDPI step 6/7, DMI detection)

### Commits
- (pending)

---

## Previous Session: Surface Pro 6 First Boot

### What Was Done
1. **Surface Pro 6 is LIVE on Gentoo** — booted, all packages installed, first-boot restore complete
2. **Package check**: All 63 world packages already installed — install scripts covered everything
3. **Desktop restore** (`restore-desktop.sh`): XFCE keybindings (Super+Enter maximize, Super+Arrow tiling, Ctrl+Alt+T terminal, etc.), panel layout with Remmina launcher, PipeWire autostart, display profiles, xhost autostart
4. **System restore** (`restore-system.sh`): elogind config, ACPI lid toggle, LightDM display setup, touchpad (tap-to-click), KSM startup, `/dev/ppp` for SSTP VPN, services restarted (elogind + acpid)
5. **Remaining**: Reboot/logout to apply touchpad config changes

### Commits
- `c97aff3` Surface Pro 6: mark production — first boot restore complete
- `9889aee` Surface Pro 6: fix Marvell 88W8897 WiFi power save hang

---

## Previous Session: XPS 9510 Touchpad + Bug 970769 Feedback

### What Was Done
1. **XPS 9510 touchpad fix**: Enabled RMI4 subsystem (RMI4_CORE, RMI4_I2C, RMI4_SMB, RMI4_F11, RMI4_F12, RMI4_F30) and HID_RMI in both .config and kernel_config.sh. Synaptics touchpad was falling back to generic HID without these — no two-finger scrolling, poor palm rejection causing tap-while-typing. Kernel rebuild in progress on XPS 9510.
2. **Bug 970769 feedback**: Sam James responded — double-brace typo not found in genpatches, ebuild, or upstream 6.12.y. Likely local filesystem corruption. Need to re-emerge and verify before responding.

### Commits
- `6898d7f` XPS 9510: enable RMI4 for Synaptics touchpad multitouch + palm rejection

---

## Previous Session: MBP installkernel + Upstream Patch Investigation

### What Was Done
1. **MBP 2015 installkernel fix**: Added `sys-kernel/installkernel grub` to package.use, added installkernel to world, updated post_install_setup.sh — now matches XPS 9510/9315/SP6 pattern (auto grub-mkconfig on `make install`)
2. **ipu-bridge bug filed**: [Bug 970769](https://bugs.gentoo.org/970769) on Gentoo Bugzilla — double-brace typo in gentoo-sources-6.12.58, fixed in upstream mainline, Gentoo-specific backport error. Filed via pybugz CLI.
3. **intel_idle Tiger Lake — deep upstream investigation**: Cloned torvalds/linux, traced full git history of `intel_idle_ids[]`. Key findings:
   - CML/ICL-client/TGL/RKL were **never** in the table (not removed — never merged)
   - Rafael Wysocki deliberately stopped adding client CPUs after Kaby Lake (Dec 2019), relying on ACPI `_CST` fallback (`18734958e9bf`)
   - CML patch was posted but never merged; ICL-client patch was NAK'd
   - Root cause is Dell BIOS only exposing 3 of 8 C-states via ACPI — firmware deficiency
   - **Decision: keep as local patch only**, LKML submission not viable
4. **intel_idle patch cleanup**: Updated Signed-off-by to `Chris Wetzel <chris@cwetzel.com>`, improved commit message
5. **pybugz configured**: `~/.bugzrc` with Gentoo Bugzilla API key (outside repo)

### Commits
- `0031b63` MBP installkernel fix + upstream patch prep
- `a5058f1` Update backlog + patches/README: ipu-bridge reported as Bug 970769
- `1457827` Close intel_idle LKML item: intentional upstream omission, Dell firmware bug

---

## Previous Session: SP6 Config Validation

Validated Surface Pro 6 configs and fixed bugs before continuing the install (phases 5-13) tomorrow at the office.

### What Was Done
1. **Fixed filename mismatch bug (CRITICAL)**: `kernel_config_surface_pro6.sh` → `kernel_config.sh` in part2.sh (4 refs), part3_chroot.sh (2 refs), kernel_config.sh USAGE comment, EXEC_SEQUENCE.md — 8 total occurrences. Would have broken install on first run.
2. **Added `# UPDATE THIS URL` comment** above STAGE3_FILE in part2.sh (consistency with XPS 9510)
3. **Fixed stale `-march=kabylake`** references in HARDWARE.md and EXEC_SEQUENCE.md → `-march=skylake` (see gotcha #19)
4. **Validated make.conf** against harvest data: CPU_FLAGS_X86 (16 flags), MAKEOPTS (-j9 -l8), VIDEO_CARDS (intel), MICROCODE_SIGNATURES (0x000806ea) — all correct
5. **Cross-checked kernel_config.sh vs HARDWARE.md**: All 20+ PCI devices/subsystems have drivers, all firmware paths correct, no missing platform drivers
6. **kconfig-lint** already run (previous session): 0 FAILs, 15 WARNs, 16 INFOs

### SP6 Install Status
- Phases 1-4 done on-site: kernel built, GRUB installed, users created
- Machine is at office — can't verify until tomorrow
- Phases 5-13 remain: networking, world, services, LightDM, PipeWire, Surface HW, verification

### Commits
- `ba6cb91` Fix SP6 install script bugs: filename mismatch + stale march references

---

## Previous Session Summary

Built 3 future-proof kernel config tools: kconfig-lint.sh (static validator that catches 5 classes of silent bugs), enhanced harvest.sh (7 new hardware discovery sections), and kernel-config-template.sh (auto-generates kernel_config.sh from harvest data). kconfig-lint immediately caught a real bug in XPS 9315 — `SND_SOC_SOF_INTEL_TOPLEVEL` is bool but was set with `--module`, silently disabling SOF audio support.

## What Was Done

### Future-Proof Kernel Config Tooling (3 tools)

#### Tool 1: kconfig-lint.sh (360 lines) — Static Config Validator
- Parses all 1812 Kconfig files into a 19414-symbol TSV database (~2s)
- 5 checks: `--module` on bool (FAIL), missing parent toggles (WARN), firmware driver =y (WARN), unsatisfied deps (WARN), unknown options (INFO)
- Fixed `find -L` for symlinked kernel source, `((n++))` bash `set -e` gotcha
- Pre-scans script for all symbols to reduce false positives on ordering
- Expanded always-on skip lists (arch basics, subsystem menus, common selections)
- Validation results across all 4 machines:
  - XPS 9510: 0 FAIL, 2 WARN, 12 INFO (clean — already fixed)
  - XPS 9315: **1 FAIL** (SND_SOC_SOF_INTEL_TOPLEVEL), 6 WARN, 10 INFO
  - MBP 2015: 0 FAIL, 10 WARN, 26 INFO
  - Surface Pro 6: 0 FAIL, 15 WARN, 16 INFO

#### Tool 2: harvest.sh enhancements (+263 lines, 15 sections total)
- Section 9: CPU_FLAGS_X86 via cpuid2cpuflags (with /proc/cpuinfo fallback + 28 flag mappings)
- Section 10: Audio subsystem — SOF vs HDA detection from loaded modules + codec info
- Section 11: Platform vendor — DMI classification (Dell/Apple/Surface/Lenovo/HP/ASUS/Intel/generic)
- Section 12: Boot type — EFI vs BIOS, Secure Boot state, EFI bitness (32/64)
- Section 13: Suspend capabilities — s2idle vs S3 deep, hibernate support
- Section 14: Loaded firmware — module-to-firmware file mapping from dmesg + on-disk scan
- Section 15: GCC -march suggestion — CPU vendor:family:model lookup table (Intel Broadwell→Meteor Lake, AMD Zen 1→Zen 4)

#### Tool 3: kernel-config-template.sh (1279 lines) — Skeleton Generator
- Parses harvest log to auto-detect: CPU (vendor, cores, hybrid), GPU (Intel/NVIDIA/AMD), WiFi (8 vendors), Audio (SOF/HDA + codec), Storage (NVMe/SATA), Platform (6 vendors), Ethernet, Thunderbolt, ISH, cameras
- Generates complete 26-phase kernel_config.sh with correct drivers pre-filled
- Module-to-config lookup: iwlwifi, brcmfmac, mwifiex, ath11k, ath12k, mt76, rtw89, rtw88, i915, amdgpu, nouveau/nvidia, snd_hda_intel, sof variants, igc, e1000e, r8169, igb, ixgbe, mlx5, and more
- Platform templates: Dell (SMBIOS/WMI), Apple (applesmc/gmux/bcm5974), Surface (SAM/HID/DTX), Lenovo (thinkpad_acpi), HP (WMI), ASUS (WMI)
- Auto-runs kconfig-lint on generated output

#### Bug Fix: XPS 9315 SND_SOC_SOF_INTEL_TOPLEVEL
- kconfig-lint caught: `--module` on bool option (FAIL)
- Fixed: changed to `--enable` — SOF Intel audio was silently never enabled

### Commits Pushed
- `53f9a78` Add future-proof kernel config tooling: kconfig-lint, harvest enhancements, template generator
- `bc708be` Fix XPS 9315: SND_SOC_SOF_INTEL_TOPLEVEL is bool, not tristate
- `4d9f3f0` Document kconfig-lint, kernel-config-template, and harvest enhancements in CLAUDE.md

## Previous Session (2026-03-01 earlier)

### XPS 9510 — Live Dogfooding + Fixes
- Ran `machines/xps-9510/live-fixes.sh` on live system — all 6 fixes applied:
  - **CPU_FLAGS_X86**: cpuid2cpuflags detected 31 flags (10 more than predicted: avx512_bitalg, avx512_vbmi2, avx512_vnni, avx512_vp2intersect, avx512_vpopcntdq, avx512ifma, avx512vbmi, bmi1, bmi2, vpclmulqdq)
  - **INPUT_DEVICES**: Added `libinput`
  - **ccache**: Installed, configured on /data/build-cache/ccache (10G)
  - **package.env**: 6 large packages redirected to disk
  - **Portage tmpfs**: 24G mounted at /var/tmp/portage
  - **fastfetch**: Replaced neofetch

### XPS 9510 — @world Rebuild
- `emerge -avuDN @world`: 26 packages (12 upgrades, 14 reinstalls with new CPU_FLAGS_X86)
- Key packages now using hardware crypto/SIMD: libgcrypt (AES-NI, AVX-512, SHA), nss (AVX2), libsodium (AES-NI), nettle (AES, PCLMUL, SHA), eigen (AVX-512, FMA3), pixman (SSSE3), gtk-4 (F16C)
- GCC updated 15.2.1_p20251122 → 15.2.1_p20260214
- Python 3.14.0 → 3.14.2

### XPS 9510 — New Packages
- `app-text/evince` 48.1 (PDF viewer, gtk print preview)
- `app-emulation/qemu` 10.2.0-r1 (x86_64 softmmu target)
- `x11-misc/xdotool` (screen keep-alive during compiles)
- Added chris to `kvm` group
- `emerge --depclean`: removed 6 orphaned packages (alsa-plugins, speexdsp, webrtc-audio-processing, orc, abseil-cpp, libatasmart)
- Fixed: ccache, cpuid2cpuflags, fastfetch weren't in live world file — added via `emerge --noreplace`

### XPS 9510 — Kernel Config Dogfooding
- Applied kernel_config.sh from defconfig baseline on kernel 6.12.58-gentoo
- **Found 5 issues** (all fixed):
  1. `X86_PLATFORM_DRIVERS_DELL` parent toggle missing — Dell drivers were invisible
  2. `ACPI_DPTF` parent toggle missing — INT340X thermal drivers invisible
  3. `CPU_FREQ_GOV_POWERSAVE` not explicitly enabled alongside DEFAULT_GOV
  4. `DELL_SMBIOS_WMI`, `DELL_SMBIOS_SMM` are booleans, not tristate (--enable not --module)
  5. `ITCO_VENDOR_SUPPORT` is boolean, not tristate
- Second run: 0 warnings, all 26 phases clean
- Kernel built (`make -j17`), modules_install, make install, @module-rebuild
- **Rebooted and verified** — all checks pass:
  - IKCONFIG: enabled (=y, _PROC=y)
  - dmesg: only Dell ACPI BIOS bug (\_TZ.ETMD, harmless)
  - lspci -k: all devices have drivers (i915, nvidia, iwlwifi, nvme x2, snd_hda_intel, etc.)
  - nvidia-smi: RTX 3050 Ti running, driver 590.48, CUDA 13.1, 7W idle
  - zram: 8GB zstd swap active
  - sensors: all temps normal (CPU 52C, GPU 49C)

### Repo Updates (earlier session)
- Updated `machines/xps-9510/make.conf` with verified 31 CPU_FLAGS_X86
- Updated `machines/xps-9510/INSTALL_GOTCHAS.md` with correct flags
- Updated `machines/xps-9510/kernel_config.sh` with QEMU support (VHOST_NET, BRIDGE) and all 5 fixes
- Updated `machines/xps-9510/world` with evince, QEMU, xdotool
- Updated `machines/xps-9510/package.use` with poppler cairo
- Created `tools/keep-awake.sh` (xdotool mouse wiggle for long compiles)

### Earlier Commits
- `8f7f7bc` Fix CPU_FLAGS_X86 to match verified cpuid2cpuflags output
- `1541248` Add evince, QEMU, xdotool; add KVM/VHOST_NET/BRIDGE to kernel config
- `c04bd30` Fix kernel_config.sh: parent toggles and bool vs tristate

## Previous Sessions (Abbreviated)

### 2026-02-28: Universal Framework Implementation
- Phase 2: XPS 9510 full config framework (~25 files)
- Phase 3: XPS 9315 best-effort update (~12 files)
- Phase 4: Shared framework (INSTALL_GOTCHAS 25 lessons, machine-checklist)

### 2026-02-27: MBP 2015 Production + Surface Pro 6 Prep
- MBP 2015 audio, hotkeys, kernel tuning, battery fix, zram
- zram-init config bug fix (num_devices required)
- Surface Pro 6 + MBP 2015 repo integration

### 2026-02-22: XPS 9510 Initial Production
- Full production: kernel tuning, PipeWire, Dell hotkeys, SSTP VPN, nvidia

## Current State

### Machine Status
| Machine | Status | Next Step |
|---------|--------|-----------|
| Dell XPS 15 9510 | **Production — dogfooded kernel verified** | Maintenance only |
| MacBook Pro 12,1 (2015) | Production | Maintenance only |
| Surface Pro 6 | **Production — fully verified** | Maintenance only |
| Dell XPS 13 9315 | Configs updated (returned to Windows) | N/A |
| Intel NUC11TNBi5 | Config ready | Boot live USB, follow INSTALL.md |
| ASRock B550 / Ryzen 9 5950X | Placeholder | Harvest on Fedora 42 |
| Dell Precision T5810 | Placeholder | Harvest on Fedora 42 |
| Dell Precision 7960 | Placeholder | Harvest on RHEL 10.1 |
| Surface Pro 9 | Placeholder | Harvest on Windows 11 Pro |

## Next Steps

1. **NUC11** — boot live USB, follow INSTALL.md
2. **ASRock B550 / Precision T5810 / Precision 7960** — harvest on existing OS, generate configs
3. **Surface Pro 9** — harvest on Windows 11 Pro
