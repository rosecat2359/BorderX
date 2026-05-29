#!/bin/bash

echo "╔══════════════════════════════════╗"
echo "║     BorderX Panel 卸载           ║"
echo "╚══════════════════════════════════╝"
echo ""

# 询问卸载模式
echo "请选择卸载模式："
echo "  1) 仅停止服务（保留所有文件，可恢复）"
echo "  2) 卸载程序（保留数据）"
echo "  3) 完全清除（程序 + 数据全部删除）"
read -p "请选择 [2]: " MODE
MODE=${MODE:-2}

case "$MODE" in
  1)
    echo "[1/1] 停止服务..."
    systemctl stop borderx-panel 2>/dev/null && echo "[OK] 服务已停止" || echo "[-] 服务未运行"
    systemctl disable borderx-panel 2>/dev/null && echo "[OK] 服务已禁用" || echo "[-] 服务未启用"
    echo "服务已停止，文件保留。恢复: systemctl enable --now borderx-panel"
    ;;
  2)
    echo "[1/3] 停止并禁用服务..."
    systemctl stop borderx-panel 2>/dev/null || true
    systemctl disable borderx-panel 2>/dev/null || true
    rm -f /etc/systemd/system/borderx-panel.service
    systemctl daemon-reload
    echo "[OK]"

    echo "[2/3] 删除程序文件..."
    rm -f /usr/local/bin/borderx-panel
    echo "[OK]"

    echo "[3/3] 数据保留在 /var/lib/borderx"
    echo "如需完全清除，手动执行: rm -rf /var/lib/borderx"
    ;;
  3)
    read -p "⚠ 确定要删除所有数据吗？此操作不可恢复！ [y/N]: " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "已取消"
        exit 0
    fi

    echo "[1/3] 停止并禁用服务..."
    systemctl stop borderx-panel 2>/dev/null || true
    systemctl disable borderx-panel 2>/dev/null || true
    rm -f /etc/systemd/system/borderx-panel.service
    systemctl daemon-reload

    echo "[2/3] 删除程序和数据..."
    rm -f /usr/local/bin/borderx-panel
    rm -rf /var/lib/borderx

    echo "[3/3] 清理完成"
    ;;
  *)
    echo "无效选项"
    exit 1
    ;;
esac

echo ""
echo "╔══════════════════════════════════╗"
echo "║         卸载完成                 ║"
echo "╚══════════════════════════════════╝"
