// 节点 HTTP API — CRUD、SSH 连通性测试、运行状态查询。
package node

import (
	"database/sql"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/borderx/panel/internal/model"
)

// Handler handles HTTP requests for node management.
type Handler struct {
	DB  *sql.DB
	SSH *SSHManager
}

// List returns all nodes with computed inbound and client counts.
func (h *Handler) List(c *gin.Context) {
	rows, err := h.DB.Query(
		`SELECT n.id, n.name, n.host, n.ssh_port, n.ssh_user, n.os, n.region, n.is_active, n.last_seen_at, n.created_at,
		        (SELECT count(*) FROM inbounds WHERE node_id=n.id),
		        (SELECT count(DISTINCT ci.client_id) FROM client_inbounds ci JOIN inbounds i ON ci.inbound_id=i.id WHERE i.node_id=n.id)
		 FROM nodes n ORDER BY n.created_at DESC`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "查询失败"})
		return
	}
	defer rows.Close()

	nodes := []model.Node{}
	for rows.Next() {
		var n model.Node
		var isActive int
		var lastSeen, createdAt sql.NullString
		rows.Scan(&n.ID, &n.Name, &n.Host, &n.SSHPort, &n.SSHUser, &n.OS, &n.Region, &isActive, &lastSeen, &createdAt, &n.InboundCount, &n.ClientCount)
		n.IsActive = isActive == 1
		if lastSeen.Valid {
			n.LastSeenAt = lastSeen.String
		}
		if createdAt.Valid {
			n.CreatedAt = createdAt.String
		}
		n.Status = "unknown"
		nodes = append(nodes, n)
	}
	c.JSON(http.StatusOK, nodes)
}

// Get returns a single node by ID.
func (h *Handler) Get(c *gin.Context) {
	var n model.Node
	var isActive int
	var lastSeen, createdAt sql.NullString
	err := h.DB.QueryRow(
		`SELECT id, name, host, ssh_port, ssh_user, os, region, is_active, last_seen_at, created_at FROM nodes WHERE id=?`,
		c.Param("id"),
	).Scan(&n.ID, &n.Name, &n.Host, &n.SSHPort, &n.SSHUser, &n.OS, &n.Region, &isActive, &lastSeen, &createdAt)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "节点不存在"})
		return
	}
	n.IsActive = isActive == 1
	if lastSeen.Valid {
		n.LastSeenAt = lastSeen.String
	}
	if createdAt.Valid {
		n.CreatedAt = createdAt.String
	}
	c.JSON(http.StatusOK, n)
}

// Create inserts a new node and optionally registers its SSH key.
func (h *Handler) Create(c *gin.Context) {
	var req struct {
		Name    string `json:"name" binding:"required"`
		Host    string `json:"host" binding:"required"`
		SSHPort int    `json:"ssh_port"`
		SSHUser string `json:"ssh_user"`
		SSHKey  string `json:"ssh_key"`
		OS      string `json:"os"`
		Region  string `json:"region"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}
	if req.SSHPort == 0 {
		req.SSHPort = 22
	}
	if req.SSHUser == "" {
		req.SSHUser = "root"
	}
	if req.OS == "" {
		req.OS = "linux"
	}
	id := uuid.New().String()
	_, err := h.DB.Exec(
		`INSERT INTO nodes (id, name, host, ssh_port, ssh_user, ssh_key, os, region) VALUES (?,?,?,?,?,?,?,?)`,
		id, req.Name, req.Host, req.SSHPort, req.SSHUser, req.SSHKey, req.OS, req.Region,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "创建失败: " + err.Error()})
		return
	}
	// Register SSH key if provided
	if req.SSHKey != "" && h.SSH != nil {
		h.SSH.Register(id, req.SSHUser, req.SSHKey, req.SSHPort)
	}
	c.JSON(http.StatusCreated, gin.H{"id": id})
}

// Update modifies node fields. Only non-nil fields in the request are applied.
func (h *Handler) Update(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		Name    *string `json:"name"`
		Host    *string `json:"host"`
		SSHPort *int    `json:"ssh_port"`
		OS      *string `json:"os"`
		Region  *string `json:"region"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "参数错误"})
		return
	}
	if req.Name != nil {
		h.DB.Exec("UPDATE nodes SET name=? WHERE id=?", *req.Name, id)
	}
	if req.Host != nil {
		h.DB.Exec("UPDATE nodes SET host=? WHERE id=?", *req.Host, id)
	}
	if req.SSHPort != nil {
		h.DB.Exec("UPDATE nodes SET ssh_port=? WHERE id=?", *req.SSHPort, id)
	}
	if req.OS != nil {
		h.DB.Exec("UPDATE nodes SET os=? WHERE id=?", *req.OS, id)
	}
	if req.Region != nil {
		h.DB.Exec("UPDATE nodes SET region=? WHERE id=?", *req.Region, id)
	}
	c.JSON(http.StatusOK, gin.H{"message": "已更新"})
}

// Delete removes a node and closes its SSH connection.
func (h *Handler) Delete(c *gin.Context) {
	id := c.Param("id")
	if h.SSH != nil {
		h.SSH.Close(id)
	}
	h.DB.Exec("DELETE FROM nodes WHERE id=?", id)
	c.JSON(http.StatusOK, gin.H{"message": "已删除"})
}

// Test runs a connectivity check by executing "uname -a" on the node.
func (h *Handler) Test(c *gin.Context) {
	id := c.Param("id")
	if h.SSH == nil {
		c.JSON(http.StatusOK, gin.H{"success": false, "error": "SSH 模块未初始化"})
		return
	}
	var host, sshUser string
	var sshPort int
	err := h.DB.QueryRow("SELECT host, ssh_user, ssh_port FROM nodes WHERE id=?", id).Scan(&host, &sshUser, &sshPort)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "节点不存在"})
		return
	}
	if err := h.SSH.Connect(id, host, sshPort); err != nil {
		c.JSON(http.StatusOK, gin.H{"success": false, "error": err.Error()})
		return
	}
	out, err := h.SSH.Exec(id, "uname -a")
	h.DB.Exec("UPDATE nodes SET last_seen_at=datetime('now') WHERE id=?", id)

	// Auto-detect region via geo-IP on remote node
	regionOut, _ := h.SSH.Exec(id, "curl -s --connect-timeout 3 https://ipapi.co/json/ 2>/dev/null || curl -s --connect-timeout 3 https://ipinfo.io/json 2>/dev/null || echo '{}'")
	if regionOut != "" {
		country := extractJSONField(regionOut, "country")
		city := extractJSONField(regionOut, "city")
		if country != "" {
			region := country
			if city != "" {
				region = city + ", " + country
			}
			h.DB.Exec("UPDATE nodes SET region=? WHERE id=?", region, id)
		}
	}

	c.JSON(http.StatusOK, gin.H{"success": err == nil, "output": out})
}

// Status returns the current online/offline status of a node.
func (h *Handler) Status(c *gin.Context) {
	id := c.Param("id")
	var host, sshUser string
	var sshPort int
	var osName string
	h.DB.QueryRow("SELECT host, ssh_user, ssh_port, os FROM nodes WHERE id=?", id).
		Scan(&host, &sshUser, &sshPort, &osName)
	status := "unknown"
	if h.SSH != nil {
		if err := h.SSH.Connect(id, host, sshPort); err == nil {
			_, execErr := h.SSH.Exec(id, "uptime")
			if execErr == nil {
				status = "online"
				h.DB.Exec("UPDATE nodes SET last_seen_at=datetime('now') WHERE id=?", id)
			} else {
				status = "offline"
			}
		} else {
			status = "offline"
		}
	}
	c.JSON(http.StatusOK, gin.H{"status": status, "os": osName})
}

// extractJSONField does a simple substring-based extraction of a string field from a JSON object.
func extractJSONField(jsonStr, field string) string {
	key := `"` + field + `":"`
	for idx := 0; idx < len(jsonStr); idx++ {
		match := true
		for j := 0; j < len(key); j++ {
			if idx+j >= len(jsonStr) || jsonStr[idx+j] != key[j] {
				match = false
				break
			}
		}
		if match {
			start := idx + len(key)
			end := start
			for end < len(jsonStr) && jsonStr[end] != '"' {
				end++
			}
			return jsonStr[start:end]
		}
	}
	return ""
}
