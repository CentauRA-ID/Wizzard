#!/bin/bash
set -e

# =========================================================
# COLOR
# =========================================================
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
NC="\e[0m"

LOG_FILE="/var/log/hestia-install.log"

# =========================================================
# SPINNER
# =========================================================
spinner() {
    local pid=$1
    local info_msg="$2"
    local ok_msg="$3"

    local spin='|/-\'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) %4 ))

        printf "\r${CYAN}[INFO]${NC} %-40s ${spin:$i:1}" "$info_msg"
        sleep 0.1
    done

    wait "$pid"
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        printf "\r${GREEN}[OK]${NC} %-50s\n" "$ok_msg"
    else
        printf "\r${RED}[ERROR]${NC} %-47s\n" "$info_msg"
        echo -e "${RED}[ERROR] Check log: $LOG_FILE${NC}"
        exit 1
    fi
}

# =========================================================
# APT LOCK CHECK
# =========================================================
fix_apt_lock() {
    local spin='|/-\'
    local i=0

    while \
        fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
        fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
        fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
        fuser /var/cache/apt/archives/lock >/dev/null 2>&1
    do
        i=$(( (i+1) %4 ))

        printf "\r${CYAN}[INFO]${NC} Waiting for APT lock ${spin:$i:1}"
        sleep 0.2
    done

    rm -f /var/lib/dpkg/lock*
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock

    dpkg --configure -a >> "$LOG_FILE" 2>&1 || true

    printf "\r${GREEN}[OK]${NC} %-50s\n" "APT lock cleared"
}

# =========================================================
# HEADER
# =========================================================
clear

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}               HESTIA INSTALLER WIZARD              ${NC}"
echo -e "${BLUE}====================================================${NC}"
echo ""

# =========================================================
# CONFIRM
# =========================================================
read -p "Start Hestia installation wizard? (Y/n): " CONFIRM
CONFIRM=${CONFIRM:-Y}

[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && exit 0

echo ""

# =========================================================
# STEP 1/4 CONFIGURATION
# =========================================================
echo -e "${YELLOW}----------------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 1/4] Configuration${NC}"
echo -e "${YELLOW}----------------------------------------------------${NC}"

HOSTNAME_DEFAULT=$(hostname -f 2>/dev/null || hostname)

echo -e "${CYAN}[INFO]${NC} Please enter your Hestia configuration"
echo ""

# =========================================================
# USERNAME VALIDATION
# =========================================================
echo -e "Please enter the username for the Hestia administrator"
while true; do
    read -p "Username         : " USERNAME

    [[ -z "$USERNAME" ]] && {
        echo -e "${RED}Username cannot be empty${NC}"
        continue
    }

    if getent passwd "$USERNAME" >/dev/null || getent group "$USERNAME" >/dev/null; then
        echo -e "${RED}Username already exists${NC}"
        continue
    fi

    if [[ "$USERNAME" == "admin" ]]; then
        echo -e "${RED}Avoid using 'admin' as username${NC}"
        continue
    fi

    break
done

echo ""

# =========================================================
# PASSWORD
# =========================================================
echo -e "Please enter the password for the Hestia administrator"
while true; do
    read -s -p "Password         : " P1
    echo ""

    read -s -p "Confirm Password : " P2
    echo ""

    [[ "$P1" == "$P2" && -n "$P1" ]] && break

    echo -e "${RED}Password mismatch${NC}"
done

PASSWORD=$P1

echo ""

# =========================================================
# EMAIL VALIDATION
# =========================================================
echo -e "Please enter the administrator email address"
while true; do
    read -p "Email           : " EMAIL

    if [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
    else
        echo -e "${RED}[ERROR] Invalid email format! Example: user@domain.com${NC}"
    fi
done

echo ""

# =========================================================
# DOMAIN VALIDATION
# =========================================================
echo -e "Please enter the FQDN [default:$HOSTNAME_DEFAULT]"
while true; do
    read -p "FQDN             : " FQDN
    FQDN=${FQDN:-$HOSTNAME_DEFAULT}

    if [[ ! "$FQDN" =~ ^([a-zA-Z0-9](-?[a-zA-Z0-9])*\.)+[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}[ERROR] Invalid domain format! Example: panel.domain.com${NC}"
        continue
    fi

    if [[ $(echo "$FQDN" | tr -cd '.' | wc -c) -lt 2 ]]; then
        echo -e "${RED}[ERROR] Subdomain is required! Example: panel.domain.com${NC}"
        continue
    fi

    break
done

echo ""

# =========================================================
# PORT VALIDATION
# =========================================================
echo -e "Please enter the Hestia panel port [default:8083]"

while true; do
    read -p "Port             : " PORT
    PORT=${PORT:-8083}

    # must be numeric
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[ERROR] Port must be numeric${NC}"
        continue
    fi

    # valid range
    if (( PORT < 1 || PORT > 65535 )); then
        echo -e "${RED}[ERROR] Port must be between 1-65535${NC}"
        continue
    fi

    # reserved ports
    case "$PORT" in
        80|8080|443|8443)
            echo -e "${RED}[ERROR] Port $PORT is reserved for HTTP/HTTPS${NC}"
            continue
            ;;
    esac

    # check ALL listening ports
    if ss -tuln | grep -qE "[:.]${PORT}[[:space:]]"; then
        PROCESS_NAME=$(ss -tulpn 2>/dev/null | \
            grep -E "[:.]${PORT}[[:space:]]" | \
            sed -n 's/.*users:(("\([^"]*\)".*/\1/p' | \
            head -n1)

        PROCESS_NAME=${PROCESS_NAME:-unknown}

        echo -e "${RED}[ERROR] Port $PORT is already in use by ${PROCESS_NAME}${NC}"
        continue
    fi

    break
done

echo ""

# =========================================================
# DATABASE CHOICE
# =========================================================
echo -e "Please select the database you want to use"
echo "1) MySQL (Default)"
echo "2) PostgreSQL"

while true; do
    read -p "Select DB (1/2) [default:1]: " DB_CHOICE
    DB_CHOICE=${DB_CHOICE:-1}

    case "$DB_CHOICE" in
        1)
            DB_ARGS=""
            DB_NAME="MySQL"
            break
            ;;
        2)
            DB_ARGS="--mysql no --postgresql yes"
            DB_NAME="PostgreSQL"
            break
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            ;;
    esac
done

echo ""

# =========================================================
# STEP 2/4 PREPARE SYSTEM
# =========================================================
echo -e "${YELLOW}----------------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 2/4] Prepare System${NC}"
echo -e "${YELLOW}----------------------------------------------------${NC}"

fix_apt_lock

(
    apt update -y >> "$LOG_FILE" 2>&1
    apt install -y wget curl sudo >> "$LOG_FILE" 2>&1
    groupdel admin > "$LOG_FILE" 2>&1
) &
spinner $! "Installing dependencies" "Dependencies installed successfully"

(
    systemctl stop ufw >/dev/null 2>&1 || true
    systemctl disable ufw >/dev/null 2>&1 || true
    apt remove -y ufw >> "$LOG_FILE" 2>&1 || true
    apt purge -y ufw >> "$LOG_FILE" 2>&1 || true
) &
spinner $! "Removing UFW" "UFW removed successfully"

echo ""

# =========================================================
# STEP 3/4 INSTALL HESTIA
# =========================================================
echo -e "${YELLOW}----------------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 3/4] Install Hestia${NC}"
echo -e "${YELLOW}----------------------------------------------------${NC}"

(
    wget -O /root/install.sh \
    https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh \
    >> "$LOG_FILE" 2>&1

    chmod +x /root/install.sh
) &
spinner $! "Downloading installer" "Installer downloaded successfully"

(
    bash /root/install.sh \
        --port "$PORT" \
        --hostname "$FQDN" \
        --username "$USERNAME" \
        --email "$EMAIL" \
        --password "$PASSWORD" \
        $DB_ARGS \
        --interactive no >> "$LOG_FILE" 2>&1
) &
spinner $! "Installing Hestia" "Hestia installed successfully"

echo ""

# =========================================================
# STEP 4/4 LOGIN INFO
# =========================================================
echo -e "${YELLOW}----------------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 4/4] Login Information${NC}"
echo -e "${YELLOW}----------------------------------------------------${NC}"

IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}                 HESTIA LOGIN INFO                  ${NC}"
echo -e "${GREEN}====================================================${NC}"

printf "${CYAN}%-12s${NC} : %s\n" "Panel URL" "https://$FQDN:$PORT"
printf "${CYAN}%-12s${NC} : %s\n" "Server IP" "https://$IP:$PORT"
printf "${CYAN}%-12s${NC} : %s\n" "Username" "$USERNAME"
printf "${CYAN}%-12s${NC} : %s\n" "Password" "$PASSWORD"
printf "${CYAN}%-12s${NC} : %s\n" "Database" "$DB_NAME"

echo -e "${GREEN}====================================================${NC}"

echo ""

printf "${CYAN}%-12s${NC} : %s\n" "Log File" "$LOG_FILE"

echo ""
