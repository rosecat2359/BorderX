#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
    error "请使用 root 用户运行此脚本"
fi

echo -e "${YELLOW}警告: 此操作将完全卸载 BorderX 服务及所有相关组件!${NC}"
read -rp "确认卸载? 输入 YES 继续: " confirm

if [[ "$confirm" != "YES" ]]; then
    info "卸载已取消"
    exit 0
fi

info "停止服务..."
systemctl stop xray 2>/dev/null || true
systemctl stop x-ui 2>/dev/null || true
systemctl disable xray 2>/dev/null || true
systemctl disable x-ui 2>/dev/null || true

info "删除 systemd 服务文件..."
rm -f /etc/systemd/system/xray.service
rm -f /etc/systemd/system/x-ui.service
systemctl daemon-reload

info "删除 Xray 程序和配置..."
rm -f /usr/local/bin/xray
rm -rf /usr/local/etc/xray
rm -rf /var/log/xray

info "删除 3X-UI 面板..."
rm -rf /usr/local/x-ui
rm -f /etc/x-ui/x-ui.db

info "删除 Nginx 配置..."
rm -f /etc/nginx/sites-available/borderx-panel
rm -f /etc/nginx/sites-enabled/borderx-panel
systemctl restart nginx 2>/dev/null || true

info "删除安装目录..."
rm -rf /usr/local/borderx

info "删除日志轮转配置..."
rm -f /etc/logrotate.d/xray

info "删除安全加固配置 (可选)..."
read -rp "是否同时移除安全加固配置? (y/N): " remove_hardening
if [[ "$remove_hardening" == "y" || "$remove_hardening" == "Y" ]]; then
    rm -f /etc/sysctl.d/99-borderx-hardening.conf
    sysctl --system > /dev/null 2>&1
    rm -f /etc/modprobe.d/borderx-blacklist.conf
    rm -f /etc/fail2ban/jail.local
    systemctl restart fail2ban 2>/dev/null || true
    info "安全加固配置已移除"
fi

info "清理完成!"
echo ""
info "以下组件仍保留在系统中 (如需移除请手动执行):"
info "  - Nginx: apt-get remove --purge nginx"
info "  - Fail2Ban: apt-get remove --purge fail2ban"
info "  - Certbot: apt-get remove --purge certbot python3-certbot-nginx"
info "  - 备份数据: rm -rf /opt/borderx-backups"
