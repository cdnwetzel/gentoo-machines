#!/bin/bash
# Surface Pro 6 HiDPI setup (150% / 144 DPI)
# Run as your normal user after XFCE is installed and running
# Also applied automatically via restore-desktop.sh
#
# 2736x1824 PixelSense @ 12.3" = 267 PPI
# 144 DPI = 150% scale (default X11 DPI is 96)

set -euo pipefail

echo "Configuring HiDPI scaling (150% / 144 DPI)..."

# Font rendering DPI — controls text and GTK widget sizing
xfconf-query -c xsettings -p /Xft/DPI -n -t int -s 144 2>/dev/null || \
    xfconf-query -c xsettings -p /Xft/DPI -s 144

# Cursor size (default 24 is tiny at HiDPI — 36 = 24 * 1.5)
xfconf-query -c xsettings -p /Gtk/CursorThemeSize -n -t int -s 36 2>/dev/null || \
    xfconf-query -c xsettings -p /Gtk/CursorThemeSize -s 36

# Set xrandr DPI for the session (catches apps that read X server DPI directly)
xrandr --dpi 144

echo "Done. HiDPI configured at 150% (144 DPI)."
echo ""
echo "To change scale factor, edit Xft/DPI:"
echo "  125% = 120 DPI, cursor 30"
echo "  150% = 144 DPI, cursor 36"
echo "  175% = 168 DPI, cursor 42"
echo "  200% = 192 DPI, cursor 48"
