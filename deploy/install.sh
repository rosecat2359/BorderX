#!/bin/bash
set -e

echo "╔══════════════════════════════════╗"
echo "║     BorderX Panel v2.0 安装      ║"
echo "╚══════════════════════════════════╝"
echo ""

# 检测架构
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  BIN_ARCH="amd64" ;;
  aarch64) BIN_ARCH="arm64" ;;
  *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac

# 询问安装目录
read -p "安装目录 [/usr/local/bin]: " INSTALL_DIR < /dev/tty
INSTALL_DIR=${INSTALL_DIR:-/usr/local/bin}

# 询问数据目录
read -p "数据目录 [/var/lib/borderx]: " DATA_DIR < /dev/tty
DATA_DIR=${DATA_DIR:-/var/lib/borderx}

# 询问端口
read -p "面板端口 [8080]: " PANEL_PORT < /dev/tty
PANEL_PORT=${PANEL_PORT:-8080}

# 询问是否安装 Xray
read -p "是否安装 Xray-core？(已安装选 n) [Y/n]: " INSTALL_XRAY < /dev/tty
INSTALL_XRAY=${INSTALL_XRAY:-Y}

echo ""
echo "════════════════════════════════════"
echo "  安装目录: $INSTALL_DIR"
echo "  数据目录: $DATA_DIR"
echo "  面板端口: $PANEL_PORT"
echo "  安装Xray: $INSTALL_XRAY"
echo "════════════════════════════════════"
read -p "确认安装? [Y/n]: " CONFIRM < /dev/tty
CONFIRM=${CONFIRM:-Y}
if [ "$CONFIRM" != "Y" ] && [ "$CONFIRM" != "y" ]; then
    echo "已取消"
    exit 0
fi

echo ""
echo "[1/3] 下载 BorderX Panel..."

# 尝试多个下载源
BIN_URLS=(
    "https://ghproxy.com/https://github.com/rosecat2359/BorderX/releases/latest/download/borderx-panel-linux-${BIN_ARCH}"
    "https://github.com/rosecat2359/BorderX/releases/latest/download/borderx-panel-linux-${BIN_ARCH}"
)

DOWNLOADED=0
for URL in "${BIN_URLS[@]}"; do
    echo "尝试: $URL"
    if curl -fsSL --connect-timeout 10 "$URL" -o "${INSTALL_DIR}/borderx-panel" 2>/dev/null; then
        DOWNLOADED=1
        break
    fi
    echo "失败，尝试下一个..."
done

if [ $DOWNLOADED -eq 0 ]; then
    echo "下载失败，请手动下载并放置到 ${INSTALL_DIR}/borderx-panel"
    exit 1
fi

chmod +x "${INSTALL_DIR}/borderx-panel"
echo "[OK] 二进制已安装到 ${INSTALL_DIR}/borderx-panel"

mkdir -p "$DATA_DIR"

# 安装 Xray
if [ "$INSTALL_XRAY" = "Y" ] || [ "$INSTALL_XRAY" = "y" ]; then
    echo "[2/3] 安装 Xray-core..."
    bash -c "$(curl -sL https://ghproxy.com/https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --beta 2>/dev/null || \
    bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --beta 2>/dev/null || \
    echo "[!] Xray 安装失败，请手动安装"
else
    echo "[2/3] 跳过 Xray 安装"
fi

# 创建 systemd 服务
echo "[3/3] 创建 systemd 服务..."
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
systemctl restart borderx-panel

echo ""
echo "╔══════════════════════════════════╗"
echo "║         安装完成！               ║"
echo "╠══════════════════════════════════╣"
echo "║  面板地址: http://$(hostname -I | awk '{print $1}'):${PANEL_PORT}"
echo "║  数据目录: ${DATA_DIR}"
echo "║  管理命令: systemctl status/restart/stop borderx-panel"
echo "║  卸载命令: curl -sL https://raw.githubusercontent.com/rosecat2359/BorderX/main/deploy/uninstall.sh | bash"
echo "╚══════════════════════════════════╝"
echo ""
echo "首次访问需设置管理员密码"
