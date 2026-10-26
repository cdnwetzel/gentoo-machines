#!/bin/sh
# keep-awake.sh — prevent screen blanking during long compiles
# Requires: x11-misc/xdotool
# Usage: ./keep-awake.sh (Ctrl-C to stop)

trap 'echo "Stopped."; exit 0' INT TERM
echo "Keep-awake running (Ctrl-C to stop)..."
while true; do
    xdotool mousemove_relative -- 1 1
    xdotool mousemove_relative -- -1 -1
    sleep 60
done
