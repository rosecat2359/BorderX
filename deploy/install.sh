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

# 默认值
INSTALL_DIR="/usr/local/bin"
DATA_DIR="/var/lib/borderx"
PANEL_PORT="8080"
INSTALL_XRAY="Y"

# 交互模式（有终端时才提问）
if [ -t 0 ]; then
  read -p "安装目录 [$INSTALL_DIR]: " INPUT; INSTALL_DIR=${INPUT:-$INSTALL_DIR}
  read -p "数据目录 [$DATA_DIR]: " INPUT; DATA_DIR=${INPUT:-$DATA_DIR}
  read -p "面板端口 [$PANEL_PORT]: " INPUT; PANEL_PORT=${INPUT:-$PANEL_PORT}
  read -p "是否安装 Xray-core？(已安装选 n) [Y/n]: " INPUT; INSTALL_XRAY=${INPUT:-Y}
  echo ""
  echo "════════════════════════════════════"
  echo "  安装目录: $INSTALL_DIR"
  echo "  数据目录: $DATA_DIR"
  echo "  面板端口: $PANEL_PORT"
  echo "  安装Xray: $INSTALL_XRAY"
  echo "════════════════════════════════════"
  read -p "确认安装? [Y/n]: " CONFIRM
  if [ "$CONFIRM" != "Y" ] && [ "$CONFIRM" != "y" ] && [ -n "$CONFIRM" ]; then
    echo "已取消"; exit 0
  fi
else
  echo "[非交互模式] 使用默认配置安装"
  echo "  安装目录: $INSTALL_DIR"
  echo "  数据目录: $DATA_DIR"
  echo "  面板端口: $PANEL_PORT"
fi

echo ""
echo "[1/3] 下载 BorderX Panel..."

BIN_URLS=(
  "https://github.com/rosecat2359/BorderX/releases/download/v2.0.0/borderx-panel-linux-${BIN_ARCH}"
  "https://ghproxy.com/https://github.com/rosecat2359/BorderX/releases/download/v2.0.0/borderx-panel-linux-${BIN_ARCH}"
)

DOWNLOADED=0
for URL in "${BIN_URLS[@]}"; do
  echo "尝试: $URL"
  if curl -fsSL --connect-timeout 10 "$URL" -o "${INSTALL_DIR}/borderx-panel" 2>/dev/null; then
    DOWNLOADED=1; break
  fi
  echo "失败，尝试下一个..."
done

if [ $DOWNLOADED -eq 0 ]; then
  echo "下载失败！请手动下载: https://github.com/rosecat2359/BorderX/releases/latest"
  exit 1
fi

chmod +x "${INSTALL_DIR}/borderx-panel"
echo "[OK] 二进制 → ${INSTALL_DIR}/borderx-panel"
mkdir -p "$DATA_DIR"

if [ "$INSTALL_XRAY" = "Y" ] || [ "$INSTALL_XRAY" = "y" ]; then
  echo "[2/3] 安装依赖 + Xray-core..."

  # 安装必要依赖
  if command -v apt &>/dev/null; then
    apt update -qq && apt install -y -qq unzip curl 2>/dev/null
  elif command -v yum &>/dev/null; then
    yum install -y unzip curl 2>/dev/null
  fi

  bash -c "$(curl -sL https://ghproxy.com/https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --beta 2>/dev/null || \
  bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --beta 2>/dev/null || \
  echo "[!] Xray 安装失败，请手动安装"
else
  echo "[2/3] 跳过 Xray 安装"
fi

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
echo "║  面板: http://$(hostname -I | awk '{print $1}'):${PANEL_PORT}       ║"
echo "║  数据: ${DATA_DIR}                ║"
echo "║  管理: systemctl status borderx-panel  ║"
echo "╚══════════════════════════════════╝"
echo ""
echo "首次访问需设置管理员密码"
echo "交互安装: curl -sL .../install.sh -o install.sh && bash install.sh"
