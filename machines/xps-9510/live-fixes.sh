#!/bin/bash
# ============================================================================
# live-fixes.sh - Apply optimizations to LIVE XPS 9510 Gentoo system
# ============================================================================
# Run this on the live XPS 9510 to fix the CPU_FLAGS_X86 bug, enable ccache,
# add portage tmpfs, and other optimizations.
#
# USAGE: sudo bash live-fixes.sh
#
# After running: emerge -avuDN @world (rebuilds everything with correct flags)
# ============================================================================

set -euo pipefail

echo "=== XPS 9510 Live System Fixes ==="
echo ""

# Must be root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root (sudo bash live-fixes.sh)"
    exit 1
fi

# ============================================================================
# FIX 1: CPU_FLAGS_X86 (CRITICAL)
# ============================================================================
echo "[FIX 1] CPU_FLAGS_X86 — detecting correct flags..."

if ! command -v cpuid2cpuflags &>/dev/null; then
    echo "  Installing cpuid2cpuflags..."
    emerge -av1 app-portage/cpuid2cpuflags
fi

CORRECT_FLAGS=$(cpuid2cpuflags | sed 's/^CPU_FLAGS_X86: //')
echo "  Detected: CPU_FLAGS_X86=\"$CORRECT_FLAGS\""

CURRENT_FLAGS=$(grep '^CPU_FLAGS_X86=' /etc/portage/make.conf 2>/dev/null || echo "NOT SET")
echo "  Current:  $CURRENT_FLAGS"

if grep -q '^CPU_FLAGS_X86=' /etc/portage/make.conf; then
    sed -i "s/^CPU_FLAGS_X86=.*/CPU_FLAGS_X86=\"$CORRECT_FLAGS\"/" /etc/portage/make.conf
    echo "  [OK] Updated CPU_FLAGS_X86 in make.conf"
else
    echo "" >> /etc/portage/make.conf
    echo "CPU_FLAGS_X86=\"$CORRECT_FLAGS\"" >> /etc/portage/make.conf
    echo "  [OK] Added CPU_FLAGS_X86 to make.conf"
fi
echo ""

# ============================================================================
# FIX 2: INPUT_DEVICES
# ============================================================================
echo "[FIX 2] INPUT_DEVICES..."

if grep -q '^INPUT_DEVICES=' /etc/portage/make.conf; then
    echo "  Already set."
else
    echo 'INPUT_DEVICES="libinput"' >> /etc/portage/make.conf
    echo "  [OK] Added INPUT_DEVICES=\"libinput\" to make.conf"
fi
echo ""

# ============================================================================
# FIX 3: ccache
# ============================================================================
echo "[FIX 3] ccache..."

if ! command -v ccache &>/dev/null; then
    echo "  Installing ccache..."
    emerge -av1 dev-util/ccache
fi

# Create ccache directory on /data
mkdir -p /data/build-cache/ccache
chown root:portage /data/build-cache/ccache
chmod 2775 /data/build-cache/ccache
echo "  [OK] ccache directory: /data/build-cache/ccache"

# Enable in make.conf
if grep -q '^FEATURES=.*ccache' /etc/portage/make.conf; then
    echo "  FEATURES already includes ccache."
elif grep -q '^FEATURES=' /etc/portage/make.conf; then
    sed -i 's/^FEATURES="\(.*\)"/FEATURES="\1 ccache"/' /etc/portage/make.conf
    echo "  [OK] Added ccache to FEATURES"
else
    echo 'FEATURES="parallel-fetch candy ccache"' >> /etc/portage/make.conf
    echo "  [OK] Added FEATURES with ccache"
fi

if ! grep -q '^CCACHE_DIR=' /etc/portage/make.conf; then
    echo 'CCACHE_DIR="/data/build-cache/ccache"' >> /etc/portage/make.conf
    echo 'CCACHE_SIZE="10G"' >> /etc/portage/make.conf
    echo "  [OK] Added CCACHE_DIR and CCACHE_SIZE"
fi
echo ""

# ============================================================================
# FIX 4: package.env + portage disk fallback
# ============================================================================
echo "[FIX 4] Large package disk fallback..."

mkdir -p /etc/portage/env
if [[ ! -f /etc/portage/env/notmpfs.conf ]]; then
    echo 'PORTAGE_TMPDIR="/var/tmp/portage-disk"' > /etc/portage/env/notmpfs.conf
    echo "  [OK] Created /etc/portage/env/notmpfs.conf"
fi

if [[ ! -f /etc/portage/package.env ]]; then
    cat > /etc/portage/package.env << 'EOF'
# Packages that exceed tmpfs - redirect to disk
www-client/chromium         notmpfs.conf
www-client/firefox          notmpfs.conf
sys-devel/llvm              notmpfs.conf
dev-lang/rust               notmpfs.conf
dev-qt/qtwebengine          notmpfs.conf
sys-devel/gcc               notmpfs.conf
EOF
    echo "  [OK] Created /etc/portage/package.env"
else
    echo "  package.env already exists."
fi

mkdir -p /var/tmp/portage-disk
chown portage:portage /var/tmp/portage-disk
echo "  [OK] /var/tmp/portage-disk created"
echo ""

# ============================================================================
# FIX 5: Portage tmpfs mount
# ============================================================================
echo "[FIX 5] Portage tmpfs..."

if grep -q '/var/tmp/portage.*tmpfs' /etc/fstab; then
    echo "  Already in fstab."
else
    echo 'tmpfs  /var/tmp/portage  tmpfs  size=24G,uid=portage,gid=portage,mode=775,nosuid,noatime,nodev  0  0' >> /etc/fstab
    echo "  [OK] Added portage tmpfs to fstab (24G)"
fi

if ! mountpoint -q /var/tmp/portage 2>/dev/null; then
    mount /var/tmp/portage
    echo "  [OK] Mounted /var/tmp/portage"
else
    echo "  Already mounted."
fi
echo ""

# ============================================================================
# FIX 6: Replace neofetch with fastfetch
# ============================================================================
echo "[FIX 6] Replace neofetch with fastfetch..."

if command -v neofetch &>/dev/null; then
    emerge --deselect app-misc/neofetch
    emerge -av1 app-misc/fastfetch
    emerge --depclean app-misc/neofetch 2>/dev/null || true
    echo "  [OK] Replaced neofetch with fastfetch"
elif ! command -v fastfetch &>/dev/null; then
    emerge -av1 app-misc/fastfetch
    echo "  [OK] Installed fastfetch"
else
    echo "  fastfetch already installed."
fi
echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo "=========================================="
echo "=== All fixes applied ==="
echo "=========================================="
echo ""
echo "Verify:"
echo "  emerge --info | grep CPU_FLAGS_X86"
echo "  ccache -s"
echo "  mount | grep portage"
echo "  cat /etc/portage/package.env"
echo ""
echo "NEXT STEP — rebuild everything with correct flags:"
echo "  emerge -avuDN @world"
echo ""
echo "This is the big one. It will rebuild every package with proper"
echo "AVX-512, AES-NI, FMA3, SHA hardware acceleration."
echo "Expect 2-4 hours depending on installed packages."
