#!/bin/sh
# /etc/lightdm/display-setup.sh
# Called by LightDM before showing the greeter
# Sets HiDPI scaling for the Surface Pro 6 (2736x1824, 267 PPI)

xrandr --dpi 144
