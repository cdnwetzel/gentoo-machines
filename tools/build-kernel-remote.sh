#!/bin/bash
#
# Build a Gentoo kernel on a build host, then deploy to the target machine.
#
# Usage:
#   ./build-kernel-remote.sh <target> pull     - Fetch source + config from target
#   ./build-kernel-remote.sh <target> build    - Build kernel + modules
#   ./build-kernel-remote.sh <target> deploy   - Push built kernel + modules to target
#   ./build-kernel-remote.sh <target> all      - Do all three steps
#
# Targets are defined below in the TARGETS associative array.
# After deploy, SSH to the target and run the install steps printed at the end.
#

set -euo pipefail

# --- Target Definitions ---
# Format: TARGETS[name]="user@host"
declare -A TARGETS=(
    [xps-9315]="user@xps-9315.local"
    [nuc11]="user@nuc11.local"
)

# Kernel version (update as needed)
KVER="6.12.58-gentoo"
BUILD_DIR="/tmp/kernel-build"
JOBS=$(nproc)

# --- Helpers ---
info()  { echo -e "\033[1;32m>>>\033[0m $*"; }
warn()  { echo -e "\033[1;33m>>>\033[0m $*"; }
error() { echo -e "\033[1;31m>>>\033[0m $*" >&2; exit 1; }

usage() {
    echo "Usage: $0 <target> {pull|build|deploy|all}"
    echo ""
    echo "Targets:"
    for t in "${!TARGETS[@]}"; do
        echo "  ${t}  (${TARGETS[$t]})"
    done
    echo ""
    echo "Actions:"
    echo "  pull    - Fetch kernel source + .config from target"
    echo "  build   - Build kernel + modules on this host"
    echo "  deploy  - Push built artifacts to target (/tmp)"
    echo "  all     - pull + build + deploy"
    exit 1
}

check_deps() {
    local missing=()
    for cmd in gcc make bc flex bison perl openssl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing build dependencies: ${missing[*]}"
    fi
    # Check libelf
    if ! pkg-config --exists libelf 2>/dev/null; then
        error "Missing libelf-devel (elfutils-libelf-devel)"
    fi
    info "All build dependencies satisfied"
    info "Host GCC: $(gcc --version | head -1)"
    info "Using -j${JOBS}"
}

do_pull() {
    info "Pulling kernel source and .config from ${TARGET_NAME} (${TARGET_HOST})..."

    mkdir -p "${SRC_DIR}"

    # rsync the clean source tree (exclude any prior build artifacts)
    info "Syncing kernel source (this may take a minute on first run)..."
    rsync -az --delete \
        --exclude='.tmp_*' \
        --exclude='*.o' \
        --exclude='*.ko' \
        --exclude='*.cmd' \
        --exclude='modules.order' \
        --exclude='modules.builtin*' \
        --exclude='vmlinux' \
        --exclude='vmlinuz' \
        --exclude='bzImage' \
        --exclude='System.map' \
        --exclude='.config.old' \
        "${TARGET_HOST}:/usr/src/linux-${KVER}/" "${SRC_DIR}/"

    # Grab the running .config
    info "Fetching running kernel .config..."
    scp "${TARGET_HOST}:/usr/src/linux/.config" "${SRC_DIR}/.config"

    info "Source tree ready at ${SRC_DIR}"
    info "Source size: $(du -sh "${SRC_DIR}" | cut -f1)"
}

do_build() {
    [[ -d "${SRC_DIR}" ]] || error "Source dir not found. Run: $0 ${TARGET_NAME} pull"
    [[ -f "${SRC_DIR}/.config" ]] || error "No .config found. Run: $0 ${TARGET_NAME} pull"

    check_deps

    cd "${SRC_DIR}"

    # Ensure config is up to date for this compiler
    info "Running make olddefconfig..."
    make olddefconfig

    info "Building kernel and modules with -j${JOBS}..."
    time make -j"${JOBS}"

    info "Build complete!"
    info "Kernel: $(ls -lh arch/x86/boot/bzImage)"

    # Show vermagic so user can verify
    local vermagic
    vermagic=$(cat include/config/kernel.release 2>/dev/null || echo "unknown")
    info "Kernel release: ${vermagic}"
}

do_deploy() {
    [[ -f "${SRC_DIR}/arch/x86/boot/bzImage" ]] || error "No bzImage found. Run: $0 ${TARGET_NAME} build"

    cd "${SRC_DIR}"

    local krelease
    krelease=$(cat include/config/kernel.release)

    info "Installing modules to staging directory..."
    local mod_staging="${BUILD_DIR}/${TARGET_NAME}-modules-${krelease}"
    rm -rf "${mod_staging}"
    make INSTALL_MOD_PATH="${mod_staging}" modules_install

    info "Deploying to ${TARGET_NAME} (${TARGET_HOST})..."

    # Push bzImage
    info "Pushing kernel image..."
    scp arch/x86/boot/bzImage "${TARGET_HOST}:/tmp/vmlinuz-${krelease}"

    # Push System.map
    scp System.map "${TARGET_HOST}:/tmp/System.map-${krelease}"

    # Push .config for reference
    scp .config "${TARGET_HOST}:/tmp/config-${krelease}"

    # Push modules
    info "Pushing modules..."
    rsync -az "${mod_staging}/lib/modules/${krelease}/" \
        "${TARGET_HOST}:/tmp/modules-${krelease}/"

    info ""
    info "=== Files staged on ${TARGET_NAME} in /tmp ==="
    info "  /tmp/vmlinuz-${krelease}"
    info "  /tmp/System.map-${krelease}"
    info "  /tmp/config-${krelease}"
    info "  /tmp/modules-${krelease}/"
    info ""
    info "=== SSH to ${TARGET_NAME} and run as root ==="
    cat <<INSTALL

    # Install kernel
    cp /tmp/vmlinuz-${krelease} /boot/vmlinuz-${krelease}
    cp /tmp/System.map-${krelease} /boot/System.map-${krelease}
    cp /tmp/config-${krelease} /boot/config-${krelease}

    # Install modules
    rm -rf /lib/modules/${krelease}
    cp -a /tmp/modules-${krelease} /lib/modules/${krelease}
    depmod ${krelease}

    # Rebuild initramfs
    dracut --force /boot/initramfs-${krelease}.img ${krelease}

    # Update GRUB (if using GRUB)
    grub-mkconfig -o /boot/grub/grub.cfg

    # Clean up
    rm -f /tmp/vmlinuz-${krelease} /tmp/System.map-${krelease} /tmp/config-${krelease}
    rm -rf /tmp/modules-${krelease}

INSTALL
}

# --- Main ---
[[ $# -ge 2 ]] || usage

TARGET_NAME="${1}"
ACTION="${2}"

# Validate target
if [[ -z "${TARGETS[$TARGET_NAME]+x}" ]]; then
    error "Unknown target '${TARGET_NAME}'. Valid targets: ${!TARGETS[*]}"
fi

TARGET_HOST="${TARGETS[$TARGET_NAME]}"
SRC_DIR="${BUILD_DIR}/${TARGET_NAME}-linux-${KVER}"

case "${ACTION}" in
    pull)   do_pull ;;
    build)  do_build ;;
    deploy) do_deploy ;;
    all)
        do_pull
        do_build
        do_deploy
        ;;
    *)  usage ;;
esac
