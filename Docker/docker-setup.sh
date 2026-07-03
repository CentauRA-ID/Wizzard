#!/bin/bash
set -e

MAIN_LOG="/var/log/docker-install.log"

exec > >(tee -a "$MAIN_LOG") 2>&1

# ==============================
# COLOR
# ==============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==============================
# ROOT CHECK
# ==============================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} Please run as root"
    exit 1
fi

# ==============================
# DETECT OS
# ==============================
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_LIKE=$ID_LIKE
else
    echo -e "${RED}[ERROR]${NC} Cannot detect OS"
    exit 1
fi

PKG_MANAGER=""

case "$OS_ID" in
    ubuntu|debian)
        PKG_MANAGER="apt"
        ;;
    rhel|rocky|almalinux|centos|fedora)
        if command -v dnf >/dev/null 2>&1; then
            PKG_MANAGER="dnf"
        else
            PKG_MANAGER="yum"
        fi
        ;;
    *)
        if [[ "$OS_LIKE" == *"debian"* ]]; then
            PKG_MANAGER="apt"
        elif [[ "$OS_LIKE" == *"rhel"* ]] || [[ "$OS_LIKE" == *"fedora"* ]]; then
            if command -v dnf >/dev/null 2>&1; then
                PKG_MANAGER="dnf"
            else
                PKG_MANAGER="yum"
            fi
        else
            echo -e "${RED}[ERROR]${NC} Unsupported OS"
            exit 1
        fi
        ;;
esac

# ==============================
# SPINNER
# ==============================
spinner() {
    local pid=$1
    local msg="$2"
    local spin='-\|/'
    local i=0

    tput civis 2>/dev/null || true

    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${CYAN}[INFO]${NC} %s... %s" "$msg" "${spin:$i:1}"
        sleep 0.2
    done

    printf "\r\033[K"
    tput cnorm 2>/dev/null || true
}

# ==============================
# RUN STEP
# ==============================
run_step() {
    local MSG="$1"
    shift

    (
        "$@"
    ) >> "$MAIN_LOG" 2>&1 &

    PID=$!

    spinner $PID "$MSG"
    wait $PID

    if [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} $MSG failed!"
        echo -e "${YELLOW}[INFO]${NC} Check log: $MAIN_LOG"
        exit 1
    fi

    echo -e "${GREEN}[OK]${NC} $MSG"
}

# ==============================
# INSTALL PACKAGE
# ==============================
install_package() {
    local pkg="$1"

    case "$PKG_MANAGER" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt install -y "$pkg"
            ;;
        dnf)
            dnf install -y "$pkg"
            ;;
        yum)
            yum install -y "$pkg"
            ;;
    esac
}

# ==============================
# CHECK DEPENDENCY
# ==============================
check_dependency() {
    local cmd="$1"
    local pkg="$2"

    if command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC} $cmd already installed" >/dev/null 2>&1
    else
        run_step "Installing dependency: $pkg" install_package "$pkg"
    fi
}

clear
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}     DOCKER INSTALLER WIZARD         ${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# =========================
# PROMPT (optional)
# =========================
if [ -t 0 ]; then
    read -p "Start Docker installation? (Y/n): " CONFIRM
    CONFIRM=${CONFIRM:-Y}

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Installation cancelled.${NC}"
        exit 0
    fi
fi

# =========================================================
# STEP 1
# =========================================================
echo ""
echo -e "${YELLOW}--------------------------------------${NC}"
echo -e "${YELLOW}[STEP 1/3] Prepare system${NC}"
echo -e "${YELLOW}--------------------------------------${NC}"

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

        dpkg --configure -a >> "$MAIN_LOG" 2>&1 || true

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
	        dnf makecache >> "$MAIN_LOG" 2>&1 || true
	    else
 	       yum makecache >> "$MAIN_LOG" 2>&1 || true
    	fi
fi) &

STEP1_PID=$!

spinner "$STEP1_PID" "Preparing package manager"

echo -e "${GREEN}[OK]${NC} Package manager ready"

# ==============================
# DEPENDENCIES
# ==============================
DEPENDENCIES=(
    "curl:curl"
    "ca-certificates:ca-certificates"
)

for dep in "${DEPENDENCIES[@]}"; do
    CMD="${dep%%:*}"
    PKG="${dep##*:}"

    check_dependency "$CMD" "$PKG"
done
echo -e "${GREEN}[OK]${NC} All dependencies ready"

# =========================================================
# STEP 2
# =========================================================
echo ""
echo -e "${YELLOW}--------------------------------------${NC}"
echo -e "${YELLOW}[STEP 2/3] Install Docker${NC}"
echo -e "${YELLOW}--------------------------------------${NC}"

run_step "Downloading Docker installer" \
    curl -fsSL https://raw.githubusercontent.com/KnowLedZ/Wizzard/main/docker-install.sh \
    -o /tmp/get-docker.sh

chmod +x /tmp/get-docker.sh

DOCKER_SUCCESS=0

for i in 1 2 3; do
    run_step "Installing Docker" bash /tmp/get-docker.sh

    if systemctl status docker >/dev/null 2>&1 || service docker status >/dev/null 2>&1; then
        DOCKER_SUCCESS=1
        break
    fi

    sleep 3
done

if [ "$DOCKER_SUCCESS" -ne 1 ]; then
    echo -e "${RED}[ERROR]${NC} Docker installation failed"
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Docker installed"

# =========================================================
# STEP 3
# =========================================================
echo ""
echo -e "${YELLOW}--------------------------------------${NC}"
echo -e "${YELLOW}[STEP 3/3] Verify Docker${NC}"
echo -e "${YELLOW}--------------------------------------${NC}"

(
    systemctl start docker || service docker start || true
    systemctl enable docker >/dev/null 2>&1 || true

    for i in {1..30}; do
        if docker info >/dev/null 2>&1; then
            exit 0
        fi
        sleep 2
    done

    exit 1
) &

spinner $! "Starting & checking Docker"

echo ""

# =========================================================
# DONE
# =========================================================
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}       DOCKER INSTALL SUCCESS         ${NC}"
echo -e "${GREEN}======================================${NC}"

DOCKER_VERSION=$(docker --version 2>/dev/null || echo "Unknown")
IP=$(hostname -I | awk '{print $1}')

printf "${CYAN}%-15s${NC} : %s\n" "Docker Version" "$DOCKER_VERSION"
printf "${CYAN}%-15s${NC} : %s\n" "Server IP" "$IP"
printf "${CYAN}%-15s${NC} : %s\n" "Log File" "$MAIN_LOG"

echo ""
echo -e "${GREEN}Useful commands:${NC}"
echo -e "${CYAN}systemctl start docker${NC}"
echo -e "${CYAN}systemctl stop docker${NC}"
echo -e "${CYAN}systemctl restart docker${NC}"
echo -e "${CYAN}docker ps${NC}"
echo -e "${CYAN}docker info${NC}"
echo ""
