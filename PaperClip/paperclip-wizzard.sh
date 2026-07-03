#!/bin/bash
set -e

MAIN_LOG="/var/log/paperclip-install.log"

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
# OS CHECK
# ==============================
if [ ! -f /etc/os-release ]; then
    echo -e "${RED}[ERROR]${NC} Unsupported OS"
    exit 1
fi

. /etc/os-release

if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    echo -e "${RED}[ERROR]${NC} This installer only supports Ubuntu/Debian"
    exit 1
fi

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
# HEADER
# ==============================
clear

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}         PAPERCLIP INSTALLER WIZARD${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

read -p "Start installation? (Y/n): " CONFIRM
CONFIRM=${CONFIRM:-y}

[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && exit 0

# ==============================
# CONFIG
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 1/5] Configuration${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

DEFAULT_FQDN=$(hostname -f 2>/dev/null || hostname)

while true; do
    read -p "Domain/FQDN [${DEFAULT_FQDN}] : " DOMAIN
    DOMAIN=${DOMAIN:-$DEFAULT_FQDN}

    if [ -n "$DOMAIN" ]; then
        break
    fi

    echo -e "${RED}[ERROR]${NC} Domain cannot be empty"
done

# ==============================
# PREPARE SYSTEM
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 2/5] Prepare system${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

(
    export DEBIAN_FRONTEND=noninteractive

    sleep 3

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
    apt update -y
) &

spinner $! "Preparing package manager"
wait $!

echo -e "${GREEN}[OK]${NC} Package manager ready"

# ==============================
# INSTALL DEPENDENCIES
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 3/5] Installing dependencies${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

run_step "Installing NodeSource repository" bash -c \
    "curl -fsSL https://deb.nodesource.com/setup_22.x | bash -"

run_step "Installing packages" apt install -y \
    nodejs \
    git \
    curl \
    ca-certificates \
    nginx \
    certbot \
    python3-certbot-nginx

run_step "Installing corepack" npm install -g corepack

run_step "Enabling corepack" corepack enable

run_step "Activating pnpm" corepack prepare pnpm@latest --activate

echo -e "${GREEN}[OK]${NC} Dependencies installed"

# ==============================
# CREATE USER
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 4/5] Creating user${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

if id "paperclip" >/dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} User paperclip already exists"
else
    run_step "Creating paperclip user" useradd \
        --system \
        --create-home \
        --shell /bin/bash \
        paperclip
fi

# ==============================
# ENVIRONMENT
# ==============================
cat > /home/paperclip/paperclip.env <<EOF
PAPERCLIP_DEPLOYMENT_MODE=authenticated
PAPERCLIP_DEPLOYMENT_EXPOSURE=public
PAPERCLIP_AUTH_PUBLIC_BASE_URL=https://$DOMAIN
PAPERCLIP_ALLOWED_HOSTNAMES=$DOMAIN
PAPERCLIP_BIND=lan
EOF

chmod 600 /home/paperclip/paperclip.env
chown paperclip:paperclip /home/paperclip/paperclip.env

echo -e "${GREEN}[OK]${NC} Environment configured"

# ==============================
# SYSTEMD
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 5/5] Configuring services${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

cat > /etc/systemd/system/paperclip.service <<'EOF'
[Unit]
Description=Paperclip control plane
After=network.target

[Service]
Type=simple
User=paperclip
Group=paperclip
WorkingDirectory=/home/paperclip
EnvironmentFile=/home/paperclip/paperclip.env
ExecStart=/usr/bin/npx paperclipai run
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

run_step "Reloading systemd" systemctl daemon-reload

run_step "Enabling paperclip service" systemctl enable paperclip

# ==============================
# NGINX
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[EXTRA] Configuring Nginx${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

cat > /etc/nginx/sites-available/paperclip <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    client_max_body_size 50m;

    location / {
        proxy_pass http://127.0.0.1:3100;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/paperclip /etc/nginx/sites-enabled/paperclip
rm -f /etc/nginx/sites-enabled/default

run_step "Testing nginx configuration" nginx -t

run_step "Restarting nginx" systemctl restart nginx

echo ""
read -p "Install SSL with Let's Encrypt now? (Y/n): " SSL_CONFIRM
SSL_CONFIRM=${SSL_CONFIRM:-y}

if [[ "$SSL_CONFIRM" =~ ^[Yy]$ ]]; then
    run_step "Generating SSL certificate" certbot \
        --nginx \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        -d "$DOMAIN"
fi

# ==============================
# DONE
# ==============================
IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}          INSTALLATION COMPLETE${NC}"
echo -e "${BLUE}============================================${NC}"

echo ""
echo -e "${CYAN}ACCESS:${NC}"
echo "URL : https://$DOMAIN"
echo "IP  : http://$IP"

echo ""
echo -e "${YELLOW}============================================${NC}"
echo -e "${YELLOW}           NEXT STEP REQUIRED${NC}"
echo -e "${YELLOW}============================================${NC}"

echo ""
echo -e "${CYAN}Run these commands manually:${NC}"
echo ""

cat <<EOF
sudo -iu paperclip

export PAPERCLIP_DEPLOYMENT_MODE=authenticated
export PAPERCLIP_DEPLOYMENT_EXPOSURE=public
export PAPERCLIP_AUTH_PUBLIC_BASE_URL=https://$DOMAIN
export PAPERCLIP_ALLOWED_HOSTNAMES=$DOMAIN
export PAPERCLIP_BIND=lan

npx paperclipai onboard
EOF

echo ""
echo -e "${CYAN}After onboarding finished:${NC}"
echo ""

cat <<EOF
sudo systemctl restart paperclip
sudo systemctl status paperclip
EOF

echo ""
echo -e "${CYAN}Bootstrap CEO:${NC}"
echo ""

cat <<EOF
sudo -iu paperclip
npx paperclipai auth bootstrap-ceo
EOF

echo ""
echo -e "${CYAN}LOG:${NC}"
echo "$MAIN_LOG"

echo ""
echo -e "${GREEN}[OK]${NC} Installer finished"
