# Kernel Patches

## ipu-bridge-fix-double-brace.patch

Fixes a double-brace typo in `drivers/media/pci/intel/ipu-bridge.c` line 195
in `gentoo-sources-6.12.58`. Causes build failure with GCC <15.

**Upstream status:** FIXED in mainline Linux. `torvalds/linux` master has
the correct single-brace `if (!csi_dev) {` at line 217. This is a
Gentoo-specific issue — likely a backport error in the gentoo-sources 6.12.x
patchset.

**Reported:** [Bug 970769](https://bugs.gentoo.org/970769) — filed 2026-03-01.
No LKML submission needed.

**Affects:** gentoo-sources-6.12.58 only (not upstream)

## intel_idle-add-tiger-lake.patch

Adds Tiger Lake (0x8D) and Tiger Lake-L (0x8C) to the `intel_idle` CPU
ID table in `drivers/idle/intel_idle.c`. Without this, the driver falls
back to ACPI-enumerated C-states — Dell's BIOS only exposes 3 states
(C1, ~C7, C10) instead of the 8 native SKL-family states (C1, C1E, C3,
C6, C7s, C8, C9, C10).

Maps both to `idle_cpu_skl` / `skl_cstates`, the same table used by
Skylake and Kaby Lake. Safe — the driver validates each MWAIT substate
at boot and skips any the hardware doesn't support.

**Upstream status:** STILL MISSING in mainline Linux as of v6.15+.
`INTEL_TIGERLAKE` and `INTEL_TIGERLAKE_L` are not in `intel_idle_ids[]`
in `torvalds/linux` master. This is a legitimate candidate for LKML
submission.

**Submission target:** linux-pm@vger.kernel.org (Rafael Wysocki maintains
intel_idle). Patch formatted for `git send-email`.

**Affects:** XPS 9510 (i7-11800H), NUC11 (i5-1135G7)
