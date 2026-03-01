# Kernel Patches

## ipu-bridge-fix-double-brace.patch

Fixes a double-brace typo in `drivers/media/pci/intel/ipu-bridge.c` line 195.
Causes build failure with GCC <15.

**Status:** LOCAL PATCH ONLY. Originally reported as
[Bug 970769](https://bugs.gentoo.org/970769), but Sam James confirmed the
typo is not present in official genpatches, the ebuild, or upstream 6.12.y.
Root cause was local filesystem corruption during emerge. Patch kept for
reference but should not be needed on a clean source tree.

**Affects:** Local copy only (not in official gentoo-sources)

## intel_idle-add-tiger-lake.patch

Adds Tiger Lake (0x8D) and Tiger Lake-L (0x8C) to the `intel_idle` CPU
ID table in `drivers/idle/intel_idle.c`. Without this, the driver falls
back to ACPI-enumerated C-states — Dell's BIOS only exposes 3 states
(C1, ~C7, C10) instead of the 8 native SKL-family states (C1, C1E, C3,
C6, C7s, C8, C9, C10).

Maps both to `idle_cpu_skl` / `skl_cstates`, the same table used by
Skylake and Kaby Lake. Safe — the driver validates each MWAIT substate
at boot and skips any the hardware doesn't support.

**Upstream status:** LOCAL PATCH ONLY — not submitting to LKML.

Tiger Lake was never in `intel_idle_ids[]` upstream, and this is intentional.
Starting with Ice Lake client (2019), the kernel maintainer (Rafael Wysocki)
stopped adding client CPUs to the native table, relying instead on ACPI `_CST`
fallback (`18734958e9bf`, Dec 2019). Comet Lake, Ice Lake client, Rocket Lake,
and Raptor Lake patches were either rejected or never merged for the same
reason. The maintainer's position: if ACPI `_CST` exposes insufficient
C-states, that's a firmware bug, not a kernel gap.

**Root cause:** Dell's XPS 9510 BIOS only exposes 3 C-states via ACPI `_CST`
(C1, ~C7, C10) when the hardware supports 8. This is a Dell firmware
deficiency, but the XPS 9510 (2021) is unlikely to receive BIOS updates.

**Our patch works around this** by adding Tiger Lake to the native table,
bypassing the ACPI path entirely. Safe to carry as a local patch — the driver
validates each MWAIT substate at boot and skips unsupported states.

**Investigated:** 2026-03-01 via `torvalds/linux` clone. Verified git history
confirms CML/ICL/TGL/RKL were never in the table (not accidentally removed).

**Affects:** XPS 9510 (i7-11800H), NUC11 (i5-1135G7)
