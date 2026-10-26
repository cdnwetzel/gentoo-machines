#!/bin/bash
set -e

# OptiPlex 3080 (i3-10105 Comet Lake-S, B460, UHD 630, RTL8168h, SATA SSD, SOF CNL audio)
# Derived from nuc11 base. Run `make olddefconfig` afterwards to resolve dependencies.

CFG="$(cd "$(dirname "$0")" && pwd)/.config"

if [ ! -f "$CFG" ]; then
    echo "ERROR: $CFG not found (copy machines/nuc11/.config there first)" >&2
    exit 1
fi

# Portable in-place sed: works on both GNU sed and BSD/macOS sed
_sed() { sed -i.bak -E "$1" "$CFG"; rm -f "$CFG.bak"; }

# set_opt NAME VALUE: works whether the option is currently set, unset, or missing
set_opt() {
    local name="$1" val="$2"
    if grep -qE "^(# )?CONFIG_${name}( is not set|=)" "$CFG"; then
        _sed "s/^# CONFIG_${name} is not set\$/CONFIG_${name}=${val}/"
        _sed "s/^CONFIG_${name}=.*/CONFIG_${name}=${val}/"
    else
        echo "CONFIG_${name}=${val}" >> "$CFG"
    fi
}

# unset_opt NAME: changes =y/=m/=value to "is not set"
unset_opt() {
    local name="$1"
    if grep -qE "^CONFIG_${name}=" "$CFG"; then
        _sed "s/^CONFIG_${name}=.*/# CONFIG_${name} is not set/"
    fi
}

# ---------------------------------------------------------------------------
# Storage: the root disk is SATA (sda, 223.6G) behind AHCI and there is no initramfs,
# so ATA and AHCI MUST be built in (=y). As modules the root disk could not be mounted at boot.
# The PCI class reads "RAID bus controller" but ahci is the bound driver.
# Make sure the BIOS SATA mode is AHCI, not RAID/RST (same trap as optiplex-3090).
# ---------------------------------------------------------------------------
set_opt ATA y
set_opt ATA_ACPI y
set_opt SATA_HOST y
set_opt SATA_AHCI y
set_opt SATA_MOBILE_LPM_POLICY 3
set_opt BLK_DEV_SD y
# NVMe left enabled: no NVMe in the current harvest, but the board has an M.2 slot
set_opt NVME_CORE y
set_opt BLK_DEV_NVME y

# ---------------------------------------------------------------------------
# Networking: Realtek RTL8111/8168 (r8169, rev 15 = RTL8168h)
# This driver loads firmware (rtl_nic/rtl8168h-2.fw) and there is no initramfs, so build it as a module.
# ---------------------------------------------------------------------------
set_opt NET_VENDOR_REALTEK y
set_opt R8169 m
set_opt REALTEK_PHY m

# Not present: Intel e1000e / igc NICs
unset_opt E1000E
unset_opt E1000E_HWTS
unset_opt IGC

# Not present: no WiFi/BT (OptiPlex 3080 SFF/MT, wired only)
unset_opt IWLWIFI
unset_opt IWLMVM
unset_opt IWLWIFI_LEDS
unset_opt IWLWIFI_OPMODE_MODULAR
unset_opt IWLWIFI_DEVICE_TRACING

# ---------------------------------------------------------------------------
# Graphics: CometLake-S GT2 UHD 630 [8086:9bc8]. i915 is a module because it loads kbl_dmc firmware.
# ---------------------------------------------------------------------------
set_opt DRM_I915 m

# ---------------------------------------------------------------------------
# Audio: Comet Lake PCH-V cAVS [8086:a3f0], Realtek ALC3246 + Intel HDMI
# Modules: snd_hda_intel, snd_sof_pci_intel_cnl, snd_soc_avs
# ---------------------------------------------------------------------------
set_opt SND_HDA_INTEL m
set_opt SND_HDA_CODEC_REALTEK m
set_opt SND_HDA_CODEC_ALC269 m
set_opt SND_HDA_CODEC_HDMI m
set_opt SND_HDA_CODEC_HDMI_INTEL m
set_opt SND_HDA_CODEC_GENERIC m
set_opt SND_SOC_SOF_TOPLEVEL y
set_opt SND_SOC_SOF_PCI m
set_opt SND_SOC_SOF_INTEL_TOPLEVEL y
set_opt SND_SOC_SOF_INTEL_CNL m
set_opt SND_SOC_SOF_COMETLAKE m
set_opt SND_SOC_SOF_HDA_LINK y
set_opt SND_SOC_SOF_HDA_AUDIO_CODEC y
set_opt SND_SOC_INTEL_AVS m

# Not present: Tiger Lake / Alder Lake SOF platforms
unset_opt SND_SOC_SOF_TIGERLAKE
unset_opt SND_SOC_SOF_ALDERLAKE
unset_opt SND_SOC_SOF_INTEL_TGL

# ---------------------------------------------------------------------------
# Chipset / platform: B460 PCH-V
# ---------------------------------------------------------------------------
set_opt I2C_I801 m
set_opt EEPROM_EE1004 m
set_opt INTEL_MEI y
set_opt INTEL_MEI_ME y
set_opt INTEL_MEI_HDCP m
set_opt INTEL_MEI_PXP m
set_opt PINCTRL_SUNRISEPOINT m
set_opt INTEL_PMC_CORE m
set_opt ITCO_WDT m
set_opt ITCO_VENDOR_SUPPORT y
set_opt INTEL_OC_WATCHDOG m
set_opt INTEL_VSEC m
set_opt INTEL_PMT_TELEMETRY m
set_opt INTEL_RAPL m
set_opt INTEL_UNCORE_FREQ_CONTROL m
set_opt INTEL_TCC_COOLING m
set_opt INTEL_POWERCLAMP m
set_opt X86_PKG_TEMP_THERMAL m
set_opt SENSORS_CORETEMP m
set_opt ACPI_PAD m

# Not present: Tiger Lake IBECC EDAC (and this machine has non-ECC DIMMs)
unset_opt IGEN6_EDAC

# Not present: exposed SPI flash controller (nuc11-only)
unset_opt SPI_INTEL_PCI
unset_opt MTD_SPI_NOR

# Not present: Thunderbolt 4 / USB4 and the TPS6598x USB-C PD controller
unset_opt USB4
unset_opt TYPEC_TPS6598X

# Not present: parallel port
unset_opt PARPORT_PC
unset_opt PARPORT_PC_FIFO
unset_opt PARPORT_PC_SUPERIO
unset_opt PARPORT

# Not present: AMD CPU / IOMMU
unset_opt AMD_IOMMU
unset_opt CPU_SUP_AMD

# ---------------------------------------------------------------------------
# Dell platform drivers (dell_wmi, dell_smbios, dell_wmi_sysman, dell_smm_hwmon, dcdbas)
# DELL_SMBIOS_WMI and DELL_SMBIOS_SMM are bool options (=y), not tristate.
# Desktop chassis, so DELL_LAPTOP, DELL_RBTN, DELL_SMO8800 and DELL_WMI_AIO stay off.
# ---------------------------------------------------------------------------
set_opt ACPI_WMI m
set_opt WMI_BMOF m
set_opt X86_PLATFORM_DEVICES y
set_opt X86_PLATFORM_DRIVERS_DELL y
set_opt DCDBAS m
set_opt DELL_SMBIOS m
set_opt DELL_SMBIOS_WMI y
set_opt DELL_SMBIOS_SMM y
set_opt DELL_WMI m
set_opt DELL_WMI_DESCRIPTOR m
set_opt DELL_WMI_SYSMAN m
set_opt FW_ATTR_CLASS m
set_opt SENSORS_DELL_SMM m

echo "optiplex-3080 config adjustments applied to $CFG"
echo "Next: make olddefconfig, then tools/kconfig-lint.sh."
echo "Secure Boot is ENABLED in the BIOS. Disable it, or sign the kernel and modules, before booting this kernel."
