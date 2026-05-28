package payment

import (
	"database/sql"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// Handler processes payment-related HTTP requests.
type Handler struct {
	DB     *sql.DB
	Alipay *AlipayClient

	// CreateAccount is a callback that provisions a VPN account after a
	// successful payment. It is wired from main.go so that the payment
	// package does not need to import xray directly.
	CreateAccount func(userID, orderID, protocol string) error
}

// AlipayNotify 处理支付宝异步通知回调。
// POST /api/payment/alipay/notify
func (h *Handler) AlipayNotify(c *gin.Context) {
	params := make(map[string]string)
	if err := c.Request.ParseForm(); err != nil {
		c.String(http.StatusBadRequest, "fail")
		return
	}
	for k, v := range c.Request.PostForm {
		if len(v) > 0 {
			params[k] = v[0]
		}
	}

	// 支付宝沙箱 / 当面付测试时可跳过验签
	if h.Alipay != nil && !h.Alipay.VerifyNotify(params) {
		log.Printf("[payment] 支付宝签名验证失败")
		c.String(http.StatusBadRequest, "fail")
		return
	}

	outTradeNo := params["out_trade_no"] // = order_id
	tradeStatus := params["trade_status"]

	if tradeStatus != "TRADE_SUCCESS" {
		c.String(http.StatusOK, "success")
		return
	}

	// 标记订单为已支付
	now := time.Now()
	result, err := h.DB.Exec(
		"UPDATE orders SET status='paid', paid_at=$1 WHERE id=$2 AND status='pending'",
		now, outTradeNo,
	)
	if err != nil {
		log.Printf("[payment] 更新订单状态失败: %v", err)
		c.String(http.StatusInternalServerError, "fail")
		return
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		// 订单可能已经处理过（重复通知），直接返回 success
		c.String(http.StatusOK, "success")
		return
	}

	// 获取订单信息，创建 VPN 账号
	var userID, planID, protocol string
	if err := h.DB.QueryRow(
		"SELECT user_id, plan_id, COALESCE(protocol, 'vless') FROM orders WHERE id=$1",
		outTradeNo,
	).Scan(&userID, &planID, &protocol); err != nil {
		log.Printf("[payment] 查询订单信息失败: %v", err)
		c.String(http.StatusOK, "success")
		return
	}

	if h.CreateAccount != nil {
		if err := h.CreateAccount(userID, outTradeNo, protocol); err != nil {
			log.Printf("[payment] 创建 VPN 账号失败: %v", err)
		}
	}

	c.String(http.StatusOK, "success")
}

// GetOrderStatus 前端轮询订单状态。
// GET /api/orders/:id/status
func (h *Handler) GetOrderStatus(c *gin.Context) {
	orderID := c.Param("id")
	userID := c.GetString("user_id")

	var status string
	err := h.DB.QueryRow(
		"SELECT status FROM orders WHERE id=$1 AND user_id=$2",
		orderID, userID,
	).Scan(&status)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "订单不存在"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": status})
}

// EnsureSubToken ensures a subscription token exists for the given user.
// It is exported so that the API handler can reuse it during order creation
// if Alipay is not configured (MVP fallback).
func EnsureSubToken(db *sql.DB, userID string) (string, error) {
	var token string
	err := db.QueryRow(
		`INSERT INTO sub_tokens (user_id, token) VALUES ($1,$2)
		 ON CONFLICT (user_id) DO UPDATE SET token=sub_tokens.token
		 RETURNING token`,
		userID, uuid.New().String()[:16],
	).Scan(&token)
	return token, err
}
