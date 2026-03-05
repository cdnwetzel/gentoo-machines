#!/bin/bash
# ============================================================================
# kconfig-lint.sh — Static Kernel Config Validator
# ============================================================================
# Validates a kernel_config.sh against actual Kconfig source to catch bugs
# that scripts/config silently ignores and make olddefconfig quietly "fixes".
#
# 5 CHECKS:
#   1. FAIL: --module on bool option (e.g., DELL_SMBIOS_WMI)
#   2. WARN: Missing parent toggle (e.g., X86_PLATFORM_DRIVERS_DELL)
#   3. WARN: Firmware driver set =y (built-in) without initramfs
#   4. WARN: Dependency not satisfied in script order
#   5. INFO: Unknown config option (typos, wrong kernel version)
#
# USAGE:
#   tools/kconfig-lint.sh machines/xps-9510/kernel_config.sh [/usr/src/linux]
#
# DEPENDENCIES: awk, grep, sed, find (all in stage 3 base)
# ============================================================================

set -euo pipefail

# --- Colors (disabled if not a terminal) ---
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    YEL='\033[0;33m'
    BLU='\033[0;34m'
    GRN='\033[0;32m'
    RST='\033[0m'
else
    RED='' YEL='' BLU='' GRN='' RST=''
fi

# --- Usage ---
usage() {
    echo "Usage: $0 <kernel_config.sh> [kernel-source-dir]"
    echo ""
    echo "  kernel_config.sh    Path to a machine's kernel_config.sh"
    echo "  kernel-source-dir   Kernel source (default: /usr/src/linux)"
    exit 1
}

# --- Args ---
[[ $# -lt 1 ]] && usage
CONFIG_SCRIPT="$1"
KSRC="${2:-/usr/src/linux}"

if [[ ! -f "$CONFIG_SCRIPT" ]]; then
    echo "ERROR: Config script not found: $CONFIG_SCRIPT"
    exit 1
fi

if [[ ! -d "$KSRC/kernel" ]] || [[ ! -f "$KSRC/Kconfig" ]]; then
    echo "ERROR: Kernel source not found at: $KSRC"
    echo "  Specify path: $0 $CONFIG_SCRIPT /path/to/linux"
    exit 1
fi

# --- Counters ---
FAILS=0
WARNS=0
INFOS=0

fail() { FAILS=$((FAILS + 1)); echo -e "${RED}FAIL${RST} [line $1] $2"; }
warn() { WARNS=$((WARNS + 1)); echo -e "${YEL}WARN${RST} [line $1] $2"; }
info() { INFOS=$((INFOS + 1)); echo -e "${BLU}INFO${RST} [line $1] $2"; }

# ============================================================================
# PHASE 1: Build Kconfig database
# ============================================================================
# Parse all Kconfig* files → extract per-option:
#   NAME  TYPE  DEPENDS  IF_CONTEXT  SELECTS
# Output: TSV in temp file (~0.2s for full kernel tree)
# ============================================================================

KCONFIG_DB=$(mktemp /tmp/kconfig-db.XXXXXX)
trap 'rm -f "$KCONFIG_DB"' EXIT

echo "Parsing Kconfig files in $KSRC..."

find -L "$KSRC" -name 'Kconfig*' -not -path '*/.git/*' -print0 2>/dev/null | \
    xargs -0 awk '
    # Flush previous symbol when we encounter a new block
    function flush_sym() {
        if (sym != "" && type != "") {
            printf "%s\t%s\t%s\t%s\t%s\n", sym, type, depends, if_ctx, selects
        }
        sym = ""; type = ""; depends = ""; selects = ""; in_help = 0
    }

    # Track if/endif stack for parent context
    /^if[[:space:]]+/ {
        cond = $0
        sub(/^if[[:space:]]+/, "", cond)
        sub(/[[:space:]]*$/, "", cond)
        if_stack[++if_depth] = cond
        next
    }
    /^endif/ {
        if (if_depth > 0) if_depth--
        next
    }

    # config/menuconfig — new symbol (may be indented inside choice blocks)
    /^[[:space:]]*(config|menuconfig)[[:space:]]+[A-Za-z0-9_]+/ {
        flush_sym()
        sym = $2
        type = ""
        depends = ""
        selects = ""
        in_help = 0
        # Build if_context from stack
        if_ctx = ""
        for (i = 1; i <= if_depth; i++) {
            if (if_ctx != "") if_ctx = if_ctx " && "
            if_ctx = if_ctx if_stack[i]
        }
        next
    }

    # Top-level keywords end the current config block
    /^(source|menu[[:space:]]|endmenu|choice|endchoice|comment[[:space:]])/ {
        flush_sym()
        next
    }

    # Skip if no active symbol
    sym == "" { next }

    # Help block: starts with indented "help" or "---help---"
    # Once in help, all deeper-indented text is help until de-indent
    /^[\t ][[:space:]]*(help|---help---)/ {
        in_help = 1
        # Record indentation level of help keyword for de-indent detection
        help_line = $0
        match(help_line, /^[[:space:]]*/)
        help_indent = RLENGTH
        next
    }

    # Inside help block: skip lines indented deeper than the help keyword
    in_help && /^$/ { next }
    in_help {
        match($0, /^[[:space:]]*/)
        if (RLENGTH > help_indent) next
        in_help = 0
    }

    # Properties are tab-indented (single tab)
    /^[\t ][[:space:]]*bool/ { type = "bool" }
    /^[\t ][[:space:]]*boolean/ { type = "bool" }
    /^[\t ][[:space:]]*tristate/ { type = "tristate" }
    /^[\t ][[:space:]]*def_bool/ { type = "bool" }
    /^[\t ][[:space:]]*def_tristate/ { type = "tristate" }
    /^[\t ][[:space:]]*string/ { type = "string" }
    /^[\t ][[:space:]]*int[[:space:]]/ { type = "int" }
    /^[\t ][[:space:]]*hex[[:space:]]/ { type = "hex" }

    # depends on
    /^[\t ][[:space:]]*depends on[[:space:]]+/ {
        dep = $0
        sub(/^[\t ][[:space:]]*depends on[[:space:]]+/, "", dep)
        sub(/[[:space:]]*$/, "", dep)
        if (depends != "") depends = depends " && "
        depends = depends dep
    }

    # select
    /^[\t ][[:space:]]*select[[:space:]]+[A-Za-z0-9_]+/ {
        sel = $0
        sub(/^[\t ][[:space:]]*select[[:space:]]+/, "", sel)
        sub(/[[:space:]].*/, "", sel)
        if (selects != "") selects = selects ","
        selects = selects sel
    }

    END { flush_sym() }
' | sort -u -t$'\t' -k1,1 > "$KCONFIG_DB"

DB_COUNT=$(wc -l < "$KCONFIG_DB")
echo "  Found $DB_COUNT config symbols"
echo ""

# --- Helper: look up a symbol in the database ---
# Returns: TYPE\tDEPENDS\tIF_CONTEXT\tSELECTS  (or empty if not found)
lookup() {
    awk -F'\t' -v sym="$1" '$1 == sym { print $2 "\t" $3 "\t" $4 "\t" $5; exit }' "$KCONFIG_DB"
}

# --- Known firmware-dependent drivers (need =m without initramfs) ---
FW_DRIVERS="DRM_I915 DRM_AMDGPU DRM_XE DRM_NOUVEAU IWLWIFI IWLMVM BRCMFMAC MWIFIEX MWIFIEX_PCIE BT_HCIBTUSB BT_INTEL BT_BCM ATH11K ATH11K_PCI ATH12K ATH12K_PCI MT76_CORE RTW89_CORE RTW89_PCI SND_SOC_SOF_PCI_INTEL_TGL SND_SOC_SOF_PCI_INTEL_MTL SND_HDA_INTEL"

is_fw_driver() {
    local sym="$1"
    for d in $FW_DRIVERS; do
        [[ "$sym" == "$d" ]] && return 0
    done
    return 1
}

# ============================================================================
# PHASE 2: Parse kernel_config.sh for all scripts/config calls
# ============================================================================
# Extract: LINE_NUM  ACTION  SYMBOL
#   ACTION: enable, module, disable, set-val, set-str
# ============================================================================

echo "Checking: $CONFIG_SCRIPT"
echo "Against:  $KSRC ($(cat "$KSRC/Makefile" 2>/dev/null | awk '/^VERSION|^PATCHLEVEL|^SUBLEVEL/ {v[$1]=$3} END {printf "%s.%s.%s", v["VERSION"], v["PATCHLEVEL"], v["SUBLEVEL"]}'))"
echo ""

# Pre-scan: collect ALL symbols set anywhere in the script (for dep checking)
declare -A ALL_SCRIPT_SYMS  # symbol → "y" or "m" (set anywhere in script)
while IFS= read -r prescan_line; do
    if [[ "$prescan_line" =~ \$SC[[:space:]]+--([a-z-]+)[[:space:]]+([A-Za-z0-9_]+) ]] || \
       [[ "$prescan_line" =~ scripts/config[[:space:]]+--([a-z-]+)[[:space:]]+([A-Za-z0-9_]+) ]]; then
        case "${BASH_REMATCH[1]}" in
            enable)  ALL_SCRIPT_SYMS[${BASH_REMATCH[2]}]="y" ;;
            module)  ALL_SCRIPT_SYMS[${BASH_REMATCH[2]}]="m" ;;
        esac
    fi
done < "$CONFIG_SCRIPT"

# Track which symbols are enabled/moduled in script order (for parent toggle check)
declare -A SCRIPT_STATE  # symbol → "y" or "m" (set so far)

# Parse the script
LINE_NUM=0
while IFS= read -r line; do
    LINE_NUM=$((LINE_NUM + 1))

    # Skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    # Match: $SC --enable SYMBOL  or  $SC --module SYMBOL  etc.
    # Also handle: ./scripts/config --enable SYMBOL
    if [[ "$line" =~ \$SC[[:space:]]+--([a-z-]+)[[:space:]]+([A-Za-z0-9_]+) ]] || \
       [[ "$line" =~ scripts/config[[:space:]]+--([a-z-]+)[[:space:]]+([A-Za-z0-9_]+) ]]; then
        ACTION="${BASH_REMATCH[1]}"
        SYMBOL="${BASH_REMATCH[2]}"
    else
        continue
    fi

    # Skip set-val and set-str (not enable/module/disable)
    [[ "$ACTION" == "set-val" ]] && continue
    [[ "$ACTION" == "set-str" ]] && continue

    # Look up symbol in database
    DB_ENTRY=$(lookup "$SYMBOL")

    # --- CHECK 5: Unknown config option ---
    if [[ -z "$DB_ENTRY" ]]; then
        # Check if suppressed with 2>/dev/null || true
        if [[ "$line" =~ 2\>/dev/null ]] || [[ "$line" =~ \|\|[[:space:]]*true ]]; then
            # Script already handles this gracefully
            info "$LINE_NUM" "$SYMBOL: not found in kernel source (handled by script)"
        else
            info "$LINE_NUM" "$SYMBOL: not found in kernel source (typo? wrong kernel version?)"
        fi
        continue
    fi

    SYM_TYPE=$(echo "$DB_ENTRY" | cut -f1)
    SYM_DEPS=$(echo "$DB_ENTRY" | cut -f2)
    SYM_IFCTX=$(echo "$DB_ENTRY" | cut -f3)

    # Track state for dependency checking
    case "$ACTION" in
        enable) SCRIPT_STATE[$SYMBOL]="y" ;;
        module) SCRIPT_STATE[$SYMBOL]="m" ;;
        disable) SCRIPT_STATE[$SYMBOL]="n" ;;
    esac

    # --- CHECK 1: --module on bool option ---
    if [[ "$ACTION" == "module" ]] && [[ "$SYM_TYPE" == "bool" ]]; then
        fail "$LINE_NUM" "$SYMBOL: --module on bool option (type=$SYM_TYPE). Use --enable instead"
    fi

    # --- CHECK 2: Missing parent toggle ---
    # Check if_context: symbols that must be =y for this option to be visible
    if [[ -n "$SYM_IFCTX" ]] && [[ "$ACTION" != "disable" ]]; then
        # Extract simple symbol references from if context
        # e.g., "X86_PLATFORM_DRIVERS_DELL" or "ACPI_DPTF && EXPERT"
        PARENTS=$(echo "$SYM_IFCTX" | grep -oE '[A-Z][A-Z0-9_]+' || true)
        for PARENT in $PARENTS; do
            # Skip common always-on symbols
            case "$PARENT" in
                # Architecture / always-on in defconfig
                X86|X86_64|PCI|ACPI|HAS_IOMEM|HAS_DMA|HAS_IOPORT|MODULES|NET|INET|USB|SND|INPUT|HID|I2C|SPI|GPIOLIB|REGULATOR|SYSFS|PROC_FS|BLOCK|MMU|EXPERT|OF|COMPILE_TEST|PM|THERMAL|HWMON|WATCHDOG|MFD|MEDIA_SUPPORT|DRM|BT|RFKILL|CFG80211|MAC80211|SOUND|TTY|SERIAL_CORE|CRYPTO|STAGING|IIO) continue ;;
                # x86 arch basics (always set by arch/x86/Kconfig via select)
                HAVE_PCI|HAVE_ARCH_TRANSPARENT_HUGEPAGE|HAVE_PREEMPT_DYNAMIC|HAVE_ARCH_SECCOMP|HAVE_ARCH_SECCOMP_FILTER|ARCH_SUPPORTS_ACPI|ARCH_SUPPORTS_SCHED_SMT|ARCH_HIBERNATION_POSSIBLE|CPU_SUP_INTEL|CPU_SUP_AMD|CPU_IDLE|CPU_FREQ|DMI|SHMEM|MULTIUSER|SPARSEMEM_VMEMMAP|X86_PAE|AGP|IRQ_REMAP|INDIRECT_IOMEM) continue ;;
                # ARCH_SUPPORTS_* / HAVE_* / ARCH_* patterns (auto-selected by arch)
                ARCH_SUPPORTS_*|HAVE_*|ARCH_*) continue ;;
                # x86 auto-selected symbols (always set on x86_64)
                X86_LOCAL_APIC|X86_THERMAL_VECTOR|IA32_FEAT_CTL|GENERIC_CLOCKEVENTS|USB_ARCH_HAS_HCD|PAGE_SIZE_LESS_THAN_256KB|SUSPEND_POSSIBLE) continue ;;
                # Non-x86 architectures (irrelevant in OR deps)
                ARM64|RISCV|ARM|MIPS|POWERPC|S390|SPARC|LOONGARCH) continue ;;
                # Subsystem parent menus (always on in any desktop config)
                USB_SUPPORT|HID_SUPPORT|NETDEVICES|NET_CORE|INPUT_MISC|USB_NET_DRIVERS|USB_PCI|NLS|SCSI|LOONGARCH|X86_PLATFORM_DEVICES|DMADEVICES|COMMON_CLK|HIGH_RES_TIMERS|EVENTFD|FB_CORE|BLK_CGROUP|POWERCAP|VIRTUALIZATION|VHOST_MENU|SND_HDA|SND_HDA_CORE|SND_PCI|SND_SOC|SND_HDA|CPU_MITIGATIONS|HYPERVISOR_GUEST|PTP_1588_CLOCK_OPTIONAL|BT_BREDR|IIO_BUFFER|USB_USBNET) continue ;;
            esac
            # Check if parent is set in script before this symbol
            if [[ -z "${SCRIPT_STATE[$PARENT]:-}" ]] || [[ "${SCRIPT_STATE[$PARENT]:-}" == "n" ]]; then
                # Verify parent actually exists in DB (not a Kconfig variable)
                PARENT_ENTRY=$(lookup "$PARENT")
                if [[ -n "$PARENT_ENTRY" ]]; then
                    warn "$LINE_NUM" "$SYMBOL: parent toggle $PARENT not enabled before this line"
                fi
            fi
        done
    fi

    # Also check depends-on for parent toggles
    if [[ -n "$SYM_DEPS" ]] && [[ "$ACTION" != "disable" ]]; then
        # Handle OR deps: split on || and check each branch
        # If ANY branch of an OR dep is satisfied, skip the whole OR group
        # Split deps into AND-separated clauses first
        # e.g., "INTEL_MEI_ME && (DRM_I915 || DRM_XE)" → check each clause
        DEP_SYMS=$(echo "$SYM_DEPS" | grep -oE '[A-Z][A-Z0-9_]+' || true)
        for DEP in $DEP_SYMS; do
            case "$DEP" in
                # Architecture / always-on
                X86|X86_64|PCI|ACPI|HAS_IOMEM|HAS_DMA|HAS_IOPORT|MODULES|NET|INET|USB|SND|INPUT|HID|I2C|SPI|GPIOLIB|REGULATOR|SYSFS|PROC_FS|BLOCK|MMU|EXPERT|OF|COMPILE_TEST|PM|THERMAL|HWMON|WATCHDOG|MFD|MEDIA_SUPPORT|DRM|BT|RFKILL|CFG80211|MAC80211|SOUND|TTY|SERIAL_CORE|CRYPTO|STAGING|IIO) continue ;;
                # x86 arch basics (auto-selected by arch)
                HAVE_PCI|HAVE_ARCH_TRANSPARENT_HUGEPAGE|HAVE_PREEMPT_DYNAMIC|HAVE_ARCH_SECCOMP|HAVE_ARCH_SECCOMP_FILTER|ARCH_SUPPORTS_ACPI|ARCH_SUPPORTS_SCHED_SMT|ARCH_HIBERNATION_POSSIBLE|CPU_SUP_INTEL|CPU_SUP_AMD|CPU_IDLE|CPU_FREQ|DMI|SHMEM|MULTIUSER|SPARSEMEM_VMEMMAP|X86_PAE|AGP|IRQ_REMAP|INDIRECT_IOMEM) continue ;;
                # ARCH_SUPPORTS_* / HAVE_* / *_ARCH_* patterns (auto-selected by arch)
                ARCH_SUPPORTS_*|HAVE_*|ARCH_*) continue ;;
                # x86 auto-selected symbols (always set on x86_64)
                X86_LOCAL_APIC|X86_THERMAL_VECTOR|IA32_FEAT_CTL|GENERIC_CLOCKEVENTS|USB_ARCH_HAS_HCD|PAGE_SIZE_LESS_THAN_256KB|SUSPEND_POSSIBLE) continue ;;
                # Non-x86 architectures (irrelevant in OR deps)
                ARM64|RISCV|ARM|MIPS|POWERPC|S390|SPARC|LOONGARCH) continue ;;
                # Subsystem parent menus
                USB_SUPPORT|HID_SUPPORT|NETDEVICES|NET_CORE|INPUT_MISC|USB_NET_DRIVERS|USB_PCI|NLS|SCSI|LOONGARCH|X86_PLATFORM_DEVICES|DMADEVICES|COMMON_CLK|HIGH_RES_TIMERS|EVENTFD|FB_CORE|BLK_CGROUP|POWERCAP|VIRTUALIZATION|VHOST_MENU|SND_HDA|SND_HDA_CORE|SND_PCI|SND_SOC|CPU_MITIGATIONS|HYPERVISOR_GUEST|PTP_1588_CLOCK_OPTIONAL|BT_BREDR|IIO_BUFFER|USB_USBNET) continue ;;
                # Common lib/feature selections
                LEDS_CLASS|NEW_LEDS|BACKLIGHT_CLASS_DEVICE|VIDEO_DEV|MEDIA_CONTROLLER|DCDBAS|DELL_WMI_DESCRIPTOR|SERIO_I8042) continue ;;
            esac
            # Skip negated deps (e.g., !DRM_NOUVEAU)
            if echo "$SYM_DEPS" | grep -qE "![[:space:]]*$DEP"; then
                continue
            fi
            # Skip OR-dep branches where another branch is satisfied
            # e.g., "DRM_I915 || DRM_XE" — if DRM_I915 is set, skip DRM_XE warning
            if echo "$SYM_DEPS" | grep -qE "[A-Z0-9_]+[[:space:]]*\|\|[[:space:]]*$DEP|$DEP[[:space:]]*\|\|[[:space:]]*[A-Z0-9_]+"; then
                # This dep is part of an OR group — extract all OR siblings
                OR_SATISFIED=false
                OR_GROUP=$(echo "$SYM_DEPS" | grep -oE "[A-Z][A-Z0-9_]+[[:space:]]*(\|\|[[:space:]]*[A-Z][A-Z0-9_]+)+" || true)
                OR_SYMS=$(echo "$OR_GROUP" | grep -oE '[A-Z][A-Z0-9_]+' || true)
                for OR_SYM in $OR_SYMS; do
                    if [[ -n "${ALL_SCRIPT_SYMS[$OR_SYM]:-}" ]]; then
                        OR_SATISFIED=true
                        break
                    fi
                done
                if $OR_SATISFIED; then
                    continue
                fi
            fi
            # Check if dep is set ANYWHERE in the script (not just before this line)
            if [[ -z "${ALL_SCRIPT_SYMS[$DEP]:-}" ]]; then
                DEP_ENTRY=$(lookup "$DEP")
                if [[ -n "$DEP_ENTRY" ]]; then
                    DEP_TYPE=$(echo "$DEP_ENTRY" | cut -f1)
                    if [[ "$DEP_TYPE" == "tristate" ]] || [[ "$DEP_TYPE" == "bool" ]]; then
                        warn "$LINE_NUM" "$SYMBOL: depends on $DEP (not set anywhere in script)"
                    fi
                fi
            fi
        done
    fi

    # --- CHECK 3: Firmware driver set =y (built-in) ---
    if [[ "$ACTION" == "enable" ]] && is_fw_driver "$SYMBOL"; then
        # Only flag tristate (can be =m)
        if [[ "$SYM_TYPE" == "tristate" ]]; then
            warn "$LINE_NUM" "$SYMBOL: firmware-dependent driver set =y (built-in). Use --module unless you have initramfs or EXTRA_FIRMWARE"
        fi
    fi

done < "$CONFIG_SCRIPT"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "--- Summary ---"
TOTAL=$((FAILS + WARNS + INFOS))
if [[ $TOTAL -eq 0 ]]; then
    echo -e "${GRN}All checks passed — no issues found${RST}"
else
    [[ $FAILS -gt 0 ]] && echo -e "${RED}$FAILS FAIL(s)${RST} — config will silently produce wrong values"
    [[ $WARNS -gt 0 ]] && echo -e "${YEL}$WARNS WARN(s)${RST} — potential issues (review recommended)"
    [[ $INFOS -gt 0 ]] && echo -e "${BLU}$INFOS INFO(s)${RST} — informational (may be expected)"
fi
echo ""

# Exit code: 1 if any FAILs, 0 otherwise
[[ $FAILS -gt 0 ]] && exit 1
exit 0
