#!/bin/bash
# XFCE4 panel configuration - restore script
# Run as your normal user (not root) after XFCE is installed
# Usage: bash shared/xfce4-panel.sh

set -euo pipefail

echo "Restoring XFCE4 panel configuration..."

# --- Panel layout ---
# Panel 1: top bar (app menu, tasklist, pager, systray, clock, actions)
# Panel 2: bottom dock (show desktop, launchers, directory menu) - autohide

xfconf-query -c xfce4-panel -p /configver -n -t int -s 2
xfconf-query -c xfce4-panel -p /panels -n -a -t int -s 1 -t int -s 2
xfconf-query -c xfce4-panel -p /panels/dark-mode -n -t bool -s true

# --- Panel 1: Top bar ---
xfconf-query -c xfce4-panel -p /panels/panel-1/icon-size -n -t int -s 16
xfconf-query -c xfce4-panel -p /panels/panel-1/length -n -t int -s 100
xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids -n -a \
    -t int -s 1 -t int -s 2 -t int -s 3 -t int -s 4 -t int -s 5 \
    -t int -s 6 -t int -s 7 -t int -s 8 -t int -s 9 -t int -s 10
xfconf-query -c xfce4-panel -p /panels/panel-1/position -n -t string -s "p=6;x=0;y=0"
xfconf-query -c xfce4-panel -p /panels/panel-1/position-locked -n -t bool -s true
xfconf-query -c xfce4-panel -p /panels/panel-1/size -n -t int -s 26

# --- Panel 2: Bottom dock (autohide) ---
xfconf-query -c xfce4-panel -p /panels/panel-2/autohide-behavior -n -t int -s 1
xfconf-query -c xfce4-panel -p /panels/panel-2/length -n -t int -s 1
xfconf-query -c xfce4-panel -p /panels/panel-2/plugin-ids -n -a \
    -t int -s 11 -t int -s 12 -t int -s 13 -t int -s 14 -t int -s 15 \
    -t int -s 16 -t int -s 17 -t int -s 18
xfconf-query -c xfce4-panel -p /panels/panel-2/position -n -t string -s "p=10;x=0;y=0"
xfconf-query -c xfce4-panel -p /panels/panel-2/position-locked -n -t bool -s true
xfconf-query -c xfce4-panel -p /panels/panel-2/size -n -t int -s 48

# --- Panel 1 plugins ---
# 1: Application Menu
xfconf-query -c xfce4-panel -p /plugins/plugin-1 -n -t string -s "applicationsmenu"
# 2: Tasklist
xfconf-query -c xfce4-panel -p /plugins/plugin-2 -n -t string -s "tasklist"
xfconf-query -c xfce4-panel -p /plugins/plugin-2/grouping -n -t int -s 1
# 3: Separator (expand)
xfconf-query -c xfce4-panel -p /plugins/plugin-3 -n -t string -s "separator"
xfconf-query -c xfce4-panel -p /plugins/plugin-3/expand -n -t bool -s true
xfconf-query -c xfce4-panel -p /plugins/plugin-3/style -n -t int -s 0
# 4: Workspace Pager
xfconf-query -c xfce4-panel -p /plugins/plugin-4 -n -t string -s "pager"
# 5: Separator
xfconf-query -c xfce4-panel -p /plugins/plugin-5 -n -t string -s "separator"
xfconf-query -c xfce4-panel -p /plugins/plugin-5/style -n -t int -s 0
# 6: System Tray
xfconf-query -c xfce4-panel -p /plugins/plugin-6 -n -t string -s "systray"
xfconf-query -c xfce4-panel -p /plugins/plugin-6/known-items -n -a -t string -s "blueman"
xfconf-query -c xfce4-panel -p /plugins/plugin-6/known-legacy-items -n -a -t string -s "notification-daemon"
xfconf-query -c xfce4-panel -p /plugins/plugin-6/square-icons -n -t bool -s true
# 7: Separator
xfconf-query -c xfce4-panel -p /plugins/plugin-7 -n -t string -s "separator"
xfconf-query -c xfce4-panel -p /plugins/plugin-7/style -n -t int -s 0
# 8: Clock
xfconf-query -c xfce4-panel -p /plugins/plugin-8 -n -t string -s "clock"
# 9: Separator
xfconf-query -c xfce4-panel -p /plugins/plugin-9 -n -t string -s "separator"
xfconf-query -c xfce4-panel -p /plugins/plugin-9/style -n -t int -s 0
# 10: Actions (logout/lock/etc)
xfconf-query -c xfce4-panel -p /plugins/plugin-10 -n -t string -s "actions"

# --- Panel 2 plugins ---
# 11: Show Desktop
xfconf-query -c xfce4-panel -p /plugins/plugin-11 -n -t string -s "showdesktop"
# 12: Separator
xfconf-query -c xfce4-panel -p /plugins/plugin-12 -n -t string -s "separator"
# 13-16: Launchers
xfconf-query -c xfce4-panel -p /plugins/plugin-13 -n -t string -s "launcher"
xfconf-query -c xfce4-panel -p /plugins/plugin-14 -n -t string -s "launcher"
xfconf-query -c xfce4-panel -p /plugins/plugin-15 -n -t string -s "launcher"
xfconf-query -c xfce4-panel -p /plugins/plugin-16 -n -t string -s "launcher"
# 17: Separator
xfconf-query -c xfce4-panel -p /plugins/plugin-17 -n -t string -s "separator"
# 18: Directory Menu (home)
xfconf-query -c xfce4-panel -p /plugins/plugin-18 -n -t string -s "directorymenu"
xfconf-query -c xfce4-panel -p /plugins/plugin-18/base-directory -n -t string -s "$HOME"

# --- Create launcher desktop files ---
PANEL_DIR="$HOME/.config/xfce4/panel"

mkdir -p "$PANEL_DIR/launcher-13"
cat > "$PANEL_DIR/launcher-13/17709279641.desktop" << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Exec=exo-open --launch TerminalEmulator
Icon=org.xfce.terminalemulator
StartupNotify=true
Terminal=false
Categories=Utility;X-XFCE;X-Xfce-Toplevel;
Name=Terminal Emulator
Comment=Use the command line
DESKTOP

mkdir -p "$PANEL_DIR/launcher-14"
cat > "$PANEL_DIR/launcher-14/17709279642.desktop" << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Exec=exo-open --launch FileManager %u
Icon=org.xfce.filemanager
StartupNotify=true
Terminal=false
Categories=Utility;X-XFCE;X-Xfce-Toplevel;
Name=File Manager
Comment=Browse the file system
DESKTOP

mkdir -p "$PANEL_DIR/launcher-15"
cat > "$PANEL_DIR/launcher-15/17709279643.desktop" << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Exec=exo-open --launch WebBrowser %u
Icon=org.xfce.webbrowser
StartupNotify=true
Terminal=false
Categories=Network;X-XFCE;X-Xfce-Toplevel;
Name=Web Browser
Comment=Browse the web
DESKTOP

mkdir -p "$PANEL_DIR/launcher-16"
cat > "$PANEL_DIR/launcher-16/17709279644.desktop" << 'DESKTOP'
[Desktop Entry]
Version=1.0
Exec=xfce4-appfinder
Icon=org.xfce.appfinder
StartupNotify=true
Terminal=false
Type=Application
Categories=Utility;X-XFCE;
Name=Application Finder
Comment=Find and launch applications installed on your system
DESKTOP

# Set launcher items
xfconf-query -c xfce4-panel -p /plugins/plugin-13/items -n -a -t string -s "17709279641.desktop"
xfconf-query -c xfce4-panel -p /plugins/plugin-14/items -n -a -t string -s "17709279642.desktop"
xfconf-query -c xfce4-panel -p /plugins/plugin-15/items -n -a -t string -s "17709279643.desktop"
xfconf-query -c xfce4-panel -p /plugins/plugin-16/items -n -a -t string -s "17709279644.desktop"

echo "Done. Panel config restored. Run 'xfce4-panel --restart' to apply."
