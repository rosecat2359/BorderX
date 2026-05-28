#!/usr/bin/env bash
# ============================================================
# BorderX 服务管理模块
# 启动/启用所有服务，打印安装摘要
# ============================================================
set -euo pipefail

start_services() {
    info "启动所有服务..."

    # Xray
    systemctl enable xray 2>/dev/null || true
    systemctl start xray 2>/dev/null || true
    sleep 2
    if systemctl is-active --quiet xray 2>/dev/null; then
        info "Xray 服务启动成功"
    else
        warn "Xray 服务启动失败，请检查日志: journalctl -u xray"
    fi

    # 3X-UI 面板
    systemctl enable x-ui 2>/dev/null || true
    systemctl start x-ui 2>/dev/null || true
    sleep 2
    if systemctl is-active --quiet x-ui 2>/dev/null; then
        info "3X-UI 面板启动成功"
    else
        warn "3X-UI 面板启动失败，请检查日志: journalctl -u x-ui"
    fi
}

print_summary() {
    local server_ip
    server_ip=$(cat "${INSTALL_DIR}/server.ip" 2>/dev/null || echo "YOUR_SERVER_IP")
    local panel_pw_display="${PANEL_PASSWORD:-admin}"

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              BorderX 服务安装完成!                      ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} 管理面板: ${GREEN}https://${server_ip}:8443${NC}"
    echo -e "${CYAN}║${NC} 用户名:   ${GREEN}${PANEL_USERNAME:-admin}${NC}"
    echo -e "${CYAN}║${NC} 密码:     ${GREEN}${panel_pw_display}${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} VLESS Reality: ${GREEN}${server_ip}:443${NC}"
    if [[ "$LOW_MEMORY" != true ]]; then
        echo -e "${CYAN}║${NC} VMess WS:      ${GREEN}${server_ip}:10001${NC}"
        echo -e "${CYAN}║${NC} Trojan TLS:    ${GREEN}${server_ip}:10002${NC}"
    else
        echo -e "${CYAN}║${NC} ${YELLOW}(低内存模式: 仅 VLESS Reality)${NC}"
    fi
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} 配置文件: ${YELLOW}/usr/local/etc/xray/config.json${NC}"
    echo -e "${CYAN}║${NC} 安装信息: ${YELLOW}${INSTALL_DIR}/install-info.env${NC}"
    echo -e "${CYAN}║${NC}          ${YELLOW}${INSTALL_DIR}/install-info.json${NC}"
    echo -e "${CYAN}║${NC} 日志目录: ${YELLOW}/var/log/xray/${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} 常用命令:${NC}"
    echo -e "${CYAN}║${NC}   systemctl status xray       - 查看 Xray 状态${NC}"
    echo -e "${CYAN}║${NC}   systemctl restart xray      - 重启 Xray${NC}"
    echo -e "${CYAN}║${NC}   systemctl status x-ui       - 查看面板状态${NC}"
    echo -e "${CYAN}║${NC}   bash scripts/monitor.sh     - 服务监控面板${NC}"
    echo -e "${CYAN}║${NC}   source ${INSTALL_DIR}/install-info.env # 加载连接信息${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ "$panel_pw_display" == "admin" ]]; then
        warn "============================================"
        warn "  安全提醒: 面板使用默认密码 admin!"
        warn "  请立即登录面板修改密码:"
        warn "  https://${server_ip}:8443"
        warn "============================================"
    fi
}
