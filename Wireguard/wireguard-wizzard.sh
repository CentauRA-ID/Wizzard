#!/bin/bash
set -e

MAIN_LOG="/var/log/wireguard-install.log"
DOCKER_LOG="/var/log/wireguard-docker.log"

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
echo -e "${BLUE}         WIREGUARD INSTALLER WIZARD         ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

read -p "Start WireGuard configuration wizard? (Y/n): " CONFIRM
CONFIRM=${CONFIRM:-y}

[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && exit 0

# ==============================
# STEP 1
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 1/4] Configuration${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

echo -e "${CYAN}[INFO]${NC} Please enter your WireGuard configuration"
echo ""

DEFAULT_FQDN=$(hostname -f 2>/dev/null || hostname)

while true; do
    read -p "Domain / FQDN               : " DOMAIN

    if [ -n "$DOMAIN" ]; then
        break
    fi

    echo -e "${RED}[ERROR]${NC} FQDN cannot be empty"
done

echo ""

read -p "WireGuard Web Port [default 80] : " PORT
PORT=${PORT:-80}

IP=$(hostname -I | awk '{print $1}')
INSTALL_DIR="/opt/wireguard"

# ==============================
# STEP 2
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 2/4] Prepare system${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

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
# ==============================
# START DOCKER
# ==============================
run_step "Starting Docker service" bash -c "
systemctl enable docker || true
systemctl restart docker || service docker restart || true
"

echo -e "${GREEN}[OK]${NC} Docker ready"

echo -e "${GREEN}[OK]${NC} All dependencies ready"

# ==============================
# STEP 3
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 3/4] Install WireGuard${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

cat <<EOF > docker-compose.yaml
volumes:
  etc_wireguard:

services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:15
    container_name: wg-easy
    networks:
      wg:
        ipv4_address: 10.42.42.42
        ipv6_address: fdcc:ad94:bacf:61a3::2a
    volumes:
      - etc_wireguard:/etc/wireguard
      - /lib/modules:/lib/modules:ro
    ports:
      - "51820:51820/udp"
      - "$PORT:80/tcp"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
      # - NET_RAW #Uncomment if using Podman
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv6.conf.all.disable_ipv6=0
      - net.ipv6.conf.all.forwarding=1
      - net.ipv6.conf.default.forwarding=1
    environment:
      - PORT=80
      - INSECURE=true

networks:
  wg:
    driver: bridge
    enable_ipv6: true
    ipam:
      driver: default
      config:
        - subnet: 10.42.42.0/24
        - subnet: fdcc:ad94:bacf:61a3::/64
EOF

echo -e "${GREEN}[OK]${NC} Config ready"

docker compose up -d >> "$DOCKER_LOG" 2>&1 &
COMPOSE_PID=$!

spinner $COMPOSE_PID "Deploying containers"
wait $COMPOSE_PID

COMPOSE_EXIT=$?

set -e
(
    while true; do

        # ==========================================
        # CHECK CONTAINER EXIST
        # ==========================================
        EXISTS=$(docker ps -a \
            --format '{{.Names}}' | grep -c '^wg-easy$' || true)

        if [[ "$EXISTS" -eq 0 ]]; then
            sleep 2
            continue
        fi

        # ==========================================
        # CHECK FAILED
        # ==========================================
        FAILED=$(docker ps -a \
            --format '{{.Names}} {{.Status}}' \
            | grep '^wg-easy ' \
            | grep -ciE 'exited|dead' || true)

        if [[ "$FAILED" -ge 1 ]]; then
            echo ""
            echo -e "${RED}[ERROR]${NC} WireGuard container failed"
            echo -e "${YELLOW}[INFO]${NC} Docker log: $DOCKER_LOG"
            docker ps -a
            docker logs wg-easy --tail 50 || true
            exit 1
        fi

        # ==========================================
        # CHECK HEALTH STATUS
        # ==========================================
        HEALTH=$(docker inspect \
            --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' \
            wg-easy 2>/dev/null || true)

        RUNNING=$(docker inspect \
            --format='{{.State.Running}}' \
            wg-easy 2>/dev/null || echo "false")

        # ==========================================
        # SUCCESS
        # ==========================================
        if [[ "$RUNNING" == "true" ]]; then

            # kalau ada healthcheck → wajib healthy
            if [[ "$HEALTH" == "healthy" ]]; then
                break
            fi

            # fallback kalau image tidak punya healthcheck
            if [[ "$HEALTH" == "no-healthcheck" ]]; then
                break
            fi
        fi

        sleep 2
    done
) &

WAIT_PID=$!

spinner $WAIT_PID "Starting Container WireGuard" 
wait $WAIT_PID

echo -e "${GREEN}[OK]${NC}Container WireGuard Ready"

echo ""
echo -e "${CYAN}[INFO]${NC} Container status :"


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
echo -e "${YELLOW}[STEP 4/4] Finalizing${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

# ==============================
# DONE
# ==============================
echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}        INSTALLATION COMPLETE${NC}"
echo -e "${BLUE}======================================${NC}"

echo ""
echo -e "${CYAN}To set up the WireGuard, please access:${NC}"
echo "Domain / FQDN   : http://$DOMAIN"
echo "IP              : http://$IP:$PORT"

echo ""
echo -e "${CYAN}LOG:${NC}"
echo "Main   : $MAIN_LOG"
echo "Docker : $DOCKER_LOG"
