#!/bin/bash
# ============================================================================
# update-system.sh — System Update Tool
# ============================================================================
# Single self-contained script for updating production Gentoo machines:
# portage sync, @world packages, kernel build/install, config file merging,
# post-reboot verification, and old kernel cleanup.
# Auto-detects which machine via hostname + DMI fallback.
#
# Subcommands:
#   full          - Prompted end-to-end workflow with resume (default when no args)
#                   fetch → check → prepare → build → install → world →
#                   config-update → reboot → verify → clean
#                   Prompts Y/n/skip before each phase. State saved to
#                   /var/lib/kernel-update/ so the workflow survives interruption
#                   and reboot.
#   fetch         - Sync portage, install latest gentoo-sources, select new kernel,
#                   show news (requires root)
#   world         - Update @world + preserved-rebuild + depclean (requires root)
#   config-update - Merge updated config files (auto-accept new versions) (requires root)
#   check         - Pre-flight: versions, disk, NVIDIA compat, patches, config strategy,
#                   drift detection (does a fresh prepare actually change anything?)
#   prepare       - Backup .config, migrate config (copy or script), apply patches, lint
#   build         - make -j$(nproc) with timing
#   install       - modules_install + make install + NVIDIA rebuild + verify state
#   verify        - Post-reboot checks: dmesg, drivers, GPU, WiFi, zram, services
#   clean         - Remove old kernels, keeping 3 most recent (requires root)
#   all           - prepare + build + install (not verify or clean — requires reboot first)
#
# Flags:
#   --dry-run          Show what would happen without making changes
#   --machine <name>   Override auto-detection
#
# Config strategy:
#   Same-series (e.g., 6.18.12 → 6.18.16):
#     Copy running .config → kernel_config.sh → make olddefconfig
#   Cross-series (e.g., 6.12 → 6.18):
#     make defconfig → kernel_config.sh → make olddefconfig
#   kernel_config.sh is always applied (idempotent) to ensure machine-specific
#   settings are never lost — even if the base .config came from another machine.
#
# Usage:
#   sudo update-system.sh                  # full prompted workflow (default)
#   sudo update-system.sh full             # same thing, explicit
#   sudo update-system.sh --dry-run full   # preview all phases
#   update-system.sh --machine xps-9510 check
#   update-system.sh verify
#   sudo update-system.sh clean
# ============================================================================

set -euo pipefail

# --- Save original args (before shift) for possible re-exec ---
_ORIG_ARGS=("$@")

# --- Script location (for finding repo files) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- State directory ---
STATE_DIR="/var/lib/kernel-update"
HISTORY_DIR="${STATE_DIR}/history"
PENDING_FILE="${STATE_DIR}/pending-verify"

# --- Kernel source ---
KERNEL_SRC="/usr/src/linux"

# --- Flags ---
DRY_RUN=false
MACHINE_OVERRIDE=""

# --- State shared across phases (set by do_check, read by do_full) ---
# 0 = no rebuild needed (running kernel matches a fresh prepare)
# 1 = rebuild needed (default — safe assumption when undetermined)
REBUILD_NEEDED=1

# --- Colors ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
BOLD='\033[1m'
RESET='\033[0m'

# ============================================================================
# Machine Registry
# ============================================================================
# Format: hostname|dmi|gpu|patches (pipe-delimited fields)
declare -A MACHINES=(
    [xps-9510]="hostname=xps-9510|dmi=XPS 15 9510|gpu=nvidia|patches=intel_idle-add-tiger-lake"
    [mbp-2015]="hostname=gentoo-mbp|dmi=MacBookPro12,1|gpu=intel|patches="
    [surface-pro-6]="hostname=surface-pro-6|dmi=Surface Pro|gpu=intel|patches="
    [nuc11]="hostname=nuc11|dmi=NUC11TNBi5|gpu=intel|patches=intel_idle-add-tiger-lake"
    [precision-t5810]="hostname=precision-t5810|dmi=Precision Tower 5810|gpu=nvidia|patches="
    [asrock-b550]="hostname=asrock-b550|dmi=Asrock B550|gpu=nvidia|patches="
    [beelink-minis]="hostname=beelink-minis|dmi=MINI S|gpu=intel|patches="
    [optiplex-3090]="hostname=optiplex-3090|dmi=OptiPlex 3090|gpu=nvidia|patches="
)

# ============================================================================
# Patch Registry
# ============================================================================
# Format: file|min_version|max_version|machines (pipe-delimited)
# Version range is inclusive: patch applies when min <= target <= max
declare -A PATCH_REGISTRY=(
    [intel_idle-add-tiger-lake]="patches/intel_idle-add-tiger-lake.patch|6.12|6.99|xps-9510,nuc11"
)

# ============================================================================
# Portage Workarounds Registry
# ============================================================================
# Temporary CFLAGS/env workarounds for packages that fail to build.
# These install an env file + package.env entry, and are auto-removed
# when the fixed version is available.
#
# Format: env_file|package_atom|max_version (pipe-delimited)
#   env_file:     source file in shared/ (repo-relative)
#   package_atom: category/package for package.env
#   max_version:  remove workaround when installed version > this
declare -A PORTAGE_WORKAROUNDS=(
    # Add entries as: [name]="repo_file|package_atom|max_version"
)

# ============================================================================
# Helpers
# ============================================================================
info()  { echo -e "${GREEN}>>>${RESET} $*"; }
warn()  { echo -e "${YELLOW}>>>${RESET} $*"; }
error() { echo -e "${RED}>>>${RESET} $*" >&2; exit 1; }
header() { echo -e "\n${BLUE}=== $* ===${RESET}"; }

# Ensure /boot/efi is mounted (needed by linux-firmware, installkernel, grub)
ensure_boot_efi_mounted() {
    if [[ -d /boot/efi ]] && ! mountpoint -q /boot/efi 2>/dev/null; then
        if grep -q '/boot/efi' /etc/fstab 2>/dev/null; then
            if ! $DRY_RUN; then
                mount /boot/efi && info "Mounted /boot/efi" || warn "/boot/efi mount failed — check fstab"
            else
                info "[dry-run] Would mount /boot/efi"
            fi
        fi
    fi
}

# Get a field from a machine registry entry
# Usage: get_machine_field xps-9510 gpu
get_machine_field() {
    local machine="$1" field="$2"
    local entry="${MACHINES[$machine]:-}"
    [[ -z "$entry" ]] && return 1
    echo "$entry" | tr '|' '\n' | grep "^${field}=" | cut -d= -f2-
}

# Parse kernel version from a Makefile
# Returns: major.minor.sublevel
parse_makefile_version() {
    local makefile="$1"
    local major minor sublevel
    major=$(grep '^VERSION' "$makefile" | head -1 | awk '{print $3}')
    minor=$(grep '^PATCHLEVEL' "$makefile" | head -1 | awk '{print $3}')
    sublevel=$(grep '^SUBLEVEL' "$makefile" | head -1 | awk '{print $3}')
    echo "${major}.${minor}.${sublevel}"
}

# Compare version: returns "same-series" or "cross-series"
classify_update() {
    local running="$1" target="$2"
    local run_major run_minor tgt_major tgt_minor
    run_major=$(echo "$running" | cut -d. -f1)
    run_minor=$(echo "$running" | cut -d. -f2)
    tgt_major=$(echo "$target" | cut -d. -f1)
    tgt_minor=$(echo "$target" | cut -d. -f2)

    if [[ "$run_major" == "$tgt_major" && "$run_minor" == "$tgt_minor" ]]; then
        echo "same-series"
    else
        echo "cross-series"
    fi
}

# Version comparison: returns 0 if $1 >= $2
version_ge() {
    local v1="$1" v2="$2"
    local v1_major v1_minor v2_major v2_minor
    v1_major=$(echo "$v1" | cut -d. -f1)
    v1_minor=$(echo "$v1" | cut -d. -f2)
    v2_major=$(echo "$v2" | cut -d. -f1)
    v2_minor=$(echo "$v2" | cut -d. -f2)
    if (( v1_major > v2_major )); then return 0; fi
    if (( v1_major == v2_major && v1_minor >= v2_minor )); then return 0; fi
    return 1
}

# Version comparison: returns 0 if $1 <= $2
version_le() {
    version_ge "$2" "$1"
}

get_running_version() {
    uname -r | sed 's/-gentoo.*//'
}

get_running_release() {
    uname -r
}

get_target_version() {
    if [[ ! -f "${KERNEL_SRC}/Makefile" ]]; then
        error "No kernel source at ${KERNEL_SRC} — is /usr/src/linux symlink set?"
    fi
    parse_makefile_version "${KERNEL_SRC}/Makefile"
}

get_target_release() {
    if [[ -f "${KERNEL_SRC}/include/config/kernel.release" ]]; then
        cat "${KERNEL_SRC}/include/config/kernel.release"
    else
        echo "$(get_target_version)-gentoo"
    fi
}

# ============================================================================
# Portage Workaround Sync
# ============================================================================
# Compares installed package versions against PORTAGE_WORKAROUNDS registry.
# Installs workarounds for affected versions, removes them when fixed.
sync_portage_workarounds() {
    local changed=false

    for name in "${!PORTAGE_WORKAROUNDS[@]}"; do
        local entry="${PORTAGE_WORKAROUNDS[$name]}"
        local env_file pkg_atom max_ver
        IFS='|' read -r env_file pkg_atom max_ver <<< "$entry"

        local env_name
        env_name=$(basename "$env_file" | sed 's/^portage_env_//')
        local dest="/etc/portage/env/${env_name}"
        local src="${REPO_DIR}/${env_file}"

        # Get installed version (e.g., "3.14.1")
        local installed_ver=""
        installed_ver=$(qatom -F '%{PV}' "$(qlist -Iv "$pkg_atom" 2>/dev/null | head -1)" 2>/dev/null || true)

        # Check if workaround is still needed
        # Needed if: package not installed (pre-install), or installed_ver <= max_ver
        local needed=true
        if [[ -n "$installed_ver" ]]; then
            # Not needed if installed version is newer than max_ver
            if [[ "$(printf '%s\n' "$installed_ver" "$max_ver" | sort -V | tail -1)" != "$max_ver" ]]; then
                needed=false
            fi
        fi

        if $needed; then
            # Install workaround if not present
            if [[ ! -f "$dest" ]]; then
                if [[ ! -f "$src" ]]; then
                    warn "Workaround source missing: ${src}"
                    continue
                fi
                if $DRY_RUN; then
                    info "[dry-run] Would install workaround: ${env_name} for ${pkg_atom} ${installed_ver}"
                else
                    cp "$src" "$dest"
                    info "Installed workaround: ${env_name}"
                    changed=true
                fi
            fi
            # Add package.env entry if not present
            if ! grep -q "^${pkg_atom}.*${env_name}" /etc/portage/package.env 2>/dev/null; then
                if $DRY_RUN; then
                    info "[dry-run] Would add package.env: ${pkg_atom} ${env_name}"
                else
                    echo "${pkg_atom} ${env_name}" >> /etc/portage/package.env
                    info "Added package.env entry: ${pkg_atom} ${env_name}"
                    changed=true
                fi
            fi
        else
            # Remove workaround if no longer needed
            if [[ -f "$dest" ]]; then
                if $DRY_RUN; then
                    info "[dry-run] Would remove obsolete workaround: ${env_name} (${pkg_atom} ${installed_ver:-not installed} > ${max_ver})"
                else
                    rm -f "$dest"
                    info "Removed obsolete workaround: ${env_name} (${pkg_atom} upgraded past ${max_ver})"
                    changed=true
                fi
            fi
            if grep -q "^${pkg_atom}.*${env_name}" /etc/portage/package.env 2>/dev/null; then
                if $DRY_RUN; then
                    info "[dry-run] Would remove package.env entry: ${pkg_atom} ${env_name}"
                else
                    sed -i "\|^${pkg_atom}.*${env_name}|d" /etc/portage/package.env
                    info "Removed package.env entry: ${pkg_atom} ${env_name}"
                    changed=true
                fi
            fi
        fi
    done

    if ! $changed; then
        info "Portage workarounds up to date"
    fi
}

# Report workaround status (for check subcommand, no root needed)
check_portage_workarounds() {
    header "Portage Workarounds"
    local any=false
    for name in "${!PORTAGE_WORKAROUNDS[@]}"; do
        any=true
        local entry="${PORTAGE_WORKAROUNDS[$name]}"
        local env_file pkg_atom max_ver
        IFS='|' read -r env_file pkg_atom max_ver <<< "$entry"

        local env_name
        env_name=$(basename "$env_file" | sed 's/^portage_env_//')
        local installed_ver=""
        installed_ver=$(qatom -F '%{PV}' "$(qlist -Iv "$pkg_atom" 2>/dev/null | head -1)" 2>/dev/null || true)

        local status
        if [[ -z "$installed_ver" ]]; then
            status="needed (${pkg_atom} not yet installed, workaround ready)"
        elif [[ "$(printf '%s\n' "$installed_ver" "$max_ver" | sort -V | tail -1)" != "$max_ver" ]]; then
            status="obsolete — ${pkg_atom}-${installed_ver} > ${max_ver}, safe to remove"
        else
            status="active — ${pkg_atom}-${installed_ver} <= ${max_ver}"
        fi

        local installed_icon="✗"
        [[ -f "/etc/portage/env/${env_name}" ]] && installed_icon="✓"

        info "${name}: ${status} [${installed_icon} installed]"
    done
    if ! $any; then
        info "No workarounds registered"
    fi
}

# ============================================================================
# Machine Detection
# ============================================================================
detect_machine() {
    # 1. Command-line override
    if [[ -n "$MACHINE_OVERRIDE" ]]; then
        # 'generic' is always allowed — backfilled into MACHINES after detect_machine returns
        if [[ "$MACHINE_OVERRIDE" != "generic" && -z "${MACHINES[$MACHINE_OVERRIDE]+x}" ]]; then
            error "Unknown machine '${MACHINE_OVERRIDE}'. Valid: ${!MACHINES[*]} (or 'generic' for an unsupported host)"
        fi
        echo "$MACHINE_OVERRIDE"
        return
    fi

    # 2. Hostname match
    local hostname
    hostname=$(hostname)
    for machine in "${!MACHINES[@]}"; do
        local expected
        expected=$(get_machine_field "$machine" hostname)
        if [[ "$hostname" == "$expected" ]]; then
            echo "$machine"
            return
        fi
    done

    # 3. DMI fallback
    if [[ -r /sys/class/dmi/id/product_name ]]; then
        local dmi
        dmi=$(cat /sys/class/dmi/id/product_name)
        for machine in "${!MACHINES[@]}"; do
            local expected
            expected=$(get_machine_field "$machine" dmi)
            if [[ "$dmi" == *"$expected"* ]]; then
                echo "$machine"
                return
            fi
        done
    fi

    # 4. No match — offer a generic fallback (interactive only).
    #    Read/write /dev/tty so this works inside $(detect_machine).
    local dmi_str=""
    [[ -r /sys/class/dmi/id/product_name ]] && dmi_str=$(cat /sys/class/dmi/id/product_name)
    if [[ -t 0 || -e /dev/tty ]]; then
        {
            echo
            echo "Cannot detect machine."
            echo "  Hostname:  ${hostname}"
            echo "  DMI:       ${dmi_str:-<unreadable>}"
            echo "  Inventory: ${!MACHINES[*]}"
            echo
            echo "Run with a 'generic' profile? This skips machine-specific tuning:"
            echo "  - no kernel_config.sh    → defconfig + olddefconfig only"
            echo "  - no patches"
            echo "  - GPU type auto-detected at runtime (lsmod)"
            echo "  - no machine-specific dmesg filters / WiFi check / platform header"
            echo
            echo "All other phases (emerge sync, @world, depclean, kernel build/install,"
            echo "verify, clean) run normally."
        } >/dev/tty
        local reply=""
        read -r -p "Continue with generic profile [y/N]? " reply </dev/tty || reply=""
        case "$reply" in
            [yY]|[yY][eE][sS])
                echo "generic"
                return
                ;;
        esac
    fi
    error "Cannot detect machine. Hostname='${hostname}'. Use --machine <name> to override or add a row to the MACHINES registry.\nValid machines: ${!MACHINES[*]}"
}

# ============================================================================
# fetch — Sync portage, install latest gentoo-sources, select new kernel
# ============================================================================
do_fetch() {
    [[ $EUID -eq 0 ]] || error "Fetch requires root"

    header "Portage Sync"
    if $DRY_RUN; then
        info "[dry-run] Would run: emerge --sync"
    else
        emerge --sync
    fi

    header "Install gentoo-sources"
    # Check what's available vs installed
    local available installed
    available=$(emerge -pv gentoo-sources 2>/dev/null | grep "gentoo-sources" | head -1 || true)
    info "Available: ${available:-unknown}"

    if $DRY_RUN; then
        info "[dry-run] Would run: emerge -v gentoo-sources"
        emerge -pv gentoo-sources 2>/dev/null || true
    else
        emerge -v gentoo-sources
    fi

    header "Select Kernel"
    # Find the newest kernel source directory
    local newest
    newest=$(printf '%s\n' /usr/src/linux-* | sort -V | tail -1)
    [[ -d "$newest" ]] || newest=""

    if [[ -z "$newest" ]]; then
        error "No kernel sources found in /usr/src/"
    fi

    local newest_name
    newest_name=$(basename "$newest")
    local current_target=""
    if [[ -L /usr/src/linux ]]; then
        current_target=$(readlink /usr/src/linux)
        current_target=$(basename "$current_target")
    fi

    if [[ "$newest_name" == "$current_target" ]]; then
        info "Already selected: ${newest_name}"
    else
        if $DRY_RUN; then
            info "[dry-run] Would select: ${newest_name} (current: ${current_target:-none})"
        else
            # Find the eselect index for this kernel
            local idx
            idx=$(eselect kernel list 2>/dev/null | grep "$newest_name" | grep -oP '\[\K[0-9]+' || true)
            if [[ -n "$idx" ]]; then
                eselect kernel set "$idx"
                info "Selected: ${newest_name} (was: ${current_target:-none})"
            else
                warn "Could not find eselect index for ${newest_name}"
                warn "Run manually: eselect kernel list && eselect kernel set <N>"
            fi
        fi
    fi

    # Show current state
    if [[ -L /usr/src/linux ]]; then
        info "Symlink: /usr/src/linux → $(readlink /usr/src/linux)"
    fi

    header "Portage Workarounds"
    sync_portage_workarounds

    header "Portage News"
    if $DRY_RUN; then
        info "[dry-run] Would run: eselect news read"
    else
        eselect news read
    fi

    echo ""
    info "Run '${0##*/} check' for pre-flight report."
}

# ============================================================================
# check — Pre-flight report
# ============================================================================
do_check() {
    local machine="$1"

    header "Machine"
    info "Detected: ${BOLD}${machine}${RESET}"
    info "GPU type: $(get_machine_field "$machine" gpu)"
    info "Hostname: $(hostname)"
    if [[ -r /sys/class/dmi/id/product_name ]]; then
        info "DMI: $(cat /sys/class/dmi/id/product_name)"
    fi

    header "Kernel Versions"
    local running target update_type
    running=$(get_running_version)
    info "Running: ${BOLD}$(get_running_release)${RESET} (version ${running})"

    if [[ ! -f "${KERNEL_SRC}/Makefile" ]]; then
        warn "No kernel source at ${KERNEL_SRC}"
        warn "Install gentoo-sources and set symlink: eselect kernel set <N>"
        return 1
    fi

    target=$(get_target_version)
    info "Target:  ${BOLD}${KERNEL_SRC}${RESET} → version ${target}"

    update_type=$(classify_update "$running" "$target")
    if [[ "$update_type" == "same-series" ]]; then
        info "Update type: ${GREEN}same-series${RESET} (${running} → ${target})"
        if [[ -f "${REPO_DIR}/machines/${machine}/kernel_config.sh" ]]; then
            info "Config strategy: copy running .config → kernel_config.sh → make olddefconfig"
        else
            info "Config strategy: copy running .config → make olddefconfig"
            warn "No kernel_config.sh — machine-specific settings may be missing"
        fi
    else
        info "Update type: ${YELLOW}cross-series${RESET} (${running} → ${target})"
        if [[ -f "${REPO_DIR}/machines/${machine}/kernel_config.sh" ]]; then
            info "Config strategy: make defconfig → kernel_config.sh → make olddefconfig"
        else
            warn "Config strategy: copy running .config → make olddefconfig (no kernel_config.sh found!)"
            warn "Cross-series without a script may miss new Kconfig options"
        fi
    fi

    header "Disk Space"
    local boot_avail root_avail
    boot_avail=$(df --output=avail /boot 2>/dev/null | tail -1 | tr -d ' ')
    root_avail=$(df --output=avail / 2>/dev/null | tail -1 | tr -d ' ')
    # Convert KB to MB
    info "/boot: $(( boot_avail / 1024 ))MB available (need ~100MB)"
    info "/:     $(( root_avail / 1024 ))MB available (need ~2GB for build)"
    if (( boot_avail < 102400 )); then
        warn "/boot is low on space — consider cleaning old kernels"
    fi
    if (( root_avail < 2097152 )); then
        warn "Root is low on space — kernel build needs ~2GB"
    fi

    # NVIDIA check
    local gpu_type
    gpu_type=$(get_machine_field "$machine" gpu)
    # Generic profile: probe at runtime instead of relying on registry.
    if [[ "$gpu_type" == "auto" ]]; then
        if lsmod 2>/dev/null | grep -q '^nvidia '; then
            gpu_type=nvidia
        else
            gpu_type=other  # i915, amdgpu, nouveau, etc. — no @module-rebuild needed
        fi
        info "GPU autodetect → ${gpu_type}"
    fi
    if [[ "$gpu_type" == "nvidia" ]]; then
        header "NVIDIA"
        if command -v nvidia-smi &>/dev/null; then
            local nv_driver
            nv_driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "unknown")
            info "nvidia-drivers: ${nv_driver}"
            if [[ -d /usr/src/linux/drivers/gpu/drm ]]; then
                info "DRM subsystem present in target source"
            fi
        else
            warn "nvidia-smi not found — nvidia-drivers not installed?"
        fi
        info "Install phase will run: emerge @module-rebuild"
    fi

    # Patches
    local patches
    patches=$(get_machine_field "$machine" patches)
    if [[ -n "$patches" ]]; then
        header "Patches"
        IFS=',' read -ra patch_list <<< "$patches"
        for patch_name in "${patch_list[@]}"; do
            local patch_entry="${PATCH_REGISTRY[$patch_name]:-}"
            if [[ -z "$patch_entry" ]]; then
                warn "Patch '${patch_name}' not found in registry"
                continue
            fi
            local patch_file patch_min patch_max patch_machines
            IFS='|' read -r patch_file patch_min patch_max patch_machines <<< "$patch_entry"
            local full_path="${REPO_DIR}/${patch_file}"
            if [[ ! -f "$full_path" ]]; then
                warn "Patch file missing: ${full_path}"
                continue
            fi
            if version_ge "$target" "$patch_min" && version_le "$target" "$patch_max"; then
                info "Will apply: ${patch_name} (${patch_file})"
            else
                info "Out of range: ${patch_name} (needs ${patch_min}-${patch_max}, target is ${target})"
            fi
        done
    else
        info "No patches registered for ${machine}"
    fi

    # Portage workarounds
    check_portage_workarounds

    # Existing kernels
    header "Installed Kernels"
    if [[ -d /boot ]]; then
        local count=0
        for f in /boot/vmlinuz-*; do
            [[ -f "$f" ]] || continue
            info "  $(basename "$f")  ($(stat -c '%y' "$f" | cut -d' ' -f1))"
            count=$(( count + 1 ))
        done
        if (( count == 0 )); then
            warn "No vmlinuz files found in /boot"
        fi
    fi

    # Repo config status
    header "Repo Config"
    local machine_dir="${REPO_DIR}/machines/${machine}"
    if [[ -f "${machine_dir}/.config" ]]; then
        info "Repo .config: present ($(stat -c '%y' "${machine_dir}/.config" | cut -d' ' -f1))"
    else
        info "Repo .config: not present"
    fi
    if [[ -f "${machine_dir}/kernel_config.sh" ]]; then
        info "kernel_config.sh: present"
    else
        info "kernel_config.sh: not present"
    fi

    # Drift check — sets REBUILD_NEEDED for do_full to consume
    header "Rebuild Check"
    check_rebuild_needed "$machine" "$(get_running_release)" "$(get_target_release)"

    echo ""
    if (( REBUILD_NEEDED == 0 )); then
        info "${GREEN}System is up to date — no rebuild needed.${RESET}"
        info "Run '${0##*/} verify' to re-check the running system, or '${0##*/} clean' to prune old kernels."
    else
        info "Run '${0##*/} prepare' to start the update."
    fi
}

# ============================================================================
# check_rebuild_needed — Detect whether a rebuild would actually change anything
# ============================================================================
# Sets the global REBUILD_NEEDED:
#   0 = no meaningful rebuild needed (running == target AND a fresh prepare
#       would produce a .config equivalent to the installed one, ignoring
#       toolchain-probe artifacts — see DRIFT_FILTER_REGEX below)
#   1 = rebuild needed (any precondition fails, real drift detected, or
#       check could not be completed — fail safe)
#
# Approach: simulate a same-series prepare in a tempdir.
#   1. Seed sandbox with /boot/config-<target>
#   2. Stage scripts/config locally so kernel_config.sh's `./scripts/config` works
#   3. Run kernel_config.sh in the sandbox (idempotent transform)
#   4. scripts/kconfig/conf --olddefconfig to resolve dependencies
#   5. Filter toolchain-probe symbols on both sides (false-drift, see below)
#   6. Hash + diff the remaining lines vs the installed config
#
# Limitation: `scripts/kconfig/conf --olddefconfig` is NOT equivalent to
# `make olddefconfig`. The latter runs shell probes (`$(success,...)` and
# `$(cc-option,...)` calls in Kconfig) to detect compiler/linker capabilities,
# which set CC_HAS_*, RUSTC_*, X86_KERNEL_IBT, MITIGATION_{RETHUNK,SRSO,...},
# CALL_PADDING, INIT_STACK_*, STACKPROTECTOR, etc. The sandbox can't run those
# probes, so those symbols appear as drift even though a real rebuild
# regenerates them identically. We strip them via DRIFT_FILTER_REGEX before
# comparison so the reported drift count reflects only meaningful changes.
# The filter is x86-focused (where we run); aarch64 hosts may see residual
# false-drift from arch-specific probes not yet enumerated.
#
# Cost: ~10-15s on slow machines (kernel_config.sh dominates), <5s on fast.
# ============================================================================
check_rebuild_needed() {
    local machine="$1" running_release="$2" target_release="$3"
    REBUILD_NEEDED=1   # safe default

    if [[ -z "$target_release" ]]; then
        warn "Cannot determine target release — assuming rebuild needed"
        return 0
    fi

    if [[ "$running_release" != "$target_release" ]]; then
        info "Rebuild needed: running ${running_release} ≠ target ${target_release}"
        return 0
    fi

    if [[ ! -f "/boot/vmlinuz-${target_release}" ]]; then
        info "Rebuild needed: /boot/vmlinuz-${target_release} not installed"
        return 0
    fi

    if [[ ! -f "/boot/config-${target_release}" ]]; then
        warn "Cannot drift-check: /boot/config-${target_release} missing — assuming rebuild needed"
        return 0
    fi

    local kconfig_script="${REPO_DIR}/machines/${machine}/kernel_config.sh"
    if [[ ! -f "$kconfig_script" ]]; then
        warn "Cannot drift-check: no kernel_config.sh for ${machine} — assuming rebuild needed"
        return 0
    fi

    if [[ ! -x "${KERNEL_SRC}/scripts/config" ]]; then
        warn "Cannot drift-check: ${KERNEL_SRC}/scripts/config missing — assuming rebuild needed"
        return 0
    fi

    if [[ ! -x "${KERNEL_SRC}/scripts/kconfig/conf" ]]; then
        warn "Cannot drift-check: ${KERNEL_SRC}/scripts/kconfig/conf missing (run a build first) — assuming rebuild needed"
        return 0
    fi

    # Map host arch to kernel ARCH/SRCARCH
    local arch
    case "$(uname -m)" in
        x86_64|i?86)  arch=x86 ;;
        aarch64)      arch=arm64 ;;
        *)            arch=$(uname -m) ;;
    esac

    info "Simulating fresh prepare in sandbox (this takes ~10-15s)..."

    local tmpdir
    tmpdir=$(mktemp -d "/tmp/update-system-drift.XXXXXX")

    # Seed: same starting point as same-series prepare
    cp "/boot/config-${target_release}" "$tmpdir/.config"

    # Stage scripts/config so kernel_config.sh's `./scripts/config` resolves
    mkdir -p "$tmpdir/scripts"
    cp "${KERNEL_SRC}/scripts/config" "$tmpdir/scripts/config"
    chmod +x "$tmpdir/scripts/config"

    if ! ( cd "$tmpdir" && bash "$kconfig_script" >/dev/null 2>&1 ); then
        warn "Drift check failed: kernel_config.sh errored in sandbox — assuming rebuild needed"
        rm -rf "$tmpdir"
        return 0
    fi

    # Resolve dependencies via direct conf invocation with KCONFIG_CONFIG.
    # We avoid `make olddefconfig` because the source tree is dirty after a
    # build (`make O=` refuses) and `make` would try to rebuild scripts/basic
    # under the user's UID. conf is already built, so we just point it at the
    # sandbox file and let it parse the in-tree Kconfig hierarchy directly.
    if ! ( cd "${KERNEL_SRC}" && \
            srctree="${KERNEL_SRC}" \
            ARCH="$arch" SRCARCH="$arch" \
            CC=gcc HOSTCC=gcc LD=ld \
            KCONFIG_CONFIG="$tmpdir/.config" \
            ./scripts/kconfig/conf --olddefconfig Kconfig >/dev/null 2>&1 ); then
        warn "Drift check failed: scripts/kconfig/conf errored in sandbox — assuming rebuild needed"
        rm -rf "$tmpdir"
        return 0
    fi

    # Symbols whose value comes from `make olddefconfig`'s compiler/linker
    # shell probes — the sandbox can't reproduce them, so we strip them on
    # both sides before comparing. Categories (all toolchain-derived):
    #   - Direct probes: CC_HAS_*, RUSTC_*, CC_VERSION_TEXT, CC_CAN_LINK*,
    #     CC_IMPLICIT_FALLTHROUGH, HAVE_KCSAN_COMPILER, TOOLS_SUPPORT_RELR
    #   - x86 mitigations gated on probes: MITIGATION_{CALL_DEPTH_TRACKING,
    #     ITS,RETHUNK,SLS,SRSO,UNRET_ENTRY}, CALL_{PADDING,THUNKS,THUNKS_DEBUG},
    #     HAVE_CALL_THUNKS, PREFIX_SYMBOLS
    #   - x86 hardening gated on probes: X86_{CET,KERNEL_IBT,NATIVE_CPU,X32_ABI},
    #     X86_DISABLED_FEATURE_*, ZERO_CALL_USED_REGS, STACKPROTECTOR{,_STRONG}
    #   - Sanitizer/init probes: KASAN, KCSAN, INIT_STACK_*
    local DRIFT_FILTER_REGEX='^(# )?CONFIG_(CC_HAS_[A-Z0-9_]+|CC_VERSION_TEXT|CC_IMPLICIT_FALLTHROUGH|CC_CAN_LINK[A-Z0-9_]*|RUSTC_[A-Z0-9_]+|HAVE_KCSAN_COMPILER|MITIGATION_(CALL_DEPTH_TRACKING|ITS|RETHUNK|SLS|SRSO|UNRET_ENTRY)|CALL_(PADDING|THUNKS(_DEBUG)?)|HAVE_CALL_THUNKS|PREFIX_SYMBOLS|INIT_STACK_[A-Z0-9_]+|KASAN|KCSAN|STACKPROTECTOR(_STRONG)?|TOOLS_SUPPORT_RELR|X86_(CET|KERNEL_IBT|NATIVE_CPU|X32_ABI|DISABLED_FEATURE_[A-Z0-9_]+)|ZERO_CALL_USED_REGS)( |=)'

    # Filtered (real-drift) line sets and unfiltered (raw) line sets
    local installed_filt sandbox_filt installed_raw sandbox_raw
    installed_raw=$(grep -E '^(CONFIG_|# CONFIG_.* is not set)' "/boot/config-${target_release}" | sort)
    sandbox_raw=$(grep -E '^(CONFIG_|# CONFIG_.* is not set)' "$tmpdir/.config" | sort)
    installed_filt=$(printf '%s\n' "$installed_raw" | grep -vE "$DRIFT_FILTER_REGEX" || true)
    sandbox_filt=$(printf '%s\n' "$sandbox_raw"   | grep -vE "$DRIFT_FILTER_REGEX" || true)

    local sandbox_hash installed_hash
    installed_hash=$(printf '%s\n' "$installed_filt" | sha256sum | cut -d' ' -f1)
    sandbox_hash=$(printf '%s\n' "$sandbox_filt"   | sha256sum | cut -d' ' -f1)

    # Diff line counts — raw includes toolchain noise, real strips it
    local raw_drift real_drift false_drift
    raw_drift=$(diff <(printf '%s\n' "$installed_raw")  <(printf '%s\n' "$sandbox_raw")  | grep -cE '^[<>]' || true)
    real_drift=$(diff <(printf '%s\n' "$installed_filt") <(printf '%s\n' "$sandbox_filt") | grep -cE '^[<>]' || true)
    false_drift=$(( raw_drift - real_drift ))

    if [[ "$sandbox_hash" == "$installed_hash" ]]; then
        rm -rf "$tmpdir"
        if (( false_drift > 0 )); then
            info "${GREEN}No real drift${RESET}: installed ${target_release} matches a fresh prepare (${false_drift} toolchain-probe line(s) filtered as sandbox artifact)"
        else
            info "${GREEN}No drift${RESET}: installed ${target_release} matches a fresh prepare"
        fi
        REBUILD_NEEDED=0
        return 0
    fi

    # Save the filtered (real-drift) diff for human inspection
    local drift_file="/tmp/${machine}-drift.diff"
    diff <(printf '%s\n' "$installed_filt") <(printf '%s\n' "$sandbox_filt") > "$drift_file" || true

    rm -rf "$tmpdir"
    warn "Drift detected: ${real_drift} meaningful config line(s) differ between installed and a fresh prepare"
    if (( false_drift > 0 )); then
        info "(${false_drift} additional toolchain-probe line(s) filtered — false drift from sandbox/make olddefconfig divergence)"
    fi
    info "Drift detail saved to: ${drift_file}"
    info "Rebuild may converge the running kernel with kernel_config.sh — but note that"
    info "a real \`make olddefconfig\` can still drop requested symbols whose deps are unmet."
    info "Inspect with: less ${drift_file} and machines/${machine}/INSTALL_GOTCHAS.md if present."
    return 0
}

# ============================================================================
# prepare — Backup config, migrate, apply patches, lint
# ============================================================================
do_prepare() {
    local machine="$1"

    [[ -f "${KERNEL_SRC}/Makefile" ]] || error "No kernel source at ${KERNEL_SRC}"

    local running target update_type
    running=$(get_running_version)
    target=$(get_target_version)
    update_type=$(classify_update "$running" "$target")
    local machine_dir="${REPO_DIR}/machines/${machine}"

    # --- Backup current .config ---
    header "Backup .config"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_repo="${machine_dir}/.config.backup-${timestamp}"
    local backup_src="${KERNEL_SRC}/.config.backup-${timestamp}"

    if [[ -f "${KERNEL_SRC}/.config" ]]; then
        if $DRY_RUN; then
            info "[dry-run] Would backup ${KERNEL_SRC}/.config to:"
            info "  ${backup_repo}"
            info "  ${backup_src}"
        else
            cp "${KERNEL_SRC}/.config" "$backup_repo"
            cp "${KERNEL_SRC}/.config" "$backup_src"
            info "Backed up to: ${backup_repo}"
            info "Backed up to: ${backup_src}"
        fi
    elif [[ -f "/proc/config.gz" ]]; then
        if $DRY_RUN; then
            info "[dry-run] Would extract /proc/config.gz as backup"
        else
            zcat /proc/config.gz > "$backup_repo"
            zcat /proc/config.gz > "$backup_src"
            info "Extracted from /proc/config.gz to: ${backup_repo}"
            info "Extracted from /proc/config.gz to: ${backup_src}"
        fi
    else
        warn "No existing .config found — nothing to backup"
    fi

    # --- Migrate config ---
    header "Config Migration (${update_type})"
    if [[ "$update_type" == "same-series" ]]; then
        # Same-series: copy running config as base
        info "Same-series update: copying running config"
        if $DRY_RUN; then
            info "[dry-run] Would copy running .config → ${KERNEL_SRC}/.config"
        else
            if [[ -f "/proc/config.gz" ]]; then
                zcat /proc/config.gz > "${KERNEL_SRC}/.config"
                info "Copied from /proc/config.gz"
            elif [[ -f "/boot/config-$(get_running_release)" ]]; then
                cp "/boot/config-$(get_running_release)" "${KERNEL_SRC}/.config"
                info "Copied from /boot/config-$(get_running_release)"
            elif [[ -f "${machine_dir}/.config" ]]; then
                cp "${machine_dir}/.config" "${KERNEL_SRC}/.config"
                info "Copied from repo: ${machine_dir}/.config"
            else
                error "Cannot find running .config — no /proc/config.gz, no /boot/config, no repo .config"
            fi
        fi
    else
        # Cross-series: start from defconfig (clean slate)
        info "Cross-series update: starting from defconfig"
        if $DRY_RUN; then
            info "[dry-run] Would run: make defconfig"
        else
            cd "${KERNEL_SRC}"
            make defconfig
            info "Generated defconfig"
        fi
    fi

    # --- Apply machine-specific kernel_config.sh (all update types) ---
    # kernel_config.sh uses scripts/config which is idempotent — safe to
    # re-apply on every build. This ensures machine-specific settings are
    # never lost, even if the base .config came from another machine or
    # a previous build that missed the script.
    if [[ -f "${machine_dir}/kernel_config.sh" ]]; then
        if $DRY_RUN; then
            info "[dry-run] Would run: bash ${machine_dir}/kernel_config.sh"
            info "[dry-run] Would run: make olddefconfig"
        else
            cd "${KERNEL_SRC}"
            bash "${machine_dir}/kernel_config.sh"
            info "Applied kernel_config.sh"
            make olddefconfig
            info "Resolved dependencies via olddefconfig"
        fi
    else
        warn "No kernel_config.sh found — relying on base .config only"
        warn "Machine-specific settings may be missing or inherited from another machine"
        if $DRY_RUN; then
            info "[dry-run] Would run: make olddefconfig"
        else
            cd "${KERNEL_SRC}"
            make olddefconfig
            info "Config updated via olddefconfig"
        fi
    fi

    # --- Apply patches ---
    local patches
    patches=$(get_machine_field "$machine" patches)
    if [[ -n "$patches" ]]; then
        header "Patches"
        IFS=',' read -ra patch_list <<< "$patches"
        for patch_name in "${patch_list[@]}"; do
            local patch_entry="${PATCH_REGISTRY[$patch_name]:-}"
            if [[ -z "$patch_entry" ]]; then
                warn "Patch '${patch_name}' not in registry — skipping"
                continue
            fi
            local patch_file patch_min patch_max patch_machines
            IFS='|' read -r patch_file patch_min patch_max patch_machines <<< "$patch_entry"
            local full_path="${REPO_DIR}/${patch_file}"

            if [[ ! -f "$full_path" ]]; then
                warn "Patch file missing: ${full_path} — skipping"
                continue
            fi

            # Check version range
            if ! version_ge "$target" "$patch_min" || ! version_le "$target" "$patch_max"; then
                info "Skipping ${patch_name}: out of version range (${patch_min}-${patch_max})"
                continue
            fi

            # Dry-run the patch to check if it applies / is already applied
            cd "${KERNEL_SRC}"
            if patch -p1 --dry-run -R < "$full_path" &>/dev/null; then
                info "Already applied: ${patch_name} — skipping"
                continue
            fi

            if ! patch -p1 --dry-run < "$full_path" &>/dev/null; then
                warn "Patch does not apply cleanly: ${patch_name}"
                warn "You may need to update the patch for kernel ${target}"
                continue
            fi

            if $DRY_RUN; then
                info "[dry-run] Would apply: ${patch_name}"
            else
                patch -p1 < "$full_path"
                info "Applied: ${patch_name}"
            fi
        done
    fi

    # --- Lint (if available) ---
    local lint="${REPO_DIR}/tools/kconfig-lint.sh"
    local kconfig_script="${machine_dir}/kernel_config.sh"
    if [[ -f "$lint" && -f "$kconfig_script" ]]; then
        header "Lint"
        if $DRY_RUN; then
            info "[dry-run] Would run: kconfig-lint.sh ${kconfig_script}"
        else
            # Lint is advisory — don't fail the prepare step
            bash "$lint" "$kconfig_script" "${KERNEL_SRC}" || true
        fi
    fi

    echo ""
    info "Prepare complete. Run '${0##*/} build' to compile."
}

# ============================================================================
# build — Compile kernel
# ============================================================================
do_build() {
    [[ -f "${KERNEL_SRC}/.config" ]] || error "No .config in ${KERNEL_SRC} — run 'prepare' first"

    if [[ $EUID -eq 0 ]]; then
        warn "Running build as root — consider running 'build' as a normal user"
    fi

    header "Build"
    local jobs
    jobs=$(nproc)
    local target
    target=$(get_target_version)
    info "Building kernel ${target} with -j${jobs}"

    if $DRY_RUN; then
        info "[dry-run] Would run: make -j${jobs} in ${KERNEL_SRC}"
        return
    fi

    cd "${KERNEL_SRC}"
    local start_time
    start_time=$(date +%s)

    make -j"${jobs}"

    local end_time elapsed_min elapsed_sec
    end_time=$(date +%s)
    elapsed_sec=$(( end_time - start_time ))
    elapsed_min=$(( elapsed_sec / 60 ))
    elapsed_sec=$(( elapsed_sec % 60 ))

    info "Build complete in ${elapsed_min}m ${elapsed_sec}s"
    info "Kernel: $(ls -lh arch/x86/boot/bzImage 2>/dev/null || echo 'not found')"
    local krelease
    krelease=$(cat include/config/kernel.release 2>/dev/null || echo "unknown")
    info "Release: ${krelease}"

    echo ""
    info "Run '${0##*/} install' to install (requires root)."
}

# ============================================================================
# install — Install kernel, modules, NVIDIA rebuild, write verify state
# ============================================================================
do_install() {
    local machine="$1"

    [[ -f "${KERNEL_SRC}/arch/x86/boot/bzImage" ]] || error "No bzImage — run 'build' first"
    [[ $EUID -eq 0 ]] || error "Install requires root"

    cd "${KERNEL_SRC}"
    local krelease old_release
    krelease=$(cat include/config/kernel.release)
    old_release=$(get_running_release)

    header "Install Modules"
    if $DRY_RUN; then
        info "[dry-run] Would run: make modules_install"
    else
        make modules_install
        info "Modules installed to /lib/modules/${krelease}"
    fi

    # Source symlink fix (needed for nvidia-drivers and other out-of-tree modules)
    local mod_dir="/lib/modules/${krelease}"
    if [[ -L "${mod_dir}/build" && ! -e "${mod_dir}/source" ]] && ! $DRY_RUN; then
        ln -s "$(readlink "${mod_dir}/build")" "${mod_dir}/source"
        info "Created ${mod_dir}/source symlink"
    fi

    ensure_boot_efi_mounted

    header "Install Kernel"
    if $DRY_RUN; then
        info "[dry-run] Would run: make install"
    else
        make install
        info "Kernel installed"

        # Copy GRUB to EFI fallback path — many UEFI firmwares (especially Dell)
        # only boot from EFI/Boot/bootx64.efi, ignoring custom bootloader-id entries.
        if [[ -d /boot/efi/EFI/Gentoo ]]; then
            mkdir -p /boot/efi/EFI/Boot
            cp /boot/efi/EFI/Gentoo/grubx64.efi /boot/efi/EFI/Boot/bootx64.efi
            info "GRUB copied to EFI fallback path (EFI/Boot/bootx64.efi)"
        fi
    fi

    # NVIDIA rebuild — skipped if a postinst.d hook already handled it during
    # `make install` above (avoids rebuilding nvidia-drivers twice).
    local gpu_type
    gpu_type=$(get_machine_field "$machine" gpu)
    if [[ "$gpu_type" == "nvidia" ]]; then
        if [[ -x /etc/kernel/postinst.d/99-module-rebuild.install ]] && ! $DRY_RUN; then
            header "NVIDIA Module Rebuild"
            info "Skipped — handled by /etc/kernel/postinst.d/99-module-rebuild.install during make install"
        else
            header "NVIDIA Module Rebuild"
            if $DRY_RUN; then
                info "[dry-run] Would run: emerge @module-rebuild"
            else
                info "Rebuilding out-of-tree modules (nvidia-drivers, etc.)..."
                env -i HOME=/root TERM="${TERM:-linux}" \
                    KERNEL_DIR="${KERNEL_SRC}" \
                    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/bin" \
                    emerge @module-rebuild
                info "Module rebuild complete"
            fi
        fi
    fi

    # Verify GRUB has both old and new entries
    header "GRUB"
    if $DRY_RUN; then
        info "[dry-run] Would verify GRUB entries"
    else
        if [[ -f /boot/grub/grub.cfg ]]; then
            local grub_entries
            grub_entries=$(grep -c "menuentry " /boot/grub/grub.cfg 2>/dev/null || true)
            info "GRUB has ${grub_entries} menu entries"
            if grep -q "$krelease" /boot/grub/grub.cfg; then
                info "New kernel ${krelease} found in GRUB"
            else
                warn "New kernel ${krelease} NOT found in GRUB — check installkernel / grub-mkconfig"
            fi
            if grep -q "$old_release" /boot/grub/grub.cfg; then
                info "Old kernel ${old_release} still in GRUB (rollback available)"
            else
                warn "Old kernel ${old_release} not in GRUB — no rollback entry!"
            fi
        else
            warn "/boot/grub/grub.cfg not found"
        fi
    fi

    # Write verify state
    header "Verify State"
    if $DRY_RUN; then
        info "[dry-run] Would write ${PENDING_FILE}"
    else
        mkdir -p "${STATE_DIR}"
        cat > "${PENDING_FILE}" <<EOF
# Kernel update pending verification
# Written by update-system.sh on $(date -Iseconds)
MACHINE=${machine}
OLD_RELEASE=${old_release}
NEW_RELEASE=${krelease}
GPU_TYPE=${gpu_type}
TIMESTAMP=$(date +%s)
EOF
        info "Wrote ${PENDING_FILE}"
    fi

    echo ""
    info "Install complete. Reboot, then run '${0##*/} verify'."
}

# ============================================================================
# verify — Post-reboot checks
# ============================================================================
do_verify() {
    local machine="$1"
    local expected_release="" old_release="" gpu_type=""

    # Read pending verify state if available
    if [[ -f "$PENDING_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$PENDING_FILE"
        machine="${MACHINE:-$machine}"
        expected_release="${NEW_RELEASE:-}"
        old_release="${OLD_RELEASE:-}"
        gpu_type="${GPU_TYPE:-$(get_machine_field "$machine" gpu)}"
        info "Loaded verify state from ${PENDING_FILE}"
    else
        gpu_type=$(get_machine_field "$machine" gpu)
        info "No pending verify state — running general checks"
    fi

    local running_release
    running_release=$(get_running_release)

    header "Kernel Version"
    info "Running: ${BOLD}${running_release}${RESET}"
    if [[ -n "$expected_release" ]]; then
        if [[ "$running_release" == "$expected_release" ]]; then
            info "${GREEN}Match!${RESET} Running the expected new kernel"
        else
            warn "Expected ${expected_release} but running ${running_release}"
            warn "Did you boot the new kernel? Check GRUB."
        fi
    fi

    # ------------------------------------------------------------------
    # Known-benign patterns: filtered from error counts but reported as info
    # so a change in count is still visible. Each entry MUST have a comment
    # explaining WHY it's benign — future-you will need it.
    # ------------------------------------------------------------------
    # General (apply to every machine)
    local benign_dmesg='error\.recovery|failsafe|fail.over|aer.*corrected|manage.error'
    benign_dmesg+='|rdinit=/init failed'                            # no initramfs — kernel falls back to /sbin/init, harmless
    benign_dmesg+='|tmp\.[A-Za-z0-9]+\[[0-9]+\]: segfault'          # Claude Code Bash tool tempfile exec races (mktemp tmp.XXXXXXXX scripts unmapped mid-call)
    local benign_services=''                                        # space-separated service names expected to be stopped

    case "$machine" in
        surface-pro-6)
            benign_dmesg+='|mwifiex.*nxp/rgpower_.*\.bin'           # Marvell regulatory power tables not shipped by linux-firmware; WiFi works without
            benign_dmesg+='|dw-apb-uart.*failed to request DMA'     # SP6 SAM UART chain — DMA optional, polling fallback fine
            benign_services='xdm'                                    # SP6 uses lightdm; xdm shipped in default runlevel but never started
            ;;
        xps-9510)
            benign_dmesg+='|pci 0000:01:00\.0: ROM .* failed to assign'  # NVIDIA RTX 3050 Ti option ROM — BIOS doesn't allocate the BAR, kernel proxies via vBIOS shadow; nvidia-drivers loads fine
            benign_dmesg+='|_TZ\.ETMD'                                    # Dell BIOS bug: ACPI thermal zone references undefined symbol; thermald handles thermal mgmt regardless
            benign_dmesg+='|NVRM: nvAssertFailedNoLog.*kernel_gsp\.c:1446' # GSP-RM firmware cosmetic assertion (nvidia-drivers 595.58.03 + kernel 6.18); no functional impact, awaiting driver fix
            ;;
    esac

    header "Boot Messages"
    local raw_errors filtered_errors benign_dmesg_count
    raw_errors=$(dmesg 2>/dev/null | grep -ciE "(error|fail)" || true)
    filtered_errors=$(dmesg 2>/dev/null | grep -iE "(error|fail)" | grep -icvE "$benign_dmesg" || true)
    benign_dmesg_count=$(( raw_errors - filtered_errors ))
    if (( filtered_errors == 0 )); then
        if (( benign_dmesg_count > 0 )); then
            info "No errors in dmesg (${benign_dmesg_count} known-benign filtered)"
        else
            info "No errors or failures in dmesg"
        fi
    else
        warn "${filtered_errors} lines with error/fail in dmesg (${benign_dmesg_count} known-benign filtered)"
        dmesg 2>/dev/null | grep -iE "(error|fail)" | grep -ivE "$benign_dmesg" | head -10
        if (( filtered_errors > 10 )); then
            warn "... and $(( filtered_errors - 10 )) more (run 'dmesg | grep -i error' to see all)"
        fi
    fi

    header "PCI Drivers"
    local unbound
    unbound=$(lspci -k 2>/dev/null | grep -c "Kernel driver in use:" || true)
    local total_pci
    total_pci=$(lspci 2>/dev/null | wc -l)
    info "${unbound}/${total_pci} PCI devices have drivers bound"

    # Machine-specific checks
    verify_machine_specific "$machine" "$gpu_type"

    header "zram"
    if swapon --show 2>/dev/null | grep -q zram; then
        info "zram swap: $(swapon --show 2>/dev/null | grep zram | awk '{print $3}')"
    else
        warn "No zram swap detected"
    fi

    header "Firmware"
    local fw_raw fw_filtered fw_benign
    fw_raw=$(dmesg 2>/dev/null | grep -ciE "firmware.*(error|fail|missing)" || true)
    fw_filtered=$(dmesg 2>/dev/null | grep -iE "firmware.*(error|fail|missing)" | grep -icvE "$benign_dmesg" || true)
    fw_benign=$(( fw_raw - fw_filtered ))
    if (( fw_filtered == 0 )); then
        if (( fw_benign > 0 )); then
            info "No firmware errors in dmesg (${fw_benign} known-benign filtered)"
        else
            info "No firmware errors in dmesg"
        fi
    else
        warn "${fw_filtered} firmware-related errors in dmesg (${fw_benign} known-benign filtered):"
        dmesg 2>/dev/null | grep -iE "firmware.*(error|fail|missing)" | grep -ivE "$benign_dmesg" | head -5
    fi

    header "Services"
    if command -v rc-status &>/dev/null; then
        local failed_raw_count failed_lines failed_filtered_count benign_svc_count
        failed_raw_count=$(rc-status 2>/dev/null | grep -cE "crashed|stopped" || true)
        if (( failed_raw_count == 0 )); then
            info "All OpenRC services running"
        else
            failed_lines=$(rc-status 2>/dev/null | grep -E "crashed|stopped")
            if [[ -n "$benign_services" ]]; then
                # Match service name at start of line (rc-status indents with spaces)
                local benign_re="^[[:space:]]*(${benign_services// /|})[[:space:]]"
                failed_lines=$(echo "$failed_lines" | grep -vE "$benign_re" || true)
            fi
            failed_filtered_count=$(echo -n "$failed_lines" | grep -c . || true)
            benign_svc_count=$(( failed_raw_count - failed_filtered_count ))
            if (( failed_filtered_count == 0 )); then
                info "All services running (${benign_svc_count} known-benign stopped: ${benign_services})"
            else
                warn "${failed_filtered_count} services crashed or stopped:"
                echo "$failed_lines"
                (( benign_svc_count > 0 )) && info "(${benign_svc_count} known-benign filtered: ${benign_services})"
            fi
        fi
    fi

    # Archive verify state on success
    if [[ -f "$PENDING_FILE" && "$running_release" == "$expected_release" ]]; then
        header "Archive"
        mkdir -p "${HISTORY_DIR}"
        local archive="${HISTORY_DIR}/verify-${running_release}-$(date +%Y%m%d).txt"
        mv "$PENDING_FILE" "$archive"
        info "Archived verify state to ${archive}"
    fi

    echo ""
    info "Verify complete."
}

# Machine-specific verification
verify_machine_specific() {
    local machine="$1" gpu_type="$2"

    # GPU
    header "GPU (${gpu_type})"
    case "$gpu_type" in
        nvidia)
            if command -v nvidia-smi &>/dev/null; then
                local nv_out
                nv_out=$(nvidia-smi --query-gpu=name,driver_version,power.draw --format=csv,noheader 2>/dev/null || echo "FAILED")
                if [[ "$nv_out" == "FAILED" ]]; then
                    warn "nvidia-smi failed — driver may not be loaded"
                else
                    info "nvidia-smi: ${nv_out}"
                fi
            else
                warn "nvidia-smi not found"
            fi
            if [[ -c /dev/nvidia0 ]]; then
                info "/dev/nvidia0 exists"
            else
                warn "/dev/nvidia0 missing — nvidia module not loaded?"
            fi
            local nv_dmesg_err
            nv_dmesg_err=$(dmesg 2>/dev/null | grep -ci "nvidia.*error\|nvrm.*error" || true)
            if (( nv_dmesg_err > 0 )); then
                warn "${nv_dmesg_err} NVIDIA errors in dmesg"
            else
                info "No NVIDIA errors in dmesg"
            fi
            ;;
        intel)
            if grep -q "^i915 " /proc/modules 2>/dev/null; then
                info "i915 loaded"
            else
                warn "i915 not loaded"
            fi
            if [[ -d /sys/class/backlight/intel_backlight ]]; then
                info "intel_backlight available"
            fi
            ;;
    esac

    # WiFi
    header "WiFi"
    case "$machine" in
        precision-t5810|optiplex-3090)
            info "No WiFi (wired desktop)"
            ;;
        xps-9510|xps-9315|nuc11|beelink-minis)
            if grep -q "^iwlwifi " /proc/modules 2>/dev/null; then
                info "iwlwifi loaded"
                local wl_iface
                wl_iface=$(ip -o link show 2>/dev/null | grep -oP 'wl\S+' | head -1 || true)
                if [[ -n "$wl_iface" ]]; then
                    info "WiFi interface: ${wl_iface}"
                fi
            else
                warn "iwlwifi not loaded"
            fi
            ;;
        mbp-2015)
            if grep -q "^brcmfmac " /proc/modules 2>/dev/null; then
                info "brcmfmac loaded"
            else
                warn "brcmfmac not loaded"
            fi
            ;;
        surface-pro-6)
            if grep -q "^mwifiex " /proc/modules 2>/dev/null; then
                info "mwifiex loaded"
            else
                warn "mwifiex not loaded"
            fi
            ;;
    esac

    # Platform-specific
    case "$machine" in
        mbp-2015)
            header "Apple Platform"
            if grep -q "^applesmc " /proc/modules 2>/dev/null; then
                info "applesmc loaded"
                if command -v sensors &>/dev/null; then
                    local temp
                    temp=$(sensors 2>/dev/null | grep "TC0P\|CPU" | head -1 || true)
                    [[ -n "$temp" ]] && info "Temperature: ${temp}"
                fi
            else
                warn "applesmc not loaded"
            fi
            ;;
        surface-pro-6)
            header "Surface Platform"
            if grep -q "^surface_aggregator " /proc/modules 2>/dev/null; then
                info "surface_aggregator loaded"
            else
                warn "surface_aggregator not loaded"
            fi
            if [[ -d /sys/class/power_supply/BAT1 ]]; then
                local cap
                cap=$(cat /sys/class/power_supply/BAT1/capacity 2>/dev/null || echo "?")
                info "Battery: ${cap}%"
            fi
            ;;
        xps-9510|optiplex-3090)
            header "Dell Platform"
            if grep -q "^dell_smbios " /proc/modules 2>/dev/null; then
                info "dell_smbios loaded"
            fi
            if grep -q "^dell_wmi " /proc/modules 2>/dev/null; then
                info "dell_wmi loaded"
            fi
            ;;
        precision-t5810)
            header "Dell Workstation Platform"
            if grep -q "^e1000e " /proc/modules 2>/dev/null; then
                info "e1000e loaded (I217-LM Ethernet)"
            else
                warn "e1000e not loaded"
            fi
            if grep -q "^sb_edac " /proc/modules 2>/dev/null; then
                info "sb_edac loaded (ECC memory)"
                if [[ -d /sys/devices/system/edac/mc ]]; then
                    local ce ue
                    ce=$(cat /sys/devices/system/edac/mc/mc0/ce_count 2>/dev/null || echo "?")
                    ue=$(cat /sys/devices/system/edac/mc/mc0/ue_count 2>/dev/null || echo "?")
                    info "EDAC MC0: ${ce} correctable, ${ue} uncorrectable errors"
                fi
            else
                warn "sb_edac not loaded (ECC monitoring unavailable)"
            fi
            ;;
    esac
}

# ============================================================================
# all — prepare + build + install
# ============================================================================
do_all() {
    local machine="$1"
    info "Running: prepare → build → install"
    echo ""

    do_prepare "$machine"
    echo ""
    do_build
    echo ""
    do_install "$machine"

    echo ""
    info "All phases complete. Reboot, then run '${0##*/} verify'."
}

# ============================================================================
# clean — Remove old kernels via eclean-kernel
# ============================================================================
do_clean() {
    [[ $EUID -eq 0 ]] || error "Clean requires root"

    # Auto-install eclean-kernel if missing
    if ! command -v eclean-kernel &>/dev/null; then
        info "eclean-kernel not installed — installing now"
        if $DRY_RUN; then
            info "[dry-run] Would run: emerge app-admin/eclean-kernel"
        else
            emerge app-admin/eclean-kernel
        fi
    fi

    header "Kernel Cleanup"
    local before_count=0
    for f in /boot/vmlinuz-*; do
        [[ -f "$f" ]] || continue
        before_count=$(( before_count + 1 ))
    done
    info "Kernels in /boot before cleanup: ${before_count}"

    # Prune .old build-backups for the running kernel version. installkernel's
    # updatever() renames the prior build to vmlinuz-${VER}.old before installing
    # the new one. After a successful boot+verify on the same version (e.g. a
    # rebuild without a version bump), the .old triplet is dead weight that
    # eclean-kernel ignores entirely (it tracks distinct versions, not build
    # backups). Only touch files matching the *running* version — never another.
    local running_kver
    running_kver=$(uname -r)
    local stale_old=(
        "/boot/vmlinuz-${running_kver}.old"
        "/boot/System.map-${running_kver}.old"
        "/boot/config-${running_kver}.old"
    )
    local stale_found=0
    for f in "${stale_old[@]}"; do
        [[ -f "$f" ]] && stale_found=$(( stale_found + 1 ))
    done
    if (( stale_found > 0 )); then
        if $DRY_RUN; then
            info "[dry-run] Would remove ${stale_found} stale .old file(s) for running kernel ${running_kver}:"
            for f in "${stale_old[@]}"; do
                [[ -f "$f" ]] && info "  $f"
            done
        else
            info "Removing ${stale_found} stale .old file(s) for running kernel ${running_kver}"
            for f in "${stale_old[@]}"; do
                if [[ -f "$f" ]]; then
                    rm -f "$f"
                    info "  removed $(basename "$f")"
                fi
            done
        fi
    fi

    if $DRY_RUN; then
        info "[dry-run] Would run: eclean-kernel -n 3"
        eclean-kernel -n 3 --pretend
    else
        eclean-kernel -n 3
        info "eclean-kernel complete"
    fi

    header "Update GRUB"
    if $DRY_RUN; then
        info "[dry-run] Would run: grub-mkconfig -o /boot/grub/grub.cfg"
    else
        grub-mkconfig -o /boot/grub/grub.cfg
        info "GRUB config updated"
    fi

    # Show remaining kernels
    header "Remaining Kernels"
    local after_count=0
    for f in /boot/vmlinuz-*; do
        [[ -f "$f" ]] || continue
        info "  $(basename "$f")  ($(stat -c '%y' "$f" | cut -d' ' -f1))"
        after_count=$(( after_count + 1 ))
    done
    info "Kernels remaining: ${after_count}"

    echo ""
    info "Cleanup complete."
}

# ============================================================================
# world — Update system packages (@world + preserved-rebuild + depclean)
# ============================================================================
do_world() {
    [[ $EUID -eq 0 ]] || error "World update requires root"

    # linux-firmware, installkernel, grub all need /boot/efi during @world
    ensure_boot_efi_mounted

    header "System Update (@world)"
    if $DRY_RUN; then
        info "[dry-run] Would run: emerge -avuDN @world"
        emerge --pretend -vuDN @world || true
    else
        if ! emerge -avuDN @world; then
            warn "@world update failed. To resume where it left off:"
            warn "  emerge --resume              # retry from the failed package"
            warn "  emerge --resume --skipfirst  # skip it and continue with the rest"
            warn "Before skipping, check if anything depends on the failed package:"
            warn "  equery depends <failed-pkg>  # if nothing, safe to skip"
            warn "NEVER skip: gcc, glibc, binutils, openssl, python, llvm, portage, baselayout"
            warn "Fix the issue, then re-run: sudo ${0##*/} world"
            return 1
        fi
    fi

    header "Preserved Rebuild"
    if $DRY_RUN; then
        info "[dry-run] Would run: emerge @preserved-rebuild"
        emerge --pretend @preserved-rebuild || true
    else
        if ! emerge @preserved-rebuild; then
            warn "preserved-rebuild failed. Fix the issue, then re-run: sudo ${0##*/} world"
            return 1
        fi
    fi

    header "Dependency Cleanup"
    if $DRY_RUN; then
        info "[dry-run] Would run: emerge --depclean -a"
        emerge --pretend --depclean || true
    else
        if ! emerge --depclean -a; then
            warn "depclean failed. Fix the issue, then re-run: sudo ${0##*/} world"
            return 1
        fi
    fi

    echo ""
    info "World update complete."
    info "Run '${0##*/} config-update' if there are pending config file updates."
}

# ============================================================================
# config-update — Merge updated config files (auto-accept new versions)
# ============================================================================
do_config_update() {
    [[ $EUID -eq 0 ]] || error "Config update requires root"

    header "Config File Updates"
    local pending
    pending=$(find /etc -name '._cfg????_*' 2>/dev/null | wc -l)
    if (( pending == 0 )); then
        info "No config files to update."
        return 0
    fi
    info "${pending} config file(s) need updating:"
    find /etc -name '._cfg????_*' 2>/dev/null | sed 's|.*_cfg[0-9]*_|  |' | sort -u
    if $DRY_RUN; then
        info "[dry-run] Would run: etc-update --automode -5 (use new)"
    else
        etc-update --automode -5
    fi
}

# ============================================================================
# full — Complete prompted workflow with resume support
# ============================================================================
# State file tracks completed phases so the workflow can be interrupted and
# resumed (e.g., across a reboot). Each line is a completed phase name.
FULL_STATE="${STATE_DIR}/full-progress"

phase_done() {
    $DRY_RUN && return 1  # dry-run shows all phases
    [[ -f "$FULL_STATE" ]] && grep -qx "$1" "$FULL_STATE" 2>/dev/null
}

mark_done() {
    $DRY_RUN && return 0
    echo "$1" >> "$FULL_STATE"
}

# Prompt before a phase, run the command, mark done.
# Usage: run_full_phase <phase> <description> <command> [args...]
# User can answer: Y (run), n (stop and resume later), s (skip this phase)
run_full_phase() {
    local phase="$1" desc="$2"
    shift 2

    phase_done "$phase" && return 0

    echo ""
    echo -e "${BOLD}>>> Phase: ${phase}${RESET} — ${desc}"
    if ! $DRY_RUN; then
        read -rp "    Proceed? [Y/n/s(kip)] " answer
        case "${answer,,}" in
            n|no)
                echo ""
                info "Stopped. Resume later: sudo ${0##*/} full"
                exit 0
                ;;
            s|skip)
                mark_done "$phase"
                info "Skipped ${phase}"
                return 0
                ;;
        esac
    fi

    "$@"
    mark_done "$phase"
}

do_full() {
    local machine="$1"
    [[ $EUID -eq 0 ]] || error "Full workflow requires root"

    mkdir -p "${STATE_DIR}"

    # Resume check
    if [[ -f "$FULL_STATE" ]] && ! $DRY_RUN; then
        info "Resuming full workflow — completed phases:"
        while IFS= read -r line; do
            info "  done: ${line}"
        done < "$FULL_STATE"
        echo ""
        read -rp "Continue from where you left off? [Y/n/reset] " answer
        case "${answer,,}" in
            n|no) exit 0 ;;
            r|reset)
                rm -f "$FULL_STATE"
                info "Progress cleared — starting fresh."
                echo ""
                ;;
        esac
    fi

    info "Full workflow: fetch → check → prepare → build → install → world → config-update → reboot → verify → clean"

    # --- Pre-reboot phases ---
    # Kernel build (prepare/build/install) MUST precede world. `fetch` repoints
    # /usr/src/linux at a fresh source tree with no .config; if @world rebuilds
    # an out-of-tree module (nvidia-drivers, etc.) before prepare/build stages
    # and compiles the new tree, its pkg_setup dies in require_configured_kernel.
    run_full_phase fetch          "Sync portage + install gentoo-sources + eselect kernel + news" \
        do_fetch
    run_full_phase check          "Pre-flight report (versions, disk, patches)" \
        do_check "$machine"

    # If do_check determined no rebuild is needed, auto-mark prepare/build/install
    # as done so the workflow drops straight to world → verify/clean. Also clear
    # any stale pending-verify state so the post-install reboot prompt doesn't fire.
    if (( REBUILD_NEEDED == 0 )) && ! $DRY_RUN; then
        echo ""
        info "${GREEN}Skipping prepare/build/install — installed kernel matches a fresh prepare.${RESET}"
        rm -f "$PENDING_FILE"
        for skip_phase in prepare build install; do
            phase_done "$skip_phase" || mark_done "$skip_phase"
        done
    fi

    run_full_phase prepare "Backup config + migrate + apply patches + lint" \
        do_prepare "$machine"
    run_full_phase build   "Compile kernel with make -j$(nproc)" \
        do_build
    run_full_phase install "Install modules + kernel + NVIDIA rebuild + GRUB" \
        do_install "$machine"
    run_full_phase world          "Update @world + preserved-rebuild + depclean" \
        do_world
    run_full_phase config-update  "Merge updated config files (auto-accept new versions)" \
        do_config_update

    # --- Reboot boundary ---
    if ! phase_done verify; then
        # Check if the new kernel is running (i.e., user rebooted)
        if [[ -f "$PENDING_FILE" ]]; then
            # shellcheck disable=SC1090
            source "$PENDING_FILE"
            local running
            running=$(get_running_release)
            if [[ "${NEW_RELEASE:-}" != "$running" ]] && ! $DRY_RUN; then
                echo ""
                info "Install complete. Reboot into the new kernel, then resume:"
                info "  sudo ${0##*/} full"
                exit 0
            fi
        fi
    fi

    # --- Post-reboot phases ---
    run_full_phase verify "Post-reboot verification (dmesg, drivers, GPU, WiFi)" \
        do_verify "$machine"
    run_full_phase clean  "Remove old kernels, keeping 3 most recent" \
        do_clean

    # All done
    if ! $DRY_RUN; then
        rm -f "$FULL_STATE"
    fi
    echo ""
    info "Full workflow complete."
}

# ============================================================================
# Usage
# ============================================================================
usage() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS] COMMAND

System update tool for production Gentoo machines.

Commands:
  full           Prompted end-to-end workflow with resume support (default)
                   fetch → check → prepare → build → install → world →
                   config-update → reboot → verify → clean
                   Prompts Y/n/skip before each phase. Saves progress — re-run to resume.
  fetch          Sync portage, install latest gentoo-sources, select kernel, show news (requires root)
  world          Update @world + preserved-rebuild + depclean (requires root)
  config-update  Merge updated config files (auto-accept new versions) (requires root)
  check          Pre-flight: versions, disk, NVIDIA compat, patches, config strategy
  prepare        Backup .config, migrate config, apply patches, lint
  build          Compile kernel with make -j\$(nproc)
  install        Install modules + kernel + NVIDIA rebuild (requires root)
  verify         Post-reboot verification checks
  clean          Remove old kernels, keeping 3 most recent (requires root)
  all            Run prepare + build + install (requires root)

Options:
  --dry-run          Show what would happen without changes
  --machine NAME     Override auto-detection (valid: ${!MACHINES[*]})
  -h, --help         Show this help

Typical usage:
  sudo ${0##*/}              # prompted full workflow (default)
  sudo ${0##*/} full         # same thing
  sudo ${0##*/} --dry-run    # preview all phases
  # after reboot:
  sudo ${0##*/}              # resumes with verify + clean

Individual subcommands (run phases manually):
  sudo ${0##*/} fetch
  sudo ${0##*/} world
  sudo ${0##*/} config-update
  ${0##*/} check
  ${0##*/} prepare
  ${0##*/} build
  sudo ${0##*/} install
  # reboot
  ${0##*/} verify
  sudo ${0##*/} clean
EOF
    exit 0
}

# ============================================================================
# Main
# ============================================================================
# Parse flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --machine)
            [[ -n "${2:-}" ]] || error "--machine requires an argument"
            MACHINE_OVERRIDE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            error "Unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

[[ $# -ge 1 ]] || set -- full

COMMAND="$1"
shift

# Detect machine
MACHINE=$(detect_machine)

# Backfill registry for the generic profile (chosen via prompt).
# detect_machine ran in a subshell so it couldn't mutate MACHINES itself.
if [[ "$MACHINE" == "generic" && -z "${MACHINES[generic]+x}" ]]; then
    _gen_dmi=""
    [[ -r /sys/class/dmi/id/product_name ]] && _gen_dmi=$(cat /sys/class/dmi/id/product_name)
    MACHINES[generic]="hostname=$(hostname)|dmi=${_gen_dmi}|gpu=auto|patches="
    info "Generic profile: gpu=auto (runtime-probed), no patches, no kernel_config.sh"
fi

if $DRY_RUN; then
    info "[dry-run mode]"
fi

# --- Inhibit sleep/idle for the duration of long-running operations ---
# Re-exec under elogind-inhibit/systemd-inhibit to prevent the machine from
# suspending during builds (especially on laptops with idle-hibernate).
#
# Probe each candidate first with a no-op `true` invocation: polkit may deny
# non-root callers, in which case the inhibitor exits non-zero. Only `exec`
# once we've confirmed the inhibitor will actually take. Otherwise we'd
# silently terminate (exec already replaced this shell) when the chosen
# inhibitor refuses.
if [[ -z "${_UPDATE_INHIBITED:-}" ]]; then
    _inhibit_chosen=""
    for _inhibit_cmd in elogind-inhibit systemd-inhibit; do
        command -v "$_inhibit_cmd" &>/dev/null || continue
        if "$_inhibit_cmd" --what=sleep:idle \
                           --who="update-system.sh-probe" \
                           --why="probe" true 2>/dev/null; then
            _inhibit_chosen="$_inhibit_cmd"
            break
        fi
    done
    if [[ -n "$_inhibit_chosen" ]]; then
        export _UPDATE_INHIBITED=1
        info "Inhibiting sleep for duration of update (${_inhibit_chosen})"
        exec "$_inhibit_chosen" --what=sleep:idle \
            --who="update-system.sh" \
            --why="System update in progress" \
            "$0" "${_ORIG_ARGS[@]}"
    else
        # Either no inhibitor binary, or all of them denied (polkit). Press on.
        if command -v elogind-inhibit &>/dev/null || command -v systemd-inhibit &>/dev/null; then
            warn "Sleep inhibitor present but cannot inhibit (polkit denied?) — continuing without"
        elif [[ -d /sys/class/power_supply/BAT0 || -d /sys/class/power_supply/BAT1 ]]; then
            warn "No sleep inhibitor found — laptop may suspend during long builds"
        fi
    fi
fi

case "$COMMAND" in
    full)          do_full "$MACHINE" ;;
    fetch)         do_fetch ;;
    world)         do_world ;;
    config-update) do_config_update ;;
    check)         do_check "$MACHINE" ;;
    prepare)       do_prepare "$MACHINE" ;;
    build)         do_build ;;
    install)       do_install "$MACHINE" ;;
    verify)        do_verify "$MACHINE" ;;
    clean)         do_clean ;;
    all)           do_all "$MACHINE" ;;
    *)             error "Unknown command: ${COMMAND}. Run '${0##*/} --help' for usage." ;;
esac
