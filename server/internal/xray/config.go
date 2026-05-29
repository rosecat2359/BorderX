package xray

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"runtime"
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
	return reloadXray()
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

// EnsureInbound makes sure an inbound with the given tag exists.
// If it already exists, nothing is changed. Otherwise it is appended.
func (m *Manager) EnsureInbound(tag, protocol string, port int, settingsJSON, streamJSON string) error {
	for i := range m.config.Inbounds {
		if m.config.Inbounds[i].Tag == tag {
			return nil // already exists
		}
	}
	in := Inbound{
		Tag:            tag,
		Port:           port,
		Protocol:       protocol,
		Listen:         "0.0.0.0",
		Settings:       json.RawMessage(settingsJSON),
		StreamSettings: json.RawMessage(streamJSON),
		Sniffing:       json.RawMessage(`{"enabled":true,"destOverride":["http","tls"]}`),
	}
	m.config.Inbounds = append(m.config.Inbounds, in)
	return m.save()
}

// RemoveInbound removes the inbound with the given tag.
func (m *Manager) RemoveInbound(tag string) error {
	filtered := make([]Inbound, 0, len(m.config.Inbounds))
	for _, in := range m.config.Inbounds {
		if in.Tag != tag {
			filtered = append(filtered, in)
		}
	}
	m.config.Inbounds = filtered
	return m.save()
}

// SyncClients replaces ALL clients in the given inbound with the provided list.
// For vless: each entry uses uuid and email. flow defaults to "xtls-rprx-vision".
// For vmess: each entry uses uuid and email, alterId=0.
// For trojan: each entry uses password (from passwords slice) and email.
func (m *Manager) SyncClients(tag, protocol string, uuids, emails, passwords []string) error {
	for i := range m.config.Inbounds {
		in := &m.config.Inbounds[i]
		if in.Tag != tag {
			continue
		}
		switch protocol {
		case "vless":
			clients := make([]VLESSClient, len(uuids))
			for j, uid := range uuids {
				clients[j] = VLESSClient{ID: uid, Flow: "xtls-rprx-vision", Email: emails[j]}
			}
			data, _ := json.Marshal(map[string]interface{}{"clients": clients, "decryption": "none"})
			in.Settings = data
		case "vmess":
			clients := make([]VMessClient, len(uuids))
			for j, uid := range uuids {
				clients[j] = VMessClient{ID: uid, AlterID: 0, Email: emails[j]}
			}
			data, _ := json.Marshal(map[string]interface{}{"clients": clients})
			in.Settings = data
		case "trojan":
			clients := make([]TrojanClient, len(passwords))
			for j, pw := range passwords {
				clients[j] = TrojanClient{Password: pw, Email: emails[j]}
			}
			data, _ := json.Marshal(map[string]interface{}{"clients": clients})
			in.Settings = data
		}
	}
	return m.save()
}

// ListClientEmails returns all client emails for a given inbound tag.
func (m *Manager) ListClientEmails(tag string) []string {
	for _, in := range m.config.Inbounds {
		if in.Tag != tag {
			continue
		}
		var wrapper struct {
			Clients []struct {
				Email string `json:"email"`
			} `json:"clients"`
		}
		if err := json.Unmarshal(in.Settings, &wrapper); err != nil {
			return nil
		}
		emails := make([]string, len(wrapper.Clients))
		for i, c := range wrapper.Clients {
			emails[i] = c.Email
		}
		return emails
	}
	return nil
}

// reloadXray reloads the local Xray service depending on OS.
func reloadXray() error {
	switch runtime.GOOS {
	case "linux":
		if err := exec.Command("systemctl", "reload", "xray").Run(); err != nil {
			return exec.Command("systemctl", "restart", "xray").Run()
		}
		return nil
	case "windows":
		return exec.Command("powershell", "-Command", "Restart-Service", "Xray").Run()
	default:
		return fmt.Errorf("unsupported OS: %s", runtime.GOOS)
	}
}
