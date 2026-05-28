#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# BorderX 一键更新脚本
# 免责声明: 本脚本仅供学习研究使用，使用者需遵守当地法律法规。
# 自动检测并更新 Xray-core / 3X-UI，保留所有用户配置
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

BACKUP_DIR="/opt/borderx-backups"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
XUI_DIR="/usr/local/x-ui"

GITHUB_MIRRORS=(
    "https://github.com"
    "https://ghfast.top/https://github.com"
    "https://mirror.ghproxy.com/https://github.com"
)

if [[ $EUID -ne 0 ]]; then error "请使用 root 用户运行"; fi

echo -e "${CYAN}  BorderX 一键更新${NC}"
echo ""

# ---- 备份 ----
backup_before_update() {
    info "更新前备份配置..."
    mkdir -p "$BACKUP_DIR"
    local ts; ts=$(date +%Y%m%d_%H%M%S)
    local dir="${BACKUP_DIR}/pre-update-${ts}"
    mkdir -p "$dir"

    cp -r /usr/local/etc/xray "$dir/xray-config" 2>/dev/null || true
    cp /etc/x-ui/x-ui.db "$dir/x-ui.db" 2>/dev/null || true
    cp /usr/local/borderx/install-info.env "$dir/" 2>/dev/null || true

    tar -czf "${BACKUP_DIR}/pre-update-${ts}.tar.gz" -C "$BACKUP_DIR" "pre-update-${ts}" 2>/dev/null
    rm -rf "$dir"
    info "备份: ${BACKUP_DIR}/pre-update-${ts}.tar.gz"
}

# ---- 下载工具 ----
download_fallback() {
    local out="$1"; shift; local urls=("$@")
    for url in "${urls[@]}"; do
        rm -f "$out"
        wget --timeout=60 --tries=1 -O "$out" "$url" 2>/dev/null && [[ -s "$out" ]] && return 0
    done
    return 1
}

# ---- 更新 Xray ----
update_xray() {
    info "检查 Xray-core 更新..."
    local current; current=$("$XRAY_BIN" version 2>/dev/null | grep -oP 'Xray \K[0-9.]+' | head -1 || echo "0")
    local latest; latest=$(curl -sL "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null | grep -o '"tag_name":"[^"]*"' | head -1 | grep -o 'v[^"]*' | tr -d '"' | sed 's/^v//')

    [[ -z "$latest" ]] && { warn "无法获取 Xray 最新版本，跳过"; return; }

    if [[ "$current" == "$latest" ]]; then
        info "Xray 已是最新 (v${current})，跳过"
        return
    fi

    info "发现新版本: v${current} → v${latest}"
    read -rp "更新 Xray? [Y/n]: " confirm
    [[ "$confirm" == "n" || "$confirm" == "N" ]] && { info "跳过 Xray 更新"; return; }

    local arch; arch=$(dpkg --print-architecture)
    case "$arch" in amd64) arch="64" ;; arm64) arch="arm64-v8a" ;; *) error "不支持的架构: $arch" ;; esac

    local tmpdir; tmpdir=$(mktemp -d)
    local urls=()
    for m in "${GITHUB_MIRRORS[@]}"; do urls+=("${m}/XTLS/Xray-core/releases/download/v${latest}/Xray-linux-${arch}.zip"); done

    if ! download_fallback "${tmpdir}/xray.zip" "${urls[@]}"; then
        warn "Xray 下载失败，跳过"
        rm -rf "$tmpdir"; return
    fi

    unzip -o "${tmpdir}/xray.zip" -d "${tmpdir}/extract" > /dev/null 2>&1
    systemctl stop xray
    cp "${tmpdir}/extract/xray" "$XRAY_BIN"; chmod +x "$XRAY_BIN"
    rm -rf "$tmpdir"

    # 验证配置
    if "$XRAY_BIN" run -test -config "$XRAY_CONFIG" > /dev/null 2>&1; then
        systemctl start xray
        info "Xray 更新完成: v${latest}"
    else
        warn "配置验证失败，已回滚旧版本请检查: xray run -test -config $XRAY_CONFIG"
        systemctl start xray  # 尝试用旧配置启动
    fi
}

# ---- 更新 3X-UI ----
update_xui() {
    info "检查 3X-UI 更新..."
    local current; current=$(cat /usr/local/x-ui/bin/config.json 2>/dev/null | grep -oP '"version":\s*"\K[^"]+' || echo "0")
    local latest; latest=$(curl -sL "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" 2>/dev/null | grep -o '"tag_name":"[^"]*"' | head -1 | grep -o 'v[^"]*' | tr -d '"' | sed 's/^v//')

    [[ -z "$latest" ]] && { warn "无法获取 3X-UI 最新版本，跳过"; return; }

    if [[ "$current" == "$latest" ]]; then
        info "3X-UI 已是最新 (v${current})，跳过"
        return
    fi

    info "发现新版本: v${current} → v${latest}"
    read -rp "更新 3X-UI? [Y/n]: " confirm
    [[ "$confirm" == "n" || "$confirm" == "N" ]] && { info "跳过 3X-UI 更新"; return; }

    local arch; arch=$(dpkg --print-architecture)
    case "$arch" in amd64) arch="amd64" ;; arm64) arch="arm64" ;; *) error "不支持的架构" ;; esac

    local tmpdir; tmpdir=$(mktemp -d)
    local urls=()
    for m in "${GITHUB_MIRRORS[@]}"; do urls+=("${m}/MHSanaei/3x-ui/releases/download/v${latest}/x-ui-linux-${arch}.tar.gz"); done

    if ! download_fallback "${tmpdir}/x-ui.tar.gz" "${urls[@]}"; then
        warn "3X-UI 下载失败，跳过"
        rm -rf "$tmpdir"; return
    fi

    tar -xzf "${tmpdir}/x-ui.tar.gz" -C "${tmpdir}" > /dev/null 2>&1
    local bin; bin=$(find "${tmpdir}" -name "x-ui" -type f 2>/dev/null | head -1)
    [[ -z "$bin" ]] && { warn "未找到 x-ui 二进制"; rm -rf "$tmpdir"; return; }

    systemctl stop x-ui
    cp -r "$(dirname "$bin")/." "$XUI_DIR/"
    chmod +x "$XUI_DIR/x-ui"
    rm -rf "$tmpdir"
    systemctl start x-ui
    info "3X-UI 更新完成: v${latest}"
}

# ---- 主流程 ----
echo "  1. 备份配置 → 2. 更新 Xray → 3. 更新 3X-UI"
echo ""

backup_before_update
echo ""
update_xray
echo ""
update_xui

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  更新完成!${NC}"
echo -e "${GREEN}========================================${NC}"
info "备份目录: ${BACKUP_DIR}/"
info "如有问题可恢复: tar -xzf [备份文件] && 手动还原配置"
