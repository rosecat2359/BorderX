# BorderX 重构设计规格

> 2026-05-28 | 状态: 待审查

## 概述

将 BorderX 从一个 Bash 一键部署脚本重构为面向多用户的 VPN SaaS 管理系统。

**核心理念：** 单机 MVP，Panel + Xray 同机部署，Go API 直接操作本地 Xray 配置。后续通过 SSH 扩展多节点。

**技术栈：** Go (API) + React (SPA) + PostgreSQL + Xray-core

## 架构

```
VPS (单机)
├── React SPA ──→ Go API Server (:8080)
│                    │
│              ┌─────┴──────┐
│              │ PostgreSQL │
│              └────────────┘
│                    │
│              ┌─────┴──────┐
│              │ Xray-core  │
│              │ :443/入站  │
│              └────────────┘
```

- Go 二进制内嵌 React 构建产物，单文件部署
- Xray 配置读写通过 Go 直接操作 JSON 文件 + `systemctl reload`
- 流量采集通过 Xray Stats API (:10085 gRPC)
- Panel 内部定时任务用 Go cron 库，不依赖系统 crontab

## 数据库表

### users — 终端用户
| 列 | 类型 |
|---|---|
| id | UUID PK |
| email | VARCHAR(255) UNIQUE |
| password_hash | VARCHAR(255) |
| status | ENUM(active,disabled,deleted) |
| created_at | TIMESTAMP |

### admins — 管理员
| 列 | 类型 |
|---|---|
| id | UUID PK |
| username | VARCHAR(64) UNIQUE |
| password_hash | VARCHAR(255) |
| role | ENUM(super,operator,viewer) |
| created_at | TIMESTAMP |

### plans — 套餐
| 列 | 类型 |
|---|---|
| id | UUID PK |
| name | VARCHAR(128) |
| price_cents | INT |
| duration_days | INT |
| traffic_limit_gb | INT |
| max_devices | INT |
| sort_order | INT |
| is_active | BOOLEAN |

### orders — 订单
| 列 | 类型 |
|---|---|
| id | UUID PK |
| user_id | UUID FK → users |
| plan_id | UUID FK → plans |
| status | ENUM(pending,paid,expired,cancelled) |
| amount_cents | INT |
| paid_at | TIMESTAMP |
| starts_at | TIMESTAMP |
| expires_at | TIMESTAMP |

### vpn_accounts — VPN 账号
| 列 | 类型 |
|---|---|
| id | UUID PK |
| user_id | UUID FK → users |
| order_id | UUID FK → orders |
| protocol | ENUM(vless,vmess,trojan) |
| uuid | UUID |
| password | VARCHAR(128) |
| settings_json | JSONB |
| status | ENUM(active,disabled,expired) |
| traffic_used_bytes | BIGINT |
| traffic_limit_bytes | BIGINT |
| expires_at | TIMESTAMP |
| created_at | TIMESTAMP |

### traffic_logs — 流量明细
| 列 | 类型 |
|---|---|
| id | BIGSERIAL PK |
| account_id | UUID FK → vpn_accounts |
| upload_bytes | BIGINT |
| download_bytes | BIGINT |
| recorded_at | TIMESTAMP |

每小时归档到 traffic_hourly，traffic_logs 仅保留 24h。

### nodes — 节点
| 列 | 类型 |
|---|---|
| id | UUID PK |
| name | VARCHAR(128) |
| host | VARCHAR(255) |
| ssh_port | INT |
| ssh_user | VARCHAR(64) |
| ssh_key_path | VARCHAR(512) |
| region | VARCHAR(64) |
| is_active | BOOLEAN |
| last_seen_at | TIMESTAMP |

### sub_tokens — 订阅 token
| 列 | 类型 |
|---|---|
| id | UUID PK |
| user_id | UUID FK → users UNIQUE |
| token | VARCHAR(64) |
| last_accessed_at | TIMESTAMP |

### audit_logs — 操作日志
| 列 | 类型 |
|---|---|
| id | BIGSERIAL PK |
| admin_id | UUID FK → admins |
| action | VARCHAR(128) |
| target_type | VARCHAR(64) |
| target_id | UUID |
| detail_json | JSONB |
| created_at | TIMESTAMP |

## API

### 用户端 (`/api`, JWT)
```
POST   /api/auth/register
POST   /api/auth/login
POST   /api/auth/forgot-password
POST   /api/auth/reset-password
GET    /api/me
PUT    /api/me/password
GET    /api/plans
POST   /api/orders
GET    /api/orders
GET    /api/accounts
GET    /api/sub?token=xxx         → clash/v2ray 订阅文本
```

### 管理端 (`/api/admin`, JWT + admin role)
```
GET    /api/admin/users
GET    /api/admin/users/:id
POST   /api/admin/users/:id/disable
POST   /api/admin/users/:id/enable
GET    /api/admin/orders
POST   /api/admin/orders/:id/cancel
GET    /api/admin/plans
POST   /api/admin/plans
PUT    /api/admin/plans/:id
DELETE /api/admin/plans/:id
POST   /api/admin/accounts
POST   /api/admin/accounts/:id/reset-uuid
POST   /api/admin/accounts/:id/disable
DELETE /api/admin/accounts/:id
GET    /api/admin/nodes
POST   /api/admin/nodes
PUT    /api/admin/nodes/:id
POST   /api/admin/nodes/:id/test
GET    /api/admin/traffic
GET    /api/admin/traffic/summary
GET    /api/admin/dashboard
GET    /api/admin/audit-logs
GET    /api/admin/settings
PUT    /api/admin/settings
```

### Xray 控制（Go 内部，不暴露 HTTP）
```
XrayConfigReader   → 读 /usr/local/etc/xray/config.json
XrayConfigWriter   → 写 config + systemctl reload xray
XrayStatsReader    → gRPC 调 127.0.0.1:10085 StatsService
RealityKeyManager  → X25519 密钥管理
```

## React 页面

```
/                   首页（套餐展示、注册入口）
/login              登录
/register           注册
/dashboard          用户仪表盘
/dashboard/plans    购买套餐
/dashboard/orders   我的订单
/admin              管理仪表盘
/admin/users        用户列表
/admin/users/:id    用户详情
/admin/orders       订单列表
/admin/plans        套餐管理
/admin/accounts     VPN 账号管理
/admin/nodes        节点管理
/admin/traffic      流量统计
/admin/settings     系统设置
/admin/audit        操作日志
```

## 支付流程

支付宝当面付（扫码支付）：

```
用户选套餐 → 创建 order(pending) → 调支付宝生成 QR 码
→ 用户扫码支付 → 支付宝回调 webhook → order=paid
→ 自动创建 vpn_account → 用户刷新看到账号和订阅链接
```

## 流量统计

每 60 秒 Go cron 任务：
1. Xray Stats API 获取所有客户端累计 upload/download
2. 与上次差值 → 写入 traffic_logs
3. 累加 vpn_accounts.traffic_used_bytes
4. 超限的自动 disable

定时任务：
```
@every 60s    采集流量
@every 1h     归档到 traffic_hourly
@daily 03:00  检查过期账号
@daily 04:00  清理 30 天前审计日志
```

## 安全

- 密码: bcrypt cost=12
- JWT: RS256, 24h 过期
- 用户 API: 60 req/min; 管理 API: 300 req/min
- 注册: 同 IP 每小时最多 3 个账号
- 登录: 5 次失败锁定 15 分钟
- Xray 私钥: 文件 600, owner root
- 敏感配置: 环境变量或 /etc/borderx/config.yml
- 数据库: 仅监听 127.0.0.1
- Xray Stats API: 仅监听 127.0.0.1:10085

## 测试

| 层级 | 工具 | 覆盖 |
|---|---|---|
| Go 单元 | testing + testify | xray config、流量计算、订单状态机 |
| Go 集成 | testcontainers-go | 数据库迁移、API handler |
| React 组件 | Vitest + Testing Library | 页面渲染、表单 |
| E2E | Playwright | 注册→下单→支付→订阅 全流程 |

## 部署

一键安装:
```bash
curl -sL https://get.borderx.io/install.sh | bash
```

脚本流程:
1. 检测 Debian/Ubuntu
2. 下载 borderx-panel 到 /usr/local/bin/
3. 安装 Xray-core
4. 生成 Xray 配置 + X25519 密钥
5. 创建 PostgreSQL 数据库（可选 SQLite 轻量模式）
6. 跑迁移 + 默认管理员账号
7. 创建 systemd 服务 + 启动

## 开发分阶段

| Phase | 内容 | 预估 |
|---|---|---|
| 1. 核心骨架 | Go 项目 + DB 迁移 + 注册/登录 + 管理 CRUD + React 基础页面 | 2 周 |
| 2. VPN 核心 | Xray 配置读写 + 购买→创建账号 + 流量采集 + 订阅链接 | 2 周 |
| 3. 支付 & 运维 | 支付宝支付 + 统计页面 + 一键安装 + systemd/Nginx | 1 周 |
| 4. 打磨 | 邮箱验证 + 密码重置 + 审计日志 + E2E 测试 | 1 周 |

## 目录结构

```
BorderX/
├── server/
│   ├── cmd/panel/main.go
│   ├── internal/
│   │   ├── api/          # 用户端 handler
│   │   ├── admin/        # 管理端 handler
│   │   ├── xray/         # Xray 配置读写 + 流量
│   │   ├── billing/      # 订单 + 支付
│   │   ├── traffic/      # 流量统计
│   │   ├── sub/          # 订阅链接生成
│   │   ├── auth/         # JWT
│   │   ├── model/        # DB 模型
│   │   ├── mail/         # SMTP
│   │   └── payment/      # 支付宝/微信
│   ├── migrations/
│   ├── go.mod
│   └── go.sum
├── web/
│   ├── src/
│   │   ├── pages/
│   │   ├── components/
│   │   ├── hooks/
│   │   ├── store/
│   │   └── App.tsx
│   ├── package.json
│   └── vite.config.ts
├── deploy/
│   ├── panel.service
│   ├── nginx.conf
│   ├── install.sh
│   └── Dockerfile
└── docs/
```

## 关键决策记录

1. **不用 Agent** — 避免维护额外组件，Panel 本机直管 Xray
2. **不用 3X-UI** — 减少依赖，通过 Go 直接操作 Xray JSON 配置
3. **单机 MVP** — 先跑通单机全景，后续 SSH 扩展多节点
4. **Go 内嵌前端** — 单二进制部署，对标 X-UI 的一键脚本体验
5. **Go cron 替代系统 crontab** — 减少部署耦合，定时任务随 Panel 启停
