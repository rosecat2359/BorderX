// V2Ray / Clash 订阅链接生成 — 按客户端聚合多节点代理条目。
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
	clientID := c.Query("client")
	if clientID == "" {
		c.String(http.StatusBadRequest, "missing client parameter")
		return
	}

	var clientUUID, flow string
	err := h.DB.QueryRow(
		"SELECT uuid, flow FROM clients WHERE id = ? AND is_active = 1",
		clientID,
	).Scan(&clientUUID, &flow)
	if err == sql.ErrNoRows {
		c.String(http.StatusNotFound, "client not found or inactive")
		return
	}
	if err != nil {
		c.String(http.StatusInternalServerError, "query failed")
		return
	}

	rows, err := h.DB.Query(
		`SELECT n.host, n.name, i.protocol, i.port, i.tag
		 FROM client_inbounds ci
		 JOIN inbounds i ON ci.inbound_id = i.id
		 JOIN nodes n ON i.node_id = n.id
		 WHERE ci.client_id = ? AND ci.is_visible = 1 AND i.is_active = 1 AND n.is_active = 1`,
		clientID,
	)
	if err != nil {
		c.String(http.StatusInternalServerError, "query failed")
		return
	}
	defer rows.Close()

	var links []string
	for rows.Next() {
		var host, nodeName, protocol, tag string
		var port int
		rows.Scan(&host, &nodeName, &protocol, &port, &tag)
		label := fmt.Sprintf("%s-%s", nodeName, tag)

		switch protocol {
		case "vless":
			link := fmt.Sprintf(
				"vless://%s@%s:%d?encryption=none&flow=%s&security=reality&type=tcp#%s",
				clientUUID, host, port, flow, label,
			)
			links = append(links, link)
		case "vmess":
			link := fmt.Sprintf(
				"vmess://%s@%s:%d?path=/ws&security=none&type=ws#%s",
				clientUUID, host, port, label,
			)
			links = append(links, link)
		case "trojan":
			var pw string
			h.DB.QueryRow("SELECT password FROM clients WHERE id = ?", clientID).Scan(&pw)
			link := fmt.Sprintf(
				"trojan://%s@%s:%d?security=tls&type=tcp#%s",
				pw, host, port, label,
			)
			links = append(links, link)
		}
	}

	if len(links) == 0 {
		c.String(http.StatusOK, "")
		return
	}

	subscription := strings.Join(links, "\n")
	encoded := base64.StdEncoding.EncodeToString([]byte(subscription))
	c.String(http.StatusOK, encoded)
}
