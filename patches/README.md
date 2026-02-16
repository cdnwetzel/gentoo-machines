# Kernel Patches

## ipu-bridge-fix-double-brace.patch

Fixes a double-brace typo in `drivers/media/pci/intel/ipu-bridge.c` line 195
in `gentoo-sources-6.12.58`. Causes build failure with GCC <15.

**TODO:** Check if this exists in upstream Linux (torvalds/linux) or is
Gentoo-specific, and report to the appropriate bugzilla.
