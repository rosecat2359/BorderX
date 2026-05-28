# BorderX 使用文档

> **免责声明**：本项目仅供学习研究使用。使用者需遵守当地法律法规，作者不对任何滥用行为负责。

---

## 目录

1. [项目概述](#1-项目概述)
2. [系统要求](#2-系统要求)
3. [文件结构](#3-文件结构)
4. [部署指南](#4-部署指南)
5. [管理面板 (3X-UI)](#5-管理面板-3x-ui)
6. [用户管理 (命令行)](#6-用户管理-命令行)
7. [客户端配置](#7-客户端配置)
8. [监控与维护](#8-监控与维护)
9. [一键更新](#9-一键更新)
10. [备份与恢复](#10-备份与恢复)
11. [故障排查](#11-故障排查)
12. [卸载](#12-卸载)

---

## 1. 项目概述

BorderX 是基于 **Xray-core** + **3X-UI** 的 VPN 服务一键部署方案，专为 Debian/Ubuntu 设计。

**核心特性：**

| 特性 | 说明 |
|------|------|
| 多协议支持 | VLESS Reality / VMess WebSocket / Trojan TLS（低内存模式仅 VLESS Reality） |
| Web 管理面板 | 可视化管理用户、流量、配置、生成客户端链接/二维码 |
| 自动优化 | 内存 ≤ 1GB 自动启用低内存模式（创建 Swap、精简协议、限制内存） |
| 多镜像下载 | GitHub 直连 + 4 个镜像源轮询，适应各种网络环境 |
| 安全加固 | SSH 密钥认证、Fail2Ban 防暴力破解、内核参数优化 |
| 随机密码 | 面板管理员密码在部署时自动随机生成 |
| 自动备份 | 每日凌晨 2 点自动备份配置，保留最近 10 份 |
| 健康检查 | 每 5 分钟自动巡检，服务异常时自动重启恢复 |

**技术栈：**

```
┌─────────────────────────────────────┐
│         Nginx (反向代理 TLS)          │
│         端口 8443 → 3X-UI:2053       │
├─────────────────────────────────────┤
│     3X-UI Web 面板 (端口 2053)        │
│     用户管理 ─ 流量统计 ─ 配置编辑     │
├──────────┬──────────┬───────────────┤
│ VLESS    │ VMess    │ Trojan        │
│ Reality  │ WS       │ TLS           │
│ :443     │ :10001   │ :10002        │
├──────────┴──────────┴───────────────┤
│           Xray-core 引擎             │
├─────────────────────────────────────┤
│        Debian / Ubuntu 系统          │
└─────────────────────────────────────┘
```

---

## 2. 系统要求

| 项目 | 最低配置 | 推荐配置 |
|------|---------|---------|
| 操作系统 | Debian 10+ / Ubuntu 20.04+ | Debian 12+ / Ubuntu 22.04+ |
| CPU | 1 核 | 2 核 |
| 内存 | 512MB (+ 1GB Swap) | 1GB+ |
| 磁盘 | 5GB | 20GB+ |
| 网络 | 公网 IP，25Mbps+ | 100Mbps+ |

> 低内存模式自动启用，仅开启 VLESS Reality 协议 + Swap，日常运行占用 ~200MB，可支撑 10-20 个并发用户。

---

## 3. 文件结构

```
项目目录 (如 /opt/BorderX)
├── deploy.sh                       # 一键部署入口
├── install.sh                      # 安装编排脚本（source lib/ 模块）
├── uninstall.sh                    # 卸载脚本
├── lib/                            # 安装模块库
│   ├── common.sh                   #   公共函数：日志、检测、下载回退
│   ├── deps.sh                     #   系统依赖安装
│   ├── xray-install.sh             #   Xray-core 下载/安装/配置生成
│   ├── panel-install.sh            #   3X-UI 面板安装 + 随机密码
│   ├── nginx.sh                    #   Nginx 反向代理配置
│   ├── security.sh                 #   Fail2Ban 防暴力破解
│   ├── maintenance.sh              #   日志轮转、Swap、安装信息
│   └── services.sh                 #   服务启动 + 安装摘要
├── config/
│   ├── xray-config-template.json   # Xray 配置模板（全协议）
│   ├── xray-config-lowmem.json     # Xray 配置模板（仅 VLESS）
│   └── nginx-panel.conf            # Nginx 反向代理配置
└── scripts/
    ├── harden.sh                   # 系统安全加固
    ├── backup.sh                   # 配置备份
    ├── monitor.sh                  # 服务监控
    ├── health-check.sh             # 健康检查 + 自动恢复
    ├── user-manager.sh             # 命令行用户管理
    ├── optimize-lowmem.sh          # 低内存深度优化
    └── fix-dns.sh                  # DNS 配置修复

安装后系统路径
├── /usr/local/bin/xray             # Xray 二进制文件
├── /usr/local/etc/xray/config.json # Xray 运行配置
├── /usr/local/x-ui/                # 3X-UI 面板目录
│   ├── x-ui                        # 面板二进制文件
│   └── bin/config.json             # 面板配置
├── /usr/local/borderx/             # 项目安装信息
│   ├── install-info.env            # 安装参数（可 source）
│   ├── install-info.json           # 安装参数（JSON 格式）
│   └── scripts/                    # 运维脚本副本
├── /etc/nginx/sites-available/
│   └── borderx-panel               # Nginx 面板代理配置
├── /opt/borderx-backups/           # 自动备份目录
└── /var/log/xray/                  # Xray 日志目录
```

---

## 4. 部署指南

### 4.1 一键部署

```bash
# 1. 将项目目录上传到服务器
scp -r BorderX/ root@你的服务器IP:/opt/

# 2. 登录服务器并执行
ssh root@你的服务器IP
cd /opt/BorderX
chmod +x deploy.sh install.sh uninstall.sh
chmod +x scripts/*.sh
./deploy.sh
```

部署流程（5 步）：
1. **VPN 核心服务** — 安装 Xray-core、3X-UI 面板、Nginx、Fail2Ban
2. **安全加固** — 交互式选择是否执行（推荐 Y）
3. **部署运维脚本** — 将管理脚本复制到 `/usr/local/borderx/scripts/`
4. **首次备份** — 自动备份初始配置
5. **定时任务** — 每日凌晨 2:00 自动备份 + 每 5 分钟健康检查

### 4.2 低内存模式（≤1GB）

脚本**自动检测**内存并启用低内存模式，无需手动操作：

- 仅启用 VLESS Reality 协议（最省资源）
- Xray 日志级别设为 warning
- 自动创建 1GB Swap 分区
- 后续可通过 `bash scripts/optimize-lowmem.sh` 进一步限制各服务内存

### 4.3 部署后输出示例

```
╔══════════════════════════════════════════════════════════════╗
║              BorderX 服务安装完成!                      ║
╠══════════════════════════════════════════════════════════════╣
║ 管理面板: https://192.0.2.1:8443
║ 用户名:   admin
║ 密码:     aB3xK9mQ2wR7tY4v  (已随机生成)
╠══════════════════════════════════════════════════════════════╣
║ VLESS Reality: 192.0.2.1:443
║ (低内存模式: 仅 VLESS Reality)
╠══════════════════════════════════════════════════════════════╣
║ 配置文件: /usr/local/etc/xray/config.json
║ 安装信息: /usr/local/borderx/install-info.env
║          /usr/local/borderx/install-info.json
║ 日志目录: /var/log/xray/
╠══════════════════════════════════════════════════════════════╣
║ 常用命令:
║   systemctl status xray       - 查看 Xray 状态
║   systemctl restart xray      - 重启 Xray
║   systemctl status x-ui       - 查看面板状态
║   bash /usr/local/borderx/scripts/monitor.sh - 监控面板
║   source /usr/local/borderx/install-info.env - 加载连接信息
╚══════════════════════════════════════════════════════════════╝
```

### 4.4 端口说明

| 端口 | 协议 | 用途 |
|------|------|------|
| 22 | TCP | SSH（不要关闭！） |
| 443 | TCP | VLESS Reality 入站 |
| 8443 | TCP | 管理面板 (HTTPS) |
| 10001 | TCP | VMess WebSocket（非低内存模式） |
| 10002 | TCP | Trojan TLS（非低内存模式） |
| 10085 | TCP (本地) | Xray API（供面板读取流量统计） |
| 2053 | TCP (本地) | 3X-UI 面板内部端口 |

---

## 5. 管理面板 (3X-UI)

### 5.1 登录

```
地址: https://你的服务器IP:8443
用户: admin
密码: 部署时随机生成，查看方式:
      cat /usr/local/borderx/install-info.env | grep PANEL_PASSWORD
```

> 密码在部署时随机生成，不同于旧版的默认 admin/admin。如忘记密码，可用以下命令重置：
> `/usr/local/x-ui/x-ui setting -username admin -password 新密码`

### 5.2 面板主要功能

| 功能 | 位置 | 说明 |
|------|------|------|
| 入站管理 | 侧边栏 → 入站列表 | 查看/编辑 VLESS Reality 等协议的入站配置 |
| 用户管理 | 入站详情 → 客户端列表 | 添加/删除/编辑用户，设置流量限制和过期时间 |
| 流量统计 | 入站详情 | 实时查看每个用户的上下行流量 |
| 生成链接 | 用户行 → 操作 → 分享链接 | 生成 URL/二维码供客户端导入 |
| Xray 配置 | 侧边栏 → Xray 设置 | 直接编辑 Xray JSON 配置（高级） |
| 面板设置 | 侧边栏 → 面板设置 | 修改面板端口、管理员密码、证书等 |

### 5.3 添加入站

1. 点击「添加入站」
2. 协议选择 `vless`（低内存模式）或 `vmess` / `trojan`
3. 监听 IP 填 `0.0.0.0`，端口填目标端口（如 443）
4. 传输设置按需配置（VLESS Reality 选 tcp + reality）
5. 保存后在「客户端」中添加用户

### 5.4 添加用户（面板方式）

1. 进入对应入站的「操作」→「查看」
2. 点击「添加客户端」
3. 填写 Email（标识名）、流量限制（可选）、过期时间（可选）
4. 保存后自动生成连接二维码

---

## 6. 用户管理 (命令行)

除了面板，也可以通过命令行管理用户：

```bash
# 添加 VLESS Reality 用户（自动生成分享链接和二维码）
bash scripts/user-manager.sh add-vless  user1@example.com

# 添加 VMess WebSocket 用户
bash scripts/user-manager.sh add-vmess  user2@example.com

# 添加 Trojan 用户
bash scripts/user-manager.sh add-trojan user3@example.com

# 列出所有用户
bash scripts/user-manager.sh list

# 删除用户
bash scripts/user-manager.sh remove user1@example.com

# 重启 Xray 使配置生效
bash scripts/user-manager.sh restart
```

> 注意：VMess 和 Trojan 命令在低内存模式下不可用（入站未创建）。

---

## 7. 客户端配置

### 7.1 推荐客户端

| 平台 | 推荐软件 |
|------|---------|
| Windows | v2rayN / Nekoray |
| macOS | V2rayU / Nekoray |
| Android | v2rayNG / Clash Meta for Android |
| iOS | Shadowrocket / Streisand |
| Linux | Nekoray / v2rayA |
| 路由器 | PassWall / OpenClash |

### 7.2 导入方式

**方式一：命令行生成（推荐）**

```bash
bash scripts/user-manager.sh add-vless alice@phone
# 输出中包含分享链接和二维码，直接用客户端扫码导入
```

**方式二：面板生成**

1. 打开面板 → 入站 → 查看 → 客户端列表
2. 点击用户行的「分享链接」→ 复制 URL 或扫描二维码
3. 在客户端中「从剪贴板导入」或「扫描二维码」

**方式三：查看安装信息**

```bash
# 加载连接信息到环境变量
source /usr/local/borderx/install-info.env
echo "$VLESS_UUID"
echo "$REALITY_PUB"
echo "$REALITY_SID"

# 或查看 JSON 格式
cat /usr/local/borderx/install-info.json
```

手动填入客户端配置。

### 7.3 VLESS Reality 配置示例

**v2rayN / Nekoray 手动配置：**

```
地址 (address):    你的服务器IP
端口 (port):       443
用户ID (uuid):     来自 install-info.env 的 VLESS_UUID
流控 (flow):       xtls-rprx-vision
加密 (encryption): none
传输 (network):    tcp
安全 (security):   reality

Reality 设置:
  SNI:             www.microsoft.com
  Public Key:      来自 install-info.env 的 REALITY_PUB
  Short ID:        来自 install-info.env 的 REALITY_SID
  指纹 (fingerprint): chrome
```

### 7.4 分享链接示例

```
VLESS Reality:
vless://uuid@IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=REALITY_PUB&sid=SHORT_ID&type=tcp#BorderX

VMess WebSocket:
vmess://base64编码的JSON配置

Trojan TLS:
trojan://password@IP:10002?security=tls&type=tcp#BorderX
```

---

## 8. 监控与维护

### 8.1 服务监控面板

```bash
bash scripts/monitor.sh
```

输出包括：系统信息、CPU/内存/磁盘使用率、网络流量、Xray 版本和进程信息、Fail2Ban 封禁记录、活跃连接数、最近日志。

### 8.2 自动健康检查

部署时自动创建了每 5 分钟执行一次的健康检查 cron 任务。脚本会：

- 检测 Xray 和 3X-UI 运行状态，异常时自动重启
- 监控内存使用率（>90% 预警）
- 监控磁盘空间（>90% 预警）

```bash
# 查看健康检查日志
tail -f /var/log/borderx-healthcheck.log

# 手动执行一次
bash scripts/health-check.sh
```

### 8.3 日常管理命令

```bash
# 查看 Xray 状态
systemctl status xray

# 重启 Xray（修改配置后）
systemctl restart xray

# 查看 Xray 实时日志
journalctl -u xray -f

# 查看 3X-UI 面板状态
systemctl status x-ui

# 查看 Nginx 状态
systemctl status nginx

# 查看 Fail2Ban 封禁状态
fail2ban-client status
fail2ban-client status sshd
```

### 8.4 低内存优化

如果部署后内存仍然紧张，可运行独立优化脚本：

```bash
bash scripts/optimize-lowmem.sh
```

该脚本会：
- 创建/扩容 Swap（≤512MB 内存自动创建 2GB）
- 为 Xray、3X-UI、Nginx 设置 systemd 内存限制
- 调整内核 swappiness=10
- 限制 journal 日志大小到 50MB
- 禁用不必要的定时任务

---

## 9. 一键更新

部署后如需更新 Xray-core 或 3X-UI 到最新版本：

```bash
bash update.sh
```

脚本流程：
1. 自动备份当前配置到 `/opt/borderx-backups/`
2. 检查 Xray-core 是否有新版本，有则询问是否更新
3. 检查 3X-UI 是否有新版本，有则询问是否更新
4. 更新前自动停止服务，更新后自动启动
5. 保留所有用户配置和入站设置，仅替换二进制文件

```bash
# 也可单独更新某个组件
bash update.sh  # 交互式选择

# 更新后验证
systemctl status xray
systemctl status x-ui
```

---

## 10. 备份与恢复

### 10.1 手动备份

```bash
bash /usr/local/borderx/scripts/backup.sh
```

备份位置：`/opt/borderx-backups/`  
格式：`20260501_120000.tar.gz`  
自动保留最近 10 份备份。

备份内容：Xray 配置、3X-UI 数据库、Nginx 配置、Fail2Ban 配置、安装信息、systemd 服务文件。

### 10.2 定时自动备份

部署时已自动配置 cron，每日凌晨 2:00 执行。查看：

```bash
cat /etc/cron.d/borderx-backup
```

### 10.3 恢复配置

```bash
# 找到要恢复的备份
ls /opt/borderx-backups/

# 解压
tar -xzf /opt/borderx-backups/20260501_120000.tar.gz -C /tmp/restore

# 还原 Xray 配置
cp /tmp/restore/20260501_120000/xray-config/config.json /usr/local/etc/xray/
systemctl restart xray

# 还原 3X-UI 数据库
systemctl stop x-ui
cp /tmp/restore/20260501_120000/x-ui.db /etc/x-ui/x-ui.db
systemctl start x-ui
```

---

## 11. 故障排查

### 11.1 面板无法访问

```
问题: https://IP:8443 无法打开
排查:
  1. netstat -tlnp | grep 8443 — 端口是否监听
  2. systemctl status nginx — Nginx 是否运行
  3. systemctl status x-ui — 3X-UI 是否运行
  4. nginx -t — Nginx 配置是否正确
  5. cat /var/log/nginx/borderx-panel.error.log — 查看 Nginx 错误日志
```

### 11.2 客户端无法连接

```
问题: VLESS Reality 连接失败
排查:
  1. netstat -tlnp | grep 443 — 确认端口被监听
  2. systemctl status xray — 是否在运行
  3. journalctl -u xray -n 50 — 查看最近错误日志
  4. 核对客户端的 UUID / Public Key / Short ID 是否与服务器一致
  5. cat /usr/local/borderx/install-info.env — 查看配置参数
  6. 检查客户端时间是否同步（Reality 协议对时间敏感）
```

### 11.3 内存不足

```
问题: 面板或 Xray 频繁被系统杀进程 (OOM)
解决:
  bash scripts/optimize-lowmem.sh
  bash scripts/health-check.sh  # 确认服务已恢复
```

### 11.4 证书过期（面板 HTTPS）

```bash
# 重新生成自签名证书
openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout /usr/local/etc/xray/panel.key \
    -out /usr/local/etc/xray/panel.crt \
    -days 3650 \
    -subj "/CN=localhost"
systemctl restart nginx
```

### 11.5 DNS 解析异常

```bash
bash scripts/fix-dns.sh
# 脚本会检查并注入 Google + Cloudflare DoH DNS 配置
```

### 11.6 查看安装日志

```bash
cat /var/log/borderx-install.log
```

---

## 12. 卸载

```bash
bash uninstall.sh
```

卸载流程：
- 停止并删除 Xray、3X-UI 系统服务
- 删除 Xray 二进制和配置文件
- 删除 3X-UI 面板和数据库
- 删除 Nginx 面板配置
- 删除安装信息、运维脚本和定时任务
- 可选：移除安全加固配置

**保留的组件**（需手动移除）：
- Nginx：`apt-get remove --purge nginx`
- Fail2Ban：`apt-get remove --purge fail2ban`
- Certbot：`apt-get remove --purge certbot python3-certbot-nginx`
- 备份数据：`rm -rf /opt/borderx-backups`

---

## 附录 A：从面板创建用户后分享给客户端

1. 打开面板 → 点击对应入站的「查看」
2. 「添加客户端」→ 填写 Email（如 `xiaoming@phone`）→ 设置流量上限（可选）
3. 保存后，在客户端列表点击「分享链接」
4. 将链接或二维码发给用户，用户用客户端导入即可

## 附录 B：修改面板端口

```bash
# 编辑面板配置
vi /usr/local/x-ui/bin/config.json
# 修改 "port" 字段

# 同时更新 Nginx 代理
vi /etc/nginx/sites-available/borderx-panel
# 修改 proxy_pass 中的端口

nginx -t && systemctl restart nginx
systemctl restart x-ui
```

## 附录 C：添加新协议

低内存模式仅部署了 VLESS Reality。如需添加其他协议：

```bash
# 通过面板添加
面板 → 添加入站 → 选择协议（VMess/Trojan）→ 配置参数 → 保存

# 通过命令行添加 VMess
bash scripts/user-manager.sh add-vmess user@example.com
```

## 附录 D：定时任务说明

部署后自动创建两个 cron 任务：

| 任务 | 频率 | 脚本 |
|------|------|------|
| 配置备份 | 每日 02:00 | `/usr/local/borderx/scripts/backup.sh` |
| 健康检查 | 每 5 分钟 | `/usr/local/borderx/scripts/health-check.sh` |

```bash
# 查看定时任务
cat /etc/cron.d/borderx-backup
cat /etc/cron.d/borderx-healthcheck
```
