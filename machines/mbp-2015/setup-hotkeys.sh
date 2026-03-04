#!/bin/bash
# MacBook Pro 12,1 (Early 2015) — Fn row hotkey setup for XFCE
# Run from the desktop session (not SSH)
#
# Fn row layout:
#   F1  XF86MonBrightnessDown    → xbacklight -dec 10
#   F2  XF86MonBrightnessUp      → xbacklight -inc 10
#   F5  XF86KbdBrightnessDown    → kbd backlight -25
#   F6  XF86KbdBrightnessUp      → kbd backlight +25
#   F10 XF86AudioMute            → amixer set Master toggle
#   F11 XF86AudioLowerVolume     → handled by pulseaudio plugin
#   F12 XF86AudioRaiseVolume     → handled by pulseaudio plugin

set -e

# Auto-detect DBUS session from xfce4-session if not set
if ! xfconf-query -c xfce4-panel -l &>/dev/null; then
    echo "Detecting DBUS session..."
    XFCE_PID=$(pgrep -u "$(id -u)" xfce4-session | head -1)
    if [ -z "$XFCE_PID" ]; then
        echo "ERROR: xfce4-session not found. Run this from the desktop." >&2
        exit 1
    fi
    eval "$(cat /proc/$XFCE_PID/environ 2>/dev/null | tr '\0' '\n' | grep -E '^(DISPLAY|DBUS_SESSION_BUS_ADDRESS)=' | sed 's/^/export /')"
    echo "Using DISPLAY=$DISPLAY DBUS=$DBUS_SESSION_BUS_ADDRESS"
fi

XKS="xfce4-keyboard-shortcuts"
CMD="/commands/custom"

echo "=== Setting up display brightness (F1/F2) ==="
xfconf-query -c "$XKS" -n -t string -p "$CMD/XF86MonBrightnessDown" -s "xbacklight -dec 10"
xfconf-query -c "$XKS" -n -t string -p "$CMD/XF86MonBrightnessUp"   -s "xbacklight -inc 10"

echo "=== Setting up keyboard backlight (F5/F6) ==="
KBD="/sys/class/leds/smc::kbd_backlight"
xfconf-query -c "$XKS" -n -t string -p "$CMD/XF86KbdBrightnessDown" \
  -s "sh -c 'f=$KBD/brightness; cur=\$(cat \$f); echo \$(( cur > 25 ? cur - 25 : 0 )) > \$f'"
xfconf-query -c "$XKS" -n -t string -p "$CMD/XF86KbdBrightnessUp" \
  -s "sh -c 'f=$KBD/brightness; cur=\$(cat \$f); echo \$(( cur < 230 ? cur + 25 : 255 )) > \$f'"

echo "=== Setting up mute toggle (F10) ==="
xfconf-query -c "$XKS" -n -t string -p "$CMD/XF86AudioMute" -s "amixer set Master toggle"
# NOTE: Do NOT bind XF86AudioLowerVolume / XF86AudioRaiseVolume —
# xfce4-pulseaudio-plugin handles F11/F12 natively and custom bindings conflict.

echo ""
echo "=== Done! ==="
echo "Brightness keys require acpilight + video group membership."
echo "Log out and back in if you just got added to the video group."
echo ""
echo "NOTE: PulseAudio and battery plugins are configured by shared/xfce4-panel.sh"
echo "      (run via shared/restore-desktop.sh)."
