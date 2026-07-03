#!/bin/bash
set -Eeuo pipefail

# =========================================================
# COLOR
# =========================================================
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
NC="\e[0m"

LOG_FILE="/var/log/coolify-install.log"
: > "$LOG_FILE"

# =========================================================
# STATUS / SPINNER
# =========================================================
spinner() {
    local pid=$1
    local msg="$2"
    local spin='-\|/'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) %4 ))

        printf "\r${CYAN}[INFO]${NC} %s ${spin:$i:1}" "$msg"

        sleep 0.1
    done

    wait "$pid"
    local exit_code=$?

    printf "\r\033[K"

    if [ $exit_code -eq 0 ]; then
        printf "${GREEN}[OK]${NC} %s\n" "$msg"
    else
        printf "${RED}[FAIL]${NC} %s\n" "$msg"

        echo ""
        echo -e "${RED}[ERROR] Installer gagal!${NC}"
        echo -e "${YELLOW}[INFO]${NC} Check log: $LOG_FILE"
        echo ""

        tail -n 20 "$LOG_FILE" || true
        exit 1
    fi
}

# =========================================================
# ROOT CHECK
# =========================================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Please run as root${NC}"
    exit 1
fi

# =========================================================
# DETECT OS
# =========================================================
if [ -f /etc/os-release ]; then
    . /etc/os-release

    OS_ID=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
    OS_NAME="$PRETTY_NAME"
else
    echo -e "${RED}[ERROR] Cannot detect OS${NC}"
    exit 1
fi

SUPPORTED=false

case "$OS_ID" in
    ubuntu|debian|rocky|almalinux|alma|centos|rhel)
        SUPPORTED=true
    ;;
esac

if [ "$SUPPORTED" != true ]; then
    echo -e "${RED}[ERROR] Unsupported OS: $OS_ID${NC}"
    exit 1
fi

# =========================================================
# HEADER
# =========================================================
clear
echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}              COOLIFY INSTALLER WIZARD              ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""

# =========================
# PROMPT
# =========================
read -p "Start coolify installation wizard? (Y/n): " CONFIRM
CONFIRM=${CONFIRM:-Y}

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Installation cancelled.${NC}"
    exit 0
fi

echo ""

# =========================================================
# STEP 1
# =========================================================
echo -e "${YELLOW}----------------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 1/3] Prepare system${NC}"
echo -e "${YELLOW}----------------------------------------------------${NC}"

# =========================================================
# PREPARE PACKAGE MANAGER
# =========================================================
(
    if [[ "$OS_ID" =~ ^(ubuntu|debian)$ ]]; then

        export DEBIAN_FRONTEND=noninteractive

        sleep 5

        while \
            fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
            fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
            fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
            fuser /var/cache/apt/archives/lock >/dev/null 2>&1
        do
            sleep 2
        done

        rm -f /var/lib/dpkg/lock*
        rm -f /var/lib/apt/lists/lock
        rm -f /var/cache/apt/archives/lock

        dpkg --configure -a >> "$LOG_FILE" 2>&1 || true

	else

	    sleep 5

	    while \
	        fuser /var/lib/rpm/.rpm.lock >/dev/null 2>&1 || \
	        pgrep -x dnf >/dev/null 2>&1 || \
	        pgrep -x yum >/dev/null 2>&1 || \
	        pgrep -x rpm >/dev/null 2>&1
	    do
	        sleep 2
	    done

	    rm -f /var/lib/rpm/.rpm.lock

	    if command -v dnf >/dev/null 2>&1; then
	        dnf makecache >> "$LOG_FILE" 2>&1 || true
	    else
 	       yum makecache >> "$LOG_FILE" 2>&1 || true
    	fi
fi) &

STEP1_PID=$!

spinner "$STEP1_PID" "Preparing package manager"

echo -e "${GREEN}[OK]${NC} Package manager ready"

# =========================================================
# INSTALL WGET
# =========================================================
if ! command -v wget >/dev/null 2>&1; then

    (
        if [[ "$OS_ID" =~ ^(ubuntu|debian)$ ]]; then

            apt update -y >> "$LOG_FILE" 2>&1
            apt install -y wget >> "$LOG_FILE" 2>&1

        else

            if command -v dnf >/dev/null 2>&1; then
                dnf install -y wget >> "$LOG_FILE" 2>&1
            else
                yum install -y wget >> "$LOG_FILE" 2>&1
            fi
        fi
    ) &

    WGET_PID=$!

    spinner "$WGET_PID" "Installing dependency: wget"

fi

echo -e "${GREEN}[OK]${NC} All dependencies ready"

echo ""


# =========================================================
# STEP 2
# =========================================================
echo -e "${YELLOW}----------------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 2/3] Install coolify${NC}"
echo -e "${YELLOW}----------------------------------------------------${NC}"

(
    wget -q -O /root/install.sh https://raw.githubusercontent.com/KnowLedZ/Wizzard/main/coolify-install.sh \
        >> "$LOG_FILE" 2>&1

    chmod +x /root/install.sh
) &
spinner $! "Downloading Coolify installer"

(
    bash /root/install.sh
) >> "$LOG_FILE" 2>&1 &
spinner $! "Installing Coolify"

# =========================================================
# WAIT CONTAINER HEALTHY
# =========================================================
(
    for i in {1..90}; do

        if docker ps --format '{{.Names}} {{.Status}}' \
            | grep -i coolify \
            | grep -qi healthy; then
            exit 0
        fi

        sleep 2
    done

    exit 1
) &
spinner $! "Waiting Coolify container healthy"


echo ""
echo -e "${CYAN}[INFO]${NC} Container status:"

printf "%-28s %-12s %-30s\n" "NAME" "STATE" "STATUS"
printf "%-28s %-12s %-30s\n" "------------------------" "----------" "------------------------------"

docker ps -a --format '{{.Names}}|{{.State}}|{{.Status}}' | while IFS='|' read -r NAME STATE STATUS; do
    printf "%-28s %-12s %-30s\n" "$NAME" "$STATE" "$STATUS"
done

# =========================================================
# STEP 3
# =========================================================
echo ""
echo -e "${YELLOW}----------------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 3/3] Finalizing${NC}"
echo -e "${YELLOW}----------------------------------------------------${NC}"

IP=$(hostname -I | awk '{print $1}')
PORT=8000
IP_URL="http://$IP:$PORT"

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}                 COOLIFY ACCESS INFO                ${NC}"
echo -e "${GREEN}====================================================${NC}"

echo -e "${CYAN}PANEL URL:${NC}"
printf "${CYAN}%-18s${NC} : %s\n" "IP" "$IP_URL"

echo ""
printf "${CYAN}%-18s${NC} : %s\n" "Log File" "$LOG_FILE"
