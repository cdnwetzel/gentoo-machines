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

echo "=== Adding pulseaudio plugin to top panel ==="
# Find next available plugin ID
MAX_ID=$(xfconf-query -c xfce4-panel -l | grep '/plugins/plugin-' | sed 's|.*/plugin-||' | sed 's|/.*||' | sort -n -u | tail -1)
if [ -z "$MAX_ID" ] || [ "$MAX_ID" -eq 0 ]; then
    echo "ERROR: Could not read panel plugin IDs" >&2
    exit 1
fi
NEXT_ID=$((MAX_ID + 1))
echo "Max plugin ID: $MAX_ID, creating plugin-${NEXT_ID}"

# Create the pulseaudio plugin
xfconf-query -c xfce4-panel -n -t string -p "/plugins/plugin-${NEXT_ID}" -s "pulseaudio"

# Insert before clock (plugin-8) — between systray-6 and separator-7
# Current: [1,2,3,4,5,6,7,8,9,10] → [1,2,3,4,5,6,NEXT,7,8,9,10]
xfconf-query -c xfce4-panel -n -t int -t int -t int -t int -t int -t int -t int -t int -t int -t int -t int \
  -p /panels/panel-1/plugin-ids \
  -s 1 -s 2 -s 3 -s 4 -s 5 -s 6 -s "${NEXT_ID}" -s 7 -s 8 -s 9 -s 10

echo ""
echo "=== Done! ==="
echo "Plugin ${NEXT_ID} (pulseaudio) added to panel."
echo ""
echo "Restart the panel to apply:"
echo "  xfce4-panel -r"
echo ""
echo "Brightness keys require acpilight + video group membership."
echo "Log out and back in if you just got added to the video group."
