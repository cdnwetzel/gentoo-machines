# Dell XPS 15 9510 - Post-Reboot Checklist

**Date**: 2026-02-22
**Kernel**: 6.12.58-gentoo (modules: i915, iwlwifi, cfg80211, mac80211, nvidia)

## Immediate Verification

### 1. Check WiFi
```bash
# Verify iwlwifi loaded with firmware
dmesg | grep iwlwifi
# Should show: loaded firmware version 77... QuZ-a0-hr-b0-77.ucode

# Check interface is up
ip link show wlp0s20f3

# Connect to WiFi (should auto-connect if NM profiles exist)
nmcli device status
nmcli connection show

# If not auto-connected:
nmcli device wifi list
nmcli device wifi connect "SSID" password "PASSWORD"
```

### 2. Check GPU (Intel + NVIDIA)
```bash
# Intel i915 firmware loaded
dmesg | grep i915
# Should show: Finished loading DMC firmware i915/tgl_dmc_ver2_12.bin

# NVIDIA driver loaded
nvidia-smi
# Should show RTX 3050 Ti with driver 590.48

# Check for GPU errors
dmesg | grep -iE 'error|fail' | grep -iE 'i915|nvidia|drm'
```

### 3. Check Bluetooth
```bash
bluetoothctl show
# Should show controller with address

bluetoothctl power on
bluetoothctl scan on
# Pair devices as needed
```

### 4. Check Services
```bash
rc-status default
# Should show: NetworkManager, bluetooth, acpid, dbus, display-manager,
#              metalog, sshd all started
```

### 5. Check Audio
```bash
aplay -l
# Should show Tiger Lake-H HD Audio
```

## Desktop Configuration

### 6. Restore XFCE Settings (as chris, in GUI)
```bash
cd /data/gentoo_dell_xps9315
bash shared/restore-desktop.sh
```
This restores: keyboard shortcuts, panel layout, display profiles, xhost autostart.

### 7. Restore System Settings (as root)
```bash
cd /data/gentoo_dell_xps9315
sudo bash shared/restore-system.sh
```
This restores: elogind config, ACPI lid toggle, LightDM display setup.

## Git Push

### 8. Push Repo Changes
```bash
cd /data/gentoo_dell_xps9315
git config user.name "Chris Wetzel"
git config user.email "chris@cwetzel.com"
git remote set-url origin git@github.com:cdnwetzel/gentoo_dell_xps9315.git
# Or use HTTPS with token:
# git remote set-url origin https://<TOKEN>@github.com/cdnwetzel/gentoo_dell_xps9315.git
git push origin main
```

### 9. Clone Repo to Home (optional)
```bash
cd ~
git clone /data/gentoo_dell_xps9315
# Or from GitHub after push:
# git clone git@github.com:cdnwetzel/gentoo_dell_xps9315.git
```

## Python / AI ML Environment

### 10. Activate ML Virtual Environment
```bash
source ~/venvs/ml/bin/activate

# Verify CUDA works with PyTorch
python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'GPU: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"N/A\"}')"

# Verify key packages
python3 -c "import sentence_transformers; print('sentence-transformers OK')"
python3 -c "import chromadb; print('chromadb OK')"
python3 -c "import pyodbc; print('pyodbc OK')"
python3 -c "import langchain; print('langchain OK')"
```

### 11. Test MSSQL ODBC Connection
```python
import pyodbc
# List available drivers
print(pyodbc.drivers())
# Should include: 'ODBC Driver 18 for SQL Server'

# Test connection (adjust server/db):
# conn = pyodbc.connect('DRIVER={ODBC Driver 18 for SQL Server};SERVER=your_server;DATABASE=your_db;UID=user;PWD=pass;TrustServerCertificate=yes')
```

### 12. nvm / Node.js
```bash
# nvm is already installed, reload shell or:
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# System node is already installed (v24), but nvm lets you manage versions:
nvm list
node --version
npm --version
```

## Optional - Not Yet Installed

### CUDA Toolkit (for compiling CUDA code directly)
```bash
# Unmask and install (large download ~5.7GB)
echo "dev-util/nvidia-cuda-toolkit ~amd64" >> /etc/portage/package.accept_keywords/cuda
emerge -av dev-util/nvidia-cuda-toolkit
```

### Docker (for containerized AI workloads)
```bash
emerge -av app-containers/docker
rc-update add docker default
usermod -aG docker chris
# Reboot or newgrp docker
```

### Additional Python Dev Tools (install in venvs as needed)
```bash
pip install black flake8 mypy pytest pre-commit
```

### LibreOffice (long compile time)
```bash
emerge -av app-office/libreoffice
```

## Known Issues

- **UCSI USB-C errors**: `ucsi_acpi USBC000:00: error -ENODEV` — harmless, occurs when no USB-C devices are plugged in at boot
- **i8042 Keylock warning**: `i8042: Warning: Keylock active` — cosmetic, doesn't affect keyboard
- **polkit rules directories**: Missing `/run/polkit-1/rules.d` — created at runtime, warning is harmless
- **NVIDIA GPU idle**: The RTX 3050 Ti won't show in `lspci -k` as using nvidia driver until an application requests it (PRIME/Optimus). Use `nvidia-smi` to verify driver is loaded.

## Installed Package Summary

| Category | Packages |
|----------|----------|
| **Desktop** | XFCE, LightDM, nm-applet, blueman |
| **Browsers** | Google Chrome, Microsoft Edge |
| **Editors** | VS Code, Geany, Mousepad |
| **Dev** | Git, Node.js 24, npm, nvm, Python 3.13, pip |
| **AI/ML** | PyTorch+CUDA, sentence-transformers, transformers, langchain, chromadb, faiss, openai, jupyter |
| **Database** | unixODBC, MSSQL ODBC 18.6, pyodbc |
| **Remote** | Remmina (RDP/VNC/SSH), OpenSSH server, sshfs |
| **VPN** | NetworkManager SSTP |
| **Monitoring** | btop, htop, nvtop, lm-sensors, neofetch |
| **CLI** | tmux, jq, tree, xclip, tesseract, zip/unzip |
| **GPU** | nvidia-drivers 590.48, Intel i915 (module) |
| **Bluetooth** | bluez, blueman, btusb/btintel (kernel) |
