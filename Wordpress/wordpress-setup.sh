#!/bin/bash
set -e

URL_SCRIPT="https://raw.githubusercontent.com/KnowLedZ/Wizzard/main/wordpress-wizzard.sh"

echo "[INFO] Downloading installer..."
curl -L -f "$URL_SCRIPT" -o /root/wordpress-installer.sh

chmod +x /root/wordpress-installer.sh

echo "[OK] Installer downloaded"
echo ""

echo "[INFO] Running installer..."
echo ""

# ✅ BLOCKING (WAJIB, supaya tidak lanjut sebelum selesai)
exec bash /root/wordpress-installer.sh
