// 客户端 HTTP API — 全局跨节点管理、多入站关联、可见性控制。
package client

import (
	"database/sql"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/borderx/panel/internal/model"
	"github.com/borderx/panel/internal/xray"
)

// Handler holds dependencies for client management endpoints.
type Handler struct {
	DB   *sql.DB
	Xray *xray.Manager
}

// List returns all clients with their traffic totals and associated inbounds.
func (h *Handler) List(c *gin.Context) {
	rows, err := h.DB.Query(
		`SELECT id, name, uuid, flow, total_limit, expiry_at, is_active, created_at
		 FROM clients ORDER BY created_at DESC`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}
	defer rows.Close()

	clients := make([]model.Client, 0)
	for rows.Next() {
		var cl model.Client
		var expiry sql.NullString
		var isActive int
		if err := rows.Scan(&cl.ID, &cl.Name, &cl.UUID, &cl.Flow, &cl.TotalLimit, &expiry, &isActive, &cl.CreatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "读取客户端失败"})
			return
		}
		cl.IsActive = isActive == 1
		if expiry.Valid {
			cl.ExpiryAt = expiry.String
		}
		// Count total used traffic.
		var used int64
		h.DB.QueryRow("SELECT COALESCE(SUM(up_bytes+down_bytes),0) FROM traffic_hourly WHERE client_id=?", cl.ID).Scan(&used)
		cl.TotalUsed = used
		// Load associated inbounds.
		cl.Inbounds = loadClientInbounds(h.DB, cl.ID)
		clients = append(clients, cl)
	}

	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "遍历客户端失败"})
		return
	}

	c.JSON(http.StatusOK, clients)
}

// Create creates a client and optionally associates it with inbound IDs.
func (h *Handler) Create(c *gin.Context) {
	var req struct {
		Name       string   `json:"name"`
		TotalLimit int64    `json:"total_limit"`
		ExpiryAt   string   `json:"expiry_at"`
		InboundIDs []string `json:"inbound_ids"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}

	id := uuid.New().String()
	clientUUID := uuid.New().String()
	var expiryPtr *string
	if req.ExpiryAt != "" {
		expiryPtr = &req.ExpiryAt
	}

	_, err := h.DB.Exec(
		`INSERT INTO clients (id, name, uuid, total_limit, expiry_at) VALUES (?,?,?,?,?)`,
		id, req.Name, clientUUID, req.TotalLimit, expiryPtr,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败: " + err.Error()})
		return
	}

	// Associate with inbounds.
	for _, inboundID := range req.InboundIDs {
		h.DB.Exec("INSERT OR IGNORE INTO client_inbounds (client_id, inbound_id) VALUES (?,?)", id, inboundID)
	}

	// Sync to Xray on all associated nodes.
	h.syncToXray(id, clientUUID, "", req.InboundIDs)

	c.JSON(http.StatusCreated, gin.H{"id": id, "uuid": clientUUID})
}

// Update modifies client metadata.
func (h *Handler) Update(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		Name       *string `json:"name"`
		TotalLimit *int64  `json:"total_limit"`
		ExpiryAt   *string `json:"expiry_at"`
		IsActive   *bool   `json:"is_active"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}

	if req.Name != nil {
		h.DB.Exec("UPDATE clients SET name=? WHERE id=?", *req.Name, id)
	}
	if req.TotalLimit != nil {
		h.DB.Exec("UPDATE clients SET total_limit=? WHERE id=?", *req.TotalLimit, id)
	}
	if req.ExpiryAt != nil {
		if *req.ExpiryAt == "" {
			h.DB.Exec("UPDATE clients SET expiry_at=NULL WHERE id=?", id)
		} else {
			h.DB.Exec("UPDATE clients SET expiry_at=? WHERE id=?", *req.ExpiryAt, id)
		}
	}
	if req.IsActive != nil {
		a := 0
		if *req.IsActive {
			a = 1
		}
		h.DB.Exec("UPDATE clients SET is_active=? WHERE id=?", a, id)
	}

	c.JSON(http.StatusOK, gin.H{"message": "已更新"})
}

// Delete removes a client and its Xray entries from all associated inbounds.
func (h *Handler) Delete(c *gin.Context) {
	id := c.Param("id")

	var clientUUID string
	h.DB.QueryRow("SELECT uuid FROM clients WHERE id=?", id).Scan(&clientUUID)

	// Remove from Xray on all associated inbounds.
	h.removeFromXrayAll(id)

	h.DB.Exec("DELETE FROM client_inbounds WHERE client_id=?", id)
	h.DB.Exec("DELETE FROM clients WHERE id=?", id)

	c.JSON(http.StatusOK, gin.H{"message": "已删除"})
}

// Reset generates a new UUID for the client and syncs to Xray.
func (h *Handler) Reset(c *gin.Context) {
	id := c.Param("id")
	newUUID := uuid.New().String()

	h.DB.Exec("UPDATE clients SET uuid=? WHERE id=?", newUUID, id)

	inboundIDs := getClientInboundIDs(h.DB, id)
	h.syncToXray(id, newUUID, "", inboundIDs)

	c.JSON(http.StatusOK, gin.H{"uuid": newUUID})
}

// UpdateInbounds replaces the entire client_inbounds mapping for a client.
func (h *Handler) UpdateInbounds(c *gin.Context) {
	id := c.Param("id")
	var req []struct {
		InboundID string `json:"inbound_id"`
		IsVisible bool   `json:"is_visible"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}

	h.DB.Exec("DELETE FROM client_inbounds WHERE client_id=?", id)
	for _, ci := range req {
		vis := 0
		if ci.IsVisible {
			vis = 1
		}
		h.DB.Exec("INSERT OR IGNORE INTO client_inbounds (client_id, inbound_id, is_visible) VALUES (?,?,?)",
			id, ci.InboundID, vis)
	}

	// Full re-sync to Xray.
	var clientUUID string
	h.DB.QueryRow("SELECT uuid FROM clients WHERE id=?", id).Scan(&clientUUID)
	inboundIDs := make([]string, len(req))
	for i, ci := range req {
		inboundIDs[i] = ci.InboundID
	}
	h.syncToXray(id, clientUUID, "", inboundIDs)

	c.JSON(http.StatusOK, gin.H{"message": "已更新"})
}

// ---- internal helpers ----

func (h *Handler) syncToXray(clientID, clientUUID, password string, inboundIDs []string) {
	if h.Xray == nil {
		return
	}
	email := clientID + "@borderx"
	for _, inboundID := range inboundIDs {
		var tag, protocol string
		h.DB.QueryRow("SELECT tag, protocol FROM inbounds WHERE id=?", inboundID).Scan(&tag, &protocol)
		if tag != "" {
			h.Xray.AddClient(tag, protocol, email, clientUUID, password)
		}
	}
}

func (h *Handler) removeFromXrayAll(clientID string) {
	if h.Xray == nil {
		return
	}
	email := clientID + "@borderx"
	inboundIDs := getClientInboundIDs(h.DB, clientID)
	for _, inboundID := range inboundIDs {
		var tag string
		h.DB.QueryRow("SELECT tag FROM inbounds WHERE id=?", inboundID).Scan(&tag)
		if tag != "" {
			h.Xray.RemoveClient(tag, email)
		}
	}
}

func loadClientInbounds(db *sql.DB, clientID string) []model.ClientInbound {
	rows, err := db.Query(
		`SELECT ci.client_id, ci.inbound_id, ci.is_visible,
		        COALESCE(n.name,''), i.protocol, i.port, COALESCE(n.host,'')
		 FROM client_inbounds ci
		 JOIN inbounds i ON ci.inbound_id=i.id
		 JOIN nodes n ON i.node_id=n.id
		 WHERE ci.client_id=?`, clientID)
	if err != nil {
		return []model.ClientInbound{}
	}
	defer rows.Close()

	result := make([]model.ClientInbound, 0)
	for rows.Next() {
		var ci model.ClientInbound
		var vis int
		rows.Scan(&ci.ClientID, &ci.InboundID, &vis, &ci.NodeName, &ci.Protocol, &ci.Port, &ci.Host)
		ci.IsVisible = vis == 1
		result = append(result, ci)
	}
	return result
}

func getClientInboundIDs(db *sql.DB, clientID string) []string {
	rows, err := db.Query("SELECT inbound_id FROM client_inbounds WHERE client_id=?", clientID)
	if err != nil {
		return nil
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		rows.Scan(&id)
		ids = append(ids, id)
	}
	return ids
}
