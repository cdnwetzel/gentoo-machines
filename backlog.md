# Backlog

## High Priority
- [x] Install PipeWire + WirePlumber + xfce4-pulseaudio-plugin + pavucontrol + acpilight
- [x] Run restore-desktop.sh to apply hotkey + panel + PipeWire autostart changes
- [x] Apply intel_idle Tiger Lake patch and rebuild kernel
- [x] Deploy fixed zram-init.conf
- [x] Verify post-reboot: PipeWire, intel_idle, zram, brightness/volume hotkeys
- [x] Fix nvidia-drivers module-rebuild hook (KERNEL_DIR=/usr/src/linux)
- [x] Fix volume hotkeys (remove XFCE bindings that conflict with pulseaudio plugin)
- [x] Fix module-rebuild hook environment leak (`env -i` to isolate from kernel make vars)
- [x] Configure SSTP VPN (PS VPN) — sstpc + pppd + NM, PAP auth for Duo MFA
- [x] Add PPP kernel modules (CONFIG_PPP=m, MPPE, ASYNC, etc.) for SSTP VPN
- [x] Configure VPN DNS (10.0.0.42/40, corp.local search domain)
- [x] Set up Remmina RDP profile (server01.corp.local)
- [x] Set up Remmina SSH profile (ssh.example.com, key auth)
- [x] Add Remmina launcher to XFCE bottom dock panel

## Medium Priority
- [x] Enable SCHED_DEBUG in kernel for runtime preempt mode switching
- [ ] Install Gentoo on NUC11 — follow INSTALL.md
- [ ] Test USB-C hub (Anker 7-in-1) — HDMI + USB 3.0 devices (hub detected, PD working)
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
