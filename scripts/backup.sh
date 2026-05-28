#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/opt/borderx-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} 请使用 root 用户运行此脚本"
    exit 1
fi

mkdir -p "${BACKUP_PATH}"

info "开始备份 BorderX 配置..."

info "备份 Xray 配置..."
cp -r /usr/local/etc/xray "${BACKUP_PATH}/xray-config"

info "备份 3X-UI 数据库..."
if [[ -f /etc/x-ui/x-ui.db ]]; then
    cp /etc/x-ui/x-ui.db "${BACKUP_PATH}/x-ui.db"
fi

info "备份 Nginx 配置..."
cp -r /etc/nginx/sites-available "${BACKUP_PATH}/nginx-sites"

info "备份 Fail2Ban 配置..."
cp /etc/fail2ban/jail.local "${BACKUP_PATH}/jail.local" 2>/dev/null || true

info "备份安装信息..."
cp /usr/local/borderx/install-info.env "${BACKUP_PATH}/install-info.env" 2>/dev/null || true

info "备份 systemd 服务..."
cp /etc/systemd/system/xray.service "${BACKUP_PATH}/xray.service" 2>/dev/null || true
cp /etc/systemd/system/x-ui.service "${BACKUP_PATH}/x-ui.service" 2>/dev/null || true

info "创建压缩包..."
cd "${BACKUP_DIR}"
tar -czf "${TIMESTAMP}.tar.gz" "${TIMESTAMP}"
rm -rf "${TIMESTAMP}"

KEEP_COUNT=10
BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | wc -l)
if [[ $BACKUP_COUNT -gt $KEEP_COUNT ]]; then
    info "清理旧备份 (保留最近 ${KEEP_COUNT} 个)..."
    ls -1t "${BACKUP_DIR}"/*.tar.gz | tail -n +$((KEEP_COUNT + 1)) | xargs rm -f
fi

BACKUP_SIZE=$(du -sh "${BACKUP_DIR}/${TIMESTAMP}.tar.gz" | cut -f1)
info "备份完成: ${BACKUP_DIR}/${TIMESTAMP}.tar.gz (${BACKUP_SIZE})"
