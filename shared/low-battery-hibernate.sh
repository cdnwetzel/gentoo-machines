#!/bin/bash
# low-battery-hibernate.sh — Hibernate when battery drops to critical level
#
# Install: crontab -e → */2 * * * * /usr/local/bin/low-battery-hibernate.sh
# Or run hibernate-setup.sh which installs this automatically.
#
# Desktops/servers with no battery exit silently (UPS uses apcupsd instead).

THRESHOLD=5  # percent

BATTERY=""

# Auto-detect battery: BAT0 (most laptops) or BAT1 (Surface Pro 6)
for bat in BAT0 BAT1; do
    if [[ -d "/sys/class/power_supply/$bat" ]]; then
        BATTERY="$bat"
        break
    fi
done

# No battery = desktop/server, exit silently
[[ -z "$BATTERY" ]] && exit 0

# Only act when discharging
STATUS=$(cat "/sys/class/power_supply/$BATTERY/status")
[[ "$STATUS" != "Discharging" ]] && exit 0

# Check level
CAPACITY=$(cat "/sys/class/power_supply/$BATTERY/capacity")
if [[ "$CAPACITY" -le "$THRESHOLD" ]]; then
    logger -t low-battery "Battery at ${CAPACITY}% — hibernating"
    sync
    echo disk > /sys/power/state
fi
