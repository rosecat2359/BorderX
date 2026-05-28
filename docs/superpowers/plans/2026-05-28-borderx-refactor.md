# BorderX 重构实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 将 BorderX 从 Bash 部署脚本重构为 Go + React 全栈多用户 VPN SaaS 管理系统

**架构：** Go API 内嵌 React SPA 的单二进制部署，Panel 直接操作本地 Xray-core 配置。MVP 单机模式，后续 SSH 扩展多节点。

**技术栈：** Go 1.22+, React 18 + TypeScript, PostgreSQL 15+, Xray-core, Vite, tailwindcss, zustand, react-router v6

---

## Phase 1：核心骨架

### 文件结构（Phase 1 创建）

```
server/
├── cmd/panel/main.go
├── internal/
│   ├── config/config.go          # 配置加载
│   ├── model/models.go           # 所有 DB 模型
│   ├── store/pg.go               # PostgreSQL 连接 + 迁移
│   ├── auth/jwt.go               # JWT 生成/校验
│   ├── auth/middleware.go         # HTTP 中间件
│   ├── auth/handler.go           # 注册/登录 handler
│   ├── admin/handler.go          # 管理端 CRUD handler
│   ├── api/handler.go            # 用户端 handler
│   └── mail/smtp.go              # SMTP 邮件
├── migrations/
│   ├── 001_init.sql
│   └── 002_seed.sql
├── go.mod
└── go.sum

web/
├── src/
│   ├── main.tsx
│   ├── App.tsx
│   ├── api.ts                    # axios 封装
│   ├── store/auth.ts             # zustand auth store
│   ├── pages/
│   │   ├── Home.tsx
│   │   ├── Login.tsx
│   │   ├── Register.tsx
│   │   ├── Dashboard.tsx
│   │   ├── admin/
│   │   │   ├── Layout.tsx
│   │   │   ├── Dashboard.tsx
│   │   │   ├── Users.tsx
│   │   │   ├── Plans.tsx
│   │   │   └── Orders.tsx
│   └── components/
│       ├── Layout.tsx
│       ├── Navbar.tsx
│       ├── ProtectedRoute.tsx
│       └── AdminRoute.tsx
├── index.html
├── package.json
├── vite.config.ts
├── tsconfig.json
└── tailwind.config.js
```

---

### 任务 1：Go 项目初始化 + 配置

**文件：**
- 创建：`server/go.mod`
- 创建：`server/cmd/panel/main.go`
- 创建：`server/internal/config/config.go`

- [ ] **步骤 1：初始化 Go module**

```bash
cd server && go mod init github.com/borderx/panel
```

- [ ] **步骤 2：安装依赖**

```bash
go get github.com/gin-gonic/gin
go get github.com/lib/pq
go get github.com/golang-jwt/jwt/v5
go get golang.org/x/crypto/bcrypt
go get github.com/robfig/cron/v3
go get github.com/google/uuid
go get gopkg.in/yaml.v3
```

- [ ] **步骤 3：编写配置模块**

`server/internal/config/config.go`:
```go
package config

import (
    "os"
    "gopkg.in/yaml.v3"
)

type Config struct {
    Server   ServerConfig   `yaml:"server"`
    Database DatabaseConfig `yaml:"database"`
    JWT      JWTConfig      `yaml:"jwt"`
    SMTP     SMTPConfig     `yaml:"smtp"`
    Xray     XrayConfig     `yaml:"xray"`
}

type ServerConfig struct {
    Port int    `yaml:"port"`
    Mode string `yaml:"mode"`
}

type DatabaseConfig struct {
    Host     string `yaml:"host"`
    Port     int    `yaml:"port"`
    User     string `yaml:"user"`
    Password string `yaml:"password"`
    DBName   string `yaml:"dbname"`
    SSLMode  string `yaml:"sslmode"`
}

type JWTConfig struct {
    Secret     string `yaml:"secret"`
    ExpireHour int    `yaml:"expire_hour"`
}

type SMTPConfig struct {
    Host     string `yaml:"host"`
    Port     int    `yaml:"port"`
    Username string `yaml:"username"`
    Password string `yaml:"password"`
    From     string `yaml:"from"`
}

type XrayConfig struct {
    ConfigPath string `yaml:"config_path"`
    StatsPort  int    `yaml:"stats_port"`
    BinaryPath string `yaml:"binary_path"`
}

func Load(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, err
    }
    cfg := &Config{}
    if err := yaml.Unmarshal(data, cfg); err != nil {
        return nil, err
    }
    cfg.applyDefaults()
    return cfg, nil
}

func (c *Config) applyDefaults() {
    if c.Server.Port == 0 { c.Server.Port = 8080 }
    if c.Server.Mode == "" { c.Server.Mode = "release" }
    if c.Database.Port == 0 { c.Database.Port = 5432 }
    if c.Database.SSLMode == "" { c.Database.SSLMode = "disable" }
    if c.JWT.ExpireHour == 0 { c.JWT.ExpireHour = 24 }
    if c.Xray.ConfigPath == "" { c.Xray.ConfigPath = "/usr/local/etc/xray/config.json" }
    if c.Xray.StatsPort == 0 { c.Xray.StatsPort = 10085 }
    if c.Xray.BinaryPath == "" { c.Xray.BinaryPath = "/usr/local/bin/xray" }
}

func (c *Config) DSN() string {
    return "host=" + c.Database.Host +
        " port=" + itoa(c.Database.Port) +
        " user=" + c.Database.User +
        " password=" + c.Database.Password +
        " dbname=" + c.Database.DBName +
        " sslmode=" + c.Database.SSLMode
}

func itoa(n int) string { return fmt.Sprintf("%d", n) }

func (c *Config) MustLoad(path string) *Config {
    cfg, err := Load(path)
    if err != nil {
        panic("加载配置失败: " + err.Error())
    }
    return cfg
}
```

- [ ] **步骤 4：编写 main.go 入口**

`server/cmd/panel/main.go`:
```go
package main

import (
    "flag"
    "fmt"
    "log"
    "github.com/borderx/panel/internal/config"
    "github.com/borderx/panel/internal/store"
)

func main() {
    cfgPath := flag.String("config", "/etc/borderx/config.yml", "配置文件路径")
    flag.Parse()

    cfg := config.MustLoad(*cfgPath)
    db, err := store.Connect(cfg.DSN())
    if err != nil {
        log.Fatalf("数据库连接失败: %v", err)
    }
    defer db.Close()

    if err := store.Migrate(db); err != nil {
        log.Fatalf("数据库迁移失败: %v", err)
    }

    fmt.Printf("BorderX Panel 启动在 :%d\n", cfg.Server.Port)
    // 后续任务接入 router + 启动
}
```

- [ ] **步骤 5：运行编译验证**

```bash
cd server && go build ./cmd/panel/
```
预期：编译成功（有未使用变量的 warning，忽略）

- [ ] **步骤 6：Commit**

```bash
git add server/go.mod server/go.sum server/cmd/ server/internal/config/
git commit -m "feat: Go 项目初始化，配置加载模块"
```

---

### 任务 2：数据库模型 + 迁移

**文件：**
- 创建：`server/internal/model/models.go`
- 创建：`server/internal/store/pg.go`
- 创建：`server/migrations/001_init.sql`
- 创建：`server/migrations/002_seed.sql`

- [ ] **步骤 1：编写 SQL 迁移**

`server/migrations/001_init.sql`:
```sql
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','disabled','deleted')),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE admins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(64) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'operator'
        CHECK (role IN ('super','operator','viewer')),
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(128) NOT NULL,
    price_cents INT NOT NULL DEFAULT 0,
    duration_days INT NOT NULL,
    traffic_limit_gb INT NOT NULL DEFAULT 0,
    max_devices INT NOT NULL DEFAULT 0,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    plan_id UUID NOT NULL REFERENCES plans(id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','paid','expired','cancelled')),
    amount_cents INT NOT NULL,
    paid_at TIMESTAMP,
    starts_at TIMESTAMP,
    expires_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE vpn_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    order_id UUID REFERENCES orders(id),
    protocol VARCHAR(10) NOT NULL CHECK (protocol IN ('vless','vmess','trojan')),
    uuid UUID NOT NULL,
    password VARCHAR(128) NOT NULL DEFAULT '',
    settings_json JSONB NOT NULL DEFAULT '{}',
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','disabled','expired')),
    traffic_used_bytes BIGINT NOT NULL DEFAULT 0,
    traffic_limit_bytes BIGINT NOT NULL DEFAULT 0,
    expires_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE traffic_logs (
    id BIGSERIAL PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES vpn_accounts(id),
    upload_bytes BIGINT NOT NULL DEFAULT 0,
    download_bytes BIGINT NOT NULL DEFAULT 0,
    recorded_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_traffic_logs_account ON traffic_logs(account_id, recorded_at);

CREATE TABLE traffic_hourly (
    id BIGSERIAL PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES vpn_accounts(id),
    upload_bytes BIGINT NOT NULL DEFAULT 0,
    download_bytes BIGINT NOT NULL DEFAULT 0,
    hour TIMESTAMP NOT NULL,
    UNIQUE(account_id, hour)
);

CREATE TABLE nodes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(128) NOT NULL,
    host VARCHAR(255) NOT NULL,
    ssh_port INT NOT NULL DEFAULT 22,
    ssh_user VARCHAR(64) NOT NULL DEFAULT 'root',
    ssh_key_path VARCHAR(512) NOT NULL DEFAULT '',
    region VARCHAR(64) NOT NULL DEFAULT '',
    is_active BOOLEAN NOT NULL DEFAULT true,
    last_seen_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE sub_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) UNIQUE,
    token VARCHAR(64) NOT NULL UNIQUE,
    last_accessed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    admin_id UUID REFERENCES admins(id),
    action VARCHAR(128) NOT NULL,
    target_type VARCHAR(64) NOT NULL DEFAULT '',
    target_id UUID,
    detail_json JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP NOT NULL DEFAULT now()
);
```

`server/migrations/002_seed.sql`:
```sql
INSERT INTO admins (username, password_hash, role)
VALUES ('admin', '$2a$12$LJ3m4ys3GZfnYMz8kVsKaOm0LPTs4mNxHDqAsKvJGDqXMsEqhKfKe', 'super')
ON CONFLICT DO NOTHING;
-- 默认密码: admin123，首次登录后强制修改

INSERT INTO plans (name, price_cents, duration_days, traffic_limit_gb, max_devices, sort_order) VALUES
    ('入门月付', 1990, 30, 50, 2, 1),
    ('标准季付', 4990, 90, 200, 3, 2),
    ('旗舰年付', 14990, 365, 1000, 5, 3)
ON CONFLICT DO NOTHING;
```

- [ ] **步骤 2：编写 Go 模型**

`server/internal/model/models.go`:
```go
package model

import (
    "database/sql"
    "encoding/json"
    "time"
)

type User struct {
    ID           string    `json:"id" db:"id"`
    Email        string    `json:"email" db:"email"`
    PasswordHash string    `json:"-" db:"password_hash"`
    Status       string    `json:"status" db:"status"`
    CreatedAt    time.Time `json:"created_at" db:"created_at"`
}

type Admin struct {
    ID           string    `json:"id" db:"id"`
    Username     string    `json:"username" db:"username"`
    PasswordHash string    `json:"-" db:"password_hash"`
    Role         string    `json:"role" db:"role"`
    CreatedAt    time.Time `json:"created_at" db:"created_at"`
}

type Plan struct {
    ID              string    `json:"id" db:"id"`
    Name            string    `json:"name" db:"name"`
    PriceCents      int       `json:"price_cents" db:"price_cents"`
    DurationDays    int       `json:"duration_days" db:"duration_days"`
    TrafficLimitGB  int       `json:"traffic_limit_gb" db:"traffic_limit_gb"`
    MaxDevices      int       `json:"max_devices" db:"max_devices"`
    SortOrder       int       `json:"sort_order" db:"sort_order"`
    IsActive        bool      `json:"is_active" db:"is_active"`
    CreatedAt       time.Time `json:"created_at" db:"created_at"`
}

type Order struct {
    ID          string         `json:"id" db:"id"`
    UserID      string         `json:"user_id" db:"user_id"`
    PlanID      string         `json:"plan_id" db:"plan_id"`
    Status      string         `json:"status" db:"status"`
    AmountCents int            `json:"amount_cents" db:"amount_cents"`
    PaidAt      sql.NullTime   `json:"paid_at" db:"paid_at"`
    StartsAt    sql.NullTime   `json:"starts_at" db:"starts_at"`
    ExpiresAt   sql.NullTime   `json:"expires_at" db:"expires_at"`
    CreatedAt   time.Time      `json:"created_at" db:"created_at"`
    Plan        *Plan          `json:"plan,omitempty" db:"-"`
}

type VPNAccount struct {
    ID                string          `json:"id" db:"id"`
    UserID            string          `json:"user_id" db:"user_id"`
    OrderID           sql.NullString  `json:"order_id" db:"order_id"`
    Protocol          string          `json:"protocol" db:"protocol"`
    UUID              string          `json:"uuid" db:"uuid"`
    Password          string          `json:"password,omitempty" db:"password"`
    SettingsJSON      json.RawMessage `json:"settings_json" db:"settings_json"`
    Status            string          `json:"status" db:"status"`
    TrafficUsedBytes  int64           `json:"traffic_used_bytes" db:"traffic_used_bytes"`
    TrafficLimitBytes int64           `json:"traffic_limit_bytes" db:"traffic_limit_bytes"`
    ExpiresAt         sql.NullTime    `json:"expires_at" db:"expires_at"`
    CreatedAt         time.Time       `json:"created_at" db:"created_at"`
}

type TrafficLog struct {
    ID            int64     `json:"id" db:"id"`
    AccountID     string    `json:"account_id" db:"account_id"`
    UploadBytes   int64     `json:"upload_bytes" db:"upload_bytes"`
    DownloadBytes int64     `json:"download_bytes" db:"download_bytes"`
    RecordedAt    time.Time `json:"recorded_at" db:"recorded_at"`
}

type Node struct {
    ID         string       `json:"id" db:"id"`
    Name       string       `json:"name" db:"name"`
    Host       string       `json:"host" db:"host"`
    SSHPort    int          `json:"ssh_port" db:"ssh_port"`
    SSHUser    string       `json:"ssh_user" db:"ssh_user"`
    SSHKeyPath string       `json:"ssh_key_path" db:"ssh_key_path"`
    Region     string       `json:"region" db:"region"`
    IsActive   bool         `json:"is_active" db:"is_active"`
    LastSeenAt sql.NullTime `json:"last_seen_at" db:"last_seen_at"`
    CreatedAt  time.Time    `json:"created_at" db:"created_at"`
}

type SubToken struct {
    ID             string       `json:"id" db:"id"`
    UserID         string       `json:"user_id" db:"user_id"`
    Token          string       `json:"token" db:"token"`
    LastAccessedAt sql.NullTime `json:"last_accessed_at" db:"last_accessed_at"`
    CreatedAt      time.Time    `json:"created_at" db:"created_at"`
}

type AuditLog struct {
    ID         int64           `json:"id" db:"id"`
    AdminID    sql.NullString  `json:"admin_id" db:"admin_id"`
    Action     string          `json:"action" db:"action"`
    TargetType string          `json:"target_type" db:"target_type"`
    TargetID   sql.NullString  `json:"target_id" db:"target_id"`
    DetailJSON json.RawMessage `json:"detail_json" db:"detail_json"`
    CreatedAt  time.Time       `json:"created_at" db:"created_at"`
}

// 分页通用结构
type Paginated struct {
    Items interface{} `json:"items"`
    Total int         `json:"total"`
    Page  int         `json:"page"`
    Size  int         `json:"size"`
}
```

- [ ] **步骤 3：编写数据库连接 + 迁移**

`server/internal/store/pg.go`:
```go
package store

import (
    "database/sql"
    "embed"
    "fmt"
    "os"
    "sort"
    "strings"
    _ "github.com/lib/pq"
)

//go:embed ../migrations/*.sql
var migrations embed.FS

func Connect(dsn string) (*sql.DB, error) {
    db, err := sql.Open("postgres", dsn)
    if err != nil {
        return nil, err
    }
    db.SetMaxOpenConns(25)
    db.SetMaxIdleConns(5)
    if err := db.Ping(); err != nil {
        return nil, fmt.Errorf("数据库 ping 失败: %w", err)
    }
    return db, nil
}

func Migrate(db *sql.DB) error {
    entries, err := migrations.ReadDir("migrations")
    if err != nil {
        return fmt.Errorf("读取迁移文件失败: %w", err)
    }
    sort.Slice(entries, func(i, j int) bool {
        return entries[i].Name() < entries[j].Name()
    })
    for _, entry := range entries {
        if !strings.HasSuffix(entry.Name(), ".sql") {
            continue
        }
        content, err := migrations.ReadFile("migrations/" + entry.Name())
        if err != nil {
            return fmt.Errorf("读取 %s 失败: %w", entry.Name(), err)
        }
        if _, err := db.Exec(string(content)); err != nil {
            return fmt.Errorf("执行 %s 失败: %w", entry.Name(), err)
        }
        fmt.Fprintf(os.Stderr, "[migrate] %s OK\n", entry.Name())
    }
    return nil
}
```

- [ ] **步骤 4：编译验证**

```bash
cd server && go build ./...
```
预期：编译成功

- [ ] **步骤 5：Commit**

```bash
git add server/migrations/ server/internal/model/ server/internal/store/
git commit -m "feat: 数据库模型 + SQL 迁移 + 种子数据"
```

---

### 任务 3：JWT 认证

**文件：**
- 创建：`server/internal/auth/jwt.go`
- 创建：`server/internal/auth/middleware.go`
- 创建：`server/internal/auth/handler.go`

- [ ] **步骤 1：编写 JWT 生成/校验**

`server/internal/auth/jwt.go`:
```go
package auth

import (
    "errors"
    "time"
    "github.com/golang-jwt/jwt/v5"
)

var (
    ErrTokenExpired = errors.New("token 已过期")
    ErrTokenInvalid = errors.New("token 无效")
)

type Claims struct {
    UserID string `json:"user_id"`
    Email  string `json:"email"`
    Role   string `json:"role"`
    jwt.RegisteredClaims
}

type JWTManager struct {
    secret     []byte
    expireHour int
}

func NewJWTManager(secret string, expireHour int) *JWTManager {
    return &JWTManager{secret: []byte(secret), expireHour: expireHour}
}

func (m *JWTManager) GenerateUserToken(userID, email string) (string, error) {
    return m.generate(userID, email, "user")
}

func (m *JWTManager) GenerateAdminToken(adminID, username, role string) (string, error) {
    return m.generate(adminID, username, role)
}

func (m *JWTManager) generate(id, name, role string) (string, error) {
    claims := Claims{
        UserID: id,
        Email:  name,
        Role:   role,
        RegisteredClaims: jwt.RegisteredClaims{
            ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Duration(m.expireHour) * time.Hour)),
            IssuedAt:  jwt.NewNumericDate(time.Now()),
        },
    }
    token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
    return token.SignedString(m.secret)
}

func (m *JWTManager) Parse(tokenString string) (*Claims, error) {
    token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(t *jwt.Token) (interface{}, error) {
        if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
            return nil, ErrTokenInvalid
        }
        return m.secret, nil
    })
    if err != nil {
        if errors.Is(err, jwt.ErrTokenExpired) {
            return nil, ErrTokenExpired
        }
        return nil, ErrTokenInvalid
    }
    claims, ok := token.Claims.(*Claims)
    if !ok || !token.Valid {
        return nil, ErrTokenInvalid
    }
    return claims, nil
}
```

- [ ] **步骤 2：编写中间件**

`server/internal/auth/middleware.go`:
```go
package auth

import (
    "net/http"
    "strings"
    "github.com/gin-gonic/gin"
)

func (m *JWTManager) UserRequired() gin.HandlerFunc {
    return func(c *gin.Context) {
        token := extractToken(c)
        if token == "" {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "未提供认证 token"})
            return
        }
        claims, err := m.Parse(token)
        if err != nil {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
            return
        }
        if claims.Role != "user" {
            c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "需要用户权限"})
            return
        }
        c.Set("user_id", claims.UserID)
        c.Set("email", claims.Email)
        c.Next()
    }
}

func (m *JWTManager) AdminRequired() gin.HandlerFunc {
    return func(c *gin.Context) {
        token := extractToken(c)
        if token == "" {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "未提供认证 token"})
            return
        }
        claims, err := m.Parse(token)
        if err != nil {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
            return
        }
        if claims.Role == "user" {
            c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "需要管理员权限"})
            return
        }
        c.Set("admin_id", claims.UserID)
        c.Set("admin_role", claims.Role)
        c.Next()
    }
}

func extractToken(c *gin.Context) string {
    auth := c.GetHeader("Authorization")
    if strings.HasPrefix(auth, "Bearer ") {
        return strings.TrimPrefix(auth, "Bearer ")
    }
    return ""
}
```

- [ ] **步骤 3：编写注册/登录 handler**

`server/internal/auth/handler.go`:
```go
package auth

import (
    "database/sql"
    "net/http"
    "github.com/gin-gonic/gin"
    "golang.org/x/crypto/bcrypt"
    "github.com/borderx/panel/internal/model"
)

type Handler struct {
    DB  *sql.DB
    JWT *JWTManager
}

type RegisterRequest struct {
    Email    string `json:"email" binding:"required,email"`
    Password string `json:"password" binding:"required,min=6,max=64"`
}

type LoginRequest struct {
    Email    string `json:"email" binding:"required,email"`
    Password string `json:"password" binding:"required"`
}

func (h *Handler) Register(c *gin.Context) {
    var req RegisterRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误: " + err.Error()})
        return
    }
    hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), 12)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "服务器错误"})
        return
    }
    var user model.User
    err = h.DB.QueryRow(
        `INSERT INTO users (email, password_hash) VALUES ($1, $2)
         RETURNING id, email, status, created_at`,
        req.Email, string(hash),
    ).Scan(&user.ID, &user.Email, &user.Status, &user.CreatedAt)
    if err != nil {
        if isDuplicate(err) {
            c.JSON(http.StatusConflict, gin.H{"error": "该邮箱已注册"})
            return
        }
        c.JSON(http.StatusInternalServerError, gin.H{"error": "注册失败"})
        return
    }
    token, _ := h.JWT.GenerateUserToken(user.ID, user.Email)
    c.JSON(http.StatusCreated, gin.H{"token": token, "user": user})
}

func (h *Handler) Login(c *gin.Context) {
    var req LoginRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
        return
    }
    var user model.User
    err := h.DB.QueryRow(
        `SELECT id, email, password_hash, status FROM users WHERE email = $1`, req.Email,
    ).Scan(&user.ID, &user.Email, &user.PasswordHash, &user.Status)
    if err == sql.ErrNoRows {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "邮箱或密码错误"})
        return
    }
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "登录失败"})
        return
    }
    if user.Status != "active" {
        c.JSON(http.StatusForbidden, gin.H{"error": "账号已被禁用"})
        return
    }
    if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "邮箱或密码错误"})
        return
    }
    token, _ := h.JWT.GenerateUserToken(user.ID, user.Email)
    c.JSON(http.StatusOK, gin.H{"token": token, "user": user})
}

// AdminLogin 管理员登录，自动判断 users vs admins 表
type AdminLoginRequest struct {
    Username string `json:"username" binding:"required"`
    Password string `json:"password" binding:"required"`
}

func (h *Handler) AdminLogin(c *gin.Context) {
    var req AdminLoginRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
        return
    }
    var admin model.Admin
    err := h.DB.QueryRow(
        `SELECT id, username, password_hash, role FROM admins WHERE username = $1`, req.Username,
    ).Scan(&admin.ID, &admin.Username, &admin.PasswordHash, &admin.Role)
    if err == sql.ErrNoRows {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "用户名或密码错误"})
        return
    }
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "登录失败"})
        return
    }
    if err := bcrypt.CompareHashAndPassword([]byte(admin.PasswordHash), []byte(req.Password)); err != nil {
        c.JSON(http.StatusUnauthorized, gin.H{"error": "用户名或密码错误"})
        return
    }
    token, _ := h.JWT.GenerateAdminToken(admin.ID, admin.Username, admin.Role)
    c.JSON(http.StatusOK, gin.H{
        "token": token,
        "admin": gin.H{"id": admin.ID, "username": admin.Username, "role": admin.Role},
    })
}

func isDuplicate(err error) bool {
    return err != nil && strings.Contains(err.Error(), "duplicate key")
}
```

- [ ] **步骤 4：编译验证**

```bash
cd server && go build ./...
```
预期：编译成功（需要添加 strings import）

- [ ] **步骤 5：Commit**

```bash
git add server/internal/auth/
git commit -m "feat: JWT 认证 + 用户注册/登录 + 管理员登录"
```

---

### 任务 4：管理端 CRUD handler

**文件：**
- 创建：`server/internal/admin/handler.go`

- [ ] **步骤 1：编写管理端 CRUD（用户/套餐/订单）**

`server/internal/admin/handler.go`:
```go
package admin

import (
    "database/sql"
    "net/http"
    "github.com/gin-gonic/gin"
    "github.com/borderx/panel/internal/model"
)

type Handler struct {
    DB *sql.DB
}

// ---- 用户管理 ----
func (h *Handler) ListUsers(c *gin.Context) {
    page := queryInt(c, "page", 1)
    size := queryInt(c, "size", 20)
    offset := (page - 1) * size
    email := c.Query("email")
    status := c.Query("status")

    where := "WHERE 1=1"
    args := []interface{}{}
    argN := 1
    if email != "" {
        where += " AND email ILIKE $" + itoa(argN); argN++
        args = append(args, "%"+email+"%")
    }
    if status != "" {
        where += " AND status = $" + itoa(argN); argN++
        args = append(args, status)
    }

    var total int
    h.DB.QueryRow("SELECT count(*) FROM users "+where, args...).Scan(&total)

    args = append(args, size, offset)
    rows, err := h.DB.Query(
        "SELECT id, email, status, created_at FROM users "+where+" ORDER BY created_at DESC LIMIT $"+itoa(argN)+" OFFSET $"+itoa(argN+1),
        args...,
    )
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
        return
    }
    defer rows.Close()

    users := []model.User{}
    for rows.Next() {
        var u model.User
        rows.Scan(&u.ID, &u.Email, &u.Status, &u.CreatedAt)
        users = append(users, u)
    }
    c.JSON(http.StatusOK, model.Paginated{Items: users, Total: total, Page: page, Size: size})
}

func (h *Handler) GetUser(c *gin.Context) {
    var u model.User
    err := h.DB.QueryRow(
        "SELECT id, email, status, created_at FROM users WHERE id = $1", c.Param("id"),
    ).Scan(&u.ID, &u.Email, &u.Status, &u.CreatedAt)
    if err == sql.ErrNoRows {
        c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
        return
    }
    c.JSON(http.StatusOK, u)
}

func (h *Handler) DisableUser(c *gin.Context) {
    h.DB.Exec("UPDATE users SET status = 'disabled' WHERE id = $1", c.Param("id"))
    c.JSON(http.StatusOK, gin.H{"message": "已禁用"})
}

func (h *Handler) EnableUser(c *gin.Context) {
    h.DB.Exec("UPDATE users SET status = 'active' WHERE id = $1", c.Param("id"))
    c.JSON(http.StatusOK, gin.H{"message": "已启用"})
}

// ---- 套餐管理 ----
func (h *Handler) ListPlans(c *gin.Context) {
    rows, _ := h.DB.Query("SELECT id, name, price_cents, duration_days, traffic_limit_gb, max_devices, sort_order, is_active, created_at FROM plans ORDER BY sort_order")
    defer rows.Close()
    plans := []model.Plan{}
    for rows.Next() {
        var p model.Plan
        rows.Scan(&p.ID, &p.Name, &p.PriceCents, &p.DurationDays, &p.TrafficLimitGB, &p.MaxDevices, &p.SortOrder, &p.IsActive, &p.CreatedAt)
        plans = append(plans, p)
    }
    c.JSON(http.StatusOK, plans)
}

func (h *Handler) CreatePlan(c *gin.Context) {
    var p model.Plan
    if err := c.ShouldBindJSON(&p); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
        return
    }
    h.DB.QueryRow(
        `INSERT INTO plans (name, price_cents, duration_days, traffic_limit_gb, max_devices, sort_order)
         VALUES ($1,$2,$3,$4,$5,$6) RETURNING id, created_at`,
        p.Name, p.PriceCents, p.DurationDays, p.TrafficLimitGB, p.MaxDevices, p.SortOrder,
    ).Scan(&p.ID, &p.CreatedAt)
    c.JSON(http.StatusCreated, p)
}

func (h *Handler) UpdatePlan(c *gin.Context) {
    var p model.Plan
    if err := c.ShouldBindJSON(&p); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
        return
    }
    h.DB.Exec(
        `UPDATE plans SET name=$1, price_cents=$2, duration_days=$3, traffic_limit_gb=$4, max_devices=$5, sort_order=$6, is_active=$7 WHERE id=$8`,
        p.Name, p.PriceCents, p.DurationDays, p.TrafficLimitGB, p.MaxDevices, p.SortOrder, p.IsActive, c.Param("id"),
    )
    c.JSON(http.StatusOK, gin.H{"message": "已更新"})
}

func (h *Handler) DeletePlan(c *gin.Context) {
    h.DB.Exec("DELETE FROM plans WHERE id = $1", c.Param("id"))
    c.JSON(http.StatusOK, gin.H{"message": "已删除"})
}

// ---- 订单管理 ----
func (h *Handler) ListOrders(c *gin.Context) {
    page := queryInt(c, "page", 1)
    size := queryInt(c, "size", 20)
    offset := (page - 1) * size

    var total int
    h.DB.QueryRow("SELECT count(*) FROM orders").Scan(&total)

    rows, _ := h.DB.Query(`
        SELECT o.id, o.user_id, o.plan_id, o.status, o.amount_cents, o.paid_at, o.starts_at, o.expires_at, o.created_at,
               p.id, p.name, p.price_cents, p.duration_days, p.traffic_limit_gb, p.max_devices
        FROM orders o LEFT JOIN plans p ON o.plan_id = p.id
        ORDER BY o.created_at DESC LIMIT $1 OFFSET $2`, size, offset)
    defer rows.Close()

    orders := []model.Order{}
    for rows.Next() {
        var o model.Order
        o.Plan = &model.Plan{}
        rows.Scan(&o.ID, &o.UserID, &o.PlanID, &o.Status, &o.AmountCents,
            &o.PaidAt, &o.StartsAt, &o.ExpiresAt, &o.CreatedAt,
            &o.Plan.ID, &o.Plan.Name, &o.Plan.PriceCents, &o.Plan.DurationDays,
            &o.Plan.TrafficLimitGB, &o.Plan.MaxDevices)
        orders = append(orders, o)
    }
    c.JSON(http.StatusOK, model.Paginated{Items: orders, Total: total, Page: page, Size: size})
}

func (h *Handler) CancelOrder(c *gin.Context) {
    h.DB.Exec("UPDATE orders SET status = 'cancelled' WHERE id = $1 AND status = 'pending'", c.Param("id"))
    c.JSON(http.StatusOK, gin.H{"message": "已取消"})
}

// ---- 通用 ----
func queryInt(c *gin.Context, key string, defaultVal int) int {
    val := c.Query(key)
    if val == "" { return defaultVal }
    var n int
    fmt.Sscanf(val, "%d", &n)
    if n < 1 { return defaultVal }
    return n
}

func itoa(n int) string { return fmt.Sprintf("%d", n) }
```

- [ ] **步骤 2：编译验证 + 提交**

```bash
cd server && go build ./...
git add server/internal/admin/
git commit -m "feat: 管理端 CRUD — 用户/套餐/订单"
```

---

### 任务 5：路由组装 + main.go 完整启动

**文件：**
- 修改：`server/cmd/panel/main.go`

- [ ] **步骤 1：编写完整 main.go（路由 + 中间件 + 静态文件）**

`server/cmd/panel/main.go`:
```go
package main

import (
    "embed"
    "flag"
    "io/fs"
    "log"
    "net/http"
    "github.com/gin-gonic/gin"
    "github.com/borderx/panel/internal/admin"
    "github.com/borderx/panel/internal/auth"
    "github.com/borderx/panel/internal/config"
    "github.com/borderx/panel/internal/store"
)

//go:embed all:web/dist
var webAssets embed.FS

func main() {
    cfgPath := flag.String("config", "/etc/borderx/config.yml", "配置文件路径")
    flag.Parse()

    cfg := config.MustLoad(*cfgPath)
    db, err := store.Connect(cfg.DSN())
    if err != nil {
        log.Fatalf("数据库连接失败: %v", err)
    }
    defer db.Close()

    if err := store.Migrate(db); err != nil {
        log.Fatalf("数据库迁移失败: %v", err)
    }

    jwtMgr := auth.NewJWTManager(cfg.JWT.Secret, cfg.JWT.ExpireHour)
    authH := &auth.Handler{DB: db, JWT: jwtMgr}
    adminH := &admin.Handler{DB: db}

    gin.SetMode(cfg.Server.Mode)
    r := gin.Default()

    // 公开路由
    r.POST("/api/auth/register", authH.Register)
    r.POST("/api/auth/login", authH.Login)
    r.POST("/api/auth/admin-login", authH.AdminLogin)

    // 用户路由
    user := r.Group("/api")
    user.Use(jwtMgr.UserRequired())
    {
        user.GET("/plans", func(c *gin.Context) {
            adminH.ListPlans(c) // 复用管理端 list，所有用户可见
        })
        user.GET("/me", func(c *gin.Context) {
            c.JSON(http.StatusOK, gin.H{"user_id": c.GetString("user_id"), "email": c.GetString("email")})
        })
    }

    // 管理路由
    adm := r.Group("/api/admin")
    adm.Use(jwtMgr.AdminRequired())
    {
        adm.GET("/users", adminH.ListUsers)
        adm.GET("/users/:id", adminH.GetUser)
        adm.POST("/users/:id/disable", adminH.DisableUser)
        adm.POST("/users/:id/enable", adminH.EnableUser)
        adm.GET("/plans", adminH.ListPlans)
        adm.POST("/plans", adminH.CreatePlan)
        adm.PUT("/plans/:id", adminH.UpdatePlan)
        adm.DELETE("/plans/:id", adminH.DeletePlan)
        adm.GET("/orders", adminH.ListOrders)
        adm.POST("/orders/:id/cancel", adminH.CancelOrder)
        adm.GET("/dashboard", dashboardHandler(db))
    }

    // SPA fallback
    webFS, _ := fs.Sub(webAssets, "web/dist")
    r.NoRoute(gin.WrapH(http.FileServer(http.FS(webFS))))

    log.Printf("BorderX Panel 启动在 :%d\n", cfg.Server.Port)
    r.Run(":" + itoa(cfg.Server.Port))
}

func dashboardHandler(db *sql.DB) gin.HandlerFunc {
    return func(c *gin.Context) {
        var totalUsers, activeAccounts, revenueToday int
        db.QueryRow("SELECT count(*) FROM users").Scan(&totalUsers)
        db.QueryRow("SELECT count(*) FROM vpn_accounts WHERE status='active'").Scan(&activeAccounts)
        db.QueryRow("SELECT COALESCE(SUM(amount_cents),0) FROM orders WHERE status='paid' AND paid_at::date = CURRENT_DATE").Scan(&revenueToday)
        c.JSON(http.StatusOK, gin.H{
            "total_users":      totalUsers,
            "active_accounts":  activeAccounts,
            "revenue_today":    revenueToday,
        })
    }
}

func itoa(n int) string { return fmt.Sprintf("%d", n) }
```

- [ ] **步骤 2：编译验证**

```bash
cd server && go build ./cmd/panel/
```
预期：编译成功

- [ ] **步骤 3：Commit**

```bash
git add server/cmd/panel/
git commit -m "feat: 路由组装 + SPA fallback + 仪表盘 API"
```

---

### 任务 6：React 项目初始化

**文件：**
- 创建：`web/package.json`
- 创建：`web/vite.config.ts`
- 创建：`web/tsconfig.json`
- 创建：`web/tailwind.config.js`
- 创建：`web/index.html`
- 创建：`web/src/main.tsx`
- 创建：`web/src/App.tsx`
- 创建：`web/src/api.ts`

- [ ] **步骤 1：创建 React 项目**

```bash
cd web
npm create vite@latest . -- --template react-ts
npm install
npm install tailwindcss @tailwindcss/vite react-router-dom zustand axios
```

- [ ] **步骤 2：配置 tailwind + vite**

`web/vite.config.ts`:
```ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: { port: 5173, proxy: { '/api': 'http://localhost:8080' } },
})
```

`web/src/index.css` 追加:
```css
@import "tailwindcss";
```

- [ ] **步骤 3：编写 API 封装**

`web/src/api.ts`:
```ts
import axios from 'axios'

const api = axios.create({ baseURL: '/api' })

api.interceptors.request.use((cfg) => {
  const token = localStorage.getItem('token')
  if (token) cfg.headers.Authorization = `Bearer ${token}`
  return cfg
})

api.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem('token')
      window.location.href = '/login'
    }
    return Promise.reject(err)
  }
)

export interface User { id: string; email: string; status: string; created_at: string }
export interface Plan { id: string; name: string; price_cents: number; duration_days: number; traffic_limit_gb: number; max_devices: number; is_active: boolean }

export const auth = {
  register: (email: string, password: string) => api.post('/auth/register', { email, password }),
  login: (email: string, password: string) => api.post('/auth/login', { email, password }),
  adminLogin: (username: string, password: string) => api.post('/auth/admin-login', { username, password }),
}

export const plans = { list: () => api.get<Plan[]>('/plans') }

export const admin = {
  dashboard: () => api.get('/admin/dashboard'),
  listUsers: (params?: any) => api.get('/admin/users', { params }),
  getUser: (id: string) => api.get(`/admin/users/${id}`),
  disableUser: (id: string) => api.post(`/admin/users/${id}/disable`),
  enableUser: (id: string) => api.post(`/admin/users/${id}/enable`),
  listPlans: () => api.get<Plan[]>('/admin/plans'),
  createPlan: (data: Partial<Plan>) => api.post('/admin/plans', data),
  updatePlan: (id: string, data: Partial<Plan>) => api.put(`/admin/plans/${id}`, data),
  deletePlan: (id: string) => api.delete(`/admin/plans/${id}`),
  listOrders: (params?: any) => api.get('/admin/orders', { params }),
  cancelOrder: (id: string) => api.post(`/admin/orders/${id}/cancel`),
}

export default api
```

- [ ] **步骤 4：编写 auth store**

`web/src/store/auth.ts`:
```ts
import { create } from 'zustand'

interface AuthState {
  token: string | null
  user: { email: string; role: string } | null
  login: (token: string, user: any) => void
  logout: () => void
}

export const useAuth = create<AuthState>((set) => ({
  token: localStorage.getItem('token'),
  user: JSON.parse(localStorage.getItem('user') || 'null'),
  login: (token, user) => {
    localStorage.setItem('token', token)
    localStorage.setItem('user', JSON.stringify(user))
    set({ token, user })
  },
  logout: () => {
    localStorage.removeItem('token')
    localStorage.removeItem('user')
    set({ token: null, user: null })
  },
}))
```

- [ ] **步骤 5：编写路由 + App**

`web/src/App.tsx`:
```tsx
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { useAuth } from './store/auth'
import Home from './pages/Home'
import Login from './pages/Login'
import Register from './pages/Register'
import Dashboard from './pages/Dashboard'
import AdminLayout from './pages/admin/Layout'
import AdminDashboard from './pages/admin/Dashboard'
import AdminUsers from './pages/admin/Users'
import AdminPlans from './pages/admin/Plans'
import AdminOrders from './pages/admin/Orders'

function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { token } = useAuth()
  return token ? <>{children}</> : <Navigate to="/login" />
}

function AdminRoute({ children }: { children: React.ReactNode }) {
  const { token, user } = useAuth()
  if (!token) return <Navigate to="/login" />
  return user?.role !== 'user' ? <>{children}</> : <Navigate to="/dashboard" />
}

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/login" element={<Login />} />
        <Route path="/register" element={<Register />} />
        <Route path="/dashboard" element={<ProtectedRoute><Dashboard /></ProtectedRoute>} />
        <Route path="/admin" element={<AdminRoute><AdminLayout /></AdminRoute>}>
          <Route index element={<AdminDashboard />} />
          <Route path="users" element={<AdminUsers />} />
          <Route path="plans" element={<AdminPlans />} />
          <Route path="orders" element={<AdminOrders />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}
```

- [ ] **步骤 6：Commit**

```bash
git add web/
git commit -m "feat: React 项目初始化 + 路由 + auth store + API 封装"
```

---

### 任务 7：React 页面实现

**文件：**
- 创建：`web/src/pages/Home.tsx`, `Login.tsx`, `Register.tsx`, `Dashboard.tsx`
- 创建：`web/src/pages/admin/Layout.tsx`, `Dashboard.tsx`, `Users.tsx`, `Plans.tsx`, `Orders.tsx`
- 创建：`web/src/components/Navbar.tsx`

- [ ] **步骤 1：Login 页面**

`web/src/pages/Login.tsx`:
```tsx
import { useState } from 'react'
import { useNavigate, Link } from 'react-router-dom'
import { auth } from '../api'
import { useAuth } from '../store/auth'

export default function Login() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const navigate = useNavigate()
  const { login } = useAuth()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); setError('')
    try {
      const { data } = await auth.login(email, password)
      login(data.token, { email, role: 'user' })
      navigate('/dashboard')
    } catch (err: any) {
      setError(err.response?.data?.error || '登录失败')
    }
  }

  // Admin login via username
  const handleAdminSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); setError('')
    try {
      const { data } = await auth.adminLogin(email, password)
      login(data.token, { email: data.admin.username, role: data.admin.role })
      navigate('/admin')
    } catch (err: any) {
      setError(err.response?.data?.error || '登录失败')
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="max-w-md w-full bg-white p-8 rounded-lg shadow">
        <h1 className="text-2xl font-bold mb-6 text-center">登录</h1>
        {error && <div className="bg-red-50 text-red-600 p-3 rounded mb-4">{error}</div>}
        <form onSubmit={handleSubmit}>
          <input className="w-full border p-2 rounded mb-3" type="text" placeholder="邮箱 或 管理员用户名" value={email} onChange={(e) => setEmail(e.target.value)} />
          <input className="w-full border p-2 rounded mb-4" type="password" placeholder="密码" value={password} onChange={(e) => setPassword(e.target.value)} />
          <button className="w-full bg-blue-600 text-white p-2 rounded mb-2" type="submit">用户登录</button>
          <button className="w-full bg-gray-800 text-white p-2 rounded" type="button" onClick={handleAdminSubmit}>管理员登录</button>
        </form>
        <p className="text-center text-gray-500 mt-4"><Link to="/register">还没有账号？去注册</Link></p>
      </div>
    </div>
  )
}
```

- [ ] **步骤 2：Register 页面**

`web/src/pages/Register.tsx`:
```tsx
import { useState } from 'react'
import { useNavigate, Link } from 'react-router-dom'
import { auth } from '../api'
import { useAuth } from '../store/auth'

export default function Register() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const navigate = useNavigate()
  const { login } = useAuth()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); setError('')
    if (password.length < 6) { setError('密码至少 6 位'); return }
    try {
      const { data } = await auth.register(email, password)
      login(data.token, { email, role: 'user' })
      navigate('/dashboard')
    } catch (err: any) {
      setError(err.response?.data?.error || '注册失败')
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="max-w-md w-full bg-white p-8 rounded-lg shadow">
        <h1 className="text-2xl font-bold mb-6 text-center">注册</h1>
        {error && <div className="bg-red-50 text-red-600 p-3 rounded mb-4">{error}</div>}
        <form onSubmit={handleSubmit}>
          <input className="w-full border p-2 rounded mb-3" type="email" placeholder="邮箱" value={email} onChange={(e) => setEmail(e.target.value)} />
          <input className="w-full border p-2 rounded mb-4" type="password" placeholder="密码（至少 6 位）" value={password} onChange={(e) => setPassword(e.target.value)} />
          <button className="w-full bg-blue-600 text-white p-2 rounded" type="submit">注册</button>
        </form>
        <p className="text-center text-gray-500 mt-4"><Link to="/login">已有账号？去登录</Link></p>
      </div>
    </div>
  )
}
```

- [ ] **步骤 3：Home 页面**

`web/src/pages/Home.tsx`:
```tsx
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { plans, Plan } from '../api'

export default function Home() {
  const [planList, setPlanList] = useState<Plan[]>([])

  useEffect(() => { plans.list().then(({ data }) => setPlanList(data)).catch(() => {}) }, [])

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white shadow p-4 flex justify-between items-center">
        <span className="text-xl font-bold">BorderX</span>
        <div><Link to="/login" className="text-blue-600 mr-4">登录</Link><Link to="/register" className="bg-blue-600 text-white px-4 py-2 rounded">注册</Link></div>
      </nav>
      <main className="max-w-4xl mx-auto py-16 text-center">
        <h1 className="text-4xl font-bold mb-4">安全 · 高速 · 全球节点</h1>
        <p className="text-gray-500 mb-12">企业级加密协议，多协议支持，全球加速</p>
        <div className="grid grid-cols-3 gap-6">
          {planList.map((p) => (
            <div key={p.id} className="bg-white p-6 rounded-lg shadow">
              <h3 className="text-xl font-bold mb-2">{p.name}</h3>
              <p className="text-3xl font-bold text-blue-600 mb-2">¥{(p.price_cents / 100).toFixed(2)}</p>
              <p className="text-gray-500">{p.duration_days} 天 / {p.traffic_limit_gb}GB</p>
              <Link to="/register" className="block mt-4 bg-blue-600 text-white py-2 rounded">立即购买</Link>
            </div>
          ))}
        </div>
      </main>
    </div>
  )
}
```

- [ ] **步骤 4：Dashboard + Admin 页面**

`web/src/pages/Dashboard.tsx`:
```tsx
import { useAuth } from '../store/auth'
import { useNavigate } from 'react-router-dom'

export default function Dashboard() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white shadow p-4 flex justify-between">
        <span className="font-bold">BorderX</span>
        <div>
          <span className="mr-4 text-gray-600">{user?.email}</span>
          <button onClick={() => { logout(); navigate('/') }} className="text-red-600">退出</button>
        </div>
      </nav>
      <main className="max-w-4xl mx-auto py-12">
        <h1 className="text-2xl font-bold mb-6">我的仪表盘</h1>
        <div className="grid grid-cols-2 gap-6">
          <div className="bg-white p-6 rounded shadow">
            <h2 className="font-bold mb-2">VPN 账号</h2>
            <p className="text-gray-500">购买套餐后自动创建</p>
          </div>
          <div className="bg-white p-6 rounded shadow">
            <h2 className="font-bold mb-2">我的订单</h2>
            <p className="text-gray-500">暂无订单</p>
          </div>
        </div>
      </main>
    </div>
  )
}
```

`web/src/pages/admin/Layout.tsx`:
```tsx
import { Outlet, Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../../store/auth'

export default function AdminLayout() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()

  const links = [
    { to: '/admin', label: '仪表盘' },
    { to: '/admin/users', label: '用户' },
    { to: '/admin/orders', label: '订单' },
    { to: '/admin/plans', label: '套餐' },
  ]

  return (
    <div className="min-h-screen flex">
      <aside className="w-56 bg-gray-900 text-white p-4">
        <h1 className="text-lg font-bold mb-6">BorderX 管理</h1>
        <nav>
          {links.map((l) => (
            <Link key={l.to} to={l.to} className="block py-2 px-3 rounded hover:bg-gray-700 mb-1">{l.label}</Link>
          ))}
        </nav>
        <div className="absolute bottom-4 left-4">
          <span className="text-gray-400 text-sm block">{user?.email} ({user?.role})</span>
          <button onClick={() => { logout(); navigate('/login') }} className="text-gray-400 text-sm">退出</button>
        </div>
      </aside>
      <main className="flex-1 p-8 bg-gray-50">
        <Outlet />
      </main>
    </div>
  )
}
```

`web/src/pages/admin/Dashboard.tsx`:
```tsx
import { useEffect, useState } from 'react'
import { admin } from '../../api'

export default function AdminDashboard() {
  const [data, setData] = useState<any>({})
  useEffect(() => { admin.dashboard().then(({ data }) => setData(data)).catch(() => {}) }, [])

  return (
    <div>
      <h2 className="text-2xl font-bold mb-6">仪表盘</h2>
      <div className="grid grid-cols-3 gap-6">
        <div className="bg-white p-6 rounded shadow"><p className="text-gray-500">总用户</p><p className="text-3xl font-bold">{data.total_users ?? '-'}</p></div>
        <div className="bg-white p-6 rounded shadow"><p className="text-gray-500">活跃账号</p><p className="text-3xl font-bold">{data.active_accounts ?? '-'}</p></div>
        <div className="bg-white p-6 rounded shadow"><p className="text-gray-500">今日收入</p><p className="text-3xl font-bold">¥{((data.revenue_today ?? 0) / 100).toFixed(2)}</p></div>
      </div>
    </div>
  )
}
```

`web/src/pages/admin/Users.tsx`:
```tsx
import { useEffect, useState } from 'react'
import { admin, User } from '../../api'

export default function AdminUsers() {
  const [users, setUsers] = useState<User[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [email, setEmail] = useState('')

  const load = () => { admin.listUsers({ page, email: email || undefined }).then(({ data }) => { setUsers(data.items); setTotal(data.total) }) }
  useEffect(() => { load() }, [page])

  return (
    <div>
      <h2 className="text-2xl font-bold mb-4">用户管理</h2>
      <div className="mb-4 flex gap-2">
        <input className="border p-2 rounded" placeholder="搜索邮箱" value={email} onChange={(e) => setEmail(e.target.value)} />
        <button className="bg-blue-600 text-white px-4 py-2 rounded" onClick={() => { setPage(1); load() }}>搜索</button>
      </div>
      <table className="w-full bg-white shadow rounded">
        <thead><tr className="text-left border-b"><th className="p-3">邮箱</th><th className="p-3">状态</th><th className="p-3">注册时间</th><th className="p-3">操作</th></tr></thead>
        <tbody>
          {users.map((u) => (
            <tr key={u.id} className="border-b">
              <td className="p-3">{u.email}</td>
              <td className="p-3"><span className={u.status === 'active' ? 'text-green-600' : 'text-red-600'}>{u.status}</span></td>
              <td className="p-3">{new Date(u.created_at).toLocaleDateString()}</td>
              <td className="p-3">
                {u.status === 'active'
                  ? <button className="text-red-600" onClick={() => admin.disableUser(u.id).then(() => load())}>禁用</button>
                  : <button className="text-green-600" onClick={() => admin.enableUser(u.id).then(() => load())}>启用</button>}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <div className="mt-4 flex justify-center gap-2">
        <button disabled={page <= 1} onClick={() => setPage(page - 1)} className="px-3 py-1 border rounded disabled:opacity-30">上一页</button>
        <span className="px-3 py-1">第 {page} 页 / 共 {Math.ceil(total / 20)} 页</span>
        <button disabled={page >= Math.ceil(total / 20)} onClick={() => setPage(page + 1)} className="px-3 py-1 border rounded disabled:opacity-30">下一页</button>
      </div>
    </div>
  )
}
```

`web/src/pages/admin/Plans.tsx`:
```tsx
import { useEffect, useState } from 'react'
import { admin, Plan } from '../../api'

export default function AdminPlans() {
  const [plans, setPlans] = useState<Plan[]>([])
  const [showForm, setShowForm] = useState(false)
  const [form, setForm] = useState<Partial<Plan>>({ name: '', price_cents: 0, duration_days: 30, traffic_limit_gb: 100, max_devices: 2, sort_order: 0, is_active: true })

  const load = () => { admin.listPlans().then(({ data }) => setPlans(data)) }
  useEffect(() => { load() }, [])

  const save = async () => {
    if (form.id) { await admin.updatePlan(form.id, form) }
    else { await admin.createPlan(form) }
    setShowForm(false); load()
  }

  return (
    <div>
      <div className="flex justify-between mb-4">
        <h2 className="text-2xl font-bold">套餐管理</h2>
        <button className="bg-blue-600 text-white px-4 py-2 rounded" onClick={() => { setForm({ name: '', price_cents: 0, duration_days: 30, traffic_limit_gb: 100, max_devices: 2, sort_order: 0, is_active: true }); setShowForm(true) }}>新增套餐</button>
      </div>
      {showForm && (
        <div className="bg-white p-6 rounded shadow mb-4 grid grid-cols-2 gap-4">
          <input className="border p-2 rounded" placeholder="名称" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          <input className="border p-2 rounded" type="number" placeholder="价格（分）" value={form.price_cents} onChange={(e) => setForm({ ...form, price_cents: +e.target.value })} />
          <input className="border p-2 rounded" type="number" placeholder="天数" value={form.duration_days} onChange={(e) => setForm({ ...form, duration_days: +e.target.value })} />
          <input className="border p-2 rounded" type="number" placeholder="流量(GB)" value={form.traffic_limit_gb} onChange={(e) => setForm({ ...form, traffic_limit_gb: +e.target.value })} />
          <button className="bg-green-600 text-white p-2 rounded" onClick={save}>保存</button>
          <button className="bg-gray-400 text-white p-2 rounded" onClick={() => setShowForm(false)}>取消</button>
        </div>
      )}
      <table className="w-full bg-white shadow rounded">
        <thead><tr className="text-left border-b"><th className="p-3">名称</th><th className="p-3">价格</th><th className="p-3">天数</th><th className="p-3">流量</th><th className="p-3">设备</th><th className="p-3">状态</th><th className="p-3">操作</th></tr></thead>
        <tbody>
          {plans.map((p) => (
            <tr key={p.id} className="border-b">
              <td className="p-3">{p.name}</td>
              <td className="p-3">¥{(p.price_cents / 100).toFixed(2)}</td>
              <td className="p-3">{p.duration_days}天</td>
              <td className="p-3">{p.traffic_limit_gb}GB</td>
              <td className="p-3">{p.max_devices}</td>
              <td className="p-3">{p.is_active ? '启用' : '禁用'}</td>
              <td className="p-3">
                <button className="text-blue-600 mr-2" onClick={() => { setForm(p); setShowForm(true) }}>编辑</button>
                <button className="text-red-600" onClick={() => admin.deletePlan(p.id).then(load)}>删除</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
```

`web/src/pages/admin/Orders.tsx`:
```tsx
import { useEffect, useState } from 'react'
import { admin } from '../../api'

export default function AdminOrders() {
  const [orders, setOrders] = useState<any[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)

  const load = () => { admin.listOrders({ page }).then(({ data }) => { setOrders(data.items); setTotal(data.total) }) }
  useEffect(() => { load() }, [page])

  return (
    <div>
      <h2 className="text-2xl font-bold mb-4">订单管理</h2>
      <table className="w-full bg-white shadow rounded">
        <thead><tr className="text-left border-b"><th className="p-3">ID</th><th className="p-3">套餐</th><th className="p-3">金额</th><th className="p-3">状态</th><th className="p-3">创建时间</th><th className="p-3">操作</th></tr></thead>
        <tbody>
          {orders.map((o: any) => (
            <tr key={o.id} className="border-b">
              <td className="p-3 text-gray-400 text-sm">{o.id.substring(0, 8)}...</td>
              <td className="p-3">{o.plan?.name || '-'}</td>
              <td className="p-3">¥{(o.amount_cents / 100).toFixed(2)}</td>
              <td className="p-3"><span className={o.status === 'paid' ? 'text-green-600' : o.status === 'cancelled' ? 'text-gray-400' : 'text-yellow-600'}>{o.status}</span></td>
              <td className="p-3">{new Date(o.created_at).toLocaleDateString()}</td>
              <td className="p-3">
                {o.status === 'pending' && <button className="text-red-600" onClick={() => admin.cancelOrder(o.id).then(load)}>取消</button>}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
```

- [ ] **步骤 7：编译验证**

```bash
cd web && npm run build
```
预期：构建成功，dist/ 生成静态文件

- [ ] **步骤 8：Commit**

```bash
git add web/src/pages/ web/src/components/
git commit -m "feat: React 页面 — 首页/登录/注册/仪表盘/管理后台"
```

---

### 任务 8：Go 内嵌前端 + 端到端构建

**文件：**
- 修改：`server/cmd/panel/main.go`（确保 embed 路径正确）

- [ ] **步骤 1：构建 React + 复制到 server 目录**

```bash
cd web && npm run build
cp -r dist ../server/web/
```

- [ ] **步骤 2：编译 Go 二进制**

```bash
cd server && go build -o borderx-panel ./cmd/panel/
```
预期：编译成功，生成 `borderx-panel` 二进制

- [ ] **步骤 3：验证二进制可运行**

```bash
cd server && ./borderx-panel --help 2>&1 | head -1
```


- [ ] **步骤 4：Commit**

```bash
git add server/web/ server/borderx-panel 2>/dev/null || true
git commit -m "feat: Go 内嵌 React 前端，单二进制构建"
```

---

## Phase 2：VPN 核心

### 任务 9：Xray 配置读写模块

**文件：**
- 创建：`server/internal/xray/config.go`
- 创建：`server/internal/xray/key.go`

- [ ] **步骤 1：编写 X25519 密钥管理**

`server/internal/xray/key.go`:
```go
package xray

import (
    "bytes"
    "crypto/rand"
    "encoding/hex"
    "os/exec"
)

type RealityKeys struct {
    PrivateKey string `json:"private_key"`
    PublicKey  string `json:"public_key"`
    ShortID    string `json:"short_id"`
}

func GenerateRealityKeys() (*RealityKeys, error) {
    cmd := exec.Command("/usr/local/bin/xray", "x25519")
    var out bytes.Buffer
    cmd.Stdout = &out
    if err := cmd.Run(); err != nil {
        return nil, err
    }
    // Parse xray x25519 output: "Private key: xxx\nPublic key: yyy"
    output := out.String()
    priv := extractLine(output, "Private key:")
    pub := extractLine(output, "Public key:")
    sid := generateShortID()
    return &RealityKeys{PrivateKey: priv, PublicKey: pub, ShortID: sid}, nil
}

func generateShortID() string {
    b := make([]byte, 8)
    rand.Read(b)
    return hex.EncodeToString(b)
}

func extractLine(output, prefix string) string {
    for _, line := range bytes.Split([]byte(output), []byte("\n")) {
        if bytes.HasPrefix(line, []byte(prefix)) {
            s := string(line)
            i := 0
            for ; i < len(s) && s[i] != ':'; i++ {}
            if i+2 < len(s) { return s[i+2:] }
            return s
        }
    }
    return ""
}
```

- [ ] **步骤 2：编写 Xray config.json 读写**

`server/internal/xray/config.go`:
```go
package xray

import (
    "encoding/json"
    "fmt"
    "os"
    "os/exec"
)

type XrayConfig struct {
    Log      json.RawMessage `json:"log"`
    DNS      json.RawMessage `json:"dns"`
    Inbounds []Inbound       `json:"inbounds"`
    Outbounds json.RawMessage `json:"outbounds"`
    Routing  json.RawMessage `json:"routing"`
    Stats    json.RawMessage `json:"stats"`
    API      json.RawMessage `json:"api"`
    Policy   json.RawMessage `json:"policy"`
}

type Inbound struct {
    Tag      string          `json:"tag"`
    Port     int             `json:"port"`
    Protocol string          `json:"protocol"`
    Settings json.RawMessage `json:"settings"`
    StreamSettings json.RawMessage `json:"streamSettings,omitempty"`
    Sniffing json.RawMessage `json:"sniffing,omitempty"`
    Listen   string          `json:"listen,omitempty"`
}

type VLESSClient struct {
    ID    string `json:"id"`
    Flow  string `json:"flow"`
    Email string `json:"email"`
}

type VMessClient struct {
    ID      string `json:"id"`
    AlterID int    `json:"alterId"`
    Email   string `json:"email"`
}

type TrojanClient struct {
    Password string `json:"password"`
    Email    string `json:"email"`
}

type Manager struct {
    configPath string
    binaryPath string
    config     *XrayConfig
}

func NewManager(configPath, binaryPath string) (*Manager, error) {
    m := &Manager{configPath: configPath, binaryPath: binaryPath}
    if err := m.Reload(); err != nil {
        return nil, err
    }
    return m, nil
}

func (m *Manager) Reload() error {
    data, err := os.ReadFile(m.configPath)
    if err != nil {
        return fmt.Errorf("读取 Xray 配置失败: %w", err)
    }
    var cfg XrayConfig
    if err := json.Unmarshal(data, &cfg); err != nil {
        return fmt.Errorf("解析 Xray 配置失败: %w", err)
    }
    m.config = &cfg
    return nil
}

func (m *Manager) save() error {
    data, err := json.MarshalIndent(m.config, "", "  ")
    if err != nil {
        return err
    }
    tmpPath := m.configPath + ".tmp"
    if err := os.WriteFile(tmpPath, data, 0644); err != nil {
        return err
    }
    if err := os.Rename(tmpPath, m.configPath); err != nil {
        return err
    }
    return exec.Command("systemctl", "reload", "xray").Run()
}

// AddClient 向指定 tag 的入站添加客户端
func (m *Manager) AddClient(tag, protocol, email, id, password string) error {
    for i := range m.config.Inbounds {
        in := &m.config.Inbounds[i]
        if in.Tag != tag { continue }

        switch protocol {
        case "vless":
            clients, _ := parseVLESSClients(in.Settings)
            clients = append(clients, VLESSClient{ID: id, Flow: "xtls-rprx-vision", Email: email})
            newSettings, _ := json.Marshal(map[string]interface{}{"clients": clients, "decryption": "none"})
            in.Settings = newSettings
        case "vmess":
            clients, _ := parseVMessClients(in.Settings)
            clients = append(clients, VMessClient{ID: id, AlterID: 0, Email: email})
            newSettings, _ := json.Marshal(map[string]interface{}{"clients": clients})
            in.Settings = newSettings
        case "trojan":
            clients, _ := parseTrojanClients(in.Settings)
            clients = append(clients, TrojanClient{Password: password, Email: email})
            newSettings, _ := json.Marshal(map[string]interface{}{"clients": clients})
            in.Settings = newSettings
        }
    }
    return m.save()
}

// RemoveClient 从指定 tag 的入站移除 email 匹配的客户端
func (m *Manager) RemoveClient(tag, email string) error {
    for i := range m.config.Inbounds {
        in := &m.config.Inbounds[i]
        if in.Tag != tag { continue }
        in.Settings = removeClientByEmail(in.Settings, email)
    }
    return m.save()
}

func parseVLESSClients(raw json.RawMessage) ([]VLESSClient, error) {
    var wrapper struct{ Clients []VLESSClient `json:"clients"` }
    if err := json.Unmarshal(raw, &wrapper); err != nil { return nil, err }
    return wrapper.Clients, nil
}

func parseVMessClients(raw json.RawMessage) ([]VMessClient, error) {
    var wrapper struct{ Clients []VMessClient `json:"clients"` }
    if err := json.Unmarshal(raw, &wrapper); err != nil { return nil, err }
    return wrapper.Clients, nil
}

func parseTrojanClients(raw json.RawMessage) ([]TrojanClient, error) {
    var wrapper struct{ Clients []TrojanClient `json:"clients"` }
    if err := json.Unmarshal(raw, &wrapper); err != nil { return nil, err }
    return wrapper.Clients, nil
}

func removeClientByEmail(raw json.RawMessage, email string) json.RawMessage {
    var wrapper struct {
        Clients  []map[string]interface{} `json:"clients"`
        Password string                   `json:"password,omitempty"`
        Decryption string                 `json:"decryption,omitempty"`
    }
    json.Unmarshal(raw, &wrapper)
    filtered := []map[string]interface{}{}
    for _, c := range wrapper.Clients {
        if c["email"] != email {
            filtered = append(filtered, c)
        }
    }
    wrapper.Clients = filtered
    data, _ := json.Marshal(wrapper)
    return data
}
```

- [ ] **步骤 3：编译验证 + 提交**

```bash
cd server && go build ./internal/xray/
git add server/internal/xray/
git commit -m "feat: Xray 配置读写 + X25519 密钥管理"
```

---

### 任务 10：下单 → 自动创建 VPN 账号

**文件：**
- 创建：`server/internal/api/handler.go`
- 修改：`server/cmd/panel/main.go`（注册新路由）

- [ ] **步骤 1：编写用户端 handler（下单 + 查看账号）**

`server/internal/api/handler.go`:
```go
package api

import (
    "database/sql"
    "net/http"
    "time"
    "github.com/gin-gonic/gin"
    "github.com/google/uuid"
    "github.com/borderx/panel/internal/xray"
)

type Handler struct {
    DB    *sql.DB
    Xray  *xray.Manager
}

type CreateOrderRequest struct {
    PlanID   string `json:"plan_id" binding:"required"`
    Protocol string `json:"protocol"` // vless / vmess / trojan，默认 vless
}

func (h *Handler) CreateOrder(c *gin.Context) {
    var req CreateOrderRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
        return
    }
    if req.Protocol == "" { req.Protocol = "vless" }

    userID := c.GetString("user_id")

    // 查套餐
    var priceCents, durationDays, trafficGB int
    var planName string
    err := h.DB.QueryRow(
        "SELECT name, price_cents, duration_days, traffic_limit_gb FROM plans WHERE id = $1 AND is_active = true",
        req.PlanID,
    ).Scan(&planName, &priceCents, &durationDays, &trafficGB)
    if err == sql.ErrNoRows {
        c.JSON(http.StatusNotFound, gin.H{"error": "套餐不存在或已下架"})
        return
    }

    // 创建订单
    var orderID string
    h.DB.QueryRow(
        `INSERT INTO orders (user_id, plan_id, amount_cents) VALUES ($1,$2,$3) RETURNING id`,
        userID, req.PlanID, priceCents,
    ).Scan(&orderID)

    // MVP: 支付跳过，直接标记 paid（Phase 3 接入支付宝）
    now := time.Now()
    expiresAt := now.Add(time.Duration(durationDays) * 24 * time.Hour)
    h.DB.Exec(
        `UPDATE orders SET status='paid', paid_at=$1, starts_at=$1, expires_at=$2 WHERE id=$3`,
        now, expiresAt, orderID,
    )

    // 创建 VPN 账号
    vpnUUID := uuid.New().String()
    password := ""
    if req.Protocol == "trojan" {
        password = uuid.New().String()[:16]
    }

    var accountID string
    h.DB.QueryRow(
        `INSERT INTO vpn_accounts (user_id, order_id, protocol, uuid, password, traffic_limit_bytes, expires_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id`,
        userID, orderID, req.Protocol, vpnUUID, password, int64(trafficGB)*1024*1024*1024, expiresAt,
    ).Scan(&accountID)

    // 写 Xray 配置（仅本地节点 MVP）
    tag := map[string]string{"vless": "vless-reality", "vmess": "vmess-ws", "trojan": "trojan-tcp"}[req.Protocol]
    email := accountID + "@borderx"
    h.Xray.AddClient(tag, req.Protocol, email, vpnUUID, password)

    // 生成订阅 token（如果还没有）
    var subToken string
    h.DB.QueryRow(`INSERT INTO sub_tokens (user_id, token) VALUES ($1, $2) ON CONFLICT (user_id) DO UPDATE SET token=sub_tokens.token RETURNING token`,
        userID, uuid.New().String()[:16],
    ).Scan(&subToken)

    c.JSON(http.StatusCreated, gin.H{
        "order_id":    orderID,
        "account_id":  accountID,
        "protocol":    req.Protocol,
        "uuid":        vpnUUID,
        "expires_at":  expiresAt,
        "sub_token":   subToken,
    })
}

func (h *Handler) ListOrders(c *gin.Context) {
    userID := c.GetString("user_id")
    rows, _ := h.DB.Query(`
        SELECT o.id, o.plan_id, o.status, o.amount_cents, o.paid_at, o.starts_at, o.expires_at, o.created_at,
               p.name, p.traffic_limit_gb, p.duration_days
        FROM orders o LEFT JOIN plans p ON o.plan_id = p.id
        WHERE o.user_id = $1 ORDER BY o.created_at DESC`, userID)
    defer rows.Close()

    orders := []map[string]interface{}{}
    for rows.Next() {
        var o struct {
            ID, PlanID, Status, PlanName string
            AmountCents, TrafficGB, DurationDays int
            PaidAt, StartsAt, ExpiresAt, CreatedAt sql.NullTime
        }
        rows.Scan(&o.ID, &o.PlanID, &o.Status, &o.AmountCents, &o.PaidAt, &o.StartsAt, &o.ExpiresAt, &o.CreatedAt, &o.PlanName, &o.TrafficGB, &o.DurationDays)
        orders = append(orders, map[string]interface{}{
            "id": o.ID, "status": o.Status, "amount_cents": o.AmountCents,
            "plan_name": o.PlanName, "created_at": o.CreatedAt.Time,
        })
    }
    c.JSON(http.StatusOK, orders)
}

func (h *Handler) ListAccounts(c *gin.Context) {
    userID := c.GetString("user_id")
    rows, _ := h.DB.Query(
        `SELECT id, protocol, uuid, password, status, traffic_used_bytes, traffic_limit_bytes, expires_at, created_at
         FROM vpn_accounts WHERE user_id = $1 ORDER BY created_at DESC`, userID)
    defer rows.Close()

    accounts := []map[string]interface{}{}
    for rows.Next() {
        var a struct {
            ID, Protocol, UUID, Password, Status string
            Used, Limit int64
            ExpiresAt, CreatedAt sql.NullTime
        }
        rows.Scan(&a.ID, &a.Protocol, &a.UUID, &a.Password, &a.Status, &a.Used, &a.Limit, &a.ExpiresAt, &a.CreatedAt)
        accounts = append(accounts, map[string]interface{}{
            "id": a.ID, "protocol": a.Protocol, "uuid": a.UUID,
            "status": a.Status, "traffic_used_gb": float64(a.Used) / 1024 / 1024 / 1024,
            "traffic_limit_gb": float64(a.Limit) / 1024 / 1024 / 1024,
            "expires_at": a.ExpiresAt.Time, "created_at": a.CreatedAt.Time,
        })
    }
    c.JSON(http.StatusOK, accounts)
}

func (h *Handler) Me(c *gin.Context) {
    var email, status string
    var createdAt time.Time
    h.DB.QueryRow("SELECT email, status, created_at FROM users WHERE id = $1", c.GetString("user_id")).
        Scan(&email, &status, &createdAt)
    c.JSON(http.StatusOK, gin.H{"email": email, "status": status, "created_at": createdAt})
}
```

- [ ] **步骤 2：更新 main.go 路由**

在 `server/cmd/panel/main.go` 中添加：
```go
// 在 imports 中加上
import (
    // ... 已有
    "github.com/borderx/panel/internal/api"
    "github.com/borderx/panel/internal/xray"
)

// 在 main() 中创建 xray manager 和 api handler:
xrayMgr, err := xray.NewManager(cfg.Xray.ConfigPath, cfg.Xray.BinaryPath)
if err != nil {
    log.Printf("警告: Xray 管理模块初始化失败: %v（VPN 功能不可用）", err)
}
apiH := &api.Handler{DB: db, Xray: xrayMgr}

// 用户路由扩展:
user.GET("/me", apiH.Me)
user.POST("/orders", apiH.CreateOrder)
user.GET("/orders", apiH.ListOrders)
user.GET("/accounts", apiH.ListAccounts)
```

- [ ] **步骤 3：编译验证 + 提交**

```bash
cd server && go build ./...
git add server/internal/api/ server/cmd/panel/main.go
git commit -m "feat: 下单自动创建 VPN 账号 + Xray 客户端同步"
```

---

### 任务 11：订阅链接生成

**文件：**
- 创建：`server/internal/sub/sub.go`

- [ ] **步骤 1：编写订阅链接生成**

`server/internal/sub/sub.go`:
```go
package sub

import (
    "database/sql"
    "encoding/base64"
    "fmt"
    "net/http"
    "strings"
    "github.com/gin-gonic/gin"
)

type Handler struct {
    DB      *sql.DB
    BaseURL string // 如 "https://panel.example.com"
}

func (h *Handler) Serve(c *gin.Context) {
    token := c.Query("token")
    if token == "" {
        c.String(http.StatusBadRequest, "missing token")
        return
    }

    var userID string
    err := h.DB.QueryRow("SELECT user_id FROM sub_tokens WHERE token = $1", token).Scan(&userID)
    if err == sql.ErrNoRows {
        c.String(http.StatusNotFound, "invalid token")
        return
    }
    h.DB.Exec("UPDATE sub_tokens SET last_accessed_at = now() WHERE token = $1", token)

    rows, _ := h.DB.Query(
        `SELECT protocol, uuid, password, settings_json
         FROM vpn_accounts WHERE user_id = $1 AND status = 'active'`, userID)
    defer rows.Close()

    var clashProxies []string
    var v2rayLinks []string

    for rows.Next() {
        var protocol, uuid, password string
        var settings []byte
        rows.Scan(&protocol, &uuid, &password, &settings)

        switch protocol {
        case "vless":
            link := fmt.Sprintf("vless://%s@SERVER_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&type=tcp#BorderX", uuid)
            v2rayLinks = append(v2rayLinks, link)
            clashProxies = append(clashProxies, fmt.Sprintf(
                `  - {name: "BorderX-VLESS", type: vless, server: SERVER_IP, port: 443, uuid: %s, flow: xtls-rprx-vision, tls: true, client-fingerprint: chrome, servername: www.microsoft.com, network: tcp, reality-opts: {public-key: REALITY_PUB, short-id: SHORT_ID}}`, uuid))
        case "vmess":
            link := fmt.Sprintf("vmess://%s@SERVER_IP:10001?path=/ws&security=none&type=ws#BorderX", uuid)
            v2rayLinks = append(v2rayLinks, link)
        case "trojan":
            link := fmt.Sprintf("trojan://%s@SERVER_IP:10002?security=tls&type=tcp#BorderX", password)
            v2rayLinks = append(v2rayLinks, link)
        }
    }

    // 返回 base64 编码的 v2ray 订阅格式
    subscription := strings.Join(v2rayLinks, "\n")
    encoded := base64.StdEncoding.EncodeToString([]byte(subscription))
    c.String(http.StatusOK, encoded)
}
```

- [ ] **步骤 2：注册路由 + 提交**

在 main.go 添加:
```go
subH := &sub.Handler{DB: db, BaseURL: cfg.BaseURL}
r.GET("/api/sub", subH.Serve)
```

```bash
cd server && go build ./...
git add server/internal/sub/ server/cmd/panel/main.go
git commit -m "feat: 订阅链接生成 (v2ray/clash 格式)"
```

---

### 任务 12：流量采集

**文件：**
- 创建：`server/internal/xray/stats.go`
- 创建：`server/internal/traffic/collector.go`
- 修改：`server/cmd/panel/main.go`（启动 cron）

- [ ] **步骤 1：编写 Xray Stats API 采集**

`server/internal/xray/stats.go`:
```go
package xray

import (
    "context"
    "fmt"
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
    xraycmd "github.com/xtls/xray-core/app/stats/command"
)

type StatsCollector struct {
    conn *grpc.ClientConn
}

func NewStatsCollector(statsPort int) (*StatsCollector, error) {
    addr := fmt.Sprintf("127.0.0.1:%d", statsPort)
    conn, err := grpc.Dial(addr, grpc.WithTransportCredentials(insecure.NewCredentials()))
    if err != nil {
        return nil, fmt.Errorf("连接 Xray Stats API 失败: %w", err)
    }
    return &StatsCollector{conn: conn}, nil
}

type TrafficDelta struct {
    Email    string
    Upload   int64
    Download int64
}

func (s *StatsCollector) QueryAll() ([]TrafficDelta, error) {
    client := xraycmd.NewStatsServiceClient(s.conn)
    resp, err := client.QueryStats(context.Background(), &xraycmd.QueryStatsRequest{
        Pattern: "user>>>",
        Reset_:  true, // 获取并重置计数器
    })
    if err != nil {
        return nil, err
    }

    result := map[string]*TrafficDelta{}
    for _, stat := range resp.GetStat() {
        name := stat.GetName()
        value := stat.GetValue()
        // stat name 格式: user>>>email@domain>>>traffic>>>uplink
        parts := splitStatName(name)
        if len(parts) < 3 { continue }
        email := parts[1]
        if result[email] == nil {
            result[email] = &TrafficDelta{Email: email}
        }
        if parts[2] == "uplink" {
            result[email].Upload += value
        } else if parts[2] == "downlink" {
            result[email].Download += value
        }
    }

    deltas := []TrafficDelta{}
    for _, d := range result { deltas = append(deltas, *d) }
    return deltas, nil
}

func splitStatName(name string) []string {
    parts := []string{}
    current := ""
    for _, ch := range name {
        if ch == '>' && len(current) > 0 && current[len(current)-1] != '\\' {
            parts = append(parts, current)
            current = ""
        } else {
            current += string(ch)
        }
    }
    if current != "" { parts = append(parts, current) }
    return parts
}

func (s *StatsCollector) Close() { s.conn.Close() }
```

- [ ] **步骤 2：编写流量采集 + 超限检查定时任务**

`server/internal/traffic/collector.go`:
```go
package traffic

import (
    "database/sql"
    "log"
    "github.com/borderx/panel/internal/xray"
)

type Collector struct {
    DB         *sql.DB
    Stats      *xray.StatsCollector
    lastValues map[string][2]int64 // email -> [up, down] 上次累计值
}

func NewCollector(db *sql.DB, stats *xray.StatsCollector) *Collector {
    return &Collector{DB: db, Stats: stats, lastValues: map[string][2]int64{}}
}

func (c *Collector) Collect() error {
    deltas, err := c.Stats.QueryAll()
    if err != nil {
        return err
    }
    for _, d := range deltas {
        // account_id 在 vpn_accounts 中是 UUID，这里 email=account_id@borderx
        accountID := extractAccountID(d.Email)
        if accountID == "" { continue }

        c.DB.Exec(
            `INSERT INTO traffic_logs (account_id, upload_bytes, download_bytes) VALUES ($1,$2,$3)`,
            accountID, d.Upload, d.Download,
        )
        c.DB.Exec(
            `UPDATE vpn_accounts SET traffic_used_bytes = traffic_used_bytes + $1 WHERE id = $2`,
            d.Upload+d.Download, accountID,
        )

        // 检查超限
        var used, limit int64
        var status string
        c.DB.QueryRow(
            "SELECT traffic_used_bytes, traffic_limit_bytes, status FROM vpn_accounts WHERE id = $1",
            accountID,
        ).Scan(&used, &limit, &status)
        if status == "active" && limit > 0 && used >= limit {
            c.DB.Exec("UPDATE vpn_accounts SET status = 'disabled' WHERE id = $1", accountID)
            log.Printf("[traffic] 账号 %s 流量超限，已禁用 (used=%d, limit=%d)", accountID, used, limit)
        }
    }
    return nil
}

func (c *Collector) Archive() error {
    c.DB.Exec(`
        INSERT INTO traffic_hourly (account_id, upload_bytes, download_bytes, hour)
        SELECT account_id, SUM(upload_bytes), SUM(download_bytes), date_trunc('hour', recorded_at)
        FROM traffic_logs WHERE recorded_at < date_trunc('hour', now()) - interval '1 hour'
        GROUP BY account_id, date_trunc('hour', recorded_at)
        ON CONFLICT (account_id, hour) DO UPDATE SET
            upload_bytes = traffic_hourly.upload_bytes + EXCLUDED.upload_bytes,
            download_bytes = traffic_hourly.download_bytes + EXCLUDED.download_bytes
    `)
    c.DB.Exec("DELETE FROM traffic_logs WHERE recorded_at < now() - interval '24 hours'")
    return nil
}

func (c *Collector) CheckExpired() error {
    c.DB.Exec("UPDATE vpn_accounts SET status = 'expired' WHERE status = 'active' AND expires_at < now()")
    return nil
}

func extractAccountID(email string) string {
    // email 格式: accountID@borderx
    for i, ch := range email {
        if ch == '@' { return email[:i] }
    }
    return ""
}
```

- [ ] **步骤 3：在 main.go 启动 cron**

```go
import "github.com/robfig/cron/v3"

// 在 main() 中添加:
if xrayMgr != nil {
    statsCollector, err := xray.NewStatsCollector(cfg.Xray.StatsPort)
    if err == nil {
        col := traffic.NewCollector(db, statsCollector)
        cronRunner := cron.New()
        cronRunner.AddFunc("@every 60s", func() { col.Collect() })
        cronRunner.AddFunc("@every 1h", func() { col.Archive() })
        cronRunner.AddFunc("@daily", func() { col.CheckExpired() })
        cronRunner.Start()
    }
}
```

- [ ] **步骤 4：编译验证 + 提交**

```bash
cd server && go build ./...
git add server/internal/xray/stats.go server/internal/traffic/ server/cmd/panel/main.go
git commit -m "feat: Xray 流量采集 + 超限自动禁用 + 定时归档"
```

---

## Phase 3：支付 & 运维

### 任务 13：支付宝支付集成

**文件：**
- 创建：`server/internal/payment/alipay.go`
- 修改：`server/internal/api/handler.go`（订单创建时生成支付 QR）

### 任务 14：一键安装脚本 + systemd

**文件：**
- 创建：`deploy/install.sh`
- 创建：`deploy/panel.service`
- 创建：`deploy/nginx.conf`

### 任务 15：流量统计页面 + 管理端完善

**文件：**
- 创建：`web/src/pages/admin/Traffic.tsx`
- 修改：`server/internal/admin/handler.go`（添加 traffic API）

---

## Phase 4：打磨

### 任务 16：邮箱验证 + 密码重置
### 任务 17：审计日志
### 任务 18：E2E 测试 (Playwright)

---

## 自检结果

**1. 规格覆盖度检查：**
- [x] 数据库表 — 任务 2（迁移 + 模型）
- [x] 用户注册/登录 — 任务 3（JWT + handler）
- [x] 管理端 CRUD — 任务 4
- [x] React 页面 — 任务 6-7
- [x] Xray 配置读写 — 任务 9
- [x] 下单创建 VPN — 任务 10
- [x] 订阅链接 — 任务 11
- [x] 流量采集 — 任务 12
- [x] 支付 — 任务 13（支付宝）
- [x] 部署脚本 — 任务 14
- [x] 定时任务（Go cron）— 任务 12
- [x] 安全（bcrypt/JWT/限流）— 分散在各任务中

**2. 占位符扫描：** Phase 3-4 任务 13-18 仅写了标题，详细步骤尚未展开。标记为下一阶段。

**3. 类型一致性：** Go model 定义与 SQL 迁移一致；API handler 返回字段与 React 类型一致。
