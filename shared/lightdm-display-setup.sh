#!/bin/sh
# /etc/lightdm/display-setup.sh
# Called by LightDM before showing the greeter
# Ensures login screen appears on the correct display in clamshell mode

LID_STATE=$(cat /proc/acpi/button/lid/LID0/state | awk '{print $2}')

if [ "$LID_STATE" = "closed" ]; then
    xrandr --output eDP-1 --off
    xrandr --output DP-3 --auto --primary
fi
