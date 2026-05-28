#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# BorderX — Xray-core + 3X-UI 一键部署方案
# 免责声明: 本脚本仅供学习研究使用，使用者需遵守当地法律法规。
# 作者不对任何滥用行为负责。请勿用于任何违法用途。
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/core.sh"
source "${SCRIPT_DIR}/lib/setup.sh"

main() {
    echo -e "${CYAN}  BorderX 一键安装  Xray-core + 3X-UI${NC}\n"

    # 初始化日志目录（必须在任何 info 调用之前）
    mkdir -p /var/log /var/tmp/borderx "$INSTALL_DIR"
    touch "$LOG_FILE"

    check_root
    check_os
    check_memory

    rm -rf /tmp/tmp.* 2>/dev/null || true

    setup_swap
    install_deps
    install_xray
    create_xray_service
    install_panel
    gen_xray_config
    setup_nginx
    setup_fail2ban
    setup_firewall
    setup_logrotate
    start_all
    save_info
    print_done
}

main "$@"
