# Backlog

## High Priority
- [x] Install PipeWire + WirePlumber + xfce4-pulseaudio-plugin + pavucontrol + acpilight
- [x] Run restore-desktop.sh to apply hotkey + panel + PipeWire autostart changes
- [x] Apply intel_idle Tiger Lake patch and rebuild kernel
- [x] Deploy fixed zram-init.conf
- [x] Verify post-reboot: PipeWire, intel_idle, zram, brightness/volume hotkeys
- [x] Fix nvidia-drivers module-rebuild hook (KERNEL_DIR=/usr/src/linux)
- [x] Fix volume hotkeys (remove XFCE bindings that conflict with pulseaudio plugin)

## Medium Priority
- [ ] Enable SCHED_DEBUG in kernel for runtime preempt mode switching
- [ ] Install Gentoo on NUC11 — follow INSTALL.md
- [ ] Test USB-C hub (Anker 7-in-1) — Ethernet/HDMI/SD
- [ ] Test clamshell mode with AOC 34" external

## Low Priority
- [ ] Rename GitHub repo (gentoo_dell_xps9315 → gentoo-machines or similar)
- [ ] Harvest ASRock B550 / Ryzen 9 5950X (Fedora 42)
- [ ] Harvest Dell Precision T5810 (Fedora 42)
- [ ] Harvest Dell Precision 7960 (RHEL 10.1)
- [ ] Harvest Surface Pro 6 (Fedora 43)
- [ ] Harvest Surface Pro 9 (Windows 11 Pro)
- [ ] Report ipu-bridge-fix-double-brace.patch upstream (Gentoo or kernel bugzilla)
- [ ] Submit intel_idle Tiger Lake patch upstream to LKML
