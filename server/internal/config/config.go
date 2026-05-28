package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// Config holds all configuration for the BorderX Panel server.
type Config struct {
	Server   ServerConfig   `yaml:"server"`
	Database DatabaseConfig `yaml:"database"`
	JWT      JWTConfig      `yaml:"jwt"`
	SMTP     SMTPConfig     `yaml:"smtp"`
	Xray     XrayConfig     `yaml:"xray"`
}

// ServerConfig holds HTTP server settings.
type ServerConfig struct {
	Port int    `yaml:"port"`
	Mode string `yaml:"mode"`
}

// DatabaseConfig holds PostgreSQL connection settings.
type DatabaseConfig struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	User     string `yaml:"user"`
	Password string `yaml:"password"`
	DBName   string `yaml:"dbname"`
	SSLMode  string `yaml:"sslmode"`
}

// JWTConfig holds JWT authentication settings.
type JWTConfig struct {
	Secret     string `yaml:"secret"`
	ExpireHour int    `yaml:"expire_hour"`
}

// SMTPConfig holds SMTP mail server settings.
type SMTPConfig struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	Username string `yaml:"username"`
	Password string `yaml:"password"`
	From     string `yaml:"from"`
}

// XrayConfig holds Xray control settings.
type XrayConfig struct {
	ConfigPath string `yaml:"config_path"`
	StatsPort  int    `yaml:"stats_port"`
	BinaryPath string `yaml:"binary_path"`
}

// Load reads a YAML config file from the given path, applies defaults, and
// returns the parsed Config. It returns an error if the file cannot be read
// or parsed.
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

// MustLoad calls Load and panics on error. Useful for startup where invalid
// configuration is a fatal condition.
func MustLoad(path string) *Config {
	cfg, err := Load(path)
	if err != nil {
		panic(fmt.Sprintf("加载配置失败: %v", err))
	}
	return cfg
}

// DSN returns a PostgreSQL connection string built from the database
// configuration fields.
func (c *Config) DSN() string {
	return fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
		c.Database.Host,
		c.Database.Port,
		c.Database.User,
		c.Database.Password,
		c.Database.DBName,
		c.Database.SSLMode,
	)
}

// applyDefaults fills in sensible default values for any fields that were not
// set in the YAML configuration file.
func applyDefaults(cfg *Config) {
	if cfg.Server.Port == 0 {
		cfg.Server.Port = 8080
	}
	if cfg.Server.Mode == "" {
		cfg.Server.Mode = "release"
	}
	if cfg.Database.Port == 0 {
		cfg.Database.Port = 5432
	}
	if cfg.Database.SSLMode == "" {
		cfg.Database.SSLMode = "disable"
	}
	if cfg.JWT.ExpireHour == 0 {
		cfg.JWT.ExpireHour = 24
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
	if cfg.SMTP.Port == 0 {
		cfg.SMTP.Port = 587
	}
}
