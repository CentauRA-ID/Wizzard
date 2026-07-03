#!/bin/bash -e

#
#   cPanel Installer
#   -----------------
#   Support: AlmaLinux & Rocky Linux 8, 9, 10
#   Instalasi berjalan di background, hanya tampilkan hasil/error.
#
#   Cara pakai: sudo bash cpanel-install.sh
#

# ─── Warna ──────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

clear
printf "${GREEN}+────────────────────────────────────────+\n"
printf "|        cPanel Installer                |\n"
printf "|  AlmaLinux & Rocky Linux 8 / 9 / 10   |\n"
printf "+────────────────────────────────────────+${NC}\n\n"

# ─── Cek Root ───────────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    printf "${RED}Harus dijalankan sebagai root: sudo bash cpanel-install.sh${NC}\n"
    exit 1
fi

# ════════════════════════════════════════════════════════════════════════════════
# PILIHAN BAHASA / LANGUAGE SELECTION
# ════════════════════════════════════════════════════════════════════════════════
printf "${BLUE}Language / Bahasa:${NC}\n"
printf "  1) Bahasa Indonesia\n"
printf "  2) English\n\n"
printf "${BLUE}Pilihan / Choice (1/2): ${NC}"; read -r lang_choice

if [ "$lang_choice" == "2" ]; then
    T_DETECT_OS="Detecting OS"
    T_OS_UNSUPPORTED="Unsupported OS. This script only supports AlmaLinux and Rocky Linux 8/9/10."
    T_OS_FOUND="OS detected"
    T_CHECK_HOSTNAME="Checking hostname"
    T_HOSTNAME_LABEL="Hostname (e.g. server.yourdomain.com)"
    T_HOSTNAME_SET="Hostname set to"
    T_HOSTNAME_INVALID="Hostname must be a valid FQDN (e.g. server.domain.com)"
    T_DISABLE_SELINUX="Disabling SELinux"
    T_SELINUX_DONE="SELinux set to permissive"
    T_DISABLE_FIREWALL="Stopping firewalld (cPanel manages its own firewall)"
    T_UPDATE="Updating system packages"
    T_UPDATE_DONE="System updated"
    T_INSTALL_DEPS="Installing dependencies"
    T_DEPS_DONE="Dependencies ready"
    T_CONFIRM="Start cPanel installation? (Y/n)"
    T_CANCELLED="Installation cancelled."
    T_STARTING="Starting cPanel installation in background"
    T_WAIT="This will take 20-40 minutes. You can monitor the log"
    T_LOG_FILE="Installation log"
    T_DONE_TITLE="cPanel Installation Complete!"
    T_DONE_ACCESS="Access WHM to complete setup"
    T_DONE_URL="https://YOUR_SERVER_IP:2087"
    T_ERROR_TITLE="Installation Failed!"
    T_ERROR_CHECK="Check the log for details"
    T_MONITORING="Monitoring installation"
    T_PROGRESS="Progress"
    T_ELAPSED="Elapsed"
    T_MINUTES="minutes"
else
    T_DETECT_OS="Mendeteksi OS"
    T_OS_UNSUPPORTED="OS tidak didukung. Script ini hanya support AlmaLinux dan Rocky Linux 8/9/10."
    T_OS_FOUND="OS terdeteksi"
    T_CHECK_HOSTNAME="Mengecek hostname"
    T_HOSTNAME_LABEL="Hostname (contoh: server.domainmu.com)"
    T_HOSTNAME_SET="Hostname diset ke"
    T_HOSTNAME_INVALID="Hostname harus berupa FQDN yang valid (contoh: server.domain.com)"
    T_DISABLE_SELINUX="Menonaktifkan SELinux"
    T_SELINUX_DONE="SELinux diset ke permissive"
    T_DISABLE_FIREWALL="Menghentikan firewalld (cPanel punya firewall sendiri)"
    T_UPDATE="Update paket sistem"
    T_UPDATE_DONE="Sistem terupdate"
    T_INSTALL_DEPS="Menginstall dependency"
    T_DEPS_DONE="Dependency siap"
    T_CONFIRM="Mulai instalasi cPanel? (Y/n)"
    T_CANCELLED="Instalasi dibatalkan."
    T_STARTING="Memulai instalasi cPanel di background"
    T_WAIT="Proses ini memakan waktu 20-40 menit. Pantau log di"
    T_LOG_FILE="File log instalasi"
    T_DONE_TITLE="Instalasi cPanel Selesai!"
    T_DONE_ACCESS="Akses WHM untuk menyelesaikan setup"
    T_DONE_URL="https://IP_SERVER_KAMU:2087"
    T_ERROR_TITLE="Instalasi Gagal!"
    T_ERROR_CHECK="Periksa log untuk detail error"
    T_MONITORING="Memantau instalasi"
    T_PROGRESS="Progres"
    T_ELAPSED="Waktu berjalan"
    T_MINUTES="menit"
fi

LOG_FILE="/var/log/cpanel-install.log"
SERVER_IP=$(hostname -I | awk '{print $1}')

# ─── Deteksi OS ─────────────────────────────────────────────────────────────────
printf '\n'
printf "${BLUE}[ ${T_DETECT_OS} ]${NC}\n"

if [ ! -f /etc/os-release ]; then
    printf "${RED}${T_OS_UNSUPPORTED}${NC}\n"
    exit 1
fi

source /etc/os-release
OS_NAME="${NAME}"
OS_ID="${ID}"
OS_VERSION="${VERSION_ID%%.*}"   # ambil major version saja (8, 9, atau 10)
OS_FULL="${NAME} ${VERSION_ID}"

# Validasi OS
if [[ "$OS_ID" != "almalinux" && "$OS_ID" != "rocky" ]]; then
    printf "${RED}${T_OS_UNSUPPORTED}${NC}\n"
    printf "${RED}OS saat ini: ${OS_FULL}${NC}\n"
    exit 1
fi

# Validasi versi
if [[ "$OS_VERSION" != "8" && "$OS_VERSION" != "9" && "$OS_VERSION" != "10" ]]; then
    printf "${RED}${T_OS_UNSUPPORTED}${NC}\n"
    printf "${RED}Versi: ${VERSION_ID} (butuh 8, 9, atau 10)${NC}\n"
    exit 1
fi

printf "${GREEN}✅ ${T_OS_FOUND}: ${OS_FULL}${NC}\n"

# ─── Cek & Set Hostname ─────────────────────────────────────────────────────────
printf '\n'
printf "${BLUE}[ ${T_CHECK_HOSTNAME} ]${NC}\n"

CURRENT_HOSTNAME=$(hostname -f 2>/dev/null || hostname)
printf "${YELLOW}Hostname saat ini: ${CURRENT_HOSTNAME}${NC}\n"

printf "${BLUE}${T_HOSTNAME_LABEL} [${CURRENT_HOSTNAME}]: ${NC}"; read -r input_hostname
input_hostname=${input_hostname:-$CURRENT_HOSTNAME}

# Validasi FQDN (minimal ada satu titik)
if ! echo "$input_hostname" | grep -qP '^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+$'; then
    printf "${RED}${T_HOSTNAME_INVALID}${NC}\n"
    exit 1
fi

hostnamectl set-hostname "$input_hostname"
printf "${GREEN}✅ ${T_HOSTNAME_SET}: ${input_hostname}${NC}\n"

# ─── Konfirmasi ─────────────────────────────────────────────────────────────────
printf '\n'
printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "  OS       : ${OS_FULL}\n"
printf "  Hostname : ${input_hostname}\n"
printf "  IP       : ${SERVER_IP}\n"
printf "  Log      : ${LOG_FILE}\n"
printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"

printf "${BLUE}${T_CONFIRM} ${NC}"; read -r run
if [ "$run" == "n" ] || [ "$run" == "N" ]; then
    printf "${RED}${T_CANCELLED}${NC}\n"
    exit 0
fi

# ─── Persiapan Sistem ───────────────────────────────────────────────────────────
printf '\n'
printf "${BLUE}[ ${T_DISABLE_SELINUX} ]${NC}\n"
setenforce 0 2>/dev/null || true
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
sed -i 's/^SELINUX=enabled/SELINUX=permissive/' /etc/selinux/config
printf "${GREEN}✅ ${T_SELINUX_DONE}${NC}\n"

printf '\n'
printf "${BLUE}[ ${T_DISABLE_FIREWALL} ]${NC}\n"
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true
printf "${GREEN}✅ ${T_DONE:-Done}${NC}\n"

printf '\n'
printf "${BLUE}[ ${T_UPDATE} ]${NC}\n"
dnf update -y -q >> "${LOG_FILE}" 2>&1
printf "${GREEN}✅ ${T_UPDATE_DONE}${NC}\n"

printf '\n'
printf "${BLUE}[ ${T_INSTALL_DEPS} ]${NC}\n"
dnf install -y -q curl perl wget >> "${LOG_FILE}" 2>&1
printf "${GREEN}✅ ${T_DEPS_DONE}${NC}\n"

# ─── Download Installer cPanel ──────────────────────────────────────────────────
printf '\n'
printf "${BLUE}[ Download cPanel Installer ]${NC}\n"
curl -fsSL -o /root/latest https://securedownloads.cpanel.net/latest
printf "${GREEN}✅ Installer downloaded${NC}\n"

# ─── Jalankan Instalasi di Background ──────────────────────────────────────────
printf '\n'
printf "${GREEN}[ ${T_STARTING} ]${NC}\n"
printf "${YELLOW}📄 ${T_WAIT}: ${LOG_FILE}${NC}\n\n"

# Jalankan installer di background, output ke log
nohup sh /root/latest >> "${LOG_FILE}" 2>&1 &
CPANEL_PID=$!

printf "${BLUE}PID: ${CPANEL_PID}${NC}\n\n"

# ─── Monitor Progress ───────────────────────────────────────────────────────────
printf "${BLUE}[ ${T_MONITORING} ]${NC}\n"
printf "${YELLOW}(Ctrl+C untuk keluar dari monitor, instalasi tetap berjalan di background)${NC}\n\n"

START_TIME=$(date +%s)
LAST_LINE=""

while kill -0 "$CPANEL_PID" 2>/dev/null; do
    NOW=$(date +%s)
    ELAPSED=$(( (NOW - START_TIME) / 60 ))

    # Ambil baris terakhir dari log yang bukan kosong
    CURRENT_LINE=$(grep -v '^[[:space:]]*$' "${LOG_FILE}" 2>/dev/null | tail -1 | cut -c1-70)

    if [ "$CURRENT_LINE" != "$LAST_LINE" ] && [ -n "$CURRENT_LINE" ]; then
        printf "\r${BLUE}[${T_ELAPSED}: ${ELAPSED} ${T_MINUTES}]${NC} ${CURRENT_LINE}%-20s\n" ""
        LAST_LINE="$CURRENT_LINE"
    else
        printf "\r${BLUE}[${T_ELAPSED}: ${ELAPSED} ${T_MINUTES}]${NC} %-80s" "..."
    fi

    sleep 5
done

# ─── Cek Hasil Instalasi ────────────────────────────────────────────────────────
printf '\n\n'
wait "$CPANEL_PID" 2>/dev/null
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && command -v whmapi1 &>/dev/null; then
    printf "${GREEN}╔══════════════════════════════════════════════╗\n"
    printf "║   ✅  ${T_DONE_TITLE}         ║\n"
    printf "╚══════════════════════════════════════════════╝${NC}\n\n"

    printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  WHM   : https://${SERVER_IP}:2087\n"
    printf "  cPanel: https://${SERVER_IP}:2083\n"
    printf "  FTP   : ftp://${SERVER_IP}:21\n"
    printf "  Email : ${SERVER_IP}:25\n"
    printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"
    printf "  ${T_DONE_ACCESS}:\n"
    printf "  ${BLUE}https://${SERVER_IP}:2087${NC}\n\n"
    printf "  ${T_LOG_FILE}: ${LOG_FILE}\n\n"
else
    printf "${RED}╔══════════════════════════════════════════════╗\n"
    printf "║   ❌  ${T_ERROR_TITLE}                ║\n"
    printf "╚══════════════════════════════════════════════╝${NC}\n\n"
    printf "${RED}${T_ERROR_CHECK}:${NC}\n"
    printf "${YELLOW}  tail -100 ${LOG_FILE}${NC}\n\n"

    # Tampilkan 30 baris terakhir log yang mengandung error
    printf "${RED}[ Last errors from log ]${NC}\n"
    grep -iE 'error|fail|fatal|critical' "${LOG_FILE}" 2>/dev/null | tail -20 | while read -r line; do
        printf "${RED}  ${line}${NC}\n"
    done
    printf '\n'
fi


    RUN_SERVICE_COMMANDS: |
      dashboard | ls -lah
      dashboard | cat /etc/os-release
