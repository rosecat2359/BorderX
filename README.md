# BorderX

基于 Xray-core 的多用户 VPN SaaS 管理系统。Go + React 全栈，单二进制部署。

> **免责声明**：本项目仅供学习研究使用。使用者需遵守当地法律法规。

## 特性

| 模块 | 功能 |
|------|------|
| 用户端 | 注册/登录、浏览套餐、下单购买、VPN 账号管理、订阅链接 |
| 管理端 | 仪表盘、用户管理、套餐 CRUD、订单管理、流量统计、审计日志 |
| VPN | VLESS Reality / VMess WS / Trojan TLS，自动配置 + 流量采集 + 超限禁用 |
| 支付 | 支付宝当面付（扫码支付） |
| 安全 | JWT 认证、bcrypt 密码、邮箱验证、RBAC 权限 |

## 技术栈

| 层 | 技术 |
|---|---|
| 后端 | Go 1.22+, Gin, PostgreSQL, Xray-core |
| 前端 | React 18, TypeScript, Tailwind CSS, Vite |
| 部署 | systemd + Nginx，单二进制（内嵌前端） |

## 快速开始

### 一键安装（Debian/Ubuntu）

```bash
curl -sL https://raw.githubusercontent.com/rosecat2359/BorderX/main/deploy/install.sh | bash
```

安装后访问 `http://<服务器IP>` 即可。默认管理员：`admin` / `admin123`。

### 手动构建

```bash
# 构建前端
cd web && npm install && npm run build

# 复制前端到 server
cp -r dist ../server/web/dist

# 构建后端
cd ../server
go build -o borderx-panel ./cmd/panel/

# 跨平台构建
GOOS=linux GOARCH=amd64 go build -o borderx-panel ./cmd/panel/
```

### 配置文件

`/etc/borderx/config.yml`:

```yaml
server:
  port: 8080
  mode: release
database:
  host: localhost
  port: 5432
  user: borderx
  password: <your-password>
  dbname: borderx
jwt:
  secret: <random-secret>
  expire_hour: 24
xray:
  config_path: /usr/local/etc/xray/config.json
  stats_port: 10085
  binary_path: /usr/local/bin/xray
smtp:
  host: ""
  port: 587
  username: ""
  password: ""
  from: ""
alipay:
  app_id: ""
  private_key: ""
  alipay_pub_key: ""
  notify_domain: ""
```

## 项目结构

```
BorderX/
├── server/                    # Go API
│   ├── cmd/panel/main.go      # 入口
│   ├── internal/
│   │   ├── api/               # 用户端 handler
│   │   ├── admin/             # 管理端 handler
│   │   ├── auth/              # JWT + 中间件
│   │   ├── config/            # 配置加载
│   │   ├── mail/              # SMTP 邮件
│   │   ├── model/             # 数据模型
│   │   ├── payment/           # 支付宝
│   │   ├── store/             # DB 连接 + 迁移
│   │   ├── sub/               # 订阅链接
│   │   ├── traffic/           # 流量采集
│   │   └── xray/              # Xray 配置 + 统计
│   ├── web/dist/              # React 构建产物（内嵌）
│   ├── go.mod
│   └── go.sum
├── web/                       # React SPA
│   └── src/
│       ├── pages/             # 页面组件
│       ├── store/             # Zustand 状态
│       ├── api.ts             # API 封装
│       └── App.tsx            # 路由
├── deploy/
│   ├── install.sh             # 一键安装脚本
│   ├── panel.service          # systemd 服务
│   ├── nginx.conf             # Nginx 反代配置
│   └── config.yml             # 配置模板
├── build.sh / build.bat       # 构建脚本
└── docs/
    └── superpowers/
        ├── specs/             # 设计规格
        └── plans/             # 实现计划
```

## API 路由

```
# 公开
POST  /api/auth/register          用户注册
POST  /api/auth/login             用户登录
POST  /api/auth/admin-login       管理员登录
POST  /api/auth/forgot-password   忘记密码
POST  /api/auth/reset-password    重置密码
GET   /api/auth/verify-email      邮箱验证
GET   /api/sub?token=xxx          订阅链接
POST  /api/payment/alipay/notify  支付宝回调

# 用户 (JWT)
GET   /api/plans                  套餐列表
GET   /api/me                     个人信息
POST  /api/send-verify-email      发送验证邮件
POST  /api/orders                 下单
GET   /api/orders                 我的订单
GET   /api/accounts               我的 VPN 账号

# 管理 (JWT + admin role)
GET   /api/admin/dashboard        仪表盘
GET   /api/admin/users            用户管理
GET   /api/admin/plans            套餐管理
GET   /api/admin/orders           订单管理
GET   /api/admin/traffic/summary  流量总览
GET   /api/admin/traffic/accounts 账号流量
GET   /api/admin/traffic/timeline 24h 趋势
GET   /api/admin/audit-logs       审计日志
```

## 定时任务

| 频率 | 任务 |
|------|------|
| 每 60 秒 | Xray 流量采集 + 超限检测 |
| 每小时 | 流量归档 (logs → hourly) |
| 每天 03:00 | 过期账号自动禁用 |
| 每天 04:00 | 清理 30 天前审计日志 |

## 管理

```bash
# 查看状态
systemctl status borderx-panel

# 查看日志
journalctl -u borderx-panel -f

# 重启
systemctl restart borderx-panel
```

## License

MIT
