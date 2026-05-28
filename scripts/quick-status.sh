#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# BorderX 一键状态查看 — 服务状态、资源、流量、关键信息
# ============================================================

INSTALL_DIR="/usr/local/borderx"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'; DIM='\033[2m'

ok()    { echo -e "  ${GREEN}Running${NC}"; }
fail()  { echo -e "  ${RED}Stopped${NC}"; }

echo -e "${BOLD}BorderX 状态报告${NC}  $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${DIM}$(printf '─%.0s' {1..55})${NC}"

# ---- 服务状态 ----
echo -e "\n${BOLD}服务状态${NC}"
for svc in xray x-ui nginx fail2ban ufw; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        printf "  %-15s" "$svc"; ok
    else
        printf "  %-15s" "$svc"; fail
    fi
done

# ---- 系统资源 ----
echo -e "\n${BOLD}系统资源${NC}"
# CPU
read -r cpu_load _ <<< "$(awk '{printf "%.0f", $1*100}' /proc/loadavg)"
echo -e "  CPU 负载:       ${cpu_load}%"
# Memory
read -r mem_total mem_used _ <<< "$(free -m | awk '/Mem:/{print $2, $3, $4}')"
mem_pct=$(( mem_used * 100 / mem_total ))
echo -e "  内存:           ${mem_used}MB / ${mem_total}MB (${mem_pct}%)"
# Disk
read -r disk_pct _ <<< "$(df -h / | awk 'NR==2{print $5}' | tr -d '%')"
disk_info=$(df -h / | awk 'NR==2{print $3"/"$2}')
echo -e "  磁盘 (/):       ${disk_info} (${disk_pct}%)"
# Swap
swap_info=$(swapon --show 2>/dev/null | awk 'NR>1{printf "%s / %s", $3, $4}' || echo "无")
[[ -z "$swap_info" ]] && swap_info="无"
echo -e "  Swap:           ${swap_info}"

# ---- 网络端口 ----
echo -e "\n${BOLD}监听端口${NC}"
# 只显示 BorderX 相关的监听端口
ports=$(ss -tlnp 2>/dev/null | grep -E ':(443|8443|10001|10002|2053|10085)\s' || true)
if [[ -n "$ports" ]]; then
    echo "$ports" | while read -r line; do
        port=$(echo "$line" | grep -oP ':\K\d+')
        svc=$(echo "$line" | grep -oP 'users:\(\("([^"]+)"' | cut -d'"' -f2 || echo "?")
        printf "  %-5s  %s\n" "$port" "$svc"
    done
else
    echo -e "  ${RED}无 BorderX 端口在监听！${NC}"
fi

# ---- 活跃连接数 ----
echo -e "\n${BOLD}连接统计${NC}"
if ss -tn state established 2>/dev/null | grep -q ':443 '; then
    conn_count=$(ss -tn state established 2>/dev/null | grep -c ':443 ' || echo 0)
    echo -e "  VLESS Reality 活跃连接: ${conn_count}"
else
    echo -e "  VLESS Reality 活跃连接: 0"
fi

# ---- 面板信息 ----
echo -e "\n${BOLD}面板信息${NC}"
if [[ -f "${INSTALL_DIR}/install-info.env" ]]; then
    source "${INSTALL_DIR}/install-info.env" 2>/dev/null || true
    echo -e "  地址:       ${PANEL_URL:-未找到}"
    echo -e "  用户名:     ${PANEL_USERNAME:-admin}"
    echo -e "  安装日期:   ${INSTALL_DATE:-未知}"
    echo -e "  Xray 版本:  ${XRAY_VERSION:-未知}"
    echo -e "  模式:       $([[ "${LOW_MEMORY:-}" == "true" ]] && echo "低内存 (仅 VLESS)" || echo "标准 (VLESS+VMess+Trojan)")"
fi

# ---- 备份信息 ----
echo -e "\n${BOLD}最近备份${NC}"
backup_dir="/opt/borderx-backups"
if [[ -d "$backup_dir" ]]; then
    latest=$(ls -1t "$backup_dir"/*.tar.gz 2>/dev/null | head -1)
    if [[ -n "$latest" ]]; then
        size=$(du -h "$latest" | cut -f1)
        echo -e "  最新:  $(basename "$latest") (${size})"
        count=$(ls -1 "$backup_dir"/*.tar.gz 2>/dev/null | wc -l)
        echo -e "  总数:  ${count} 份"
    else
        echo -e "  ${YELLOW}暂无备份${NC}"
    fi
else
    echo -e "  ${YELLOW}备份目录不存在${NC}"
fi

# ---- 最近错误 ----
echo -e "\n${BOLD}最近 Xray 错误${NC} (最后 5 条)"
if journalctl -u xray --no-pager -n 5 2>/dev/null | grep -iE 'error|warn|failed' | head -5; then
    :
else
    echo -e "  ${GREEN}无异常${NC}"
fi

echo -e "\n${DIM}$(printf '─%.0s' {1..55})${NC}"
echo -e "${CYAN}快捷命令:${NC}"
echo -e "  详细监控:  bash ${INSTALL_DIR}/scripts/monitor.sh"
echo -e "  健康检查:  bash ${INSTALL_DIR}/scripts/health-check.sh"
echo -e "  查看日志:  journalctl -u xray -f"
echo -e "  面板密码:  source ${INSTALL_DIR}/install-info.env && echo \$PANEL_PASSWORD"
echo ""
