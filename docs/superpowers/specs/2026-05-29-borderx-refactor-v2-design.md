# BorderX 重构设计规格 v2

> 2026-05-29 | 状态: 待审查

## 概述

将 BorderX 从 VPN SaaS 管理系统重构为轻量级 VPN 运维管理面板，聚焦快速部署和极简操作。

**核心理念：** 单二进制部署，三步上线（添加节点 → 创建入站 → 复制订阅），对标 X-UI 体验。

**技术栈：** Go 1.22+ + React 18 + TypeScript + SQLite + MUI v6 (Material Design 3)

## 架构

```
┌──────────────────────────────────────────────┐
│              borderx-panel (单二进制)           │
│                                               │
│  ┌──────────┐  ┌──────────┐  ┌─────────────┐ │
│  │ React SPA │  │ Go HTTP  │  │  SSH Manager │ │
│  │ (内嵌)    │  │ :8080    │  │  (crypto/ssh)│ │
│  └──────────┘  └────┬─────┘  └──────┬──────┘ │
│                     │               │         │
│              ┌──────┴──────┐        │         │
│              │   SQLite    │        │         │
│              │ (WAL mode)  │        │         │
│              └─────────────┘        │         │
│              ┌─────────────┐        │         │
│              │ 本地 Xray    │        │         │
│              │ config.json │        │         │
│              └─────────────┘        │         │
└──────────────────────┼──────────────┼─────────┘
                       │              │
              本地 Xray-core    远程 VPS 节点
              :443 / :10085    (SSH 连接)
                                    │
                              ┌─────┴──────┐
                              │  Xray-core  │
                              │  :443 入站   │
                              └────────────┘
```

**运行模式：**
- **单机模式：** 面板启动自动检测本机 Xray，本地操作，零配置
- **多节点模式：** 本机 + SSH 远程管理多台 VPS，可随时从单机升级

**技术选型：**
- 数据库：`modernc.org/sqlite`（纯 Go SQLite，无 CGO，零依赖）
- SSH：`golang.org/x/crypto/ssh`
- 路由：`gin-gonic/gin`
- 前端：React 18 + Vite + MUI v6 (MD3) + zustand
- 定时任务：`robfig/cron/v3`

## 数据库设计

```sql
-- 管理员（单用户，bcrypt hash）
CREATE TABLE admin (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    username   TEXT NOT NULL DEFAULT 'admin',
    password   TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 节点
CREATE TABLE nodes (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    host        TEXT NOT NULL,
    ssh_port    INTEGER NOT NULL DEFAULT 22,
    ssh_user    TEXT NOT NULL DEFAULT 'root',
    ssh_key     TEXT NOT NULL DEFAULT '',
    region      TEXT NOT NULL DEFAULT '',
    is_active   INTEGER NOT NULL DEFAULT 1,
    last_seen_at TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 入站规则
CREATE TABLE inbounds (
    id          TEXT PRIMARY KEY,
    node_id     TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    tag         TEXT NOT NULL,
    protocol    TEXT NOT NULL CHECK (protocol IN ('vless','vmess','trojan','shadowsocks')),
    port        INTEGER NOT NULL,
    listen      TEXT NOT NULL DEFAULT '0.0.0.0',
    settings    TEXT NOT NULL DEFAULT '{}',
    stream      TEXT NOT NULL DEFAULT '{}',
    sniffing    INTEGER NOT NULL DEFAULT 1,
    is_active   INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 客户端（全局，不绑定单个入站）
CREATE TABLE clients (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL DEFAULT '',
    uuid        TEXT NOT NULL UNIQUE,
    password    TEXT NOT NULL DEFAULT '',
    flow        TEXT NOT NULL DEFAULT 'xtls-rprx-vision',
    total_limit INTEGER NOT NULL DEFAULT 0,
    expiry_at   TEXT,
    is_active   INTEGER NOT NULL DEFAULT 1,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 客户端 ↔ 入站 多对多
CREATE TABLE client_inbounds (
    client_id  TEXT NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    inbound_id TEXT NOT NULL REFERENCES inbounds(id) ON DELETE CASCADE,
    is_visible INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (client_id, inbound_id)
);

-- 流量日志（按小时聚合）
CREATE TABLE traffic_hourly (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    client_id  TEXT NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    inbound_id TEXT NOT NULL REFERENCES inbounds(id) ON DELETE CASCADE,
    up_bytes   INTEGER NOT NULL DEFAULT 0,
    down_bytes INTEGER NOT NULL DEFAULT 0,
    hour       TEXT NOT NULL,
    UNIQUE(client_id, inbound_id, hour)
);

-- 操作日志
CREATE TABLE audit_logs (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    action     TEXT NOT NULL,
    target     TEXT NOT NULL DEFAULT '',
    detail     TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

## API 设计

### 认证
```
POST   /api/auth/login        # 登录（首次自动初始化管理员）
GET    /api/auth/setup        # 检查是否需要初始化
```

### 节点管理
```
GET    /api/nodes              # 节点列表
POST   /api/nodes              # 添加节点（支持自动安装 Xray）
PUT    /api/nodes/:id          # 编辑节点
DELETE /api/nodes/:id          # 删除节点
POST   /api/nodes/:id/test     # 测试 SSH 连接
GET    /api/nodes/:id/status   # 节点状态（CPU/内存/Xray 版本）
```

### 入站规则
```
GET    /api/inbounds            # 所有入站列表（可按 node_id 筛选）
POST   /api/inbounds            # 创建入站（支持选择多节点批量部署）
PUT    /api/inbounds/:id        # 编辑入站
DELETE /api/inbounds/:id        # 删除入站
POST   /api/inbounds/:id/deploy # 部署到节点
```

### 客户端（全局）
```
GET    /api/clients                   # 客户端列表
POST   /api/clients                   # 创建客户端（指定部署节点 + 可见性）
PUT    /api/clients/:id               # 编辑客户端
DELETE /api/clients/:id               # 删除客户端
POST   /api/clients/:id/reset         # 重置 UUID/密码
PUT    /api/clients/:id/inbounds      # 更新客户端关联的入站和可见性
GET    /api/clients/:id/subscription  # 获取客户端订阅配置
```

### 流量 & 统计
```
GET    /api/traffic/overview           # 总览
GET    /api/traffic/clients/:id        # 某客户端流量图表
GET    /api/traffic/nodes/:id          # 某节点流量
```

### 订阅
```
GET    /api/sub/:token                 # 通用订阅链接（v2ray/clash 格式）
```

### 系统
```
GET    /api/system/info                # 面板版本/运行时间
PUT    /api/system/password            # 修改管理员密码
POST   /api/system/backup              # 导出 SQLite + 配置
POST   /api/system/restore             # 导入恢复
```

## React 页面 & UI

**UI 风格：** Material Design 3 (MUI v6)，暗色主题，响应式适配移动端

### 页面结构（7 页）

```
/login                    登录页（首次启动引导设置密码）
/                         仪表盘（节点状态 + 流量趋势）
/nodes                    节点列表
/nodes/:id                节点详情（入站列表 + 运行状态）
/clients                  客户端管理
/traffic                  流量统计
/settings                 系统设置
```

### 各页面要点

**登录页：** MD3 居中卡片，暗色渐变背景，首次启动引导设置密码

**仪表盘：** 顶部三卡片（节点数/活跃客户端/今日流量），下方节点状态网格 + 近 24h 流量趋势图（MUI X Charts）

**节点列表：** 卡片网格 + 状态指示灯（绿/黄/红），支持按地区分组，显示入站数和客户端数

**节点详情：** 左侧节点信息 + 运行指标，右侧入站卡片列表，每个入站显示协议标签/端口/客户端数

**客户端管理：** 表格展示 备注/uuid/流量用量/到期时间/关联节点数，展开行显示各节点可见性开关，快捷复制订阅链接 + QR 码

**流量统计：** 按节点/客户端筛选，折线图展示流量趋势

**系统设置：** 修改密码、数据备份/恢复、面板版本信息

### 前端技术

- 组件库：MUI v6 + @mui/icons-material + MUI X Charts
- 状态管理：zustand
- 路由：react-router v6（lazy loading）
- HTTP：axios（拦截器处理 JWT）
- QR 码：qrcode.react
- 性能优化：路由级 lazy loading、图表组件按需加载、虚拟列表（大量客户端时）

## 核心流程

### 首次启动

```
启动面板 → 打开浏览器 → 选择模式（单机/多节点）
    ├── 单机：自动检测本机 Xray → 直接进入仪表盘
    └── 多节点：进入仪表盘 → 引导添加远程节点
```

### 三步上线

```
1. 添加节点（1 分钟）
   输入 IP + root 密码 → 自动安装 Xray + 初始化配置 → 返回就绪

2. 创建入站（30 秒）
   选择场景（推荐 VLESS+Reality）→ 勾选目标节点 → 一键创建并部署

3. 复制订阅（5 秒）
   创建客户端 → 选择节点可见性 → 复制订阅链接 / 扫 QR 码
```

### 智能默认值

| 操作 | 自动完成 |
|---|---|
| 安装 Xray | 添加节点时检测并自动安装 |
| 生成密钥 | 创建入站自动执行 xray x25519 |
| Reality dest | 预设 microsoft.com / discord.com |
| 配置 reload | 变更自动推送 + reload |
| 订阅链接 | 创建客户端自动生成，一键复制/QR |

### 客户端跨节点

- 客户端是全局的，通过 `client_inbounds` 关联到多个入站/节点
- 每个关联可独立设置 `is_visible`，控制是否在订阅中显示
- 订阅输出每个可见节点作为独立代理条目
- 不同节点可以使用不同协议/端口（如本机 VLESS:443，新加坡 VMess+WS:10001）

## Xray 配置管理

### 配置模板

| 模板 | 配置 |
|---|---|
| VLESS + Reality（推荐） | vless + reality + xtls-rprx-vision，端口 443 |
| VLESS + WebSocket + TLS | 端口 443，path=/ws，搭配 caddy/nginx |
| VMess + WebSocket + CDN | 端口 10001，无 TLS，适合套 CDN |
| Trojan + TCP + TLS | 端口 443，fallback 伪装站点 |

### 部署流程

1. 管理员在面板创建入站 → SQLite 存储
2. 面板读取模板 + 节点信息 → 渲染完整 JSON + 生成密钥
3. SSH SCP config.json → 远程 `/usr/local/etc/xray/config.json`
4. SSH exec: `systemctl reload xray`
5. 返回部署结果

### 流量采集

- 本地节点：直接连接 `127.0.0.1:10085` Stats API
- 远程节点：SSH 端口转发（`ssh -L 10085:127.0.0.1:10085`）后连接
- 采集频率：60 秒
- 超限处理：total_limit > 0 且达到上限时自动禁用客户端

## 安全

- 密码：bcrypt cost=12
- JWT：HS256，72h 过期
- SQLite 文件：0600，仅面板进程可读写
- SSH 私钥：AES-256-GCM 加密存储，密钥由管理员密码派生
- Xray 私钥：文件 600，owner root
- 仅监听本地：Xray Stats API 127.0.0.1，远程通过 SSH 转发
- 登录保护：5 次失败锁定 15 分钟

## 部署

### 单二进制

```bash
curl -sL <release-url>/borderx-panel-linux-amd64 -o /usr/local/bin/borderx-panel
chmod +x /usr/local/bin/borderx-panel
./borderx-panel
# 浏览器打开 http://<ip>:8080，设置管理员密码
```

### Docker

```bash
docker run -d --name borderx \
  -v /etc/xray:/etc/xray \
  -v borderx-data:/data \
  -p 8080:8080 \
  borderx/panel
```

### 打包

Go 编译内嵌 React 构建产物 + SQLite，最终 ~25MB 二进制。`go build -tags "fts5"`。

## 目录结构

```
BorderX/
├── server/
│   ├── cmd/panel/main.go
│   ├── internal/
│   │   ├── config/config.go
│   │   ├── model/models.go
│   │   ├── store/sqlite.go
│   │   ├── auth/
│   │   │   ├── jwt.go
│   │   │   ├── middleware.go
│   │   │   └── handler.go
│   │   ├── node/
│   │   │   ├── manager.go
│   │   │   ├── deploy.go
│   │   │   └── handler.go
│   │   ├── inbound/
│   │   │   ├── template.go
│   │   │   └── handler.go
│   │   ├── client/
│   │   │   └── handler.go
│   │   ├── xray/
│   │   │   ├── config.go
│   │   │   ├── stats.go
│   │   │   └── key.go
│   │   ├── traffic/
│   │   │   └── collector.go
│   │   └── sub/
│   │       └── handler.go
│   ├── migrations/
│   │   └── 001_init.sql
│   ├── go.mod
│   └── go.sum
├── web/
│   └── src/
│       ├── pages/
│       │   ├── Login.tsx
│       │   ├── Dashboard.tsx
│       │   ├── Nodes.tsx
│       │   ├── NodeDetail.tsx
│       │   ├── Clients.tsx
│       │   ├── Traffic.tsx
│       │   └── Settings.tsx
│       └── components/
├── deploy/
│   ├── install.sh
│   └── Dockerfile
└── docs/
```

## 开发分阶段

| Phase | 内容 | 预估 |
|---|---|---|
| 1. 核心骨架 | Go 项目 + SQLite + JWT + React MD3 基础页面 + 首次设置向导 | 1 周 |
| 2. 单机模式 | 本地 Xray 配置读写 + 入站/客户端管理 + 流量采集 + 订阅链接 | 1.5 周 |
| 3. 多节点模式 | SSH 管理 + 远程部署 + 节点健康检查 + 自动安装 Xray | 1 周 |
| 4. 打磨 | 流量图表 + 备份恢复 + 一键安装脚本 + 暗色主题完善 | 1 周 |

## 对比现有设计的变更

| | 现有设计 (v1) | 新设计 (v2) |
|---|---|---|
| 定位 | VPN SaaS 系统 | 运维管理面板 |
| 用户模型 | 多用户 + 多管理员 | 单管理员 |
| 数据库 | PostgreSQL | SQLite |
| 表数量 | 9 张 | 6 张 |
| HTTP API | 30+ 端点 | 25 端点 |
| 页面 | 18 页 | 7 页 |
| 前端 UI | Tailwind 手写 | MUI v6 MD3 |
| 组件库 | 无 | shadcn/ui → MUI v6 |
| 主题 | 亮色 | 暗色（MD3 Dark） |
| 节点管理 | 预留扩展 | SSH 核心功能 |
| 客户端模型 | 绑定入站 | 全局跨节点（多对多） |
| 订阅可见性 | 无控制 | 按节点开关 |
| 安装复杂度 | 依赖 PostgreSQL | 单二进制 ~25MB |
| 支付系统 | 支付宝 | 砍掉 |
| 开发周期 | 6 周 | 4.5 周 |
