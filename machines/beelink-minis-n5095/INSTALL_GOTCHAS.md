# Beelink MINI S (N5095A) — Install Gotchas

Lessons learned from the first install run (2026-04-14 → 2026-04-15). Fix
durable ones in the scripts; document the rest here so future runs don't
re-learn them.

## 1. `set -euo pipefail` breaks `source /etc/profile` in stage3

**Symptom** (Phase 1, first line of Phase 1):
```
/etc/profile.d/debuginfod.sh: line 8: DEBUGINFOD_URLS: unbound variable
```
…and the script aborts immediately.

**Cause**: `set -u` (nounset) catches any sourced shell file that references
an unbound variable. Current stage3s ship `/etc/profile.d/debuginfod.sh` which
uses `${DEBUGINFOD_URLS}` without a default. Other profile fragments may have
the same issue — relying on `-u` while sourcing arbitrary shell is fragile.

**Fix** (applied to `gentoo_install_part3_chroot.sh`): drop `-u` only.
```bash
set -eo pipefail   # NOT set -euo pipefail
```

**If you hit this on a freshly-copied script in the chroot**, patch in place:
```bash
sed -i 's/^set -euo pipefail$/set -eo pipefail/' /root/gentoo_install_part3_chroot.sh
```
Then re-run. Phase 1 is idempotent — nothing had actually executed before the
crash, so a clean re-run is safe.

## 2. fstab tmpfs for portage doesn't apply inside the chroot

**Expectation**: We wrote `/etc/fstab` in part2 with a 4 GB tmpfs line for
`/var/tmp/portage`, and `package.env` routes large packages to `/var/tmp/portage-disk`.

**Reality**:
```
(chroot) # df -h /var/tmp/portage /var/tmp/portage-disk
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda3       232G   13G  207G   6% /
/dev/sda3       232G   13G  207G   6% /
```
Both paths resolve to `/dev/sda3`. **fstab is not parsed inside the chroot** —
everything emerges to the real SATA SSD (207 GB free).

**Consequence**: during chroot install, **the `package.env` disk-fallback
routing is inert**. Every package builds on `/dev/sda3` regardless of listing.
We briefly worried about a 4 GB tmpfs OOM on `llvm-core/clang-21.1.8` — but
there was no tmpfs to OOM in the first place.

**Implications**:
- **False-positive worry during install**: seeing clang/llvm NOT in package.env
  is harmless *during install*. It only matters post-first-boot.
- **Real implication**: the first boot finally mounts the tmpfs from fstab,
  and at that point `package.env` routing becomes load-bearing.
  **`llvm-core/clang` is missing from our package.env** — add it before the
  first post-boot `@world` update, or the first clang rebuild will OOM the
  4 GB tmpfs.

**Fix** (apply before first post-boot emerge):
```bash
echo "llvm-core/clang   notmpfs.conf" >> /etc/portage/package.env
```
TODO: ship this in the initial repo `package.env` so future installs get it.

## 3. GNOME idle/sleep on Fedora 43 live is aggressive

GNOME on the live USB will blank, sleep, and suspend aggressively during a
multi-hour install. The polkit-prompted `systemd-inhibit` is not usable from
a pure terminal session.

**What works** (run as user):
```bash
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
xset s off -dpms
```

**Nuclear option**:
```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
```

## 4. Fedora live rootfs overlay fills up during long installs

The live USB's writable overlay (`LiveOS_rootfs`) is **1.6 GB total**. During a
multi-hour install session with Firefox open, periodic cache writes, and
accumulated log data, it can fill to 100% and cause apparently random
"No space left on device" errors for writes into `/home/liveuser/...`, even
though the target SSD has 200+ GB free.

**Diagnosis**:
```bash
df -h /           # LiveOS_rootfs should be well under 100%
```

**Fix**:
```bash
rm -rf /home/liveuser/.cache/*     # usually the biggest hog (Firefox, fontconfig)
```
Other candidates: `/var/cache`, `/var/log`, any large downloads in `~/Downloads`.

**Prevention**: use `/tmp` (separate 3.8 GB tmpfs) for scratch work during the
install session, not `~/...`.

## 5. Build wall-clock expectations on Tremont 4C/4T, -j2

Anecdotal from this install:
- Phase 1 (stage3 world rebuild, ~46 packages): **~30–60 min**
- Phase 2 kernel (linux-firmware ~5 GB copy + gentoo-sources unpack +
  `make -j2`): **~60–90 min total**, `make -j2` itself ~30–60 min
- Phase 6 (full `@world`, XFCE + deps): **~8–16 hours**
  - `llvm-core/clang` alone: several hours (2209 ninja steps on this CPU)
  - Everything else combined: a few more hours

Rule of thumb: **~2–3× slower than Surface Pro 6**. Remote cross-compile from
a faster machine is the right answer if time is tight (repo backlog item).

## 6. I/O-bound "copying sources" is not a hang

During `sys-kernel/gentoo-sources` merge you'll see `copying sources` for 2–5
minutes with no other output. Not a hang — just unpack + copy of the full
6.18.x tree to `/usr/src/`. Normal.

## 8. `discard=async` is btrfs-only — breaks ext4 root mount

**Symptom**: first boot comes up with a read-only root filesystem. SSH keys
can't be written, NetworkManager can't start, sshd fails, systemd-tmpfiles
fails — everything cascades from the read-only root.

**Cause**: `gentoo_install_part2.sh` generated fstab with `discard=async` on
the ext4 root partition. `discard=async` is a **btrfs-only mount option**.
For ext4, the kernel rejects it with `Unexpected value for 'discard'`, and
the root remount-rw fails silently, leaving the system read-only.

**Fix** (applied to `gentoo_install_part2.sh`): removed `discard=async`
entirely. Use weekly `fstrim` via cronie instead (lower overhead, works on
any filesystem).

**Recovery if hit on a live system**: boot with GRUB edit (`ro` → `rw` on
kernel line), then edit `/etc/fstab` to remove `discard=async`, reboot.

**Lesson**: always verify mount options are valid for the target filesystem.
`discard` (boolean) works on ext4; `discard=async` does not.

## 9. `app-alternatives/cpio` file collision warning is expected

Phase 1 emits a scary-looking multi-line warning about `/bin/cpio` colliding,
ending with "Package merged despite file collisions". **This is intentional** —
`app-alternatives/*` are Gentoo's mechanism for swapping between BSD and GNU
tool variants. Ignore.
