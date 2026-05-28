#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
    error "请使用 root 用户运行此脚本"
    exit 1
fi

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         BorderX 服务监控面板              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

info "=== 系统信息 ==="
info "主机名: $(hostname)"
info "系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
info "内核: $(uname -r)"
info "运行时间: $(uptime -p)"
info "当前时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

info "=== 资源使用 ==="
info "CPU 使用率: $(top -bn1 | grep "Cpu(s)" | awk '{printf "%.1f%%", $2 + $4}')"
info "内存使用: $(free -h | awk '/Mem:/{printf "%s / %s (%.1f%%)", $3, $2, $3/$2*100}')"
info "磁盘使用: $(df -h / | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}')"
echo ""

info "=== 网络流量 ==="
info "总接收: $(cat /sys/class/net/$(ip route | grep default | awk '{print $5}' | head -1)/statistics/rx_bytes | awk '{printf "%.2f GB", $1/1024/1024/1024}')"
info "总发送: $(cat /sys/class/net/$(ip route | grep default | awk '{print $5}' | head -1)/statistics/tx_bytes | awk '{printf "%.2f GB", $1/1024/1024/1024}')"
echo ""

info "=== 服务状态 ==="
for svc in xray x-ui nginx fail2ban; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        info "${svc}: ${GREEN}运行中${NC}"
    else
        error "${svc}: ${RED}已停止${NC}"
    fi
done
echo ""

info "=== Xray 连接统计 ==="
if systemctl is-active --quiet xray; then
    XRAY_API=/usr/local/bin/xray
    if [[ -x "$XRAY_API" ]]; then
        info "Xray 版本: $($XRAY_API version 2>/dev/null | head -1 || echo '未知')"
    fi
    info "Xray 进程 PID: $(pgrep -x xray || echo '未找到')"
    info "Xray 内存使用: $(ps -p $(pgrep -x xray | head -1) -o rss= 2>/dev/null | awk '{printf "%.1f MB", $1/1024}' || echo '未知')"
fi
echo ""

info "=== Fail2Ban 状态 ==="
if systemctl is-active --quiet fail2ban; then
    fail2ban-client status 2>/dev/null | head -10
    echo ""
    fail2ban-client status sshd 2>/dev/null | grep -E "Currently banned|Total banned|IP list" || true
else
    warn "Fail2Ban 未运行"
fi
echo ""

info "=== 活跃连接 ==="
ESTABLISHED=$(ss -tunp | grep -c ESTAB 2>/dev/null || echo "0")
info "当前活跃 TCP/UDP 连接: ${ESTABLISHED}"
echo ""

info "=== 最近日志 (Xray) ==="
journalctl -u xray --no-pager -n 10 --output=short-iso 2>/dev/null | tail -10 || \
    tail -10 /var/log/xray/error.log 2>/dev/null || warn "无 Xray 日志"
echo ""

info "=== 最近日志 (3X-UI) ==="
journalctl -u x-ui --no-pager -n 5 --output=short-iso 2>/dev/null | tail -5 || warn "无 3X-UI 日志"
