# BorderX

基于 Xray-core 的多用户 VPN SaaS 管理系统。Go + React 全栈，单二进制部署。

> **免责声明**：本项目仅供学习研究使用。使用者需遵守当地法律法规。

## 特性

| 模块 | 功能 |
|------|------|
| 用户端 | 注册/登录、邮箱验证、密码重置、浏览套餐、下单购买、VPN 账号管理、订阅链接 |
| 管理端 | 仪表盘、用户管理、套餐 CRUD、订单管理、流量统计（排行/趋势）、审计日志 |
| VPN | VLESS Reality / VMess WS / Trojan TLS，自动配置 + 流量采集 + 超限禁用 |
| 支付 | 支付宝当面付（扫码支付） |
| 安全 | JWT 认证、bcrypt 密码、RBAC 权限（super/operator/viewer） |

## 技术栈

| 层 | 技术 |
|---|---|
| 后端 | Go 1.22+, Gin, PostgreSQL, Xray-core |
| 前端 | React 18, TypeScript, Tailwind CSS, Vite |
| 部署 | systemd + Nginx，单二进制（Go 内嵌 React 前端） |

## 系统要求

- Debian 11+ / Ubuntu 20.04+
- PostgreSQL 12+
- Xray-core（部署脚本自动安装）
- 构建需要 Go 1.22+ 和 Node.js 20+

## 快速开始

### 一键安装

```bash
curl -sL https://raw.githubusercontent.com/rosecat2359/BorderX/main/deploy/install.sh | bash
```

脚本自动完成：系统依赖 → PostgreSQL → 下载二进制 → 配置 → systemd 服务 → Nginx 反代 → 启动。

安装后访问 `http://<服务器IP>`。默认管理员：`admin` / `admin123`（首次登录后务必修改）。

### 手动构建

```bash
# 1. 构建前端
cd web
npm install
npm run build

# 2. 复制前端产物到 server（Go embed 需要）
cp -r dist ../server/web/dist

# 3. 构建后端
cd ../server
go build -o borderx-panel ./cmd/panel/

# 4. 跨平台构建
GOOS=linux GOARCH=amd64 go build -o borderx-panel ./cmd/panel/
GOOS=windows GOARCH=amd64 go build -o borderx-panel.exe ./cmd/panel/
```

### 配置文件

`/etc/borderx/config.yml`：

```yaml
server:
  port: 8080
  mode: release              # debug 模式输出更多日志
database:
  host: localhost
  port: 5432
  user: borderx
  password: <数据库密码>
  dbname: borderx
jwt:
  secret: <随机密钥>
  expire_hour: 24
xray:
  config_path: /usr/local/etc/xray/config.json
  stats_port: 10085
  binary_path: /usr/local/bin/xray
smtp:                        # 可选，不填跳过邮件功能
  host: ""
  port: 587
  username: ""
  password: ""
  from: ""
alipay:                      # 可选，不填则下单即生效
  app_id: ""
  private_key: ""            # 应用私钥文件路径（PEM 格式）
  alipay_pub_key: ""         # 支付宝公钥文件路径（PEM 格式）
  notify_domain: ""          # 回调域名，如 https://example.com
```

## 项目结构

```
BorderX/
├── server/                     # Go API
│   ├── cmd/panel/main.go       # 入口，路由组装
│   ├── internal/
│   │   ├── api/                # 用户端：下单、账号查询
│   │   ├── admin/              # 管理端：CRUD + 仪表盘 + 审计
│   │   ├── auth/               # JWT 生成/校验 + 中间件 + 注册/登录
│   │   ├── config/             # YAML 配置加载
│   │   ├── mail/               # SMTP 邮件发送
│   │   ├── model/              # 数据库模型 struct
│   │   ├── payment/            # 支付宝当面付 + 回调处理
│   │   ├── store/              # DB 连接 + SQL 迁移
│   │   │   └── migrations/     # 建表 + 种子数据
│   │   ├── sub/                # 订阅链接生成（v2ray 格式）
│   │   ├── traffic/            # 流量采集 + 归档 + 超限检查
│   │   └── xray/               # Xray 配置读写 + 统计 + 密钥
│   └── web/embed.go            # 内嵌 React 前端
├── web/                        # React SPA
│   └── src/
│       ├── pages/              # 13 个页面组件
│       │   └── admin/          # 管理后台页面
│       ├── store/auth.ts       # Zustand 认证状态
│       ├── api.ts              # Axios API 封装
│       └── App.tsx             # 路由配置
├── deploy/
│   ├── install.sh              # 一键安装脚本
│   ├── panel.service           # systemd 服务文件
│   ├── nginx.conf              # Nginx 反代配置
│   └── config.yml              # 配置模板
├── build.sh                    # Linux 构建脚本
├── build.bat                   # Windows 构建脚本
└── README.md
```

## API 路由

### 公开（无需认证）

```
POST  /api/auth/register             注册
POST  /api/auth/login                登录
POST  /api/auth/admin-login          管理员登录
POST  /api/auth/forgot-password      忘记密码
POST  /api/auth/reset-password       重置密码
GET   /api/auth/verify-email         邮箱验证
GET   /api/sub?token=xxx             订阅链接（base64 编码）
POST  /api/payment/alipay/notify     支付宝异步回调
```

### 用户（需要 JWT）

```
GET   /api/plans                     套餐列表
GET   /api/me                        个人信息
POST  /api/send-verify-email         发送验证邮件
POST  /api/orders                    下单购买
GET   /api/orders                    我的订单
GET   /api/accounts                  我的 VPN 账号
```

### 管理（需要 JWT + admin role）

```
GET   /api/admin/dashboard           仪表盘统计
GET   /api/admin/users               用户列表（分页+搜索）
GET   /api/admin/users/:id           用户详情
POST  /api/admin/users/:id/disable   禁用用户
POST  /api/admin/users/:id/enable    启用用户
GET   /api/admin/plans               套餐列表
POST  /api/admin/plans               创建套餐
PUT   /api/admin/plans/:id           更新套餐
DELETE /api/admin/plans/:id           删除套餐
GET   /api/admin/orders              订单列表（分页）
POST  /api/admin/orders/:id/cancel   取消订单
GET   /api/admin/traffic/summary     30 天流量总览
GET   /api/admin/traffic/accounts    账号流量排行（1/7/30 天）
GET   /api/admin/traffic/timeline    24 小时流量趋势
GET   /api/admin/audit-logs          操作日志（分页）
```

## 定时任务（Go 内置 cron）

| 频率 | 任务 |
|------|------|
| 每 60 秒 | Xray 流量采集 + 超限自动禁用 |
| 每小时 | 流量明细归档到小时表、清理 24 小时前明细 |
| 每天 03:00 | 过期账号自动设为 expired |
| 每天 04:00 | 清理 30 天前审计日志 |

## 管理命令

```bash
# 查看服务状态
systemctl status borderx-panel

# 查看实时日志
journalctl -u borderx-panel -f

# 重启
systemctl restart borderx-panel

# 查看 Nginx 日志
tail -f /var/log/nginx/access.log

# 重置管理员密码（如 bcrypt 哈希损坏）
cd /tmp && mkdir hashtool && cd hashtool && go mod init hashtool && go get golang.org/x/crypto@latest
cat > main.go << 'GOEOF'
package main
import ("fmt"; "golang.org/x/crypto/bcrypt")
func main() { h, _ := bcrypt.GenerateFromPassword([]byte("新密码"), 12); fmt.Println(string(h)) }
GOEOF
go run main.go
# 将输出的哈希写入数据库：
# echo '哈希值' > /tmp/passhash.txt
# su - postgres -c "psql -d borderx -c \"UPDATE admins SET password_hash='\$(cat /tmp/passhash.txt)' WHERE username='admin';\""
```

## 故障排查

| 问题 | 排查 |
|------|------|
| 502 Bad Gateway | Panel 未运行 `systemctl status borderx-panel` |
| 密码错误 | 哈希可能损坏，用上方命令重置 |
| 迁移失败 | 数据库有残留表 `su - postgres -c "psql -c 'DROP DATABASE borderx; CREATE DATABASE borderx OWNER borderx;'"` |
| 页面 404 | 刷新后正常？是 SPA 路由，直接访问路径需 Panel 支持 |
| 安装脚本密码不匹配 | 重复运行保留旧密码，或手动同步 `/etc/borderx/config.yml` 与 DB |

## License

MIT
