#!/usr/bin/env bash
# ============================================================
# BorderX 3X-UI 管理面板安装模块
# 下载、安装 3X-UI，设置随机管理员密码
# ============================================================
set -euo pipefail

# 面板默认凭据（会被随机化覆盖）
PANEL_USERNAME="admin"
PANEL_PASSWORD=""

install_3xui() {
    info "安装 3X-UI 管理面板..."

    # 生成随机管理员密码
    PANEL_PASSWORD=$(generate_password)
    info "已生成随机面板密码: ${PANEL_PASSWORD}"

    info "获取 3X-UI 最新版本..."
    local xui_version=""

    # 来源 1: GitHub API 直连
    xui_version=$(curl -sL --connect-timeout 10 "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" 2>/dev/null \
        | { grep -o '"tag_name":"[^"]*"' || true; } | head -1 | { grep -o '"v[^"]*"' || true; } | tr -d '"')

    # 来源 2: GitHub API 镜像
    if [[ -z "$xui_version" ]] || [[ "$xui_version" != v* ]]; then
        xui_version=$(curl -sL --connect-timeout 10 "https://ghfast.top/https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" 2>/dev/null \
            | { grep -o '"tag_name":"[^"]*"' || true; } | head -1 | { grep -o '"v[^"]*"' || true; } | tr -d '"')
    fi

    # 来源 3: 从官方安装脚本提取版本
    if [[ -z "$xui_version" ]] || [[ "$xui_version" != v* ]]; then
        xui_version=$(curl -sL --connect-timeout 10 "https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh" 2>/dev/null \
            | grep -oP 'LATEST="\K[^"]*' | head -1) || true
        [[ -n "$xui_version" ]] && xui_version="v${xui_version}"
    fi

    if [[ -z "$xui_version" ]] || [[ "$xui_version" != v* ]]; then
        xui_version="$XUI_FALLBACK_VERSION"
        warn "无法获取最新版本（已尝试 3 个来源），使用回退版本: ${xui_version}"
    fi

    info "3X-UI 版本: ${xui_version}"

    local arch xui_arch
    arch=$(dpkg --print-architecture)
    case "$arch" in
        amd64)  xui_arch="amd64" ;;
        arm64)  xui_arch="arm64" ;;
        armhf)  xui_arch="armv7" ;;
        *)      error "不支持的架构: $arch" ;;
    esac

    local filename="x-ui-linux-${xui_arch}.tar.gz"
    local tmpdir
    tmpdir=$(mktemp -d -p /var/tmp/borderx xui-XXXXXX)

    # 构建镜像 URL 列表
    local urls=()
    for mirror in "${GITHUB_MIRRORS[@]}"; do
        urls+=("${mirror}/MHSanaei/3x-ui/releases/download/${xui_version}/${filename}")
    done

    local download_ok=false
    for url in "${urls[@]}"; do
        info "尝试下载: ${url}"
        rm -f "${tmpdir}/x-ui.tar.gz"
        if wget --timeout=300 --tries=2 -O "${tmpdir}/x-ui.tar.gz" "$url" 2>/dev/null; then
            local fsize_bytes
            fsize_bytes=$(stat -c%s "${tmpdir}/x-ui.tar.gz" 2>/dev/null || echo 0)
            if [[ "$fsize_bytes" -gt 50000000 ]]; then
                download_ok=true
                local fsize
                fsize=$(du -h "${tmpdir}/x-ui.tar.gz" | cut -f1)
                info "下载成功 (大小: ${fsize})"
                break
            else
                warn "下载文件过小 (${fsize_bytes} 字节)，可能不完整，重试..."
                rm -f "${tmpdir}/x-ui.tar.gz"
            fi
        fi
        warn "下载失败: ${url}"
    done

    if [[ "$download_ok" != true ]]; then
        info "============================================"
        info "3X-UI 预编译包下载失败，改用官方安装脚本"
        info "============================================"
        sleep 1
        bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)
        if [[ -d /usr/local/x-ui ]] && [[ -x /usr/local/x-ui/x-ui ]]; then
            info "3X-UI 通过官方脚本安装成功"
            update_panel_password
            rm -rf "$tmpdir"
            return 0
        else
            error "3X-UI 安装失败，请检查网络连接"
        fi
    fi

    info "解压 3X-UI..."
    tar -xzf "${tmpdir}/x-ui.tar.gz" -C "${tmpdir}" >> "$LOG_FILE" 2>&1

    # 查找二进制文件位置
    local xui_bin
    xui_bin=$(find "${tmpdir}" -name "x-ui" -type f 2>/dev/null | head -1)
    if [[ -z "$xui_bin" ]]; then
        tar -tzf "${tmpdir}/x-ui.tar.gz" 2>/dev/null | head -20 >> "$LOG_FILE" || true
        error "3X-UI 二进制文件未找到于压缩包中"
    fi

    info "部署 3X-UI 到 /usr/local/x-ui..."
    local xui_src_dir
    xui_src_dir=$(dirname "$xui_bin")
    rm -rf /usr/local/x-ui
    ensure_dir /usr/local/x-ui
    cp -r "${xui_src_dir}/." /usr/local/x-ui/ >> "$LOG_FILE" 2>&1
    chmod +x /usr/local/x-ui/x-ui 2>/dev/null || true

    if [[ ! -f /usr/local/x-ui/x-ui ]]; then
        error "3X-UI 二进制文件部署失败"
    fi

    info "3X-UI ${xui_version} 安装完成"
    rm -rf "$tmpdir"

    update_panel_password

    # 创建 systemd 服务（如果还不存在）
    if [[ ! -f /etc/systemd/system/x-ui.service ]]; then
        safe_write /etc/systemd/system/x-ui.service <<'EOF'
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
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload 2>/dev/null || true
    fi

    info "3X-UI 管理面板安装完成"
}

update_panel_password() {
    # 更新 3X-UI 面板管理员密码
    # 优先使用 x-ui setting 命令，失败则直接操作 SQLite 数据库

    local xui_db="/etc/x-ui/x-ui.db"
    local xui_config="/usr/local/x-ui/bin/config.json"
    local password_set=false

    # 确保面板配置目录存在
    ensure_dir /usr/local/x-ui/bin
    ensure_dir /etc/x-ui

    # 写入面板基础配置（端口、凭据）
    if [[ ! -f "$xui_config" ]]; then
        cat > "$xui_config" << EOF
{
    "port": 2053,
    "webPort": 2053,
    "webBasePath": "/",
    "webCertFile": "",
    "webKeyFile": "",
    "timezone": "Asia/Shanghai",
    "tgWebhookUrl": "",
    "logAccess": "",
    "logError": "",
    "xrayTemplateConfig": ""
}
EOF
        info "已创建 3X-UI 配置文件"
    fi

    # 方式一：x-ui setting 命令行
    if [[ -x /usr/local/x-ui/x-ui ]]; then
        if /usr/local/x-ui/x-ui setting -username "$PANEL_USERNAME" -password "$PANEL_PASSWORD" >> "$LOG_FILE" 2>&1; then
            password_set=true
            info "面板密码已设置（命令行方式）"
        fi
    fi

    # 方式二：直接写 SQLite 数据库（x-ui setting 失败时回退）
    if [[ "$password_set" != true ]] && command -v sqlite3 &>/dev/null; then
        info "尝试通过 SQLite 直接设置密码..."
        local hashed
        hashed=$(echo -n "${PANEL_PASSWORD}" | sha256sum | cut -d' ' -f1 2>/dev/null) || true
        if [[ -n "$hashed" ]] && sqlite3 "$xui_db" "UPDATE users SET username='${PANEL_USERNAME}', password='${hashed}' WHERE id=1;" >> "$LOG_FILE" 2>&1; then
            password_set=true
            info "面板密码已设置（SQLite 方式）"
        fi
    fi

    # 方式三：生成密码重置脚本，在首次启动后自动执行
    if [[ "$password_set" != true ]]; then
        safe_write "${INSTALL_DIR}/reset-panel-password.sh" <<'RESETEOF'
#!/usr/bin/env bash
# BorderX - 面板密码重置脚本（首次启动后自动执行）
set -euo pipefail
PANEL_USERNAME="__USERNAME__"
PANEL_PASSWORD="__PASSWORD__"

# 等待面板启动
for i in $(seq 1 30); do
    if systemctl is-active --quiet x-ui 2>/dev/null; then break; fi
    sleep 1
done

if [[ -x /usr/local/x-ui/x-ui ]]; then
    /usr/local/x-ui/x-ui setting -username "$PANEL_USERNAME" -password "$PANEL_PASSWORD" && exit 0
fi

if command -v sqlite3 &>/dev/null && [[ -f /etc/x-ui/x-ui.db ]]; then
    HASHED=$(echo -n "$PANEL_PASSWORD" | sha256sum | cut -d' ' -f1)
    sqlite3 /etc/x-ui/x-ui.db "UPDATE users SET username='${PANEL_USERNAME}', password='${HASHED}' WHERE id=1;" && exit 0
fi

echo "[BorderX] 自动设置面板密码失败，请手动执行: /usr/local/x-ui/x-ui setting -username admin -password <新密码>"
exit 1
RESETEOF
        sed -i "s/__USERNAME__/${PANEL_USERNAME}/g; s/__PASSWORD__/${PANEL_PASSWORD}/g" "${INSTALL_DIR}/reset-panel-password.sh"
        chmod +x "${INSTALL_DIR}/reset-panel-password.sh"

        # 创建 oneshot systemd 服务，首次启动后自动执行
        safe_write /etc/systemd/system/borderx-reset-password.service <<SVCEOF
[Unit]
Description=BorderX Panel Password Reset (oneshot)
After=x-ui.service
Wants=x-ui.service
ConditionPathExists=${INSTALL_DIR}/reset-panel-password.sh

[Service]
Type=oneshot
ExecStart=/bin/bash ${INSTALL_DIR}/reset-panel-password.sh
ExecStartPost=/bin/rm -f ${INSTALL_DIR}/reset-panel-password.sh
ExecStartPost=/bin/systemctl disable borderx-reset-password.service
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
SVCEOF
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable borderx-reset-password.service 2>/dev/null || true
        warn "面板密码将在 x-ui 首次启动后通过 oneshot 服务自动设置"
    fi
}
