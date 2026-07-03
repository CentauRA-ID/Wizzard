#!/bin/bash -e

#
#   WordPress Installer - VPS Dagang Edition
#   -----------------------------------------
#   Pilihan stack: Nginx+PHP-FPM, Apache2, atau Docker Compose
#   Deteksi OS otomatis (apt / yum)
#   Kredensial disimpan ke file setelah instalasi selesai.
#
#   Cara pakai: sudo bash wordpress-vps.sh
#

# ─── Warna ──────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

MAIN_LOG="/var/log/wordpress-install.log"

mkdir -p "$(dirname "$MAIN_LOG")"
touch "$MAIN_LOG"

# ==============================
# SPINNER
# ==============================
spinner() {
    local pid=$1
    local msg="$2"
    local spin='-\|/'
    local i=0

    tput civis 2>/dev/null || true

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${CYAN}[INFO]${NC} %-60s %s" "$msg" "${spin:$i:1}"
        sleep 0.15
    done

    printf "\r\033[K"
    tput cnorm 2>/dev/null || true
}

# ==============================
# WAIT PACKAGE MANAGER LOCK
# ==============================
wait_package_manager() {

    export DEBIAN_FRONTEND=noninteractive

    if command -v apt-get >/dev/null 2>&1; then

        sleep 5

        while \
            fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
            fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
            fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
            fuser /var/cache/apt/archives/lock >/dev/null 2>&1
        do
            printf "\r${YELLOW}[WAIT]${NC} Waiting for apt lock..."
            sleep 2
        done

        printf "\r\033[K"

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
            printf "\r${YELLOW}[WAIT]${NC} Waiting for yum/dnf lock..."
            sleep 2
        done

        printf "\r\033[K"

        rm -f /var/lib/rpm/.rpm.lock

        if command -v dnf >/dev/null 2>&1; then
            dnf makecache >> "$MAIN_LOG" 2>&1 || true
        else
            yum makecache >> "$MAIN_LOG" 2>&1 || true
        fi
    fi
}

# ==============================
# RUN TASK WITH SPINNER
# ==============================
run_task() {

    local message="$1"
    shift

    (
        eval "$@"
    ) >> "$MAIN_LOG" 2>&1 &

    local pid=$!

    spinner "$pid" "$message"

    wait "$pid"
    local status=$?

    if [ $status -eq 0 ]; then
        printf "${GREEN}[OK]${NC} %-58s ✅\n" "$message"
    else
        printf "${RED}[ERROR]${NC} %-55s ❌\n" "$message"
        printf "${YELLOW}Check log:${NC} $MAIN_LOG\n"
        exit 1
    fi
}

clear

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}        WORDPRESS INSTALLER WIZARD${NC}"
echo -e "${BLUE}============================================${NC}"

# ─── Cek Root ───────────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    printf "${RED}Must be run as root: sudo bash wordpress-vps.sh${NC}\n"
    exit 1
fi

HOSTNAME=$(hostname -f 2>/dev/null || hostname)

# ════════════════════════════════════════════════════════════════════════════════
# PILIHAN BAHASA / LANGUAGE SELECTION
# ════════════════════════════════════════════════════════════════════════════════
printf "${BLUE}Language / Bahasa:${NC}\n"
printf "  1) Bahasa Indonesia\n"
printf "  2) English\n\n"
read -r -p $'\e[34mPilihan / Choice (1/2): \e[0m' lang_choice

if [ "$lang_choice" == "2" ]; then

    T_DOMAIN="Domain (e.g. $HOSTNAME)"
    T_STACK_TITLE="Choose web server stack"
    T_DB_TITLE="Database credentials (press Enter to use defaults)"
    T_DBNAME="Database Name    [wordpress]"
    T_DBUSER="Database Username [wordpress]"
    T_DBPASS="Database Password"
    T_DBROOTPASS="MariaDB Root Password"
    T_CONFIRM="Run installation? (Y/n)"
    T_CANCELLED="Installation cancelled."
    T_INVALID="Invalid choice."
    T_UPDATE="System Update"
    T_INSTALL_MARIADB="Install MariaDB"
    T_INSTALL_NGINX="Install Nginx"
    T_INSTALL_PHP="Install PHP-FPM"
    T_INSTALL_APACHE="Install Apache2"
    T_INSTALL_DOCKER="Install Docker"
    T_INSTALL_WP="Install WordPress"
    T_VHOST_NGINX="Configuring Nginx virtual host"
    T_VHOST_APACHE="Configuring Apache2 virtual host"
    T_DOCKER_COMPOSE="Creating docker-compose.yml"
    T_PERMISSION="Setting file permissions"
    T_CLEANUP="Cleaning up leftover files"
    T_DONE="Done!"
    T_READY="ready!"
    T_FINISH_TITLE="Installation Complete!"
    T_CRED_SAVED="Credentials saved to"
    T_STACK="Stack"
    T_WEBROOT="Web Root"
    T_SITEURL="Site URL"
    T_SERVERIP="Server IP"
    T_SETUP="WordPress Setup"
    T_NEXT="Next steps"
    T_NEXT1="Point DNS for"
    T_NEXT2="to this server's IP"
    T_NEXT3="Open"
    T_NEXT4="to complete WordPress setup"
    T_USEFUL_CMDS="Useful commands"
    T_WAITING="Waiting for container to be ready (15 seconds)"
    T_GENERATED="Generated"

else

    T_DOMAIN="Domain (contoh: $HOSTNAME)"
    T_STACK_TITLE="Pilih stack web server"
    T_DB_TITLE="Kredensial Database (tekan Enter untuk pakai nilai default)"
    T_DBNAME="Nama Database    [wordpress]"
    T_DBUSER="Username Database [wordpress]"
    T_DBPASS="Password Database"
    T_DBROOTPASS="Password Root MariaDB"
    T_CONFIRM="Jalankan instalasi? (Y/n)"
    T_CANCELLED="Instalasi dibatalkan."
    T_INVALID="Pilihan tidak valid."
    T_UPDATE="Update Sistem"
    T_INSTALL_MARIADB="Install MariaDB"
    T_INSTALL_NGINX="Install Nginx"
    T_INSTALL_PHP="Install PHP-FPM"
    T_INSTALL_APACHE="Install Apache2"
    T_INSTALL_DOCKER="Install Docker"
    T_INSTALL_WP="Install WordPress"
    T_VHOST_NGINX="Mengkonfigurasi Nginx virtual host"
    T_VHOST_APACHE="Mengkonfigurasi Apache2 virtual host"
    T_DOCKER_COMPOSE="Membuat docker-compose.yml"
    T_PERMISSION="Mengatur permission file"
    T_CLEANUP="Membersihkan file sisa"
    T_DONE="Selesai!"
    T_READY="siap!"
    T_FINISH_TITLE="Instalasi Selesai!"
    T_CRED_SAVED="Kredensial disimpan di"
    T_STACK="Stack"
    T_WEBROOT="Web Root"
    T_SITEURL="Site URL"
    T_SERVERIP="Server IP"
    T_SETUP="Setup WordPress"
    T_NEXT="Langkah selanjutnya"
    T_NEXT1="Arahkan DNS domain"
    T_NEXT2="ke IP server ini"
    T_NEXT3="Buka"
    T_NEXT4="untuk setup WordPress"
    T_USEFUL_CMDS="Perintah berguna"
    T_WAITING="Menunggu container siap (15 detik)"
    T_GENERATED="Dibuat pada"

fi

# ─── Deteksi Package Manager ────────────────────────────────────────────────────
if command -v apt-get &>/dev/null; then

    PKG_MANAGER="apt"
    PKG_UPDATE="apt-get update -qq && apt-get upgrade -y -qq"
    PKG_INSTALL="apt-get install -y -qq"

    MARIADB_SVC="mariadb"
    MARIADB_PKG="mariadb-server"

    NGINX_PKG="nginx"
    APACHE_PKG="apache2"

    PHP_PKGS="php-fpm php-mysql php-xml php-curl php-gd php-mbstring php-zip php-intl php-soap"
    PHP_APACHE_PKGS="php libapache2-mod-php php-mysql php-xml php-curl php-gd php-mbstring php-zip php-intl php-soap"

    DEPS_PKG="curl wget unzip perl"

elif command -v yum &>/dev/null || command -v dnf &>/dev/null; then

    PKG_MANAGER="yum"

    if command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    fi

    PKG_UPDATE="${PKG_MANAGER} update -y -q"
    PKG_INSTALL="${PKG_MANAGER} install -y -q"

    MARIADB_SVC="mariadb"
    MARIADB_PKG="mariadb-server"

    NGINX_PKG="nginx"
    APACHE_PKG="httpd"

    PHP_PKGS="php-fpm php-mysqlnd php-xml php-curl php-gd php-mbstring php-zip php-intl php-soap"
    PHP_APACHE_PKGS="php php-mysqlnd php-xml php-curl php-gd php-mbstring php-zip php-intl php-soap"

    DEPS_PKG="curl wget unzip perl"

else

    printf "${RED}OS tidak didukung (butuh apt atau yum/dnf).${NC}\n"
    exit 1
fi

# ==============================
# STEP 1
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 1/4] Configuration${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"
echo ""

printf '\n'
printf "${BLUE}${T_DOMAIN}: ${NC}"
read -r domain
domain=${domain:-$HOSTNAME}

printf '\n'
printf "${BLUE}${T_STACK_TITLE}:${NC}\n"
printf "  1) Nginx + PHP-FPM\n"
printf "  2) Apache2 + PHP\n"
printf "  3) Docker Compose\n\n"

printf "${BLUE}Pilihan / Choice (1/2/3): ${NC}"
read -r stack_choice

printf '\n'
printf "${YELLOW}${T_DB_TITLE}:${NC}\n\n"

_defpass=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
_defrootpass=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)

printf "${BLUE}${T_DBNAME}: ${NC}"
read -r dbname
dbname=${dbname:-wordpress}

printf "${BLUE}${T_DBUSER}: ${NC}"
read -r dbuser
dbuser=${dbuser:-wordpress}

printf "${BLUE}${T_DBPASS} [${_defpass}]: ${NC}"
read -r dbpass
dbpass=${dbpass:-$_defpass}

printf "${BLUE}${T_DBROOTPASS} [${_defrootpass}]: ${NC}"
read -r dbrootpass
dbrootpass=${dbrootpass:-$_defrootpass}

printf '\n'
printf "${BLUE}${T_CONFIRM} ${NC}"
read -r run

if [ "$run" == "n" ] || [ "$run" == "N" ]; then
    printf "${RED}${T_CANCELLED}${NC}\n"
    exit 0
fi

WEBROOT="/var/www/${domain}"
CRED_FILE="/root/wordpress-credentials-${domain}.txt"

# ==============================
# STEP 2
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 2/4] Prepare system${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"
# ─── Update Sistem ──────────────────────────────────────────────────────────────
printf '\n'
printf "${BLUE}===== ${T_UPDATE} =====${NC}\n\n"
eval "${PKG_UPDATE}" >> "$MAIN_LOG" 2>&1


# ─── Install Dependency Dasar ───────────────────────────────────────────────────
eval "${PKG_INSTALL} ${DEPS_PKG}" >> "$MAIN_LOG" 2>&1
printf "${GREEN}${T_DONE} ✅${NC}\n"

# ─── Install MariaDB (Nginx & Apache) ───────────────────────────────────────────
if [ "$stack_choice" != "3" ]; then
    printf '\n'
    printf "${BLUE}===== ${T_INSTALL_MARIADB} =====${NC}\n\n"
    eval "${PKG_INSTALL} ${MARIADB_PKG}" >> "$MAIN_LOG" 2>&1
    systemctl enable "${MARIADB_SVC}"
    systemctl start "${MARIADB_SVC}"

    mariadb -u root << SQLEOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${dbrootpass}';
CREATE DATABASE IF NOT EXISTS \`${dbname}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}';
GRANT ALL PRIVILEGES ON \`${dbname}\`.* TO '${dbuser}'@'localhost';
FLUSH PRIVILEGES;
SQLEOF
    printf "${GREEN}MariaDB ${T_READY} ✅${NC}\n"
fi

# ════════════════════════════════════════════════════════════════════════════════
# STACK 1: NGINX + PHP-FPM
# ════════════════════════════════════════════════════════════════════════════════
if [ "$stack_choice" == "1" ]; then

    printf '\n'
    printf "${BLUE}===== ${T_INSTALL_NGINX} =====${NC}\n\n"
    eval "${PKG_INSTALL} ${NGINX_PKG}" >> "$MAIN_LOG" 2>&1
    systemctl enable nginx
    systemctl start nginx
    # Hapus default site (apt only)
    [ -f /etc/nginx/sites-enabled/default ] && rm -f /etc/nginx/sites-enabled/default
    printf "${GREEN}Nginx ${T_READY} ✅${NC}\n"

    printf '\n'
    printf "${BLUE}===== ${T_INSTALL_PHP} =====${NC}\n\n"
    eval "${PKG_INSTALL} ${PHP_PKGS}" >> "$MAIN_LOG" 2>&1
    # Deteksi versi PHP — coba php dulu, fallback ke php-fpm --version
    if command -v php &>/dev/null; then
        PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    else
        PHP_VERSION=$(php-fpm --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+' | head -1)
        # Fallback: cari dari nama paket yang terinstall
        [ -z "$PHP_VERSION" ] && PHP_VERSION=$(rpm -qa 'php-common*' 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
        [ -z "$PHP_VERSION" ] && PHP_VERSION=$(dpkg -l 'php*-fpm' 2>/dev/null | grep '^ii' | grep -oP '\d+\.\d+' | head -1)
    fi
    if [ "$PKG_MANAGER" == "apt" ]; then
        systemctl enable "php${PHP_VERSION}-fpm"
        systemctl start "php${PHP_VERSION}-fpm"
    else
        systemctl enable php-fpm
        systemctl start php-fpm
    fi
    printf "${GREEN}PHP ${PHP_VERSION}-FPM ${T_READY} ✅${NC}\n"

    printf '\n'
    printf "⚙️  ${T_VHOST_NGINX}...\n"
    mkdir -p "${WEBROOT}"

    # Tentukan path socket PHP-FPM (berbeda di apt vs yum)
    if [ "$PKG_MANAGER" == "apt" ]; then
        PHP_FPM_SOCK="unix:/run/php/php${PHP_VERSION}-fpm.sock"
    else
        PHP_FPM_SOCK="unix:/run/php-fpm/www.sock"
    fi

    # apt: pakai sites-available/sites-enabled
    if [ "$PKG_MANAGER" == "apt" ]; then
        NGINX_CONF="/etc/nginx/sites-available/${domain}"
        NGINX_LINK="/etc/nginx/sites-enabled/${domain}"
    else
        NGINX_CONF="/etc/nginx/conf.d/${domain}.conf"
        NGINX_LINK=""
    fi

    cat > "${NGINX_CONF}" << EOF
server {
    listen 80;
    server_name ${domain} www.${domain};
    root ${WEBROOT};
    index index.php index.html;

    access_log /var/log/nginx/${domain}_access.log;
    error_log  /var/log/nginx/${domain}_error.log;

    client_max_body_size 64M;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        fastcgi_pass ${PHP_FPM_SOCK};
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht { deny all; }
    location = /xmlrpc.php { deny all; }
}
EOF

    [ -n "${NGINX_LINK}" ] && ln -sf "${NGINX_CONF}" "${NGINX_LINK}"
    nginx -t && systemctl reload nginx
    printf "${GREEN}Nginx virtual host ${T_READY} ✅${NC}\n"
    WEB_USER="www-data"
    [ "$PKG_MANAGER" != "apt" ] && WEB_USER="nginx"
    STACK_NAME="Nginx + PHP-FPM ${PHP_VERSION}"

# ════════════════════════════════════════════════════════════════════════════════
# STACK 2: APACHE2 + PHP
# ════════════════════════════════════════════════════════════════════════════════
elif [ "$stack_choice" == "2" ]; then

    printf '\n'
    printf "${BLUE}===== ${T_INSTALL_APACHE} =====${NC}\n\n"
    eval "${PKG_INSTALL} ${APACHE_PKG}" >> "$MAIN_LOG" 2>&1

    if [ "$PKG_MANAGER" == "apt" ]; then
        APACHE_SVC="apache2"
        systemctl enable apache2
        systemctl start apache2
        a2enmod rewrite
    else
        APACHE_SVC="httpd"
        systemctl enable httpd
        systemctl start httpd
    fi
    printf "${GREEN}Apache ${T_READY} ✅${NC}\n"

    printf '\n'
    printf "${BLUE}===== ${T_INSTALL_PHP} =====${NC}\n\n"
    eval "${PKG_INSTALL} ${PHP_APACHE_PKGS}" >> "$MAIN_LOG" 2>&1
    if command -v php &>/dev/null; then
        PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    else
        PHP_VERSION=$(rpm -qa 'php-common*' 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
        [ -z "$PHP_VERSION" ] && PHP_VERSION=$(dpkg -l 'php*' 2>/dev/null | grep '^ii' | grep -oP '\d+\.\d+' | head -1)
    fi
    printf "${GREEN}PHP ${PHP_VERSION} ${T_READY} ✅${NC}\n"

    printf '\n'
    printf "⚙️  ${T_VHOST_APACHE}...\n"
    mkdir -p "${WEBROOT}"

    if [ "$PKG_MANAGER" == "apt" ]; then
        APACHE_CONF="/etc/apache2/sites-available/${domain}.conf"
    else
        APACHE_CONF="/etc/httpd/conf.d/${domain}.conf"
    fi

    cat > "${APACHE_CONF}" << EOF
<VirtualHost *:80>
    ServerName ${domain}
    ServerAlias www.${domain}
    DocumentRoot ${WEBROOT}

    ErrorLog /var/log/${APACHE_SVC}/${domain}_error.log
    CustomLog /var/log/${APACHE_SVC}/${domain}_access.log combined

    <Directory ${WEBROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

    if [ "$PKG_MANAGER" == "apt" ]; then
        a2ensite "${domain}.conf"
        a2dissite 000-default.conf 2>/dev/null || true
        systemctl reload apache2
    else
        systemctl reload httpd
    fi
    printf "${GREEN}Apache virtual host ${T_READY} ✅${NC}\n"
    WEB_USER="www-data"
    [ "$PKG_MANAGER" != "apt" ] && WEB_USER="apache"
    STACK_NAME="Apache2 + PHP ${PHP_VERSION}"

# ════════════════════════════════════════════════════════════════════════════════
# STACK 3: DOCKER COMPOSE
# ════════════════════════════════════════════════════════════════════════════════
elif [ "$stack_choice" == "3" ]; then

    printf '\n'
    printf "${BLUE}===== ${T_INSTALL_DOCKER} =====${NC}\n\n"
    curl -fsSL https://get.docker.com/ | sh
    systemctl enable docker
    systemctl start docker
    printf "${GREEN}Docker ${T_READY} ✅${NC}\n"

    WEBROOT="/opt/wordpress-${domain}"
    mkdir -p "${WEBROOT}"

    printf '\n'
    printf "⚙️  ${T_DOCKER_COMPOSE}...\n"
    cat > "${WEBROOT}/docker-compose.yml" << EOF
services:
  db:
    image: mariadb:11
    restart: always
    environment:
      MYSQL_DATABASE: ${dbname}
      MYSQL_USER: ${dbuser}
      MYSQL_PASSWORD: ${dbpass}
      MYSQL_ROOT_PASSWORD: ${dbrootpass}
    volumes:
      - db_data:/var/lib/mysql

  wordpress:
    image: wordpress:latest
    restart: always
    ports:
      - "80:80"
    depends_on:
      - db
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_NAME: ${dbname}
      WORDPRESS_DB_USER: ${dbuser}
      WORDPRESS_DB_PASSWORD: ${dbpass}
    volumes:
      - wp_data:/var/www/html

volumes:
  db_data:
  wp_data:
EOF

    cd "${WEBROOT}"
    docker compose up -d
    printf "${GREEN}Docker Compose ${T_READY} ✅${NC}\n"

    printf '\n'
    printf "⏳ ${T_WAITING}...\n"
    sleep 15

    SERVER_IP=$(hostname -I | awk '{print $1}')
    cat > "${CRED_FILE}" << EOF


echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 3/4] Install Wordpress${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

========================================
  WordPress Credentials - ${domain}
  ${T_GENERATED}: $(date)
========================================

  ${T_STACK}       : Docker Compose
  ${T_SITEURL}     : http://${SERVER_IP}

  Database Name  : ${dbname}
  DB Username    : ${dbuser}
  DB Password    : ${dbpass}
  DB Root Pass   : ${dbrootpass}

  ${T_SETUP}      : http://${SERVER_IP}/wp-admin/install.php

  ${T_USEFUL_CMDS}:
    cd ${WEBROOT}
    docker compose ps
    docker compose logs -f
    docker compose down / up -d

========================================
EOF
    chmod 600 "${CRED_FILE}"

    printf '\n'
    printf "${GREEN}╔══════════════════════════════════════════╗\n"
    printf "║   ✅  ${T_FINISH_TITLE}                 ║\n"
    printf "╚══════════════════════════════════════════╝${NC}\n\n"
    printf "${YELLOW}📄 ${T_CRED_SAVED}: ${CRED_FILE}${NC}\n\n"
    cat "${CRED_FILE}"
    exit 0

else
    printf "${RED}${T_INVALID}${NC}\n"
    exit 1
fi

# ─── Download & Install WordPress (Nginx / Apache) ──────────────────────────────
printf '\n'
printf "${BLUE}===== ${T_INSTALL_WP} =====${NC}\n\n"

printf "⬇️  Downloading WordPress...\n"
curl --remote-name --silent --show-error https://wordpress.org/latest.tar.gz
tar --extract --gzip --file latest.tar.gz
rm latest.tar.gz
cp -R -f wordpress/* "${WEBROOT}/"
rm -R wordpress
printf "${GREEN}${T_DONE} ✅${NC}\n"

# ─── Konfigurasi wp-config.php ──────────────────────────────────────────────────
printf '\n'
printf "⚙️  wp-config.php...\n"
cp "${WEBROOT}/wp-config-sample.php" "${WEBROOT}/wp-config.php"

sed -i "s/database_name_here/${dbname}/g" "${WEBROOT}/wp-config.php"
sed -i "s/username_here/${dbuser}/g"      "${WEBROOT}/wp-config.php"
sed -i "s/password_here/${dbpass}/g"      "${WEBROOT}/wp-config.php"

perl -i -pe '
  BEGIN {
    @chars = ("a" .. "z", "A" .. "Z", 0 .. 9);
    push @chars, split //, "!@#$%^&*()-_ []{}<>~\`+=,.;:/?|";
    sub salt { join "", map $chars[ rand @chars ], 1 .. 64 }
  }
  s/put your unique phrase here/salt()/ge
' "${WEBROOT}/wp-config.php"

cat >> "${WEBROOT}/wp-config.php" << 'WPEOF'

/** Disable file editor */
define( 'DISALLOW_FILE_EDIT', true );

/** Limit post revisions */
define( 'WP_POST_REVISIONS', 5 );

/** Auto empty trash */
define( 'EMPTY_TRASH_DAYS', 30 );
WPEOF

printf "${GREEN}${T_DONE} ✅${NC}\n"

# ─── Permission ─────────────────────────────────────────────────────────────────
printf '\n'
printf "🔒 ${T_PERMISSION}...\n"
chown -R "${WEB_USER}:${WEB_USER}" "${WEBROOT}"
find "${WEBROOT}" -type d -exec chmod 755 {} \;
find "${WEBROOT}" -type f -exec chmod 644 {} \;
printf "${GREEN}${T_DONE} ✅${NC}\n"

# ─── Bersihkan File Sisa ────────────────────────────────────────────────────────
printf '\n'
printf "🧹 ${T_CLEANUP}...\n"
rm -f "${WEBROOT}/wp-config-sample.php"
rm -f "${WEBROOT}/readme.html"
rm -f "${WEBROOT}/license.txt"
printf "${GREEN}${T_DONE} ✅${NC}\n"

# ─── Simpan Kredensial ──────────────────────────────────────────────────────────
SERVER_IP=$(hostname -I | awk '{print $1}')

cat > "${CRED_FILE}" << EOF
========================================
  WordPress Credentials - ${domain}
  ${T_GENERATED}: $(date)
========================================

  ${T_STACK}       : ${STACK_NAME}
  ${T_WEBROOT}     : ${WEBROOT}
  ${T_SITEURL}     : http://${domain}
  ${T_SERVERIP}    : ${SERVER_IP}

  Database Name  : ${dbname}
  DB Username    : ${dbuser}
  DB Password    : ${dbpass}
  DB Root Pass   : ${dbrootpass}

  ${T_SETUP}      : http://${SERVER_IP}/wp-admin/install.php

========================================
EOF
chmod 600 "${CRED_FILE}"

# ==============================
# STEP 4
# ==============================
echo ""
echo -e "${YELLOW}--------------------------------------------${NC}"
echo -e "${YELLOW}[STEP 4/4] Finalizing${NC}"
echo -e "${YELLOW}--------------------------------------------${NC}"

# ─── Ringkasan Akhir ────────────────────────────────────────────────────────────
printf '\n'
printf "${GREEN}╔══════════════════════════════════════════╗\n"
printf "║   ✅  ${T_FINISH_TITLE}                ║\n"
printf "╚══════════════════════════════════════════╝${NC}\n\n"
printf "${YELLOW}📄 ${T_CRED_SAVED}: ${CRED_FILE}${NC}\n\n"
printf "${BLUE}${T_NEXT}:${NC}\n"
printf "   1. ${T_NEXT1} ${domain} ${T_NEXT2}\n"
printf "   2. ${T_NEXT3} http://${SERVER_IP}/wp-admin/install.php ${T_NEXT4}\n\n"
cat "${CRED_FILE}"
