#!/bin/bash
set -e

URL_SCRIPT="https://raw.githubusercontent.com/KnowLedZ/Wizzard/main/cpanel-wizzard.sh"

echo "[INFO] Downloading installer..."
curl -L -f "$URL_SCRIPT" -o /root/cpanel-installer.sh

chmod +x /root/cpanel-installer.sh

echo "[OK] Installer downloaded"
echo ""

echo "[INFO] Running installer..."
echo ""

# ✅ BLOCKING (WAJIB, supaya tidak lanjut sebelum selesai)
exec bash /root/cpanel-installer.sh
