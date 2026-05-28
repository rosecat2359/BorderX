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
