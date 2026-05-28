#!/usr/bin/env bash
# ============================================================
# BorderX 安全模块
# 配置 Fail2Ban 防暴力破解 + UFW 防火墙
# ============================================================
set -euo pipefail

setup_firewall() {
    info "配置 UFW 防火墙..."

    if ! command -v ufw &>/dev/null; then
        info "安装 UFW..."
        apt-get install -y ufw >> "$LOG_FILE" 2>&1 || { warn "UFW 安装失败，跳过防火墙配置"; return 0; }
    fi

    # 默认策略：拒绝入站，允许出站
    ufw default deny incoming >> "$LOG_FILE" 2>&1
    ufw default allow outgoing >> "$LOG_FILE" 2>&1

    # 基础端口
    ufw allow 22/tcp comment 'SSH' >> "$LOG_FILE" 2>&1

    # BorderX 服务端口
    ufw allow 443/tcp comment 'BorderX VLESS Reality' >> "$LOG_FILE" 2>&1
    ufw allow 8443/tcp comment 'BorderX 管理面板' >> "$LOG_FILE" 2>&1

    # 非低内存模式的额外端口
    if [[ "$LOW_MEMORY" != true ]]; then
        ufw allow 10001/tcp comment 'BorderX VMess WebSocket' >> "$LOG_FILE" 2>&1
        ufw allow 10002/tcp comment 'BorderX Trojan TLS' >> "$LOG_FILE" 2>&1
    fi

    # 限制 SSH 连接速率（防暴力破解的第一道防线）
    ufw limit 22/tcp >> "$LOG_FILE" 2>&1

    echo "y" | ufw enable >> "$LOG_FILE" 2>&1 || warn "UFW 启用失败，请手动检查"
    info "UFW 防火墙配置完成（仅开放 SSH/443/8443 及已启用的协议端口）"
}

setup_fail2ban() {
    info "配置 Fail2Ban 防暴力破解..."

    safe_write /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
banaction = iptables-multiport

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3

[x-ui]
enabled = true
filter = nginx-http-auth
port = 8443
logpath = /var/log/nginx/borderx-panel.error.log
maxretry = 5
bantime = 3600
EOF

    systemctl enable fail2ban 2>/dev/null || true
    systemctl restart fail2ban 2>/dev/null || true

    info "Fail2Ban 配置完成"
}
