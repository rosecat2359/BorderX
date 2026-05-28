#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# BorderX 防火墙同步脚本
# 读取 Xray 入站端口，自动同步 UFW 规则
# 用法：  bash sync-firewall.sh         # 详细输出
#        bash sync-firewall.sh --quiet  # 静默（仅变更/错误时输出）
# ============================================================

QUIET=false
if [[ "${1:-}" == "--quiet" ]]; then QUIET=true; fi

XRAY_CONFIG="${XRAY_CONFIG:-/usr/local/etc/xray/config.json}"
UFW="$(command -v ufw || true)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log()   { $QUIET || echo -e "$@"; }
ok()    { $QUIET || echo -e "  ${GREEN}+${NC} $*"; }
rmv()   { $QUIET || echo -e "  ${RED}-${NC} $*"; }
skip()  { $QUIET || echo -e "  ${YELLOW}~${NC} $*     (已放行)"; }

# 错误永远输出
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then
    err "请使用 root 用户运行"
fi

if [[ ! -f "$XRAY_CONFIG" ]]; then
    err "Xray 配置文件不存在: ${XRAY_CONFIG}"
fi

if [[ -z "$UFW" ]]; then
    err "UFW 未安装，请先运行: apt install ufw"
fi

PRESERVE_PORTS=(22)

# ---- 1. 提取 Xray 入站端口 ----
log "读取 Xray 入站配置: ${XRAY_CONFIG}"

XRAY_PORTS=()
while IFS= read -r port; do
    XRAY_PORTS+=("$port")
done < <(jq -r '
    .inbounds[]
    | select(.tag != "api")
    | select(.listen == "0.0.0.0" or .listen == "::" or .listen == null or .listen == "")
    | .port
' "$XRAY_CONFIG" 2>/dev/null | sort -n | uniq)

if [[ ${#XRAY_PORTS[@]} -eq 0 ]]; then
    err "未从 Xray 配置中找到任何非 API 入站端口"
fi

log ""
log "Xray 入站端口: ${XRAY_PORTS[*]}"
log "保留端口:      ${PRESERVE_PORTS[*]}"
log ""
log "同步中..."

# ---- 2. 加 Xray 端口 ----
ADDED=0
for port in "${XRAY_PORTS[@]}"; do
    if ufw status verbose 2>/dev/null | grep -q "^${port}/tcp.*ALLOW IN"; then
        skip "${port}/tcp"
        continue
    fi
    ok "添加 ${port}/tcp"
    ufw allow "${port}/tcp" comment "BorderX auto" >> /dev/null 2>&1
    ADDED=$((ADDED + 1))
done

# ---- 3. 清理不在 Xray 配置中的 BorderX 旧规则 ----
CLEANED=0
while IFS= read -r line; do
    port=$(echo "$line" | grep -oP '\d+(?=/tcp)' | head -1)
    [[ -z "$port" ]] && continue

    local skip_this=false
    for p in "${PRESERVE_PORTS[@]}"; do
        [[ "$port" == "$p" ]] && skip_this=true && break
    done
    $skip_this && continue

    if ! echo "$line" | grep -qi "BorderX"; then
        continue
    fi

    local still_exists=false
    for xp in "${XRAY_PORTS[@]}"; do
        [[ "$port" == "$xp" ]] && still_exists=true && break
    done

    if ! $still_exists; then
        rmv "移除 ${port}/tcp (不在 Xray 配置中)"
        yes | ufw delete allow "${port}/tcp" >> /dev/null 2>&1 || true
        CLEANED=$((CLEANED + 1))
    fi
done < <(ufw status numbered 2>/dev/null | grep 'ALLOW' || true)

# ---- 4. 确保保留端口存在 ----
for port in "${PRESERVE_PORTS[@]}"; do
    if ! ufw status verbose 2>/dev/null | grep -q "^${port}/tcp.*ALLOW IN"; then
        ok "恢复保留端口 ${port}/tcp"
        ufw allow "${port}/tcp" comment "SSH" >> /dev/null 2>&1
        ADDED=$((ADDED + 1))
    fi
done

# ---- 5. 报告 ----
if [[ $ADDED -gt 0 || $CLEANED -gt 0 ]]; then
    # 有变更时始终输出
    echo -e "[BorderX] 防火墙同步: +${ADDED} 条规则, -${CLEANED} 条规则  ($(date '+%H:%M:%S'))"
else
    # 无变更时，非静默模式输出汇总，静默模式不输出
    if ! $QUIET; then
        echo ""
        echo "============================================"
        echo "  同步完成 — 无变更"
        echo "============================================"
        echo ""
        echo "当前 BorderX 防火墙规则:"
        ufw status verbose 2>/dev/null | grep -i "BorderX\|SSH" || echo "  (无)"
    fi
fi
