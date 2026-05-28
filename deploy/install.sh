#!/usr/bin/env bash
# ============================================================
# BorderX Panel 一键安装脚本
# 支持 Debian 11+ / Ubuntu 20.04+
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] || error "Please run as root"
[[ -f /etc/debian_version ]] || error "Only Debian/Ubuntu supported"

INSTALL_DIR="/opt/borderx"
REPO="rosecat2359/BorderX"
BIN_NAME="borderx-panel"

echo ""
echo -e "${CYAN}  BorderX Panel 一键安装${NC}"
echo ""

# ---- 1. System deps ----
info "Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq curl wget git nginx postgresql certbot python3-certbot-nginx openssl

# ---- 2. PostgreSQL ----
info "Configuring PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

# Check if user already exists, reuse password if so
if su - postgres -c "psql -t -c \"SELECT 1 FROM pg_roles WHERE rolname='borderx';\"" 2>/dev/null | grep -q 1; then
    info "Database user borderx already exists, preserving password"
else
    DB_PASSWORD=$(openssl rand -base64 16)
    su - postgres -c "psql -c \"CREATE USER borderx WITH PASSWORD '${DB_PASSWORD}';\"" 2>/dev/null || true
    info "Database user borderx created"
fi
su - postgres -c "psql -c \"CREATE DATABASE borderx OWNER borderx;\"" 2>/dev/null || true
su - postgres -c "psql -c \"ALTER USER borderx CREATEDB;\""

# ---- 3. Download or compile binary ----
info "Getting BorderX Panel..."

mkdir -p "$INSTALL_DIR"

DOWNLOAD_OK=false

# Try stable Release first, then pre-release via API
info "Looking for prebuilt binary..."

RELEASE_URL="https://github.com/${REPO}/releases/latest/download/${BIN_NAME}"
curl -fsSL "$RELEASE_URL" -o "${INSTALL_DIR}/${BIN_NAME}" 2>/dev/null && [[ -s "${INSTALL_DIR}/${BIN_NAME}" ]] && DOWNLOAD_OK=true

if ! $DOWNLOAD_OK; then
    # latest may not find pre-release; query API for any release
    API_URL="https://api.github.com/repos/${REPO}/releases?per_page=1"
    ASSET_URL=$(curl -fsSL "$API_URL" 2>/dev/null | grep -o '"browser_download_url": *"[^"]*'"${BIN_NAME}"'"' | head -1 | grep -o 'https://[^"]*')
    if [[ -n "$ASSET_URL" ]]; then
        curl -fsSL "$ASSET_URL" -o "${INSTALL_DIR}/${BIN_NAME}" 2>/dev/null && [[ -s "${INSTALL_DIR}/${BIN_NAME}" ]] && DOWNLOAD_OK=true
    fi
fi

if $DOWNLOAD_OK; then
    info "Downloaded from GitHub Release"
else
    warn "No prebuilt binary found, will compile from source (5-10 min)..."
    echo ""
    echo "  This will install Go + Node.js and build BorderX."
    echo "  For low-spec VPS, consider uploading a prebuilt binary to GitHub Releases."
    echo ""
    read -rp "  Continue? [Y/n]: " do_compile
    [[ "$do_compile" == "n" || "$do_compile" == "N" ]] && error "Aborted. Upload a prebuilt binary to GitHub Releases and re-run."

    if ! command -v go &>/dev/null; then
        info "Installing Go 1.22..."
        GO_TAR="go1.22.10.linux-amd64.tar.gz"
        curl -fsSL "https://go.dev/dl/${GO_TAR}" -o /tmp/${GO_TAR}
        tar -C /usr/local -xzf /tmp/${GO_TAR}
        export PATH=$PATH:/usr/local/go/bin
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    fi

    if ! command -v node &>/dev/null; then
        info "Installing Node.js 20..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>/dev/null
        apt-get install -y -qq nodejs
    fi

    BUILD_DIR="/tmp/borderx-build"
    rm -rf "$BUILD_DIR"
    git clone --depth 1 "https://github.com/${REPO}.git" "$BUILD_DIR"

    info "Building frontend..."
    cd "${BUILD_DIR}/web"
    npm install --silent 2>/dev/null
    npm run build 2>/dev/null

    info "Building backend..."
    mkdir -p "${BUILD_DIR}/server/web/dist"
    cp -r dist/* "${BUILD_DIR}/server/web/dist/"
    cd "${BUILD_DIR}/server"
    go build -o "${BIN_NAME}" ./cmd/panel/
    cp "${BIN_NAME}" "${INSTALL_DIR}/${BIN_NAME}"

    rm -rf "$BUILD_DIR"
    info "Build complete"
fi

chmod +x "${INSTALL_DIR}/${BIN_NAME}"

# ---- 4. Config ----
info "Creating config..."
mkdir -p /etc/borderx

# Get password: reuse if already set, otherwise generate
if [[ -f /etc/borderx/config.yml ]]; then
    DB_PASSWORD=$(grep 'password:' /etc/borderx/config.yml | head -1 | sed 's/.*password: *"\([^"]*\)".*/\1/')
fi
if [[ -z "${DB_PASSWORD:-}" ]]; then
    DB_PASSWORD=$(openssl rand -base64 16)
fi

JWT_SECRET=$(openssl rand -base64 32)

cat > /etc/borderx/config.yml << YEOF
server:
  port: 8080
  mode: release
database:
  host: localhost
  port: 5432
  user: borderx
  password: "${DB_PASSWORD}"
  dbname: borderx
  sslmode: disable
jwt:
  secret: "${JWT_SECRET}"
  expire_hour: 24
xray:
  config_path: /usr/local/etc/xray/config.json
  stats_port: 10085
  binary_path: /usr/local/bin/xray
smtp:
  host: ""
  port: 587
  username: ""
  password: ""
  from: ""
alipay:
  app_id: ""
  private_key: ""
  alipay_pub_key: ""
  notify_domain: ""
YEOF

# ---- 5. systemd ----
info "Creating systemd service..."
cat > /etc/systemd/system/borderx-panel.service << SEOF
[Unit]
Description=BorderX Panel
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/${BIN_NAME} --config /etc/borderx/config.yml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SEOF

systemctl daemon-reload
systemctl enable borderx-panel

# ---- 6. Nginx ----
info "Configuring Nginx..."
cat > /etc/nginx/sites-available/borderx << NEOF
server {
    listen 80;
    server_name _;
    client_max_body_size 50m;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NEOF

ln -sf /etc/nginx/sites-available/borderx /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

# ---- 7. Start ----
info "Starting BorderX Panel..."
systemctl start borderx-panel
sleep 2

if systemctl is-active --quiet borderx-panel; then
    IP=$(curl -s4 ifconfig.me 2>/dev/null || echo "YOUR_IP")
    echo ""
    echo -e "${GREEN}  BorderX Panel installed!${NC}"
    echo ""
    echo -e "  URL:      http://${IP}"
    echo -e "  Admin:    http://${IP}/admin"
    echo -e "  Login:    admin / admin123"
    echo -e "  Config:   /etc/borderx/config.yml"
    echo -e "  Status:   systemctl status borderx-panel"
    echo ""
else
    echo ""
    warn "Panel failed to start. Check logs: journalctl -u borderx-panel -n 50"
    echo ""
fi
