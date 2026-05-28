#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# BorderX 服务配置：Nginx + Fail2Ban + Swap + 服务启动
# ============================================================

setup_nginx() {
    info "配置 Nginx 反向代理..."
    safe_write /etc/nginx/sites-available/borderx-panel <<'NGINX'
server {
    listen 80; server_name _;
    location / { return 301 https://$host$request_uri; }
}
server {
    listen 8443 ssl http2; server_name _;
    ssl_certificate /usr/local/etc/xray/panel.crt;
    ssl_certificate_key /usr/local/etc/xray/panel.key;
    ssl_protocols TLSv1.2 TLSv1.3; ssl_ciphers HIGH:!aNULL:!MD5;
    client_max_body_size 50m;
    location / {
        proxy_pass http://127.0.0.1:2053;
        proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade"; proxy_read_timeout 86400;
    }
    access_log /var/log/nginx/borderx-panel.access.log;
    error_log /var/log/nginx/borderx-panel.error.log;
}
NGINX
    ln -sf /etc/nginx/sites-available/borderx-panel /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    nginx -t >> "$LOG_FILE" 2>&1 || warn "Nginx 配置检查失败"
    systemctl enable nginx 2>/dev/null || true; systemctl restart nginx 2>/dev/null || true
    info "面板地址: https://<IP>:8443"
}

setup_fail2ban() {
    info "配置 Fail2Ban..."
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
    systemctl enable fail2ban 2>/dev/null || true; systemctl restart fail2ban 2>/dev/null || true
}

setup_firewall() {
    info "配置 UFW 防火墙..."
    if ! command -v ufw &>/dev/null; then
        apt-get install -y ufw >> "$LOG_FILE" 2>&1 || { warn "UFW 安装失败，跳过防火墙配置"; return 0; }
    fi
    ufw default deny incoming >> "$LOG_FILE" 2>&1
    ufw default allow outgoing >> "$LOG_FILE" 2>&1
    ufw allow 22/tcp comment 'SSH' >> "$LOG_FILE" 2>&1
    ufw allow 443/tcp comment 'BorderX VLESS Reality' >> "$LOG_FILE" 2>&1
    ufw allow 8443/tcp comment 'BorderX Panel' >> "$LOG_FILE" 2>&1
    [[ "$LOW_MEMORY" != true ]] && { ufw allow 10001/tcp comment 'BorderX VMess' >> "$LOG_FILE" 2>&1; ufw allow 10002/tcp comment 'BorderX Trojan' >> "$LOG_FILE" 2>&1; }
    ufw limit 22/tcp >> "$LOG_FILE" 2>&1
    echo "y" | ufw enable >> "$LOG_FILE" 2>&1 || warn "UFW 启用失败"
    info "防火墙配置完成（仅开放必要端口）"
}

setup_swap() {
    [[ "$LOW_MEMORY" != true ]] && return 0
    swapon --show 2>/dev/null | grep -q borderx && { info "Swap 已存在"; return 0; }
    info "创建 1GB Swap..."
    fallocate -l 1024M /swapfile-borderx 2>/dev/null || dd if=/dev/zero of=/swapfile-borderx bs=1M count=1024 status=none
    chmod 600 /swapfile-borderx; mkswap /swapfile-borderx >> "$LOG_FILE" 2>&1; swapon /swapfile-borderx
    grep -q swapfile-borderx /etc/fstab || echo "/swapfile-borderx none swap sw 0 0" >> /etc/fstab
    echo "vm.swappiness = 10" >> /etc/sysctl.d/99-borderx-hardening.conf
    sysctl vm.swappiness=10 > /dev/null 2>&1 || true
}

setup_logrotate() {
    info "配置日志轮转..."
    safe_write /etc/logrotate.d/xray <<'EOF'
/var/log/xray/*.log { daily; rotate 7; compress; delaycompress; missingok; notifempty; create 0644 nobody nogroup; postrotate; systemctl reload xray > /dev/null 2>&1 || true; endpostrotate; }
EOF
}

save_info() {
    info "保存安装信息..."
    local ip; ip=$(cat "${INSTALL_DIR}/server.ip" 2>/dev/null || echo "unknown")
    local vuuid; vuuid=$(cat "${INSTALL_DIR}/vless.uuid" 2>/dev/null || echo "")
    local pub; pub=$(cat "${INSTALL_DIR}/reality.pub" 2>/dev/null || echo "")
    local sid; sid=$(cat "${INSTALL_DIR}/reality.sid" 2>/dev/null || echo "")

    safe_write "${INSTALL_DIR}/install-info.env" <<EOF
INSTALL_DATE='$(date '+%Y-%m-%d %H:%M:%S')'
XRAY_VERSION='${XRAY_VERSION}'
SERVER_IP='${ip}'
VLESS_UUID='${vuuid}'
REALITY_PUB='${pub}'
REALITY_SID='${sid}'
PANEL_URL="https://${ip}:8443"
PANEL_USERNAME='${PANEL_USERNAME}'
PANEL_PASSWORD='${PANEL_PASSWORD}'
LOW_MEMORY='${LOW_MEMORY}'
EOF
    info "安装信息: ${INSTALL_DIR}/install-info.env"
}

start_all() {
    info "验证 Xray 配置..."
    if /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json >> "$LOG_FILE" 2>&1; then
        info "配置验证通过"
    else
        warn "Xray 配置有误，查看: /usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json"
    fi

    info "启动服务..."
    for svc in xray x-ui; do
        systemctl enable "$svc" 2>/dev/null || true; systemctl start "$svc" 2>/dev/null || true
        sleep 1
        systemctl is-active --quiet "$svc" 2>/dev/null && info "${svc} 启动成功" || warn "${svc} 启动失败: journalctl -u ${svc}"
    done
}

print_done() {
    local ip; ip=$(cat "${INSTALL_DIR}/server.ip" 2>/dev/null || echo "YOUR_IP")
    echo -e "\n${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     BorderX 安装完成!                 ║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} 面板: ${GREEN}https://${ip}:8443${NC}"
    echo -e "${CYAN}║${NC} 用户: ${GREEN}${PANEL_USERNAME}${NC}  密码: ${GREEN}${PANEL_PASSWORD}${NC}"
    echo -e "${CYAN}║${NC} VLESS: ${GREEN}${ip}:443${NC}"
    echo -e "${CYAN}║${NC} 配置: ${INSTALL_DIR}/install-info.env${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}\n"
}
