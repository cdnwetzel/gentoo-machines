#!/bin/bash
# ============================================================================
# update-kernel.sh — Local Kernel Update Tool
# ============================================================================
# Single self-contained script for updating the kernel on production Gentoo
# machines. Auto-detects which machine via hostname + DMI fallback.
#
# Subcommands:
#   check    - Pre-flight: versions, disk, NVIDIA compat, patches, config strategy
#   prepare  - Backup .config, migrate config (copy or script), apply patches, lint
#   build    - make -j$(nproc) with timing
#   install  - modules_install + make install + NVIDIA rebuild + verify state
#   verify   - Post-reboot checks: dmesg, drivers, GPU, WiFi, zram, services
#   all      - prepare + build + install (not verify — requires reboot first)
#
# Flags:
#   --dry-run          Show what would happen without making changes
#   --machine <name>   Override auto-detection
#
# Config strategy:
#   Same-series (e.g., 6.18.12 → 6.18.16):
#     Copy running .config → make olddefconfig
#   Cross-series (e.g., 6.12 → 6.18):
#     make defconfig → kernel_config.sh → make olddefconfig
#     Falls back to .config copy + warning if no script exists
#
# Usage:
#   update-kernel.sh check
#   update-kernel.sh --dry-run prepare
#   update-kernel.sh --machine xps-9510 all
#   update-kernel.sh verify
# ============================================================================

set -euo pipefail

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
# Helpers
# ============================================================================
info()  { echo -e "${GREEN}>>>${RESET} $*"; }
warn()  { echo -e "${YELLOW}>>>${RESET} $*"; }
error() { echo -e "${RED}>>>${RESET} $*" >&2; exit 1; }
header() { echo -e "\n${BLUE}=== $* ===${RESET}"; }

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
# Machine Detection
# ============================================================================
detect_machine() {
    # 1. Command-line override
    if [[ -n "$MACHINE_OVERRIDE" ]]; then
        if [[ -z "${MACHINES[$MACHINE_OVERRIDE]+x}" ]]; then
            error "Unknown machine '${MACHINE_OVERRIDE}'. Valid: ${!MACHINES[*]}"
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

    error "Cannot detect machine. Hostname='${hostname}'. Use --machine <name> to override.\nValid machines: ${!MACHINES[*]}"
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
        info "Config strategy: copy running .config → make olddefconfig"
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

    echo ""
    info "Run '${0##*/} prepare' to start the update."
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
        # Same-series: copy running config → olddefconfig
        info "Same-series update: copying running config"
        if $DRY_RUN; then
            info "[dry-run] Would copy running .config → ${KERNEL_SRC}/.config"
            info "[dry-run] Would run: make olddefconfig"
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
            cd "${KERNEL_SRC}"
            make olddefconfig
            info "Config updated via olddefconfig"
        fi
    else
        # Cross-series: prefer kernel_config.sh, fallback to copy
        if [[ -f "${machine_dir}/kernel_config.sh" ]]; then
            info "Cross-series update: defconfig → kernel_config.sh → olddefconfig"
            if $DRY_RUN; then
                info "[dry-run] Would run: make defconfig"
                info "[dry-run] Would run: bash ${machine_dir}/kernel_config.sh"
                info "[dry-run] Would run: make olddefconfig"
            else
                cd "${KERNEL_SRC}"
                make defconfig
                info "Generated defconfig"
                bash "${machine_dir}/kernel_config.sh"
                info "Applied kernel_config.sh"
                make olddefconfig
                info "Resolved dependencies via olddefconfig"
            fi
        else
            warn "No kernel_config.sh found — falling back to .config copy"
            warn "Cross-series config copy may miss new Kconfig options!"
            if $DRY_RUN; then
                info "[dry-run] Would copy running .config → ${KERNEL_SRC}/.config"
                info "[dry-run] Would run: make olddefconfig"
            else
                if [[ -f "/proc/config.gz" ]]; then
                    zcat /proc/config.gz > "${KERNEL_SRC}/.config"
                elif [[ -f "${machine_dir}/.config" ]]; then
                    cp "${machine_dir}/.config" "${KERNEL_SRC}/.config"
                else
                    error "Cannot find any .config source"
                fi
                cd "${KERNEL_SRC}"
                make olddefconfig
            fi
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

    header "Install Kernel"
    if $DRY_RUN; then
        info "[dry-run] Would run: make install"
    else
        make install
        info "Kernel installed"
    fi

    # NVIDIA rebuild
    local gpu_type
    gpu_type=$(get_machine_field "$machine" gpu)
    if [[ "$gpu_type" == "nvidia" ]]; then
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

    # Verify GRUB has both old and new entries
    header "GRUB"
    if $DRY_RUN; then
        info "[dry-run] Would verify GRUB entries"
    else
        if [[ -f /boot/grub/grub.cfg ]]; then
            local grub_entries
            grub_entries=$(grep -c "menuentry " /boot/grub/grub.cfg 2>/dev/null || echo 0)
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
# Written by update-kernel.sh on $(date -Iseconds)
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

    header "Boot Messages"
    local error_count
    error_count=$(dmesg 2>/dev/null | grep -ci -E "(error|fail)" || echo 0)
    if (( error_count == 0 )); then
        info "No errors or failures in dmesg"
    else
        warn "${error_count} lines with error/fail in dmesg"
        dmesg 2>/dev/null | grep -i -E "(error|fail)" | head -10
        if (( error_count > 10 )); then
            warn "... and $(( error_count - 10 )) more (run 'dmesg | grep -i error' to see all)"
        fi
    fi

    header "PCI Drivers"
    local unbound
    unbound=$(lspci -k 2>/dev/null | grep -c "Kernel driver in use:" || echo 0)
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
    local fw_errors
    fw_errors=$(dmesg 2>/dev/null | grep -ci "firmware.*error\|firmware.*fail\|firmware.*missing" || echo 0)
    if (( fw_errors == 0 )); then
        info "No firmware errors in dmesg"
    else
        warn "${fw_errors} firmware-related errors in dmesg:"
        dmesg 2>/dev/null | grep -i "firmware.*error\|firmware.*fail\|firmware.*missing" | head -5
    fi

    header "Services"
    if command -v rc-status &>/dev/null; then
        local failed
        failed=$(rc-status 2>/dev/null | grep -c "crashed\|stopped" || echo 0)
        if (( failed == 0 )); then
            info "All OpenRC services running"
        else
            warn "${failed} services crashed or stopped:"
            rc-status 2>/dev/null | grep -E "crashed|stopped"
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
            nv_dmesg_err=$(dmesg 2>/dev/null | grep -ci "nvidia.*error\|nvrm.*error" || echo 0)
            if (( nv_dmesg_err > 0 )); then
                warn "${nv_dmesg_err} NVIDIA errors in dmesg"
            else
                info "No NVIDIA errors in dmesg"
            fi
            ;;
        intel)
            if lsmod 2>/dev/null | grep -q i915; then
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
        xps-9510|xps-9315|nuc11)
            if lsmod 2>/dev/null | grep -q iwlwifi; then
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
            if lsmod 2>/dev/null | grep -q brcmfmac; then
                info "brcmfmac loaded"
            else
                warn "brcmfmac not loaded"
            fi
            ;;
        surface-pro-6)
            if lsmod 2>/dev/null | grep -q mwifiex; then
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
            if lsmod 2>/dev/null | grep -q applesmc; then
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
            if lsmod 2>/dev/null | grep -q surface_aggregator; then
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
        xps-9510)
            header "Dell Platform"
            if lsmod 2>/dev/null | grep -q dell_smbios; then
                info "dell_smbios loaded"
            fi
            if lsmod 2>/dev/null | grep -q dell_wmi; then
                info "dell_wmi loaded"
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
# Usage
# ============================================================================
usage() {
    cat <<EOF
Usage: ${0##*/} [OPTIONS] COMMAND

Local kernel update tool for production Gentoo machines.

Commands:
  check      Pre-flight: versions, disk, NVIDIA compat, patches, config strategy
  prepare    Backup .config, migrate config, apply patches, lint
  build      Compile kernel with make -j\$(nproc)
  install    Install modules + kernel + NVIDIA rebuild (requires root)
  verify     Post-reboot verification checks
  all        Run prepare + build + install (requires root)

Options:
  --dry-run          Show what would happen without changes
  --machine NAME     Override auto-detection (valid: ${!MACHINES[*]})
  -h, --help         Show this help

Typical workflow:
  1. emerge gentoo-sources && eselect kernel set <N>
  2. ${0##*/} check
  3. ${0##*/} prepare
  4. ${0##*/} build
  5. ${0##*/} install        # as root
  6. reboot
  7. ${0##*/} verify
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

[[ $# -ge 1 ]] || usage

COMMAND="$1"
shift

# Detect machine
MACHINE=$(detect_machine)

if $DRY_RUN; then
    info "[dry-run mode]"
fi

case "$COMMAND" in
    check)   do_check "$MACHINE" ;;
    prepare) do_prepare "$MACHINE" ;;
    build)   do_build ;;
    install) do_install "$MACHINE" ;;
    verify)  do_verify "$MACHINE" ;;
    all)     do_all "$MACHINE" ;;
    *)       error "Unknown command: ${COMMAND}. Run '${0##*/} --help' for usage." ;;
esac
