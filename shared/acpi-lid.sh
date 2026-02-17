#!/bin/sh
# /etc/acpi/actions/lid.sh
# Toggle internal display on lid open/close
# Requires: xhost +local:0 (run once as your user in XFCE session)

# Find the active X display and user
export DISPLAY=:0
export XAUTHORITY=/home/chris/.Xauthority

LID_STATE=$(cat /proc/acpi/button/lid/LID0/state | awk '{print $2}')

case "$LID_STATE" in
    open)
        # Enable internal display centered below AOC 34" (3440x1440)
        # X offset: (3440 - 1920) / 2 = 760, Y offset: 1440
        xrandr --output eDP-1 --auto --pos 760x1440
        logger "ACPI lid: opened - enabled eDP-1"
        ;;
    closed)
        # Disable internal display
        xrandr --output eDP-1 --off
        logger "ACPI lid: closed - disabled eDP-1"
        ;;
esac
