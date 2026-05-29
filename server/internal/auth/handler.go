package auth

import (
	"database/sql"
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

type Handler struct {
	DB  *sql.DB
	JWT *JWTManager
}

// SetupCheck checks if admin needs initialization
func (h *Handler) SetupCheck(c *gin.Context) {
	var count int
	h.DB.QueryRow("SELECT count(*) FROM admin").Scan(&count)
	c.JSON(http.StatusOK, gin.H{"need_setup": count == 0})
}

// Setup initializes the admin password (first-time)
func (h *Handler) Setup(c *gin.Context) {
	var req struct {
		Password string `json:"password" binding:"required,min=6,max=64"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "密码至少 6 位"})
		return
	}
	var count int
	h.DB.QueryRow("SELECT count(*) FROM admin").Scan(&count)
	if count > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "已初始化，请登录"})
		return
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), 12)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "服务器错误"})
		return
	}
	h.DB.Exec("INSERT INTO admin (username, password) VALUES ('admin', ?)", string(hash))
	token, _ := h.JWT.GenerateToken("1")
	c.JSON(http.StatusCreated, gin.H{"token": token, "username": "admin"})
}

// Login authenticates the admin
func (h *Handler) Login(c *gin.Context) {
	var req struct {
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请输入密码"})
		return
	}
	var adminID int64
	var passwordHash string
	err := h.DB.QueryRow("SELECT id, password FROM admin WHERE username = 'admin'").Scan(&adminID, &passwordHash)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "系统未初始化"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "服务器错误"})
		return
	}
	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "密码错误"})
		return
	}
	token, _ := h.JWT.GenerateToken(fmt.Sprintf("%d", adminID))
	c.JSON(http.StatusOK, gin.H{"token": token, "username": "admin"})
}
