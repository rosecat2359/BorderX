#!/bin/bash
set -e

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  BIN_ARCH="amd64" ;;
  aarch64) BIN_ARCH="arm64" ;;
  *) echo "不支持架构: $ARCH"; exit 1 ;;
esac

INSTALL_DIR="/usr/local/bin"
DATA_DIR="/var/lib/borderx"
CONFIG_DIR="/etc/borderx"

echo "=== BorderX Panel v2.0 安装 ==="
echo "架构: ${BIN_ARCH}"

mkdir -p "$DATA_DIR" "$CONFIG_DIR"

# Download binary
BIN_URL="https://github.com/rosecat2359/BorderX/releases/latest/download/borderx-panel-linux-${BIN_ARCH}"
echo "下载: $BIN_URL"
curl -sL "$BIN_URL" -o "${INSTALL_DIR}/borderx-panel"
chmod +x "${INSTALL_DIR}/borderx-panel"

# Create systemd service
cat > /etc/systemd/system/borderx-panel.service << SERVICE
[Unit]
Description=BorderX Panel
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/borderx-panel --data-dir ${DATA_DIR}
WorkingDirectory=${DATA_DIR}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable borderx-panel
systemctl start borderx-panel

IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
echo "=== 安装完成 ==="
echo "面板: http://${IP}:8080"
echo "首次启动需要设置管理员密码"
