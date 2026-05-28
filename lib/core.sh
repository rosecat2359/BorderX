#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# BorderX 核心安装：依赖 + Xray + 3X-UI
# ============================================================

PANEL_USERNAME="admin"
PANEL_PASSWORD=""

# ---- 依赖安装 ----
install_deps() {
    info "安装系统依赖..."
    apt-get update -y >> "$LOG_FILE" 2>&1 || warn "apt update 失败，继续..."
    apt-get install -y curl wget unzip tar nginx fail2ban cron logrotate qrencode >> "$LOG_FILE" 2>&1 || warn "部分依赖失败，继续..."
    info "依赖安装完成"
}

# ---- Xray-core ----
install_xray() {
    info "安装 Xray-core..."
    XRAY_VERSION=$(curl -sL "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null | grep -o '"tag_name":"[^"]*"' | head -1 | grep -o '"v[^"]*"' | tr -d '"' || echo "v26.3.27")
    info "版本: ${XRAY_VERSION}"

    local arch; arch=$(dpkg --print-architecture)
    case "$arch" in amd64) arch="64" ;; arm64) arch="arm64-v8a" ;; armhf) arch="arm32-v7a" ;; *) error "不支持的架构: $arch" ;; esac

    local tmpdir; tmpdir=$(mktemp -d -p /var/tmp/borderx xray-XXXXXX)
    local urls=()
    for m in "${GITHUB_MIRRORS[@]}"; do urls+=("${m}/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${arch}.zip"); done

    if ! download_fallback "${tmpdir}/xray.zip" "${urls[@]}"; then
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install >> "$LOG_FILE" 2>&1
        command -v xray &>/dev/null || error "Xray 安装失败"
        rm -rf "$tmpdir"; return 0
    fi

    mkdir -p /usr/local/bin /usr/local/etc/xray /var/log/xray
    unzip -o "${tmpdir}/xray.zip" -d "${tmpdir}/xray-extract" >> "$LOG_FILE" 2>&1
    cp "${tmpdir}/xray-extract/xray" /usr/local/bin/xray; chmod +x /usr/local/bin/xray
    rm -rf "$tmpdir"
    info "Xray 安装完成: $(/usr/local/bin/xray version 2>/dev/null | head -1 || echo ok)"
}

create_xray_service() {
    info "创建 Xray 服务..."
    safe_write /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service
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
}

# ---- Xray 配置生成 ----
gen_xray_config() {
    info "生成 Xray 配置..."
    local ip; ip=$(curl -s4 ifconfig.me 2>/dev/null || curl -s4 icanhazip.com 2>/dev/null || echo "YOUR_IP")
    local vuuid; vuuid=$(generate_uuid)
    local keys; keys=$(/usr/local/bin/xray x25519 2>/dev/null)
    local priv; priv=$(echo "$keys" | grep -oP 'Private key:\s*\K\S+' 2>/dev/null || echo "")
    local pub;  pub=$(echo "$keys" | grep -oP 'Public key:\s*\K\S+'  2>/dev/null || echo "")
    local sid;  sid=$(openssl rand -hex 8)

    # 面板自签名证书
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /usr/local/etc/xray/panel.key -out /usr/local/etc/xray/panel.crt -days 3650 -subj "/CN=localhost" >> "$LOG_FILE" 2>&1

    # VLESS Reality 入站
    local VLESS_INBOUND; read -r -d '' VLESS_INBOUND <<'VLESS' || true
{"tag":"vless-reality","port":443,"protocol":"vless","settings":{"clients":[{"id":"__UUID__","flow":"xtls-rprx-vision","email":"admin@vless-reality"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"show":false,"dest":"www.microsoft.com:443","xver":0,"serverNames":["www.microsoft.com","microsoft.com","login.microsoftonline.com"],"privateKey":"__PRIV__","shortIds":["__SID__","","0123456789abcdef"]}},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}}
VLESS
    VLESS_INBOUND="${VLESS_INBOUND//__UUID__/${vuuid}}"; VLESS_INBOUND="${VLESS_INBOUND//__PRIV__/${priv}}"; VLESS_INBOUND="${VLESS_INBOUND//__SID__/${sid}}"

    local INBOUNDS='[{"tag":"api","port":10085,"listen":"127.0.0.1","protocol":"dokodemo-door","settings":{},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"]}},'${VLESS_INBOUND}

    if [[ "$LOW_MEMORY" != true ]]; then
        local vmid; vmid=$(generate_uuid)
        local wsp; wsp="/$(openssl rand -hex 8)"
        local VMESS; read -r -d '' VMESS <<VMESS || true
,{"tag":"vmess-ws","port":10001,"protocol":"vmess","settings":{"clients":[{"id":"__VMID__","alterId":0,"email":"admin@vmess-ws"}]},"streamSettings":{"network":"ws","security":"auto","wsSettings":{"path":"__WSP__","headers":{}}},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"]}}
VMESS
        VMESS="${VMESS//__VMID__/${vmid}}"; VMESS="${VMESS//__WSP__/${wsp}}"
        local tpass; tpass=$(openssl rand -hex 16)
        openssl req -x509 -nodes -newkey rsa:2048 -keyout /usr/local/etc/xray/self-signed.key -out /usr/local/etc/xray/self-signed.crt -days 3650 -subj "/CN=www.microsoft.com" >> "$LOG_FILE" 2>&1
        cp /usr/local/etc/xray/self-signed.crt /usr/local/etc/xray/panel.crt; cp /usr/local/etc/xray/self-signed.key /usr/local/etc/xray/panel.key
        local TROJAN; read -r -d '' TROJAN <<TROJAN || true
,{"tag":"trojan-tcp","port":10002,"protocol":"trojan","settings":{"clients":[{"password":"__TPASS__","email":"admin@trojan-tcp"}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/usr/local/etc/xray/self-signed.crt","keyFile":"/usr/local/etc/xray/self-signed.key"}]}},"sniffing":{"enabled":true,"destOverride":["http","tls","quic"]}}
TROJAN
        TROJAN="${TROJAN//__TPASS__/${tpass}}"
        INBOUNDS+="${VMESS}${TROJAN}"
    fi
    INBOUNDS+="]"

    local DNS='"dns":{"servers":["localhost","tcp+local://8.8.8.8","tcp+local://1.1.1.1","https+local://dns.alidns.com/dns-query","https+local://doh.pub/dns-query"],"queryStrategy":"UseIPv4","disableFallback":false}'
    local RULES='{"type":"field","outboundTag":"blocked","ip":["geoip:private"]}'
    [[ "$LOW_MEMORY" != true ]] && RULES+=',{"type":"field","outboundTag":"blocked","domain":["geosite:category-ads-all"]}'

    cat > /usr/local/etc/xray/config.json <<JSON
{"log":{"loglevel":"warning"$( [[ "$LOW_MEMORY" != true ]] && echo ',"access":"/var/log/xray/access.log","error":"/var/log/xray/error.log"' )},"stats":{},"api":{"tag":"api","services":["StatsService"]},"policy":{"levels":{"0":{"stats":true,"statsUp":true,"statsDown":true}},"system":{"statsInboundUplink":true,"statsInboundDownlink":true,"statsOutboundUplink":true,"statsOutboundDownlink":true}},${DNS},"inbounds":${INBOUNDS},"outbounds":[{"tag":"direct","protocol":"freedom","settings":{"domainStrategy":"UseIPv4"}},{"tag":"blocked","protocol":"blackhole","settings":{}}],"routing":{"domainStrategy":"IPIfNonMatch","rules":[{"type":"field","inboundTag":["api"],"outboundTag":"api"},${RULES}]}}
JSON

    info "VLESS Reality: ${ip}:443 | UUID: ${vuuid} | PubKey: ${pub}"
    mkdir -p "$INSTALL_DIR"
    echo "${vuuid}" > "${INSTALL_DIR}/vless.uuid"; echo "${pub}" > "${INSTALL_DIR}/reality.pub"
    echo "${sid}" > "${INSTALL_DIR}/reality.sid"; echo "${ip}" > "${INSTALL_DIR}/server.ip"
}

# ---- 3X-UI 面板 ----
install_panel() {
    info "安装 3X-UI 面板..."
    PANEL_PASSWORD=$(generate_password)
    info "面板密码: ${PANEL_PASSWORD}"

    local ver; ver=$(curl -sL "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" 2>/dev/null | grep -o '"tag_name":"[^"]*"' | head -1 | grep -o '"v[^"]*"' | tr -d '"' || echo "v3.1.0")
    info "版本: ${ver}"

    local arch xa; arch=$(dpkg --print-architecture)
    case "$arch" in amd64) xa="amd64" ;; arm64) xa="arm64" ;; armhf) xa="armv7" ;; *) error "不支持的架构" ;; esac

    local tmpdir; tmpdir=$(mktemp -d -p /var/tmp/borderx xui-XXXXXX)
    local urls=()
    for m in "${GITHUB_MIRRORS[@]}"; do urls+=("${m}/MHSanaei/3x-ui/releases/download/${ver}/x-ui-linux-${xa}.tar.gz"); done

    local ok=false
    for url in "${urls[@]}"; do
        rm -f "${tmpdir}/x-ui.tar.gz"
        wget --timeout=120 --tries=1 -O "${tmpdir}/x-ui.tar.gz" "$url" 2>/dev/null || continue
        local sz; sz=$(stat -c%s "${tmpdir}/x-ui.tar.gz" 2>/dev/null || echo 0)
        [[ "$sz" -gt 50000000 ]] && { ok=true; info "下载成功"; break; }
        warn "文件过小 (${sz} 字节)，重试..."
    done

    if [[ "$ok" != true ]]; then
        info "预编译包下载失败，使用官方脚本..."
        bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)
        [[ -x /usr/local/x-ui/x-ui ]] || error "3X-UI 安装失败"
        /usr/local/x-ui/x-ui setting -username admin -password "$PANEL_PASSWORD" >> "$LOG_FILE" 2>&1 || true
        rm -rf "$tmpdir"; return 0
    fi

    tar -xzf "${tmpdir}/x-ui.tar.gz" -C "${tmpdir}" >> "$LOG_FILE" 2>&1
    local bin; bin=$(find "${tmpdir}" -name "x-ui" -type f 2>/dev/null | head -1)
    [[ -z "$bin" ]] && error "未找到 x-ui 二进制文件"

    rm -rf /usr/local/x-ui; mkdir -p /usr/local/x-ui
    cp -r "$(dirname "$bin")/." /usr/local/x-ui/ >> "$LOG_FILE" 2>&1
    chmod +x /usr/local/x-ui/x-ui
    /usr/local/x-ui/x-ui setting -username admin -password "$PANEL_PASSWORD" >> "$LOG_FILE" 2>&1 || true
    rm -rf "$tmpdir"

    [[ ! -f /etc/systemd/system/x-ui.service ]] && safe_write /etc/systemd/system/x-ui.service <<'EOF'
[Unit]
Description=3X-UI Panel
After=network.target

[Service]
Type=simple
WorkingDirectory=/usr/local/x-ui
ExecStart=/usr/local/x-ui/x-ui
Restart=on-failure
RestartSec=5
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null || true
    info "3X-UI 安装完成"
}
