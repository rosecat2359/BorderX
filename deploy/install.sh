#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] || error "请使用 root 用户运行"
[[ -f /etc/debian_version ]] || error "仅支持 Debian/Ubuntu"

PANEL_VERSION="${1:-latest}"
INSTALL_DIR="/opt/borderx"

echo ""
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     BorderX Panel 一键安装脚本        ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# 1. 安装系统依赖
# ============================================================
info "安装系统依赖..."
apt-get update -qq
apt-get install -y -qq curl wget nginx postgresql certbot python3-certbot-nginx openssl

# ============================================================
# 2. 配置 PostgreSQL
# ============================================================
info "配置 PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

DB_PASSWORD=$(openssl rand -base64 16)
su - postgres -c "psql -c \"CREATE USER borderx WITH PASSWORD '${DB_PASSWORD}';\"" 2>/dev/null || true
su - postgres -c "psql -c \"CREATE DATABASE borderx OWNER borderx;\"" 2>/dev/null || true
su - postgres -c "psql -c \"ALTER USER borderx CREATEDB;\""

info "数据库用户 borderx 已创建"

# ============================================================
# 3. 下载 Panel 二进制
# ============================================================
info "下载 BorderX Panel..."
mkdir -p "$INSTALL_DIR"

DOWNLOAD_URL="https://github.com/borderx/panel/releases/${PANEL_VERSION}/download/borderx-panel-linux-amd64"
if [[ "$PANEL_VERSION" == "latest" ]]; then
    DOWNLOAD_URL="https://github.com/borderx/panel/releases/latest/download/borderx-panel-linux-amd64"
fi

curl -fsSL "$DOWNLOAD_URL" -o "${INSTALL_DIR}/borderx-panel" 2>/dev/null || {
    warn "GitHub Release 下载失败，尝试使用本地编译版本..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${SCRIPT_DIR}/../server/borderx-panel" ]]; then
        cp "${SCRIPT_DIR}/../server/borderx-panel" "${INSTALL_DIR}/borderx-panel"
        info "已从本地路径复制二进制文件"
    elif [[ -f "./borderx-panel-linux" ]]; then
        cp ./borderx-panel-linux "${INSTALL_DIR}/borderx-panel"
        info "已从当前目录复制二进制文件"
    else
        error "下载失败且未找到本地二进制文件，请手动编译后重试"
    fi
}
chmod +x "${INSTALL_DIR}/borderx-panel"

# ============================================================
# 4. 创建配置文件
# ============================================================
info "创建配置文件..."
JWT_SECRET=$(openssl rand -base64 32)

mkdir -p /etc/borderx

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
YEOF

info "配置文件已保存到 /etc/borderx/config.yml"

# ============================================================
# 5. 创建 systemd 服务
# ============================================================
info "创建系统服务..."
cat > /etc/systemd/system/borderx-panel.service << SEOF
[Unit]
Description=BorderX Panel
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/borderx-panel --config /etc/borderx/config.yml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SEOF

systemctl daemon-reload
systemctl enable borderx-panel

# ============================================================
# 6. 配置 Nginx 反向代理
# ============================================================
info "配置 Nginx 反向代理..."
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
nginx -t && systemctl restart nginx || warn "Nginx 配置检测失败，请检查 /etc/nginx/sites-available/borderx"

# ============================================================
# 7. 启动服务
# ============================================================
info "启动 BorderX Panel..."
systemctl start borderx-panel
sleep 2

if systemctl is-active --quiet borderx-panel; then
    IP=$(curl -s4 ifconfig.me 2>/dev/null || echo "YOUR_IP")
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   BorderX Panel 安装完成!             ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC} 面板地址:  http://${IP}"
    echo -e "${GREEN}║${NC} 管理后台:  http://${IP}/admin"
    echo -e "${GREEN}║${NC} 管理员:    admin / admin123"
    echo -e "${GREEN}║${NC} 配置文件:  /etc/borderx/config.yml"
    echo -e "${GREEN}║${NC} 管理命令:  systemctl status borderx-panel"
    echo -e "${GREEN}║${NC} 查看日志:  journalctl -u borderx-panel -f"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
else
    error "Panel 启动失败，请查看日志: journalctl -u borderx-panel -n 50"
fi
