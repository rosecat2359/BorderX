#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# BorderX — Xray-core + 3X-UI 一键部署方案
# 免责声明: 本脚本仅供学习研究使用，使用者需遵守当地法律法规。
# 作者不对任何滥用行为负责。请勿用于任何违法用途。
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/borderx"

if [[ $EUID -ne 0 ]]; then
    error "请使用 root 用户运行此脚本"
fi

if [[ ! -f /etc/debian_version ]]; then
    error "此脚本仅支持 Debian/Ubuntu 系统"
fi

echo -e "${CYAN}"
echo "  ╔═════════════════════════════════════════════════════╗"
echo "  ║           BorderX 一键部署脚本                      ║"
echo "  ║     Xray-core + 3X-UI + Nginx + 安全加固           ║"
echo "  ╚═════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ---- 步骤 1: 核心 VPN 服务安装 ----
info "步骤 1/5: 安装 VPN 核心服务..."
if ! bash "${SCRIPT_DIR}/install.sh"; then
    error "核心服务安装失败，请检查日志: /var/log/borderx-install.log"
fi

# ---- 步骤 2: 系统安全加固 ----
info "步骤 2/5: 执行系统安全加固..."
read -rp "是否执行系统安全加固? (推荐) [Y/n]: " do_harden
if [[ "$do_harden" != "n" && "$do_harden" != "N" ]]; then
    bash "${SCRIPT_DIR}/scripts/harden.sh" || warn "安全加固部分失败，不影响核心功能，可稍后手动执行: bash scripts/harden.sh"
else
    warn "已跳过安全加固"
fi

# ---- 步骤 3: 复制脚本到安装目录 ----
info "步骤 3/5: 部署运维脚本..."
mkdir -p "${INSTALL_DIR}/scripts"
cp "${SCRIPT_DIR}/scripts/backup.sh"      "${INSTALL_DIR}/scripts/backup.sh"
cp "${SCRIPT_DIR}/scripts/monitor.sh"     "${INSTALL_DIR}/scripts/monitor.sh"
cp "${SCRIPT_DIR}/scripts/health-check.sh" "${INSTALL_DIR}/scripts/health-check.sh"
cp "${SCRIPT_DIR}/scripts/user-manager.sh" "${INSTALL_DIR}/scripts/user-manager.sh"
cp "${SCRIPT_DIR}/scripts/optimize-lowmem.sh" "${INSTALL_DIR}/scripts/optimize-lowmem.sh" 2>/dev/null || true
cp "${SCRIPT_DIR}/scripts/fix-dns.sh"     "${INSTALL_DIR}/scripts/fix-dns.sh" 2>/dev/null || true
cp "${SCRIPT_DIR}/scripts/quick-status.sh" "${INSTALL_DIR}/scripts/quick-status.sh"
cp "${SCRIPT_DIR}/scripts/sync-firewall.sh" "${INSTALL_DIR}/scripts/sync-firewall.sh"
cp "${SCRIPT_DIR}/update.sh"              "${INSTALL_DIR}/update.sh"
chmod +x "${INSTALL_DIR}/scripts/"*.sh
info "运维脚本已部署到 ${INSTALL_DIR}/scripts/"

# ---- 步骤 4: 首次备份 ----
info "步骤 4/5: 执行首次配置备份..."
bash "${INSTALL_DIR}/scripts/backup.sh"

# ---- 步骤 5: 配置定时任务 ----
info "步骤 5/5: 配置定时任务..."

# 每日凌晨 2:00 自动备份
cat > /etc/cron.d/borderx-backup <<'CRONEOF'
0 2 * * * root /usr/local/borderx/scripts/backup.sh >> /var/log/borderx-backup.log 2>&1
CRONEOF

# 每 5 分钟健康检查
cat > /etc/cron.d/borderx-healthcheck <<'CRONEOF'
*/5 * * * * root /usr/local/borderx/scripts/health-check.sh >> /var/log/borderx-healthcheck.log 2>&1
CRONEOF

# 每 10 分钟防火墙端口同步（静默，仅变更时记录日志）
cat > /etc/cron.d/borderx-firewall-sync <<'CRONEOF'
7,17,27,37,47,57 * * * * root /usr/local/borderx/scripts/sync-firewall.sh --quiet >> /var/log/borderx-firewall-sync.log 2>&1
CRONEOF

chmod 644 /etc/cron.d/borderx-backup /etc/cron.d/borderx-healthcheck /etc/cron.d/borderx-firewall-sync

info "定时任务已配置:"
info "  - 每日 02:00  配置备份 (${INSTALL_DIR}/scripts/backup.sh)"
info "  - 每 5 分钟    健康检查 (${INSTALL_DIR}/scripts/health-check.sh)"
info "  - 每 10 分钟   防火墙端口同步 (${INSTALL_DIR}/scripts/sync-firewall.sh --quiet)"

# ---- 完成 ----
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              BorderX 部署全部完成!                       ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC} 下一步操作:${NC}"
echo -e "${GREEN}║${NC} 1. 运行状态检查获取面板信息${NC}"
echo -e "${GREEN}║${NC}    bash ${INSTALL_DIR}/scripts/quick-status.sh${NC}"
echo -e "${GREEN}║${NC} 2. 在面板或命令行中添加 VPN 用户${NC}"
echo -e "${GREEN}║${NC}    bash ${INSTALL_DIR}/scripts/user-manager.sh add-vless your@email${NC}"
echo -e "${GREEN}║${NC} 3. 使用客户端连接测试${NC}"
echo -e "${GREEN}║${NC} 4. 同步防火墙（面板添加入站后执行）${NC}"
echo -e "${GREEN}║${NC}    bash ${INSTALL_DIR}/scripts/sync-firewall.sh${NC}"
echo -e "${GREEN}║${NC} 5. 查看详细监控${NC}"
echo -e "${GREEN}║${NC}    bash ${INSTALL_DIR}/scripts/monitor.sh${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
