package api

import (
	"database/sql"
	"net/http"
	"time"

	"github.com/borderx/panel/internal/payment"
	"github.com/borderx/panel/internal/xray"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// Handler handles user-facing API operations.
type Handler struct {
	DB     *sql.DB
	Xray   *xray.Manager
	Alipay *payment.AlipayClient
}

// CreateOrderRequest is the request body for CreateOrder.
type CreateOrderRequest struct {
	PlanID   string `json:"plan_id" binding:"required"`
	Protocol string `json:"protocol"` // vless/vmess/trojan, default vless
}

// CreateOrder creates an order. When Alipay is configured the order starts as
// "pending" and a QR code URL is returned; the user pays and the Alipay notify
// callback finalises the order. Without Alipay (MVP), the order is marked "paid"
// immediately and a VPN account is provisioned inline.
func (h *Handler) CreateOrder(c *gin.Context) {
	var req CreateOrderRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}
	if req.Protocol == "" {
		req.Protocol = "vless"
	}
	userID := c.GetString("user_id")

	// Look up the plan
	var planName string
	var priceCents, durationDays, trafficGB int
	err := h.DB.QueryRow(
		"SELECT name, price_cents, duration_days, traffic_limit_gb FROM plans WHERE id=$1 AND is_active=true",
		req.PlanID,
	).Scan(&planName, &priceCents, &durationDays, &trafficGB)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "套餐不存在或已下架"})
		return
	}

	// Create order with pending status
	var orderID string
	h.DB.QueryRow(
		"INSERT INTO orders (user_id, plan_id, amount_cents, protocol) VALUES ($1,$2,$3,$4) RETURNING id",
		userID, req.PlanID, priceCents, req.Protocol,
	).Scan(&orderID)

	// ---- Alipay 模式: 返回 QR 码让用户扫码支付 ----
	if h.Alipay != nil {
		qrCode, _ := h.Alipay.TradePrecreate(orderID, planName, float64(priceCents)/100.0)

		c.JSON(http.StatusCreated, gin.H{
			"order_id":  orderID,
			"amount":    float64(priceCents) / 100.0,
			"status":    "pending",
			"qr_code":   qrCode,
			"plan_name": planName,
		})
		return
	}

	// ---- MVP 模式: 直接标记 paid + 创建 VPN 账号 ----
	now := time.Now()
	expiresAt := now.Add(time.Duration(durationDays) * 24 * time.Hour)
	h.DB.Exec(
		"UPDATE orders SET status='paid', paid_at=$1, starts_at=$1, expires_at=$2 WHERE id=$3",
		now, expiresAt, orderID,
	)

	// Create VPN account
	vpnUUID := uuid.New().String()
	password := ""
	if req.Protocol == "trojan" {
		password = uuid.New().String()[:16]
	}

	var accountID string
	h.DB.QueryRow(
		`INSERT INTO vpn_accounts (user_id, order_id, protocol, uuid, password, traffic_limit_bytes, expires_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id`,
		userID, orderID, req.Protocol, vpnUUID, password,
		int64(trafficGB)*1024*1024*1024, expiresAt,
	).Scan(&accountID)

	// Write Xray config
	if h.Xray != nil {
		tag := map[string]string{
			"vless":  "vless-reality",
			"vmess":  "vmess-ws",
			"trojan": "trojan-tcp",
		}[req.Protocol]
		email := accountID + "@borderx"
		if err := h.Xray.AddClient(tag, req.Protocol, email, vpnUUID, password); err != nil {
			c.Error(err)
		}
	}

	// Ensure a subscription token exists for the user
	subToken, _ := payment.EnsureSubToken(h.DB, userID)

	c.JSON(http.StatusCreated, gin.H{
		"order_id":   orderID,
		"account_id": accountID,
		"protocol":   req.Protocol,
		"uuid":       vpnUUID,
		"expires_at": expiresAt,
		"sub_token":  subToken,
	})
}

// ListOrders returns all orders belonging to the current user, ordered by
// creation time descending.
func (h *Handler) ListOrders(c *gin.Context) {
	userID := c.GetString("user_id")
	rows, err := h.DB.Query(`
		SELECT o.id, o.status, o.amount_cents, o.created_at,
		       COALESCE(p.name, '') as plan_name
		FROM orders o LEFT JOIN plans p ON o.plan_id = p.id
		WHERE o.user_id = $1 ORDER BY o.created_at DESC`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}
	defer rows.Close()

	orders := []gin.H{}
	for rows.Next() {
		var id, status, planName string
		var amountCents int
		var createdAt time.Time
		rows.Scan(&id, &status, &amountCents, &createdAt, &planName)
		orders = append(orders, gin.H{
			"id": id, "status": status, "amount_cents": amountCents,
			"plan_name": planName, "created_at": createdAt,
		})
	}
	c.JSON(http.StatusOK, orders)
}

// ListAccounts returns all VPN accounts belonging to the current user.
func (h *Handler) ListAccounts(c *gin.Context) {
	userID := c.GetString("user_id")
	rows, err := h.DB.Query(`
		SELECT id, protocol, uuid, password, status, traffic_used_bytes, traffic_limit_bytes, expires_at, created_at
		FROM vpn_accounts WHERE user_id = $1 ORDER BY created_at DESC`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}
	defer rows.Close()

	accounts := []gin.H{}
	for rows.Next() {
		var id, protocol, uuid_, password, status string
		var used, limit int64
		var expiresAt, createdAt sql.NullTime
		rows.Scan(&id, &protocol, &uuid_, &password, &status, &used, &limit, &expiresAt, &createdAt)
		accounts = append(accounts, gin.H{
			"id": id, "protocol": protocol, "uuid": uuid_,
			"status":           status,
			"traffic_used_gb":  float64(used) / 1024 / 1024 / 1024,
			"traffic_limit_gb": float64(limit) / 1024 / 1024 / 1024,
			"expires_at":       expiresAt.Time, "created_at": createdAt.Time,
		})
	}
	c.JSON(http.StatusOK, accounts)
}

// Me returns basic profile info for the current user.
func (h *Handler) Me(c *gin.Context) {
	var email, status string
	var createdAt time.Time
	h.DB.QueryRow("SELECT email, status, created_at FROM users WHERE id=$1", c.GetString("user_id")).
		Scan(&email, &status, &createdAt)
	c.JSON(http.StatusOK, gin.H{"email": email, "status": status, "created_at": createdAt})
}
