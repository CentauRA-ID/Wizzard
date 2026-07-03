#!/bin/bash
set -uo pipefail

# =========================
# COLOR
# =========================
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
NC="\e[0m"

# =========================
# LOG
# =========================
LOG_FILE="/var/log/aapanel-installer.log"

# =========================
# SPINNER
# =========================
spinner() {
    local pid=$1
    local msg="$2"
    local done_msg="$3"
    local err_msg="$4"

    local spin='-\|/'
    local i=0

    printf "${CYAN}[INFO]${NC} %s " "$msg"

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\b%s" "${spin:$i:1}"
        sleep 0.1
    done

    wait "$pid"
    local exit_code=$?

    # clear line
    printf "\r\033[K"

    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} $done_msg"
    else
        echo -e "${RED}[ERROR]${NC} $err_msg"

        if [ -f "$LOG_FILE" ]; then
            echo ""
            echo -e "${YELLOW}Last 15 log lines:${NC}"
            tail -n 15 "$LOG_FILE"

            echo ""
            echo -e "${CYAN}Full log:${NC} $LOG_FILE"
        fi

        exit 1
    fi
}

# =========================
# VALIDATION
# =========================
validate_username() {
    local user="$1"

    [[ "$user" != "admin" ]] || return 1
    [[ "$user" =~ ^[a-zA-Z0-9_]{5,20}$ ]]
}

validate_password() {
    local pass="$1"

    [ ${#pass} -ge 8 ] || return 1
    [[ "$pass" =~ [A-Z] ]] || return 1
    [[ "$pass" =~ [a-z] ]] || return 1
    [[ "$pass" =~ [0-9] ]] || return 1

    return 0
}

# =========================
# DETECT OS
# =========================
detect_os() {

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
    else
        echo -e "${RED}[ERROR] Cannot detect OS.${NC}"
        exit 1
    fi

    case "$OS_ID" in
        ubuntu|debian)
            PKG_UPDATE="apt update -y"
            PKG_INSTALL="apt install -y wget curl sudo expect"
            ;;
        almalinux|rocky|rhel|centos)
            PKG_UPDATE="dnf makecache"
            PKG_INSTALL="dnf install -y wget curl sudo expect"
            ;;
        *)
            echo -e "${RED}[ERROR] Unsupported OS: $OS_ID${NC}"
            exit 1
            ;;
    esac
}

# =========================
# HEADER
# =========================
clear

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}        AAPANEL INSTALLER WIZARD         ${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# =========================
# CONFIRM
# =========================
while true; do

    read -rp "Start aaPanel installation wizard? (Y/n): " CONFIRM
    CONFIRM=${CONFIRM:-Y}

    case "$CONFIRM" in
        Y|y)
            break
            ;;
        N|n)
            echo -e "${RED}[INFO] Installation cancelled.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR] Please input Y or N only.${NC}"
            ;;
    esac

done

echo ""

# =========================================================
# STEP 1
# =========================================================
echo -e "${YELLOW}-----------------------------------------${NC}"
echo -e "${YELLOW}[STEP 1/4] Configure aaPanel account${NC}"
echo -e "${YELLOW}-----------------------------------------${NC}"

# USERNAME
while true; do

    read -rp "Input aaPanel username: " PANEL_USER

    if validate_username "$PANEL_USER"; then
        break
    else
        echo -e "${RED}[ERROR] Invalid username.${NC}"
        echo "Requirements:"
        echo " - 5-20 characters"
        echo " - Only letters, numbers, underscore"
        echo " - Username cannot be: admin"
        echo ""
    fi

done

echo ""

# PASSWORD
while true; do

    read -rsp "Input aaPanel password: " PANEL_PASS
    echo ""

    read -rsp "Confirm aaPanel password: " PANEL_PASS2
    echo ""

    if [ "$PANEL_PASS" != "$PANEL_PASS2" ]; then
        echo -e "${RED}[ERROR] Password confirmation does not match.${NC}"
        echo ""
        continue
    fi

    if ! validate_password "$PANEL_PASS"; then
        echo -e "${RED}[ERROR] Weak password.${NC}"
        echo "Requirements:"
        echo " - Minimum 8 characters"
        echo " - Uppercase letter"
        echo " - Lowercase letter"
        echo " - Number"
        echo ""
        continue
    fi

    break

done

echo ""
echo -e "${GREEN}[OK]${NC} Account configuration completed."
echo ""

# =========================================================
# STEP 2
# =========================================================
echo -e "${YELLOW}-----------------------------------------${NC}"
echo -e "${YELLOW}[STEP 2/4] Preparing system${NC}"
echo -e "${YELLOW}-----------------------------------------${NC}"

detect_os

(
    if [[ "$OS_ID" =~ ^(ubuntu|debian)$ ]]; then

        while fuser /var/lib/dpkg/lock >/dev/null 2>&1; do sleep 2; done
        while fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 2; done

        rm -f /var/lib/dpkg/lock*
        rm -f /var/lib/apt/lists/lock*
        rm -f /var/cache/apt/archives/lock

        dpkg --configure -a >> "$LOG_FILE" 2>&1 || true

    fi

    eval "$PKG_UPDATE" >> "$LOG_FILE" 2>&1

) &

spinner \
$! \
"Preparing package manager" \
"Package manager ready" \
"Failed preparing package manager"

(
    eval "$PKG_INSTALL" >> "$LOG_FILE" 2>&1
) &

spinner \
$! \
"Installing dependencies" \
"Dependencies installed" \
"Failed installing dependencies"

echo ""

# =========================================================
# STEP 3
# =========================================================
echo -e "${YELLOW}-----------------------------------------${NC}"
echo -e "${YELLOW}[STEP 3/4] Download & install aaPanel${NC}"
echo -e "${YELLOW}-----------------------------------------${NC}"

(
    wget -qO /root/install.sh https://www.aapanel.com/script/install_panel_en.sh >> "$LOG_FILE" 2>&1
    chmod +x /root/install.sh
) &

spinner \
$! \
"Downloading aaPanel installer" \
"Installer downloaded" \
"Failed downloading installer"

(
    yes y | bash /root/install.sh >> "$LOG_FILE" 2>&1

    test -d /www/server/panel

) &

spinner \
$! \
"Installing aaPanel" \
"aaPanel installed" \
"Failed installing aaPanel"

echo ""

# =========================================================
# STEP 4
# =========================================================
echo -e "${YELLOW}-----------------------------------------${NC}"
echo -e "${YELLOW}[STEP 4/4] Configure aaPanel login${NC}"
echo -e "${YELLOW}-----------------------------------------${NC}"

(
    for i in {1..60}; do
        command -v bt >/dev/null 2>&1 && break
        sleep 2
    done

expect << EOF >> "$LOG_FILE" 2>&1
spawn bt 6
expect "Pls enter new username"
send "$PANEL_USER\r"
expect eof
EOF

) &

spinner \
$! \
"Setting aaPanel username" \
"Username configured" \
"Failed configuring username"

(
expect << EOF >> "$LOG_FILE" 2>&1
spawn bt 5
expect "Pls enter new password"
send "$PANEL_PASS\r"
expect eof
EOF

) &

spinner \
$! \
"Setting aaPanel password" \
"Password configured" \
"Failed configuring password"

echo ""

# =========================================================
# GET INFO
# =========================================================
for i in {1..20}; do
    BT_INFO=$(bt default 2>/dev/null || true)
    [ -n "$BT_INFO" ] && break
    sleep 2
done

PUBLIC_URL=$(echo "$BT_INFO" | grep "aaPanel Internet IPv4 Address" | awk -F': ' '{print $2}')
INTERNAL_URL=$(echo "$BT_INFO" | grep "Internal Address" | awk -F': ' '{print $2}')

IP=$(hostname -I | awk '{print $1}')
PORT=$(cat /www/server/panel/data/port.pl 2>/dev/null || echo "7800")

[ -z "$PUBLIC_URL" ] && PUBLIC_URL="http://$IP:$PORT"
[ -z "$INTERNAL_URL" ] && INTERNAL_URL="http://$IP:$PORT"

# =========================================================
# RESULT
# =========================================================
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}         AAPANEL INSTALL SUCCESS         ${NC}"
echo -e "${GREEN}=========================================${NC}"

printf "${CYAN}%-15s${NC} : %s\n" "Public URL" "$PUBLIC_URL"
printf "${CYAN}%-15s${NC} : %s\n" "Internal URL" "$INTERNAL_URL"
printf "${CYAN}%-15s${NC} : %s\n" "Username" "$PANEL_USER"
printf "${CYAN}%-15s${NC} : %s\n" "Password" "$PANEL_PASS"

echo -e "${GREEN}=========================================${NC}"

echo ""
printf "${CYAN}%-15s${NC} : %s\n" "Log File" "$LOG_FILE"
printf "${CYAN}%-15s${NC} : %s\n" "Install Path" "/www/server"

echo ""
echo -e "${GREEN}Useful commands:${NC}"

printf "${CYAN}%-12s${NC} %s\n" "bt start" ": Start aaPanel"
printf "${CYAN}%-12s${NC} %s\n" "bt stop" ": Stop aaPanel"
printf "${CYAN}%-12s${NC} %s\n" "bt restart" ": Restart aaPanel"
printf "${CYAN}%-12s${NC} %s\n" "bt status" ": Check status"
printf "${CYAN}%-12s${NC} %s\n" "bt default" ": Show login info"
printf "${CYAN}%-12s${NC} %s\n" "bt 5" ": Change panel password"
printf "${CYAN}%-12s${NC} %s\n" "bt 6" ": Change panel username"
printf "${CYAN}%-12s${NC} %s\n" "bt 16" ": Change panel port"
printf "${CYAN}%-12s${NC} %s\n" "bt" ": All aaPanel CLI"
