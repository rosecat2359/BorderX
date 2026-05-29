package inbound

import (
	"database/sql"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/borderx/panel/internal/model"
	"github.com/borderx/panel/internal/xray"
)

// Handler exposes CRUD endpoints for inbounds plus local deployment.
type Handler struct {
	DB   *sql.DB
	Xray *xray.Manager
}

// List returns all inbounds, optionally filtered by node_id.
func (h *Handler) List(c *gin.Context) {
	nodeID := c.Query("node_id")
	query := `SELECT i.id, i.node_id, i.tag, i.protocol, i.port, i.listen, i.sniffing, i.is_active, i.created_at,
	           COALESCE(n.name,''), (SELECT count(*) FROM client_inbounds WHERE inbound_id=i.id)
	           FROM inbounds i LEFT JOIN nodes n ON i.node_id=n.id`
	args := []any{}
	if nodeID != "" {
		query += " WHERE i.node_id = ?"
		args = append(args, nodeID)
	}
	query += " ORDER BY i.created_at DESC"
	rows, err := h.DB.Query(query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}
	defer rows.Close()
	inbounds := []model.Inbound{}
	for rows.Next() {
		var in model.Inbound
		var sniffing int
		var isActive int
		rows.Scan(&in.ID, &in.NodeID, &in.Tag, &in.Protocol, &in.Port, &in.Listen, &sniffing, &isActive, &in.CreatedAt, &in.NodeName, &in.ClientCount)
		in.Sniffing = sniffing == 1
		in.IsActive = isActive == 1
		inbounds = append(inbounds, in)
	}
	c.JSON(http.StatusOK, inbounds)
}

// Create persists a new inbound and optionally deploys it locally.
func (h *Handler) Create(c *gin.Context) {
	var req struct {
		NodeID   string `json:"node_id" binding:"required"`
		Protocol string `json:"protocol" binding:"required"`
		Port     int    `json:"port" binding:"required"`
		Tag      string `json:"tag"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}
	if req.Tag == "" {
		req.Tag = req.Protocol + "-" + uuid.New().String()[:6]
	}
	id := uuid.New().String()
	settingsJSON, streamJSON := GenerateSettings(req.Protocol)
	// Generate Reality keys if vless
	if req.Protocol == "vless" {
		priv, _, shortID := GenerateRealityKeys()
		streamJSON = ReplacePlaceholders(streamJSON, priv, shortID)
	}
	_, err := h.DB.Exec(
		`INSERT INTO inbounds (id, node_id, tag, protocol, port, settings, stream) VALUES (?,?,?,?,?,?,?)`,
		id, req.NodeID, req.Tag, req.Protocol, req.Port, settingsJSON, streamJSON,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败: " + err.Error()})
		return
	}
	// Deploy to local Xray immediately
	if h.Xray != nil {
		h.Xray.EnsureInbound(req.Tag, req.Protocol, req.Port, settingsJSON, streamJSON)
	}
	c.JSON(http.StatusCreated, gin.H{"id": id, "tag": req.Tag})
}

// Update modifies mutable fields (port, sniffing, is_active) for a single inbound.
func (h *Handler) Update(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		Port     *int  `json:"port"`
		Sniffing *bool `json:"sniffing"`
		IsActive *bool `json:"is_active"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}
	if req.Port != nil {
		h.DB.Exec("UPDATE inbounds SET port=? WHERE id=?", *req.Port, id)
	}
	if req.Sniffing != nil {
		s := 0
		if *req.Sniffing {
			s = 1
		}
		h.DB.Exec("UPDATE inbounds SET sniffing=? WHERE id=?", s, id)
	}
	if req.IsActive != nil {
		a := 0
		if *req.IsActive {
			a = 1
		}
		h.DB.Exec("UPDATE inbounds SET is_active=? WHERE id=?", a, id)
	}
	c.JSON(http.StatusOK, gin.H{"message": "已更新"})
}

// Delete removes the inbound from the database and Xray config.
func (h *Handler) Delete(c *gin.Context) {
	id := c.Param("id")
	var tag string
	h.DB.QueryRow("SELECT tag FROM inbounds WHERE id=?", id).Scan(&tag)
	if h.Xray != nil && tag != "" {
		h.Xray.RemoveInbound(tag)
	}
	h.DB.Exec("DELETE FROM inbounds WHERE id=?", id)
	c.JSON(http.StatusOK, gin.H{"message": "已删除"})
}

// Deploy pushes an existing inbound to the local Xray config.
func (h *Handler) Deploy(c *gin.Context) {
	id := c.Param("id")
	var nodeID, tag, protocol string
	var port int
	var settings, stream string
	err := h.DB.QueryRow("SELECT node_id, tag, protocol, port, settings, stream FROM inbounds WHERE id=?", id).
		Scan(&nodeID, &tag, &protocol, &port, &settings, &stream)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "入站不存在"})
		return
	}
	if h.Xray == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Xray 管理模块未初始化"})
		return
	}
	if err := h.Xray.EnsureInbound(tag, protocol, port, settings, stream); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "部署失败: " + err.Error()})
		return
	}
	_ = nodeID
	c.JSON(http.StatusOK, gin.H{"message": "已部署到 " + tag})
}

// Templates returns the built-in inbound preset list.
func (h *Handler) Templates(c *gin.Context) {
	c.JSON(http.StatusOK, GetTemplates())
}
