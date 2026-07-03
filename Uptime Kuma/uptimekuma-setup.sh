#!/bin/bash
set -e

URL_SCRIPT="https://raw.githubusercontent.com/CentauRA-ID/Wizzard/main/Uptime%20Kuma/uptimekuma-wizzard.sh"

echo "======================================"
echo "  UPTIME KUMA BOOTSTRAP INITIALIZER"
echo "======================================"
echo ""

echo "[INFO] Downloading installer..."
curl -L -f "$URL_SCRIPT" -o /root/uptime-kuma-installer.sh

chmod +x /root/uptime-kuma-installer.sh

echo "[OK] Installer downloaded"
echo ""

echo "[INFO] Running installer..."
echo ""

# ✅ BLOCKING (WAJIB, supaya tidak lanjut sebelum selesai)
exec bash /root/uptime-kuma-installer.sh
