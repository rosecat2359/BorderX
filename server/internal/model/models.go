// 数据库模型定义 — 管理员、节点、入站、客户端、流量日志。
package model

// Admin represents the single-panel administrator.
type Admin struct {
	ID        int64  `json:"id"`
	Username  string `json:"username"`
	Password  string `json:"-"`
	CreatedAt string `json:"created_at"`
}

// Node represents an edge server running Xray-core.
type Node struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Host       string `json:"host"`
	SSHPort    int    `json:"ssh_port"`
	SSHUser    string `json:"ssh_user"`
	SSHKey     string `json:"-"`
	OS         string `json:"os"`
	Region     string `json:"region"`
	IsActive   bool   `json:"is_active"`
	LastSeenAt string `json:"last_seen_at,omitempty"`
	CreatedAt  string `json:"created_at"`
	// Computed fields (populated by JOIN / aggregation queries).
	InboundCount int    `json:"inbound_count,omitempty"`
	ClientCount  int    `json:"client_count,omitempty"`
	Status       string `json:"status,omitempty"`
}

// Inbound represents an Xray-core inbound on a specific node.
type Inbound struct {
	ID        string `json:"id"`
	NodeID    string `json:"node_id"`
	Tag       string `json:"tag"`
	Protocol  string `json:"protocol"`
	Port      int    `json:"port"`
	Listen    string `json:"listen"`
	Settings  string `json:"settings"`
	Stream    string `json:"stream"`
	Sniffing  bool   `json:"sniffing"`
	IsActive  bool   `json:"is_active"`
	CreatedAt string `json:"created_at"`
	// Computed fields.
	NodeName    string `json:"node_name,omitempty"`
	ClientCount int    `json:"client_count,omitempty"`
}

// Client represents a VPN user / device.
type Client struct {
	ID         string          `json:"id"`
	Name       string          `json:"name"`
	UUID       string          `json:"uuid"`
	Password   string          `json:"password,omitempty"`
	Flow       string          `json:"flow"`
	TotalLimit int64           `json:"total_limit"`
	ExpiryAt   string          `json:"expiry_at,omitempty"`
	IsActive   bool            `json:"is_active"`
	CreatedAt  string          `json:"created_at"`
	// Computed fields.
	TotalUsed int64           `json:"total_used,omitempty"`
	Inbounds  []ClientInbound `json:"inbounds,omitempty"`
}

// ClientInbound is the join table between clients and inbounds.
type ClientInbound struct {
	ClientID  string `json:"client_id"`
	InboundID string `json:"inbound_id"`
	IsVisible bool   `json:"is_visible"`
	// Joined fields (populated by JOIN queries).
	NodeName string `json:"node_name,omitempty"`
	Protocol string `json:"protocol,omitempty"`
	Port     int    `json:"port,omitempty"`
	Host     string `json:"host,omitempty"`
}

// TrafficHourly records per-client-inbound traffic for a given hour.
type TrafficHourly struct {
	ID        int64  `json:"id"`
	ClientID  string `json:"client_id"`
	InboundID string `json:"inbound_id"`
	UpBytes   int64  `json:"up_bytes"`
	DownBytes int64  `json:"down_bytes"`
	Hour      string `json:"hour"`
}

// AuditLog records an administrative action.
type AuditLog struct {
	ID        int64  `json:"id"`
	Action    string `json:"action"`
	Target    string `json:"target"`
	Detail    string `json:"detail"`
	CreatedAt string `json:"created_at"`
}

// DashboardStats holds aggregate statistics for the dashboard overview.
type DashboardStats struct {
	NodeCount      int   `json:"node_count"`
	ActiveClients  int   `json:"active_clients"`
	TodayUpBytes   int64 `json:"today_up_bytes"`
	TodayDownBytes int64 `json:"today_down_bytes"`
}
