#!/bin/bash
# ============================================================================
# Post-Install Deep Verification
# ============================================================================
# Run after first boot to verify hardware, drivers, and services.
# Auto-detects machine from DMI. No arguments needed.
#
# Usage: sudo tools/verify-install.sh
# ============================================================================

[[ $EUID -ne 0 ]] && echo "ERROR: Must run as root (sudo)" && exit 1

FAIL=0
WARN=0

pass() { echo "  [OK]   $1"; }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  [WARN] $1"; WARN=$((WARN + 1)); }

check_file()    { [ -f "$1" ] && pass "$2" || fail "$2 ($1 missing)"; }
check_dir()     { [ -d "$1" ] && pass "$2" || fail "$2 ($1 missing)"; }
check_cmd()     { command -v "$1" &>/dev/null && pass "$2" || fail "$2 ($1 not found)"; }
check_service() {
    if rc-status -a 2>/dev/null | grep -q "$1"; then
        pass "Service: $1"
    elif rc-update show 2>/dev/null | grep -q "$1"; then
        warn "Service $1 enabled but not running"
    else
        fail "Service $1 not enabled"
    fi
}
check_module() {
    if lsmod | grep -qw "$1"; then
        pass "Module: $1"
    elif [ -d "/sys/module/$1" ]; then
        pass "Module: $1 (built-in)"
    else
        warn "Module $1 not loaded"
    fi
}

# ============================================================================
# MACHINE DETECTION
# ============================================================================
echo "=== Post-Install Deep Verification ==="
echo ""

SYS_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
CHASSIS=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)
HOSTNAME=$(hostname)

MACHINE="unknown"
HAS_NVIDIA=0
HAS_INTEL_GPU=0
HAS_WIFI=0
HAS_BLUETOOTH=0
IS_LAPTOP=0
HAS_BATTERY=0
WIFI_DRIVER=""

case "$PRODUCT" in
    *"XPS 15 9510"*)    MACHINE="xps-9510"; HAS_NVIDIA=1; HAS_INTEL_GPU=1; HAS_WIFI=1; HAS_BLUETOOTH=1; IS_LAPTOP=1; WIFI_DRIVER="iwlwifi" ;;
    *"XPS 13 9315"*)    MACHINE="xps-9315"; HAS_INTEL_GPU=1; HAS_WIFI=1; HAS_BLUETOOTH=1; IS_LAPTOP=1; WIFI_DRIVER="iwlwifi" ;;
    *"NUC11"*)          MACHINE="nuc11"; HAS_INTEL_GPU=1; HAS_WIFI=1; HAS_BLUETOOTH=1; WIFI_DRIVER="iwlwifi" ;;
    *"Surface Pro"*)    MACHINE="surface-pro-6"; HAS_INTEL_GPU=1; HAS_WIFI=1; HAS_BLUETOOTH=1; IS_LAPTOP=1; WIFI_DRIVER="mwifiex_pcie" ;;
    *"Precision T5810"*|*"Precision Tower 5810"*) MACHINE="precision-t5810"; HAS_NVIDIA=1 ;;
    *"Precision 7960"*) MACHINE="precision-7960"; HAS_NVIDIA=1 ;;
    *"MINI S"*)         MACHINE="beelink-minis"; HAS_INTEL_GPU=1; HAS_WIFI=1; HAS_BLUETOOTH=1; WIFI_DRIVER="iwlwifi" ;;
esac

# MacBook detection via Apple vendor
if [[ "$SYS_VENDOR" == *"Apple"* ]]; then
    MACHINE="mbp-2015"; HAS_INTEL_GPU=1; HAS_WIFI=1; HAS_BLUETOOTH=1; IS_LAPTOP=1; WIFI_DRIVER="brcmfmac"
fi

# Hostname fallback for boards with generic DMI (e.g. ASRock "To Be Filled By O.E.M.")
if [[ "$MACHINE" == "unknown" ]]; then
    case "$HOSTNAME" in
        *"asrock-b550"*) MACHINE="asrock-b550"; HAS_NVIDIA=1; HAS_WIFI=1; HAS_BLUETOOTH=1; WIFI_DRIVER="iwlwifi" ;;
    esac
fi

# Battery detection
[ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ] && HAS_BATTERY=1

echo "Machine: $MACHINE ($PRODUCT)"
echo "Vendor: $SYS_VENDOR"
echo "Hostname: $HOSTNAME"
echo ""

# ============================================================================
# 1. KERNEL & BOOT
# ============================================================================
echo "[1] Kernel & Boot"

KVER=$(uname -r)
pass "Kernel: $KVER"
[ -f "/boot/vmlinuz-$KVER" ] && pass "Kernel image in /boot" || warn "Kernel image not found at /boot/vmlinuz-$KVER"
check_file /boot/grub/grub.cfg "GRUB config"

# Check for kernel errors
KERR=$(dmesg 2>/dev/null | grep -ciE 'error|fail' || true)
if [ "$KERR" -gt 20 ]; then
    warn "dmesg has $KERR error/fail lines — review with: dmesg | grep -iE 'error|fail'"
else
    pass "dmesg errors: $KERR (normal range)"
fi

echo ""

# ============================================================================
# 2. GPU
# ============================================================================
echo "[2] GPU & Display"

# DRM devices
if [ -d /dev/dri ]; then
    CARDS=$(ls /dev/dri/card* 2>/dev/null | wc -l)
    RENDERS=$(ls /dev/dri/renderD* 2>/dev/null | wc -l)
    pass "DRM devices: ${CARDS} card(s), ${RENDERS} render node(s)"
else
    fail "No /dev/dri — GPU driver not loaded"
fi

if [ $HAS_INTEL_GPU -eq 1 ]; then
    check_module i915
    # Check i915 firmware loaded
    if dmesg 2>/dev/null | grep -q 'i915.*firmware'; then
        pass "i915 firmware loaded"
    else
        warn "i915 firmware status unclear (dmesg may have rotated)"
    fi
fi

if [ $HAS_NVIDIA -eq 1 ]; then
    check_module nvidia
    check_module nvidia_modeset
    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi &>/dev/null; then
            GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader 2>/dev/null | head -1)
            DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
            pass "nvidia-smi OK: ${GPU_COUNT:-?} GPU(s), driver ${DRIVER_VER:-?}"
        else
            fail "nvidia-smi failed"
        fi
    else
        fail "nvidia-smi not found"
    fi
    # Check nouveau not loaded
    if lsmod | grep -qw nouveau; then
        fail "nouveau loaded alongside nvidia — blacklist nouveau"
    else
        pass "nouveau not loaded"
    fi
fi

echo ""

# ============================================================================
# 3. NETWORKING
# ============================================================================
echo "[3] Networking"

if [ $HAS_WIFI -eq 1 ]; then
    check_module "$WIFI_DRIVER"
    # Check interface exists
    WLAN=$(ip -o link show 2>/dev/null | grep -oE 'wl[a-z0-9]+' | head -1)
    if [ -n "$WLAN" ]; then
        pass "WiFi interface: $WLAN"
        # Check firmware loaded
        case "$WIFI_DRIVER" in
            iwlwifi)    dmesg 2>/dev/null | grep -q 'iwlwifi.*loaded firmware' && pass "iwlwifi firmware loaded" || warn "iwlwifi firmware status unclear" ;;
            mwifiex*)   dmesg 2>/dev/null | grep -q 'mwifiex.*FW.*active' && pass "mwifiex firmware loaded" || warn "mwifiex firmware status unclear" ;;
            brcmfmac)   dmesg 2>/dev/null | grep -q 'brcmfmac.*firmware' && pass "brcmfmac firmware loaded" || warn "brcmfmac firmware status unclear" ;;
        esac
    else
        fail "No WiFi interface found"
    fi
fi

# Check Ethernet
ETH=$(ip -o link show 2>/dev/null | grep -oE 'e[nt][a-z0-9]+' | head -1)
if [ -n "$ETH" ]; then
    pass "Ethernet interface: $ETH"
fi

# NetworkManager state
if command -v nmcli &>/dev/null; then
    NM_STATE=$(nmcli general status 2>/dev/null | tail -1 | awk '{print $1}')
    if [ "$NM_STATE" = "connected" ]; then
        pass "NetworkManager: connected"
    elif [ "$NM_STATE" = "connecting" ]; then
        warn "NetworkManager: connecting (not yet connected)"
    else
        warn "NetworkManager state: $NM_STATE"
    fi
fi

echo ""

# ============================================================================
# 4. AUDIO
# ============================================================================
echo "[4] Audio"

if command -v aplay &>/dev/null; then
    ACARDS=$(aplay -l 2>/dev/null | grep -c '^card' || true)
    pass "ALSA: $ACARDS sound card(s)"
else
    warn "aplay not found"
fi

if command -v pw-cli &>/dev/null; then
    pass "PipeWire installed"
else
    warn "PipeWire (pw-cli) not found"
fi

echo ""

# ============================================================================
# 5. STORAGE & SWAP
# ============================================================================
echo "[5] Storage & Swap"

# zram
if [ -e /dev/zram0 ]; then
    ZRAM_SIZE=$(cat /sys/block/zram0/disksize 2>/dev/null)
    ZRAM_GB=$((ZRAM_SIZE / 1073741824))
    pass "zram0: ${ZRAM_GB}GB"
else
    warn "No zram device — check zram-init service"
fi

# Swap
SWAP_TOTAL=$(free -m 2>/dev/null | awk '/Swap:/ {print $2}')
if [ "$SWAP_TOTAL" -gt 0 ] 2>/dev/null; then
    pass "Swap: ${SWAP_TOTAL}MB active"
else
    warn "No swap active"
fi

# Root filesystem
ROOT_FS=$(df -T / 2>/dev/null | awk 'NR==2 {print $2}')
ROOT_USE=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}')
pass "Root filesystem: $ROOT_FS ($ROOT_USE used)"

echo ""

# ============================================================================
# 6. SERVICES
# ============================================================================
echo "[6] Services"

# Core services all machines need
for svc in dbus NetworkManager display-manager elogind; do
    check_service "$svc"
done

# Conditional services
[ $IS_LAPTOP -eq 1 ] && check_service acpid
[ $HAS_BLUETOOTH -eq 1 ] && check_service bluetooth

# Machine-specific
case "$MACHINE" in
    xps-9510)       check_service thermald; check_service tlp ;;
    mbp-2015)       check_service mbpfan; check_service sshd ;;
    surface-pro-6)  check_service sshd ;;
    precision-t5810) check_service sshd ;;
    asrock-b550) check_service sshd ;;
    beelink-minis) check_service sshd; check_service thermald ;;
esac

echo ""

# ============================================================================
# 7. USER & PERMISSIONS
# ============================================================================
echo "[7] User & Permissions"

# Find the primary non-root user
PRIMARY_USER=$(grep -E '^[^:]+:[^:]+:1000:' /etc/passwd 2>/dev/null | cut -d: -f1)
if [ -n "$PRIMARY_USER" ]; then
    pass "Primary user: $PRIMARY_USER (UID 1000)"
    # Check groups
    USER_GROUPS=$(id -nG "$PRIMARY_USER" 2>/dev/null)
    for grp in wheel audio video input plugdev; do
        if echo "$USER_GROUPS" | grep -qw "$grp"; then
            pass "$PRIMARY_USER in group: $grp"
        else
            warn "$PRIMARY_USER not in group: $grp"
        fi
    done
    # Check sudo
    if grep -qE '^%wheel' /etc/sudoers 2>/dev/null; then
        pass "wheel group has sudo access"
    else
        fail "wheel group not in sudoers"
    fi
    # Home directory
    if [ -d "/home/$PRIMARY_USER" ]; then
        OWNER=$(stat -c '%U' "/home/$PRIMARY_USER" 2>/dev/null)
        [ "$OWNER" = "$PRIMARY_USER" ] && pass "/home/$PRIMARY_USER owned by $PRIMARY_USER" || fail "/home/$PRIMARY_USER owned by $OWNER"
    fi
else
    warn "No UID 1000 user found"
fi

echo ""

# ============================================================================
# 8. MACHINE-SPECIFIC CHECKS
# ============================================================================
echo "[8] Machine-Specific ($MACHINE)"

case "$MACHINE" in
    surface-pro-6)
        # Surface Aggregator Module
        check_module surface_aggregator
        # Battery via SAM
        if [ $HAS_BATTERY -eq 1 ]; then
            pass "Battery detected via power_supply"
        else
            warn "No battery detected — check SURFACE_BATTERY module"
        fi
        # WiFi resume hook
        check_file /etc/elogind/system-sleep/wifi-reload.sh "WiFi resume hook"
        # HiDPI
        if ls /home/*/.Xresources &>/dev/null; then
            pass "Xresources (HiDPI)"
        else
            warn "No .Xresources found for HiDPI"
        fi
        ;;
    mbp-2015)
        # Apple SMC
        check_module applesmc
        # Fan control
        if [ -f /etc/mbpfan.conf ]; then
            pass "mbpfan.conf exists"
        else
            fail "mbpfan.conf missing"
        fi
        # SMC sensors
        SENSORS=$(ls /sys/devices/platform/applesmc.768/temp*_input 2>/dev/null | wc -l)
        if [ "$SENSORS" -gt 0 ]; then
            pass "applesmc: $SENSORS temperature sensors"
        else
            warn "applesmc sensors not found"
        fi
        ;;
    xps-9510)
        # NVIDIA + Intel hybrid
        if [ $HAS_NVIDIA -eq 1 ] && [ $HAS_INTEL_GPU -eq 1 ]; then
            pass "Hybrid GPU: Intel + NVIDIA"
        fi
        check_file /usr/local/bin/prime-run "PRIME run script"
        # TLP
        if command -v tlp-stat &>/dev/null; then
            pass "TLP installed"
        else
            warn "TLP not found"
        fi
        ;;
    precision-t5810)
        # ECC memory
        if [ -d /sys/devices/system/edac/mc ]; then
            MC_COUNT=$(ls -d /sys/devices/system/edac/mc/mc* 2>/dev/null | wc -l)
            pass "EDAC: $MC_COUNT memory controller(s)"
            # Check for uncorrectable errors
            UE=$(cat /sys/devices/system/edac/mc/mc*/ue_count 2>/dev/null | awk '{s+=$1}END{print s+0}')
            CE=$(cat /sys/devices/system/edac/mc/mc*/ce_count 2>/dev/null | awk '{s+=$1}END{print s+0}')
            pass "ECC errors: $CE correctable, $UE uncorrectable"
            [ "$UE" -gt 0 ] && fail "UNCORRECTABLE ECC ERRORS DETECTED — replace faulty DIMM"
        else
            warn "EDAC not available"
        fi
        ;;
    asrock-b550)
        # AMD thermal — k10temp
        check_module k10temp
        # AMD CCP/PSP
        check_module ccp
        # AMD pinctrl
        check_module pinctrl_amd
        # zram
        if [ -b /dev/zram0 ] && [ "$(cat /sys/block/zram0/disksize 2>/dev/null)" -gt 0 ]; then
            ZRAM_SIZE=$(($(cat /sys/block/zram0/disksize) / 1024 / 1024 / 1024))
            pass "zram0: ${ZRAM_SIZE}GB"
        else
            warn "zram0 not active — check zram-init config"
        fi
        ;;
    beelink-minis)
        # Intel Jasper Lake iGPU
        check_module i915
        # Realtek Ethernet (primary network)
        check_module r8169
        ETH_LINK=$(ip -o link show 2>/dev/null | grep -oE 'e[nt][a-z0-9]+' | head -1)
        if [ -n "$ETH_LINK" ]; then
            CARRIER=$(cat /sys/class/net/"$ETH_LINK"/carrier 2>/dev/null)
            [ "$CARRIER" = "1" ] && pass "Ethernet $ETH_LINK: link up" || warn "Ethernet $ETH_LINK: no carrier"
        fi
        # AHCI/SATA storage (no NVMe on this board)
        check_module ahci
        # Audio — HDA Intel Jasperlake
        check_module snd_hda_intel
        # zram
        if [ -b /dev/zram0 ] && [ "$(cat /sys/block/zram0/disksize 2>/dev/null)" -gt 0 ]; then
            ZRAM_SIZE=$(($(cat /sys/block/zram0/disksize) / 1024 / 1024 / 1024))
            pass "zram0: ${ZRAM_SIZE}GB"
        else
            warn "zram0 not active — check zram-init config"
        fi
        ;;
    *)
        echo "  No machine-specific checks for: $MACHINE"
        ;;
esac

echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo "=========================================="
echo "  RESULTS: $FAIL failure(s), $WARN warning(s)"
echo "=========================================="
if [ $FAIL -eq 0 ]; then
    echo "  System looks good!"
else
    echo "  Review failures above before relying on this system."
fi

exit $FAIL
