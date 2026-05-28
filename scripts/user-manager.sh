#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# BorderX 命令行用户管理工具
# 支持 VLESS Reality / VMess WS / Trojan 用户增删查
# ============================================================

INSTALL_DIR="/usr/local/borderx"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CONFIG="/usr/local/etc/xray/config.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

if [[ $EUID -ne 0 ]]; then
    error "请使用 root 用户运行此脚本"
fi

# ---- 工具函数 ----

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 校验 email 格式：必须包含 @，长度 3-64 字符，不含危险字符
validate_email() {
    local email="$1"
    local label="${2:-email}"
    if [[ -z "$email" ]]; then
        error "${label} 不能为空"
    fi
    if [[ ${#email} -lt 3 || ${#email} -gt 64 ]]; then
        error "${label} 长度应在 3-64 字符之间: ${email}"
    fi
    if [[ "$email" != *@* ]]; then
        error "${label} 格式无效（需包含 @）: ${email}"
    fi
    # 防止 jq 注入：email 值会被拼入 JSON，过滤含引号/反斜杠的输入
    if [[ "$email" =~ [\"\\] ]]; then
        error "${label} 包含非法字符（引号或反斜杠）: ${email}"
    fi
}

# 校验 UUID v4 格式
validate_uuid() {
    local uuid="$1"
    local label="${2:-uuid}"
    local uuid_re='^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    if [[ ! "$uuid" =~ $uuid_re ]]; then
        error "${label} 不是有效的 UUID v4: ${uuid}"
    fi
}

# 检查用户 email 是否已存在于指定入站
user_email_exists() {
    local email="$1"
    local tag="$2"
    local count
    count=$(jq -r --arg tag "$tag" --arg email "$email" \
        '[.inbounds[] | select(.tag == $tag) | .settings.clients[]? | select(.email == $email)] | length' \
        "$XRAY_CONFIG" 2>/dev/null || echo 0)
    [[ "$count" -gt 0 ]]
}

# 安全写入配置：写临时文件 → jq 校验 → 原子替换
safe_update_config() {
    local new_config="$1"
    # 校验新配置为合法 JSON
    if ! jq empty "$new_config" 2>/dev/null; then
        rm -f "$new_config"
        error "配置更新失败：生成的 JSON 无效，原配置未修改"
    fi
    mv "$new_config" "$XRAY_CONFIG"
}

get_server_ip() {
    cat "${INSTALL_DIR}/server.ip" 2>/dev/null || curl -s4 ifconfig.me || echo "127.0.0.1"
}

# 按 tag 查找入站在 inbounds 数组中的索引
# 参数: $1 = tag 名称 (如 "vless-reality")
# 返回: 索引号 (0-based)，未找到返回 -1
find_inbound_by_tag() {
    local tag="$1"
    local idx
    idx=$(jq -r --arg tag "$tag" '.inbounds | to_entries[] | select(.value.tag == $tag) | .key' "$XRAY_CONFIG" 2>/dev/null)
    if [[ -z "$idx" ]]; then
        echo "-1"
    else
        echo "$idx"
    fi
}

# 获取入站的端口
get_inbound_port() {
    local tag="$1"
    jq -r --arg tag "$tag" '.inbounds[] | select(.tag == $tag) | .port' "$XRAY_CONFIG" 2>/dev/null
}

# 重启 Xray 使配置生效
restart_xray() {
    info "重启 Xray 服务..."
    systemctl restart xray
    sleep 2
    if systemctl is-active --quiet xray; then
        info "Xray 服务重启成功"
    else
        error "Xray 服务重启失败，请检查: journalctl -u xray"
    fi
}

# ---- 添加 VLESS Reality 用户 ----
add_vless_user() {
    local email="$1"
    validate_email "$email" "email"

    local tag="vless-reality"
    local idx
    idx=$(find_inbound_by_tag "$tag")
    if [[ "$idx" == "-1" ]]; then
        error "未找到 tag=${tag} 的入站配置"
    fi

    if user_email_exists "$email" "$tag"; then
        error "用户 ${email} 已存在于 ${tag}，请使用不同的 email"
    fi

    local uuid
    uuid=$(generate_uuid)

    info "添加 VLESS Reality 用户: ${email} (uuid=${uuid})"

    local config_tmp
    config_tmp=$(mktemp)
    jq --argjson idx "$idx" --arg email "$email" --arg uuid "$uuid" \
        '.inbounds[$idx].settings.clients += [{"id": $uuid, "flow": "xtls-rprx-vision", "email": $email}]' \
        "$XRAY_CONFIG" > "$config_tmp"
    safe_update_config "$config_tmp"

    local server_ip reality_pub short_id
    server_ip=$(get_server_ip)
    reality_pub=$(cat "${INSTALL_DIR}/reality.pub" 2>/dev/null || echo "查看配置文件")
    short_id=$(cat "${INSTALL_DIR}/reality.sid" 2>/dev/null || echo "")

    local vless_link="vless://${uuid}@${server_ip}:$(get_inbound_port "$tag")?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${reality_pub}&sid=${short_id}&type=tcp#BorderX-${email}"

    echo ""
    info "=== VLESS Reality 连接信息 ==="
    info "UUID:     ${uuid}"
    info "地址:     ${server_ip}:$(get_inbound_port "$tag")"
    info "公钥:     ${reality_pub}"
    info "Short ID: ${short_id}"
    echo ""
    info "分享链接:"
    echo "$vless_link"
    echo ""
    qrencode -t ANSIUTF8 "$vless_link" 2>/dev/null || warn "安装 qrencode 以显示二维码: apt install qrencode"
}

# ---- 添加 VMess WebSocket 用户 ----
add_vmess_user() {
    local email="$1"
    validate_email "$email" "email"

    local tag="vmess-ws"
    local idx
    idx=$(find_inbound_by_tag "$tag")
    if [[ "$idx" == "-1" ]]; then
        error "未找到 tag=${tag} 的入站配置（可能处于低内存模式，未启用 VMess）"
    fi

    if user_email_exists "$email" "$tag"; then
        error "用户 ${email} 已存在于 ${tag}，请使用不同的 email"
    fi

    local uuid
    uuid=$(generate_uuid)

    info "添加 VMess WebSocket 用户: ${email} (uuid=${uuid})"

    local ws_path
    ws_path=$(jq -r --argjson idx "$idx" '.inbounds[$idx].streamSettings.wsSettings.path' "$XRAY_CONFIG" 2>/dev/null || echo "/default")

    local config_tmp
    config_tmp=$(mktemp)
    jq --argjson idx "$idx" --arg email "$email" --arg uuid "$uuid" \
        '.inbounds[$idx].settings.clients += [{"id": $uuid, "alterId": 0, "email": $email}]' \
        "$XRAY_CONFIG" > "$config_tmp"
    safe_update_config "$config_tmp"

    local server_ip port
    server_ip=$(get_server_ip)
    port=$(get_inbound_port "$tag")

    local vmess_obj
    vmess_obj=$(printf '{"v":"2","ps":"BorderX-%s","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","type":"none","host":"","path":"%s","tls":""}' \
        "$email" "$server_ip" "$port" "$uuid" "$ws_path")
    local vmess_link="vmess://$(echo -n "$vmess_obj" | base64 -w 0)"

    echo ""
    info "=== VMess WebSocket 连接信息 ==="
    info "UUID:   ${uuid}"
    info "地址:   ${server_ip}:${port}"
    info "路径:   ${ws_path}"
    echo ""
    info "分享链接:"
    echo "$vmess_link"
}

# ---- 添加 Trojan 用户 ----
add_trojan_user() {
    local email="$1"
    validate_email "$email" "email"

    local tag="trojan-tcp"
    local idx
    idx=$(find_inbound_by_tag "$tag")
    if [[ "$idx" == "-1" ]]; then
        error "未找到 tag=${tag} 的入站配置（可能处于低内存模式，未启用 Trojan）"
    fi

    if user_email_exists "$email" "$tag"; then
        error "用户 ${email} 已存在于 ${tag}，请使用不同的 email"
    fi

    info "添加 Trojan 用户: ${email}"
    local password
    password=$(openssl rand -hex 16)

    local config_tmp
    config_tmp=$(mktemp)
    jq --argjson idx "$idx" --arg email "$email" --arg password "$password" \
        '.inbounds[$idx].settings.clients += [{"password": $password, "email": $email}]' \
        "$XRAY_CONFIG" > "$config_tmp"
    safe_update_config "$config_tmp"

    local server_ip port
    server_ip=$(get_server_ip)
    port=$(get_inbound_port "$tag")

    local trojan_link="trojan://${password}@${server_ip}:${port}?security=tls&type=tcp&headerType=none#BorderX-${email}"

    echo ""
    info "=== Trojan 连接信息 ==="
    info "密码:   ${password}"
    info "地址:   ${server_ip}:${port}"
    echo ""
    info "分享链接:"
    echo "$trojan_link"
}

# ---- 列出所有用户 ----
list_users() {
    local tags
    tags=$(jq -r '[.inbounds[] | .tag] | join(" ")' "$XRAY_CONFIG" 2>/dev/null || echo "")

    for tag in $tags; do
        echo ""
        info "=== ${tag} 用户 ==="

        case "$tag" in
            vless-reality)
                jq -r --arg tag "$tag" '.inbounds[] | select(.tag == $tag) | .settings.clients[] | "  \(.email): \(.id)"' "$XRAY_CONFIG" 2>/dev/null || echo "  (无用户)"
                ;;
            vmess-ws)
                jq -r --arg tag "$tag" '.inbounds[] | select(.tag == $tag) | .settings.clients[] | "  \(.email): \(.id)"' "$XRAY_CONFIG" 2>/dev/null || echo "  (无用户)"
                ;;
            trojan-tcp)
                jq -r --arg tag "$tag" '.inbounds[] | select(.tag == $tag) | .settings.clients[] | "  \(.email): \(.password)"' "$XRAY_CONFIG" 2>/dev/null || echo "  (无用户)"
                ;;
            api)
                # 跳过 API 入站
                ;;
            *)
                jq -r --arg tag "$tag" '.inbounds[] | select(.tag == $tag) | .settings.clients[]? | "  \(.email // "?")"' "$XRAY_CONFIG" 2>/dev/null || true
                ;;
        esac
    done
}

# ---- 删除用户 ----
remove_user() {
    local email="$1"
    validate_email "$email" "email"
    local found=0

    local count
    count=$(jq '.inbounds | length' "$XRAY_CONFIG" 2>/dev/null || echo 0)

    for i in $(seq 0 $((count - 1))); do
        local tag
        tag=$(jq -r --argjson i "$i" '.inbounds[$i].tag' "$XRAY_CONFIG" 2>/dev/null)
        [[ "$tag" == "api" ]] && continue  # 跳过 API 入站

        local client_count
        client_count=$(jq --argjson i "$i" '.inbounds[$i].settings.clients | length' "$XRAY_CONFIG" 2>/dev/null || echo 0)

        for j in $(seq 0 $((client_count - 1))); do
            local user_email
            user_email=$(jq -r --argjson i "$i" --argjson j "$j" '.inbounds[$i].settings.clients[$j].email' "$XRAY_CONFIG" 2>/dev/null)
            if [[ "$user_email" == "$email" ]]; then
                local config_tmp
                config_tmp=$(mktemp)
                jq --argjson i "$i" --argjson j "$j" 'del(.inbounds[$i].settings.clients[$j])' "$XRAY_CONFIG" > "$config_tmp"
                safe_update_config "$config_tmp"
                info "已从 ${tag} 删除用户: ${email}"
                found=1
                break 2
            fi
        done
    done

    if [[ $found -eq 0 ]]; then
        warn "未找到用户: ${email}"
    fi
}

# ---- 帮助信息 ----
show_usage() {
    echo -e "${CYAN}BorderX 用户管理工具${NC}"
    echo ""
    echo "用法:"
    echo "  $0 add-vless  <email>     添加 VLESS Reality 用户"
    echo "  $0 add-vmess  <email>     添加 VMess WebSocket 用户"
    echo "  $0 add-trojan <email>     添加 Trojan 用户"
    echo "  $0 list                   列出所有用户"
    echo "  $0 remove    <email>      删除用户"
    echo "  $0 restart                重启 Xray 服务"
    echo ""
    echo "示例:"
    echo "  $0 add-vless alice@phone"
    echo "  $0 list"
    echo "  $0 remove alice@phone"
}

# ---- 入口 ----
# 确保 jq 可用
if ! command -v jq &>/dev/null; then
    apt-get install -y jq >> /dev/null 2>&1 || error "无法安装 jq，请手动安装"
fi

# 确保 qrencode 可用（可选）
if ! command -v qrencode &>/dev/null; then
    apt-get install -y qrencode >> /dev/null 2>&1 || true
fi

case "${1:-}" in
    add-vless)
        [[ -z "${2:-}" ]] && error "请指定用户 email"
        add_vless_user "$2"
        restart_xray
        ;;
    add-vmess)
        [[ -z "${2:-}" ]] && error "请指定用户 email"
        add_vmess_user "$2"
        restart_xray
        ;;
    add-trojan)
        [[ -z "${2:-}" ]] && error "请指定用户 email"
        add_trojan_user "$2"
        restart_xray
        ;;
    list)
        list_users
        ;;
    remove)
        [[ -z "${2:-}" ]] && error "请指定用户 email"
        remove_user "$2"
        restart_xray
        ;;
    restart)
        restart_xray
        ;;
    *)
        show_usage
        ;;
esac
