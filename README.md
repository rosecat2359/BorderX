# BorderX

基于 Xray-core 的轻量级 VPN 运维管理面板。Go + React 全栈，单二进制部署，支持 Windows / Linux。

> **免责声明**：本项目仅供学习研究使用。使用者需遵守当地法律法规。

## 特性

| 模块 | 功能 |
|---|---|
| 入站管理 | VLESS Reality / VMess WS / Trojan TLS，一键创建并部署到节点 |
| 客户端管理 | 全局客户端，跨节点使用，流量限制 + 到期时间 + UUID 重置 |
| 节点管理 | 本机 / SSH 远程节点，连接测试 + 自动地区检测 + 状态监控 |
| 流量统计 | 实时仪表盘（5秒刷新），按客户端/节点流量图表，超限自动禁用 |
| 订阅链接 | 自动生成 v2ray 格式订阅，按节点控制可见性，一键复制 / QR 码 |
| 系统运维 | 单管理员、数据备份/恢复、交互式安装/卸载、首次启动自动创建本地节点 |
| 跨平台 | Windows / Linux amd64/arm64，单二进制部署，暗色主题 Web 面板 |

## 技术栈

| 层 | 技术 |
|---|---|
| 后端 | Go 1.22+, Gin, SQLite (modernc.org/sqlite), Xray-core |
| 前端 | React 18, TypeScript, MUI (Material Design 3), Vite |
| 部署 | 单二进制（Go embed 前端），systemd / Windows Service / Docker |

## 系统要求

- Linux: Debian 11+ / Ubuntu 20.04+, Xray-core（安装脚本自动安装）
- Windows: Windows 10+ / Windows Server 2016+, Xray-core（手动安装）
- 构建: Go 1.22+, Node.js 20+

## 快速开始

### Linux 一键安装

```bash
curl -sL https://raw.githubusercontent.com/rosecat2359/BorderX/main/deploy/install.sh | bash
```

脚本交互式引导：安装目录、数据目录、面板端口、是否安装 Xray-core。首次启动自动创建本地节点。

安装后访问 `http://<IP>:8080`，首次启动需设置管理员密码。

### Windows 安装

```powershell
irm https://raw.githubusercontent.com/rosecat2359/BorderX/main/deploy/install.ps1 | iex
```

### Docker

```bash
docker run -d --name borderx \
  -v /etc/xray:/etc/xray \
  -v borderx-data:/data \
  -p 8080:8080 \
  borderx/panel
```

安装后访问 `http://<IP>:8080`，首次启动需设置管理员密码。

## 手动构建

```bash
# 1. 构建前端
cd web && npm install && npm run build

# 2. 构建后端（前端产物自动内嵌）
cd ../server && go build -o borderx-panel ./cmd/panel/

# 3. 跨平台构建
GOOS=linux GOARCH=amd64 go build -o borderx-panel ./cmd/panel/
GOOS=windows GOARCH=amd64 go build -o borderx-panel.exe ./cmd/panel/
GOOS=linux GOARCH=arm64 go build -o borderx-panel ./cmd/panel/
```

## 配置

v2 支持无配置文件运行，所有参数有合理默认值。可选配置文件 `/etc/borderx/config.yml`：

```yaml
server:
  port: 8080
  host: "0.0.0.0"
jwt:
  secret: "<随机生成>"
  expire_hour: 72
xray:
  config_path: /usr/local/etc/xray/config.json
  stats_port: 10085
  binary_path: /usr/local/bin/xray
data:
  dir: ./data  # SQLite 数据库存储位置
```

## 项目结构

```
BorderX/
├── server/
│   ├── cmd/panel/main.go
│   ├── internal/
│   │   ├── auth/           # JWT + 单管理员登录
│   │   ├── client/         # 客户端 CRUD + 多入站关联
│   │   ├── config/         # YAML 配置加载
│   │   ├── inbound/        # 入站规则 + 模板引擎
│   │   ├── model/          # 数据模型
│   │   ├── node/           # SSH 节点管理 + CRUD
│   │   ├── store/          # SQLite 连接 + 迁移
│   │   ├── sub/            # 订阅链接生成
│   │   ├── traffic/        # 流量采集 + 定时任务
│   │   └── xray/           # Xray 配置读写 + 平台适配
│   └── web/embed.go        # 内嵌 React 前端
├── web/
│   └── src/
│       ├── pages/          # 7 个页面（仪表盘/节点/客户端/流量/设置）
│       ├── components/     # Layout (Navigation Rail)
│       ├── store/auth.ts   # Zustand 认证
│       ├── api.ts          # Axios API 封装
│       └── theme.ts        # MUI MD3 暗色主题
└── deploy/
    ├── install.sh          # Linux 一键安装
    ├── install.ps1         # Windows 一键安装
    └── Dockerfile
```

## API

### 公开（无需认证）

```
GET   /api/auth/setup        # 检查是否需要初始化
POST  /api/auth/setup        # 首次设置管理员密码
POST  /api/auth/login        # 管理员登录
GET   /api/sub?client=xxx    # 订阅链接（base64 编码）
```

### 认证后（JWT Bearer）

```
# 节点
GET    /api/nodes               列表
POST   /api/nodes               添加
PUT    /api/nodes/:id           编辑
DELETE /api/nodes/:id           删除
POST   /api/nodes/:id/test      SSH 连接测试
GET    /api/nodes/:id/status    运行状态

# 入站
GET    /api/inbounds             列表（可按 node_id 筛选）
POST   /api/inbounds             创建（支持批量部署到多节点）
PUT    /api/inbounds/:id         编辑
DELETE /api/inbounds/:id          删除
POST   /api/inbounds/:id/deploy  部署到节点
GET    /api/inbounds/templates   内置模板列表

# 客户端
GET    /api/clients                  列表
POST   /api/clients                  创建（指定入站 + 可见性）
PUT    /api/clients/:id               编辑
DELETE /api/clients/:id               删除
POST   /api/clients/:id/reset        重置 UUID
PUT    /api/clients/:id/inbounds     更新入站关联 + 可见性

# 流量
GET    /api/traffic/overview     总览（节点数/客户端数/今日流量）
GET    /api/traffic/clients/:id  客户端流量趋势（7天）

# 系统
GET    /api/system/info          版本 + OS + 节点/客户端/入站数量 + 数据库大小
PUT    /api/system/password      修改管理员密码
POST   /api/system/backup        导出 SQLite 数据库备份
POST   /api/system/restore       上传备份文件恢复数据库
```

## 管理命令

```bash
# 查看服务状态
systemctl status borderx-panel

# 查看日志
journalctl -u borderx-panel -f

# 重启
systemctl restart borderx-panel
```

## 卸载

### Linux
```bash
curl -sL https://raw.githubusercontent.com/rosecat2359/BorderX/main/deploy/uninstall.sh | bash
```

### Windows (PowerShell 管理员)
```powershell
irm https://raw.githubusercontent.com/rosecat2359/BorderX/main/deploy/uninstall.ps1 | iex
```

## License

MIT
