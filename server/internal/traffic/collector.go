package traffic

import (
	"database/sql"
	"log"

	"github.com/borderx/panel/internal/xray"
)

// Collector fetches traffic deltas from Xray Stats and persists them.
type Collector struct {
	DB    *sql.DB
	Stats *xray.StatsCollector
}

// NewCollector creates a traffic Collector.
func NewCollector(db *sql.DB, stats *xray.StatsCollector) *Collector {
	return &Collector{DB: db, Stats: stats}
}

// Collect fetches traffic deltas and updates vpn_accounts.traffic_used_bytes.
// Returns silently if StatsCollector is not connected (no Xray running).
func (c *Collector) Collect() {
	if c.Stats == nil {
		return
	}
	deltas, err := c.Stats.QueryStats()
	if err != nil {
		// Xray not running — skip silently, not a fatal error
		return
	}
	for _, d := range deltas {
		// email = accountID@borderx, extract accountID
		accountID := extractAccountID(d.Email)
		if accountID == "" {
			continue
		}

		// Record per-cycle traffic into traffic_logs
		c.DB.Exec(
			"INSERT INTO traffic_logs (account_id, upload_bytes, download_bytes) VALUES ($1, $2, $3)",
			accountID, d.Upload, d.Download,
		)

		// Accumulate into vpn_accounts
		result, err := c.DB.Exec(
			"UPDATE vpn_accounts SET traffic_used_bytes = traffic_used_bytes + $1 WHERE id = $2",
			d.Upload+d.Download, accountID,
		)
		if err != nil {
			continue
		}

		// Check if traffic limit is exceeded
		rowsAffected, _ := result.RowsAffected()
		if rowsAffected > 0 {
			var used, limit int64
			var status string
			err := c.DB.QueryRow(
				"SELECT traffic_used_bytes, traffic_limit_bytes, status FROM vpn_accounts WHERE id = $1",
				accountID,
			).Scan(&used, &limit, &status)
			if err != nil {
				continue
			}
			if status == "active" && limit > 0 && used >= limit {
				c.DB.Exec("UPDATE vpn_accounts SET status = 'disabled' WHERE id = $1", accountID)
				log.Printf("[traffic] 账号 %s 流量超限，已禁用 (used=%d, limit=%d)", accountID, used, limit)
			}
		}
	}
}

// Archive aggregates traffic_logs into traffic_hourly and deletes old logs.
func (c *Collector) Archive() {
	c.DB.Exec(`
		INSERT INTO traffic_hourly (account_id, upload_bytes, download_bytes, hour)
		SELECT account_id, SUM(upload_bytes), SUM(download_bytes), date_trunc('hour', recorded_at)
		FROM traffic_logs
		WHERE recorded_at < date_trunc('hour', now()) - interval '1 hour'
		GROUP BY account_id, date_trunc('hour', recorded_at)
		ON CONFLICT (account_id, hour) DO UPDATE SET
			upload_bytes = traffic_hourly.upload_bytes + EXCLUDED.upload_bytes,
			download_bytes = traffic_hourly.download_bytes + EXCLUDED.download_bytes
	`)
	c.DB.Exec("DELETE FROM traffic_logs WHERE recorded_at < now() - interval '24 hours'")
}

// CheckExpired disables accounts that have passed their expiry date.
func (c *Collector) CheckExpired() {
	result, err := c.DB.Exec(
		"UPDATE vpn_accounts SET status = 'expired' WHERE status = 'active' AND expires_at < now()",
	)
	if err == nil {
		n, _ := result.RowsAffected()
		if n > 0 {
			log.Printf("[traffic] 已过期账号: %d 个", n)
		}
	}
}

// extractAccountID returns the part before '@' in an email string.
// e.g. "abc123@borderx" => "abc123"
func extractAccountID(email string) string {
	for i, ch := range email {
		if ch == '@' {
			return email[:i]
		}
	}
	return ""
}
