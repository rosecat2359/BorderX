package xray

import (
	"encoding/json"
	"fmt"
	"os"
)

// XrayConfig represents the top-level Xray JSON configuration.
type XrayConfig struct {
	Log       json.RawMessage `json:"log,omitempty"`
	DNS       json.RawMessage `json:"dns,omitempty"`
	Inbounds  []Inbound       `json:"inbounds"`
	Outbounds json.RawMessage `json:"outbounds,omitempty"`
	Routing   json.RawMessage `json:"routing,omitempty"`
	Stats     json.RawMessage `json:"stats,omitempty"`
	API       json.RawMessage `json:"api,omitempty"`
	Policy    json.RawMessage `json:"policy,omitempty"`
}

// Inbound represents an inbound proxy configuration.
type Inbound struct {
	Tag            string          `json:"tag"`
	Port           int             `json:"port"`
	Protocol       string          `json:"protocol"`
	Settings       json.RawMessage `json:"settings"`
	StreamSettings json.RawMessage `json:"streamSettings,omitempty"`
	Sniffing       json.RawMessage `json:"sniffing,omitempty"`
	Listen         string          `json:"listen,omitempty"`
}

// VLESSClient represents a VLESS client entry.
type VLESSClient struct {
	ID    string `json:"id"`
	Flow  string `json:"flow"`
	Email string `json:"email"`
}

// VMessClient represents a VMess client entry.
type VMessClient struct {
	ID      string `json:"id"`
	AlterID int    `json:"alterId"`
	Email   string `json:"email"`
}

// TrojanClient represents a Trojan client entry.
type TrojanClient struct {
	Password string `json:"password"`
	Email    string `json:"email"`
}

// Manager handles reading and modifying the Xray config file.
type Manager struct {
	configPath string
	config     *XrayConfig
}

// NewManager creates a Manager by reading and parsing the config at configPath.
func NewManager(configPath string) (*Manager, error) {
	m := &Manager{configPath: configPath}
	if err := m.Reload(); err != nil {
		return nil, err
	}
	return m, nil
}

// Reload reads and parses config.json.
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

// save writes config atomically and reloads the service.
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
	return ReloadService()
}

// AddClient adds a client to the inbound with the given tag.
// email 参数同时作为 Xray 客户端标识.
func (m *Manager) AddClient(tag, protocol, email, id, password string) error {
	for i := range m.config.Inbounds {
		in := &m.config.Inbounds[i]
		if in.Tag != tag {
			continue
		}
		switch protocol {
		case "vless":
			var wrapper struct {
				Clients    []VLESSClient `json:"clients"`
				Decryption string        `json:"decryption"`
			}
			json.Unmarshal(in.Settings, &wrapper)
			wrapper.Clients = append(wrapper.Clients, VLESSClient{ID: id, Flow: "xtls-rprx-vision", Email: email})
			wrapper.Decryption = "none"
			newSettings, _ := json.Marshal(wrapper)
			in.Settings = newSettings
		case "vmess":
			var wrapper struct {
				Clients []VMessClient `json:"clients"`
			}
			json.Unmarshal(in.Settings, &wrapper)
			wrapper.Clients = append(wrapper.Clients, VMessClient{ID: id, AlterID: 0, Email: email})
			newSettings, _ := json.Marshal(wrapper)
			in.Settings = newSettings
		case "trojan":
			var wrapper struct {
				Clients []TrojanClient `json:"clients"`
			}
			json.Unmarshal(in.Settings, &wrapper)
			wrapper.Clients = append(wrapper.Clients, TrojanClient{Password: password, Email: email})
			newSettings, _ := json.Marshal(wrapper)
			in.Settings = newSettings
		}
	}
	return m.save()
}

// RemoveClient removes the client matching the given email from the inbound with the given tag.
func (m *Manager) RemoveClient(tag, email string) error {
	for i := range m.config.Inbounds {
		in := &m.config.Inbounds[i]
		if in.Tag != tag {
			continue
		}
		var wrapper struct {
			Clients    []map[string]interface{} `json:"clients"`
			Password   string                   `json:"password,omitempty"`
			Decryption string                   `json:"decryption,omitempty"`
		}
		json.Unmarshal(in.Settings, &wrapper)
		filtered := []map[string]interface{}{}
		for _, c := range wrapper.Clients {
			if c["email"] != email {
				filtered = append(filtered, c)
			}
		}
		wrapper.Clients = filtered
		data, _ := json.Marshal(wrapper)
		in.Settings = data
	}
	return m.save()
}

// Config returns the parsed config (read-only, for reading inbound info).
func (m *Manager) Config() *XrayConfig {
	return m.config
}
