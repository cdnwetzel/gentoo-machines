# OptiPlex 3080 — Install Preflight (do in order, install day)

## Physical (parts arrived)

1. Power off, unplug. Seat the 8 GB Hynix stick in DIMM2 (white/black slot
   pair — check board silkscreen; both channels populated).
2. Seat the fanxiang S500 Pro 256 GB in the M.2 Socket 3 (2280, screw down).
3. Leave the ADATA SU635 connected but untouched (it is dying; we may pull it
   later). Do not boot from it, do not write to it.
4. F2 at boot → BIOS:
   - Secure Boot → **Disabled** (was enabled at harvest).
   - Storage → confirm **AHCI** (not RAID/RST) — fleet Dell trap.
   - Note BIOS version (was 2.33.0); fwupd update comes later, in P6-style
     maintenance.
5. Boot the Fedora live USB (same Ventoy stick).

## Health checks before partitioning (5 min, catches DOA parts)

```
# 16 GB, both channels, same speed:
dmidecode -t memory | grep -E "Size:|Locator:|Configured Memory Speed"

# NVMe present and healthy:
lsblk -d -o NAME,SIZE,MODEL,TRAN        # nvme0n1 ~238G fanxiang
smartctl -a /dev/nvme0n1 | grep -E "Percentage Used|Available Spare|Critical"

# Full-device read pass — should sustain ~2-3 GB/s, near the rated speed:
dd if=/dev/nvme0n1 of=/dev/null bs=1M status=progress

# RAM: one full memtest86+ pass before trusting the used stick
# (boot it from the Ventoy USB)
```

## Install (rootfs fast path — the system is already built)

The complete installed system (stage3 + full @world + machine configs + user +
services + prebuilt kernel) was assembled on the T5810 and staged as
`/opt/buildhosts/optiplex-3080-rootfs.tar.zst` (3.9 GB). part2/part3 are NOT
needed; they remain in the repo as the reproducible from-scratch path.

From the Fedora live session on the 3080 (as root):

```
# 1. Partition the NVMe (labels EFI/BOOT/ROOT are written here):
scp -r user@<mac>:~/ai/gentoo-machines/machines/optiplex-3080 /root/   # or push from the Mac
bash /root/optiplex-3080/gentoo_install_part1.sh        # targets /dev/nvme0n1

# 2. Mount the new layout:
mount LABEL=ROOT /mnt/gentoo
mkdir -p /mnt/gentoo/boot && mount LABEL=BOOT /mnt/gentoo/boot
mkdir -p /mnt/gentoo/boot/efi && mount LABEL=EFI /mnt/gentoo/boot/efi

# 3. Stream the rootfs straight from the T5810 (~3.9 GB):
ssh chris@jump.example.net 'sudo cat /opt/buildhosts/optiplex-3080-rootfs.tar.zst' \
    | tar --zstd -xf - -C /mnt/gentoo

# 4. Chroot + bootloader:
mount -t proc proc /mnt/gentoo/proc && mount --rbind /sys /mnt/gentoo/sys \
  && mount --rbind /dev /mnt/gentoo/dev && mount --bind /run /mnt/gentoo/run
chroot /mnt/gentoo /bin/bash
source /etc/profile
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo
grub-mkconfig -o /boot/grub/grub.cfg      # picks up vmlinuz-6.18.57-optiplex-3080
mkdir -p /boot/efi/EFI/Boot
cp /boot/efi/EFI/Gentoo/grubx64.efi /boot/efi/EFI/Boot/bootx64.efi   # fallback path
efibootmgr -v                              # confirm 'Gentoo' entry, NVMe first
exit && reboot   # remove USB
```

- Network after boot: NetworkManager + DHCP on enp1s0 — headless, no action needed.
  SSH in as user (key auth already deployed) or root (key only).
- Post-boot: `sh ~/first-boot.sh` (staged on the Mac — scp it over), then
  `verify-install.sh` must exit 0, then commit the machine dir with an updated
  STATUS.md.
- Root password: locked by design (key-only). Set one with `passwd` from a user
  sudo session if console access is ever needed.
