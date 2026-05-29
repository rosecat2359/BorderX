// BorderX 轻量级 VPN 运维管理面板 — 单二进制入口。
// 启动 HTTP API 服务，内嵌 React 前端，SQLite 数据持久化。
package main

import (
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"runtime"

	"github.com/gin-gonic/gin"
	"github.com/robfig/cron/v3"
	"golang.org/x/crypto/bcrypt"

	"github.com/borderx/panel/internal/auth"
	"github.com/borderx/panel/internal/client"
	"github.com/borderx/panel/internal/config"
	"github.com/borderx/panel/internal/inbound"
	"github.com/borderx/panel/internal/node"
	"github.com/borderx/panel/internal/store"
	"github.com/borderx/panel/internal/sub"
	"github.com/borderx/panel/internal/traffic"
	"github.com/borderx/panel/internal/xray"
	"github.com/borderx/panel/web"
)

func main() {
	cfgPath := flag.String("config", "", "配置文件路径（可选）")
	dataDir := flag.String("data-dir", "./data", "数据目录")
	flag.Parse()

	var cfg *config.Config
	if *cfgPath != "" {
		cfg = config.MustLoad(*cfgPath)
	} else {
		cfg = &config.Config{
			Server: config.ServerConfig{Port: 8080, Host: "0.0.0.0"},
			JWT:    config.JWTConfig{ExpireHour: 72},
			Data:   config.DataConfig{Dir: *dataDir},
			Xray:   config.XrayConfig{
				ConfigPath: "/usr/local/etc/xray/config.json",
				StatsPort:  10085,
				BinaryPath: "/usr/local/bin/xray",
			},
		}
	}

	if err := os.MkdirAll(cfg.Data.Dir, 0700); err != nil {
		log.Fatalf("创建数据目录失败: %v", err)
	}

	db, err := store.Connect(cfg.DBPath())
	if err != nil {
		log.Fatalf("数据库连接失败: %v", err)
	}
	defer db.Close()

	if err := store.Migrate(db); err != nil {
		log.Fatalf("数据库迁移失败: %v", err)
	}

	jwtMgr := auth.NewJWTManager(cfg.JWT.Secret, cfg.JWT.ExpireHour)
	authH := &auth.Handler{DB: db, JWT: jwtMgr}

	// Initialize Xray Manager (optional — may fail if xray binary not found)
	xrayMgr, xrayErr := xray.NewManager(cfg.Xray.ConfigPath)
	if xrayErr != nil {
		log.Printf("警告: Xray 管理模块初始化失败: %v（VPN 功能不可用）", xrayErr)
	}

	// Create handlers
	inboundH := &inbound.Handler{DB: db, Xray: xrayMgr}
	clientH := &client.Handler{DB: db, Xray: xrayMgr}
	subH := &sub.Handler{DB: db}
	nodeSSH := node.NewSSHManager()
	nodeH := &node.Handler{DB: db, SSH: nodeSSH}

	// Start traffic collector if Xray is available
	if xrayMgr != nil {
		statsCollector, statsErr := xray.NewStatsCollector(cfg.Xray.StatsPort)
		if statsErr != nil {
			log.Printf("警告: 流量采集初始化失败: %v", statsErr)
		} else {
			col := traffic.NewCollector(db, statsCollector)
			cronRunner := cron.New()
			cronRunner.AddFunc("@every 60s", func() { col.Collect() })
			cronRunner.AddFunc("@daily", func() { col.Archive(); col.CheckExpired() })
			cronRunner.Start()
			defer cronRunner.Stop()
			log.Println("流量采集 + 定时任务已启动")
		}
	}

	gin.SetMode("release")
	r := gin.Default()

	// ---- 公开路由 ----
	r.GET("/api/auth/setup", authH.SetupCheck)
	r.POST("/api/auth/setup", authH.Setup)
	r.POST("/api/auth/login", authH.Login)
	// Subscription endpoint (public, works by client ID)
	r.GET("/api/sub", subH.Serve)

	// ---- 认证路由 ----
	api := r.Group("/api")
	api.Use(jwtMgr.Required())
	{
		// Inbounds
		api.GET("/inbounds", inboundH.List)
		api.POST("/inbounds", inboundH.Create)
		api.PUT("/inbounds/:id", inboundH.Update)
		api.DELETE("/inbounds/:id", inboundH.Delete)
		api.POST("/inbounds/:id/deploy", inboundH.Deploy)
		api.GET("/inbounds/templates", inboundH.Templates)

		// Clients
		api.GET("/clients", clientH.List)
		api.POST("/clients", clientH.Create)
		api.PUT("/clients/:id", clientH.Update)
		api.DELETE("/clients/:id", clientH.Delete)
		api.POST("/clients/:id/reset", clientH.Reset)
		api.PUT("/clients/:id/inbounds", clientH.UpdateInbounds)

		// Nodes
		api.GET("/nodes", nodeH.List)
		api.GET("/nodes/:id", nodeH.Get)
		api.POST("/nodes", nodeH.Create)
		api.PUT("/nodes/:id", nodeH.Update)
		api.DELETE("/nodes/:id", nodeH.Delete)
		api.POST("/nodes/:id/test", nodeH.Test)
		api.GET("/nodes/:id/status", nodeH.Status)

		// Traffic
		api.GET("/traffic/overview", func(c *gin.Context) {
			var nodeCount, activeClients int
			var todayUp, todayDown int64
			db.QueryRow("SELECT count(*) FROM nodes WHERE is_active=1").Scan(&nodeCount)
			db.QueryRow("SELECT count(*) FROM clients WHERE is_active=1").Scan(&activeClients)
			db.QueryRow("SELECT COALESCE(SUM(up_bytes),0) FROM traffic_hourly WHERE hour >= datetime('now','start of day')").Scan(&todayUp)
			db.QueryRow("SELECT COALESCE(SUM(down_bytes),0) FROM traffic_hourly WHERE hour >= datetime('now','start of day')").Scan(&todayDown)
			c.JSON(http.StatusOK, gin.H{
				"node_count": nodeCount, "active_clients": activeClients,
				"today_up_bytes": todayUp, "today_down_bytes": todayDown,
			})
		})
		api.GET("/traffic/clients/:id", func(c *gin.Context) {
			rows, _ := db.Query(
				"SELECT up_bytes, down_bytes, hour FROM traffic_hourly WHERE client_id=? AND hour >= datetime('now','-7 days') ORDER BY hour",
				c.Param("id"),
			)
			if rows == nil {
				c.JSON(http.StatusOK, []any{})
				return
			}
			defer rows.Close()
			var result []gin.H
			for rows.Next() {
				var up, down int64
				var hour string
				rows.Scan(&up, &down, &hour)
				result = append(result, gin.H{"up_bytes": up, "down_bytes": down, "hour": hour})
			}
			c.JSON(http.StatusOK, result)
		})

		// System
		api.GET("/system/info", func(c *gin.Context) {
			var nodeCount, clientCount, inboundCount int
			var dbSize int64
			db.QueryRow("SELECT count(*) FROM nodes WHERE is_active=1").Scan(&nodeCount)
			db.QueryRow("SELECT count(*) FROM clients WHERE is_active=1").Scan(&clientCount)
			db.QueryRow("SELECT count(*) FROM inbounds WHERE is_active=1").Scan(&inboundCount)
			if fi, err := os.Stat(cfg.DBPath()); err == nil {
				dbSize = fi.Size()
			}
			c.JSON(http.StatusOK, gin.H{
				"version":       "2.0.0",
				"os":            runtime.GOOS,
				"node_count":    nodeCount,
				"client_count":  clientCount,
				"inbound_count": inboundCount,
				"db_size":       dbSize,
			})
		})
		api.PUT("/system/password", func(c *gin.Context) {
			var req struct {
				Password string `json:"password" binding:"required,min=6"`
			}
			if err := c.ShouldBindJSON(&req); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "密码至少6位"})
				return
			}
			hash, _ := bcrypt.GenerateFromPassword([]byte(req.Password), 12)
			db.Exec("UPDATE admin SET password=?", string(hash))
			c.JSON(http.StatusOK, gin.H{"message": "密码已更新"})
		})
		api.POST("/system/backup", func(c *gin.Context) {
			c.Header("Content-Disposition", "attachment; filename=borderx-backup.db")
			c.File(cfg.DBPath())
		})
		api.POST("/system/restore", func(c *gin.Context) {
			file, err := c.FormFile("file")
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "请上传备份文件"})
				return
			}
			tmpPath := cfg.DBPath() + ".restore"
			if err := c.SaveUploadedFile(file, tmpPath); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "保存失败"})
				return
			}
			f, err := os.Open(tmpPath)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "读取失败"})
				return
			}
			header := make([]byte, 16)
			f.Read(header)
			f.Close()
			if string(header) != "SQLite format 3\x00" {
				os.Remove(tmpPath)
				c.JSON(http.StatusBadRequest, gin.H{"error": "不是有效的 SQLite 数据库文件"})
				return
			}
			db.Close()
			os.Rename(tmpPath, cfg.DBPath())
			c.JSON(http.StatusOK, gin.H{"message": "数据库已恢复，面板即将重启"})
			go func() { os.Exit(0) }()
		})
	}

	// ---- SPA fallback ----
	distFS, _ := fs.Sub(web.Dist, "dist")
	fileServer := http.FileServer(http.FS(distFS))
	r.NoRoute(func(c *gin.Context) {
		path := c.Request.URL.Path
		if path != "/" {
			f, err := distFS.Open(path[1:])
			if err != nil {
				c.Request.URL.Path = "/"
				fileServer.ServeHTTP(c.Writer, c.Request)
				return
			}
			f.Close()
		}
		fileServer.ServeHTTP(c.Writer, c.Request)
	})

	addr := fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Server.Port)
	log.Printf("BorderX Panel v2.0.0 启动: http://%s", addr)
	log.Printf("数据目录: %s", cfg.Data.Dir)
	log.Printf("数据库: %s", cfg.DBPath())
	if err := r.Run(addr); err != nil {
		log.Fatalf("启动失败: %v", err)
	}
}
