package sub

import (
	"database/sql"
	"encoding/base64"
	"fmt"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

type Handler struct {
	DB *sql.DB
}

func (h *Handler) Serve(c *gin.Context) {
	token := c.Query("token")
	if token == "" {
		c.String(http.StatusBadRequest, "missing token")
		return
	}

	var userID string
	err := h.DB.QueryRow("SELECT user_id FROM sub_tokens WHERE token = $1", token).Scan(&userID)
	if err == sql.ErrNoRows {
		c.String(http.StatusNotFound, "invalid token")
		return
	}
	if err != nil {
		c.String(http.StatusInternalServerError, "server error")
		return
	}

	// 更新最后访问时间
	h.DB.Exec("UPDATE sub_tokens SET last_accessed_at = now() WHERE token = $1", token)

	// 查所有活跃的 VPN 账号
	rows, err := h.DB.Query(
		`SELECT protocol, uuid, password FROM vpn_accounts
		 WHERE user_id = $1 AND status = 'active'`, userID)
	if err != nil {
		c.String(http.StatusInternalServerError, "query error")
		return
	}
	defer rows.Close()

	// v2ray 订阅格式：每行一个分享链接，整体 base64 编码
	var links []string
	for rows.Next() {
		var protocol, uuid, password string
		rows.Scan(&protocol, &uuid, &password)

		// MVP: server IP 从 host header 获取，后续可用节点表替换
		host := c.Request.Host
		if idx := strings.Index(host, ":"); idx != -1 {
			host = host[:idx]
		}

		switch protocol {
		case "vless":
			// VLESS Reality 分享链接
			link := fmt.Sprintf("vless://%s@%s:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&type=tcp#BorderX-VLESS", uuid, host)
			links = append(links, link)
		case "vmess":
			link := fmt.Sprintf("vmess://%s@%s:10001?path=/ws&security=none&type=ws#BorderX-VMESS", uuid, host)
			links = append(links, link)
		case "trojan":
			link := fmt.Sprintf("trojan://%s@%s:10002?security=tls&type=tcp#BorderX-Trojan", password, host)
			links = append(links, link)
		}
	}

	if len(links) == 0 {
		c.String(http.StatusOK, "No active accounts")
		return
	}

	subscription := strings.Join(links, "\n")
	encoded := base64.StdEncoding.EncodeToString([]byte(subscription))
	c.String(http.StatusOK, encoded)
}
