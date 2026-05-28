#!/usr/bin/env bash
# ============================================================
# BorderX Nginx 反向代理模块
# 配置 Nginx 将面板端口 8443 代理到 3X-UI 内部端口 2053
# ============================================================
set -euo pipefail

setup_nginx() {
    info "配置 Nginx 反向代理 (3X-UI 面板)..."

    local SSL_CERT="/usr/local/etc/xray/panel.crt"
    local SSL_KEY="/usr/local/etc/xray/panel.key"

    local panel_domain=""
    read -rp "请输入面板域名 (留空则使用 IP 访问): " panel_domain

    if [[ -n "$panel_domain" ]]; then
        info "将为域名 ${panel_domain} 申请 SSL 证书..."
        certbot --nginx -d "$panel_domain" --non-interactive --agree-tos --register-unsafely-without-email >> "$LOG_FILE" 2>&1 || \
            warn "SSL 证书申请失败，面板将使用自签名证书"
    fi

    safe_write /etc/nginx/sites-available/borderx-panel <<NGINXEOF
server {
    listen 80;
    server_name _;

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 8443 ssl http2;
    server_name _;

    ssl_certificate     ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    client_max_body_size 50m;

    location / {
        proxy_pass http://127.0.0.1:2053;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }

    access_log /var/log/nginx/borderx-panel.access.log;
    error_log  /var/log/nginx/borderx-panel.error.log;
}
NGINXEOF

    ln -sf /etc/nginx/sites-available/borderx-panel /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default

    if ! nginx -t >> "$LOG_FILE" 2>&1; then
        warn "Nginx 配置检查失败"
        return 1
    fi

    systemctl enable nginx 2>/dev/null || true
    systemctl restart nginx 2>/dev/null || true

    info "Nginx 反向代理配置完成，面板访问地址: https://<服务器IP>:8443"
}
