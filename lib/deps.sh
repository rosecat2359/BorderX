#!/usr/bin/env bash
# ============================================================
# BorderX 依赖安装模块
# 安装 Nginx、UFW、Fail2Ban、qrencode、cron、logrotate 等
# ============================================================
set -euo pipefail

install_dependencies() {
    info "更新软件包列表..."
    if ! apt-get update -y >> "$LOG_FILE" 2>&1; then
        warn "apt-get update 返回非零，继续尝试..."
    fi

    info "安装基础依赖..."
    # 分两次安装以隔离可能失败的包
    apt-get install -y \
        curl wget unzip tar \
        nginx \
        fail2ban \
        cron logrotate \
        >> "$LOG_FILE" 2>&1 || {
        warn "部分依赖安装可能失败，尝试继续..."
    }

    # qrencode 和 certbot 属于非关键依赖，单独安装
    apt-get install -y qrencode >> "$LOG_FILE" 2>&1 || warn "qrencode 安装失败，将跳过二维码功能"
    apt-get install -y certbot python3-certbot-nginx >> "$LOG_FILE" 2>&1 || warn "certbot 安装失败，将使用自签名证书"

    info "基础依赖安装完成"
}
