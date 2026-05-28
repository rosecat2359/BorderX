#!/usr/bin/env bash
# ============================================================
# BorderX Xray-core 安装模块
# 下载、安装 Xray-core，创建 systemd 服务，生成配置文件
# ============================================================
set -euo pipefail

install_xray() {
    info "获取 Xray-core 最新版本..."

    local xray_tag=""

    # 来源 1: GitHub API 直连
    xray_tag=$(curl -sL --connect-timeout 10 "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null \
        | { grep -o '"tag_name":"[^"]*"' || true; } | head -1 | { grep -o '"v[^"]*"' || true; } | tr -d '"')

    # 来源 2: GitHub API 镜像（走 ghfast.top）
    if [[ -z "$xray_tag" ]] || [[ "$xray_tag" != v* ]]; then
        xray_tag=$(curl -sL --connect-timeout 10 "https://ghfast.top/https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null \
            | { grep -o '"tag_name":"[^"]*"' || true; } | head -1 | { grep -o '"v[^"]*"' || true; } | tr -d '"')
    fi

    # 来源 3: 从 Xray-install 脚本获取最新版本号
    if [[ -z "$xray_tag" ]] || [[ "$xray_tag" != v* ]]; then
        xray_tag=$(curl -sL --connect-timeout 10 "https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh" 2>/dev/null \
            | grep -oP 'XRAY_VERSION="\K[^"]*' | head -1) || true
        [[ -n "$xray_tag" ]] && xray_tag="v${xray_tag}"
    fi

    if [[ -z "$xray_tag" ]] || [[ "$xray_tag" != v* ]]; then
        XRAY_VERSION="$XRAY_FALLBACK_VERSION"
        warn "无法获取最新版本（已尝试 3 个来源），使用回退版本: ${XRAY_VERSION}"
    else
        XRAY_VERSION="$xray_tag"
    fi

    info "Xray-core 版本: ${XRAY_VERSION}"

    local arch
    arch=$(dpkg --print-architecture)
    case "$arch" in
        amd64)  arch="64" ;;
        arm64)  arch="arm64-v8a" ;;
        armhf)  arch="arm32-v7a" ;;
        *)      error "不支持的架构: $arch" ;;
    esac

    local tmpdir
    tmpdir=$(mktemp -d -p /var/tmp/borderx xray-XXXXXX)
    local filename="Xray-linux-${arch}.zip"

    # 构建镜像 URL 列表
    local urls=()
    for mirror in "${GITHUB_MIRRORS[@]}"; do
        urls+=("${mirror}/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${filename}")
    done

    if ! download_with_fallback "${tmpdir}/xray.zip" "${urls[@]}"; then
        info "所有镜像下载失败，尝试官方安装脚本..."
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install >> "$LOG_FILE" 2>&1
        if command -v xray &>/dev/null; then
            info "Xray-core 通过官方脚本安装成功"
            rm -rf "$tmpdir"
            return 0
        else
            error "Xray-core 安装失败，请检查网络连接"
        fi
    fi

    ensure_dir /usr/local/bin
    ensure_dir /usr/local/etc/xray
    ensure_dir /var/log/xray

    unzip -o "${tmpdir}/xray.zip" -d "${tmpdir}/xray-extract" >> "$LOG_FILE" 2>&1
    cp "${tmpdir}/xray-extract/xray" /usr/local/bin/xray
    chmod +x /usr/local/bin/xray

    local xray_ver_info
    xray_ver_info=$(/usr/local/bin/xray version 2>/dev/null | head -1 || echo "unknown")
    info "Xray-core 安装完成: ${xray_ver_info}"

    rm -rf "$tmpdir"
}

create_xray_service() {
    info "创建 Xray systemd 服务..."

    safe_write /etc/systemd/system/xray.service <<'EOF'
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
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload 2>/dev/null || true
    info "Xray 服务文件创建完成"
}

generate_xray_config() {
    info "生成 Xray 配置文件..."

    local vless_port=443
    local vless_uuid
    vless_uuid=$(generate_uuid)
    local x25519_keys
    x25519_keys=$(generate_x25519_keys)
    local reality_private_key
    reality_private_key=$(echo "$x25519_keys" | cut -d: -f1)
    local reality_public_key
    reality_public_key=$(echo "$x25519_keys" | cut -d: -f2)
    local short_id
    short_id=$(openssl rand -hex 8)
    local server_ip
    server_ip=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com || echo "YOUR_SERVER_IP")

    # 公共部分：日志 / DNS / stats / API / policy
    local log_config
    if [[ "$LOW_MEMORY" == true ]]; then
        log_config='"log": {"loglevel": "warning"}'
    else
        log_config='"log": {"loglevel": "warning", "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log"}'
    fi

    # 生成自签名证书（Nginx 面板用）
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout /usr/local/etc/xray/panel.key \
        -out /usr/local/etc/xray/panel.crt \
        -days 3650 \
        -subj "/CN=localhost" >> "$LOG_FILE" 2>&1

    # VLESS Reality 入站（通用部分）
    local VLESS_INBOUND
    read -r -d '' VLESS_INBOUND <<'VLESSJSON' || true
{
    "tag": "vless-reality",
    "port": __VLESS_PORT__,
    "protocol": "vless",
    "settings": {
        "clients": [{
            "id": "__VLESS_UUID__",
            "flow": "xtls-rprx-vision",
            "email": "admin@vless-reality"
        }],
        "decryption": "none"
    },
    "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
            "show": false,
            "dest": "www.microsoft.com:443",
            "xver": 0,
            "serverNames": ["www.microsoft.com", "microsoft.com", "login.microsoftonline.com"],
            "privateKey": "__REALITY_PRIVATE__",
            "shortIds": ["__SHORT_ID__", "", "0123456789abcdef"]
        }
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true}
}
VLESSJSON

    VLESS_INBOUND="${VLESS_INBOUND//__VLESS_PORT__/${vless_port}}"
    VLESS_INBOUND="${VLESS_INBOUND//__VLESS_UUID__/${vless_uuid}}"
    VLESS_INBOUND="${VLESS_INBOUND//__REALITY_PRIVATE__/${reality_private_key}}"
    VLESS_INBOUND="${VLESS_INBOUND//__SHORT_ID__/${short_id}}"

    # API 入站
    local API_INBOUND='{"tag": "api", "port": 10085, "listen": "127.0.0.1", "protocol": "dokodemo-door", "settings": {}, "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}}'

    # 构建 inbounds 数组
    local INBOUNDS="[${API_INBOUND}, ${VLESS_INBOUND}"

    if [[ "$LOW_MEMORY" != true ]]; then
        # VMess WebSocket
        local vmess_port=10001
        local vmess_uuid
        vmess_uuid=$(generate_uuid)
        local ws_path="/$(openssl rand -hex 8)"
        local VMESS_INBOUND
        read -r -d '' VMESS_INBOUND <<'VMESSJSON' || true
, {
    "tag": "vmess-ws",
    "port": __VMESS_PORT__,
    "protocol": "vmess",
    "settings": {
        "clients": [{"id": "__VMESS_UUID__", "alterId": 0, "email": "admin@vmess-ws"}]
    },
    "streamSettings": {
        "network": "ws",
        "security": "auto",
        "wsSettings": {"path": "__WS_PATH__", "headers": {}}
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
}
VMESSJSON
        VMESS_INBOUND="${VMESS_INBOUND//__VMESS_PORT__/${vmess_port}}"
        VMESS_INBOUND="${VMESS_INBOUND//__VMESS_UUID__/${vmess_uuid}}"
        VMESS_INBOUND="${VMESS_INBOUND//__WS_PATH__/${ws_path}}"

        # Trojan
        local trojan_port=10002
        local trojan_password
        trojan_password=$(openssl rand -hex 16)
        openssl req -x509 -nodes -newkey rsa:2048 \
            -keyout /usr/local/etc/xray/self-signed.key \
            -out /usr/local/etc/xray/self-signed.crt \
            -days 3650 \
            -subj "/CN=www.microsoft.com" >> "$LOG_FILE" 2>&1
        cp /usr/local/etc/xray/self-signed.crt /usr/local/etc/xray/panel.crt
        cp /usr/local/etc/xray/self-signed.key /usr/local/etc/xray/panel.key

        local TROJAN_INBOUND
        read -r -d '' TROJAN_INBOUND <<'TROJANJSON' || true
, {
    "tag": "trojan-tcp",
    "port": __TROJAN_PORT__,
    "protocol": "trojan",
    "settings": {
        "clients": [{"password": "__TROJAN_PASS__", "email": "admin@trojan-tcp"}]
    },
    "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
            "certificates": [{"certificateFile": "/usr/local/etc/xray/self-signed.crt", "keyFile": "/usr/local/etc/xray/self-signed.key"}]
        }
    },
    "sniffing": {"enabled": true, "destOverride": ["http", "tls", "quic"]}
}
TROJANJSON
        TROJAN_INBOUND="${TROJAN_INBOUND//__TROJAN_PORT__/${trojan_port}}"
        TROJAN_INBOUND="${TROJAN_INBOUND//__TROJAN_PASS__/${trojan_password}}"

        INBOUNDS+="${VMESS_INBOUND}${TROJAN_INBOUND}"
    fi
    INBOUNDS+="]"

    # Outbounds
    local OUTBOUNDS='[
        {"tag": "direct", "protocol": "freedom", "settings": {"domainStrategy": "UseIPv4"}},
        {"tag": "blocked", "protocol": "blackhole", "settings": {}}
    ]'

    # Routing
    local ROUTING
    if [[ "$LOW_MEMORY" != true ]]; then
        ROUTING='{
            "domainStrategy": "IPIfNonMatch",
            "rules": [
                {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},
                {"type": "field", "outboundTag": "blocked", "ip": ["geoip:private"]},
                {"type": "field", "outboundTag": "blocked", "domain": ["geosite:category-ads-all"]}
            ]
        }'
    else
        ROUTING='{
            "domainStrategy": "IPIfNonMatch",
            "rules": [
                {"type": "field", "inboundTag": ["api"], "outboundTag": "api"},
                {"type": "field", "outboundTag": "blocked", "ip": ["geoip:private"]}
            ]
        }'
    fi

    # 拼接完整配置
    local DNS_CONFIG='{"servers": ["localhost", "tcp+local://8.8.8.8", "tcp+local://1.1.1.1", "https+local://dns.alidns.com/dns-query", "https+local://doh.pub/dns-query"], "queryStrategy": "UseIPv4", "disableFallback": false}'
    local STATS_CONFIG='{}'
    local API_CONFIG='{"tag": "api", "services": ["StatsService"]}'
    local POLICY_CONFIG='{
        "levels": {"0": {"stats": true, "statsUp": true, "statsDown": true}},
        "system": {"statsInboundUplink": true, "statsInboundDownlink": true, "statsOutboundUplink": true, "statsOutboundDownlink": true}
    }'

    cat > /usr/local/etc/xray/config.json <<JSONEOF
{
    ${log_config},
    "dns": ${DNS_CONFIG},
    "stats": ${STATS_CONFIG},
    "api": ${API_CONFIG},
    "policy": ${POLICY_CONFIG},
    "inbounds": ${INBOUNDS},
    "outbounds": ${OUTBOUNDS},
    "routing": ${ROUTING}
}
JSONEOF

    info "Xray 配置文件生成完成"

    # 打印连接信息
    print_connection_info "$server_ip" "$vless_port" "$vless_uuid" "$reality_public_key" "$short_id" \
        "${vmess_port:-}" "${vmess_uuid:-}" "${trojan_port:-}" "${trojan_password:-}"
}

print_connection_info() {
    local server_ip="$1"
    local vless_port="$2" vless_uuid="$3" reality_pub="$4" short_id="$5"
    local vmess_port="${6:-}" vmess_uuid="${7:-}" trojan_port="${8:-}" trojan_pass="${9:-}"

    info "============================================"
    info "  VLESS Reality 连接信息:"
    info "  - 地址: ${server_ip}"
    info "  - 端口: ${vless_port}"
    info "  - UUID: ${vless_uuid}"
    info "  - 流控: xtls-rprx-vision"
    info "  - 传输: tcp"
    info "  - 安全: reality"
    info "  - SNI: www.microsoft.com"
    info "  - 公钥: ${reality_pub}"
    info "  - Short ID: ${short_id}"
    info "  - 指纹: chrome"
    info "============================================"

    if [[ "$LOW_MEMORY" != true && -n "$vmess_port" ]]; then
        info "  VMess WebSocket 连接信息:"
        info "  - 地址: ${server_ip}"
        info "  - 端口: ${vmess_port}"
        info "  - UUID: ${vmess_uuid}"
        info "  - 传输: ws"
        info "============================================"
        info "  Trojan 连接信息:"
        info "  - 地址: ${server_ip}"
        info "  - 端口: ${trojan_port}"
        info "  - 密码: ${trojan_pass}"
        info "  - 传输: tcp"
        info "  - 安全: tls"
        info "============================================"
    else
        info "  (低内存模式: VMess/Trojan 已跳过)"
        info "============================================"
    fi

    # 持久化关键参数
    ensure_dir "$INSTALL_DIR"
    echo "${vless_uuid}" > "${INSTALL_DIR}/vless.uuid"
    echo "${reality_pub}" > "${INSTALL_DIR}/reality.pub"
    echo "${short_id}" > "${INSTALL_DIR}/reality.sid"
    echo "${server_ip}" > "${INSTALL_DIR}/server.ip"
}
