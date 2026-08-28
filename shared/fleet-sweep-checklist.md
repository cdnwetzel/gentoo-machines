# Fleet Portage Sweep — 2026-08-28

Working checklist for bringing every production machine's `/etc/portage` back
into agreement with the repo, after `tools/deploy-portage.sh` landed.

**Companion to** `shared/machine-checklist.md`, which is for onboarding a *new*
machine. This one is a one-off sweep of the existing fleet — delete it, or
fold what it teaches into the tools, once every box is ticked.

---

## The rule that earned its place

**Dry run first, every machine, every time. Read the diff before applying.**

Three machines were checked on the first night. All three had drift. On **two**
of them the drift ran in the direction that breaks things, and neither was
visible without diffing repo against live:

| machine | what a blind apply would have done |
|---|---|
| xps-9510 | re-masked `nvidia-drivers` and `chromium-bin` to stable; dropped `persistenced` |
| precision-t5810 | masked the installed CUDA toolkit — no stable version exists to fall back to |
| asrock-b550 | stripped `iptables[nftables]`, breaking podman's dependency |

A `+` line in the diff is the repo installing something. A `-` line is the repo
**deleting** something live has. Deletions are where the damage is: read every
one and decide whether the repo or the machine is the stale side. It has been
the repo more often than not.

---

## Order, and why

1. **xps-9510** — already swept; only `fetch` remains. Doing it first exercises
   the repaired workaround registry on a machine already in a known state.
2. **asrock-b550** — comment-only diffs plus the shared fingerprint block. Low
   consequence, and it answers the open `package.env` filename question.
3. **precision-t5810** — highest consequence. Apply is safe, but it unpins
   `nvidia-drivers` from 580.142 to the current branch, which lands on the next
   `@world`. Do it once the pattern is proven on the two above.
4. **surface-pro-6** — never swept, and separately owes the microcode drop-in.
5. **beelink-minis** — never swept.
6. **optiplex-3090** — never swept.

Out of scope: `nuc11` (never installed), `mbp-2015` (retired to macOS),
`xps-9315` (Windows in this repo; the Arch build lives in `arch-machines`),
`precision-7960` (reference only, RHEL, VPN-gated).

---

## Per-machine procedure

Identical everywhere. Steps 2 and 3 are the whole point.

```bash
# 1. get the repo fixes
git pull

# 2. DRY RUN — changes nothing, needs no root
tools/deploy-portage.sh

# 3. STOP. Read every '-' line. Decide before continuing.

# 4. apply
sudo tools/deploy-portage.sh --apply

# 5. what did that queue up?
emerge -pv --changed-use --deep @world | tail -20
```

`--revert` restores the newest backup from
`/var/lib/kernel-update/config-backups/` if step 4 goes wrong.

---

## Per-machine state

### 1. xps-9510 — complete ✅

Fingerprint `sudo`, portage sweep and `fetch` all done. Workaround registry
wrote `package.env/90-workarounds`; news clear. Kernel symlink moved
6.18.46 -> 6.18.47, so a build is queued here too.

<details><summary>original step, kept for reference</summary>

Fingerprint `sudo` done; portage deployed; repo and live agree.

```bash
sudo tools/update-system.sh --dry-run fetch     # preview
sudo tools/update-system.sh fetch               # then for real
```

Watch for, under `=== Portage Workarounds ===`:

```
>>> Installed workaround: freerdp-ffmpeg-fix.conf
>>> Added package.env entry: net-misc/freerdp freerdp-ffmpeg-fix.conf
```

That is the **first entry the registry has ever written** — the code path was
broken (`echo >>` into a directory) until 2026-08-27. Afterwards
`/etc/portage/package.env/90-workarounds` should exist with exactly one line.
`Portage workarounds up to date` with no such file means the fix did not take.

Note `fetch` also syncs the tree and may pull a newer `gentoo-sources`,
re-pointing `/usr/src/linux` and queueing a kernel build behind it.

</details>

### 2. asrock-b550 — complete ✅

Done 2026-08-28. `fetch`, `migrate-package-env --apply`, `deploy-portage
--apply` all complete; all four pairs report in sync. Both at-risk directives
verified present afterwards: `iptables[nftables]` in
`package.use/asrock-b550`, the freerdp workaround in
`package.env/90-workarounds`.

**Outstanding here, not from this sweep:** `emerge -p --changed-use --deep
@world` wants 33 packages, essentially all version upgrades exposed by the tree
sync rather than anything the portage changes caused — `iptables` is notably
absent from that list. Includes `nvidia-cuda-toolkit-12.9.2` (5.7 GB),
`llvm-22`, `rust-bin-1.96`, `nodejs-26`, `mesa-26`. Kernel build also queued
(6.18.21 -> 6.18.47).

<details><summary>procedure used, kept for the other single-file machines</summary>

#### Migrate package.env FIRST, then standard procedure

`/etc/portage/package.env` here is a **single file**, and both tools want to
own it. Migrate before deploying, or the deploy deletes the freerdp entry the
workaround registry installed on 2026-08-28:

```bash
tools/migrate-package-env.sh                  # dry run — read the split
sudo tools/migrate-package-env.sh --apply
```

Afterwards `00-notmpfs` should hold the ten notmpfs entries and match the repo
copy exactly, and `90-workarounds` the single freerdp line. Then standard
procedure.

</details> Expect three diffs, all safe after `360b444`:

- `shared` — adds the fingerprint block; **no longer** removes
  `iptables[nftables]`, which is now carried in the machine file
- `asrock-b550` package.use — **comment-only** (RTX 3060 Ti → 5060 Ti)
- `asrock-b550` package.accept_keywords — **comment-only**

Also report what the dry run prints for the missing `package.env` destination.
`00-notmpfs` was only ever verified on the xps-9510; the script now lists the
directory's real contents so the mapping in `PAIRS` can be corrected.

### 3. precision-t5810 — repo fix pushed, not yet applied

**Interrupted state, 2026-08-28.** A `fetch` was run here out of order and
aborted partway through (`/etc/portage/env` did not exist; fixed since). What
already landed: the gentoo tree synced, `gentoo-sources-6.18.47` installed, and
`/usr/src/linux` re-pointed from 6.18.21 to **6.18.47** — so a kernel build is
now queued on this machine. What did not: the workaround install, and the news
items were never displayed. Re-run `fetch` after pulling; it is idempotent.

Also outstanding here, reported by that run:
`emerge --oneshot sys-apps/portage` (portage update available, do it before
other packages), and 2 unread news items.


Standard procedure. After `360b444` the CUDA keyword is restored, so confirm
the dry run **no longer** shows `-dev-util/nvidia-cuda-toolkit ~amd64`. If it
still does, the pull did not land — stop.

Applying unpins `nvidia-drivers` 580.142 → current branch. That is intended for
Ampere, but the upgrade lands on the next `@world`, not now. Decide deliberately.

Hostname does not resolve fleet-wide; reachable at `10.0.1.125`.

### 4. surface-pro-6 — never swept

Standard procedure, plus one item carried from an earlier session:

```bash
sudo install -m 755 shared/35-intel-microcode.install /etc/kernel/preinst.d/
```

Suppresses the upstream microcode hook's `--list-all --list` dump on every
`make install`. Already deployed on xps-9510 and precision-t5810.

### 5. beelink-minis — never swept

Standard procedure. No NVIDIA, no known machine-specific traps.

### 6. optiplex-3090 — never swept

Standard procedure. `CLAUDE.md` still records nvidia `595.58.03` for this
machine; check the installed version while you are there and report it rather
than assuming it moved in step with the xps-9510's 610.57.04.

---

## Falls out of this sweep

- **Naming is inconsistent three ways.** `/etc/hosts` on the xps-9510 defines
  `Asrock` -> 10.0.1.115 and `T5810` -> 10.0.1.125 (each listed twice), so
  `asrock` and `t5810` resolve. The *canonical* repo names do not:
  `asrock-b550`, `precision-t5810`, `surface-pro-6`, `beelink-minis` and
  `nuc11` all fail. `Opti3090` points at 192.168.111.97, a different subnet,
  and is unreachable. So there are three naming schemes in play — repo machine
  dirs (`asrock-b550`), real hostnames (`asrock-b550`, `xps9510`), and hosts
  aliases (`Asrock`) — and hand-maintained hosts files on every node is the
  wrong end to fix it from. Related: the T5810 holds two DHCP addresses on one
  interface.
- **`shared/package.accept_keywords` and `shared/package.license` have no
  destination.** Reported as unmapped on every run because their contents were
  hand-merged into differently-named live files. Needs a decision, not a fix.
- **`CLAUDE.md` nvidia versions are unverified** for asrock-b550 and
  optiplex-3090 (both still say 595.58.03).
