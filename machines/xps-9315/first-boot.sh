#!/bin/sh
# first-boot.sh — XPS 9315 first boot into the installed Gentoo (RUNBOOK P1.8 + GATE P1).
# Run as chris from a terminal in sway (Super+Enter opens foot), or on tty2:
#     sh ~/first-boot.sh
# It asks for sudo once, connects Wi-Fi if needed, then records the P1 gate
# evidence and the camera probe into ~/first-boot-<timestamp>.log.
# Nothing here changes system config except the Wi-Fi network iwd remembers.

LOG="$HOME/first-boot-$(date +%Y%m%d-%H%M%S).log"
say() { printf '\n=== %s\n' "$*" | tee -a "$LOG"; }
run() { printf '$ %s\n' "$*" >>"$LOG"; sh -c "$*" >>"$LOG" 2>&1; }

sudo -v || { echo "sudo failed — is chris in wheel and /etc/sudoers.d/wheel present?"; exit 1; }

# --- 1. Wi-Fi -----------------------------------------------------------------
say "1. Wi-Fi"
if ping -c1 -W3 gentoo.org >/dev/null 2>&1; then
    echo "already online" | tee -a "$LOG"
else
    iwctl station wlan0 scan; sleep 4
    iwctl station wlan0 get-networks
    printf 'SSID to join: '; read -r SSID
    iwctl station wlan0 connect "$SSID"      # iwctl prompts for the passphrase
    sleep 6
fi
run "iwctl station wlan0 show"
run "ip -4 addr show wlan0"
run "ping -c3 gentoo.org"

# --- 2. P1 gate evidence ------------------------------------------------------
say "2. Kernel / services"
run "uname -r"
run "rc-update -v show | grep -E 'dbus|iwd|dhcpcd|elogind|earlyoom|thermald|local|chronyd|sysklogd'"
run "cat /proc/cmdline"
run "swapon --show; zramctl"

say "3. Display / session"
if [ -n "$WAYLAND_DISPLAY" ]; then
    run "swaymsg -t get_outputs | grep -E 'name|current_mode|width|height|refresh' | head -8"
else
    echo "not inside sway — skip outputs (run again from a sway terminal)" | tee -a "$LOG"
fi

say "4. Audio (expect the sof-soundwire card, not Dummy Output)"
run "aplay -l"
run "wpctl status | sed -n '1,40p'"
run "pgrep -a pipewire; pgrep -a wireplumber"
run "sudo dmesg | grep -iE 'sof-audio|tplg|rt1316|rt71[45]' | tail -8"

say "5. Graphics / VA-API"
run "ls /sys/class/backlight/; cat /sys/class/backlight/intel_backlight/brightness"
run "command -v vainfo && vainfo 2>&1 | grep -E 'Driver version|VAProfileVP9|VAProfileAV1' | head -6"

say "6. Power"
run "cat /sys/power/mem_sleep"
run "cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference"
run "cat /sys/bus/i2c/devices/i2c-VEN_0488:00/power/wakeup"
run "cat /sys/class/sound/ctl-led/mic/mode"

say "7. Camera probe on this kernel (RUNBOOK P3.1)"
run "sudo dmesg | grep -iE 'ipu6|ivsc|intel_vsc|ov01a10|ljca|int3472' | grep -v 'Modules linked' | tail -20"
run "sudo cat /sys/kernel/debug/devices_deferred"
run "ls /dev/media* /dev/video* 2>/dev/null | wc -l"
run "command -v cam && cam --list"

say "8. Memory baseline (idle)"
run "free -m"
run "ps -eo rss,comm --sort=-rss | head -12"

# --- 3. Suspend/resume x3 (optional, interactive) ----------------------------
say "9. Suspend/resume"
printf 'Run 3 suspend/resume cycles now? Each one sleeps until you press the power button. [y/N] '
read -r ans
if [ "$ans" = y ] || [ "$ans" = Y ]; then
    for i in 1 2 3; do
        echo "cycle $i: suspending in 3 s ..." | tee -a "$LOG"; sleep 3
        loginctl suspend; sleep 8
    done
    run "sudo dmesg | grep -iE 'PM: suspend (entry|exit)|s2idle|ACPI: PM' | tail -12"
    run "sudo cat /sys/kernel/debug/pmc_core/slp_s0_residency_usec"
else
    echo "skipped" | tee -a "$LOG"
fi

say "Done. Log: $LOG"
echo "Copy it somewhere Claude can read (e.g. the Ventoy stick) or paste it back."
