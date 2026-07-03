#!/bin/bash
set -e

URL_SCRIPT="https://raw.githubusercontent.com/KnowLedZ/Wizzard/main/wireguard-wizzard.sh"

echo "======================================"
echo "     WIREGUARD BOOTSTRAP INITIALIZER"
echo "======================================"
echo ""

echo "[INFO] Downloading installer..."
curl -L -f "$URL_SCRIPT" -o /root/wireguard-installer.sh

chmod +x /root/wireguard-installer.sh

echo "[OK] Installer downloaded"
echo ""

echo "[INFO] Running installer..."
echo ""

# ✅ BLOCKING (WAJIB, supaya tidak lanjut sebelum selesai)
exec bash /root/wireguard-installer.sh
