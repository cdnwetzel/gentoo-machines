# OptiPlex 3080 — STATUS

Role: headless always-on automation/services host.
**INSTALLED AND VERIFIED 2026-10-16** — `tools/verify-install.sh` exits 0
(0 failures, 2 benign warnings). Evidence: `first-boot-20261016.log`.

## Hardware notes (post-install, re-harvested 2026-10-16)

- i3-10105 (Comet Lake, 4C/8T) — `-march=skylake` per fleet gotcha #18.
- RAM: 16 GB DDR4-2666 dual-channel. DIMM1 = original Hynix HMAA1GU6CJR6N-XN;
  DIMM2 = **borrowed** Hynix HMA81GU6JJR8N-VK — replace with the ordered
  HMAA1GU6CJR6N-XN twin when it arrives. (zram still 4G; consider 8G after
  the RAM swap settles.)
- Storage: fanxiang S500 Pro 256 GB NVMe (Realtek RTS5765DL DRAM-less
  controller) installed in M.2 Socket 3 = `/dev/nvme0n1`, the system disk.
  SMART pristine (0% used, 0h at install); full-device read pass sustained
  ~2.8 GB/s pre-install.
- **Original SATA SSD (ADATA SU635 240 GB) was dying** (QLC read-retry
  failure with clean SMART) and is now physically disconnected. If it is
  ever reconnected: do NOT install to it, do NOT trust it for data.
- NIC: Realtek RTL8111 (r8169), wired only, no Wi-Fi/BT.
  **Interface name is `enp2s0`** (harvest predicted enp1s0; the SATA
  removal shifted PCI enumeration). NetworkManager DHCP, no action needed.
- BIOS 2.33.0: Secure Boot disabled, SATA AHCI confirmed at install.
- Chassis: SFF. Empty PCIe x16 (low-profile only, ~200 W PSU, no aux power).

## How it was built (2026-10-15/16)

Full rootfs prebuilt on the T5810 binhost (`/opt/buildhosts/optiplex-3080*`):
stage3-amd64-openrc + full @world (247 binpkgs, 1.7 GB retained on the
binhost for future updates) + machine configs + user chris + services +
prebuilt 6.18.57 kernel. Install day was: part1 (partition NVMe, labels
EFI/BOOT/ROOT) → stream `prebuilt/optiplex-3080-rootfs.tar.zst` (3.9 GB,
~40 s over GbE from the Mac mirror) → chroot grub-install + grub-mkconfig +
EFI fallback `bootx64.efi`. First boot straight to network + sshd.

## Post-boot fixes applied live (now persisted here)

- `nm-hostname-mode.conf` — deployed to `/etc/NetworkManager/conf.d/`:
  `hostname-mode=none`. NM was stomping `/etc/hostname` (optiplex-3080)
  with `localhost` from DHCP; OpenRC `hostname` service owns it now.
- `sys-apps/smartmontools` added to world (NVMe health monitoring).
- Console passwords set for root + chris via chpasswd (temporary, user
  changed at first login).
- `tools/verify-install.sh` fixes that came out of this install:
  sudoers check now includes `/etc/sudoers.d/`; display-manager only
  checked when the init script exists (headless machines skip); kernel
  image check globs `vmlinuz-<kver>*` (machine-suffixed images).

## Build artifacts

- `prebuilt/optiplex-3080-rootfs.tar.zst` — 3.9 GB install image (as built;
  predates the three live fixes above — reapply them if re-imaging).
- `prebuilt/kernel-artifacts.tar.gz` — vmlinuz/System.map/intel-uc.img.
- T5810 `/opt/buildhosts/optiplex-3080/` — binhost chroot retained;
  `optiplex-3080-rootfs/` — configured clone. Do not delete; future
  @world updates build there.
- `harvest/` — pre-install (2026-10-15) and post-hardware-change
  (2026-10-16) harvest + deep_harvest logs.

## Verification

- `first-boot-20261016.log`: identity, 16 GB RAM + zram, NVMe layout,
  enp2s0 DHCP + internet, chrony stratum-2 sync, all default-runlevel
  services started, always-on elogind drop-in, microcode rev 0x100 loaded,
  NVME/AHCI built-in, r8169 module.
- `tools/verify-install.sh`: exit 0 (2026-10-16).
- Kernel: 6.18.57 (`vmlinuz-6.18.57-optiplex-3080`), gentoo-sources ~amd64.
- Memtest86+ on the borrowed DIMM2 stick: not yet run (optional overnight
  pass; do it before trusting the replacement stick too).

## Loose ends

- Old "Windows Boot Manager" NVRAM entry (Boot0000) is stale from the
  pulled SATA drive — harmless (Gentoo is first in BootOrder), can be
  removed with `efibootmgr -B -b 0000`.
- Root password: enabled for console rescue (temporary at install).
  Revert to key-only with `passwd -l root` if desired.
