package main

import (
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/borderx/panel/internal/admin"
	"github.com/borderx/panel/internal/api"
	"github.com/borderx/panel/internal/auth"
	"github.com/borderx/panel/internal/config"
	"github.com/borderx/panel/internal/store"
	"github.com/borderx/panel/internal/sub"
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
	adminH := &admin.Handler{DB: db}

	// Initialize Xray Manager (optional — skip if config file is missing)
	xrayMgr, err := xray.NewManager(cfg.Xray.ConfigPath)
	if err != nil {
		log.Printf("警告: Xray 管理模块初始化失败: %v（VPN 功能不可用）", err)
	}
	apiH := &api.Handler{DB: db, Xray: xrayMgr}
	subH := &sub.Handler{DB: db}

	gin.SetMode(cfg.Server.Mode)
	r := gin.Default()

	// ---- 公开路由 ----
	r.POST("/api/auth/register", authH.Register)
	r.POST("/api/auth/login", authH.Login)
	r.POST("/api/auth/admin-login", authH.AdminLogin)
	r.GET("/api/sub", subH.Serve)

	// ---- 用户路由 ----
	user := r.Group("/api")
	user.Use(jwtMgr.UserRequired())
	{
		user.GET("/plans", func(c *gin.Context) { adminH.ListPlans(c) })
		user.GET("/me", apiH.Me)
		user.POST("/orders", apiH.CreateOrder)
		user.GET("/orders", apiH.ListOrders)
		user.GET("/accounts", apiH.ListAccounts)
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
	}

	// ---- SPA fallback ----
	distFS, _ := fs.Sub(web.Dist, "dist")
	r.NoRoute(gin.WrapH(http.FileServer(http.FS(distFS))))

	log.Printf("BorderX Panel 启动在 :%d\n", cfg.Server.Port)
	r.Run(fmt.Sprintf(":%d", cfg.Server.Port))
}
