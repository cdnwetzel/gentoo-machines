#!/bin/sh
# /etc/lightdm/display-setup.sh
# Called by LightDM before showing the greeter
# Sets HiDPI scaling for the MacBook Pro 12,1 (2560x1600, 227 PPI)

xrandr --dpi 144
