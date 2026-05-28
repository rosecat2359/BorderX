#!/usr/bin/env bash
# ============================================================
# BorderX 运维模块
# 日志轮转、证书自动续期、安装信息保存
# ============================================================
set -euo pipefail

setup_log_rotation() {
    info "配置日志轮转..."

    safe_write /etc/logrotate.d/xray <<'EOF'
/var/log/xray/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 nobody nogroup
    postrotate
        systemctl reload xray > /dev/null 2>&1 || true
    endpostrotate
}
EOF

    info "日志轮转配置完成"
}

setup_auto_cert_renew() {
    info "配置证书自动续期..."

    echo "0 3 1 * * root certbot renew --quiet --post-hook 'systemctl reload nginx'" > /etc/cron.d/certbot-renew

    info "证书自动续期配置完成"
}

setup_lowmem_swap() {
    if [[ "$LOW_MEMORY" != true ]]; then
        return 0
    fi

    info "创建 Swap 分区 (低内存优化)..."

    if swapon --show 2>/dev/null | grep -q borderx; then
        info "Swap 已存在，跳过创建"
        return 0
    fi

    # 使用 fallocate 创建（更快），失败则回退到 dd
    fallocate -l 1024M /swapfile-borderx 2>/dev/null || \
        dd if=/dev/zero of=/swapfile-borderx bs=1M count=1024 status=none
    chmod 600 /swapfile-borderx
    mkswap /swapfile-borderx >> "$LOG_FILE" 2>&1
    swapon /swapfile-borderx

    if ! grep -q swapfile-borderx /etc/fstab; then
        echo "/swapfile-borderx none swap sw 0 0" >> /etc/fstab
    fi

    echo "vm.swappiness = 10" >> /etc/sysctl.d/99-borderx-hardening.conf
    sysctl vm.swappiness=10 > /dev/null 2>&1 || true
    info "Swap 1GB 创建完成"
}

save_install_info() {
    info "保存安装信息..."

    local server_ip
    server_ip=$(cat "${INSTALL_DIR}/server.ip" 2>/dev/null || echo "unknown")
    local vless_uuid
    vless_uuid=$(cat "${INSTALL_DIR}/vless.uuid" 2>/dev/null || echo "unknown")
    local reality_pub
    reality_pub=$(cat "${INSTALL_DIR}/reality.pub" 2>/dev/null || echo "unknown")
    local reality_sid
    reality_sid=$(cat "${INSTALL_DIR}/reality.sid" 2>/dev/null || echo "unknown")

    safe_write "${INSTALL_DIR}/install-info.env" <<EOF
# BorderX 安装信息 — 生成于 $(date '+%Y-%m-%d %H:%M:%S')
# 此文件可被 source 导入: source ${INSTALL_DIR}/install-info.env
INSTALL_DATE='$(date '+%Y-%m-%d %H:%M:%S')'
XRAY_VERSION='${XRAY_VERSION}'
SERVER_IP='${server_ip}'
VLESS_UUID='${vless_uuid}'
REALITY_PUB='${reality_pub}'
REALITY_SID='${reality_sid}'
PANEL_URL="https://${server_ip}:8443"
PANEL_USERNAME='${PANEL_USERNAME:-admin}'
PANEL_PASSWORD='${PANEL_PASSWORD:-admin}'
LOW_MEMORY='${LOW_MEMORY}'
EOF

    # 额外保存一份纯 JSON 格式，方便程序化读取
    safe_write "${INSTALL_DIR}/install-info.json" <<JSONEOF
{
    "install_date": "$(date '+%Y-%m-%d %H:%M:%S')",
    "xray_version": "${XRAY_VERSION}",
    "server_ip": "${server_ip}",
    "panel_url": "https://${server_ip}:8443",
    "panel_username": "${PANEL_USERNAME:-admin}",
    "panel_password": "${PANEL_PASSWORD:-admin}",
    "protocols": {
        "vless_reality": {
            "port": 443,
            "uuid": "${vless_uuid}",
            "flow": "xtls-rprx-vision",
            "security": "reality",
            "sni": "www.microsoft.com",
            "public_key": "${reality_pub}",
            "short_id": "${reality_sid}",
            "fingerprint": "chrome"
        }
    },
    "low_memory": ${LOW_MEMORY}
}
JSONEOF

    info "安装信息已保存到 ${INSTALL_DIR}/"
}
