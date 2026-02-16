#!/bin/bash
#
# Generate a Gentoo kernel .config and make.conf for a new machine
# by analyzing harvest data with Claude.
#
# Prerequisites:
#   - Claude CLI installed (claude command available)
#   - Harvest data collected on target machine (harvest.sh + deep_harvest.sh)
#   - An existing base .config from a similar machine
#
# Usage:
#   ./generate-config.sh <new-machine-name> <base-machine> <harvest-dir>
#
# Example:
#   ./generate-config.sh precision-t5810 xps-9315 /tmp/t5810-harvest/
#
# The script will:
#   1. Read harvest data (hardware_inventory.log, deep_harvest.log)
#   2. Read the base machine's .config
#   3. Use Claude to analyze differences and generate:
#      - machines/<new-machine>/.config (modified kernel config)
#      - machines/<new-machine>/make.conf (with correct -march and settings)
#      - machines/<new-machine>/HARDWARE.md (from harvest data)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

# --- Helpers ---
info()  { echo -e "\033[1;32m>>>\033[0m $*"; }
warn()  { echo -e "\033[1;33m>>>\033[0m $*"; }
error() { echo -e "\033[1;31m>>>\033[0m $*" >&2; exit 1; }

usage() {
    echo "Usage: $0 <new-machine-name> <base-machine> <harvest-dir>"
    echo ""
    echo "Arguments:"
    echo "  new-machine-name  Directory name for the new machine (e.g., precision-t5810)"
    echo "  base-machine      Existing machine to use as base (e.g., xps-9315, nuc11)"
    echo "  harvest-dir       Directory containing harvest logs from the target machine"
    echo ""
    echo "The harvest-dir should contain:"
    echo "  - hardware_inventory.log  (from harvest.sh)"
    echo "  - deep_harvest.log        (from deep_harvest.sh)"
    echo ""
    echo "Example:"
    echo "  # First, run on the target machine:"
    echo "  sudo tools/harvest.sh"
    echo "  sudo -E tools/deep_harvest.sh"
    echo "  # Copy the logs, then run:"
    echo "  $0 precision-t5810 nuc11 /tmp/t5810-harvest/"
    exit 1
}

# --- Validate ---
[[ $# -eq 3 ]] || usage

NEW_MACHINE="$1"
BASE_MACHINE="$2"
HARVEST_DIR="$3"

# Check claude is available
command -v claude &>/dev/null || error "Claude CLI not found. Install from: https://claude.ai/code"

# Check base machine exists
BASE_DIR="${REPO_DIR}/machines/${BASE_MACHINE}"
[[ -f "${BASE_DIR}/.config" ]] || error "Base machine config not found: ${BASE_DIR}/.config"
[[ -f "${BASE_DIR}/make.conf" ]] || error "Base machine make.conf not found: ${BASE_DIR}/make.conf"

# Check harvest data exists
[[ -f "${HARVEST_DIR}/hardware_inventory.log" ]] || error "hardware_inventory.log not found in ${HARVEST_DIR}"
[[ -f "${HARVEST_DIR}/deep_harvest.log" ]] || error "deep_harvest.log not found in ${HARVEST_DIR}"

# Create output directory
NEW_DIR="${REPO_DIR}/machines/${NEW_MACHINE}"
mkdir -p "${NEW_DIR}"

info "Generating config for '${NEW_MACHINE}' based on '${BASE_MACHINE}'"
info "Harvest data: ${HARVEST_DIR}"
info "Output: ${NEW_DIR}"

# --- Step 1: Generate HARDWARE.md ---
info ""
info "=== Step 1/3: Generating HARDWARE.md ==="

claude -p "You are analyzing hardware inventory data for a Linux machine.
Create a HARDWARE.md file in the same format as the example below.

Example format (from another machine):
$(cat "${BASE_DIR}/HARDWARE.md" 2>/dev/null || echo "See machines/xps-9315/HARDWARE.md for format")

Hardware inventory data:
$(cat "${HARVEST_DIR}/hardware_inventory.log")

Deep harvest data:
$(cat "${HARVEST_DIR}/deep_harvest.log")

Generate ONLY the HARDWARE.md content, no explanation. Include all PCI devices, CPU info, networking, storage, audio, graphics, platform drivers, and firmware sections." > "${NEW_DIR}/HARDWARE.md"

info "Created ${NEW_DIR}/HARDWARE.md"

# --- Step 2: Generate make.conf ---
info ""
info "=== Step 2/3: Generating make.conf ==="

claude -p "You are generating a Gentoo Linux make.conf for a new machine.

Base make.conf (from ${BASE_MACHINE}):
$(cat "${BASE_DIR}/make.conf")

New machine hardware:
$(cat "${HARVEST_DIR}/hardware_inventory.log" | head -30)

CPU info from harvest:
$(grep -A5 'CPU DETAILS\|Model name\|Vendor ID\|Flags' "${HARVEST_DIR}/hardware_inventory.log" 2>/dev/null || grep -A5 'CPU DETAILS\|Model name\|Vendor ID\|Flags' "${HARVEST_DIR}/deep_harvest.log" 2>/dev/null || echo "See harvest data")

PCI GPU info:
$(grep -i 'vga\|3d controller\|display' "${HARVEST_DIR}/hardware_inventory.log" 2>/dev/null || echo "See harvest data")

Rules:
1. Set -march= to match the CPU microarchitecture (e.g., tigerlake, alderlake, znver3, broadwell, sapphirerapids)
2. Use dynamic MAKEOPTS: MAKEOPTS=\"-j\$(nproc)\" and EMERGE_DEFAULT_OPTS=\"--jobs=2 --load-average=\$(nproc)\"
3. Set VIDEO_CARDS appropriately (intel iris for Intel GPU, nvidia for NVIDIA, amdgpu radeonsi for AMD)
4. If NVIDIA GPU detected, add nvidia to VIDEO_CARDS
5. Keep all other settings the same as base unless hardware demands changes
6. Output ONLY the make.conf content, no explanation" > "${NEW_DIR}/make.conf"

info "Created ${NEW_DIR}/make.conf"

# --- Step 3: Generate kernel .config ---
info ""
info "=== Step 3/3: Generating kernel .config modifications ==="
info "This step analyzes harvest data against the base config to identify needed changes."

# Copy base config first
cp "${BASE_DIR}/.config" "${NEW_DIR}/.config"

# Generate a diff/patch script
PATCH_SCRIPT=$(claude -p "You are a Linux kernel configuration expert. Compare the hardware in the base machine (${BASE_MACHINE}) against a new target machine and generate a shell script that modifies the kernel .config using sed commands.

Base machine hardware (${BASE_MACHINE}):
$(cat "${BASE_DIR}/HARDWARE.md" 2>/dev/null | head -100 || echo "See base config")

New machine hardware inventory:
$(cat "${HARVEST_DIR}/hardware_inventory.log")

New machine deep harvest (loaded modules and PCI devices):
$(cat "${HARVEST_DIR}/deep_harvest.log")

Base kernel config options to check (key driver-related lines):
$(grep -E 'CONFIG_(IGC|SATA_AHCI|ATA=|PARPORT|MTD|SPI_INTEL|EDAC|IGEN6|INTEL_MEI|INTEL_ISH|INTEL_HFI|SCHED_MC_PRIO|VIDEO_INTEL_IPU|DELL_|X86_PLATFORM_DRIVERS_DELL|TYPEC_TPS|INTEL_POWERCLAMP|SERIAL_MULTI|EEPROM_EE1004|ACPI_TAD|SND_SOC_SOF|DRM_I915|DRM_NOUVEAU|DRM_AMDGPU|AMD_IOMMU|CPU_SUP_AMD|CPU_SUP_INTEL|E1000E|R8169|IXGBE|MLX|NVME|BLK_DEV_SD|IWLWIFI|IWLMVM|THUNDERBOLT|USB4|INTEL_SKL_INT3472|VIDEO_OV01A10)' "${BASE_DIR}/.config" 2>/dev/null)

Rules:
1. For each PCI device in the NEW machine that has a 'Kernel modules:' line, ensure that module is enabled (=m) in the config
2. For each driver enabled in the BASE config that corresponds to hardware NOT present in the NEW machine, disable it
3. Use sed commands that operate on the config file at: ${NEW_DIR}/.config
4. For enabling: change '# CONFIG_X is not set' to 'CONFIG_X=m' (or =y for subsystems)
5. For disabling: change 'CONFIG_X=m' or 'CONFIG_X=y' to '# CONFIG_X is not set'
6. Handle dependency chains (e.g., ATA needs CONFIG_ATA=m before SATA_AHCI=m)
7. Output ONLY a bash script with sed commands, no explanation, no markdown fences
8. Start with #!/bin/bash and set -e")

# Execute the patch script
echo "${PATCH_SCRIPT}" > "${NEW_DIR}/.config.patch.sh"
chmod +x "${NEW_DIR}/.config.patch.sh"

info "Generated patch script: ${NEW_DIR}/.config.patch.sh"
info "Applying config patches..."

bash "${NEW_DIR}/.config.patch.sh"

info "Created ${NEW_DIR}/.config"

# --- Summary ---
info ""
info "============================================"
info "Config generation complete for ${NEW_MACHINE}"
info "============================================"
info ""
info "Generated files:"
info "  ${NEW_DIR}/.config       - Kernel configuration"
info "  ${NEW_DIR}/make.conf     - Portage build settings"
info "  ${NEW_DIR}/HARDWARE.md   - Hardware documentation"
info "  ${NEW_DIR}/.config.patch.sh - Patch script (for reference)"
info ""
info "Next steps:"
info "  1. Review the generated files, especially .config changes"
info "  2. On the target machine (after Gentoo base install):"
info "     cp machines/${NEW_MACHINE}/.config /usr/src/linux/"
info "     cd /usr/src/linux && make olddefconfig"
info "     # olddefconfig will resolve any dependency issues"
info "     make -j\$(nproc) && make modules_install && make install"
info "  3. Boot and verify with: lspci -k && dmesg | grep -i error"
info ""
info "The .config.patch.sh can be deleted after verifying the config works."
