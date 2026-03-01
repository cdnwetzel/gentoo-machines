#!/bin/bash

# Gentoo Hardware Harvest Script - Final Comprehensive Edition
# Purpose: Generate data for an accurate .config kernel build
# Run as: sudo ./harvest.sh

LOG_FILE="hardware_inventory.log"

# Ensure we are root for dmidecode and dmesg
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root to gather all hardware data." 
   exit 1
fi

echo "--- GENTOO HARDWARE HARVEST START ---" | tee "$LOG_FILE"
date >> "$LOG_FILE"

# 1. PCI Devices (Identify Bridge, GPU, Audio, Network)
echo -e "\n[1. PCI DEVICES - CORE HARDWARE]" >> "$LOG_FILE"
lspci -nnk >> "$LOG_FILE"

# 2. CPU Architecture (Identify P-Cores/E-Cores & Optimization Flags)
echo -e "\n[2. CPU DETAILS - SCHEDULER & OPTIMIZATION]" >> "$LOG_FILE"
lscpu | grep -E 'Model name|Vendor ID|CPU family|Model:|Flags' >> "$LOG_FILE"

# 3. Motherboard & BIOS (Identify Chipset & Laptop Specifics)
echo -e "\n[3. MOTHERBOARD/DMI - CHIPSET]" >> "$LOG_FILE"
if command -v dmidecode &> /dev/null; then
    dmidecode -t 0,2 | grep -E 'Vendor|Product Name|Version|Release Date' >> "$LOG_FILE"
else
    echo "dmidecode not found. Reading from sysfs..." >> "$LOG_FILE"
    for f in board_vendor board_name board_version bios_vendor bios_version; do
        [ -f "/sys/class/dmi/id/$f" ] && echo "$f: $(cat "/sys/class/dmi/id/$f")" >> "$LOG_FILE"
    done
fi

# 4. I2C / Touchpad / Serial Buses (Crucial for Laptops)
echo -e "\n[4. I2C / SERIAL BUSES - INPUT DEVICES]" >> "$LOG_FILE"
if [ -d /sys/bus/i2c/devices ]; then
    for dev in /sys/bus/i2c/devices/*; do
        if [ -f "$dev/name" ]; then
            echo "Bus Device: $(cat "$dev/name") ($(basename "$dev"))" >> "$LOG_FILE"
        fi
    done
else
    echo "No I2C buses detected." >> "$LOG_FILE"
fi

# 5. USB Topology
echo -e "\n[5. USB DEVICES - PERIPHERALS]" >> "$LOG_FILE"
lsusb -t >> "$LOG_FILE"

# 6. Current Module Baseline (What is working now?)
echo -e "\n[6. CURRENTLY LOADED MODULES]" >> "$LOG_FILE"
lsmod >> "$LOG_FILE"

# 7. AUTOMATED FIRMWARE SHOPPING LIST (For CONFIG_EXTRA_FIRMWARE)
echo -e "\n[7. KERNEL CONFIG SUGGESTION: FIRMWARE]" >> "$LOG_FILE"
echo "If building drivers into kernel (Y), use this list:" >> "$LOG_FILE"

# Try dmesg first, fall back to journalctl if dmesg buffer has rotated
FW_LIST=$(dmesg 2>/dev/null | grep -i "firmware: direct-loading" | awk '{print $NF}' | sort -u | tr '\n' ' ')

if [ -z "$FW_LIST" ] && command -v journalctl &> /dev/null; then
    FW_LIST=$(journalctl -k -b --no-pager 2>/dev/null | grep -i "firmware: direct-loading" | awk '{print $NF}' | sort -u | tr '\n' ' ')
fi

if [ -n "$FW_LIST" ]; then
    echo "CONFIG_EXTRA_FIRMWARE=\"$FW_LIST\"" | tee -a "$LOG_FILE"
    echo "CONFIG_EXTRA_FIRMWARE_DIR=\"/lib/firmware\"" | tee -a "$LOG_FILE"
else
    echo "No firmware detected via dmesg or journalctl." >> "$LOG_FILE"
    echo "If system has been running a while, dmesg may have rotated. Try running shortly after boot." >> "$LOG_FILE"
fi

# 8. Storage Controller Check
echo -e "\n[8. STORAGE - DRIVE CONTROLLER]" >> "$LOG_FILE"
lsblk -o NAME,FSTYPE,MOUNTPOINT,SIZE >> "$LOG_FILE"

# 9. CPU_FLAGS_X86 (for make.conf CPU_FLAGS_X86 variable)
echo -e "\n[9. CPU_FLAGS_X86]" >> "$LOG_FILE"
if command -v cpuid2cpuflags &> /dev/null; then
    cpuid2cpuflags >> "$LOG_FILE"
else
    echo "cpuid2cpuflags not available — falling back to /proc/cpuinfo" >> "$LOG_FILE"
    echo "  Install: emerge app-portage/cpuid2cpuflags" >> "$LOG_FILE"
    # Fallback: extract flags from /proc/cpuinfo, filter to Gentoo-relevant set
    if [ -f /proc/cpuinfo ]; then
        RAW_FLAGS=$(grep -m1 '^flags' /proc/cpuinfo | cut -d: -f2)
        # Map to CPU_FLAGS_X86 names (subset that Gentoo uses)
        GENTOO_FLAGS=""
        for flag in $RAW_FLAGS; do
            case "$flag" in
                aes)       GENTOO_FLAGS="$GENTOO_FLAGS aes" ;;
                avx)       GENTOO_FLAGS="$GENTOO_FLAGS avx" ;;
                avx2)      GENTOO_FLAGS="$GENTOO_FLAGS avx2" ;;
                avx512f)   GENTOO_FLAGS="$GENTOO_FLAGS avx512f" ;;
                avx512bw)  GENTOO_FLAGS="$GENTOO_FLAGS avx512bw" ;;
                avx512cd)  GENTOO_FLAGS="$GENTOO_FLAGS avx512cd" ;;
                avx512dq)  GENTOO_FLAGS="$GENTOO_FLAGS avx512dq" ;;
                avx512vl)  GENTOO_FLAGS="$GENTOO_FLAGS avx512vl" ;;
                avx512vbmi) GENTOO_FLAGS="$GENTOO_FLAGS avx512vbmi" ;;
                avx512_vnni) GENTOO_FLAGS="$GENTOO_FLAGS avx512_vnni" ;;
                avx_vnni)  GENTOO_FLAGS="$GENTOO_FLAGS avx_vnni" ;;
                f16c)      GENTOO_FLAGS="$GENTOO_FLAGS f16c" ;;
                fma|fma3)  GENTOO_FLAGS="$GENTOO_FLAGS fma3" ;;
                fma4)      GENTOO_FLAGS="$GENTOO_FLAGS fma4" ;;
                mmx)       GENTOO_FLAGS="$GENTOO_FLAGS mmx" ;;
                mmxext)    GENTOO_FLAGS="$GENTOO_FLAGS mmxext" ;;
                pclmulqdq) GENTOO_FLAGS="$GENTOO_FLAGS pclmul" ;;
                popcnt)    GENTOO_FLAGS="$GENTOO_FLAGS popcnt" ;;
                sha_ni)    GENTOO_FLAGS="$GENTOO_FLAGS sha" ;;
                sse)       GENTOO_FLAGS="$GENTOO_FLAGS sse" ;;
                sse2)      GENTOO_FLAGS="$GENTOO_FLAGS sse2" ;;
                sse3)      GENTOO_FLAGS="$GENTOO_FLAGS sse3" ;;
                ssse3)     GENTOO_FLAGS="$GENTOO_FLAGS ssse3" ;;
                sse4_1)    GENTOO_FLAGS="$GENTOO_FLAGS sse4_1" ;;
                sse4_2)    GENTOO_FLAGS="$GENTOO_FLAGS sse4_2" ;;
                sse4a)     GENTOO_FLAGS="$GENTOO_FLAGS sse4a" ;;
                3dnow)     GENTOO_FLAGS="$GENTOO_FLAGS 3dnow" ;;
                3dnowext)  GENTOO_FLAGS="$GENTOO_FLAGS 3dnowext" ;;
                vpclmulqdq) GENTOO_FLAGS="$GENTOO_FLAGS vpclmulqdq" ;;
            esac
        done
        GENTOO_FLAGS=$(echo "$GENTOO_FLAGS" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/^ *//;s/ *$//')
        echo "CPU_FLAGS_X86 (approximate): $GENTOO_FLAGS" >> "$LOG_FILE"
        echo "  WARNING: Install cpuid2cpuflags for authoritative list" >> "$LOG_FILE"
    fi
fi

# 10. Audio Subsystem (SOF vs HDA detection)
echo -e "\n[10. AUDIO SUBSYSTEM]" >> "$LOG_FILE"
# Check loaded audio modules
for mod in snd_hda_intel snd_sof_pci_intel_tgl snd_sof_pci_intel_cnl snd_sof_pci_intel_mtl snd_sof_pci snd_hda_codec_realtek snd_hda_codec_hdmi snd_hda_codec_cs420x snd_hda_codec_generic; do
    if lsmod 2>/dev/null | grep -qw "${mod//-/_}"; then
        echo "  Active: $mod" >> "$LOG_FILE"
    fi
done
# HDA codec info
if [ -d /proc/asound ]; then
    for card in /proc/asound/card*/codec*; do
        if [ -f "$card" ]; then
            echo "  Codec: $(head -3 "$card" | tr '\n' ' ')" >> "$LOG_FILE"
        fi
    done 2>/dev/null
fi
# Classify
if lsmod 2>/dev/null | grep -q "snd_sof"; then
    echo "  Type: SOF (Sound Open Firmware)" >> "$LOG_FILE"
elif lsmod 2>/dev/null | grep -q "snd_hda_intel"; then
    echo "  Type: HDA (HD Audio legacy)" >> "$LOG_FILE"
else
    echo "  Type: Unknown (no audio module loaded)" >> "$LOG_FILE"
fi

# 11. Platform Vendor (DMI system info)
echo -e "\n[11. PLATFORM VENDOR]" >> "$LOG_FILE"
for f in sys_vendor product_name product_family chassis_type product_version; do
    if [ -f "/sys/class/dmi/id/$f" ]; then
        echo "  $f: $(cat "/sys/class/dmi/id/$f")" >> "$LOG_FILE"
    fi
done
# Classify vendor for platform driver selection
SYS_VENDOR=""
[ -f /sys/class/dmi/id/sys_vendor ] && SYS_VENDOR=$(cat /sys/class/dmi/id/sys_vendor)
case "$SYS_VENDOR" in
    *Dell*)     echo "  Platform: DELL (X86_PLATFORM_DRIVERS_DELL)" >> "$LOG_FILE" ;;
    *Apple*)    echo "  Platform: APPLE (APPLE_PROPERTIES, SENSORS_APPLESMC)" >> "$LOG_FILE" ;;
    *Lenovo*)   echo "  Platform: LENOVO (THINKPAD_ACPI or IDEAPAD_LAPTOP)" >> "$LOG_FILE" ;;
    *HP*|*Hewlett*) echo "  Platform: HP (HP_WMI)" >> "$LOG_FILE" ;;
    *Microsoft*) echo "  Platform: SURFACE (SURFACE_PLATFORMS)" >> "$LOG_FILE" ;;
    *ASUS*)     echo "  Platform: ASUS (ASUS_WMI)" >> "$LOG_FILE" ;;
    *Intel*)    echo "  Platform: INTEL (generic, no vendor platform driver)" >> "$LOG_FILE" ;;
    *AMD*|*Micro-Star*|*MSI*) echo "  Platform: $(echo "$SYS_VENDOR" | head -c 20) (check vendor WMI)" >> "$LOG_FILE" ;;
    *)          echo "  Platform: GENERIC ($SYS_VENDOR)" >> "$LOG_FILE" ;;
esac

# 12. Boot Type (EFI vs BIOS)
echo -e "\n[12. BOOT TYPE]" >> "$LOG_FILE"
if [ -d /sys/firmware/efi ]; then
    echo "  Boot: EFI" >> "$LOG_FILE"
    # EFI bitness
    if [ -f /sys/firmware/efi/fw_platform_size ]; then
        EFI_BITS=$(cat /sys/firmware/efi/fw_platform_size)
        echo "  EFI bitness: ${EFI_BITS}-bit" >> "$LOG_FILE"
        if [ "$EFI_BITS" = "32" ]; then
            echo "  Kernel: CONFIG_EFI_MIXED=y (32-bit EFI on 64-bit CPU)" >> "$LOG_FILE"
        fi
    fi
    # Secure Boot
    if [ -d /sys/firmware/efi/efivars ]; then
        SB_VAR=$(find /sys/firmware/efi/efivars -name 'SecureBoot-*' 2>/dev/null | head -1)
        if [ -n "$SB_VAR" ] && [ -f "$SB_VAR" ]; then
            # Last byte: 0=off, 1=on
            SB_STATE=$(od -An -t u1 -j4 -N1 "$SB_VAR" 2>/dev/null | tr -d ' ')
            if [ "$SB_STATE" = "1" ]; then
                echo "  Secure Boot: ENABLED" >> "$LOG_FILE"
            else
                echo "  Secure Boot: DISABLED" >> "$LOG_FILE"
            fi
        else
            echo "  Secure Boot: variable not readable" >> "$LOG_FILE"
        fi
    fi
else
    echo "  Boot: BIOS (legacy)" >> "$LOG_FILE"
    echo "  Kernel: No EFI_STUB needed" >> "$LOG_FILE"
fi

# 13. Suspend Capabilities
echo -e "\n[13. SUSPEND CAPABILITIES]" >> "$LOG_FILE"
if [ -f /sys/power/state ]; then
    echo "  /sys/power/state: $(cat /sys/power/state)" >> "$LOG_FILE"
fi
if [ -f /sys/power/mem_sleep ]; then
    echo "  /sys/power/mem_sleep: $(cat /sys/power/mem_sleep)" >> "$LOG_FILE"
    if grep -q '\[s2idle\]' /sys/power/mem_sleep 2>/dev/null; then
        echo "  Active mode: s2idle (Modern Standby)" >> "$LOG_FILE"
    elif grep -q '\[deep\]' /sys/power/mem_sleep 2>/dev/null; then
        echo "  Active mode: deep (S3 traditional suspend)" >> "$LOG_FILE"
    fi
    if grep -qw 'deep' /sys/power/mem_sleep 2>/dev/null; then
        echo "  S3 deep: supported" >> "$LOG_FILE"
    else
        echo "  S3 deep: NOT supported (s2idle only)" >> "$LOG_FILE"
    fi
fi
if [ -f /sys/power/disk ]; then
    echo "  Hibernate: $(cat /sys/power/disk)" >> "$LOG_FILE"
fi

# 14. Loaded Firmware Files (module → firmware mapping)
echo -e "\n[14. LOADED FIRMWARE]" >> "$LOG_FILE"
# Method 1: Check /sys/module/*/firmware/ for loaded firmware references
FW_FOUND=0
for mod_dir in /sys/module/*/; do
    mod_name=$(basename "$mod_dir")
    # Check if module has firmware loading info in dmesg
    FW_FILES=$(dmesg 2>/dev/null | grep -i "firmware.*$mod_name\|$mod_name.*firmware" | grep -oP '/lib/firmware/\S+' | sort -u)
    if [ -n "$FW_FILES" ]; then
        echo "  Module $mod_name:" >> "$LOG_FILE"
        echo "$FW_FILES" | while read -r fw; do
            echo "    $fw" >> "$LOG_FILE"
        done
        FW_FOUND=1
    fi
done
# Method 2: Scan dmesg for all firmware loads
if [ "$FW_FOUND" = "0" ]; then
    FW_DMESG=$(dmesg 2>/dev/null | grep -i "firmware: direct-loading" | sed 's/.*firmware: direct-loading firmware /  /' | sort -u)
    if [ -n "$FW_DMESG" ]; then
        echo "$FW_DMESG" >> "$LOG_FILE"
    else
        echo "  No firmware loading detected in dmesg (buffer may have rotated)" >> "$LOG_FILE"
    fi
fi
# Also check what firmware files exist for loaded modules
echo "  --- Firmware files on disk for loaded modules ---" >> "$LOG_FILE"
if [ -d /lib/firmware ]; then
    lsmod 2>/dev/null | awk 'NR>1 {print $1}' | while read -r mod; do
        case "$mod" in
            i915)     find /lib/firmware/i915/ -name '*.bin' 2>/dev/null | head -5 | sed 's/^/    /' >> "$LOG_FILE" ;;
            iwlwifi)  find /lib/firmware/ -name 'iwlwifi-*.ucode' 2>/dev/null | head -3 | sed 's/^/    /' >> "$LOG_FILE" ;;
            brcmfmac) find /lib/firmware/brcm/ -name 'brcmfmac*' 2>/dev/null | head -5 | sed 's/^/    /' >> "$LOG_FILE" ;;
            mwifiex*) find /lib/firmware/mrvl/ -name '*8897*' 2>/dev/null | head -3 | sed 's/^/    /' >> "$LOG_FILE" ;;
            btusb|btintel|btbcm|btmrvl*) find /lib/firmware/intel/ -name 'ibt-*' 2>/dev/null | head -3 | sed 's/^/    /' >> "$LOG_FILE" ;;
            amdgpu)   find /lib/firmware/amdgpu/ -name '*.bin' 2>/dev/null | head -3 | sed 's/^/    /' >> "$LOG_FILE" ;;
            nvidia*)  echo "    nvidia: firmware embedded in driver" >> "$LOG_FILE" ;;
        esac
    done
fi

# 15. GCC -march Suggestion
echo -e "\n[15. GCC -march SUGGESTION]" >> "$LOG_FILE"
if [ -f /proc/cpuinfo ]; then
    VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
    FAMILY=$(grep -m1 'cpu family' /proc/cpuinfo | awk '{print $4}')
    MODEL=$(grep -m1 '^model[[:space:]]*:' /proc/cpuinfo | awk '{print $3}')
    echo "  vendor=$VENDOR family=$FAMILY model=$MODEL" >> "$LOG_FILE"

    MARCH="unknown"
    if [ "$VENDOR" = "GenuineIntel" ]; then
        case "${FAMILY}:${MODEL}" in
            # Broadwell
            6:61|6:71)    MARCH="broadwell" ;;
            # Skylake
            6:78|6:94)    MARCH="skylake" ;;
            # Kaby Lake / Coffee Lake / Whiskey Lake (GCC: -march=skylake)
            6:142|6:158)  MARCH="skylake" ;;
            # Comet Lake
            6:165|6:166)  MARCH="skylake" ;;
            # Ice Lake
            6:126|6:125)  MARCH="icelake-client" ;;
            # Tiger Lake
            6:140|6:141)  MARCH="tigerlake" ;;
            # Alder Lake
            6:151|6:154)  MARCH="alderlake" ;;
            # Raptor Lake
            6:183|6:186)  MARCH="raptorlake" ;;
            # Meteor Lake
            6:170)        MARCH="meteorlake" ;;
            # Older
            6:60|6:69|6:70) MARCH="haswell" ;;
            6:58|6:62)    MARCH="ivybridge" ;;
            6:42|6:45)    MARCH="sandybridge" ;;
            *)            MARCH="x86-64-v3" ;;
        esac
    elif [ "$VENDOR" = "AuthenticAMD" ]; then
        case "${FAMILY}:${MODEL}" in
            # Zen 3 (Vermeer, Cezanne)
            25:33|25:80|25:68) MARCH="znver3" ;;
            25:*)              MARCH="znver3" ;;
            # Zen 4 (Raphael, Phoenix)
            26:*)              MARCH="znver4" ;;
            # Zen 2 (Matisse, Renoir)
            23:113|23:96)      MARCH="znver2" ;;
            23:*)              MARCH="znver2" ;;
            # Zen 1
            23:1|23:8|23:17)   MARCH="znver1" ;;
            # Bulldozer family
            21:*)              MARCH="bdver2" ;;
            *)                 MARCH="x86-64-v3" ;;
        esac
    fi

    echo "  Suggested: -march=$MARCH" >> "$LOG_FILE"
    echo "  For make.conf: COMMON_FLAGS=\"-march=$MARCH -O2 -pipe\"" >> "$LOG_FILE"

    # Note about GCC version requirements
    case "$MARCH" in
        alderlake|raptorlake)
            echo "  NOTE: Requires GCC 11+ for -march=$MARCH" >> "$LOG_FILE" ;;
        meteorlake)
            echo "  NOTE: Requires GCC 14+ for -march=$MARCH" >> "$LOG_FILE" ;;
        tigerlake)
            echo "  NOTE: Requires GCC 10+ for -march=$MARCH" >> "$LOG_FILE" ;;
        znver3)
            echo "  NOTE: Requires GCC 11+ for -march=$MARCH" >> "$LOG_FILE" ;;
        znver4)
            echo "  NOTE: Requires GCC 13+ for -march=$MARCH" >> "$LOG_FILE" ;;
    esac
fi

echo -e "\n--- HARVEST COMPLETE ---"
echo "Full inventory saved to: $(pwd)/$LOG_FILE"
