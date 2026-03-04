#!/bin/bash
# MacBook Pro 12,1 HiDPI setup (150% / 144 DPI)
# Run as your normal user after XFCE is installed and running
# Also applied automatically via restore-desktop.sh
#
# 2560x1600 Retina @ 13.3" = 227 PPI
# 144 DPI = 150% scale (default X11 DPI is 96)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Configuring HiDPI scaling (150% / 144 DPI)..."

# --- Persistent config (survives reboots) ---

# Install .Xresources — loaded at X session start, most reliable DPI source
if [[ -f "$SCRIPT_DIR/Xresources" ]]; then
    cp "$SCRIPT_DIR/Xresources" "$HOME/.Xresources"
    xrdb -merge "$HOME/.Xresources" 2>/dev/null || true
    echo "  [OK] .Xresources installed (Xft.dpi=144, Xcursor.size=36)"
fi

# Install xrandr autostart — backup for apps that read X server DPI directly
mkdir -p "$HOME/.config/autostart"
if [[ -f "$SCRIPT_DIR/xrandr-dpi.desktop" ]]; then
    cp "$SCRIPT_DIR/xrandr-dpi.desktop" "$HOME/.config/autostart/xrandr-dpi.desktop"
    echo "  [OK] xrandr --dpi 144 autostart installed"
fi

# --- XFCE settings (persisted in xfconf XML) ---

# Font rendering DPI — controls text and GTK widget sizing
xfconf-query -c xsettings -p /Xft/DPI -n -t int -s 144 2>/dev/null || \
    xfconf-query -c xsettings -p /Xft/DPI -s 144

# Cursor size (default 24 is tiny at HiDPI — 36 = 24 * 1.5)
xfconf-query -c xsettings -p /Gtk/CursorThemeSize -n -t int -s 36 2>/dev/null || \
    xfconf-query -c xsettings -p /Gtk/CursorThemeSize -s 36

# --- Apply for current session ---

# Set xrandr DPI for the session (catches apps that read X server DPI directly)
xrandr --dpi 144

echo ""
echo "Done. HiDPI configured at 150% (144 DPI)."
echo "  Persistent: .Xresources + xrandr autostart + xfconf"
echo "  Login screen: lightdm.conf (X -dpi 144) + lightdm-gtk-greeter.conf"
echo "  GRUB: GRUB_GFXMODE=1024x768"
echo "  Console: fbcon=font:TER16x32 (already configured)"
echo ""
echo "To change scale factor, edit all DPI values:"
echo "  125% = 120 DPI, cursor 30"
echo "  150% = 144 DPI, cursor 36"
echo "  175% = 168 DPI, cursor 42"
echo "  200% = 192 DPI, cursor 48"
