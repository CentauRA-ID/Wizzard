#!/bin/bash
set -e

MAIN_LOG="/var/log/n8n-install.log"
DOCKER_LOG="/var/log/n8n-docker.log"

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
echo -e "${BLUE}            N8N INSTALLER WIZARD${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

read -p "Start N8N configuration wizard? (Y/n): " CONFIRM
CONFIRM=${CONFIRM:-y}

[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && exit 0

# ==============================
# STEP 1
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 1/5] Configuration${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

echo -e "${CYAN}[INFO]${NC} Please enter your N8N configuration"
echo ""

DEFAULT_FQDN=$(hostname -f 2>/dev/null || hostname)

while true; do
    read -p "FQDN [${DEFAULT_FQDN}]          : " DOMAIN
    DOMAIN=${DOMAIN:-$DEFAULT_FQDN}

    if [ -n "$DOMAIN" ]; then
        break
    fi

    echo -e "${RED}[ERROR]${NC} FQDN cannot be empty"
done

echo ""

while true; do
    read -p "Postgres User               : " POSTGRES_USER

    if [ -n "$POSTGRES_USER" ]; then
        break
    fi

    echo -e "${RED}[ERROR]${NC} Postgres User cannot be empty"
done

while true; do
    read -s -p "Postgres Password           : " P1
    echo ""

    if [ -z "$P1" ]; then
        echo -e "${RED}[ERROR]${NC} Postgres Password cannot be empty"
        continue
    fi

    read -s -p "Re-enter Password           : " P2
    echo ""

    if [ "$P1" != "$P2" ]; then
        echo -e "${RED}[ERROR]${NC} Password mismatch"
        continue
    fi

    break
done

POSTGRES_PASSWORD=$P1

echo ""

while true; do
    read -p "Postgres Database           : " POSTGRES_DB

    if [ -n "$POSTGRES_DB" ]; then
        break
    fi

    echo -e "${RED}[ERROR]${NC} Postgres Database cannot be empty"
done

echo ""

while true; do
    read -p "Postgres Non-Root User      : " POSTGRES_NON_ROOT_USER

    if [ -n "$POSTGRES_NON_ROOT_USER" ]; then
        break
    fi

    echo -e "${RED}[ERROR]${NC} Postgres Non-Root User cannot be empty"
done

while true; do
    read -s -p "Postgres Non-Root Password  : " P1
    echo ""

    if [ -z "$P1" ]; then
        echo -e "${RED}[ERROR]${NC} Postgres Non-Root Password cannot be empty"
        continue
    fi

    read -s -p "Re-enter Password           : " P2
    echo ""

    if [ "$P1" != "$P2" ]; then
        echo -e "${RED}[ERROR]${NC} Password mismatch"
        continue
    fi

    break
done

POSTGRES_NON_ROOT_PASSWORD=$P1

RUNNERS_AUTH_TOKEN=$(openssl rand -hex 16)
INSTALL_DIR="/opt/n8n"

# ==============================
# STEP 2
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 2/5] Prepare system${NC}"
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
    "openssl:openssl"
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
echo -e "${YELLOW}[STEP 3/5] Prepare environment${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [ ! -d ".git" ]; then
    run_step "Cloning repository" \
        git clone https://github.com/KnowLedZ/n8n-http.git .
else
    echo -e "${GREEN}[OK]${NC} Repository already exists"
fi

IP=$(hostname -I | awk '{print $1}')

cat <<EOF > .env
N8N_VERSION=stable
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
POSTGRES_NON_ROOT_USER=$POSTGRES_NON_ROOT_USER
POSTGRES_NON_ROOT_PASSWORD=$POSTGRES_NON_ROOT_PASSWORD
RUNNERS_AUTH_TOKEN=$RUNNERS_AUTH_TOKEN
FQDN=$DOMAIN
EOF

echo -e "${GREEN}[OK]${NC} Config ready"

# ==============================
# STEP 4
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 4/5] Starting containers${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

set +e

docker compose up -d >> "$DOCKER_LOG" 2>&1 &
COMPOSE_PID=$!

spinner $COMPOSE_PID "Deploying containers"
wait $COMPOSE_PID

COMPOSE_EXIT=$?

set -e

if [ $COMPOSE_EXIT -ne 0 ]; then
    echo -e "${YELLOW}[WARN]${NC} Docker compose returned non-zero status"
    echo -e "${CYAN}[INFO]${NC} Checking container health..."
else
    echo -e "${GREEN}[OK]${NC} Containers created"
fi

(
    while true; do
        CONTAINER=$(docker ps -a --format '{{.Names}}' | grep postgres | head -n1 || true)

        if [ -z "$CONTAINER" ]; then
            sleep 2
            continue
        fi

        STATUS=$(docker inspect \
            --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
            "$CONTAINER" 2>/dev/null || echo "starting")

        if [[ "$STATUS" == "healthy" ]] || [[ "$STATUS" == "running" ]]; then
            break
        fi

        if [[ "$STATUS" == "exited" ]] || [[ "$STATUS" == "dead" ]]; then
            echo ""
            echo -e "${RED}[ERROR]${NC} PostgreSQL container failed"
            echo -e "${YELLOW}[INFO]${NC} Docker log: $DOCKER_LOG"
            docker logs "$CONTAINER" 2>/dev/null | tail -20
            exit 1
        fi

        sleep 2
    done
) &

spinner $! "Waiting PostgreSQL healthy"
wait $!

echo -e "${GREEN}[OK]${NC} PostgreSQL healthy"

# ==============================
# STEP 5
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 5/5] Finalizing${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

set +e
docker compose up -d >> "$DOCKER_LOG" 2>&1
set -e

(
    while true; do
        RUNNING=$(docker ps \
            --filter "status=running" \
            --format '{{.Names}}' | grep -c '^n8n-' || true)

        if [[ "$RUNNING" -ge 1 ]]; then
            break
        fi

        FAILED=$(docker ps -a \
            --format '{{.Names}} {{.Status}}' | grep '^n8n-' | grep -ciE 'exited|dead' || true)

        if [[ "$FAILED" -ge 1 ]]; then
            echo ""
            echo -e "${RED}[ERROR]${NC} One or more n8n containers failed"
            echo -e "${YELLOW}[INFO]${NC} Docker log: $DOCKER_LOG"
            docker ps -a
            exit 1
        fi

        sleep 2
    done
) &

spinner $! "Waiting n8n running"
wait $!

echo -e "${GREEN}[OK]${NC} n8n running"

echo ""
echo -e "${CYAN}[INFO]${NC} Container status"
echo ""

printf "%-28s %-12s %-30s\n" "NAME" "STATE" "STATUS"
printf "%-28s %-12s %-30s\n" "------------------------" "----------" "------------------------------"

docker ps -a --format '{{.Names}}|{{.State}}|{{.Status}}' | while IFS='|' read -r NAME STATE STATUS; do
    printf "%-28s %-12s %-30s\n" "$NAME" "$STATE" "$STATUS"
done

# ==============================
# DONE
# ==============================
echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}        INSTALLATION COMPLETE${NC}"
echo -e "${BLUE}======================================${NC}"

echo ""
echo -e "${CYAN}ACCESS:${NC}"
echo "FQDN   : http://$DOMAIN"
echo "IP     : http://$IP:5678"

echo ""
echo -e "${CYAN}TOKEN:${NC}"
echo "$RUNNERS_AUTH_TOKEN"

echo ""
echo -e "${CYAN}LOG:${NC}"
echo "Main   : $MAIN_LOG"
echo "Docker : $DOCKER_LOG"
