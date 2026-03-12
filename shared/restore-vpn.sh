#!/bin/bash
# Restore SSTP VPN connection via NetworkManager
# Requires: net-vpn/networkmanager-sstp, net-misc/sstp-client, net-misc/ppp
#
# Duo MFA proxy requires PAP only — all other auth methods refused.
# Password is not stored; NetworkManager prompts on each connect.
#
# Usage (run as normal user, not root):
#   bash shared/restore-vpn.sh          # create/update "PS VPN" connection
#   nmcli connection up "PS VPN"        # connect (prompts for password + Duo push)

set -euo pipefail

VPN_NAME="PS VPN"
VPN_GATEWAY="remote.thepslawfirm.com"
VPN_USER="cwe"
VPN_DOMAIN="splawoffice.local"

# Check dependencies
for cmd in nmcli sstpc pppd; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd not found. Install the required packages first."
        exit 1
    fi
done

# Check NetworkManager SSTP plugin
if ! find /usr/lib*/NetworkManager/ -name 'libnm-vpn-plugin-sstp*' 2>/dev/null | grep -q .; then
    echo "ERROR: NetworkManager SSTP plugin not found."
    echo "       emerge net-vpn/networkmanager-sstp"
    exit 1
fi

# Delete existing connection if present
if nmcli connection show "$VPN_NAME" &>/dev/null; then
    echo "Removing existing '$VPN_NAME' connection..."
    nmcli connection delete "$VPN_NAME"
fi

echo "Creating '$VPN_NAME' SSTP VPN connection..."

nmcli connection add \
    type vpn \
    con-name "$VPN_NAME" \
    vpn-type sstp \
    autoconnect no

nmcli connection modify "$VPN_NAME" \
    vpn.data "connection-type = password, domain = $VPN_DOMAIN, gateway = $VPN_GATEWAY, ignore-cert-warn = no, password-flags = 1, refuse-chap = yes, refuse-eap = yes, refuse-mschap = yes, refuse-mschapv2 = yes, refuse-pap = no, tls-ext = yes, tls-verify-key-usage = no, user = $VPN_USER"

echo ""
echo "Done. '$VPN_NAME' created."
echo "Connect with:  nmcli connection up '$VPN_NAME'"
echo ""
echo "Kernel requirements: CONFIG_PPP=y/m, CONFIG_PPP_MPPE=y/m, CONFIG_PPP_ASYNC=y/m"
echo "All production kernel configs already include these."
