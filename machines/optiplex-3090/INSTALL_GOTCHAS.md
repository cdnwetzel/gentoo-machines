# Dell OptiPlex 3090 SFF — Install Gotchas

Lessons from the first install run (2026-04-28). The install itself went
straight to desktop on first boot — the items below are pre-install
prerequisites and one post-boot quirk worth documenting.

## 1. BIOS ships with SATA in Intel RST/RAID — must flip to AHCI

**Symptom**: live USB boots fine, but `lsblk` shows no internal disk. The
256 GB M.2 NVMe is invisible to Linux until the BIOS storage mode is
changed.

**Cause**: Q470 chipset SATA controller defaults to **"RAID On"** (Intel
Rapid Storage Technology). In this mode the NVMe is exposed only via the
proprietary RST driver path, not as a standard NVMe device.

**Fix** (one-time, before first install boot):

1. Reboot, F2 at the Dell splash → BIOS setup
2. **Storage → SATA Operation** → change `RAID On` to `AHCI`
3. Save, reboot to live USB
4. `lsblk` should now show `/dev/nvme0n1`

**Caution**: switching from RAID to AHCI breaks any existing Windows boot
on the disk unless prepped with the Safe Boot / `bcdedit` registry trick.
For a wipe-and-install Gentoo flow, this is irrelevant — but don't expect
to dual-boot a factory Windows install without prep.

## 2. `chronyd` flagged as "crashed" by `rc-status` on first boot

**Symptom**: `rc-status` (or `rc-status --crashed`) lists `chronyd` as
crashed, even though `rc-service chronyd status` reports `started`,
`pgrep -a chronyd` shows the daemon running, and `/run/chrony/chronyd.pid`
contains that same PID.

**Cause**: the packaged OpenRC init script for `net-misc/chrony` (4.8 here)
uses bare `start-stop-daemon` with `--pidfile` only — no `--background`,
no `--make-pidfile`, and no `command_background="yes"`:

```sh
start-stop-daemon --start --quiet \
    --exec /usr/sbin/chronyd \
    --pidfile "${PIDFILE}" \
    -- -f "${CFGFILE}" ${ARGS}
```

That relies on chronyd's own double-fork to background itself and write
its pidfile. There's a well-known race: `start-stop-daemon` returns once
the immediate child exits, but if it samples `--pidfile` before chronyd's
grandchild has finished writing it, OpenRC's tracked PID ends up being
the short-lived parent. `rc-status --crashed` then sees that tracked PID
is gone and flags the service, while the actual chronyd worker is healthy.

The huge first-boot clock step (RTC was ~4 h behind NTP; chronyd later
stepped 14227 s) is plausible aggravation but not strictly required —
this race is reproducible on any OpenRC system with this init script.

**One-shot recovery on the running system**:

```bash
sudo pkill -x chronyd 2>/dev/null
sleep 1
sudo rc-service chronyd zap
sudo rm -f /run/chrony/chronyd.pid
sudo rc-service chronyd start
rc-status --crashed     # should be empty
```

**Persistence**: with a correct RTC the race is much less likely to fire,
but the packaged init script is still latently buggy. If `--crashed`
reappears after a future reboot, the durable fix is a local replacement
init script under `shared/` (selected via `update-system.sh` or copied
into `/etc/init.d/chronyd` with the package version masked through
`/etc/portage/package.mask`) that uses modern OpenRC syntax:

```sh
command="/usr/sbin/chronyd"
command_args="-f ${CFGFILE} ${ARGS}"
command_background="yes"
pidfile="/run/chrony/chronyd.pid"
```

Do **not** edit `/etc/init.d/chronyd` in place — it'll be overwritten on
the next `chrony` upgrade. If you go this route, file the underlying bug
upstream at `bugs.gentoo.org` against `net-misc/chrony` so the fix lands
in the package itself.

## 3. SOF kernel symbols silently dropped by `olddefconfig`

**Symptom (post-build, harmless but worth knowing)**: `kernel_config.sh`
explicitly requests SOF for Comet Lake:

```sh
$SC --enable SND_SOC_SOF_TOPLEVEL
$SC --enable SND_SOC_SOF_INTEL_TOPLEVEL
$SC --module SND_SOC_SOF_PCI
$SC --module SND_SOC_SOF_COMETLAKE
$SC --module SND_HDA_INTEL
```

…but the running kernel (`/proc/config.gz`) shows:

```
CONFIG_SND_HDA_INTEL=m
CONFIG_SND_SOC_SOF_TOPLEVEL=y
# CONFIG_SND_SOC_SOF_PCI is not set
# CONFIG_SND_SOC_SOF_INTEL_TOPLEVEL is not set
```

**Cause**: `make olddefconfig` drops symbols whose dependency chain isn't
fully satisfied. The `SOF_TOPLEVEL=y` line takes effect, but
`SND_SOC_SOF_PCI` and `SND_SOC_SOF_INTEL_TOPLEVEL` are dropped — exact
missing dep not pinned (kconfig spelunking left for a follow-up; check
`sound/soc/sof/Kconfig` and `sound/soc/sof/intel/Kconfig` against the
`scripts/config` calls in `kernel_config.sh`). The kernel ends up with
HDA legacy only.

**Why this is harmless on this machine**: PipeWire + WirePlumber on plain
`snd_hda_intel` drives both the Realtek ALC3246 analog out and the NVIDIA
GA107 HDMI audio. SOF would be needed if you wanted DSP-side features
(echo cancel, beamforming, DSP-managed power gating) — none of which are
relevant on a desktop SFF.

**Why it's still a gotcha**: `kconfig-lint.sh` doesn't currently warn on
"requested-but-dropped" symbols (it warns on missing parent toggles, but
this case is more subtle — the parent toggle is set, an indirect dep is
not). If you ever rely on SOF here, the build will silently not have it.

**Action**: documented; no fix applied. If a future workload needs SOF,
edit `kernel_config.sh`, run `tools/kconfig-lint.sh
machines/optiplex-3090/kernel_config.sh /usr/src/linux`, then rebuild and
re-grep `/proc/config.gz` to confirm the symbols stuck.

## 4. First-boot validation in 30 seconds

After install completes and you boot to desktop, the canonical sanity
check is:

```bash
sudo tools/verify-install.sh
```

Expected: `0 failure(s), 0 warning(s)` with all eight sections green,
including the `optiplex-3090`-specific block (Hybrid GPU, NVIDIA driver
version, r8169, Ethernet link, zram).
