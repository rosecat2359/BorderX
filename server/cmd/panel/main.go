package main

import (
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/robfig/cron/v3"
	"github.com/borderx/panel/internal/admin"
	"github.com/borderx/panel/internal/api"
	"github.com/borderx/panel/internal/auth"
	"github.com/borderx/panel/internal/config"
	"github.com/borderx/panel/internal/mail"
	"github.com/borderx/panel/internal/payment"
	"github.com/borderx/panel/internal/store"
	"github.com/borderx/panel/internal/sub"
	"github.com/borderx/panel/internal/traffic"
	"github.com/borderx/panel/internal/xray"
	"github.com/borderx/panel/web"
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

	jwtMgr := auth.NewJWTManager(cfg.JWT.Secret, cfg.JWT.ExpireHour)
	authH := &auth.Handler{DB: db, JWT: jwtMgr}

	// Initialize MailSender (optional — skip if SMTP host is empty)
	var mailSender *mail.Sender
	if cfg.SMTP.Host != "" {
		mailSender = mail.NewSender(cfg.SMTP.Host, cfg.SMTP.Port, cfg.SMTP.Username, cfg.SMTP.Password, cfg.SMTP.From)
	}
	authH.MailSender = mailSender

	adminH := &admin.Handler{DB: db}

	// Initialize Xray Manager (optional — skip if config file is missing)
	xrayMgr, err := xray.NewManager(cfg.Xray.ConfigPath)
	if err != nil {
		log.Printf("警告: Xray 管理模块初始化失败: %v（VPN 功能不可用）", err)
	}

	// Initialize Alipay Client (optional — skip if AppID is empty)
	var alipayClient *payment.AlipayClient
	if cfg.Alipay.AppID != "" {
		notifyURL := cfg.Alipay.NotifyDomain + "/api/payment/alipay/notify"
		var alipayErr error
		alipayClient, alipayErr = payment.NewAlipayClient(payment.AlipayConfig{
			AppID:        cfg.Alipay.AppID,
			PrivateKey:   cfg.Alipay.PrivateKey,
			AlipayPubKey: cfg.Alipay.AlipayPubKey,
			NotifyURL:    notifyURL,
		})
		if alipayErr != nil {
			log.Printf("警告: 支付宝初始化失败: %v", alipayErr)
			alipayClient = nil
		} else {
			log.Println("支付宝支付模块已启用")
		}
	}

	// Build API handler (now with optional Alipay client)
	apiH := &api.Handler{DB: db, Xray: xrayMgr, Alipay: alipayClient}
	subH := &sub.Handler{DB: db}

	// CreateAccount callback: provisions a VPN account + Xray config after
	// a successful Alipay payment notification.
	createAccountFn := func(userID, orderID, protocol string) error {
		var planID string
		var durationDays, trafficGB int
		if err := db.QueryRow(
			"SELECT plan_id, (SELECT duration_days FROM plans WHERE id=orders.plan_id), (SELECT traffic_limit_gb FROM plans WHERE id=orders.plan_id) FROM orders WHERE id=$1",
			orderID,
		).Scan(&planID, &durationDays, &trafficGB); err != nil {
			return fmt.Errorf("查询计划信息失败: %w", err)
		}

		now := time.Now()
		expiresAt := now.Add(time.Duration(durationDays) * 24 * time.Hour)

		// Update order dates
		db.Exec("UPDATE orders SET starts_at=$1, expires_at=$2 WHERE id=$3", now, expiresAt, orderID)

		vpnUUID := uuid.New().String()
		password := ""
		if protocol == "trojan" {
			password = uuid.New().String()[:16]
		}

		var accountID string
		if err := db.QueryRow(
			`INSERT INTO vpn_accounts (user_id, order_id, protocol, uuid, password, traffic_limit_bytes, expires_at)
			 VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id`,
			userID, orderID, protocol, vpnUUID, password,
			int64(trafficGB)*1024*1024*1024, expiresAt,
		).Scan(&accountID); err != nil {
			return fmt.Errorf("创建 VPN 账号失败: %w", err)
		}

		// Write Xray config
		if xrayMgr != nil {
			tag := map[string]string{
				"vless":  "vless-reality",
				"vmess":  "vmess-ws",
				"trojan": "trojan-tcp",
			}[protocol]
			email := accountID + "@borderx"
			if err := xrayMgr.AddClient(tag, protocol, email, vpnUUID, password); err != nil {
				log.Printf("[payment] 写入 Xray 配置失败 (account=%s): %v", accountID, err)
			}
		}

		payment.EnsureSubToken(db, userID)
		return nil
	}

	// Build payment handler
	payH := &payment.Handler{
		DB:            db,
		Alipay:        alipayClient,
		CreateAccount: createAccountFn,
	}

	// 流量采集（需要 Xray 运行）
	statsCollector, statsErr := xray.NewStatsCollector(cfg.Xray.StatsPort)
	if statsErr != nil {
		log.Printf("警告: 流量采集模块初始化失败: %v", statsErr)
	}
	if statsCollector != nil {
		col := traffic.NewCollector(db, statsCollector)
		cronRunner := cron.New()
		cronRunner.AddFunc("@every 60s", func() { col.Collect() })
		cronRunner.AddFunc("@every 1h", func() { col.Archive() })
		cronRunner.AddFunc("@daily", func() { col.CheckExpired() })
		cronRunner.Start()
		defer cronRunner.Stop()
		log.Println("流量采集 + 定时任务已启动")
	}

	gin.SetMode(cfg.Server.Mode)
	r := gin.Default()

	// ---- 公开路由 ----
	r.POST("/api/auth/register", authH.Register)
	r.POST("/api/auth/login", authH.Login)
	r.POST("/api/auth/admin-login", authH.AdminLogin)
	r.GET("/api/auth/verify-email", authH.VerifyEmail)
	r.POST("/api/auth/forgot-password", authH.ForgotPassword)
	r.POST("/api/auth/reset-password", authH.ResetPassword)
	r.GET("/api/sub", subH.Serve)
	r.POST("/api/payment/alipay/notify", payH.AlipayNotify)

	// ---- 用户路由 ----
	user := r.Group("/api")
	user.Use(jwtMgr.UserRequired())
	{
		user.GET("/plans", func(c *gin.Context) { adminH.ListPlans(c) })
		user.GET("/me", apiH.Me)
		user.POST("/orders", apiH.CreateOrder)
		user.GET("/orders", apiH.ListOrders)
		user.GET("/orders/:id/status", payH.GetOrderStatus)
		user.GET("/accounts", apiH.ListAccounts)
		user.POST("/send-verify-email", authH.SendVerifyEmail)
	}

	// ---- 管理路由 ----
	adm := r.Group("/api/admin")
	adm.Use(jwtMgr.AdminRequired())
	{
		adm.GET("/dashboard", adminH.Dashboard)
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
		adm.GET("/traffic/summary", adminH.TrafficSummary)
		adm.GET("/traffic/accounts", adminH.TrafficByAccount)
		adm.GET("/traffic/timeline", adminH.TrafficTimeline)
		adm.GET("/audit-logs", adminH.ListAuditLogs)
	}

	// ---- SPA fallback ----
	distFS, _ := fs.Sub(web.Dist, "dist")
	fileServer := http.FileServer(http.FS(distFS))
	r.NoRoute(func(c *gin.Context) {
		// Try to serve the file; if 404, fall back to index.html for SPA routing
		path := c.Request.URL.Path
		if path != "/" {
			// Check if file exists
			f, err := distFS.Open(path[1:]) // strip leading /
			if err != nil {
				// Not a real file — serve index.html for SPA client-side routing
				c.Request.URL.Path = "/"
				fileServer.ServeHTTP(c.Writer, c.Request)
				return
			}
			f.Close()
		}
		fileServer.ServeHTTP(c.Writer, c.Request)
	})

	log.Printf("BorderX Panel 启动在 :%d\n", cfg.Server.Port)
	r.Run(fmt.Sprintf(":%d", cfg.Server.Port))
}
