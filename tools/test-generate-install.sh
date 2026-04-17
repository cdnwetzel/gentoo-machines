#!/bin/bash
# ============================================================================
# test-generate-install.sh — regression tests for generate-install.sh
# ============================================================================
# Runs the generator against each fixture under tools/test-fixtures/ and
# asserts that feature gates fire correctly + all outputs pass bash syntax.
#
# Fixtures are synthetic harvests representing distinct feature combinations:
#   intel-sata-desktop        — Intel iGPU + SATA + BT Intel + no NVIDIA
#   amd-nvme-nvidia-desktop   — AMD + NVMe+SATA + NVIDIA Ampere + BT Intel
#   apple-broadwell-laptop    — Intel iGPU + SATA + brcmfmac WiFi + Apple
#
# Each fixture has an associated `assert_*` function that greps the generated
# output for expected presence/absence patterns. Non-zero exit on any failure.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
GENERATOR="$SCRIPT_DIR/generate-install.sh"
FIXTURES="$SCRIPT_DIR/test-fixtures"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK" "$REPO_DIR/machines/_test-"*' EXIT

PASS=0
FAIL=0

green() { echo -e "\033[1;32m$*\033[0m"; }
red()   { echo -e "\033[1;31m$*\033[0m"; }

# assert_grep <label> <pattern> <file> — fail if pattern not found
assert_grep() {
    local label="$1" pattern="$2" file="$3"
    if grep -qE "$pattern" "$file"; then
        green "  [PASS] $label"
        PASS=$((PASS+1))
    else
        red "  [FAIL] $label — pattern '$pattern' not in $(basename "$file")"
        FAIL=$((FAIL+1))
    fi
}

# assert_no_grep <label> <pattern> <file> — fail if pattern IS found
assert_no_grep() {
    local label="$1" pattern="$2" file="$3"
    if grep -qE "$pattern" "$file"; then
        red "  [FAIL] $label — unexpected '$pattern' in $(basename "$file")"
        FAIL=$((FAIL+1))
    else
        green "  [PASS] $label"
        PASS=$((PASS+1))
    fi
}

# assert_syntax <file> — fail if bash -n fails
assert_syntax() {
    local file="$1"
    if bash -n "$file" 2>/dev/null; then
        green "  [PASS] syntax: $(basename "$file")"
        PASS=$((PASS+1))
    else
        red "  [FAIL] syntax: $(basename "$file")"
        bash -n "$file" || true
        FAIL=$((FAIL+1))
    fi
}

# run_case <fixture-name> <base-machine> <assert-fn>
run_case() {
    local fixture="$1" base="$2" assert_fn="$3"
    local test_name="_test-$fixture"
    local out_dir="$REPO_DIR/machines/$test_name"
    local harvest_dir="$WORK/$fixture"

    echo ""
    echo "=== Fixture: $fixture (base=$base) ==="

    mkdir -p "$harvest_dir"
    cp "$FIXTURES/$fixture.harvest" "$harvest_dir/hardware_inventory.log"

    if ! "$GENERATOR" "$test_name" "$base" "$harvest_dir" >/dev/null 2>&1; then
        red "  [FAIL] generator exited non-zero"
        FAIL=$((FAIL+1))
        return
    fi

    assert_syntax "$out_dir/gentoo_install_part1.sh"
    assert_syntax "$out_dir/gentoo_install_part2.sh"
    assert_syntax "$out_dir/gentoo_install_part3_chroot.sh"

    "$assert_fn" "$out_dir"
}

# ============================================================================
# Per-fixture assertions
# ============================================================================

assert_intel_sata_desktop() {
    local d="$1"
    local p1="$d/gentoo_install_part1.sh"
    local p3="$d/gentoo_install_part3_chroot.sh"

    assert_grep    'part1 targets /dev/sda'                '^TARGET="/dev/sda"'           "$p1"
    assert_grep    'part1 SATA prefix (no p suffix)'       'PART_PREFIX="\$\{TARGET\}"$' "$p1"
    assert_grep    'disks detected comment'                '#   SATA: /dev/sda'           "$p1"
    assert_grep    'phase 2 includes intel-microcode'      'sys-firmware/intel-microcode' "$p3"
    assert_no_grep 'no NVIDIA modprobe block'              'nvidia-drm modeset'           "$p3"
    assert_grep    'phase 8 enables bluetooth (BT=intel)'  'rc-update add bluetooth'      "$p3"
    assert_grep    'phase 8 enables thermald (Intel CPU)'  'rc-update add thermald'       "$p3"
    assert_no_grep 'phase 8 does NOT enable tlp (desktop)' 'rc-update add tlp'            "$p3"
    assert_grep    'desktop always-on drop-in'             'always-on.conf'               "$p3"
    assert_grep    'cronie service (baseline)'             'rc-update add cronie'         "$p3"
}

assert_amd_nvme_nvidia_desktop() {
    local d="$1"
    local p1="$d/gentoo_install_part1.sh"
    local p2="$d/gentoo_install_part2.sh"
    local p3="$d/gentoo_install_part3_chroot.sh"

    assert_grep    'part1 targets /dev/nvme0n1'            '^TARGET="/dev/nvme0n1"'       "$p1"
    assert_grep    'part1 NVMe prefix (p suffix)'          'PART_PREFIX="\$\{TARGET\}p"$' "$p1"
    assert_grep    'dual-storage warning'                  'Both NVMe and SATA'           "$p1"
    assert_grep    'NVMe disk listed'                      '#   NVMe: /dev/nvme0n1'       "$p1"
    assert_grep    'SATA disk listed'                      '#   SATA: /dev/sda'           "$p1"
    assert_grep    'part2 uses PART_PREFIX for UUID'       'blkid -s UUID -o value "\$\{PART_PREFIX\}1"' "$p2"
    assert_grep    'NVIDIA modprobe block'                 'nvidia-drm modeset=1'         "$p3"
    assert_grep    'nouveau blacklist'                     'blacklist nouveau'            "$p3"
    assert_no_grep 'no intel-microcode on AMD'             'sys-firmware/intel-microcode' "$p3"
    assert_grep    'NVIDIA postinst hook copy'             '99-module-rebuild.install'    "$p3"
    assert_no_grep 'no thermald on AMD'                    'rc-update add thermald'       "$p3"
    assert_grep    'cronie service (baseline)'             'rc-update add cronie'         "$p3"
    assert_grep    'desktop always-on drop-in'             'always-on.conf'               "$p3"
}

assert_apple_broadwell_laptop() {
    local d="$1"
    local p2="$d/gentoo_install_part2.sh"
    local p3="$d/gentoo_install_part3_chroot.sh"

    assert_grep    'part2 copies mbpfan.conf'              'mbpfan.conf'                  "$p2"
    assert_grep    'part2 copies wifi_firmware_fix.sh'     'wifi_firmware_fix.sh'         "$p2"
    assert_grep    'laptop-specific: tlp.conf copy'        'tlp.conf'                     "$p2"
    assert_grep    'phase 8 enables mbpfan (Apple)'        'rc-update add mbpfan'         "$p3"
    assert_grep    'phase 8 enables tlp (laptop)'          'rc-update add tlp'            "$p3"
    assert_grep    'phase 8 enables thermald (Intel)'      'rc-update add thermald'       "$p3"
    assert_no_grep 'no NVIDIA modprobe block'              'nvidia-drm modeset'           "$p3"
    assert_no_grep 'no desktop always-on (laptop)'         'always-on.conf'               "$p3"
    assert_grep    'Apple hardware section'                'Apple-specific'               "$p3"
    assert_grep    'brcmfmac firmware check'               'brcmfmac'                     "$p3"
}

# ============================================================================
# Drive
# ============================================================================

echo "=========================================="
echo "=== generate-install.sh regression tests ==="
echo "=========================================="

run_case "intel-sata-desktop"        "beelink-minis"     assert_intel_sata_desktop
run_case "amd-nvme-nvidia-desktop"   "asrock-b550"       assert_amd_nvme_nvidia_desktop
run_case "apple-broadwell-laptop"    "mbp-2015"          assert_apple_broadwell_laptop

echo ""
echo "=========================================="
if [[ $FAIL -eq 0 ]]; then
    green "=== ALL TESTS PASSED ($PASS checks) ==="
    exit 0
else
    red "=== $FAIL FAILURES out of $((PASS+FAIL)) checks ==="
    exit 1
fi
