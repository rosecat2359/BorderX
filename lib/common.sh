#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# BorderX 公共函数库
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

INSTALL_DIR="/usr/local/borderx"
LOG_FILE="/var/log/borderx-install.log"
XRAY_VERSION=""
LOW_MEMORY=false

# 回退版本 — 当 GitHub API 不可用时的兜底值
# 维护提示：定期更新为最近稳定版本
XRAY_FALLBACK_VERSION="v26.3.27"
XUI_FALLBACK_VERSION="v3.1.0"

GITHUB_MIRRORS=(
    "https://github.com"
    "https://ghfast.top/https://github.com"
    "https://mirror.ghproxy.com/https://github.com"
)

# 日志函数 — 容错设计，tee 失败不影响脚本
_log()   { local tag="$1"; shift; echo -e "${tag}$*${NC}"; echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true; }
info()   { _log "${GREEN}[INFO] " "$@"; }
warn()   { _log "${YELLOW}[WARN] " "$@"; }
error()  { _log "${RED}[ERROR] " "$@"; exit 1; }

check_root() { [[ $EUID -eq 0 ]] || { echo -e "${RED}[ERROR]${NC} 请使用 root 用户运行"; exit 1; }; }

check_os() {
    # 支持 Debian 系: Debian / Ubuntu / 及其衍生版
    if [[ -f /etc/os-release ]]; then
        local id; id=$(grep -oP '^ID=\K.*' /etc/os-release | tr -d '"')
        [[ "$id" =~ ^(debian|ubuntu|Debian|Ubuntu) ]] || warn "非标准 Debian/Ubuntu 系统: ${id}，可能不完全兼容"
    elif [[ -f /etc/debian_version ]]; then
        :  # OK, Debian 系
    else
        error "仅支持 Debian/Ubuntu 系统"
    fi
    info "系统检测通过"
}

check_memory() {
    local mem_mb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024))
    info "内存: ${mem_mb}MB"
    if [[ $mem_mb -le 1024 ]]; then
        LOW_MEMORY=true
        warn "低内存模式 (<=1GB): 仅 VLESS Reality + Swap"
    fi
}

generate_uuid() { cat /proc/sys/kernel/random/uuid; }
generate_password() { openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16; }

download_fallback() {
    local out="$1"; shift; local urls=("$@")
    for url in "${urls[@]}"; do
        rm -f "$out"
        wget --timeout=60 --tries=1 -O "$out" "$url" 2>/dev/null && [[ -s "$out" ]] && { info "下载成功"; return 0; }
    done
    warn "所有镜像下载失败"
    return 1
}

safe_write() { local t; t=$(mktemp); cat > "$t"; mv "$t" "$1"; }
