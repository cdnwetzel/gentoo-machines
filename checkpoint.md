# Checkpoint - 2026-03-01

## Session Summary

Live dogfooding of XPS 9510 optimizations: applied CPU_FLAGS_X86 fix (31 Tiger Lake flags), rebuilt @world with hardware acceleration, installed evince/QEMU/xdotool, dogfooded kernel_config.sh from defconfig, found and fixed 5 issues (parent toggles, bool vs tristate). Built, installed, rebooted — all verified clean.

## What Was Done

### XPS 9510 — Live System Fixes (Phase 1)
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

### Repo Updates
- Updated `machines/xps-9510/make.conf` with verified 31 CPU_FLAGS_X86
- Updated `machines/xps-9510/INSTALL_GOTCHAS.md` with correct flags
- Updated `machines/xps-9510/kernel_config.sh` with QEMU support (VHOST_NET, BRIDGE) and all 5 fixes
- Updated `machines/xps-9510/world` with evince, QEMU, xdotool
- Updated `machines/xps-9510/package.use` with poppler cairo
- Created `tools/keep-awake.sh` (xdotool mouse wiggle for long compiles)

### Commits Pushed
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
| Surface Pro 6 | Ready to install | Run install scripts from Ventoy |
| Dell XPS 13 9315 | Configs updated (returned to Windows) | N/A |
| Intel NUC11TNBi5 | Config ready | Boot live USB, follow INSTALL.md |
| ASRock B550 / Ryzen 9 5950X | Placeholder | Harvest on Fedora 42 |
| Dell Precision T5810 | Placeholder | Harvest on Fedora 42 |
| Dell Precision 7960 | Placeholder | Harvest on RHEL 10.1 |
| Surface Pro 9 | Placeholder | Harvest on Windows 11 Pro |

## Next Steps

1. **Surface Pro 6 install** — boot Ventoy, run part1 → part2 → part3
2. **NUC11** — boot live USB, follow INSTALL.md
3. **ASRock B550 / Precision T5810 / Precision 7960** — harvest on existing OS, generate configs
