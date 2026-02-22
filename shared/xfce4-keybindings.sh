#!/bin/bash
# XFCE4 keyboard shortcuts - restore script
# Run as your normal user (not root) after XFCE is installed
# Usage: bash shared/xfce4-keybindings.sh

set -euo pipefail

echo "Restoring XFCE4 keyboard shortcuts..."

# --- Window Manager (xfwm4) keybindings ---

# Window tiling (Super + Arrow keys)
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Super>Left" -n -t string -s "tile_left_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Super>Right" -n -t string -s "tile_right_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Super>Up" -n -t string -s "tile_up_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Super>Down" -n -t string -s "tile_down_key"

# Window tiling (Super + Numpad)
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Super>KP_Left" -n -t string -s "tile_left_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Super>KP_Right" -n -t string -s "tile_right_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Super>KP_Up" -n -t string -s "tile_up_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Super>KP_Down" -n -t string -s "tile_down_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Super>KP_Home" -n -t string -s "tile_up_left_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Super>KP_Page_Up" -n -t string -s "tile_up_right_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Super>KP_End" -n -t string -s "tile_down_left_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Super>KP_Next" -n -t string -s "tile_down_right_key"

# Window management
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Alt>F4" -n -t string -s "close_window_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Alt>F7" -n -t string -s "move_window_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Alt>F8" -n -t string -s "resize_window_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Alt>F9" -n -t string -s "hide_window_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Alt>F10" -n -t string -s "maximize_window_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Alt>F11" -n -t string -s "fullscreen_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Super>Return" -n -t string -s "fullscreen_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Alt>F12" -n -t string -s "above_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Alt>F6" -n -t string -s "stick_window_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Alt>space" -n -t string -s "popup_menu_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Super>Tab" -n -t string -s "switch_window_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Alt>Tab" -n -t string -s "cycle_windows_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Alt><Shift>Tab" -n -t string -s "cycle_reverse_windows_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Shift><Alt>Page_Up" -n -t string -s "raise_window_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Shift><Alt>Page_Down" -n -t string -s "lower_window_key"

# Show desktop
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Primary><Alt>d" -n -t string -s "show_desktop_key"

# Workspace navigation
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Primary><Alt>Left" -n -t string -s "left_workspace_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Primary><Alt>Right" -n -t string -s "right_workspace_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Primary><Alt>Up" -n -t string -s "up_workspace_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Primary><Alt>Down" -n -t string -s "down_workspace_key"

# Move window between workspaces
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Primary><Alt>End" -n -t string -s "move_window_next_workspace_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Primary><Alt>Home" -n -t string -s "move_window_prev_workspace_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Primary><Shift><Alt>Left" -n -t string -s "move_window_left_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Primary><Shift><Alt>Right" -n -t string -s "move_window_right_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Primary><Shift><Alt>Up" -n -t string -s "move_window_up_key"

# Workspace add/delete
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Alt>Insert" -n -t string -s "add_workspace_key"
xfconf-query -c xfce4-keyboard-shortcuts -p "/xfwm4/custom/<Alt>Delete" -n -t string -s "del_workspace_key"

# --- Application shortcuts (commands) ---

xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary><Alt>t" -n -t string -s "exo-open --launch TerminalEmulator"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary><Alt>f" -n -t string -s "thunar"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Super>e" -n -t string -s "thunar"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Super>l" -n -t string -s "xflock4"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary><Alt>l" -n -t string -s "xflock4"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary><Alt>Delete" -n -t string -s "xfce4-session-logout"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary><Alt>Escape" -n -t string -s "xkill"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary><Shift>Escape" -n -t string -s "xfce4-taskmanager"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary>Escape" -n -t string -s "xfdesktop --menu"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Super>r" -n -t string -s "xfce4-appfinder -c"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Super>space" -n -t string -s "xfce4-appfinder -c"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Super>p" -n -t string -s "xfce4-display-settings --minimal"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Alt>F1" -n -t string -s "xfce4-popup-applicationsmenu"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Alt>F2" -n -t string -s "xfce4-appfinder --collapsed"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Alt>F3" -n -t string -s "xfce4-appfinder"

# Screenshots
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/Print" -n -t string -s "xfce4-screenshooter"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Alt>Print" -n -t string -s "xfce4-screenshooter -w"
xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Shift>Print" -n -t string -s "xfce4-screenshooter -r"

echo "Done. Keybindings restored."
