#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# BorderX 服务健康检查脚本
# 检测 Xray 和 3X-UI 的运行状态，异常时自动恢复
# 建议通过 cron 每 5 分钟执行一次
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOG_FILE="/var/log/borderx-healthcheck.log"
ALERT_COOLDOWN_FILE="/var/tmp/borderx-alert-cooldown"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

# ---- 检查 Xray ----
check_xray() {
    if systemctl is-active --quiet xray 2>/dev/null; then
        return 0
    fi

    log "WARN: Xray 服务已停止，尝试重启..."
    echo -e "${YELLOW}[WARN]${NC} Xray 服务已停止，尝试重启..."

    systemctl restart xray 2>/dev/null || true
    sleep 3

    if systemctl is-active --quiet xray 2>/dev/null; then
        log "OK: Xray 重启成功"
        echo -e "${GREEN}[OK]${NC} Xray 重启成功"
        return 0
    fi

    log "ERROR: Xray 重启失败！"
    echo -e "${RED}[ERROR]${NC} Xray 重启失败！请检查: journalctl -u xray"
    return 1
}

# ---- 检查 3X-UI ----
check_xui() {
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        return 0
    fi

    log "WARN: 3X-UI 面板已停止，尝试重启..."
    echo -e "${YELLOW}[WARN]${NC} 3X-UI 面板已停止，尝试重启..."

    systemctl restart x-ui 2>/dev/null || true
    sleep 3

    if systemctl is-active --quiet x-ui 2>/dev/null; then
        log "OK: 3X-UI 重启成功"
        echo -e "${GREEN}[OK]${NC} 3X-UI 重启成功"
        return 0
    fi

    log "ERROR: 3X-UI 重启失败！"
    echo -e "${RED}[ERROR]${NC} 3X-UI 重启失败！请检查: journalctl -u x-ui"
    return 1
}

# ---- 检查内存使用 (OOM 预警) ----
check_memory() {
    local mem_used_pct
    mem_used_pct=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')

    if [[ "$mem_used_pct" -gt 90 ]]; then
        log "WARN: 内存使用率 ${mem_used_pct}%，可能存在 OOM 风险"
        echo -e "${YELLOW}[WARN]${NC} 内存使用率 ${mem_used_pct}%，建议运行: bash scripts/optimize-lowmem.sh"
    fi
}

# ---- 检查磁盘空间 ----
check_disk() {
    local disk_used_pct
    disk_used_pct=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

    if [[ "$disk_used_pct" -gt 90 ]]; then
        log "WARN: 磁盘使用率 ${disk_used_pct}%"
        echo -e "${YELLOW}[WARN]${NC} 磁盘使用率 ${disk_used_pct}%，建议清理空间"
    fi
}

# ---- 主流程 ----
main() {
    local exit_code=0

    echo -e "${GREEN}=== BorderX 健康检查 $(date '+%Y-%m-%d %H:%M:%S') ===${NC}"

    check_xray  || exit_code=1
    check_xui   || exit_code=1
    check_memory
    check_disk

    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}所有服务运行正常${NC}"
    else
        echo -e "${RED}部分服务异常，详见上述输出${NC}"
    fi

    exit $exit_code
}

main "$@"
