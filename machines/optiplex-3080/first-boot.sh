#!/bin/sh
# first-boot.sh — OptiPlex 3080 first boot into the installed Gentoo (headless).
# Run as the admin user from an SSH session:
#     sh ~/first-boot.sh
# Records gate evidence into ~/first-boot-<timestamp>.log.
# Nothing here changes system config.

LOG="$HOME/first-boot-$(date +%Y%m%d-%H%M%S).log"
say() { printf '\n=== %s\n' "$*" | tee -a "$LOG"; }
run() { printf '$ %s\n' "$*" >>"$LOG"; sh -c "$*" >>"$LOG" 2>&1; }

sudo -v || { echo "sudo failed — is the user in wheel?"; exit 1; }

say "1. Identity"
run "uname -a"
run "cat /sys/class/dmi/id/product_name"          # expect: OptiPlex 3080
run "cat /etc/gentoo-release"

say "2. CPU / memory"
run "lscpu | grep -E 'Model name|^CPU\\(s\\)|MHz'"
run "free -m"                                     # expect ~16 GB after upgrade
run "zramctl"                                     # expect zram0 swap, zstd, 4G

say "3. Storage"
run "lsblk -o NAME,SIZE,MODEL,FSTYPE,MOUNTPOINTS" # nvme0n1: p1 EFI, p2 boot, p3 /
run "df -h / /boot"
run "sudo smartctl -a /dev/nvme0n1 | grep -E 'Percentage Used|Available Spare|Temperature'"

say "4. Network"
run "ip -br addr"                                 # enp1s0 up, DHCP lease
run "nmcli -t device status 2>/dev/null || true"
run "ping -c3 gentoo.org"
run "chronyc tracking 2>/dev/null | head -4"

say "5. Services (OpenRC)"
run "rc-update show default"
run "rc-service sshd status"
run "rc-service earlyoom status"
run "rc-service thermald status"
run "pgrep -a earlyoom"

say "6. Never-sleep (fleet requirement)"
run "cat /etc/elogind/logind.conf.d/always-on.conf"
run "grep -E '^Handle|^Idle' /etc/elogind/logind.conf.d/always-on.conf"

say "7. Microcode + kernel"
run "grep microcode /proc/cpuinfo | head -1"
run "dmesg | grep -i microcode | head -3"
run "zgrep -E 'CONFIG_(BLK_DEV_NVME|SATA_AHCI|R8169)' /proc/config.gz 2>/dev/null || true"

say "8. Fleet verification"
if [ -f ~/gentoo-machines/tools/verify-install.sh ]; then
    sudo bash ~/gentoo-machines/tools/verify-install.sh 2>&1 | tee -a "$LOG"
else
    echo "clone gentoo-machines and run tools/verify-install.sh" | tee -a "$LOG"
fi

say "DONE — attach this log to the machine's STATUS.md entry"
echo "Log: $LOG"
