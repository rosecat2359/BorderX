package traffic

import (
	"database/sql"
	"log"
	"time"

	"github.com/borderx/panel/internal/xray"
)

type Collector struct {
	DB    *sql.DB
	Stats *xray.StatsCollector
}

func NewCollector(db *sql.DB, stats *xray.StatsCollector) *Collector {
	return &Collector{DB: db, Stats: stats}
}

// Collect fetches traffic deltas from Xray Stats API and writes to traffic_hourly.
// It also checks for expired clients and over-limit clients.
func (c *Collector) Collect() error {
	if c.Stats == nil {
		return nil
	}
	deltas, err := c.Stats.QueryAll()
	if err != nil {
		return err
	}
	for _, d := range deltas {
		// email format: accountID@borderx
		accountID := extractAccountID(d.Email)
		if accountID == "" {
			continue
		}
		// Find all inbounds associated with this client
		rows, err := c.DB.Query(
			"SELECT inbound_id FROM client_inbounds WHERE client_id = ?", accountID,
		)
		if err != nil {
			continue
		}
		hour := time.Now().Format("2006-01-02 15") + ":00:00"
		for rows.Next() {
			var inboundID string
			rows.Scan(&inboundID)
			c.DB.Exec(
				`INSERT INTO traffic_hourly (client_id, inbound_id, up_bytes, down_bytes, hour)
				 VALUES (?, ?, ?, ?, ?)
				 ON CONFLICT(client_id, inbound_id, hour) DO UPDATE SET
				 up_bytes = up_bytes + ?, down_bytes = down_bytes + ?`,
				accountID, inboundID, d.Upload, d.Download, hour,
				d.Upload, d.Download,
			)
		}
		rows.Close()

		// Check traffic limit exceeded
		var totalLimit int64
		c.DB.QueryRow("SELECT total_limit FROM clients WHERE id = ?", accountID).Scan(&totalLimit)
		if totalLimit > 0 {
			var used int64
			c.DB.QueryRow(
				"SELECT COALESCE(SUM(up_bytes+down_bytes),0) FROM traffic_hourly WHERE client_id = ?",
				accountID,
			).Scan(&used)
			if used >= totalLimit {
				c.DB.Exec("UPDATE clients SET is_active = 0 WHERE id = ? AND is_active = 1", accountID)
				log.Printf("[traffic] 客户端 %s 流量超限，已禁用 (used=%d, limit=%d)", accountID, used, totalLimit)
			}
		}
	}
	return nil
}

// Archive removes traffic data older than 30 days.
func (c *Collector) Archive() error {
	_, err := c.DB.Exec("DELETE FROM traffic_hourly WHERE hour < datetime('now', '-30 days')")
	return err
}

// CheckExpired disables clients whose expiry date has passed.
func (c *Collector) CheckExpired() error {
	res, err := c.DB.Exec(
		"UPDATE clients SET is_active = 0 WHERE expiry_at IS NOT NULL AND expiry_at < datetime('now') AND is_active = 1",
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n > 0 {
		log.Printf("[traffic] %d 个客户端已过期，已自动禁用", n)
	}
	return nil
}

func extractAccountID(email string) string {
	for i, ch := range email {
		if ch == '@' {
			return email[:i]
		}
	}
	return ""
}
