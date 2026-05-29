#!/bin/bash
set -e

echo "=== BorderX Panel 卸载 ==="
echo ""

# Stop and disable service
if systemctl is-active --quiet borderx-panel 2>/dev/null; then
    systemctl stop borderx-panel
    echo "[OK] 服务已停止"
fi

if systemctl is-enabled --quiet borderx-panel 2>/dev/null; then
    systemctl disable borderx-panel
    echo "[OK] 服务已禁用"
fi

# Remove service file
if [ -f /etc/systemd/system/borderx-panel.service ]; then
    rm -f /etc/systemd/system/borderx-panel.service
    systemctl daemon-reload
    echo "[OK] systemd 服务文件已删除"
fi

# Remove binary
if [ -f /usr/local/bin/borderx-panel ]; then
    rm -f /usr/local/bin/borderx-panel
    echo "[OK] 二进制文件已删除"
fi

# Ask about data
DATA_DIR="/var/lib/borderx"
if [ -d "$DATA_DIR" ]; then
    echo ""
    read -p "是否删除数据目录 $DATA_DIR？(包括数据库和配置) [y/N]: " yn
    if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then
        rm -rf "$DATA_DIR"
        echo "[OK] 数据目录已删除"
    else
        echo "[OK] 数据目录已保留: $DATA_DIR"
    fi
fi

echo ""
echo "=== 卸载完成 ==="
