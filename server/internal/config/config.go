package config

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server ServerConfig `yaml:"server"`
	JWT    JWTConfig    `yaml:"jwt"`
	Xray   XrayConfig   `yaml:"xray"`
	Data   DataConfig   `yaml:"data"`
}

type ServerConfig struct {
	Port int    `yaml:"port"`
	Host string `yaml:"host"`
}

type JWTConfig struct {
	Secret     string `yaml:"secret"`
	ExpireHour int    `yaml:"expire_hour"`
}

type XrayConfig struct {
	ConfigPath string `yaml:"config_path"`
	StatsPort  int    `yaml:"stats_port"`
	BinaryPath string `yaml:"binary_path"`
}

type DataConfig struct {
	Dir string `yaml:"dir"`
}

func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("读取配置文件失败: %w", err)
	}
	cfg := &Config{}
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("解析配置文件失败: %w", err)
	}
	applyDefaults(cfg)
	return cfg, nil
}

func MustLoad(path string) *Config {
	cfg, err := Load(path)
	if err != nil {
		panic(fmt.Sprintf("加载配置失败: %v", err))
	}
	return cfg
}

func (c *Config) DBPath() string {
	return filepath.Join(c.Data.Dir, "borderx.db")
}

func applyDefaults(cfg *Config) {
	if cfg.Server.Port == 0 {
		cfg.Server.Port = 8080
	}
	if cfg.Server.Host == "" {
		cfg.Server.Host = "0.0.0.0"
	}
	if cfg.JWT.ExpireHour == 0 {
		cfg.JWT.ExpireHour = 72
	}
	if cfg.JWT.Secret == "" {
		cfg.JWT.Secret = randomSecret()
	}
	if cfg.Data.Dir == "" {
		cfg.Data.Dir = "./data"
	}
	if cfg.Xray.ConfigPath == "" {
		cfg.Xray.ConfigPath = "/usr/local/etc/xray/config.json"
	}
	if cfg.Xray.StatsPort == 0 {
		cfg.Xray.StatsPort = 10085
	}
	if cfg.Xray.BinaryPath == "" {
		cfg.Xray.BinaryPath = "/usr/local/bin/xray"
	}
}

func randomSecret() string {
	b := make([]byte, 32)
	f, err := os.Open("/dev/urandom")
	if err != nil {
		for i := range b {
			b[i] = byte(i*7%256 + 1)
		}
	} else {
		defer f.Close()
		f.Read(b)
	}
	return fmt.Sprintf("%x", b)
}
