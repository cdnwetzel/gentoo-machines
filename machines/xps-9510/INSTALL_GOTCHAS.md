# Dell XPS 15 9510 — Install Gotchas

Extends the universal gotchas (shared/INSTALL_GOTCHAS.md) with XPS 9510-specific issues.

## XPS 9510-Specific Gotchas

### G1. NVIDIA DRM_QXL Trick (kernel 6.11+)
**Problem**: nvidia-drivers build fails with missing `drm_gem_ttm_*` symbols.
Since kernel 6.11+, NVIDIA needs DRM_TTM_HELPER which is no longer auto-selected.
**Fix**: Enable `CONFIG_DRM_QXL=m` in kernel config. QXL pulls in DRM_TTM which
provides the helper symbols NVIDIA needs.
```
DRM_QXL=m → DRM_TTM=y → DRM_TTM_HELPER (nvidia links against this)
```

### G2. Module-Rebuild Environment Isolation
**Problem**: `99-module-rebuild.install` hook (called by installkernel after `make install`)
inherits the kernel's make environment (ARCH=x86, MAKEFLAGS, KBUILD_*). This breaks
`emerge @module-rebuild` — nvidia-drivers gets confused by the leaked variables.
**Fix**: Use `env -i` in the hook to start with a clean environment:
```bash
env -i HOME=/root TERM="${TERM}" \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/bin" \
    emerge @module-rebuild
```

### G3. Module Source Symlink
**Problem**: `make modules_install` creates `/lib/modules/<ver>/build` symlink but NOT
`/lib/modules/<ver>/source`. nvidia-drivers resolves KERNEL_DIR from `source` — when
missing, build fails with `/Kbuild not found`.
**Fix**: The `99-module-rebuild.install` hook creates the symlink automatically.

### G4. NVIDIA Runtime Power Management
**Problem**: RTX 3050 Ti stays powered on even when idle, draining battery.
**Fix**: Three-layer approach:
1. GRUB: `nvidia.NVreg_DynamicPowerManagement=0x02`
2. modprobe.d: `options nvidia NVreg_DynamicPowerManagement=0x02`
3. TLP: `RUNTIME_PM_DRIVER_DENYLIST="nvidia"` (let NVIDIA driver manage its own PM)

### G5. i915 GuC/HuC Boot Parameters
**Why**: Tiger Lake benefits from GuC (GPU scheduler offload) and HuC (video decode).
**Fix**: Add to GRUB: `i915.enable_guc=3` (bit 0 = GuC, bit 1 = HuC).

### G6. Audio is HDA, NOT SOF
**Problem**: Many guides assume Tiger Lake uses Sound Open Firmware (SOF).
Tiger Lake-H (11800H) uses classic HDA — `snd_hda_intel`, NOT sof-audio-pci-intel-tgl.
**Fix**: `CONFIG_SND_SOC_SOF_TOPLEVEL=n` in kernel config. The 9510 audio chip is
`[8086:43c8]` Tiger Lake-H HD Audio, driven by snd_hda_intel.

### G7. Dual NVMe — UUIDs Required
**Problem**: NVMe device names (`/dev/nvme0n1`, `/dev/nvme1n1`) can swap between boots.
**Fix**: ALWAYS use UUIDs in fstab and GRUB. Never use device names.
```bash
blkid /dev/nvme0n1p1 /dev/nvme0n1p2 /dev/nvme1n1p1
```

### G8. CPU_FLAGS_X86 Must Be Set (THE BUG)
**Problem**: The original XPS 9510 make.conf had NO CPU_FLAGS_X86 line. Result:
only `mmx mmxext sse sse2` detected (Portage default). Every compiled package
was missing AVX, AVX2, AVX-512, AES-NI, FMA3, SHA hardware acceleration.
**Fix**: Always run `cpuid2cpuflags` and set the flags in make.conf.
For i7-11800H (Tiger Lake-H):
```
CPU_FLAGS_X86="aes avx avx2 avx512bw avx512cd avx512dq avx512f avx512vl f16c fma3 mmx mmxext pclmul popcnt rdrand sha sse sse2 sse3 sse4_1 sse4_2 ssse3"
```

### G9. ccache Directory on /data
**Problem**: Default ccache dir `/var/cache/ccache` is on the root NVMe.
With 32GB RAM and 24GB portage tmpfs, root disk I/O should be minimized.
**Fix**: Put ccache on the second NVMe: `CCACHE_DIR="/data/build-cache/ccache"`.
Must create with correct permissions:
```bash
mkdir -p /data/build-cache/ccache
chown root:portage /data/build-cache/ccache
chmod 2775 /data/build-cache/ccache
```

### G10. Portage tmpfs Sizing (32GB RAM)
24GB tmpfs works for this machine (32GB RAM total):
- 24GB tmpfs for portage
- 8GB zram swap
- Large packages (chromium, llvm, rust, gcc, firefox, qtwebengine) redirected to disk via package.env

## See Also
- shared/INSTALL_GOTCHAS.md — Universal gotchas (WiFi, LightDM, firmware, etc.)
- KERNEL_CONFIG_CROSSREF.md — Built-in vs module decisions
- HARDWARE.md — Full hardware reference
