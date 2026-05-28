#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} 请使用 root 用户运行此脚本"
    exit 1
fi

TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM / 1024))

echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     BorderX 低内存优化脚本               ║${NC}"
echo -e "${CYAN}║     检测到内存: ${TOTAL_MEM_MB}MB                       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

info "[1/8] 配置 Swap 分区..."
SWAP_SIZE="1024"
if [[ $TOTAL_MEM_MB -le 512 ]]; then
    SWAP_SIZE="2048"
fi

if swapon --show | grep -q borderx; then
    info "Swap 已存在，跳过"
else
    if [[ -f /swapfile-borderx ]]; then
        swapoff /swapfile-borderx 2>/dev/null || true
        rm -f /swapfile-borderx
    fi

    info "创建 ${SWAP_SIZE}MB Swap 文件..."
    fallocate -l "${SWAP_SIZE}M" /swapfile-borderx 2>/dev/null || dd if=/dev/zero of=/swapfile-borderx bs=1M count="$SWAP_SIZE" status=progress
    chmod 600 /swapfile-borderx
    mkswap /swapfile-borderx
    swapon /swapfile-borderx

    if ! grep -q swapfile-borderx /etc/fstab; then
        echo "/swapfile-borderx none swap sw 0 0" >> /etc/fstab
    fi

    info "Swap 创建完成: ${SWAP_SIZE}MB"
fi

info "[2/8] 优化 Swappiness..."
sysctl vm.swappiness=10 > /dev/null 2>&1
if ! grep -q "vm.swappiness" /etc/sysctl.d/99-borderx-hardening.conf 2>/dev/null; then
    echo "vm.swappiness = 10" >> /etc/sysctl.d/99-borderx-hardening.conf
fi
info "Swappiness 设为 10 (优先使用物理内存)"

info "[3/8] 优化 3X-UI 面板内存限制..."
if [[ -f /etc/systemd/system/x-ui.service ]]; then
    cat > /etc/systemd/system/x-ui.service <<'EOF'
[Unit]
Description=3X-UI Panel
After=network.target
Wants=network.target

[Service]
Type=simple
WorkingDirectory=/usr/local/x-ui
ExecStart=/usr/local/x-ui/x-ui
Restart=on-failure
RestartSec=5
LimitNPROC=50
LimitNOFILE=1000000
MemoryMax=128M
MemoryHigh=96M
Environment=GOGC=50
Environment=GOMEMLIMIT=80MiB

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    info "3X-UI 内存限制: 128MB (GOGC=50 更积极 GC)"
fi

info "[4/8] 优化 Xray 内存限制..."
if [[ -f /etc/systemd/system/xray.service ]]; then
    cat > /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=nobody
Group=nogroup
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=100
LimitNOFILE=1000000
MemoryMax=256M
MemoryHigh=192M

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    info "Xray 内存限制: 256MB"
fi

info "[5/8] 优化 Nginx worker..."
if [[ -f /etc/nginx/nginx.conf ]]; then
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
    sed -i 's/worker_processes auto;/worker_processes 1;/' /etc/nginx/nginx.conf
    sed -i 's/worker_connections [0-9]*;/worker_connections 512;/' /etc/nginx/nginx.conf
    systemctl restart nginx 2>/dev/null || true
    info "Nginx worker: 1 process, 512 connections"
fi

info "[6/8] 减少系统日志内存占用..."
sed -i 's/^#SystemMaxUse=.*/SystemMaxUse=50M/' /etc/systemd/journald.conf 2>/dev/null || true
sed -i 's/^SystemMaxUse=.*/SystemMaxUse=50M/' /etc/systemd/journald.conf 2>/dev/null || true
systemctl restart systemd-journald 2>/dev/null || true
info "Journal 日志限制: 50MB"

info "[7/8] 清理不必要的系统服务..."
for svc in apt-daily apt-daily-upgrade man-db.timer e2scrub; do
    systemctl disable "$svc" 2>/dev/null || true
    systemctl stop "$svc" 2>/dev/null || true
done
info "已禁用不必要的定时任务"

info "[8/8] 释放页面缓存..."
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           优化完成! 当前内存状态:            ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
free -h
echo ""
info "建议:"
info "  - 1核768MB 适合 10~20 个并发用户"
info "  - 仅启用 VLESS Reality 协议可进一步节省内存"
info "  - 如需更多用户，建议升级到 1GB+ 内存"
info "  - 可运行 scripts/monitor.sh 随时查看资源使用"
