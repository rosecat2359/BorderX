package admin

import (
	"database/sql"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/borderx/panel/internal/model"
	"github.com/gin-gonic/gin"
)

// Handler handles admin CRUD operations.
type Handler struct {
	DB *sql.DB
}

// --- helpers ---

func queryInt(c *gin.Context, key string, defaultVal int) int {
	v := c.Query(key)
	if v == "" {
		return defaultVal
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < 1 {
		return defaultVal
	}
	return n
}

func itoa(n int) string {
	return strconv.Itoa(n)
}

// ========================
// User management
// ========================

// ListUsers returns a paginated list of users with optional email ILIKE
// search and status filtering.
func (h *Handler) ListUsers(c *gin.Context) {
	page := queryInt(c, "page", 1)
	size := queryInt(c, "size", 20)
	email := c.Query("email")
	status := c.Query("status")

	var conditions []string
	var args []interface{}
	idx := 1

	if email != "" {
		conditions = append(conditions, "email ILIKE '%' || $"+itoa(idx)+" || '%'")
		args = append(args, email)
		idx++
	}
	if status != "" {
		conditions = append(conditions, "status = $"+itoa(idx))
		args = append(args, status)
		idx++
	}

	whereSQL := ""
	if len(conditions) > 0 {
		whereSQL = "WHERE " + conditions[0]
		for i := 1; i < len(conditions); i++ {
			whereSQL += " AND " + conditions[i]
		}
	}

	// Count total
	var total int
	if err := h.DB.QueryRow("SELECT COUNT(*) FROM users "+whereSQL, args...).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	// Paginated query
	offset := (page - 1) * size
	query := "SELECT id, email, status, created_at FROM users " + whereSQL +
		" ORDER BY created_at DESC LIMIT $" + itoa(idx) + " OFFSET $" + itoa(idx+1)
	args = append(args, size, offset)

	rows, err := h.DB.Query(query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}
	defer rows.Close()

	users := make([]model.User, 0)
	for rows.Next() {
		var u model.User
		if err := rows.Scan(&u.ID, &u.Email, &u.Status, &u.CreatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "读取数据失败"})
			return
		}
		users = append(users, u)
	}

	c.JSON(http.StatusOK, model.Paginated{
		Items: users,
		Total: total,
		Page:  page,
		Size:  size,
	})
}

// GetUser returns a single user by ID.
func (h *Handler) GetUser(c *gin.Context) {
	id := c.Param("id")
	var u model.User
	err := h.DB.QueryRow(
		"SELECT id, email, status, created_at FROM users WHERE id = $1", id,
	).Scan(&u.ID, &u.Email, &u.Status, &u.CreatedAt)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}
	c.JSON(http.StatusOK, u)
}

// DisableUser sets a user's status to 'disabled'.
func (h *Handler) DisableUser(c *gin.Context) {
	id := c.Param("id")
	result, err := h.DB.Exec("UPDATE users SET status = 'disabled' WHERE id = $1", id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "操作失败"})
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "用户已禁用"})
}

// EnableUser sets a user's status to 'active'.
func (h *Handler) EnableUser(c *gin.Context) {
	id := c.Param("id")
	result, err := h.DB.Exec("UPDATE users SET status = 'active' WHERE id = $1", id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "操作失败"})
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "用户已启用"})
}

// ========================
// Plan management
// ========================

// ListPlans returns all plans ordered by sort_order.
func (h *Handler) ListPlans(c *gin.Context) {
	rows, err := h.DB.Query(
		`SELECT id, name, price_cents, duration_days, traffic_limit_gb,
		        max_devices, sort_order, is_active, created_at
		 FROM plans ORDER BY sort_order`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}
	defer rows.Close()

	plans := make([]model.Plan, 0)
	for rows.Next() {
		var p model.Plan
		if err := rows.Scan(&p.ID, &p.Name, &p.PriceCents, &p.DurationDays,
			&p.TrafficLimitGB, &p.MaxDevices, &p.SortOrder, &p.IsActive, &p.CreatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "读取数据失败"})
			return
		}
		plans = append(plans, p)
	}

	c.JSON(http.StatusOK, plans)
}

// CreatePlan inserts a new plan and returns it with the generated id and
// created_at.
func (h *Handler) CreatePlan(c *gin.Context) {
	var p model.Plan
	if err := c.ShouldBindJSON(&p); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误: " + err.Error()})
		return
	}

	err := h.DB.QueryRow(
		`INSERT INTO plans (name, price_cents, duration_days, traffic_limit_gb,
		                    max_devices, sort_order, is_active)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)
		 RETURNING id, created_at`,
		p.Name, p.PriceCents, p.DurationDays, p.TrafficLimitGB,
		p.MaxDevices, p.SortOrder, p.IsActive,
	).Scan(&p.ID, &p.CreatedAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败: " + err.Error()})
		return
	}

	c.JSON(http.StatusCreated, p)
}

// UpdatePlan updates a plan's fields by ID.
func (h *Handler) UpdatePlan(c *gin.Context) {
	id := c.Param("id")
	var p model.Plan
	if err := c.ShouldBindJSON(&p); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误: " + err.Error()})
		return
	}

	result, err := h.DB.Exec(
		`UPDATE plans
		 SET name=$1, price_cents=$2, duration_days=$3, traffic_limit_gb=$4,
		     max_devices=$5, sort_order=$6, is_active=$7
		 WHERE id=$8`,
		p.Name, p.PriceCents, p.DurationDays, p.TrafficLimitGB,
		p.MaxDevices, p.SortOrder, p.IsActive, id,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "更新失败: " + err.Error()})
		return
	}

	n, _ := result.RowsAffected()
	if n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "套餐不存在"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "更新成功"})
}

// DeletePlan deletes a plan by ID.
func (h *Handler) DeletePlan(c *gin.Context) {
	id := c.Param("id")
	result, err := h.DB.Exec("DELETE FROM plans WHERE id = $1", id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "删除失败"})
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "套餐不存在"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "删除成功"})
}

// ========================
// Order management
// ========================

// ListOrders returns a paginated list of orders with nested plan info via
// LEFT JOIN.
func (h *Handler) ListOrders(c *gin.Context) {
	page := queryInt(c, "page", 1)
	size := queryInt(c, "size", 20)
	offset := (page - 1) * size

	var total int
	if err := h.DB.QueryRow("SELECT COUNT(*) FROM orders").Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	rows, err := h.DB.Query(
		`SELECT o.id, o.user_id, o.plan_id, o.status, o.amount_cents,
		        o.paid_at, o.starts_at, o.expires_at, o.created_at,
		        p.id, p.name, p.price_cents, p.duration_days, p.traffic_limit_gb,
		        p.max_devices, p.sort_order, p.is_active, p.created_at
		 FROM orders o
		 LEFT JOIN plans p ON o.plan_id = p.id
		 ORDER BY o.created_at DESC
		 LIMIT $1 OFFSET $2`, size, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}
	defer rows.Close()

	orders := make([]model.Order, 0)
	for rows.Next() {
		var o model.Order

		// Plan columns (nullable because of LEFT JOIN)
		var (
			pID             sql.NullString
			pName           sql.NullString
			pPriceCents     sql.NullInt64
			pDurationDays   sql.NullInt64
			pTrafficLimitGB sql.NullInt64
			pMaxDevices     sql.NullInt64
			pSortOrder      sql.NullInt64
			pIsActive       sql.NullBool
			pCreatedAt      sql.NullTime
		)

		if err := rows.Scan(
			&o.ID, &o.UserID, &o.PlanID, &o.Status, &o.AmountCents,
			&o.PaidAt, &o.StartsAt, &o.ExpiresAt, &o.CreatedAt,
			&pID, &pName, &pPriceCents, &pDurationDays, &pTrafficLimitGB,
			&pMaxDevices, &pSortOrder, &pIsActive, &pCreatedAt,
		); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "读取数据失败"})
			return
		}

		if pID.Valid {
			o.Plan = &model.Plan{
				ID:             pID.String,
				Name:           pName.String,
				PriceCents:     int(pPriceCents.Int64),
				DurationDays:   int(pDurationDays.Int64),
				TrafficLimitGB: int(pTrafficLimitGB.Int64),
				MaxDevices:     int(pMaxDevices.Int64),
				SortOrder:      int(pSortOrder.Int64),
				IsActive:       pIsActive.Bool,
				CreatedAt:      pCreatedAt.Time,
			}
		}

		orders = append(orders, o)
	}

	c.JSON(http.StatusOK, model.Paginated{
		Items: orders,
		Total: total,
		Page:  page,
		Size:  size,
	})
}

// CancelOrder cancels a pending order.
func (h *Handler) CancelOrder(c *gin.Context) {
	id := c.Param("id")
	result, err := h.DB.Exec(
		"UPDATE orders SET status = 'cancelled' WHERE id = $1 AND status = 'pending'", id,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "操作失败"})
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "订单不存在或状态不允许取消"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "订单已取消"})
}

// ========================
// Dashboard
// ========================

// Dashboard returns summary statistics.
func (h *Handler) Dashboard(c *gin.Context) {
	var totalUsers, activeAccounts, revenueToday int

	if err := h.DB.QueryRow("SELECT COUNT(*) FROM users").Scan(&totalUsers); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}
	if err := h.DB.QueryRow(
		"SELECT COUNT(*) FROM vpn_accounts WHERE status = 'active'",
	).Scan(&activeAccounts); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}
	if err := h.DB.QueryRow(
		"SELECT COALESCE(SUM(amount_cents), 0) FROM orders WHERE status = 'paid' AND paid_at::date = CURRENT_DATE",
	).Scan(&revenueToday); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"total_users":     totalUsers,
		"active_accounts": activeAccounts,
		"revenue_today":   revenueToday,
	})
}

// ========================
// Traffic
// ========================

// TrafficSummary returns overview traffic stats.
func (h *Handler) TrafficSummary(c *gin.Context) {
	var totalUpload, totalDownload int64
	h.DB.QueryRow("SELECT COALESCE(SUM(upload_bytes),0), COALESCE(SUM(download_bytes),0) FROM traffic_hourly WHERE hour > now() - interval '30 days'").Scan(&totalUpload, &totalDownload)

	var activeAccounts int
	h.DB.QueryRow("SELECT count(*) FROM vpn_accounts WHERE status='active'").Scan(&activeAccounts)

	c.JSON(http.StatusOK, gin.H{
		"total_upload_gb":   float64(totalUpload) / 1024 / 1024 / 1024,
		"total_download_gb": float64(totalDownload) / 1024 / 1024 / 1024,
		"active_accounts":   activeAccounts,
	})
}

// TrafficByAccount returns per-account traffic for the last N days.
func (h *Handler) TrafficByAccount(c *gin.Context) {
	days := queryInt(c, "days", 7)
	rows, err := h.DB.Query(`
		SELECT va.email, va.protocol, COALESCE(SUM(th.upload_bytes),0), COALESCE(SUM(th.download_bytes),0)
		FROM vpn_accounts va
		LEFT JOIN traffic_hourly th ON va.id = th.account_id AND th.hour > now() - ($1 || ' days')::interval
		WHERE va.status = 'active'
		GROUP BY va.id, va.email, va.protocol
		ORDER BY COALESCE(SUM(th.upload_bytes),0) + COALESCE(SUM(th.download_bytes),0) DESC
		LIMIT 100`, fmt.Sprintf("%d", days))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}
	defer rows.Close()

	items := []gin.H{}
	for rows.Next() {
		var email, protocol string
		var up, down int64
		rows.Scan(&email, &protocol, &up, &down)
		items = append(items, gin.H{
			"email":       email,
			"protocol":    protocol,
			"upload_gb":   float64(up) / 1024 / 1024 / 1024,
			"download_gb": float64(down) / 1024 / 1024 / 1024,
			"total_gb":    float64(up+down) / 1024 / 1024 / 1024,
		})
	}
	c.JSON(http.StatusOK, items)
}

// TrafficTimeline returns hourly traffic for charts (last 24h).
func (h *Handler) TrafficTimeline(c *gin.Context) {
	rows, err := h.DB.Query(`
		SELECT hour, COALESCE(SUM(upload_bytes),0), COALESCE(SUM(download_bytes),0)
		FROM traffic_hourly
		WHERE hour > now() - interval '24 hours'
		GROUP BY hour ORDER BY hour`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}
	defer rows.Close()

	items := []gin.H{}
	for rows.Next() {
		var hour time.Time
		var up, down int64
		rows.Scan(&hour, &up, &down)
		items = append(items, gin.H{
			"hour":        hour.Format("2006-01-02 15:04"),
			"upload_gb":   float64(up) / 1024 / 1024 / 1024,
			"download_gb": float64(down) / 1024 / 1024 / 1024,
		})
	}
	c.JSON(http.StatusOK, items)
}
