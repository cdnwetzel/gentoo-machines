#!/bin/bash
# powercap-profile.sh — set Intel RAPL package power limits for XPS 9510
#
# Why: i7-11800H in the XPS 15 chassis hits the 95°C wall during sustained
# CPU+GPU inference and the EC drops the package down to ~800 MHz. Capping
# PL1 (long-term sustained) and PL2 (short burst) keeps thermals in the
# safe range while still allowing peak burst for prompt-prefill spikes.
#
# Defaults are sized for: docked, AC, lid-closed, RTX 3050 Ti loaded.
# Override via /etc/conf.d/powercap-profile (PL1_UW, PL2_UW).
#
# Usage:
#   powercap-profile.sh apply   # write limits + log result
#   powercap-profile.sh show    # print current limits
#   powercap-profile.sh reset   # restore kernel defaults from MSR
#
# Idempotent; safe to re-run.

set -u

RAPL_PKG=/sys/class/powercap/intel-rapl:0
CONF=/etc/conf.d/powercap-profile

PL1_UW_DEFAULT=35000000   # 35 W sustained
PL2_UW_DEFAULT=60000000   # 60 W burst

[ -r "$CONF" ] && . "$CONF"
PL1_UW="${PL1_UW:-$PL1_UW_DEFAULT}"
PL2_UW="${PL2_UW:-$PL2_UW_DEFAULT}"

die() { echo "powercap-profile: $*" >&2; exit 1; }

[ -d "$RAPL_PKG" ] || die "$RAPL_PKG missing — kernel CONFIG_INTEL_RAPL or hardware mismatch"

read_uw() { cat "$RAPL_PKG/$1" 2>/dev/null; }

show() {
    local pl1 pl2 cur_pl1 cur_pl2
    pl1=$(read_uw constraint_0_power_limit_uw)
    pl2=$(read_uw constraint_1_power_limit_uw)
    cur_pl1=$(awk -v v="$pl1" 'BEGIN{printf "%.1f", v/1000000}')
    cur_pl2=$(awk -v v="$pl2" 'BEGIN{printf "%.1f", v/1000000}')
    echo "PL1 (sustained): ${cur_pl1} W   [${pl1} µW]"
    echo "PL2 (burst):     ${cur_pl2} W   [${pl2} µW]"
}

apply() {
    [ "$EUID" -eq 0 ] || die "apply requires root"
    echo "powercap-profile: BEFORE"; show
    echo "$PL1_UW" > "$RAPL_PKG/constraint_0_power_limit_uw" \
        || die "failed to write PL1 — try: chmod 644 $RAPL_PKG/constraint_0_power_limit_uw"
    echo "$PL2_UW" > "$RAPL_PKG/constraint_1_power_limit_uw" \
        || die "failed to write PL2"
    # Re-enable the package-level powercap (kernel can disable on AC transition).
    # RAPL has no per-constraint enable file — only this package-level toggle.
    echo 1 > "$RAPL_PKG/enabled" 2>/dev/null || true
    echo "powercap-profile: AFTER"; show
    logger -t powercap-profile "applied PL1=${PL1_UW}µW PL2=${PL2_UW}µW"
}

reset() {
    [ "$EUID" -eq 0 ] || die "reset requires root"
    # Trigger driver re-read of MSR defaults by toggling enable
    echo 0 > "$RAPL_PKG/enabled" 2>/dev/null || true
    echo 1 > "$RAPL_PKG/enabled" 2>/dev/null || true
    echo "powercap-profile: reset to kernel/MSR defaults"; show
}

case "${1:-apply}" in
    apply) apply ;;
    show)  show ;;
    reset) reset ;;
    *)     echo "usage: $0 {apply|show|reset}"; exit 2 ;;
esac
