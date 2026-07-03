#!/bin/bash
set -e

MAIN_LOG="/var/log/uptime-kuma-install.log"
DOCKER_LOG="/var/log/uptime-kuma-docker.log"

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

# ==============================
# HEADER
# ==============================
clear
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}        UPTIME KUMA INSTALLER WIZARD${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

read -p "Start Uptime Kuma configuration wizard? (Y/n): " CONFIRM
CONFIRM=${CONFIRM:-y}
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && exit 0

# ==============================
# STEP 1
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 1/4] Configuration${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

echo -e "Please enter your Uptime Kuma configuration"
echo ""

read -p "Uptime Kuma Port (default 3001) : " UPTIME_KUMA_PORT
UPTIME_KUMA_PORT=${UPTIME_KUMA_PORT:-3001}

INSTALL_DIR="/opt/uptime-kuma"

# ==============================
# STEP 2
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 2/4] Prepare system${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

if [ "$PKG_MANAGER" = "apt" ]; then
    (
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

        dpkg --configure -a || true
    ) >> "$MAIN_LOG" 2>&1 &

    PREP_PID=$!

else
    (
        sleep 5
        $PKG_MANAGER makecache -y
    ) >> "$MAIN_LOG" 2>&1 &

    PREP_PID=$!
fi

spinner $PREP_PID "Preparing package manager"
wait $PREP_PID

echo -e "${GREEN}[OK]${NC} Package manager ready"

# ==============================
# DEPENDENCIES
# ==============================
DEPENDENCIES=(
    "curl:curl"
    "git:git"
)

for dep in "${DEPENDENCIES[@]}"; do
    CMD="${dep%%:*}"
    PKG="${dep##*:}"

    check_dependency "$CMD" "$PKG"
done

# ==============================
# INSTALL DOCKER
# ==============================
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
echo -e "${GREEN}[OK]${NC} All dependencies ready"

# ==============================
# START DOCKER
# ==============================
run_step "Starting Docker service" bash -c "
systemctl enable docker || true
systemctl restart docker || service docker restart || true
"

echo -e "${GREEN}[OK]${NC} Docker ready"


# ==============================
# STEP 3
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 3/4] Installing Uptime Kuma${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

run_step "Cloning repository" git clone https://github.com/KnowLedZ/uptime-kuma.git . || true

IP=$(hostname -I | awk '{print $1}')

cat <<EOF > .env
UPTIME_KUMA_PORT=$UPTIME_KUMA_PORT
EOF

echo -e "${GREEN}[OK]${NC} Config ready"

docker compose up -d >> "$DOCKER_LOG" 2>&1 &
spinner $! "Deploying containers"
wait $!

echo -e "${GREEN}[OK]${NC} Containers created"

check_uptime() {
    for i in {1..60}; do
        RUNNING=$(docker ps --format '{{.Names}} {{.Status}}' | grep uptime-kuma | grep -ic healthy || true)

        [[ "$RUNNING" -ge 1 ]] && return 0

        sleep 2
    done

    return 1
}

check_uptime &
PID=$!

spinner $PID "Starting uptime-kuma"

wait $PID

if [ $? -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} Uptime Kuma failed to start"
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Uptime Kuma running"

echo ""
echo -e "${CYAN}[INFO]${NC} Container status:"

printf "%-28s %-12s %-30s\n" "NAME" "STATE" "STATUS"
printf "%-28s %-12s %-30s\n" "------------------------" "----------" "------------------------------"

docker ps -a --format '{{.Names}}|{{.State}}|{{.Status}}' | while IFS='|' read -r NAME STATE STATUS; do
    printf "%-28s %-12s %-30s\n" "$NAME" "$STATE" "$STATUS"
done

# ==============================
# STEP 4
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 4/4] Uptime Kuma Information${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

# ==============================
# DONE
# ==============================
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}        INSTALLATION COMPLETE${NC}"
echo -e "${BLUE}======================================${NC}"

echo -e "${CYAN}URL:${NC}"
echo "IP     : http://$IP:$UPTIME_KUMA_PORT"

echo ""
echo -e "${CYAN}PATH INSTALLATION:${NC}"
echo "$INSTALL_DIR"

echo ""
echo -e "${CYAN}LOG:${NC}"
echo "Main   : $MAIN_LOG"
echo "Docker : $DOCKER_LOG"
