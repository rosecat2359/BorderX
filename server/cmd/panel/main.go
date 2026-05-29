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
	"github.com/borderx/panel/internal/auth"
	"github.com/borderx/panel/internal/config"
	"github.com/borderx/panel/internal/store"
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

	gin.SetMode("release")
	r := gin.Default()

	// ---- 公开路由 ----
	r.GET("/api/auth/setup", authH.SetupCheck)
	r.POST("/api/auth/setup", authH.Setup)
	r.POST("/api/auth/login", authH.Login)
	// Subscription endpoint (public, works by client ID)
	r.GET("/api/sub", func(c *gin.Context) {
		c.String(http.StatusOK, "subscription endpoint (TODO)")
	})

	// ---- 认证路由 ----
	api := r.Group("/api")
	api.Use(jwtMgr.Required())
	{
		// Nodes (placeholder — will be replaced in task 17)
		api.GET("/nodes", func(c *gin.Context) { c.JSON(http.StatusOK, []any{}) })
		api.GET("/nodes/:id", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{}) })
		api.POST("/nodes", func(c *gin.Context) { c.JSON(http.StatusCreated, gin.H{"id": "new"}) })
		api.PUT("/nodes/:id", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"message": "ok"}) })
		api.DELETE("/nodes/:id", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"message": "ok"}) })
		api.POST("/nodes/:id/test", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"success": true}) })
		api.GET("/nodes/:id/status", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"status": "unknown"}) })

		// Inbounds (placeholder — will be replaced in task 10)
		api.GET("/inbounds", func(c *gin.Context) { c.JSON(http.StatusOK, []any{}) })
		api.POST("/inbounds", func(c *gin.Context) { c.JSON(http.StatusCreated, gin.H{"id": "new"}) })
		api.PUT("/inbounds/:id", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"message": "ok"}) })
		api.DELETE("/inbounds/:id", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"message": "ok"}) })
		api.POST("/inbounds/:id/deploy", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"message": "deployed"}) })
		api.GET("/inbounds/templates", func(c *gin.Context) { c.JSON(http.StatusOK, []any{}) })

		// Clients (placeholder — will be replaced in task 11)
		api.GET("/clients", func(c *gin.Context) { c.JSON(http.StatusOK, []any{}) })
		api.POST("/clients", func(c *gin.Context) { c.JSON(http.StatusCreated, gin.H{"id": "new"}) })
		api.PUT("/clients/:id", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"message": "ok"}) })
		api.DELETE("/clients/:id", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"message": "ok"}) })
		api.POST("/clients/:id/reset", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"uuid": "new-uuid"}) })
		api.PUT("/clients/:id/inbounds", func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"message": "ok"}) })

		// Traffic (placeholder — will be replaced in task 14)
		api.GET("/traffic/overview", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{"node_count": 0, "active_clients": 0, "today_up_bytes": 0, "today_down_bytes": 0})
		})
		api.GET("/traffic/clients/:id", func(c *gin.Context) { c.JSON(http.StatusOK, []any{}) })
		api.GET("/traffic/nodes/:id", func(c *gin.Context) { c.JSON(http.StatusOK, []any{}) })

		// System
		api.GET("/system/info", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{"version": "2.0.0", "os": runtime.GOOS})
		})
		api.PUT("/system/password", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{"message": "password updated (TODO)"})
		})
		api.POST("/system/backup", func(c *gin.Context) {
			c.File(cfg.DBPath())
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
