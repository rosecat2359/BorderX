package model

import (
	"database/sql"
	"encoding/json"
	"time"
)

type User struct {
	ID           string    `json:"id" db:"id"`
	Email        string    `json:"email" db:"email"`
	PasswordHash string    `json:"-" db:"password_hash"`
	Status       string    `json:"status" db:"status"`
	CreatedAt    time.Time `json:"created_at" db:"created_at"`
}

type Admin struct {
	ID           string    `json:"id" db:"id"`
	Username     string    `json:"username" db:"username"`
	PasswordHash string    `json:"-" db:"password_hash"`
	Role         string    `json:"role" db:"role"`
	CreatedAt    time.Time `json:"created_at" db:"created_at"`
}

type Plan struct {
	ID             string    `json:"id"`
	Name           string    `json:"name"`
	PriceCents     int       `json:"price_cents"`
	DurationDays   int       `json:"duration_days"`
	TrafficLimitGB int       `json:"traffic_limit_gb"`
	MaxDevices     int       `json:"max_devices"`
	SortOrder      int       `json:"sort_order"`
	IsActive       bool      `json:"is_active"`
	CreatedAt      time.Time `json:"created_at"`
}

type Order struct {
	ID          string       `json:"id"`
	UserID      string       `json:"user_id"`
	PlanID      string       `json:"plan_id"`
	Status      string       `json:"status"`
	AmountCents int          `json:"amount_cents"`
	PaidAt      sql.NullTime `json:"paid_at"`
	StartsAt    sql.NullTime `json:"starts_at"`
	ExpiresAt   sql.NullTime `json:"expires_at"`
	CreatedAt   time.Time    `json:"created_at"`
	Plan        *Plan        `json:"plan,omitempty"`
}

type VPNAccount struct {
	ID                string          `json:"id"`
	UserID            string          `json:"user_id"`
	OrderID           sql.NullString  `json:"order_id"`
	Protocol          string          `json:"protocol"`
	UUID              string          `json:"uuid"`
	Password          string          `json:"password,omitempty"`
	SettingsJSON      json.RawMessage `json:"settings_json"`
	Status            string          `json:"status"`
	TrafficUsedBytes  int64           `json:"traffic_used_bytes"`
	TrafficLimitBytes int64           `json:"traffic_limit_bytes"`
	ExpiresAt         sql.NullTime    `json:"expires_at"`
	CreatedAt         time.Time       `json:"created_at"`
}

type TrafficLog struct {
	ID            int64     `json:"id"`
	AccountID     string    `json:"account_id"`
	UploadBytes   int64     `json:"upload_bytes"`
	DownloadBytes int64     `json:"download_bytes"`
	RecordedAt    time.Time `json:"recorded_at"`
}

type Node struct {
	ID         string       `json:"id"`
	Name       string       `json:"name"`
	Host       string       `json:"host"`
	SSHPort    int          `json:"ssh_port"`
	SSHUser    string       `json:"ssh_user"`
	SSHKeyPath string       `json:"ssh_key_path"`
	Region     string       `json:"region"`
	IsActive   bool         `json:"is_active"`
	LastSeenAt sql.NullTime `json:"last_seen_at"`
	CreatedAt  time.Time    `json:"created_at"`
}

type SubToken struct {
	ID             string       `json:"id"`
	UserID         string       `json:"user_id"`
	Token          string       `json:"token"`
	LastAccessedAt sql.NullTime `json:"last_accessed_at"`
	CreatedAt      time.Time    `json:"created_at"`
}

type AuditLog struct {
	ID         int64           `json:"id"`
	AdminID    sql.NullString  `json:"admin_id"`
	Action     string          `json:"action"`
	TargetType string          `json:"target_type"`
	TargetID   sql.NullString  `json:"target_id"`
	DetailJSON json.RawMessage `json:"detail_json"`
	CreatedAt  time.Time       `json:"created_at"`
}

type Paginated struct {
	Items interface{} `json:"items"`
	Total int         `json:"total"`
	Page  int         `json:"page"`
	Size  int         `json:"size"`
}
